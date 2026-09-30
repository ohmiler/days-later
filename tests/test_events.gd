extends "res://tests/test_base.gd"
## The city's now-and-then events (data/events.cfg, Events): the table is
## sound; one starts near a survivor, calls the dead with its sound, the nearest
## survivor is told; a ringing phone ends when someone gets to it and leaves
## what was beside it; the lottery seller's tickets, and now and then gold.


func run() -> void:
	var bad := Events.problems()
	check(bad.is_empty(), "the event table is sound" + ("" if bad.is_empty() else ": " + "; ".join(bad)))
	check(Events.DEFS.size() >= 5, "at least five events (%d)" % Events.DEFS.size())
	await host(9549, false, true, 11)
	main.spawn_timer = 1e9
	Camp.safe_on = false
	var w: World = main.world
	# Somewhere on a street, away from the camp.
	var at := Vector2.ZERO
	for y in range(150, 170):
		for x in range(40, 380, 6):
			var p := w.to_pos(Vector2i(x, y))
			if w.get_tile(Vector2i(x, y)) == World.ROAD and not w.in_camp(p, 6):
				at = p
				break
		if at != Vector2.ZERO:
			break
	me.position = at
	# Every sound is one that can be played (made in code if there is no file).
	for id in Events.DEFS:
		if Events.DEFS[id].type == "sound":
			check(Sfx.stream(Events.DEFS[id].sound) != null, "%s has its sound" % id)
	# An ice-cream truck: starts on a road near, in the day, and the dead come to look.
	main.world.is_night = false
	var z := zombie_at(at + Vector2(200, 0))
	var id: String = main.events.start_one("icecream")
	check(id == "icecream" and main.events.active.size() == 1, "an ice-cream truck turns up (%s)" % id)
	var ev: Dictionary = main.events.active[0]
	check(ev.pos.distance_to(at) > 250.0 and w.get_tile(w.to_cell(ev.pos)) == World.ROAD, "on a road, well away from you")
	var p0: Vector2 = ev.pos
	main.events.server_tick(0.1)
	var moved := 0.0
	for i in 100:
		main.events.server_tick(0.1)
	moved = ev.pos.distance_to(p0)
	check(moved > 40.0, "and it drives along (%.0f px in 10 s)" % moved)
	# Night only at night.
	main.events.active.clear()
	main.world.is_night = false
	check(main.events.start_one("ding") == "", "a door chime in the dark doesn't come in the day")
	main.world.is_night = true
	check(main.events.start_one("ding") in ["", "ding"], "...at night it may")
	main.events.active.clear()
	# A phone: someone gets to it and it stops with something beside it.
	main.world.is_night = false
	for b in w.buildings:  # (beside a shophouse, so there's a home in earshot)
		if b.kind == "shop" and b.floors >= 2 and w.can_stand(w.to_pos(b.rect.get_center() + Vector2i(0, 15)), Player.RADIUS):
			me.position = w.to_pos(b.rect.get_center() + Vector2i(0, 15))
			break
	var ph: String = main.events.start_one("phone")
	check(ph == "phone", "a house phone rings somewhere near")
	if ph == "phone":
		var e2: Dictionary = main.events.active[0]
		me.position = e2.pos + Vector2(4, 0)
		var had := count(me, "snack") + count(me, "battery")
		main.events.server_tick(0.1)
		check(main.events.active.is_empty() and count(me, "snack") + count(me, "battery") > had, "it stops when someone gets to it, and there's something for them")
	# The lottery seller.
	me.position = at
	var n0: int = main.zombies.size()
	main.events.start_one("lotto")
	check(main.zombies.size() == n0 + 1, "a lottery seller shambles up")
	var seller: Zombie = main.zombies.values().filter(func(q): return q.has_meta("lotto"))[0]
	seller.hurt_by[1] = 50.0
	main.combat._kill_zombie(seller, 1.0)
	var tickets := 0
	for pu in main.pickups.values():
		if pu.item.id == "lotto":
			tickets += 1
	check(tickets >= 1, "it drops its tickets (%d)" % tickets)
