extends "res://tests/test_base.gd"
## Round B: what only some places have. A hospital's saline, splints, gauze
## and syringes; a market's dried fish, fruit (going off on the stall) and
## sacks of rice; a mall's appliances; an office's odds and ends to take apart.


func run() -> void:
	check(Items.problems().is_empty(), "the item table is sound " + str(Items.problems()))
	var has := func(place: String, id: String) -> bool: return Items.LOOT[place].any(func(e): return e[0] == id)
	check(["saline", "splint", "gauze", "syringe"].all(func(id): return has.call("hospital", id)), "a hospital has saline, splints, gauze and syringes")
	check(not has.call("med", "saline"), "a shophouse pharmacy doesn't")
	check(["dryfish", "fruit", "ricesack"].all(func(id): return has.call("market", id)), "a market has dried fish, fruit and sacks of rice")
	check(["ricecooker", "fan"].all(func(id): return has.call("mall", id)), "a mall has appliances")
	check(["stapler", "keyboard", "laptop"].all(func(id): return has.call("office", id)), "an office has odds and ends")
	check(Items.def("ricesack").salvage.rice_raw == 10, "a sack opens into ten bags of rice")

	SaveGame.wipe()
	await host(9542)
	# A splint on a sprained ankle: you can run again, and it mends sooner.
	Body.add(me, "sprain", "legs")
	check(Body.sprained(me.wounds), "a sprained ankle")
	me.inv[0] = Items.make("splint")
	me.sel = 0
	main.inventory._use_selected(me)
	check(not Body.sprained(me.wounds) and me.inv[0] == null, "a splint on it: the ankle takes your weight")
	me.inv[0] = Items.make("splint")
	main.inventory._use_selected(me)
	check(me.inv[0] != null, "nothing to splint: the splint is kept")

	# Saline: water and a little health.
	me.thirst = 10.0
	me.inv[0] = Items.make("saline")
	main.inventory._use_selected(me)
	check(me.thirst >= 70.0, "saline puts water back (%.0f)" % me.thirst)

	# Fruit from a market stall has been sitting there: it goes off in the end.
	var fruit := Items.make("fruit")
	fruit.made = main.now()
	check(not Items.spoiled(fruit, main.now()) and Items.spoiled(fruit, main.now() + 80 * Main.HOUR), "fruit keeps a few days, then goes off")
	SaveGame.wipe()
	await close_game()
