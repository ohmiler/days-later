extends "res://tests/test_base.gd"
## V: down on hands and knees. Crawling is slow and silent, zombies hardly see
## you, and you fit under a bus or a truck, where they don't see you at all
## unless right beside you. You can't get up under there, or fight lying down.


func run() -> void:
	SaveGame.wipe()
	seed(6)
	await host(9508)
	main.spawn_timer = 1e9
	var w: World = main.world

	main.actions.req_prone()
	check(me.prone, "V: down on all fours")
	check(me.speed_mult() < 0.5, "crawling is slow (%.2f)" % me.speed_mult())
	me.set_attack_input(true, false)
	check(not me.wants_punch(), "no punching lying down")
	me.set_attack_input(false, false)

	# Hard to spot: a zombie facing you sees you standing, not crawling.
	me.position = me.position
	var z := zombie_at(me.position + Vector2(70, 0))
	z.facing = PI
	me.prone = false
	var seen_up: bool = z._nearest_player() == me
	me.prone = true
	var seen_down: bool = z._nearest_player() == me
	check(seen_up and not seen_down, "a zombie 70 px off sees you standing, not crawling (%s / %s)" % [seen_up, seen_down])
	z.queue_free()
	main.zombies.erase(z.zid)

	# Under a bus or a truck.
	w.is_under(Vector2i.ZERO)
	check(not w._under.is_empty(), "there are things to crawl under (%d cells)" % w._under.size())
	var spot := {}
	for c: Vector2i in w._under:
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if w.can_stand(w.to_pos(c + d), Player.RADIUS) and not w.is_under(c + d):
				spot = {cell = c, out = c + d}
				break
		if not spot.is_empty():
			break
	check(not spot.is_empty(), "found one to try")
	if not spot.is_empty():
		var into: Vector2 = w.to_pos(spot.cell) - w.to_pos(spot.out)
		me.prone = false
		me.position = w.to_pos(spot.out)
		me.move = into.normalized()
		simulate(1.5)
		check(not w.is_under(w.to_cell(me.position)), "standing, you can't walk under it")
		me.position = w.to_pos(spot.out)
		main.actions.req_prone()
		simulate(0.2)
		for i in 60:
			if w.to_cell(me.position) == spot.cell:
				break
			simulate(0.05)  # (in, not out the far side)
		me.move = Vector2.ZERO
		check(me.under_vehicle(), "crawling, you get under it (at %s, cell %s, bus cell %s, from %s)" % [me.position, w.to_cell(me.position), spot.cell, spot.out])
		var z2 := zombie_at(w.to_pos(spot.out) + into.normalized() * -40.0)
		z2.facing = into.angle()
		check(z2._nearest_player() != me, "under there, a zombie a few steps off doesn't see you")
		main.actions.req_prone()
		check(me.prone, "and you can't stand up under a bus")
		# Half out, the body still under the edge: still no room to stand.
		me.position = w.to_pos(spot.out) + into.normalized() * (World.TILE * 0.5 - 2.0)
		check(w.to_cell(me.position) == spot.out and me.under_vehicle(), "half out from under it, you're still under it")
		main.actions.req_prone()
		check(me.prone, "and still can't stand up")
		me.position = w.to_pos(spot.out) - into.normalized() * 4.0
		main.actions.req_prone()
		check(not me.prone, "right out, you can stand up again")

	await close_game()
