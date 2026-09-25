extends "res://tests/test_base.gd"
## The bag: stacking, quick heal, moving things around, clothes and bag size.


func run() -> void:
	await host(9303)
	me.inv.fill(null)

	# Stacks follow each item's own limit.
	for i in 12:
		main.inventory._give(me, "bandage")
	check(me.inv[0].n == 10 and me.inv[1].n == 2, "bandages stack to 10 (%s)" % bag(me))
	main.inventory._give(me, "knife")
	main.inventory._give(me, "knife")
	check(count(me, "knife") == 2 and me.inv[2].n == 1 and me.inv[3].n == 1, "weapons never stack")

	# Quick heal: bleeding first, then the smallest heal that covers the loss.
	main.inventory._give(me, "firstaid")
	main.inventory._give(me, "painkiller")
	me.hp = 95.0
	main.inventory.req_quick_heal()
	check(count(me, "bandage") == 11 and count(me, "firstaid") == 1, "a scratch uses a bandage, not the kit")
	me.hp = 40.0
	main.inventory.req_quick_heal()
	check(count(me, "firstaid") == 0, "a big wound uses the first-aid kit")
	me.hp = 95.0
	me.bleeding = true
	main.inventory.req_quick_heal()
	check(not me.bleeding, "bleeding gets stopped")

	# Moving: merge stacks, swap, split, drop, take back.
	me.inv.fill(null)
	me.inv[0] = {id = "water", n = 4, hp = 0}
	me.inv[1] = {id = "water", n = 5, hp = 0}
	main.inventory.req_move(["inv", 0], ["inv", 1])
	check(me.inv[1].n == 6 and me.inv[0] != null and me.inv[0].n == 3, "dragging onto a stack fills it to the limit")
	main.inventory.req_split(["inv", 1])
	check(count(me, "water") == 9 and me.inv[1].n == 3, "split halves a stack (%s)" % bag(me))
	var before: int = main.pickups.size()
	main.inventory.req_move(["inv", 0], ["ground", -1])
	check(main.pickups.size() == before + 1 and me.inv[0] == null, "drag out of the bag drops it")
	var pid: int = main.pickups.keys().back()
	main.inventory.req_move(["ground", pid], ["inv", -1])
	check(not main.pickups.has(pid) and count(me, "water") == 9, "take it back off the ground")

	# Clothes go only where they belong.
	main.inventory._give(me, "helmet")
	var h := me.inv.find(me.inv.filter(func(x): return x != null and x.id == "helmet")[0])
	main.inventory.req_move(["inv", h], ["worn", "legs"])
	check(not me.wear_ids.has("legs"), "a helmet cannot be worn on the legs")
	main.inventory.req_move(["inv", h], ["worn", "head"])
	check(me.wear_ids.get("head") == "helmet", "a helmet goes on the head")

	# Layers: a vest goes over a shirt, and bites hit the outer layer first.
	main.inventory._give(me, "hoodie")
	main.inventory._give(me, "vest")
	var hd := me.inv.find(me.inv.filter(func(x): return x != null and x.id == "hoodie")[0])
	main.inventory.req_move(["inv", hd], ["worn", "body"])
	var v := me.inv.find(me.inv.filter(func(x): return x != null and x.id == "vest")[0])
	main.inventory.req_move(["inv", v], ["worn", "body"])
	check(me.wear_ids.get("body") == "hoodie", "a vest does not go in the shirt's place")
	main.inventory.req_move(["inv", v], ["worn", "over"])
	check(me.wear_ids.get("body") == "hoodie" and me.wear_ids.get("over") == "vest", "a vest goes on over the hoodie")
	var vest_hp: int = me.worn.over.hp
	var hood_hp: int = me.worn.body.hp
	me.bite(1.0)
	check(me.worn.over.hp == vest_hp - 1 and me.worn.body.hp == hood_hp, "a bite wears the vest, not the hoodie under it")
	main.inventory.req_move(["worn", "over"], ["inv", -1])
	main.inventory.req_move(["worn", "body"], ["inv", -1])

	# A backpack adds slots; taking it off shrinks the bag and keeps what fits.
	main.inventory._give(me, "backpack")
	var b := me.inv.find(me.inv.filter(func(x): return x != null and x.id == "backpack")[0])
	main.inventory.req_move(["inv", b], ["worn", "back"])
	check(me.inv.size() == Items.INV_SIZE + 4, "a backpack gives 4 more slots (%d)" % me.inv.size())
	me.inv[Items.INV_SIZE + 2] = {id = "pipe", n = 1, hp = 60}
	main.inventory.req_move(["worn", "back"], ["inv", -1])
	check(me.inv.size() == Items.INV_SIZE and count(me, "pipe") == 1, "taking it off keeps the pipe from the bag (%s)" % bag(me))

	# The hotbar is the first 8 only.
	main.inventory.req_select(9)
	check(me.sel < Items.INV_SIZE, "slots past 8 cannot be selected on the hotbar")
