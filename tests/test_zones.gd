extends "res://tests/test_base.gd"
## Zones: the city is split into maps joined at their edges. At a way out, E
## takes you (and, playing with friends, the group) to the next zone, coming
## in by its way in, at the same hour; each zone keeps its own changes; a
## reload carries on in the zone you were in.


func _exit(id: String) -> Dictionary:
	for e in main.world.exits:
		if e.id == id:
			return e
	return {}


func run() -> void:
	SaveGame.wipe()
	seed(21)
	await host(9500)
	var first := Zones.first()
	check(main.zone == first and main.world.zone == first, "a new game starts in the first zone (%s)" % first)
	check(World.W * World.H <= 400 * 320, "a zone is a manageable size (%d x %d)" % [World.W, World.H])
	var east := _exit("ratchaprarop")
	check(not east.is_empty() and east.to == "pratunam", "it has a way out down Ratchaprarop, to Pratunam")
	var shut := _exit("north")
	var tn := {kind = "exit", id = "north"}
	check(not shut.is_empty() and not Interact.actions(main, me, tn).any(func(a): return a.verb == "travel" and a.ok),
			"a way out to a zone not made yet has its sign, but no way through")

	# Something changed here, to find again on the way back.
	var door := -1
	for d in main.world.doors:
		if d.kind == "door" and not d.broken:
			door = d.id
			break
	var was: bool = main.world.doors[door].closed
	main.doors._toggle_door(me, door)

	# At the way out, E offers the way on.
	var r: Rect2i = east.rect
	me.position = main.world.to_pos(r.position + r.size / 2)
	var t := {}
	for c in Interact._candidates(main, me):
		if c.kind == "exit":
			t = c
	check(not t.is_empty() and Interact.actions(main, me, t).any(func(a): return a.verb == "travel"),
			"at the way out, E offers to go on (%s)" % t.get("title", "nothing"))
	main.day = 3
	main.time = 0.4
	main.actions._do_action(me, t, "travel")
	check(main.zone == "pratunam" and main.world.zone == "pratunam", "through it: now in Pratunam")
	check(main.day == 3 and absf(main.time - 0.4) < 0.01, "at the same hour of the same day")
	var west := _exit("north")
	check(not west.is_empty() and me.position.distance_to(main.world.to_pos(west.rect.get_center())) < 120.0
			and main.world.can_stand(me.position, Player.RADIUS), "coming in by its way in (from the north)")
	check(me.world == main.world, "your body is in the new zone")
	check(FileAccess.file_exists(SaveGame.dir() + "/zones/" + first + "/world.save"), "the zone left behind was saved")

	# And back again: that zone as it was left.
	me.position = main.world.to_pos(west.rect.position + west.rect.size / 2)
	main.actions._do_action(me, {kind = "exit", id = "north"}, "travel")
	check(main.zone == first, "back the way you came")
	check(main.world.doors[door].closed != was, "the zone is as it was left (the door still as you left it)")
	check(me.position.distance_to(main.world.to_pos(_exit("ratchaprarop").rect.get_center())) < 120.0, "coming in up Ratchaprarop")

	# Go on again, save, reload: it carries on where you were.
	me.position = main.world.to_pos(_exit("ratchaprarop").rect.get_center())
	main.actions._do_action(me, {kind = "exit", id = "ratchaprarop"}, "travel")
	var at := me.position
	main._save_all()
	await close_game()
	await host(9501, true, false)
	check(main.zone == "pratunam", "a reload carries on in the zone you were in")
	check(me.position.distance_to(at) < 1.0, "right where you were")
	await close_game()
	SaveGame.wipe()
