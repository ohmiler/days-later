extends "res://tests/test_base.gd"
## Water and food on the survival core: one game clock; bottles and pots that
## hold water of a kind; food that spoils by the clock; conditions that say
## what they do (Body.CONDITIONS); a stove that cooks by the clock while you're
## away; taps, the canal.


func _advance(hours: float) -> void:
	main.time += hours * Main.HOUR / Main.DAY_LENGTH
	while main.time >= 1.0:
		main.time -= 1.0
		main.day += 1


func _item(id: String) -> Dictionary:
	for it in me.inv:
		if it != null and it.id == id:
			return it
	return {}


func run() -> void:
	SaveGame.wipe()
	seed(11)
	await host(9528)
	main.spawn_timer = 1e9
	var w: World = main.world

	# One clock.
	var t0: float = main.now()
	_advance(2.0)
	check(is_equal_approx(main.now() - t0, 2.0 * Main.HOUR), "the game clock runs in game hours")

	# Bottles hold water of a kind, and only plain things pile up.
	me.inv.fill(null)
	main.inventory._give(me, "pbottle")
	main.inventory._give(me, "pbottle")
	check(me.inv.filter(func(it): return it != null).size() == 2, "a bottle is its own (they don't stack)")
	var got: int = main.inventory.fill_containers(me, "canal", 12)
	check(got == 6, "two bottles take 3 sips of canal water each (%d)" % got)
	var b := _item("pbottle")
	check(Items.state_text(b, main.now()).contains("น้ำคลอง 3/3"), "a bottle says what's in it (%s)" % Items.state_text(b, main.now()))

	# Drinking a sip: thirst up, one sip gone.
	me.thirst = 40.0
	main.inventory.drink_from(me, b)
	check(me.thirst > 40.0 and Items.fill_of(b).n == 2, "a sip from the bottle (thirst %.0f)" % me.thirst)

	# Conditions say what they do; they run their course by the clock.
	me.conditions.clear()
	var speed := me.speed_mult()
	Body.add_condition(me, "diarrhea", main.now())
	check(is_equal_approx(Body.mod(me, "thirst"), 2.2) and me.speed_mult() < speed, "diarrhea: thirstier, slower")
	var thirst := me.thirst
	main.survival._tick_needs(me, 5.0)
	var sick_drop := thirst - me.thirst
	me.conditions.clear()
	me.thirst = thirst
	main.survival._tick_needs(me, 5.0)
	check(sick_drop > (thirst - me.thirst) * 1.8, "thirst goes twice as fast with it (%.2f vs %.2f)" % [sick_drop, thirst - me.thirst])
	Body.add_condition(me, "diarrhea", main.now())
	_advance(Body.CONDITIONS.diarrhea.hours + 1.0)
	main.survival._tick_needs(me, 0.1)
	check(not me.conditions.has("diarrhea"), "and it passes, by the clock")

	# A stove: a pot of canal water boils clean; rice cooks; both by the clock.
	var stove := {}
	for th in w.things:
		if th.kind == "stove":
			stove = th
			break
	check(not stove.is_empty(), "back kitchens have stoves (%d)" % w.things.filter(func(th): return th.kind == "stove").size())
	if stove.is_empty():
		return
	me.inv.fill(null)
	main.inventory._give(me, "pot")
	var pot := _item("pot")
	pot.fill = {what = "canal", n = 5}
	me.position = w.to_pos(stove.cell) + Vector2(0, 14)
	var acts: Array = main.things.actions_for(me, stove.id)
	check(acts.any(func(a): return a.verb == "boil" and a.ok), "with a pot of water, the stove will boil it")
	var gas: int = main.things.stove_gas(stove)
	main.things.act(me, stove.id, "boil")
	check(_item("pot").is_empty() and not stove.state.pot.is_empty(), "the pot goes on the stove")
	check(stove.state.gas == gas - 1, "using a go of gas (%d left)" % stove.state.gas)
	main.things.act(me, stove.id, "take")
	pot = _item("pot")
	check(Items.fill_of(pot).what == "canal", "taken off too soon: still canal water")
	main.things.act(me, stove.id, "boil")
	_advance(Things.BOIL_HOURS + 0.1)
	main.things.act(me, stove.id, "take")
	pot = _item("pot")
	check(Items.fill_of(pot).get("what") == "clean" and Items.fill_of(pot).n == 5, "left to boil: clean water (%s)" % pot.get("fill"))

	# Rice: a pot with water and raw rice cooks into two plates that spoil.
	main.inventory._give(me, "rice_raw")
	stove.state.gas = 5
	main.things.act(me, stove.id, "cook")
	check(_item("rice_raw").is_empty() and not stove.state.pot.is_empty(), "rice on to cook")
	_advance(Things.COOK_HOURS + 0.1)
	main.things.act(me, stove.id, "take")
	var plates := me.inv.filter(func(it): return it != null and it.id == "rice")
	check(plates.size() == 2 and plates[0].has("made"), "two plates of rice, dated")
	check(Items.fill_of(_item("pot")).n == 3, "the rice took two sips of the water")
	check(not Items.spoiled(plates[0], main.now()), "fresh when cooked")
	_advance(Items.def("rice").spoil + 1.0)
	check(Items.spoiled(plates[0], main.now()), "gone off a day and more later")

	# The canal: E at its edge scoops water up.
	var edge := Vector2.INF
	for y in range(5, World.H - 5):
		for x in range(5, World.W - 5):
			var c := Vector2i(x, y)
			if w.get_tile(c) == World.WATER and w.can_stand(w.to_pos(c + Vector2i.UP), Player.RADIUS):
				edge = w.to_pos(c + Vector2i.UP) + Vector2(0, 4)
				break
		if edge != Vector2.INF:
			break
	if edge != Vector2.INF:
		me.position = edge
		me.inv.fill(null)
		main.inventory._give(me, "bottle")
		var c: Array = Interact._candidates(main, me).filter(func(t): return t.kind == "canal")
		check(not c.is_empty(), "at the canal's edge, E offers the canal")
		if not c.is_empty():
			main.actions._do_action(me, c[0], "scoop")
			check(Items.fill_of(_item("bottle")).get("what") == "canal", "a glass bottle scoops canal water")

	# What's worn by the body and what's in the bottles comes back after a save.
	Body.add_condition(me, "food_poisoning", main.now())
	SaveGame.save_player(me)
	me.conditions.clear()
	me.inv.fill(null)
	SaveGame.load_player_into(me, me.pname)
	check(me.conditions.has("food_poisoning"), "conditions are saved")
	check(Items.fill_of(_item("bottle")).get("what") == "canal", "and so is what's in a bottle")

	await close_game()
