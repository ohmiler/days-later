extends "res://tests/test_base.gd"
## Quests (data/quests.cfg): a new survivor starts the start, a quest at a
## time, each done by doing what it asks; rewards; then two everyday tasks a
## day. Counted per survivor, kept in the save.


func _tick() -> void:
	main.quests._t = 0.0
	main.quests.server_tick(0.1)


func run() -> void:
	check(Quests.problems().is_empty(), "the quest table is sound " + str(Quests.problems()))
	check(Quests.first_id() == "intro_camp", "the first quest is the start: the refugee camp's volunteer")

	SaveGame.wipe()
	await host(9547)
	main.spawn_timer = 1e9
	me.inv.fill(null)
	me.worn.erase("hand_r")
	me.worn.erase("hand_l")
	me.refresh_wear()
	_tick()
	check(me.quests.active.has("intro_camp"), "a new survivor gets the first quest")
	main.quests.note(me, "talk", {kind = "volunteer"})  # (what the volunteer does: see test_camp)
	_tick()
	check(me.quests.active.has("intro_supplies"), "then finding food and water")
	me.inv.fill(null)  # (the volunteer's water and bandages)

	# Carrying food and water: done; the reward; the next one starts.
	main.inventory._give(me, "snack")
	main.inventory._give(me, "water")
	_tick()
	check(me.quests.done.has("intro_supplies") and me.quests.active.has("intro_weapon"), "food and water in the bag: done, on to the next")
	check(Crafting.count_in(me.inv, "bandage") == 2, "the reward is in the bag")

	# A weapon in hand.
	me.worn.hand_r = Items.make("bat")
	me.refresh_wear()
	_tick()
	check(me.quests.active.has("intro_kill"), "a weapon in hand: on to the fighting")
	var combat_before: float = me.skills.get("combat", 0.0)
	check(combat_before >= 20.0, "and fighting experience for it (%.0f)" % combat_before)

	# Kills count, three of them.
	for i in 3:
		main.quests.note(me, "kill", {kind = "normal"})
	_tick()
	check(me.quests.active.has("intro_board"), "three kills: on to boarding up")
	main.quests.note(me, "board")
	main.quests.note(me, "silent_kill")
	_tick()
	check(me.quests.active.has("intro_night"), "boarded, a silent kill: the first night")

	# Out through the night and alive at first light.
	main.world.is_night = true
	_tick()
	main.world.is_night = false
	_tick()
	check(me.quests.done.has("intro_night"), "alive at dawn: the start is done")
	_tick()
	check(not me.quests.active.keys().any(func(id): return Quests.DEFS[id].get("daily", false)), "the day's tasks wait at the camp's notice board")
	main.quests.hand_out_daily(me)
	_tick()
	var daily: Array = me.quests.active.keys().filter(func(id): return Quests.DEFS[id].get("daily", false))
	check(daily.size() == Quests.DAILY_COUNT, "then two everyday tasks (%s)" % str(daily))

	# A task for one kind counts only that kind.
	main.quests.start(me, "daily_runners")
	main.quests.note(me, "kill", {kind = "normal"})
	check(me.quests.active.daily_runners[0] == 0, "an ordinary zombie doesn't count for the runners")
	main.quests.note(me, "kill", {kind = "runner"})
	check(me.quests.active.daily_runners[0] == 1, "a runner does")

	# A new game day changes nothing (it's minutes long); a new real day does.
	var had: int = me.quests.day
	main.day += 1
	_tick()
	check(me.quests.day == had, "a new game day keeps today's tasks")
	Quests.day_shift += 1
	main.quests.hand_out_daily(me)
	_tick()
	check(me.quests.day == Quests.real_day(), "a new real day hands out the day's tasks")
	Quests.day_shift = 0
	_tick()  # (back to today, so the reload below doesn't see a new day)

	# Kept in the save.
	main.quests.start(me, "daily_hunt")
	main.quests.note(me, "kill", {kind = "normal"}, 4)
	main._save_all()
	await close_game()
	await host(9547, true, false)
	check(me.quests.done.has("intro_night") and me.quests.active.get("daily_hunt", [0])[0] == 4, "quests come back after a reload")
	SaveGame.wipe()
	await close_game()
