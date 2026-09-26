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
	main._toast(p, "ขึ้นมาบนหลังคารถ · ซอมบี้ปีนตามไม่ได้ แต่จะมารุม · เดินเพื่อกระโดดลง")


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
	p.on_car = -1
	p.position = land
	p.stamina = maxf(0.0, p.stamina - JUMP_COST)
	p.getup_t = 0.25  # (landing)
	main.fx_sound.rpc("kick", land)
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
			if item.get("n", 1) > 1 or Items.is_weapon(item.id):
				for i in p.inv.size():
					if p.inv[i] == null:
						p.inv[i] = item.duplicate()
						took = true
						break
			else:
				took = main.inventory._give(p, item.id)
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
			main.crafting._start(p, {kind = "climb", id = t.id}, CLIMB_TIME)
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
