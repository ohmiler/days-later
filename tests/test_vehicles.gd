extends "res://tests/test_base.gd"
## Motorbikes: parked bikes can be ridden, go much faster than walking, burn
## fuel, are loud, knock zombies down, can't go indoors, stay where you leave
## them (even after a reload), and can be hotwired and refuelled.


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
	for m in StreetProp.BIKE_MODELS:
		if not Vehicles.MODELS.has(m[0]):
			bad.append("no ride data for %s" % m[0])
	check(bad.is_empty(), "every bike model has ride data" + ("" if bad.is_empty() else ": " + "; ".join(bad)))

	SaveGame.wipe()
	seed(11)
	await host(9400)
	main.spawn_timer = 1e9  # no stray zombies wandering into the road
	var w: World = main.world
	check(w.vehicles.size() > 20, "the city has bikes to ride (%d)" % w.vehicles.size())
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
	main.actions.req_interact()
	check(me.riding < 0 and v.rider == 0, "E gets you off")
	var left_at: Vector2 = v.pos
	check(me.position.distance_to(left_at) < 16.0, "you step off beside it")

	# No riding into buildings.
	var door_cell := Vector2i(-1, -1)
	for d in w.doors:
		if d.kind == "door" and w.get_tile(d.cell + Vector2i.DOWN) == World.SIDEWALK:
			door_cell = d.cell
			break
	var v2: Dictionary = w.vehicles[(v.id + 1) % w.vehicles.size()]
	v2.key = true
	v2.fuel = 2.0
	v2.pos = w.to_pos(door_cell + Vector2i(0, 2))
	Vehicles._place(v2)
	w.set_door(w.door_at[door_cell], false, 60.0, 0, false)
	me.position = v2.pos + Vector2(0, 8)
	main.vehicles.mount(me, v2.id)
	me.move = Vector2.UP
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
	me.sel = 0
	main.inventory._send_inv(me)
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
