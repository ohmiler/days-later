extends "res://tests/test_base.gd"
## The story chapters (data/quests.cfg, `story = true`): after the first night
## the camp radio sends you to a pharmacy, then the hospital and its sergeant,
## then the police station and its chief; being inside a kind of building (or a
## shop with a sign) counts as a visit; the everyday jobs don't wait for it.


func _tick() -> void:
	main.quests._t = 0.0
	main.quests.server_tick(0.1)


func _stand_in(pred: Callable) -> bool:
	for b in main.world.buildings:
		if pred.call(b):
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var p: Vector2 = main.world.to_pos(b.rect.get_center() + Vector2i(dx, dy))
					if main.world.can_stand(p, Player.RADIUS) and main.world.building_at.get(main.world.to_cell(p)) != null:
						me.position = p
						return true
	return false


func run() -> void:
	check(Quests.problems().is_empty(), "the quest table is sound " + str(Quests.problems()))
	check(Quests.DEFS.intro_night.next == "story_1" and Quests.DEFS.story_1.next == "story_2" and Quests.DEFS.story_2.next == "story_3", "the first night leads into three chapters")
	SaveGame.wipe()
	await host(9548, false, true, 11)
	main.spawn_timer = 1e9
	Camp.safe_on = false
	for id in Quests.DEFS:
		if not Quests.DEFS[id].get("daily", false) and not Quests.DEFS[id].get("story", false):
			me.quests.done[id] = true
	me.quests.active.clear()
	check(main.quests._start_done(me), "the everyday jobs don't wait for the story")
	main.quests.start(me, "story_1")
	me.position = main.world.to_pos(main.world.spawn_cell)
	_tick()
	check(me.quests.active.story_1[0] == 0, "not at a pharmacy yet: no visit")
	check(_stand_in(func(b): return b.get("sign", "") == "ร้านขายยา"), "found a pharmacy to stand in")
	_tick()
	check(me.quests.active.story_1[0] == 1, "inside it: that counts as a visit to the pharmacy")
	main.quests.note(me, "search", {}, 4)
	_tick()
	check(me.quests.done.has("story_1") and me.quests.active.has("story_2"), "four searches and the first chapter is done: the hospital is next")
	check(_stand_in(func(b): return b.kind == "hospital"), "found a hospital")
	_tick()
	check(me.quests.active.story_2[0] == 1, "inside the hospital: a visit")
	main.quests.note(me, "kill", {kind = "normal"})
	check(me.quests.active.story_2[1] == 0, "an ordinary zombie isn't the sergeant")
	main.quests.note(me, "kill", {kind = "sergeant"})
	_tick()
	check(me.quests.done.has("story_2") and me.quests.active.has("story_3"), "the sergeant down: the police station is next")
	check(_stand_in(func(b): return b.kind == "police"), "found the police station")
	_tick()
	main.quests.note(me, "kill", {kind = "chief"})
	_tick()
	check(me.quests.done.has("story_3") and me.quests.active.is_empty(), "the chief down: the story so far is done")
	# Up on a roof is not inside.
	main.quests.start(me, "story_1")
	me.quests.done.erase("story_1")
	_stand_in(func(b): return b.get("sign", "") == "ร้านขายยา")
	me.on_roof = true
	_tick()
	check(me.quests.active.story_1[0] == 0, "on the roof is not a visit")
