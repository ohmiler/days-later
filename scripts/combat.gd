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
	var wid := p.held_weapon() if kind == Look.SWING else ""
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
	var it = p.inv[p.sel]
	if it == null:
		return
	it.hp -= 1
	if it.hp <= 0:
		p.inv[p.sel] = null
		main.fx_sound.rpc("break", p.position)
		main._make_noise(p.position, main.NOISE_BREAK)
		main._toast(p, "%s หัก!" % Items.display_name(it.id))
	main.inventory._send_inv(p)


## Guns come back later as loot; kept here for that milestone.
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
		p.play_attack(kind)
		if p.is_local:
			main.ui.tutorial("kick" if kind == Look.KICK else "attack")
		Sfx.play(main, "swing" if kind in [Look.SWING, Look.KICK] else "punch", p.position, -4.0)


@rpc("authority", "call_local", "unreliable")
func fx_hit(zid: int, pos: Vector2, dir: Vector2, strong: bool, attacker: int, weapon_kind := "", dmg := 0.0) -> void:
	if dmg > 0:
		main.dmg_numbers.append([pos + Vector2(randf_range(-4, 4), -30), str(int(dmg)), dmg >= 30, 0.0])
	var z: Zombie = main.zombies.get(zid)
	if z:
		z.flinch(dir)
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
