extends "res://tests/test_base.gd"
## Big buildings aren't empty: the zombies shut in them since the outbreak are
## there, on its floors, dressed for the place, when someone comes near; they
## go back to waiting when everyone leaves, and only killing them thins them out.


func run() -> void:
	SaveGame.wipe()
	seed(31)
	await host(9541)
	Survival.trapped_on = true
	main.spawn_timer = 1e9
	var w: World = main.world
	var hosp: Dictionary = w.buildings.filter(func(b): return b.kind == "hospital")[0]
	var bid: int = hosp.id
	var n: int = main.world_state.state("building", bid).trapped
	check(n >= 2 and n <= Buildings.TRAPPED_MAX, "a hospital has zombies shut in it (%d)" % n)
	check(w.buildings.filter(func(b): return not b.get("big", false)).all(func(b): return Buildings.start(w, b.id).trapped == 0),
			"shophouses have none of their own")

	# Far off: nobody let out.
	var far := Vector2(-1e5, -1e5)
	me.position = far
	main.survival._trapped_t = 0.0
	main.survival._tick_trapped(0.0)
	var inside := func() -> Array: return main.zombies.values().filter(func(z): return z.home == bid and not z.is_boss())  # (its boss, if it is the lair, is test_boss's)
	check(inside.call().is_empty(), "nobody near: they stay a number")

	# Up to its door: they're in there.
	var r: Rect2i = hosp.rect
	me.position = w.to_pos(Vector2i(r.get_center().x, r.end.y + 2))
	main.survival._trapped_t = 0.0
	main.survival._tick_trapped(0.0)
	var zs: Array = inside.call()
	check(zs.size() == n, "come near and all %d are inside (%d)" % [n, zs.size()])
	check(zs.all(func(z): return r.has_point(w.to_cell(z.position)) and not w.is_solid_on(w.to_cell(z.position), z.storey)),
			"each stands somewhere inside it")
	check(zs.any(func(z): return z.storey > 0), "some are upstairs, on the wards")
	var dressed := zs.filter(func(z): return Items.ZOMBIE_PLACES[z.zid % Items.ZOMBIE_PLACES.size()] == "hospital").size()
	check(dressed == zs.size(), "dressed for a hospital (%d of %d)" % [dressed, zs.size()])

	# Kill one: one fewer, for good.
	main.combat._kill_zombie(zs[0], 0.0)
	check(main.world_state.state("building", bid).trapped == n - 1, "killing one leaves %d" % (n - 1))

	# Walk away: they go back to waiting, and come back when you do.
	me.position = far
	for z in inside.call():
		z.target = null
	main.survival._trapped_t = 0.0
	main.survival._tick_trapped(0.0)
	await frames(1)
	check(inside.call().is_empty(), "everyone gone: back to a number")
	me.position = w.to_pos(Vector2i(r.get_center().x, r.end.y + 2))
	main.survival._trapped_t = 0.0
	main.survival._tick_trapped(0.0)
	check(inside.call().size() == n - 1, "back again: the %d left are still in there" % (n - 1))

	# The count is kept in a save.
	check(main.world_state.changed().get("building", {}).get(bid, {}).get("trapped", -1) == n - 1, "the number is saved with the building")
	Survival.trapped_on = false
	SaveGame.wipe()
	await close_game()
