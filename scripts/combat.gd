class_name Combat
extends Node
## Hitting things and what happens when they die: punches, kicks, weapons, wear, kills, severed limbs.
## Split out of main.gd; shared state (world, players, zombies, pickups) lives there.

var main: Main


const GUN_RANGE := 250.0
const GUN_DAMAGE := 34.0
const GUN_COOLDOWN := 0.25
const PUNCH := [18.0, 12.0, 0.35, 0.35, 2.5]
const KICK := [20.0, 22.0, 0.8, 0.7, 16.0]
const MELEE_SLACK := 3.0  # extra reach so a blow that looks like it lands, lands
const PUNCH_WINDUP := 0.08  # the hit lands when the fist is out, not on the click
const KICK_WINDUP := 0.18  # matches the foot snapping out in Look.kick_pose

const SEVER_CHANCE := 0.2  # a blade hit that does not kill takes an arm this often
const COMBO_RESET := 0.9  # after this long without a blow, the next one starts the 1-2 again


## The next blow from `p`'s hands: {hand, kind, stats, windup}. Swings alternate
## between the hands (a two-handed weapon uses both every time), starting from
## the right again after a pause. The server acts on it; the local player's
## client also uses it to show the swing the moment they click.
static func next_swing(p: Player) -> Dictionary:
	var hand := p.next_hand if p.anim_t < COMBO_RESET else "r"
	if Items.two_handed(p.hand_weapon("r")):
		hand = "r"
	var wid := p.hand_weapon(hand)
	if wid == "":
		return {hand = hand, kind = Look.PUNCH_R if hand == "r" else Look.PUNCH_L, stats = PUNCH, windup = PUNCH_WINDUP}
	var w := Items.def(wid)
	if Items.is_gun(wid):  # not aiming: a blow with it
		w = {range = 17.0, dmg = w.bash, cd = 0.55, stun = 0.35, knock = 6.0, dur = 0.3}
	var dual: bool = p.hand_weapon("r") != "" and p.hand_weapon("l") != ""
	var dmg: float = w.dmg * (Items.OFF_HAND if hand == "l" else 1.0)
	return {hand = hand, kind = Look.SWING if hand == "r" else Look.SWING_L,
			stats = [w.range, dmg, w.cd * (Items.DUAL_SPEED if dual else 1.0), w.stun, w.knock], windup = w.dur * 0.45}
## Punch hits the closest zombie in front; a kick hits everything in front.
func _melee(p: Player, kind: int, stats: Array, windup := -1.0) -> void:
	p.shoot_cd = stats[2]
	p.search_id = -1  # swinging interrupts a search
	fx_melee.rpc(p.peer_id, kind)
	main._make_noise(p.position, main.NOISE_SWING * (0.6 if p.sneak else 1.0))
	p.pending_kind = kind
	p.pending_stats = stats
	if windup < 0:
		windup = KICK_WINDUP if kind == Look.KICK else PUNCH_WINDUP
	p.pending_t = windup


## Punch hits the zombie in front that is closest to the aim; a kick hits
## everything in front. Generous cone so a blow that looks like it lands, lands.
func _resolve_melee(p: Player, kind: int, stats: Array) -> void:
	if not p.alive() or p.on_roof:
		return
	# Reach is measured to the edge of the body, not its middle.
	var reach: float = stats[0] + Zombie.RADIUS + MELEE_SLACK
	var dir := p.aim.normalized()
	# The cursor is where the player clicked on screen. If it is on a zombie's
	# drawn body (head to feet), that is the one they meant, whichever part they hit.
	var cursor := p.position + Look.CHEST + p.aim
	var picked: Zombie = null
	var hits: Array = []
	for z: Zombie in main.zombies.values():
		var v := z.position - p.position
		if v.length() > reach:
			continue
		if Rect2(z.position + Vector2(-8, -31), Vector2(16, 35)).has_point(cursor):
			if picked == null or v.length() < (picked.position - p.position).length():
				picked = z
		# In front of you, or so close it is pressed against you.
		var facing := v.normalized().dot(dir)
		if facing > 0.3 or (v.length() < 12.0 and facing > -0.3):
			hits.append(z)
	if picked:
		dir = (picked.position - p.position).normalized()
		if not hits.has(picked):
			hits.append(picked)
	if hits.is_empty():
		return
	var wid := p.hand_weapon(p.swing_hand) if kind in [Look.SWING, Look.SWING_L] else ""
	var cleave: bool = kind == Look.KICK or Items.def(wid).get("cleave", false)
	if cleave:
		hits = hits.filter(func(z): return z == picked or (z.position - p.position).normalized().dot(dir) > 0.0 or z.position.distance_to(p.position) < 12.0)
	elif picked:
		hits = [picked]
	else:
		hits.sort_custom(func(a, b): return (a.position - p.position).normalized().dot(dir) > (b.position - p.position).normalized().dot(dir))
		hits = [hits[0]]
	var how: String = Items.def(wid).get("draw", {}).get("kind", "")
	if how == "":
		how = "kick" if kind == Look.KICK else "punch"
	for z: Zombie in hits:
		z.hp -= stats[1]
		z.stun = stats[3]
		z.position = main.world.slide(z.position, dir * stats[4], Zombie.RADIUS)
		fx_hit.rpc(z.zid, z.position, dir, kind == Look.KICK, p.peer_id, Items.def(wid).get("draw", {}).get("kind", ""), stats[1])
		main._make_noise(z.position, main.NOISE_HIT)
		if z.hp <= 0:
			_kill_zombie(z, 1.0 if dir.x >= 0 else -1.0, how)
			p.kills += 1
			continue
		# A good kick can put it on the ground (not the fat ones); a blade can take an arm.
		if kind == Look.KICK and z.kind != "fat" and randf() < (0.5 if z.kind == "runner" else 0.3):
			z.knock_down()
		elif Items.has_tag(how, "sever") and randf() < SEVER_CHANCE:
			var bit := z.arm_left_to_cut()
			if bit > 0:
				z.missing |= bit
				fx_sever.rpc(z.zid, bit, dir)
	if wid != "":
		_wear_weapon(p)


## How a zombie dies depends on what killed it (see Corpse for what each style looks like).
static func death_style(how: String) -> String:
	# A weapon's `death` in data/items.cfg: style -> chance.
	var r := randf()
	var styles: Dictionary = Items.def(how).get("death", {})
	for style in styles:
		r -= styles[style]
		if r < 0.0:
			return style
	if not styles.is_empty():
		return styles.keys()[-1]
	match how:
		"gun":
			return "burst"
		"stomp":
			return "crush"
	return "fall"


func _kill_zombie(z: Zombie, fall_dir: float, how := "") -> void:
	fx_death.rpc(z.position, fall_dir, z.body_look(), death_style(how))
	# What it wore can be taken off the body: always what a turned survivor had
	# on, sometimes an ordinary zombie's (often worn half through).
	var i := 0
	for slot in z.wear:
		var id: String = z.wear[slot]
		var full: int = Items.def(id).get("hp", 1)
		if not z.outfit.is_empty() or randf() < 0.35:
			var hp := full if not z.outfit.is_empty() else maxi(1, int(full * randf_range(0.3, 0.8)))
			main._spawn_pickup(z.position + Vector2.from_angle(i * 1.3) * 7, {id = id, n = 1, hp = hp})
		i += 1
	main.zombies.erase(z.zid)
	z.queue_free()


## Each hit wears the weapon down; at zero it breaks.
func _wear_weapon(p: Player) -> void:
	var slot := "hand_" + p.swing_hand
	var it = p.worn.get(slot)
	if it == null:
		return
	it.hp -= 1
	if it.hp <= 0:
		p.worn.erase(slot)
		p.refresh_wear()
		main.fx_sound.rpc("break", p.position)
		main._make_noise(p.position, main.NOISE_BREAK)
		main._toast(p, "%s หัก!" % Items.display_name(it.id))
	main.inventory._send_inv(p)


## A shot from the gun in `hand`: each pellet flies along the aim, spread by
## how steady you are, stops at the first wall or zombie. Loud enough to bring
## the street. Worn guns jam; an empty one clicks.
## How wide a gun's shots can fall (radians, each side): walking, a gun in one
## hand with something in the other, a wounded arm all shake it. The aim guide
## draws the same cone.
## Where a shot along `dir` first meets a body standing at `feet`, or -1.
## The body is the whole drawn figure, feet to head (not just its middle), so
## a shot at the head or the legs lands.
const BODY_W := 8.0
static func body_hit(from: Vector2, dir: Vector2, feet: Vector2) -> float:
	var best := -1.0
	for y in [-3.0, -9.0, -15.0, -21.0, -27.0]:
		var c := feet + Vector2(0, y)
		var t := (c - from).dot(dir)
		if t > 0 and (from + dir * t).distance_to(c) < BODY_W and (best < 0 or t < best):
			best = t
	return best


## Aim help: with the cursor on a zombie's figure, aim at its middle.
static func snap_aim(from: Vector2, mouse: Vector2, zombies: Array) -> Vector2:
	var best := mouse
	var best_d := 1e9
	for z in zombies:
		var d: Vector2 = mouse - z.position
		if absf(d.x) < 12.0 and d.y > -32.0 and d.y < 4.0 and d.length() < best_d:
			best_d = d.length()
			best = z.position + Vector2(0, -14)
	return best - from


static func spread_of(p: Player, hand: String, moving: bool) -> float:
	var gun = p.worn.get("hand_" + hand)
	if gun == null:
		return 0.0
	var spread: float = deg_to_rad(Items.def(gun.id).get("spread", 3.0))
	if Items.def(gun.id).get("pellets", 1) <= 1:
		spread *= 0.25  # a steady single shot goes where you point it
	if moving:
		spread *= 1.8
	if not Items.two_handed(gun.id) and p.worn.get("hand_" + ("l" if hand == "r" else "r")) != null:
		spread *= 1.5
	if p.wounds.any(func(w): return w.part in ["arms", "hands"] and not w.bandaged):
		spread *= 1.5
	return spread


func fire(p: Player, hand: String) -> void:
	var slot := "hand_" + hand
	var gun = p.worn.get(slot)
	if gun == null or p.aim == Vector2.ZERO:
		return
	var d := Items.def(gun.id)
	p.shoot_cd = d.cd
	if p.craft.get("kind", "") == "reload":
		return  # hands busy
	if gun.get("ammo", 0) <= 0:
		p.shoot_cd = 0.4
		fx_sound_at.rpc("gun_click", p.position)
		main._toast(p, "กระสุนหมด · กด R บรรจุ")
		return
	if gun.hp < d.hp * 0.25 and randf() < 0.12:
		fx_sound_at.rpc("gun_click", p.position)
		main._toast(p, "ปืนติด! · ซ่อมด้วยเศษเหล็ก")
		return
	gun.ammo -= 1
	gun.hp -= 1
	var spread := spread_of(p, hand, p.move.length() > 0.1)
	# The gun is where you're drawn: on a roof, lifted above your feet (aim is measured from there too).
	var from := p.position + Look.CHEST + Vector2(0, -(main.world.roof_height(p.position) if p.on_roof else 0.0))
	var base := p.aim.normalized()
	var ends := []
	var hit_any := false
	for i in int(d.pellets):
		var dir := base.rotated(randf_range(-spread, spread))
		var length: float = d.range if p.on_roof else main.world.ray_length(from, dir, d.range)  # (from a roof you shoot over the street)
		var hit: Zombie = null
		for z: Zombie in main.zombies.values():
			if p.on_roof and main.world.building_at.has(main.world.to_cell(z.position)):
				continue  # indoors, under the roof: out of sight
			var t := body_hit(from, dir, z.position)
			if t > 0 and t < length:
				length = t
				hit = z
		ends.append(from + dir * length)
		if hit:
			hit_any = true
			var dmg: float = d.dmg * (1.0 if length < d.range * 0.5 else 0.6)  # (pellets lose their bite far out)
			hit.hp -= dmg
			hit.stun = maxf(hit.stun, 0.25)
			hit.position = main.world.slide(hit.position, dir * 3.0, Zombie.RADIUS)
			fx_hit.rpc(hit.zid, hit.position, dir, true, p.peer_id, "", dmg)
			if hit.hp <= 0 and main.zombies.has(hit.zid):
				_kill_zombie(hit, 1.0 if dir.x >= 0 else -1.0, "gun")
				p.kills += 1
	fx_shots.rpc(from, ends, gun.id, p.peer_id)
	main._make_noise(p.position, d.noise)
	if gun.hp <= 0:
		p.worn.erase(slot)
		p.refresh_wear()
		main._toast(p, "%s พังแล้ว" % Items.display_name(gun.id))
	main.inventory._send_inv(p)


@rpc("authority", "call_local", "unreliable")
func fx_shots(from: Vector2, ends: Array, gun: String, peer := 0) -> void:
	main.tracers.append([from, ends[0], 0.07, peer])  # (just the flash at the muzzle; no bullet line)
	Sfx.play(main, "shotgun" if gun == "shotgun" else "gunshot", from, 2.0)
	var me: Player = main.players.get(multiplayer.get_unique_id())
	if me and me.position.distance_to(from) < 300.0:
		main.shake = maxf(main.shake, 3.0 if gun == "shotgun" else 1.8)


@rpc("authority", "call_local", "unreliable")
func fx_sound_at(name: String, pos: Vector2) -> void:
	Sfx.play(main, name, pos)


## Old single-shot fire, kept for reference until guns settle.
func _fire(p: Player) -> void:
	if p.aim == Vector2.ZERO:
		return
	p.shoot_cd = GUN_COOLDOWN
	var dir := p.aim.normalized()
	var from := p.position
	var length := main.world.ray_length(from, dir, GUN_RANGE)
	var hit: Zombie = null
	for z: Zombie in main.zombies.values():
		var t := (z.position - from).dot(dir)
		if t > 0 and t < length and (from + dir * t).distance_to(z.position) < Zombie.RADIUS + 2:
			length = t
			hit = z
	if hit:
		hit.hp -= GUN_DAMAGE
		if hit.hp <= 0:
			fx_death.rpc(hit.position, 1.0 if dir.x >= 0 else -1.0, hit.body_look(), death_style("gun"))
			main.zombies.erase(hit.zid)
			hit.queue_free()
			p.kills += 1
	fx_shot.rpc(from, from + dir * length, hit != null)


@rpc("authority", "call_local", "unreliable")
func fx_shot(from: Vector2, to: Vector2, hit: bool) -> void:
	main.tracers.append([from, to, 0.08])
	if hit:
		var dir := (to - from).normalized()
		for i in 3:
			var p := to + dir * randf_range(0, 9) + Vector2(randf_range(-3, 3), randf_range(-3, 3))
			main.blood.append([p, randf_range(0.8, 2.6), Color(randf_range(0.35, 0.5), 0.02, 0.02, 0.85)])
		if main.blood.size() > 600:
			main.blood = main.blood.slice(main.blood.size() - 600)
	main.decals.queue_redraw()


@rpc("authority", "call_local", "unreliable")
func fx_melee(peer_id: int, kind: int) -> void:
	var p: Player = main.players.get(peer_id)
	if p:
		if p.is_local:
			main.ui.tutorial("kick" if kind == Look.KICK else "attack")
			if p.predicted > 0:
				p.predicted -= 1  # already shown when the button was pressed (see show_swing)
				return
		show_swing(p, kind)


## The swing's animation and sound.
func show_swing(p: Player, kind: int) -> void:
	p.play_attack(kind)
	Sfx.play(main, "swing" if kind in [Look.SWING, Look.SWING_L, Look.KICK] else "punch", p.position, -4.0)


const HITSTOP := 0.05


## Client, local player: swing the moment the button is pressed rather than a
## round trip later, guessing the cooldown the server keeps. The server still
## decides what the blow hits; its word on the swing is then not shown twice.
func predict(me: Player, delta: float) -> void:
	me.local_cd -= delta
	me.punch_buf -= delta
	me.kick_buf -= delta
	if me.anim_t > 1.0:
		me.predicted = 0  # nothing came back for a while: stop waiting on it
	if not me.alive() or me.riding >= 0 or me.sleeping or me.local_cd > 0.0 or me.aiming:
		return
	if me.wants_kick():
		me.kick_buf = 0.0
		me.local_cd = KICK[2]
		me.predicted += 1
		show_swing(me, Look.KICK)
	elif me.wants_punch():
		me.punch_buf = 0.0
		var sw := next_swing(me)
		me.next_hand = "l" if sw.hand == "r" else "r"
		me.local_cd = sw.stats[2]
		me.predicted += 1
		show_swing(me, sw.kind)


@rpc("authority", "call_local", "unreliable")
func fx_hit(zid: int, pos: Vector2, dir: Vector2, strong: bool, attacker: int, weapon_kind := "", dmg := 0.0) -> void:
	if dmg > 0:
		main.dmg_numbers.append([pos + Vector2(randf_range(-4, 4), -30), str(int(dmg)), dmg >= 30, 0.0])
	var z: Zombie = main.zombies.get(zid)
	if z:
		z.flinch(dir)
	var who: Player = main.players.get(attacker)
	if who and who.anim_t < 0.4:
		who.hitstop = HITSTOP  # the blow lands: a beat of stillness sells its weight
	main.sparks.append([pos + Look.CHEST - dir * 3.0, 0.14, strong])
	for i in 4 if strong else 2:
		main.blood.append([pos + dir * randf_range(2, 8) + Vector2(randf_range(-3, 3), randf_range(-2, 2)),
				randf_range(0.8, 2.2), Color(randf_range(0.35, 0.5), 0.02, 0.02, 0.85)])
	main.decals.queue_redraw()
	var blade := Items.has_tag(weapon_kind, "blade")
	Sfx.play(main, "blade" if blade else ("kick" if strong else "hit"), pos)
	if attacker == multiplayer.get_unique_id():
		main.shake = maxf(main.shake, 2.2 if strong or weapon_kind != "" else 1.3)


@rpc("authority", "call_local", "reliable")
func fx_death(pos: Vector2, fall_dir: float, body: Dictionary, style: String) -> void:
	main.leave_corpse(pos, fall_dir, body, true, 0.0, style)
	if style in ["behead", "arm", "burst"]:
		Sfx.play(main, "gore", pos, 2.0)
	elif style == "crush":
		Sfx.play(main, "crunch", pos, 1.0)


## A blade took an arm off a zombie that is still coming.
@rpc("authority", "call_local", "reliable")
func fx_sever(zid: int, bit: int, dir: Vector2) -> void:
	var z: Zombie = main.zombies.get(zid)
	if z == null:
		return
	z.missing |= bit
	Sfx.play(main, "gore", z.position, 1.0, 1.1)
	if Look.low_gore:
		return
	var g := Gib.new()
	g.kind = "arm"
	g.lk = z.body_look()
	g.position = z.position + Vector2(0, 1)
	g.h = 16.0
	g.vel = Vector2(dir.x, dir.y * 0.6) * 45.0
	g.vh = 50.0
	g.spin = randf_range(7.0, 12.0)
	g.flip = dir.x < 0
	g.z_index = 1
	main.add_gib(g)
	main.splatter(z.position, dir, 5)
