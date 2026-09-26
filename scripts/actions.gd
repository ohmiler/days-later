class_name Actions
extends Node
## What E does: the server side of the interaction system (see Interact for what is possible).
## Split out of main.gd; shared state (world, players, zombies, pickups) lives there.

var main: Main


## E tapped: do the main action on whatever is in reach.
@rpc("any_peer", "call_remote", "reliable")
func req_interact() -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.sleeping:
		return
	if p.riding >= 0:
		main.vehicles.dismount(p)  # E on a bike: get off
		return
	var t := Interact.target(main, p)
	var a := Interact.primary(Interact.actions(main, p, t))
	if a.is_empty():
		return
	if a.ok:
		_do_action(p, t, a.verb)
	else:
		main._toast(p, a.why)


## A specific action chosen from the hold-E wheel. The server checks the target
## is still in reach and the action still possible before doing it.
@rpc("any_peer", "call_remote", "reliable")
func req_act(kind: String, id: Variant, verb: String) -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.sleeping:
		return
	var t := Interact.resolve(main, p, kind, id)
	var a := Interact.find_action(Interact.actions(main, p, t), verb)
	if a.is_empty():
		return
	if a.ok:
		_do_action(p, t, verb)
	else:
		main._toast(p, a.why)


const CLIMB_TIME := 0.8
const JUMP_COST := 8.0  # stamina, jumping down off a car


## Up on the roof of a car, after climbing (see Crafting: the "climb" job).
func finish_climb(p: Player, id: int) -> void:
	var rec: Dictionary = main.world.street_props[id]
	if p.position.distance_to(StreetProp.middle(rec)) > Interact.CAR_REACH + 8.0:
		return
	p.on_car = id
	p.car_t = 0.0
	p.position = StreetProp.roof_spot(rec)[0]
	main.fx_sound.rpc("door", p.position)
	main._toast(p, "ขึ้นมาบนหลังคารถ · ซอมบี้ปีนตามไม่ได้ แต่จะมารุม · กด Space เพื่อกระโดดลง")


const ALARM_CHANCE := 0.25  # a car banged on sets its alarm off (once)
const ALARM_TIME := 14.0
const NOISE_ALARM := 380.0
var alarms := {}  # street_props id -> [seconds left, seconds to the next wail]


## A zombie pounds on a car someone is standing on: a thud the street hears,
## and a car might still have the battery to set its alarm off.
func bang_car(id: int, at: Vector2) -> void:
	var rec: Dictionary = main.world.street_props[id]
	main.fx_sound.rpc("door", at)
	main._make_noise(at, main.NOISE_HIT)
	if rec.kind in ["car", "taxi"] and not rec.get("alarm_used", false) and randf() < ALARM_CHANCE:
		rec.alarm_used = true
		alarms[id] = [ALARM_TIME, 0.0]


## Server, every tick: car alarms wail on, drawing zombies from all round.
func tick_alarms(delta: float) -> void:
	for id in alarms.keys():
		var a: Array = alarms[id]
		a[0] -= delta
		a[1] -= delta
		if a[0] <= 0.0:
			alarms.erase(id)
		elif a[1] <= 0.0:
			a[1] = 1.0
			var at := StreetProp.middle(main.world.street_props[id])
			main.fx_sound.rpc("alarm", at)
			main._make_noise(at, NOISE_ALARM)


## Held by a zombie: every press of Space, a click or E is a shove and a
## twist to get free. Tired, each does less. Free, the zombie staggers back.
const STRUGGLE_STEP := 0.2
const STRUGGLE_COST := 2.5


@rpc("any_peer", "call_remote", "reliable")
func req_struggle() -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.grabbed_by < 0:
		return
	var z: Zombie = main.zombies.get(p.grabbed_by)
	if z == null:
		p.grabbed_by = -1
		return
	p.struggle += STRUGGLE_STEP * (0.55 if p.stamina < Combat.TIRED else 1.0)
	p.stamina = maxf(0.0, p.stamina - STRUGGLE_COST)
	p.exert_t = Combat.EXERT_PAUSE
	if p.struggle >= 1.0:
		# Free: shove it off, it staggers back.
		var away := (z.position - p.position).normalized() if z.position.distance_to(p.position) > 0.1 else Vector2.RIGHT
		z.release()
		z.stun = 0.9
		z.attack_cd = 1.5
		z.position = main.world.slide(z.position, away * 12.0, Zombie.RADIUS, false, false, z.up)
		main.combat.fx_hit.rpc(z.zid, z.position, away, true, p.peer_id, "", 0.0)
		main.fx_sound.rpc("kick", p.position)
		main._toast(p, "ดิ้นหลุดแล้ว!")


## V: down on hands and knees to crawl, or back up. Crawling is slow and
## silent, zombies hardly see you, and you fit under a bus or a truck (where
## they don't see you at all unless right beside you, and can't get in).
@rpc("any_peer", "call_remote", "reliable")
func req_prone() -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.riding >= 0 or p.on_car >= 0 or p.sleeping or p.sitting != -1 or p.vaulting() or p.grabbed_by >= 0:
		return
	if p.prone and p.under_vehicle():
		main._toast(p, "คลานออกมาก่อนค่อยลุก")
		return
	p.prone = not p.prone


## Space at a run: a running jump the way you're going. Over something low in
## the way (sandbags, a bin, the bonnet of a car: World.is_low) to the clear
## ground beyond, or on open ground a leap of HOP (over a body, a trap, glass).
## Zombies can't follow over: they go round.
const HOP := 30.0
const VAULT_REACH := 60.0  # farthest a jump carries you, over the widest thing
const VAULT_COST := 10.0


@rpc("any_peer", "call_remote", "reliable")
func req_jump() -> void:
	var p := main._sender()
	if p != null and p.alive() and p.on_car >= 0:
		jump_off_car(p, p.move if p.move.length() > 0.1 else p.aim)  # (up on a car: Space gets you down)
		return
	if p == null or not p.alive() or p.vaulting() or p.grabbed_by >= 0 or p.riding >= 0 or p.on_car >= 0 or p.on_roof or p.up 			or p.sleeping or p.sitting != -1 or p.getup_t > 0.0:
		return
	if p.exhausted or p.stamina < VAULT_COST or Body.sprained(p.wounds):
		main._toast(p, "ไม่มีแรงกระโดด" if not Body.sprained(p.wounds) else "ข้อเท้าแพลง กระโดดไม่ได้")
		return
	var dir := p.move.normalized() if p.move.length() > 0.1 else p.aim.normalized()
	var landing := vault_landing(main.world, p.position, dir)
	if landing[0] == Vector2.INF:
		return  # (a wall, or something too high: no jump)
	var to: Vector2 = landing[0]
	p.stamina -= VAULT_COST
	p.exert_t = main.combat.EXERT_PAUSE
	var dur := 0.3 + p.position.distance_to(to) / 220.0
	fx_vault.rpc(p.peer_id, p.position, to, dur, 7.0 if landing[1] else 4.0)
	main._make_noise(to, main.NOISE_RUN)


## Where a running jump from `from` along `dir` comes down, and whether it
## went over something: [landing, over] (landing INF: can't jump that way).
static func vault_landing(w: World, from: Vector2, dir: Vector2) -> Array:
	var over := false
	# Something low just ahead: the jump is over it, not short of it.
	var need_over := false
	var d := 4.0
	while d <= VAULT_REACH * 0.6:
		var c0 := w.to_cell(from + dir * d)
		if w.is_solid(c0):
			need_over = w.is_low(c0)
			break
		d += 2.0
	d = 4.0
	while d <= VAULT_REACH:
		var at := from + dir * d
		var c := w.to_cell(at)
		if w.is_solid(c):
			if not w.is_low(c):
				return [Vector2.INF, false]
			over = true
		elif (over or (d >= HOP and not need_over)) and w.can_stand(at, Player.RADIUS):
			# Clear of anything low under the feet on landing, too.
			var clear := true
			for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				if w.is_solid(w.to_cell(at + o * Player.RADIUS)):
					clear = false
			if clear:
				return [at, over]
		d += 2.0
	return [Vector2.INF, false]


@rpc("authority", "call_local", "reliable")
func fx_vault(peer_id: int, from: Vector2, to: Vector2, dur: float, h: float, h0 := 0.0) -> void:
	var p: Player = main.players.get(peer_id)
	if p == null:
		return
	p.vault_from = from
	p.vault_to = to
	p.vault_t = 0.0
	p.vault_dur = dur
	p.vault_h = h
	p.vault_h0 = h0  # (jumping down off a roof: starts that high)
	p.lift = 0.0
	p.climb_dur = 0.0
	Sfx.play(main, "kick", from, -6.0, 1.3)  # (the push off)


## Everyone sees `peer_id` climb from `from` up onto a roof `h` high at `to`,
## over `dur` seconds (dur 0: they let go and dropped back).
@rpc("authority", "call_local", "reliable")
func fx_climb(peer_id: int, from: Vector2, to: Vector2, h: float, dur: float) -> void:
	var p: Player = main.players.get(peer_id)
	if p == null:
		return
	p.climb_from = from
	p.climb_to = to
	p.climb_h = h
	p.climb_t = 0.0
	p.climb_dur = dur


## Jump down off a car the way `dir` points, landing clear of it.
func jump_off_car(p: Player, dir: Vector2) -> void:
	if p.on_car < 0:
		return
	var rec: Dictionary = main.world.street_props[p.on_car]
	var from := StreetProp.middle(rec)
	var d := dir.normalized() if dir.length() > 0.1 else Vector2.DOWN
	var land := Vector2.INF
	for turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, PI]:
		for dist in [34.0, 42.0, 50.0]:
			var at: Vector2 = from + d.rotated(turn) * dist
			if main.world.can_stand(at, Player.RADIUS):
				land = at
				break
		if land != Vector2.INF:
			break
	if land == Vector2.INF:
		return
	var h: float = StreetProp.roof_spot(rec)[1]
	p.on_car = -1
	p.stamina = maxf(0.0, p.stamina - JUMP_COST)
	fx_vault.rpc(p.peer_id, p.position, land, 0.45, 4.0, h)  # (off the roof and down: the same arc as a running jump)
	main._make_noise(land, main.NOISE_RUN)


## X: sit down where you are (or get up again). Sat, you get your breath back
## faster and are harder to spot.
@rpc("any_peer", "call_remote", "reliable")
func req_sit() -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.riding >= 0:
		return
	if p.sitting != -1 or p.sleeping:
		p.stand_up()
		return
	if p.getup_t > 0.0:
		return
	p.sitting = -2
	p.rest_face = Player.face_of(p.aim)


## Z: lie down where you are (or get up again).
@rpc("any_peer", "call_remote", "reliable")
func req_sleep() -> void:
	var p := main._sender()
	if p == null or not p.alive():
		return
	if p.sleeping:
		p.stand_up()
		return
	var why: String = main.survival.can_sleep(p)
	if why != "":
		main._toast(p, why)
		return
	main.survival.start_sleep(p, -1)


func _do_action(p: Player, t: Dictionary, verb: String) -> void:
	if t.get("kind") == "thing":
		main.things.act(p, t.id, verb)
		return
	match verb:
		"up", "down":
			# Ground floor -> upstairs (where there is one) -> roof, and back down.
			var has_up: bool = main.world.upper.has(t.id)
			var lvl := (2 if p.on_roof else (1 if p.up else 0)) + (1 if verb == "up" else -1)
			if lvl == 1 and not has_up:
				lvl = 2 if verb == "up" else 0
			lvl = clampi(lvl, 0, 2)
			p.on_roof = lvl == 2
			p.up = lvl == 1
			p.position = main.world.to_pos(t.id)
			main.fx_sound.rpc("door", p.position)
			main._toast(p, ["ลงมาข้างล่าง", "ขึ้นมาชั้น 2 · ซอมบี้ขึ้นบันไดตามมาได้", "ขึ้นมาบนดาดฟ้า · ซอมบี้ตามขึ้นมาไม่ได้"][lvl])
		"jump":
			var drop := Interact.jump_spot(main.world, p.position)
			if drop == Vector2.INF:
				return
			p.on_roof = false
			p.position = drop
			p.take_damage(10)
			main.fx_sound.rpc("kick", drop)
			main._make_noise(drop, main.NOISE_RUN)
			if randf() < 0.6:
				Body.add(p, "sprain", "legs")
				main._toast(p, "กระโดดลงมา! ข้อเท้าแพลง · วิ่งไม่ได้สักพัก")
			else:
				main._toast(p, "กระโดดลงมา! เจ็บขา")
		"take":
			var item: Dictionary = main.pickups[t.id].item
			var took := false
			if item.get("n", 1) == 1 and Items.stack(item.id) > 1:
				took = main.inventory._give(p, item.id)  # joins a pile you already carry
			else:
				# As it lies: worn, half used, a pile of several.
				for i in p.inv.size():
					if p.inv[i] == null:
						p.inv[i] = item.duplicate()
						took = true
						break
			if not took:
				main._toast(p, "กระเป๋าเต็ม")
				return
			main.pickup_del.rpc(t.id)
			main.fx_sound.rpc("pickup", p.position)
			main._toast(p, "เก็บ %s" % Items.display_name(item.id))
			main.inventory._send_inv(p)
		"take_trap":
			var kind: String = main.world.doors[t.id].kind
			if not main.inventory._give(p, kind):
				main._toast(p, "กระเป๋าเต็ม")
				return
			main.doors.door_state.rpc(t.id, false, -1.0, 0, true)  # hp -1: picked up, draw nothing
			main.fx_sound.rpc("pickup", p.position)
			main._toast(p, "เก็บ%sคืน" % World.BUILDS[kind].name)
			main.inventory._send_inv(p)
		"open", "close", "smash":
			main.doors._toggle_door(p, t.id)
		"board", "repair":
			main.doors._reinforce(p, t.id)
		"stomp":
			var z: Zombie = main.zombies.get(t.id)
			if z == null or z.down_t <= 0.0:
				return
			main.combat.fx_melee.rpc(p.peer_id, Look.KICK)
			main._make_noise(z.position, main.NOISE_HIT)
			main.combat.fx_hit.rpc(z.zid, z.position, Vector2.DOWN, true, p.peer_id, "", z.hp)
			main.combat._kill_zombie(z, 1.0 if z.position.x >= p.position.x else -1.0, "stomp")
			p.kills += 1
		"sleep":
			main.survival.start_sleep(p, t.id)
		"climb":
			# (No progress bar: you see yourself climbing. Moving lets go: Crafting.server_tick.)
			var rec: Dictionary = main.world.street_props[t.id]
			var spot: Array = StreetProp.roof_spot(rec)
			p.craft = {kind = "climb", id = t.id, t = CLIMB_TIME}
			fx_climb.rpc(p.peer_id, p.position, spot[0], spot[1], CLIMB_TIME)
			main.fx_sound.rpc("rustle", p.position)
		"burn":
			main.burn_corpse(p, t.id)
		"travel":
			var ex: Array = main.world.exits.filter(func(e): return e.id == t.id)
			if not ex.is_empty():
				main.travel(p, ex[0])
		"jumpdown":
			jump_off_car(p, p.aim)
		"sit":
			var d: Dictionary = main.world.decor[t.id]
			p.sleeping = false
			p.sitting = t.id
			p.rest_face = 2
			p.position = main.world.to_pos(d.cell) + Vector2(0, World.TILE * 0.45 + 0.5)  # (in front of it, so drawn over it)
		"ride":
			main.vehicles.mount(p, t.id)
		"pillion":
			main.vehicles.mount_pillion(p, t.id)
		"hotwire":
			main.crafting._start(p, {kind = "hotwire", id = t.id}, Vehicles.HOTWIRE_TIME)
			main._make_noise(p.position, main.NOISE_SEARCH)
			main._toast(p, "กำลังต่อสายตรง · ยืนนิ่งๆ")
		"refuel":
			main.vehicles.refuel(p, t.id)
		"strip":
			main.crafting.start_strip(p, t.id)
		"claim":
			p.bed = t.id
			main.fx_sound.rpc("rustle", p.position)
			main._toast(p, "เตียงนี้เป็นของคุณแล้ว · ถ้าตาย คนใหม่จะตื่นที่นี่")
		"look":
			main.fx_sound.rpc("rustle", main.world.container_nodes[t.id].position)
			main.inventory._open_box(p, t.id)
		"search":
			var f: FurnitureProp = main.world.container_nodes[t.id]
			p.search_id = t.id
			p.search_t = main.inventory.SEARCH_TIME
			main.fx_sound.rpc("rustle", f.position)
			main._make_noise(f.position, main.NOISE_SEARCH)
			main._notify(p.peer_id, &"search_started", [main.inventory.SEARCH_TIME])
