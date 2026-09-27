extends "res://tests/test_base.gd"
## The big buildings (BigPlans): hospitals, flats, offices, malls and markets
## built floor by floor from their plans; every cupboard in them can be walked
## up to, several stairwells go all the way up, zombies take the nearest. A
## generator gives its building power: its lights, its pump, its fridges; it
## burns fuel by the clock and is loud.

## Letters you can walk on (floor, doorways, stairs, what lies on the floor).
const WALK := ".dDSmvnhopril qCjIPN"


func run() -> void:
	_plans()
	await _in_game()


# --- The plans ------------------------------------------------------------------

func _plans() -> void:
	var rng := RandomNumberGenerator.new()
	var bad := []
	var made := 0
	for kind in BigPlans.KINDS:
		var def: Dictionary = BigPlans.KINDS[kind]
		for i in 25:
			rng.seed = i * 7 + 1
			var size := Vector2i(rng.randi_range(def.w[0], def.w[1]), rng.randi_range(def.d[0], def.d[1]))
			var floors := rng.randi_range(def.storeys[0], def.storeys[1])
			var plan := BigPlans.make(kind, size, floors, rng)
			made += 1
			var all: Array = [plan.rows] + plan.storeys
			if all.size() != floors:
				bad.append("%s %s: %d floors, not %d" % [kind, size, all.size(), floors])
			var stairs := _cells(all[0], "S")
			for f in all.size():
				var rows: Array = all[f]
				if rows.size() != size.y or rows.any(func(r): return r.length() != size.x):
					bad.append("%s %s floor %d: not the plot's size" % [kind, size, f])
					continue
				for ch in "".join(rows):
					if not (CityGen.PLAN_FURNITURE.has(ch) or CityGen.PLAN_DECOR.has(ch) or ch in CityGen.PLAN_OTHER):
						bad.append("%s: unknown letter '%s'" % [kind, ch])
				if _cells(rows, "S") != stairs:
					bad.append("%s %s floor %d: the stairs move" % [kind, size, f])
				var from: Array = _cells(rows, "D") if f == 0 else stairs
				var lost := _unreachable(rows, from)
				if not lost.is_empty():
					bad.append("%s %s floor %d: can't get to %s" % [kind, size, f, lost.slice(0, 3)])
			if floors > 1 and stairs.size() < 2:
				bad.append("%s %s: only %d stairs" % [kind, size, stairs.size()])
	check(bad.is_empty(), "%d plans made to measure, every floor the plot's size, the stairs in the same place all the way up, everything in them can be walked up to%s" % [made, "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 4))])


func _cells(rows: Array, ch: String) -> Array:
	var out := []
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == ch:
				out.append(Vector2i(x, y))
	return out


## The furniture, taps and generators no one can get to, walking in from `from`.
func _unreachable(rows: Array, from: Array) -> Array:
	var at := func(c: Vector2i) -> String:
		return rows[c.y][c.x] if c.y >= 0 and c.y < rows.size() and c.x >= 0 and c.x < rows[c.y].length() else "W"
	var seen := {}
	var queue := from.duplicate()
	for c in from:
		seen[c] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in World.DIRS:
			var n: Vector2i = c + d
			if not seen.has(n) and at.call(n) in WALK:
				seen[n] = true
				queue.append(n)
	var out := []
	for y in rows.size():
		for x in rows[y].length():
			var c := Vector2i(x, y)
			var ch: String = rows[y][x]
			if not (CityGen.PLAN_FURNITURE.has(ch) or ch in "bTQ"):
				continue
			var cells := [c]
			if ch == "b":
				if at.call(c + Vector2i.UP) == "b":
					continue  # (the foot of a bed: its head is checked, with the foot)
				if at.call(c + Vector2i.DOWN) == "b":
					cells.append(c + Vector2i.DOWN)
			if not cells.any(func(cc): return World.DIRS.any(func(d): return seen.has(cc + d))):
				out.append(c)
	return out


# --- In the city ------------------------------------------------------------------

func _in_game() -> void:
	SaveGame.wipe()
	seed(23)
	await host(9533)
	main.spawn_timer = 1e9
	main.survival._set_rain(false)
	main.survival.rain_t = 1e9
	var w: World = main.world
	var kinds := {}
	for b in w.buildings:
		kinds[b.kind] = kinds.get(b.kind, 0) + 1
	check(["hospital", "flats", "office", "mall", "market"].all(func(k): return kinds.has(k)),
			"Victory Monument has its hospitals, flats, offices, a mall and a market (%s)" % kinds)
	var hosp: Dictionary = w.buildings.filter(func(b): return b.kind == "hospital")[0]
	var top: int = hosp.floors - 1
	check(hosp.stairwells.size() >= 2 and hosp.stairwells.all(func(s): return w.top_storey(s) == top),
			"a hospital has %d floors, and stairs at both ends that go all the way up" % hosp.floors)
	var wards := w.containers.filter(func(c): return c.get("storey", 0) > 0 and hosp.rect.has_point(c.cell))
	check(wards.size() > 20 and wards.all(func(c): return c.table == "med" or c.table == "home"),
			"its floors are furnished (%d cupboards and beds up there), stocked like a hospital" % wards.size())
	var near_hosp: BuildingProp = w.building_nodes[hosp.id]
	check(w.wide.has(near_hosp) and w.wide[near_hosp].size() > 1, "a big building stays in the scene from any of its chunks")

	# Up the stairs, a floor at a time, to the roof; no jumping off it.
	var st: Vector2i = hosp.stairwells[0]
	me.position = w.to_pos(st)
	for f in range(1, top + 1):
		main.actions._do_action(me, {kind = "stairs", id = st}, "up")
	check(me.storey == top and not me.on_roof, "up the stairs floor by floor to the top one (%d)" % (me.storey + 1))
	main.actions._do_action(me, {kind = "stairs", id = st}, "up")
	check(me.on_roof and Interact.jump_spot(w, me.position) == Vector2.INF, "on to its roof, far too high to jump off")
	main.actions._do_action(me, {kind = "stairs", id = st}, "down")
	check(me.storey == top and not me.on_roof, "and back down to the top floor")

	# A zombie a floor below comes up by the nearer stairs.
	var other: Vector2i = hosp.stairwells[1]
	me.storey = 1
	me.position = w.to_pos(other)
	var z := zombie_at(w.to_pos(other) + Vector2(-20, 0))
	z.target = me
	z.repath = 0.0
	simulate(0.2)
	check(z.climb == other, "a zombie after you upstairs heads for the nearer stairs")
	z.hp = 0
	z.queue_free()
	main.zombies.erase(z.zid)
	me.storey = 0

	# The taps on every floor run from the building's big rooftop tank.
	var bid: int = hosp.id
	var taps_up := w.things.filter(func(t): return t.kind == "tap" and t.get("storey", 0) > 0 and Buildings.at(w, t.cell) == bid)
	check(not taps_up.is_empty(), "taps upstairs (%d)" % taps_up.size())
	check(Buildings.capacity(w, bid) > Buildings.TANK * 3, "a big roof holds a big tank (%.0f sips)" % Buildings.capacity(w, bid))

	# The generator.
	var gens := w.things.filter(func(t): return t.kind == "generator" and Buildings.at(w, t.cell) == bid)
	check(gens.size() == 1, "a generator in the plant room")
	var gen: Dictionary = gens[0]
	me.position = w.to_pos(gen.cell) + Vector2(0, 14)
	me.storey = 0
	main.things.set_state(gen.id, {fuel = 0.0, on = false, since = main.now()})
	var acts: Array = main.things.actions_for(me, gen.id)
	check(not Interact.find_action(acts, "start").ok, "no fuel, it won't start")
	main.inventory._give(me, "fuelcan")
	main.things.act(me, gen.id, "refuel")
	check(Crafting.count_in(me.inv, "fuelcan") == 0 and absf(main.things.gen_fuel(gen, main.now()) - Things.GEN_CAN) < 0.01,
			"a jerrycan of fuel in it: %.0f hours of running" % Things.GEN_CAN)
	var room: Vector2 = Vector2.INF
	for l in w.light_spots:
		if l.size() > 2 and l[2] == bid:
			room = l[0]
			break
	main.time = 0.95  # (the dead of night)
	w.is_night = true
	check(not w.is_lit(room), "at night, with no power, its rooms are dark")
	var zz := zombie_at(w.to_pos(gen.cell) + Vector2(150, 0))
	zz.target = null
	main.things.act(me, gen.id, "start")
	main.things.update_power()
	check(main.things.gen_running(gen, main.now()) and Buildings.powered(main, bid), "started: the building has power")
	check(w.powered.has(bid) and w.is_lit(room), "and its rooms are lit")
	check(zz.investigate_t > 0.0, "it's loud: a zombie a way off comes to see")
	# The pump sends the water under the building up to the roof.
	main.world_state.set_state("building", bid, {tank = 0.0, tank_at = main.rain_total})
	var cistern: float = main.world_state.state("building", bid).cistern
	main.things._radio_t = 0.0
	simulate(Main.HOUR * 0.5)
	main.things._radio_t = 0.0
	main.things.server_tick(0.0)
	check(Buildings.tank(main, bid) > 5.0 and main.world_state.state("building", bid).cistern < cistern,
			"the pump fills the roof tank from under the building (%.0f sips up)" % Buildings.tank(main, bid))

	# A fridge with power keeps the rice.
	var fridge := {}
	for c in w.containers:
		if c.kind == "fridge" and Buildings.at(w, c.cell) == bid:  # (the nurses' station's, upstairs)
			fridge = c
			break
	var rice := {id = "rice", n = 1, hp = 0, made = main.now()}
	var loose := rice.duplicate()
	if not fridge.is_empty():
		me.open_box = fridge.id
		main.inventory._open_box(me, fridge.id)
		main.inventory._ref_set(me, ["box", fridge.id, 0], rice)
	simulate(Main.HOUR * 2.0)
	check(not fridge.is_empty() and Items.age(rice, main.now()) < Items.age(loose, main.now()) * 0.5,
			"food in its fridge keeps (%.1f h old, out of it %.1f h)" % [Items.age(rice, main.now()) / Main.HOUR, Items.age(loose, main.now()) / Main.HOUR])
	main.inventory._ref_set(me, ["inv", 0], rice)
	check(not rice.has("cold_in") and rice.get("cold", 0.0) > 0.0, "taken out, the cold it had is kept")

	# It runs down by the clock.
	simulate(Main.HOUR * (Things.GEN_CAN - 2.5) + 5.0)
	main.things.update_power()
	check(not main.things.gen_running(gen, main.now()) and not Buildings.powered(main, bid) and not w.powered.has(bid),
			"out of fuel it stops by itself, the lights go out")

	# All of it saved.
	main.inventory._give(me, "fuelcan")
	main.things.act(me, gen.id, "refuel")
	main.things.act(me, gen.id, "start")
	main._save_all()
	await close_game()
	await host(9533, true)
	var g2: Dictionary = main.world.things[gen.id]
	check(main.things.gen_running(g2, main.now()) and Buildings.powered(main, bid), "a running generator is still running after a reload")
	SaveGame.wipe()
	await close_game()
