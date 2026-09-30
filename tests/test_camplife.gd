extends "res://tests/test_base.gd"
## The camp's people and things (CampLife): laid out the same on every
## machine, solid where they stand, and never in the way of the spawn, the
## volunteer, the board or the gates.


func run() -> void:
	var a := _world(11)
	var b := _world(11)
	check(not a.camps.is_empty(), "the zone has a camp")
	check(a.camp_life.size() > 20, "the camp is lived in (%d things)" % a.camp_life.size())
	check(str(a.camp_life) == str(b.camp_life), "laid out the same on every machine")
	var kinds := {}
	for rec in a.camp_life:
		kinds[rec.kind] = kinds.get(rec.kind, 0) + 1
	check(kinds.get("tent", 0) >= 4 and kinds.get("person", 0) >= 6 and kinds.get("soldier", 0) >= 4 and kinds.get("fire", 0) >= 1,
			"tents, people, soldiers, a fire (%s)" % str(kinds))
	var sat := a.camp_life.filter(func(r): return r.kind == "person")
	check(sat.all(func(r): return a.is_solid(r.cell)), "you can't walk through someone")
	check(a.can_stand(a.to_pos(a.spawn_cell), Player.RADIUS), "the spawn is clear")
	for t in a.things:
		if t.kind in ["volunteer", "board"]:
			var c: Vector2i = t.cell
			check(not a.is_solid(c + Vector2i.DOWN) or not a.is_solid(c + Vector2i.LEFT) or not a.is_solid(c + Vector2i.RIGHT), "the %s can be reached" % t.kind)
	var r: Rect2i = a.camps[0].rect
	var mid := r.get_center()
	var clear := true
	for y in range(r.position.y, r.end.y):
		if a.blocked.has(Vector2i(mid.x, y)) and a.camp_life.any(func(q): return q.cell == Vector2i(mid.x, y)):
			clear = false
	check(clear, "the way in from the gates is clear")
	# A path from the south gate to the volunteer.
	var vol = a.things.filter(func(t): return t.kind == "volunteer")
	if not vol.is_empty():
		var path := a.path_between(a.to_pos(Vector2i(mid.x, r.end.y + 1)), a.to_pos(vol[0].cell + Vector2i.DOWN))
		check(not path.is_empty(), "from the gate you can walk to the volunteer")
	a.queue_free()
	b.queue_free()


func _world(seed_val: int) -> World:
	var w := World.new()
	w.prop_parent = root
	root.add_child(w)
	w.generate(seed_val, "victory")
	return w
