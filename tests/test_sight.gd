extends "res://tests/test_base.gd"
## What your character can see (Sight): the way you face, not through walls,
## and close by all round; the grid line of sight it's built on. (Who is out
## of sight fades away; the city is always shown.)


func run() -> void:
	await host(9311)
	var w: World = main.world
	var s: Sight = main.sight
	# A clear line along the street from the spawn corner.
	me.position = w.to_pos(w.spawn_cell)
	var open_dir := Vector2.ZERO
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if w.sight_ray(me.position + Vector2(0, -2), dir, 120.0)[0] >= 120.0 \
				and w.sight_ray(me.position + Vector2(0, -2), -dir, 60.0)[0] >= 60.0:
			open_dir = dir
			break
	check(open_dir != Vector2.ZERO, "found a street to look along")
	me.aim = open_dir * 50.0
	s.on = 1.0
	s.update(me, 0.016, 400.0)
	s.eye = me.position + Vector2(0, -2)
	s.facing = open_dir.angle()
	check(s.sees(s.eye + open_dir * 100.0), "you see down the street the way you face")
	check(not s.sees(s.eye - open_dir * 50.0), "but not what is behind you")
	check(s.sees(s.eye - open_dir * 15.0), "right behind you, you know it's there")
	check(s.sees(s.eye + open_dir.orthogonal() * 12.0), "or beside you")

	# Walls stop it: a room inside a shophouse, seen from the street through its
	# front wall (not its door or glass shop window, which you can see through).
	var inside := Vector2.INF
	var out := Vector2.INF
	for b in w.buildings:
		if b.kind != "shop":
			continue
		var r: Rect2i = b.rect
		var front := r.end.y - 1
		for x in range(r.position.x + 1, r.end.x - 1):
			if w.get_tile(Vector2i(x, front)) == World.IWALL and w.get_tile(Vector2i(x, front - 1)) == World.FLOOR 					and w.get_tile(Vector2i(x, front + 2)) in [World.SIDEWALK, World.ROAD, World.SOI]:
				inside = w.to_pos(Vector2i(x, front - 1))
				out = w.to_pos(Vector2i(x, front + 2))
				break
		if inside != Vector2.INF:
			break
	check(inside != Vector2.INF, "found a room behind a shop's front wall")
	s.eye = out
	s.facing = (inside - out).angle()
	check(w.sight_ray(out, (inside - out).normalized(), out.distance_to(inside))[0] < out.distance_to(inside) - 6.0,
			"a closed shop's walls block the line from the street")
	check(not s.sees(inside), "so you don't see who is inside")

	# The ray itself: through open ground to its full length, stopped by a building.
	var r: Array = w.sight_ray(s.eye, (inside - out).normalized(), 2000.0)
	check(r[1] != Vector2i(-1, -1) and w.get_tile(r[1]) in [World.IWALL, World.WALL, World.BUILDING, World.DOOR],
			"a line of sight stops at the first wall (%s)" % [r])

	# Up on a roof, or dead, the shade goes and you see everything.
	me.on_roof = true
	for i in 30:
		s.update(me, 0.05, 400.0)
	check(s.on == 0.0 and s.sees(s.eye - open_dir * 200.0), "up on the roofs you see everyone")
	me.on_roof = false
