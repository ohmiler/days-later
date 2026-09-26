extends "res://tests/test_base.gd"
## Motorbikes: parked bikes can be ridden, go much faster than walking, burn
## fuel, are loud, knock zombies down, can't go indoors, stay where you leave
## them (even after a reload), can be hotwired and refuelled, and carry two.


## A stretch of open road with nothing parked on it for a good way to the right.
func _road_spot() -> Vector2:
	var w: World = main.world
	for rd in w.roads:
		if not rd.horizontal:
			continue
		var y: int = rd.rect.position.y + 2
		for x in range(10, World.W - 30):
			var clear := true
			for dx in 22:
				for dy in [-1, 0, 1]:
					var c := Vector2i(x + dx, y + dy)
					if w.get_tile(c) != World.ROAD or w.blocked.has(c):
						clear = false
			if clear:
				return w.to_pos(Vector2i(x, y))
	return Vector2.ZERO


func run() -> void:
	var bad := []
	for id in Vehicles.MODELS:
		for key in ["name", "speed", "accel", "fuel", "use", "noise", "hp"]:
			if not Vehicles.MODELS[id].has(key):
				bad.append("%s: no %s" % [id, key])
	for m in BikeArt.BIKE_MODELS:
		if not Vehicles.MODELS.has(m[0]):
			bad.append("no ride data for %s" % m[0])
	check(bad.is_empty(), "every bike model has ride data" + ("" if bad.is_empty() else ": " + "; ".join(bad)))

	SaveGame.wipe()
	seed(11)
	await host(9400)
	main.spawn_timer = 1e9  # no stray zombies wandering into the road
	var w: World = main.world
	check(w.vehicles.size() > 20, "the city has bikes to ride (%d)" % w.vehicles.size())
	# Parked at the kerb or against a wall, never across a shop front or a door.
	var blocking := []
	for rec in w.street_props:
		if rec.kind != "motorbike":
			continue
		var c: Vector2i = w.to_cell(rec.pos)
		if w.get_tile(c + Vector2i.UP) in [World.IWALL, World.BUILDING] or w.door_at.has(c + Vector2i.DOWN) or w.door_at.has(c + Vector2i.UP):
			blocking.append(c)
	check(blocking.is_empty(), "no parked bike blocks a shop front or a door (%s)" % [blocking.slice(0, 3)])
	var kinds := {}
	for v in w.vehicles:
		kinds[v.model] = true
	check(kinds.size() >= 8, "all sorts of bikes about (%d kinds)" % kinds.size())
	var v: Dictionary = {}
	for x in w.vehicles:
		if x.model == "wave":
			v = x
			break
	v.key = true
	v.fuel = 2.0
	v.pos = _road_spot()
	Vehicles._place(v)
	me.position = v.pos + Vector2(0, 10)
	var t := Interact.target(main, me)
	check(t.get("kind") == "vehicle" and t.id == v.id, "E points at the bike (%s)" % t.get("title", "nothing"))
	main.actions.req_act("vehicle", v.id, "ride")
	check(me.riding == v.id and v.rider == 1, "E > ride gets you on")

	# Riding: fast, thirsty, loud.
	var start := me.position
	var fuel_before: float = v.fuel
	var z := zombie_at(start + Vector2(260, 60))
	me.move = Vector2.RIGHT
	simulate(1.5)
	var went := me.position.x - start.x
	check(went > 55.0 * 1.5 * 1.6, "a bike goes much faster than walking (%.0f px in 1.5 s)" % went)
	check(v.fuel < fuel_before, "and burns fuel (%.3f left)" % v.fuel)
	check(z.investigate_t > 0.0 or z.target != null, "and the engine draws zombies")
	check(v.pos == me.position, "the bike goes with you")

	# A zombie in the road is knocked flat.
	var z2 := zombie_at(me.position + Vector2(40, 0))
	z2.hp = 1000.0
	simulate(0.6)
	check(z2.down_t > 0.0, "running into a zombie knocks it down")

	# Off at the other end: the bike stays there.
	me.move = Vector2.ZERO
	simulate(1.5)
	# Tapping E, the way a player does (key down, key up), not calling the server directly.
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_E
		e.pressed = down
		main._unhandled_input(e)
	check(me.riding < 0 and v.rider == 0, "tapping E gets you off")
	var left_at: Vector2 = v.pos
	check(me.position.distance_to(left_at) < 16.0, "you step off beside it")

	# Two up: a friend hops on the back, rides along, can fight, and gets off.
	v.pos = _road_spot()
	Vehicles._place(v)
	me.position = v.pos + Vector2(0, 10)
	main.vehicles.mount(me, v.id)
	var p2: Player = main._add_player(77)
	p2.pname = "Noi"
	p2.position = v.pos + Vector2(0, -10)
	var t2 := Interact.target(main, p2)
	var acts2: Array = main.vehicles.actions_for(p2, v.id)
	check(t2.get("kind") == "vehicle" and acts2[0].verb == "pillion" and acts2[0].ok, "E on a ridden bike offers a seat on the back")
	main.actions._do_action(p2, t2, "pillion")
	check(p2.riding == v.id and p2.seat == 1 and v.pillion == 77, "and puts you there")
	var p3: Player = main._add_player(78)
	p3.position = v.pos + Vector2(0, -10)
	check(not main.vehicles.actions_for(p3, v.id)[0].ok, "a third can't squeeze on")
	var from := me.position
	me.move = Vector2.RIGHT
	simulate(0.5)
	var two_went := me.position.x - from.x
	check(p2.position == me.position, "the one on the back goes where the bike goes")
	p2.set_attack_input(true, false)
	simulate(0.1)
	p2.set_attack_input(false, false)
	check(p2.anim != Look.NONE, "and can swing a punch from there")
	main.vehicles.dismount(p2)
	check(p2.riding < 0 and p2.seat == 0 and v.pillion == 0 and me.riding == v.id, "hopping off the back leaves the rider riding")
	me.move = Vector2.ZERO
	simulate(1.5)
	main.vehicles.dismount(me)
	# Same start, alone: quicker away.
	v.pos = _road_spot()
	Vehicles._place(v)
	me.position = v.pos + Vector2(0, 10)
	main.vehicles.mount(me, v.id)
	from = me.position
	me.move = Vector2.RIGHT
	simulate(0.5)
	check(me.position.x - from.x > two_went, "two up pulls away slower (%.0f vs %.0f px)" % [two_went, me.position.x - from.x])
	me.move = Vector2.ZERO
	simulate(1.5)
	p2.position = me.position + Vector2(0, -10)
	main.vehicles.mount_pillion(p2, v.id)
	main.vehicles.dismount(me)
	check(p2.riding < 0 and v.pillion == 0 and v.rider == 0, "when the rider gets off, so does the one behind")
	check(p2.position.distance_to(v.pos) < 16.0, "beside the bike")
	for id in [77, 78]:
		main.players[id].queue_free()
		main.players.erase(id)

	# Steering: at speed it swings round, it doesn't turn on the spot.
	v.pos = _road_spot()
	Vehicles._place(v)
	me.position = v.pos
	main.vehicles.mount(me, v.id)
	me.move = Vector2.RIGHT
	simulate(1.2)
	me.move = Vector2(0, 1)
	simulate(0.1)
	check(me.ride_vel.x > me.ride_vel.length() * 0.6, "at speed a bike swings round, not on the spot (%s)" % me.ride_vel)
	simulate(0.5)
	check(me.ride_vel.y > me.ride_vel.length() * 0.9, "and comes round in a moment (%s)" % me.ride_vel)
	# Steering back the way you came brakes first.
	me.position = _road_spot()
	me.ride_vel = Vector2(140, 0)
	me.move = Vector2.RIGHT
	simulate(0.05)
	me.move = Vector2.LEFT
	simulate(0.2)
	check(me.ride_vel.x > 0.0 and me.ride_vel.length() < 140.0, "steering right back brakes first (%s)" % me.ride_vel)
	me.move = Vector2.ZERO
	simulate(1.5)

	# At night the headlight lights the road, and shows you up to zombies.
	me.position = _road_spot()
	v.pos = me.position
	w.is_night = true
	var lights: Array = w.light_spots
	w.light_spots = []
	check(Vehicles.headlight_on(v, w), "at night the headlight is on")
	var zl := zombie_at(me.position + Vector2(90, 0))
	zl.facing = PI
	zl.target = null
	check(zl._nearest_player() == me, "and a zombie sees the rider from far off in the dark")
	var fuel_was: float = v.fuel
	v.fuel = 0.0
	check(not Vehicles.headlight_on(v, w) and zl._nearest_player() == null, "no fuel, no light: the dark hides you again")
	v.fuel = fuel_was
	w.light_spots = lights
	w.is_night = false
	zl.queue_free()
	main.zombies.erase(zl.zid)
	main.vehicles.dismount(me)

	# Into a wall: a dent, and hard enough, a bruise. (Any side: in some
	# districts every shop front faces one way.)
	var wall_cell := Vector2i(-1, -1)
	var into := Vector2i.UP
	for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		for y in range(4, World.H - 4):
			for x in range(4, World.W - 4):
				var c := Vector2i(x, y)
				if w.get_tile(c) == World.SIDEWALK and w.get_tile(c + dir) in [World.BUILDING, World.IWALL, World.WALL] 						and w.get_tile(c - dir) in [World.SIDEWALK, World.ROAD] and w.get_tile(c - dir * 2) in [World.SIDEWALK, World.ROAD] 						and not w.blocked.has(c) and not w.blocked.has(c - dir) and not w.door_at.has(c + dir):
					wall_cell = c
					into = dir
					break
			if wall_cell.x >= 0:
				break
		if wall_cell.x >= 0:
			break
	check(wall_cell.x >= 0, "found a wall to ride into")
	v.pos = w.to_pos(wall_cell - into * 2)
	Vehicles._place(v)
	me.position = v.pos
	main.vehicles.mount(me, v.id)
	var hp_was: int = v.hp
	var wounds_was: int = me.wounds.size()
	me.ride_vel = Vector2(into) * 170.0
	me.move = Vector2(into)
	simulate(0.4)
	check(v.hp < hp_was, "a bike into a wall gets dented (%d -> %d)" % [hp_was, v.hp])
	check(me.wounds.size() > wounds_was and me.wounds[-1].kind == "bruise", "and a hard crash bruises the rider")
	check(me.riding == v.id, "but you stay on (it's not that hard a game)")
	me.move = Vector2.ZERO
	main.vehicles.dismount(me)
	v.hp = hp_was
	me.wounds.clear()

	v.pos = left_at  # (back where the first ride left it, for the reload check below)
	Vehicles._place(v)

	# No riding into buildings.
	var door_cell := Vector2i(-1, -1)
	var toward := Vector2i.UP  # from the street to the door
	for d in w.doors:
		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if d.kind in ["door", "shutter"] and not d.broken and w.get_tile(d.cell - dir) == World.SIDEWALK 					and w.get_tile(d.cell - dir * 2) in [World.SIDEWALK, World.ROAD]:
				door_cell = d.cell
				toward = dir
				break
		if door_cell.x >= 0:
			break
	check(door_cell.x >= 0, "found a door onto the street")
	var v2: Dictionary = w.vehicles[(v.id + 1) % w.vehicles.size()]
	v2.key = true
	v2.fuel = 2.0
	v2.pos = w.to_pos(door_cell - toward * 2)
	Vehicles._place(v2)
	w.set_door(w.door_at[door_cell], false, 60.0, 0, false)
	me.position = v2.pos - Vector2(toward) * 8.0
	main.vehicles.mount(me, v2.id)
	me.move = Vector2(toward)
	simulate(1.5)
	check(w.get_tile(w.to_cell(me.position)) not in [World.FLOOR, World.DOOR], "a bike can't go in through a door")
	main.vehicles.dismount(me)
	me.move = Vector2.ZERO

	# A bike without its key: hotwire it with a screwdriver.
	var v3: Dictionary = w.vehicles.filter(func(x): return x.model == "click" and x.id != v2.id)[0]  # (petrol: an electric one takes no jerrycan)
	v3.key = false
	v3.fuel = 0.0
	v3.pos = _road_spot() + Vector2(0, 16)
	Vehicles._place(v3)
	me.position = v3.pos + Vector2(0, 10)
	var acts: Array = main.vehicles.actions_for(me, v3.id)
	check(not acts[0].ok, "no key, no ride (%s)" % acts[0].why)
	me.inv.fill(null)
	main.inventory._give(me, "screwdriver")
	main.inventory.req_select(0)  # into the right hand
	main.actions.req_act("vehicle", v3.id, "hotwire")
	simulate(Vehicles.HOTWIRE_TIME + 0.3)
	check(v3.key, "a screwdriver and a few seconds hotwire it")
	check(not main.vehicles.actions_for(me, v3.id)[0].ok, "but an empty tank still won't go")
	main.inventory._give(me, "fuelcan")
	main.actions.req_act("vehicle", v3.id, "refuel")
	check(v3.fuel > 0.0 and count(me, "fuelcan") == 0, "a jerrycan fills it up (%.1f)" % v3.fuel)

	# Where you left it survives a reload.
	var id: int = v.id
	main._save_all()
	await close_game()
	await host(9401, true, false)
	check(main.world.vehicles[id].pos == left_at, "the bike is still where you left it after a reload")
	SaveGame.wipe()
