extends "res://tests/test_base.gd"
## The cars the city is left with (Vehicles._park_cars): real cars along the
## kerb, one in five running, solid where they stand, none left in the lanes;
## nothing else on wheels but what can be driven (no buses, vans, pickups,
## songthaews, tuk-tuks, army truck or wrecks), and their road is clear.


func run() -> void:
	SaveGame.wipe()
	await host(9381, false, true, 11)
	main.spawn_timer = 1e9
	var w: World = main.world
	var cars := w.vehicles.filter(func(v): return Vehicles.is_car(v))
	var running := cars.filter(func(v): return v.hp > 0)
	check(cars.size() > 100, "the city has cars to park (%d)" % cars.size())
	var share := float(running.size()) / cars.size()
	check(share > 0.1 and share < 0.3, "about one in five runs (%d of %d)" % [running.size(), cars.size()])
	# None left out in the lanes: every one stands within two cells of a kerb.
	var in_lane := 0
	for v in cars:
		var rec: Dictionary = v.prop
		var strip := Vehicles._strip(rec)
		if Vehicles._kerb(w, strip[0], rec.get("horizontal", true))[0] > 2:
			in_lane += 1
	check(in_lane == 0, "no car stands out in a lane (%d)" % in_lane)
	# Only what can be driven: the rest of the traffic is gone, and its road is clear.
	var laid := w.street_props.filter(func(r): return r.kind in Vehicles.PROP_ONLY)
	var shown := laid.filter(func(r): return not r.get("culled", false))
	check(not laid.is_empty() and shown.is_empty(), "no bus, van, pickup, songthaew, tuk-tuk, army truck or wreck stands in the street (%d laid out, %d left)" % [laid.size(), shown.size()])
	var bus: Array = laid.filter(func(r): return r.kind == "bus")
	if not bus.is_empty():
		var at := Vector2i((bus[0].pos / World.TILE).floor()) + Vector2i(1, -1)
		check(not w.blocked.has(at), "where a bus stood, the road is clear to walk")
	# Solid where it stands.
	var v: Dictionary = running[0]
	check(not w.can_stand(v.pos, Player.RADIUS), "a parked car is solid to walkers")
	check(w.blocked.size() > 0 and not v.cells.is_empty(), "it holds its cells (%d)" % v.cells.size())
	# A dead one can't be started.
	var dead: Dictionary = cars.filter(func(c): return c.hp <= 0)[0]
	me.position = dead.pos + Vector2(0, 24)
	var acts: Array = main.vehicles.actions_for(me, dead.id)
	check(not acts[0].ok and acts[0].why == "รถพัง", "a dead shell won't start (%s)" % acts[0].why)
	# A running one: in, its cells are free, it drives, out, it blocks where it stopped.
	# (one with room ahead of it: they are parked close)
	for c in running:
		Vehicles.free_cells(w, c)
		var clear := true
		for d in range(6, 110, 6):
			clear = clear and not Vehicles.car_blocked(w, c.pos + Vector2.from_angle(c.dir) * d, c.dir, CarArt.SEDAN)
		Vehicles.block_parked(w, c)
		if clear:
			v = c
			break
	check(Vehicles.car_blocked(w, v.pos, v.dir, CarArt.SEDAN), "(chosen a car with a clear road ahead)")
	v.key = true
	v.fuel = 30.0
	var at: Vector2 = v.pos
	var old_cells: Array = v.cells.duplicate()
	me.position = at + Vector2.from_angle(v.dir).orthogonal() * 22.0
	main.actions.req_act("vehicle", v.id, "ride")
	check(me.riding == v.id and old_cells.all(func(c): return not w.blocked.has(c)), "in, it lets go of its cells")
	me.move = Vector2.UP
	simulate(1.2)
	check(v.pos.distance_to(at) > 20.0, "it drives off (%.0f px)" % v.pos.distance_to(at))
	me.move = Vector2.ZERO
	simulate(2.5)
	var stop: Vector2 = v.pos
	main.vehicles.dismount(me)
	check(not v.cells.is_empty() and not w.can_stand(stop, Player.RADIUS), "out again, it is solid where it stopped")
	check(old_cells.all(func(c): return not w.blocked.has(c) or v.cells.has(c)), "and not where it was")
	check(main.vehicles.changed().has(v.id), "a car that has been driven is saved")
	check(w.can_stand(me.position, Player.RADIUS), "and you stand clear of it")
