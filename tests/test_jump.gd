extends "res://tests/test_base.gd"
## Space at a run: a running jump. Over something low (sandbags, a bin, a car's
## bonnet) to the ground beyond; a leap on open ground; never through a wall.


func run() -> void:
	SaveGame.wipe()
	seed(4)
	await host(9507)
	main.spawn_timer = 1e9
	var w: World = main.world
	w.is_low(Vector2i.ZERO)  # (works out the low cells)
	check(not w._low.is_empty(), "the city has low things to jump over (%d cells)" % w._low.size())

	# Something low with clear ground either side of it.
	var spot := {}
	for c: Vector2i in w._low:
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var before := w.to_pos(c - d * 2)
			var beyond := w.to_pos(c + d * 2)
			if w.can_stand(before, Player.RADIUS) and w.can_stand(beyond, Player.RADIUS) and not w.is_solid(c + d) \
					and not w.is_solid(c - d):
				spot = {cell = c, dir = Vector2(d)}
				break
		if not spot.is_empty():
			break
	check(not spot.is_empty(), "found one to try")
	if spot.is_empty():
		await close_game()
		return
	var c: Vector2i = spot.cell
	var dir: Vector2 = spot.dir
	me.position = w.to_pos(c) - dir * World.TILE * 1.2
	me.move = dir
	me.stamina = 100.0
	main.actions.req_jump()
	check(me.vaulting(), "Space at a run: up and over")
	check(me.stamina < 100.0, "a jump takes breath")
	simulate(1.2)
	var past := (me.position - w.to_pos(c)).dot(dir)
	check(past > World.TILE * 0.6 and not me.vaulting(), "landed on the far side (%.0f px past)" % past)
	check(w.can_stand(me.position, Player.RADIUS), "on clear ground")

	# Open ground: a leap forward.
	var from := me.position
	me.move = dir
	main.actions.req_jump()
	if me.vaulting():
		simulate(1.2)
		check(me.position.distance_to(from) >= Actions.HOP - 1.0, "on open ground, a leap (%.0f px)" % me.position.distance_to(from))

	# Never through a wall.
	var wall := {}
	for y in range(10, World.H - 10):
		for x in range(10, World.W - 10):
			var cc := Vector2i(x, y)
			if w.is_solid(cc) and not w.is_low(cc) and w.is_solid(cc + Vector2i.UP) and not w.door_at.has(cc) \
					and w.can_stand(w.to_pos(cc + Vector2i.DOWN), Player.RADIUS):
				wall = {cell = cc}
				break
		if not wall.is_empty():
			break
	check(not wall.is_empty(), "found a wall to try")
	if not wall.is_empty():
		me.position = w.to_pos(wall.cell + Vector2i.DOWN)
		me.move = Vector2.UP
		me.stamina = 100.0
		main.actions.req_jump()
		check(not me.vaulting() and me.stamina == 100.0, "no jumping through a building")

	# Too tired: no jump.
	me.position = from
	me.stamina = 3.0
	main.actions.req_jump()
	check(not me.vaulting(), "out of breath, no jump")

	await close_game()
