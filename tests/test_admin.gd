extends "res://tests/test_base.gd"
## The developer panel's server side: conjuring items, healing, zombies of a
## chosen kind, clearing them, the time. Only the host may use it.


func run() -> void:
	await host(9420)
	var a: Admin = main.admin
	me.inv.fill(null)
	a.req_give("axe", 1)
	a.req_give("water", 10)
	check(count(me, "axe") == 1 and count(me, "water") == 10, "conjures items into the bag (%s)" % bag(me))
	me.hp = 20.0
	me.infection = 50.0
	Body.add(me, "bite", "arms", true)
	a.req_heal()
	check(me.hp == 100.0 and me.infection == 0.0 and me.wounds.is_empty() and not me.bleeding, "heals everything")
	var before: int = main.zombies.size()
	a.req_zombie(me.position + Vector2(40, 0), "fat")
	var fat: Array = main.zombies.values().filter(func(z): return z.kind == "fat" and z.position.distance_to(me.position + Vector2(40, 0)) < 1.0)
	check(main.zombies.size() == before + 1 and not fat.is_empty(), "brings a zombie of the kind asked for")
	a.req_clear(200.0)
	check(main.zombies.values().all(func(z): return z.position.distance_to(me.position) >= 200.0), "clears the zombies nearby")
	for k in Zombie.KINDS:
		a.req_zombie(me.position + Vector2(0, 60), k, 3)
		check(main.zombies.values().filter(func(z): return z.kind == k).size() >= 3, "three of every kind: " + k)
		a.req_clear(1e9)
	a.req_zombie(me.position + Vector2(0, 60), "", 1, true)
	check(main.zombies.values().any(func(z): return z.wear.values().any(func(w): return Items.def(Items.base_id(w)).get("special", false))),
			"one in a rare costume")
	a.req_clear(1e9)
	a.req_zombie(me.position + Vector2(60, 0), "normal", 1, false, true)
	var dz: Zombie = main.zombies.values().filter(func(q): return q.dummy)[0]
	var dp := dz.position
	var df := dz.facing
	simulate(2.0)
	check(dz.position == dp and dz.facing == df and dz.target == null, "a practice dummy stands still, its back to you")
	me.sneak = true
	check(Combat.can_backstab(me, dz, "knife"), "and can be crept up on")
	me.sneak = false
	a.req_clear(1e9)
	a.req_toggle("god")
	var hp := me.hp
	me.bite(30.0, "arms")
	check(me.god and me.hp == hp, "god mode: nothing hurts")
	a.req_toggle("god")
	a.req_toggle("freeze")
	var z := zombie_at(me.position + Vector2(60, 0))
	var zp := z.position
	simulate(1.0)
	check(a.frozen and z.position == zp, "zombies frozen stand still")
	a.req_toggle("freeze")
	a.req_clear(1e9)
	for k in Body.KINDS:
		a.req_self("wound", k)
	check(Body.KINDS.keys().all(func(k): return me.wounds.any(func(w): return w.kind == k)), "every kind of wound, to try")
	for k in Body.CONDITIONS:
		a.req_self("condition", k)
	check(Body.CONDITIONS.keys().all(func(k): return me.conditions.has(k)), "every condition, to try")
	a.req_self("cure", "")
	check(me.wounds.is_empty() and me.conditions.is_empty(), "and all gone again")
	var day: int = main.day
	a.req_skip(24.0)
	check(main.day == day + 1, "skips a day")
	var rain: bool = main.raining
	a.req_toggle("rain")
	check(main.raining != rain, "rain on or off")
	a.req_goto("hospital")
	var hosp: Array = main.world.buildings.filter(func(b): return b.kind == "hospital")
	check(hosp.is_empty() or Rect2(Vector2(hosp[0].rect.position - Vector2i(4, 4)) * World.TILE, Vector2(hosp[0].rect.size + Vector2i(8, 8)) * World.TILE)
			.has_point(me.position) or hosp.any(func(b): return Rect2(Vector2(b.rect.position - Vector2i(4, 4)) * World.TILE,
			Vector2(b.rect.size + Vector2i(8, 8)) * World.TILE).has_point(me.position)), "goes to a hospital")
	a.req_time(0.85)
	check(absf(main.time - 0.85) < 0.001, "sets the time")
	me.peer_id = 5  # someone who isn't the host
	a.req_give("axe", 1)
	check(count(me, "axe") == 1, "nobody but the host gets anything")
	me.peer_id = 1
