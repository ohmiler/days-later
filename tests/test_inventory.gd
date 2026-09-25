extends "res://tests/test_base.gd"
## The bag: stacking, quick heal, moving things around, clothes and bag size.


func run() -> void:
	await host(9303)
	me.inv.fill(null)

	# Stacks follow each item's own limit.
	for i in 12:
		main._give(me, "bandage")
	check(me.inv[0].n == 10 and me.inv[1].n == 2, "bandages stack to 10 (%s)" % bag(me))
	main._give(me, "knife")
	main._give(me, "knife")
	check(count(me, "knife") == 2 and me.inv[2].n == 1 and me.inv[3].n == 1, "weapons never stack")

	# Quick heal: bleeding first, then the smallest heal that covers the loss.
	main._give(me, "firstaid")
	main._give(me, "painkiller")
	me.hp = 95.0
	main.req_quick_heal()
	check(count(me, "bandage") == 11 and count(me, "firstaid") == 1, "a scratch uses a bandage, not the kit")
	me.hp = 40.0
	main.req_quick_heal()
	check(count(me, "firstaid") == 0, "a big wound uses the first-aid kit")
	me.hp = 95.0
	me.bleeding = true
	main.req_quick_heal()
	check(not me.bleeding, "bleeding gets stopped")

	# Moving: merge stacks, swap, split, drop, take back.
	me.inv.fill(null)
	me.inv[0] = {id = "water", n = 4, hp = 0}
	me.inv[1] = {id = "water", n = 5, hp = 0}
	main.req_move(["inv", 0], ["inv", 1])
	check(me.inv[1].n == 6 and me.inv[0] != null and me.inv[0].n == 3, "dragging onto a stack fills it to the limit")
	main.req_split(["inv", 1])
	check(count(me, "water") == 9 and me.inv[1].n == 3, "split halves a stack (%s)" % bag(me))
	var before: int = main.pickups.size()
	main.req_move(["inv", 0], ["ground", -1])
	check(main.pickups.size() == before + 1 and me.inv[0] == null, "drag out of the bag drops it")
	var pid: int = main.pickups.keys().back()
	main.req_move(["ground", pid], ["inv", -1])
	check(not main.pickups.has(pid) and count(me, "water") == 9, "take it back off the ground")

	# Clothes go only where they belong.
	main._give(me, "helmet")
	var h := me.inv.find(me.inv.filter(func(x): return x != null and x.id == "helmet")[0])
	main.req_move(["inv", h], ["worn", "legs"])
	check(not me.wear_ids.has("legs"), "a helmet cannot be worn on the legs")
	main.req_move(["inv", h], ["worn", "head"])
	check(me.wear_ids.get("head") == "helmet", "a helmet goes on the head")

	# A backpack adds slots; taking it off shrinks the bag and keeps what fits.
	main._give(me, "backpack")
	var b := me.inv.find(me.inv.filter(func(x): return x != null and x.id == "backpack")[0])
	main.req_move(["inv", b], ["worn", "back"])
	check(me.inv.size() == Items.INV_SIZE + 4, "a backpack gives 4 more slots (%d)" % me.inv.size())
	me.inv[Items.INV_SIZE + 2] = {id = "pipe", n = 1, hp = 60}
	main.req_move(["worn", "back"], ["inv", -1])
	check(me.inv.size() == Items.INV_SIZE and count(me, "pipe") == 1, "taking it off keeps the pipe from the bag (%s)" % bag(me))

	# The hotbar is the first 8 only.
	main.req_select(9)
	check(me.sel < Items.INV_SIZE, "slots past 8 cannot be selected on the hotbar")
