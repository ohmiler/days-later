extends "res://tests/test_base.gd"
## The refugee camp in Victory Monument's temple (Camp): where newcomers
## start, safe from the dead, the volunteer's starter things, the day's jobs
## from the notice board, and the soldiers on the gates.


func _thing(kind: String) -> Dictionary:
	for th in main.world.things:
		if th.kind == kind:
			return th
	return {}


func run() -> void:
	SaveGame.wipe()
	await host(9378)
	Camp.safe_on = true
	for z in main.zombies.values():
		z.queue_free()  # (any that came up while the game started, before the camp was safe)
	main.zombies.clear()
	main.spawn_timer = 1e9
	var w: World = main.world
	check(w.camps.size() == 1 and w.camps[0].name == "วัดชัยมงคล", "Victory Monument has its temple camp (%d)" % w.camps.size())
	if w.camps.is_empty():
		return
	var r: Rect2i = w.camps[0].rect
	check(r.has_point(w.spawn_cell) and w.in_camp(w.spawn_point()), "newcomers start inside it")
	check(w.in_camp(me.position), "and so did you")
	var vol := _thing("volunteer")
	var board := _thing("board")
	check(not vol.is_empty() and r.has_point(vol.cell) and not board.is_empty() and r.has_point(board.cell), "its volunteer and notice board are inside")
	check(main.camp.map_marks().size() == 1, "the map shows it")

	# The volunteer starts you off.
	main.quests.ensure(me)
	check(me.quests.active.has("intro_camp"), "a newcomer's first job: talk to the volunteer")
	me.inv.fill(null)
	me.position = w.to_pos(vol.cell) + Vector2(0, 12)
	me.aim = Vector2(0, -10)
	var t := Interact.target(main, me)
	check(t.get("kind") == "thing" and t.id == vol.id, "E points at the volunteer (%s)" % t.get("kind", "nothing"))
	main.actions.req_act("thing", vol.id, "talk")
	check(count(me, "water") == 1 and count(me, "bandage") == 2, "who hands over water and bandages (%s)" % bag(me))
	check(me.quests.done.has("intro_camp") and me.quests.active.has("intro_supplies"), "and the start goes on")
	main.actions.req_act("thing", vol.id, "talk")
	check(count(me, "bandage") == 2, "talking again gives advice, not more things")

	# The board: jobs once the start is done, two a day.
	check(main.quests.hand_out_daily(me) == "start", "no daily jobs before the start is done")
	for id in Quests.DEFS:
		if not Quests.DEFS[id].get("daily", false):
			me.quests.done[id] = true
			me.quests.active.erase(id)
	main.quests.server_tick(1.0)
	check(not me.quests.active.keys().any(func(id): return Quests.DEFS[id].get("daily", false)), "jobs don't turn up by themselves")
	me.position = w.to_pos(board.cell) + Vector2(0, 12)
	main.actions.req_act("thing", board.id, "jobs")
	var dailies: Array = me.quests.active.keys().filter(func(id): return Quests.DEFS[id].get("daily", false))
	check(dailies.size() == Quests.DAILY_COUNT, "the notice board hands out today's (%s)" % [dailies])
	check(main.quests.hand_out_daily(me) == "had", "once a day")

	# No zombie comes up in or near it.
	var outside := w.to_pos(Vector2i(r.get_center().x, r.end.y + 20))
	me.position = w.to_pos(r.get_center())
	for i in 300:
		main.survival._spawn_zombie()
	var bad: Array = main.zombies.values().filter(func(z): return w.in_camp(z.position, Camp.CLEAR))
	for b in bad:
		print("  (in camp: zid %d at %s, home %d)" % [b.zid, w.to_cell(b.position), b.home])
	check(not main.zombies.is_empty() and bad.is_empty(), "zombies come up round about, never in or by the camp (%d of %d)" % [bad.size(), main.zombies.size()])
	for z in main.zombies.values():
		z.queue_free()
	main.zombies.clear()

	# One after you loses you at the wall, and can't get in.
	me.position = w.to_pos(r.get_center() + Vector2i(0, 6))
	var z := zombie_at(w.to_pos(Vector2i(r.get_center().x, r.end.y + 1)))
	z.target = me
	main.camp._t = 1e9  # (the soldiers hold their fire a moment)
	simulate(3.0)
	check(z.target == null and not w.in_camp(z.position), "it stops at the gate: you're out of its reach (%s)" % [w.to_cell(z.position)])
	main.camp._t = 0.0
	simulate(0.2)
	check(not main.zombies.has(z.zid), "and the soldiers on the gate shoot it")
	var far := zombie_at(outside + Vector2(0, 200))
	simulate(3.0)
	check(main.zombies.has(far.zid), "ones further off they leave alone")
