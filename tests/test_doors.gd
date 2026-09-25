extends "res://tests/test_base.gd"
## Doors and windows: open, shut, never on someone, boarding, smashing glass.


func run() -> void:
	await host(9306)
	var w: World = main.world
	var door := -1
	var window := -1
	for d in w.doors:
		if door < 0 and d.kind == "door" and not d.broken:
			door = d.id
		if window < 0 and d.kind == "window" and d.closed and not d.broken and d.boards == 0:
			window = d.id
	var dd: Dictionary = w.doors[door]
	var at := w.to_pos(dd.cell)

	# Toggle it from just outside.
	me.position = at + Vector2(0, 14)
	var was: bool = dd.closed
	main._toggle_door(me, door)
	check(dd.closed != was, "E opens or shuts a door")
	main._toggle_door(me, door)
	check(dd.closed == was, "and back again")

	# Standing in the doorway, it will not shut on you.
	if dd.closed:
		main._toggle_door(me, door)
	me.position = at
	main._toggle_door(me, door)
	check(not dd.closed, "a door will not close on someone standing in it")

	# Boarding needs wood.
	me.position = at + Vector2(0, 14)
	main._toggle_door(me, door)
	me.inv.fill(null)
	var b0: int = dd.boards
	main._reinforce(me, door)
	check(dd.boards == b0, "no wood, no boards")
	main._give(me, "wood")
	main._reinforce(me, door)
	check(dd.boards == b0 + 1, "a plank adds a board (%d)" % dd.boards)
	check(count(me, "wood") == 0, "and uses the plank")

	# Glass smashes, and it is loud.
	var wd: Dictionary = w.doors[window]
	var z := zombie_at(w.to_pos(wd.cell) + Vector2(60, 40))
	me.position = w.to_pos(wd.cell) + Vector2(0, 14)
	main._toggle_door(me, window)
	check(wd.broken and not wd.closed, "smashing a window breaks it open")
	check(z.investigate_t > 0.0 or z.target != null, "the noise brings a zombie to look")
