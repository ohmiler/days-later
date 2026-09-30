extends "res://tests/test_base.gd"
## Walls are thin down the middle of their cells (the 3D view draws them so):
## you walk right up to one, not through it; a blow or a look along your own
## side of a wall isn't stopped by the wall's cell, one across it is.


func run() -> void:
	var w := World.new()
	w.prop_parent = root
	root.add_child(w)
	w.generate(11, "victory")
	# A straight bit of wall inside a building, running up and down, rooms either side.
	var c := Vector2i(-1, -1)
	for y in range(1, World.H - 1):
		for x in range(1, World.W - 1):
			var q := Vector2i(x, y)
			if w.get_tile(q) == World.IWALL and w.get_tile(q + Vector2i.UP) == World.IWALL and w.get_tile(q + Vector2i.DOWN) == World.IWALL \
					and w.get_tile(q + Vector2i.LEFT) == World.FLOOR and w.get_tile(q + Vector2i.RIGHT) == World.FLOOR and not w.door_at.has(q):
				c = q
				break
		if c.x >= 0:
			break
	check(c.x >= 0, "found a wall between two rooms")
	if c.x < 0:
		return
	var mid := w.to_pos(c)
	var r := Player.RADIUS
	check(w.is_thin_wall(c), "an inside wall is a thin one")
	check(w.can_stand(mid + Vector2(-(r + World.WALL_HALF + 0.5), 0), r), "you can stand right up against it, in its cell")
	check(not w.can_stand(mid, r), "not in the wall itself")
	check(not w.can_stand(mid + Vector2(-(r + World.WALL_HALF - 0.5), 0), r), "not overlapping it")
	# Walking into it stops at the wall line.
	var p := w.to_pos(c + Vector2i.LEFT)
	for i in 60:
		p = w.slide(p, Vector2(1.0, 0.0), r)
	check(p.x < mid.x - World.WALL_HALF and p.x > mid.x - World.WALL_HALF - r - 1.5, "walking at it stops against it (%.1f px short of the middle)" % (mid.x - p.x))
	# Seeing and hitting.
	var near := mid + Vector2(-(r + World.WALL_HALF + 0.5), 0)
	var far := w.to_pos(c + Vector2i.LEFT * 2)
	var across := mid + Vector2(r + World.WALL_HALF + 0.5, 0)
	check(not w.line_hits_wall(c, far, near), "a line along your side of the wall misses it")
	check(w.line_hits_wall(c, far, across), "a line across it hits it")
	var seen: Array = w.sight_ray(far, (near - far).normalized(), far.distance_to(near))
	check(seen[1] == Vector2i(-1, -1), "you can see someone standing against the wall on your side")
	var blocked: Array = w.sight_ray(far, (across - far).normalized(), far.distance_to(across))
	check(blocked[1] == c, "but not through it")
	w.queue_free()
