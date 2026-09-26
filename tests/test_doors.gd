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
	main.doors._toggle_door(me, door)
	check(dd.closed != was, "E opens or shuts a door")
	main.doors._toggle_door(me, door)
	check(dd.closed == was, "and back again")

	# Standing in the doorway, it will not shut on you.
	if dd.closed:
		main.doors._toggle_door(me, door)
	me.position = at
	main.doors._toggle_door(me, door)
	check(not dd.closed, "a door will not close on someone standing in it")

	# Boarding needs wood.
	me.position = at + Vector2(0, 14)
	main.doors._toggle_door(me, door)
	me.inv.fill(null)
	var b0: int = dd.boards
	main.doors._reinforce(me, door)
	check(dd.boards == b0, "no wood, no boards")
	main.inventory._give(me, "wood")
	main.doors._reinforce(me, door)
	check(dd.boards == b0 + 1, "a plank adds a board (%d)" % dd.boards)
	check(count(me, "wood") == 0, "and uses the plank")

	# Glass smashes, and it is loud.
	var wd: Dictionary = w.doors[window]
	var z := zombie_at(w.to_pos(wd.cell) + Vector2(60, 40))
	me.position = w.to_pos(wd.cell) + Vector2(0, 14)
	main.doors._toggle_door(me, window)
	check(wd.broken and not wd.closed, "smashing a window breaks it open")
	check(z.investigate_t > 0.0 or z.target != null, "the noise brings a zombie to look")

	# A shop's rolling shutter: all of it goes up or down at once, loudly; it
	# blocks the way and the view; a zombie can bend a section up to crawl under.
	var sh: Dictionary = {}
	for d in w.doors:
		if d.kind == "shutter" and not d.broken and d.group.all(func(i): return not w.doors[i].broken):
			sh = d
			break
	check(not sh.is_empty(), "shops have rolling shutters")
	var group: Array = sh.group
	var sat := w.to_pos(sh.cell)
	me.position = sat + Vector2(0, 14)
	if not sh.closed:
		main.doors._toggle_door(me, sh.id)
	check(group.all(func(i): return w.doors[i].closed), "pulled down, the whole front is shut")
	check(not w.can_stand(sat, 4.0) and w.sight_ray(sat + Vector2(0, 20), Vector2.UP, 40.0)[0] < 30.0,
			"a shut shutter blocks the way and the view")
	var z2 := zombie_at(sat + Vector2(90, 30))
	main.doors._toggle_door(me, sh.id)
	check(group.all(func(i): return not w.doors[i].closed), "E lifts the whole shutter")
	check(z2.investigate_t > 0.0 or z2.target != null, "and the racket carries")
	check(Interact.actions(main, me, {kind = "door", id = sh.id}).all(func(a): return a.verb != "board"),
			"a shutter isn't boarded like a door")
	main.doors._toggle_door(me, sh.id)
	for i in 40:
		main.doors.damage_door(sh.id, 12.0)
	check(sh.broken and not sh.closed, "pounded long enough, a section bends up (%d hp)" % sh.hp)
	check(group.filter(func(i): return i != sh.id).all(func(i): return w.doors[i].closed), "the rest stays down")
	check(w.slow_at(sat) < 1.0, "and you crawl through the gap, slowly")
