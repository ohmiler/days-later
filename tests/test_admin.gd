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
	a.req_time(0.85)
	check(absf(main.time - 0.85) < 0.001, "sets the time")
	me.peer_id = 5  # someone who isn't the host
	a.req_give("axe", 1)
	check(count(me, "axe") == 1, "nobody but the host gets anything")
	me.peer_id = 1
