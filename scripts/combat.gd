class_name Combat
extends Node
## Hitting things and what happens when they die: punches, kicks, weapons, wear, kills, severed limbs.
## Split out of main.gd; shared state (world, players, zombies, pickups) lives there.

var main: Main


const PUNCH := [18.0, 12.0, 0.35, 0.35, 2.5]
const KICK := [20.0, 22.0, 0.8, 0.7, 8.0]  # (knock: half a cell, a stagger back, not a shove across the street)
const MELEE_SLACK := 3.0
## Where a blow or a shot lands on a zombie, by how high on its drawn body
## (feet at 0, the top of the head at -31): head, body or legs. What you hit
## with and where decides the damage and how it dies (death_style).
const HEAD_Y := -23.0  # above this: the head (today's body: see Proportions.head_line)
const LEGS_Y := -9.0  # below this: the legs (see Proportions.legs_line)
const ZONE_DMG := {head = 1.8, body = 1.0, legs = 0.7}
const GUN_HEAD := 2.0  # a shot to the head (instead of ZONE_DMG.head)
const LEG_KNOCK := 0.35  # a blunt blow to the legs: the chance it goes down
const KILL_STOP := 0.12  # the killing blow holds a little longer (HITSTOP)
const LEG_SEVER := 0.4  # a blade to the legs: the chance it takes one off (it crawls)
## Creeping up (sneaking) behind a zombie that isn't after you, a point in the
## back of the head: dead at once, and not a sound. Behind = its back to you
## this much (the cos of the angle between where it faces and where you are).
const BACKSTAB := -0.1
const STAB_TIME := 0.8  # the silent kill, played out: a hand over its mouth, the blade in, lowered down
const STAB_GAP := 9.0  # how far behind it you end up standing
## Deaths that go down toward whoever did it, not away.
const FORWARD := ["slump", "kneel"]
## Deaths that end face down (the rest on their backs).
const FACE_DOWN := ["slump", "kneel", "held"]  # extra reach so a blow that looks like it lands, lands
const PUNCH_WINDUP := 0.08  # the hit lands when the fist is out, not on the click
const KICK_WINDUP := 0.18  # matches the foot snapping out in Look.kick_pose

## Fighting tires you: each blow costs stamina (a kick more than a punch, a
## heavy weapon more than a light one), and you get none back for a moment
## after. Worn out (below TIRED), blows come slower and land softer.
const PUNCH_COST := 4.0
const KICK_COST := 8.0
const SWING_COST := 3.0  # a weapon: this, plus WEIGHT_COST a kilogram
const WEIGHT_COST := 2.2
const EXERT_PAUSE := 1.0  # seconds after a blow before your breath starts coming back
const TIRED := 20.0
const TIRED_SLOW := 1.35
const TIRED_WEAK := 0.8

const SEVER_CHANCE := 0.2  # a blade hit that does not kill takes an arm this often
const COMBO_RESET := 0.9  # after this long without a blow, the next one starts the 1-2 again


## Throwing (T): a bottle, a can, a lump of scrap, overarm toward the cursor.
## It flies THROW_RANGE at most, stops at a wall, and lands with a noise that
## draws zombies that haven't seen you to where it fell: glass shatters (loud,
## and gone), anything else clatters and can be picked up again. One landing
## on a zombie knocks it back a step.
const THROW_RANGE := 170.0
const THROW_COST := 3.0
const THROW_CD := 0.6
const THROW_NOISE := 150.0  # a can or scrap clattering down
const SHATTER_NOISE := 200.0  # a bottle smashing: louder than a window
var throws: Array = []  # server: [{at, t, id, item, storey, from_roof}], still in the air


## Which bag slot T throws from: the selected one if it can be thrown, else
## the first thing in the bag that can. -1 if nothing can.
static func throw_slot(p: Player) -> int:
	var sel = p.inv[p.sel] if p.sel < p.inv.size() else null
	if sel != null and Items.has_tag(sel.id, "throw"):
		return p.sel
	for i in p.inv.size():
		if p.inv[i] != null and Items.has_tag(p.inv[i].id, "throw"):
			return i
	return -1


@rpc("any_peer", "call_remote", "reliable")
func req_throw() -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.shoot_cd > 0.0 or p.sleeping or p.sitting != -1 or (p.riding >= 0 and p.seat == 0) or p.grabbed_by >= 0:
		return
	var slot := throw_slot(p)
	if slot < 0:
		main._toast(p, "ไม่มีของให้ขว้าง (ขวด กระป๋อง เศษเหล็ก)")
		return
	var it: Dictionary = p.inv[slot]
	var one := it.duplicate()
	one.n = 1
	it.n -= 1
	if it.n <= 0:
		p.inv[slot] = null
	main.inventory._send_inv(p)
	p.shoot_cd = THROW_CD
	p.stamina = maxf(0.0, p.stamina - THROW_COST)
	p.exert_t = EXERT_PAUSE
	# Toward the cursor; right at a zombie if the cursor is on one.
	var w: World = main.world
	var want := p.aim
	var cursor := p.position + Look.CHEST + p.aim
	for z: Zombie in main.zombies.values():
		if z.storey == p.storey and Rect2(z.position + Vector2(-8, -31), Vector2(16, 35)).has_point(cursor):
			want = z.position - p.position
	var dir := want.normalized() if want.length() > 0.5 else Vector2.RIGHT
	var dist := minf(want.length(), THROW_RANGE)
	if not p.on_roof:
		var clear := w.ray_length(p.position, dir, dist)
		if clear < dist:
			dist = maxf(0.0, clear - 4.0)  # (a wall stops it, and it drops at its foot)
	var at := p.position + dir * dist
	var time := 0.25 + dist / 450.0
	throws.append({at = at, t = time, id = one.id, item = one, storey = 0 if p.on_roof else p.storey, from_roof = p.on_roof})
	fx_throw.rpc(p.peer_id, p.position, at, time, one.id, p.on_roof, p.storey)
	main._make_noise(p.position, main.NOISE_WALK)


## Server, every tick: things in the air come down.
func tick_throws(delta: float) -> void:
	for th in throws.duplicate():
		th.t -= delta
		if th.t > 0.0:
			continue
		throws.erase(th)
		var at: Vector2 = th.at
		var glass := Items.has_tag(th.id, "glass")
		for z: Zombie in main.zombies.values():
			if z.storey == th.storey and z.position.distance_to(at) < Zombie.RADIUS + 4.0:
				var dir := (z.position - at).normalized() if z.position.distance_to(at) > 0.1 else Vector2.RIGHT
				z.hp -= 4.0
				z.stun = 0.4
				fx_hit.rpc(z.zid, z.position, dir, false, 0, "", 4.0)
				if z.hp <= 0:
					_kill_zombie(z, 1.0 if dir.x >= 0 else -1.0)
				break
		main._make_noise(at, SHATTER_NOISE if glass else THROW_NOISE)
		fx_landed.rpc(at, glass, th.storey)
		var w: World = main.world
		var on_roof: bool = th.from_roof and w.is_roof(w.to_cell(at))
		if not glass and not on_roof:
			main._spawn_pickup(at, th.item, th.storey)


@rpc("authority", "call_local", "reliable")
func fx_throw(peer_id: int, from: Vector2, to: Vector2, time: float, id: String, from_roof: bool, storey: int) -> void:
	var p: Player = main.players.get(peer_id)
	if p:
		p.play_attack(Look.PUNCH_R)  # (overarm: the throwing arm comes through like a punch)
	var th := Thrown.new()
	th.from = from
	th.to = to
	th.time = time
	th.id = id
	th.lift = (p.lift if p else 0.0) if from_roof else BuildingProp.storey_lift(storey)
	var w: World = main.world
	th.land_lift = w.roof_height(to) if from_roof and w.is_roof(w.to_cell(to)) else BuildingProp.storey_lift(storey)
	main.add_child(th)
	Sfx.play(main, "punch", from, -8.0, 1.4)  # (the whoosh of the arm)


@rpc("authority", "call_local", "reliable")
func fx_landed(at: Vector2, glass: bool, storey: int) -> void:
	Sfx.play(main, "glass" if glass else "metal", at, 2.0 if glass else 0.0)
	if glass and storey == 0:
		# Glass everywhere: bright little bits left on the ground.
		for i in 7:
			main.blood.append([at + Vector2(randf_range(-7, 7), randf_range(-4, 4)), randf_range(0.3, 0.7),
					Color(0.75, 0.9, 0.85, 0.8)])
		if main.decals:
			main.decals.queue_redraw()


## The next blow from `p`'s hands: {hand, kind, stats, windup}. Swings alternate
## between the hands (a two-handed weapon uses both every time), starting from
## the right again after a pause. The server acts on it; the local player's
## client also uses it to show the swing the moment they click.
static func next_swing(p: Player) -> Dictionary:
	var hand := p.next_hand if p.anim_t < COMBO_RESET else "r"
	if Items.two_handed(p.hand_weapon("r")):
		hand = "r"
	var wid := p.hand_weapon(hand)
	var slow := Body.arm_slow(p.wounds)  # (a bitten arm swings slower)
	if wid == "":
		var punch := PUNCH.duplicate()
		punch[2] *= slow
		var gloves := p.wear_mult("punch")  # (boxing gloves: harder, and a bigger shove)
		punch[1] *= gloves
		punch[4] *= gloves * gloves
		return {hand = hand, kind = Look.PUNCH_R if hand == "r" else Look.PUNCH_L, stats = tired(p, punch), windup = PUNCH_WINDUP}
	var w := Items.def(wid)
	if Items.is_gun(wid):  # not aiming: a blow with it
		w = {range = 17.0, dmg = w.bash, cd = 0.55, stun = 0.35, knock = 6.0, dur = 0.3}
	var dual: bool = p.hand_weapon("r") != "" and p.hand_weapon("l") != ""
	var dmg: float = w.dmg * (Items.OFF_HAND if hand == "l" else 1.0)
	return {hand = hand, kind = Look.SWING if hand == "r" else Look.SWING_L,
			stats = tired(p, [w.range, dmg, w.cd * (Items.DUAL_SPEED if dual else 1.0) * slow, w.stun, w.knock]), windup = w.dur * 0.45}


## A kick from `p`, as tired as they are.
static func kick_stats(p: Player) -> Array:
	return tired(p, KICK.duplicate())


## Blow stats [range, dmg, cd, stun, knock] for someone worn out: slower, softer.
static func tired(p: Player, stats: Array) -> Array:
	if p.stamina < TIRED:
		stats[1] *= TIRED_WEAK
		stats[2] *= TIRED_SLOW
	return stats


## What a blow costs in stamina: a punch, a kick, or a swing of weapon `wid`.
static func blow_cost(kind: int, wid: String) -> float:
	if kind == Look.KICK:
		return KICK_COST
	if wid == "":
		return PUNCH_COST
	return SWING_COST + WEIGHT_COST * float(Items.def(wid).get("weight", 1.0))
## Punch hits the closest zombie in front; a kick hits everything in front.
func _melee(p: Player, kind: int, stats: Array, windup := -1.0) -> void:
	p.shoot_cd = stats[2]
	p.search_id = -1  # swinging interrupts a search
	var wid := p.hand_weapon(p.swing_hand) if kind in [Look.SWING, Look.SWING_L] else ""
	p.stamina = maxf(0.0, p.stamina - blow_cost(kind, wid) * Skills.mult(p, "blow_cost"))
	p.exert_t = EXERT_PAUSE
	if p.stamina <= 0.0 and not p.exhausted:
		p.exhausted = true
		main._toast(p, "หมดแรง! หายใจก่อน")
	# Creeping up behind one: the silent kill, there and then, before the
	# swing's own sound can turn it round.
	var quiet := _backstab_target(p, kind, wid)
	if quiet != null:
		_silent_kill(p, quiet, wid)
		return
	p.shoot_cd *= Skills.mult(p, "swing_cd")  # (a practised hand swings again sooner)
	fx_melee.rpc(p.peer_id, kind)
	main._make_noise(p.position, main.NOISE_SWING * (0.6 if p.sneak else 1.0))
	p.pending_kind = kind
	p.pending_stats = stats
	if windup < 0:
		windup = KICK_WINDUP if kind == Look.KICK else PUNCH_WINDUP
	p.pending_t = windup


## A wall, a shut door or window between two people standing on `storey`?
## (No punching through a wall at someone pressed against its far side.)
func _wall_between(a: Vector2, b: Vector2, storey: int) -> bool:
	var w: World = main.world
	var n := ceili(a.distance_to(b) / 3.0)
	for i in range(1, n):
		var c := w.to_cell(a.lerp(b, float(i) / n))
		if storey > 0:
			if w.storey_map(storey).get(c, World.WALL) != World.FLOOR:
				return true
		elif w.door_at.has(c):
			if w.doors[w.door_at[c]].closed:
				return true
		elif w.get_tile(c) in [World.WALL, World.BUILDING, World.IWALL]:
			return true
	return false


## A punch or a kick hits the one zombie in front closest to the aim; a
## weapon that cleaves hits everything in front. Generous cone so a blow
## that looks like it lands, lands.
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
	var zone := "body"
	var hits: Array = []
	for z: Zombie in main.zombies.values():
		var v := z.position - p.position
		if v.length() > reach or z.storey != p.storey or _wall_between(p.position, z.position, p.storey):
			continue
		if Rect2(z.position + Vector2(-8, -31 - z.lift), Vector2(16, 35)).has_point(cursor):
			if picked == null or v.length() < (picked.position - p.position).length():
				picked = z
				zone = zone_at(cursor.y - z.position.y + z.lift, z)
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
	# A kick lands on one: the one you aimed at, else the one most in front.
	# Only a long weapon swung wide (cleave) catches all in its arc.
	var cleave: bool = kind != Look.KICK and Items.def(wid).get("cleave", false)
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
		var where := zone if z == picked and kind != Look.KICK else "body"
		var dmg: float = stats[1] * ZONE_DMG[where] * z.armour_k(where)
		if kind != Look.KICK and backstab(p, z, wid):
			_silent_kill(p, z, wid)
			continue
		z.hp -= dmg
		if z.is_boss():
			z.hurt_by[p.peer_id] = z.hurt_by.get(p.peer_id, 0.0) + dmg
		z.stun = stats[3] * Zombie.KINDS[z.kind].get("stun", 1.0)
		z.push += dir * stats[4]  # (played out over a moment: Zombie.server_tick)
		fx_hit.rpc(z.zid, z.position, dir, kind == Look.KICK, p.peer_id, Items.def(wid).get("draw", {}).get("kind", ""), dmg, where, z.hp <= 0)
		main._make_noise(z.position, main.NOISE_HIT)
		main.skills.gain(p, "combat", "hit")
		if where == "head":
			main.skills.gain(p, "combat", "head")
		if z.hp <= 0:
			main.skills.gain(p, "combat", "kill")
			main.quests.note(p, "kill", {kind = z.kind})
			if where == "head":
				main.quests.note(p, "kill_head")
			_kill_zombie(z, 1.0 if dir.x >= 0 else -1.0, how, where)
			p.kills += 1
			continue
		if kind == Look.KICK:
			_knock_on(z, dir, hits)
		# A good kick can put it on the ground (not the fat ones); a blade can take an arm.
		if kind == Look.KICK and z.kind != "fat" and randf() < (0.5 if z.kind == "runner" else 0.3):
			z.knock_down()
		elif where == "legs" and not Items.has_tag(how, "blade") and z.kind != "fat" and z.down_t <= 0.0 and randf() < LEG_KNOCK:
			z.knock_down()  # its legs taken out from under it
		elif z.is_boss():
			pass  # (its gear: no limbs off)
		elif where == "legs" and Items.has_tag(how, "sever") and not z.crawler() and randf() < LEG_SEVER:
			z.missing |= Look.LOST_LEG
			z.lunge_t = 0.0
			fx_sever.rpc(z.zid, Look.LOST_LEG, dir)
		elif Items.has_tag(how, "sever") and randf() < SEVER_CHANCE:
			var bit := z.arm_left_to_cut()
			if bit > 0:
				z.missing |= bit
				fx_sever.rpc(z.zid, bit, dir)
	if wid != "":
		_wear_weapon(p)


const KNOCK_ON_REACH := 16.0  # how close behind the kicked one another must be to be bumped
const KNOCK_ON_STUN := 0.4  # it loses its footing this long (no harm done)
const KNOCK_ON_SHOVE := 2.0


## The one kicked staggers back into whoever is right behind it: that one
## loses its footing a moment and gives a step, unhurt (one only: the nearest).
func _knock_on(z: Zombie, dir: Vector2, hit: Array) -> void:
	var best: Zombie = null
	var best_d := KNOCK_ON_REACH
	for o: Zombie in main.zombies.values():
		if o == z or hit.has(o) or o.storey != z.storey or o.hp <= 0:
			continue
		var v := o.position - z.position
		if v.length() < best_d and v.dot(dir) > 0.0:
			best = o
			best_d = v.length()
	if best == null:
		return
	best.stun = maxf(best.stun, KNOCK_ON_STUN)
	best.push += dir * KNOCK_ON_SHOVE
	fx_bump.rpc(best.zid, dir)


## Everyone sees a zombie bumped by the one kicked into it: it rocks back.
@rpc("authority", "call_local", "reliable")
func fx_bump(zid: int, dir: Vector2) -> void:
	var z: Zombie = main.zombies.get(zid)
	if z:
		z.hit_dir = dir
		z.stagger_t = Zombie.STAGGER * 0.6


## How a zombie dies depends on what killed it (see Corpse for what each style looks like).
## Head, body or legs, from how high up a zombie (`dy` from its feet) it was hit.
## One on the ground (knocked down, or crawling) is all body.
static func zone_at(dy: float, z = null) -> String:
	if z is Zombie and (z.flags & 2 or z.crawler()):
		return "body"
	var k: float = z.height if z is Zombie else 1.0  # (a tall one's head is higher up)
	return "head" if dy < Proportions.head_line() * k else ("legs" if dy > Proportions.legs_line() * k else "body")


## How it dies: what hit it (`how`: a weapon's draw kind, "gun", "kick",
## "stomp"...) and where (`zone`), before the weapon's own `death` table:
##   head   a blunt blow caves the skull or drops it where it stands (slump),
##          a blade takes the head off, a point goes in (slump), a shot bursts it
##   body   a blade or point: down on its knees, then over (kneel); a shot, back
##   kick   a finishing kick throws it back (flung); so does a shotgun up close
## A silent kill: sneaking, a weapon that can (`silent`: a knife, a machete...),
## behind a zombie that isn't after you.
func backstab(p: Player, z: Zombie, wid: String) -> bool:
	return z.target != p and can_backstab(p, z, wid)


## What every screen can tell (the knife mark over its head, see Main): the
## server also checks it isn't after you.
static func can_backstab(p: Player, z: Zombie, wid: String) -> bool:
	if not p.sneak or wid == "" or not Items.def(wid).get("silent", false) or p.storey != z.storey or z.is_boss():
		return false
	if z.state == 2 or z.flags & 2 or z.crawler():
		return false
	var to_me := (p.position - z.position).normalized()
	return Vector2.from_angle(z.facing).dot(to_me) < BACKSTAB


## The zombie a blow starting now would kill silently (see backstab): in
## reach, the one under the cursor or else the nearest in front. null: none.
func _backstab_target(p: Player, kind: int, wid: String) -> Zombie:
	if kind == Look.KICK or not p.sneak or not Items.def(wid).get("silent", false):
		return null
	var reach: float = Items.def(wid).get("range", 0.0) + Zombie.RADIUS + MELEE_SLACK
	var cursor := p.position + Look.CHEST + p.aim
	var best: Zombie = null
	for z: Zombie in main.zombies.values():
		var v := z.position - p.position
		if v.length() > reach or z.storey != p.storey or _wall_between(p.position, z.position, p.storey) or not backstab(p, z, wid):
			continue
		var on_it := Rect2(z.position + Vector2(-8, -31 - z.lift), Vector2(16, 35)).has_point(cursor)
		if not on_it and v.normalized().dot(p.aim.normalized()) < 0.3:
			continue
		if best == null or v.length() < best.position.distance_to(p.position):
			best = z
	return best


## Played out: you step in behind it (side-on, as it's drawn), a hand over
## its mouth, the blade into the back of its head, and lower it face down.
## Held there for STAB_TIME; no noise at all.
func _silent_kill(p: Player, z: Zombie, wid: String) -> void:
	var side := 1.0 if z.position.x >= p.position.x else -1.0
	var at := z.position - Vector2(side * STAB_GAP, 0)
	if main.world.can_stand(at, Player.RADIUS) and not _wall_between(at, z.position, p.storey):
		p.position = at
		p.net_pos = at
	z.hp = 0.0
	fx_stealth.rpc(p.peer_id, p.position, side)
	main.fx_sound.rpc("blade", z.position)
	_kill_zombie(z, side, wid, "head", false, "held")
	main.skills.gain(p, "stealth", "silent_kill")
	main.skills.gain(p, "combat", "kill")
	main.quests.note(p, "silent_kill")
	main.quests.note(p, "kill", {kind = z.kind})
	p.kills += 1
	main._toast(p, "ฆ่าเงียบ")


## Everyone sees `peer_id` do a silent kill toward `side` (+1: to the right).
@rpc("authority", "call_local", "reliable")
func fx_stealth(peer_id: int, pos: Vector2, side: float) -> void:
	var p: Player = main.players.get(peer_id)
	if p == null:
		return
	p.position = pos
	p.stab_t = 0.0
	p.stab_side = side


static func death_style(how: String, zone := "body", close := false) -> String:
	var r0 := randf()
	var blade := Items.has_tag(how, "sever")
	var point: bool = Items.def(how).get("death", {}).has("stab")
	var fist := how in ["", "punch"]
	var blunt := Items.has_tag(how, "blunt") or fist
	match zone:
		"head":
			if how == "gun":
				return "burst"
			if blade:
				return "behead" if r0 < 0.75 else "slump"
			if point:
				return "slump"
			if blunt:
				return "crush" if r0 < 0.55 and not fist else "slump"
		"body":
			if how == "gun":
				return "flung" if close else "blunt"
			if how == "kick":
				return "flung"
			if (blade or point) and r0 < 0.5:
				return "kneel"
	if how == "gun":
		return "blunt"
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


func _kill_zombie(z: Zombie, fall_dir: float, how := "", zone := "body", close := false, style := "") -> void:
	z.release()
	if style == "":
		style = death_style(how, zone, close)
	if style in FORWARD:
		fall_dir = -fall_dir  # (these go down toward whoever did it)
	main.add_corpse(z.position, fall_dir, z.body_look(), style, z.storey)
	# What it wore can be taken off the body: always what a turned survivor had
	# on, sometimes an ordinary zombie's (often worn half through).
	var i := 0
	for slot in z.wear:
		var id: String = z.wear[slot]
		var full: int = Items.def(id).get("hp", 1)
		var special: bool = Items.def(id).get("special", false) or z.is_boss()  # (the rare costumes, and a boss's gear, always come off)
		if not z.outfit.is_empty() or special or randf() < 0.35:
			var hp := full if not z.outfit.is_empty() or special else maxi(1, int(full * randf_range(0.3, 0.8)))
			main._spawn_pickup(z.position + Vector2.from_angle(i * 1.3) * 7, Items.from_key(id, hp), z.storey)
		i += 1
	# What some kinds had on them.
	if z.kind == "junkie" and randf() < 0.6:
		main._spawn_pickup(z.position + Vector2(-6, 4), Items.make("pills"), z.storey)
	if z.kind == "guard" and z.wear.get("neck", "") == "whistle" and randf() < 0.65:
		main._spawn_pickup(z.position + Vector2(6, 4), Items.make("whistle"), z.storey)
	if z.is_boss():
		main.bosses.died(z)
	main.survival.trapped_died(z)
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
	return body_hit_at(from, dir, feet).x


## Where a shot meets a body: (distance along it, -1 for a miss; how high up,
## dy from the feet, for zone_at): the nearest of the body's circles it passes through.
static func body_hit_at(from: Vector2, dir: Vector2, feet: Vector2) -> Vector2:
	var best := Vector2(-1.0, 0.0)
	for y in [-3.0, -9.0, -15.0, -21.0, -27.0]:
		var c := feet + Vector2(0, y)
		var t := (c - from).dot(dir)
		if t > 0 and (from + dir * t).distance_to(c) < BODY_W and (best.x < 0 or t < best.x):
			best = Vector2(t, y)
	return best


## Aim help: with the cursor on a zombie's figure, aim at its middle.
static func snap_aim(from: Vector2, mouse: Vector2, zombies: Array) -> Vector2:
	var best := mouse
	var best_d := 1e9
	for z in zombies:
		var d: Vector2 = mouse - z.position
		if absf(d.x) < 12.0 and d.y > -32.0 and d.y < 4.0 and d.length() < best_d:
			best_d = d.length()
			# (the middle of the part under the cursor: the head if it's on the head)
			best = z.position + Vector2(0, {head = -27.0, body = -15.0, legs = -5.0}[zone_at(d.y, z)])
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
		var hit_dy := 0.0
		for z: Zombie in main.zombies.values():
			if p.on_roof and (z.storey > 0 or main.world.building_at.has(main.world.to_cell(z.position))):
				continue  # indoors, under the roof: out of sight
			if not p.on_roof and z.storey != p.storey:
				continue  # (a floor between you)
			var bh := body_hit_at(from, dir, z.position)
			if bh.x > 0 and bh.x < length:
				length = bh.x
				hit = z
				hit_dy = bh.y
		ends.append(from + dir * length)
		if hit:
			hit_any = true
			var where := zone_at(hit_dy, hit)
			var dmg: float = d.dmg * (1.0 if length < d.range * 0.5 else 0.6)  # (pellets lose their bite far out)
			dmg *= (GUN_HEAD if where == "head" else ZONE_DMG[where]) * hit.armour_k(where)
			hit.hp -= dmg
			if hit.is_boss():
				hit.hurt_by[p.peer_id] = hit.hurt_by.get(p.peer_id, 0.0) + dmg
			hit.stun = maxf(hit.stun, 0.25)
			hit.position = main.world.slide(hit.position, dir * 3.0, Zombie.RADIUS, false, false, hit.storey)
			fx_hit.rpc(hit.zid, hit.position, dir, true, p.peer_id, "", dmg, where, hit.hp <= 0)
			main.skills.gain(p, "combat", "hit")
			if hit.hp <= 0:
				main.skills.gain(p, "combat", "kill")
				main.quests.note(p, "kill", {kind = hit.kind})
				if where == "head":
					main.quests.note(p, "kill_head")
			if hit.hp <= 0 and main.zombies.has(hit.zid):
				_kill_zombie(hit, 1.0 if dir.x >= 0 else -1.0, "gun", where, int(d.pellets) > 1 and length < 60.0)
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
	if not me.alive() or (me.riding >= 0 and me.seat == 0) or me.sleeping or me.local_cd > 0.0 or me.aiming:
		return
	if me.wants_kick():
		me.kick_buf = 0.0
		me.local_cd = kick_stats(me)[2]
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
func fx_hit(zid: int, pos: Vector2, dir: Vector2, strong: bool, attacker: int, weapon_kind := "", dmg := 0.0,
		zone := "body", kill := false) -> void:
	if dmg > 0:
		main.dmg_numbers.append([pos + Vector2(randf_range(-4, 4), -30), str(int(dmg)) + ("!" if zone == "head" else ""), dmg >= 30 or zone == "head", 0.0])
	var z: Zombie = main.zombies.get(zid)
	if z:
		z.flinch(dir, strong)
	var who: Player = main.players.get(attacker)
	if who and who.anim_t < 0.4:
		who.hitstop = KILL_STOP if kill else HITSTOP  # the blow lands: a beat of stillness sells its weight
	main.sparks.append([pos + Look.CHEST - dir * 3.0, 0.14, strong])
	for i in 4 if strong else 2:
		main.blood.append([pos + dir * randf_range(2, 8) + Vector2(randf_range(-3, 3), randf_range(-2, 2)),
				randf_range(0.8, 2.2), Color(randf_range(0.35, 0.5), 0.02, 0.02, 0.85)])
	main.decals.queue_redraw()
	var blade := Items.has_tag(weapon_kind, "blade")
	Sfx.play(main, "blade" if blade else ("kick" if strong else "hit"), pos)
	if attacker == multiplayer.get_unique_id():
		main.shake = maxf(main.shake, 3.2 if kill else (2.2 if strong or weapon_kind != "" else 1.3))


## Everyone sees `peer_id` jolted by a bite from direction `dir` (toward them).
@rpc("authority", "call_local", "reliable")
func fx_bitten(peer_id: int, dir: Vector2) -> void:
	var p: Player = main.players.get(peer_id)
	if p == null:
		return
	p.hurt(dir)
	if peer_id == multiplayer.get_unique_id():
		main.shake = maxf(main.shake, 1.8)


@rpc("authority", "call_local", "reliable")
func fx_death(pos: Vector2, fall_dir: float, body: Dictionary, style: String, cid := 0, storey := 0) -> void:
	main.leave_corpse(pos, fall_dir, body, true, 0.0, style, cid, -1.0, storey)
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
	g.kind = "leg" if bit == Look.LOST_LEG else "arm"
	g.lk = z.body_look()
	g.position = z.position + Vector2(0, 1)
	g.h = 6.0 if bit == Look.LOST_LEG else 16.0
	g.vel = Vector2(dir.x, dir.y * 0.6) * 45.0
	g.vh = 50.0
	g.spin = randf_range(7.0, 12.0)
	g.flip = dir.x < 0
	g.z_index = 1
	main.add_gib(g)
	main.splatter(z.position, dir, 5)
