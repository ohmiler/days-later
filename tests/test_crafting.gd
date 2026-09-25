extends "res://tests/test_base.gd"
## Making things by hand: the recipe table reads cleanly, taking clothes apart
## gives rags, rags make bandages, moving stops the work, mending gives
## durability back, and what you wear is never used up.


func _slot(id: String) -> int:
	for i in me.inv.size():
		if me.inv[i] != null and me.inv[i].id == id:
			return i
	return -1


func run() -> void:
	var bad := Crafting.problems()
	check(Crafting.RECIPES.size() >= 6, "the recipe table loads (%d)" % Crafting.RECIPES.size())
	check(bad.is_empty(), "every recipe is filled in correctly" + ("" if bad.is_empty() else ": " + "; ".join(bad)))

	await host(9390)
	me.inv.fill(null)
	var c: Crafting = main.crafting

	# Take a hoodie apart: two rags.
	main.inventory._give(me, "hoodie")
	c.req_salvage(_slot("hoodie"))
	simulate(Crafting.SALVAGE_TIME + 0.2)
	check(_slot("hoodie") < 0 and count(me, "rag") == 2, "a hoodie comes apart into 2 rags (%s)" % bag(me))

	# Two rags make a bandage, after a moment standing still.
	c.req_craft("bandage")
	simulate(0.5)
	check(count(me, "bandage") == 0, "it takes a moment")
	simulate(Crafting.RECIPES.bandage.time)
	check(count(me, "bandage") == 1 and count(me, "rag") == 0, "2 rags make a bandage (%s)" % bag(me))
	c.req_craft("bandage")
	simulate(3.0)
	check(count(me, "bandage") == 1, "not without the rags")

	# Walking off stops it and uses nothing.
	for i in 3:
		main.inventory._give(me, "nails")
	main.inventory._give(me, "plank")
	c.req_craft("nailbat_plank")
	me.move = Vector2.RIGHT
	simulate(0.3)
	me.move = Vector2.ZERO
	simulate(4.0)
	check(count(me, "nailbat") == 0 and count(me, "nails") == 3, "moving stops the work and keeps the things")
	c.req_craft("nailbat_plank")
	simulate(4.0)
	check(count(me, "nailbat") == 1 and count(me, "plank") == 0 and count(me, "nails") == 0, "a plank and 3 nails make a nail bat (%s)" % bag(me))

	# Mending: a torn hoodie you wear, with a rag from the bag.
	me.worn.body = {id = "hoodie", n = 1, hp = 3}
	me.refresh_wear()
	main.inventory._give(me, "rag")
	c.req_repair(["worn", "body"])
	simulate(Crafting.REPAIR_TIME + 0.2)
	check(me.worn.body.hp > 3 and count(me, "rag") == 0, "a rag mends the hoodie you wear (%d)" % me.worn.body.hp)

	# What you wear is never used as material.
	me.worn.body.hp = 15
	c.req_salvage(-1)
	me.inv.fill(null)
	main.inventory._give(me, "rag")
	c.req_craft("bandage")
	simulate(3.0)
	check(me.worn.has("body") and count(me, "bandage") == 0, "worn clothes are not used up")

	# Pull a cupboard apart for wood and nails: slow by hand, faster with a hammer.
	var f: FurnitureProp = null
	for n: FurnitureProp in main.world.container_nodes:
		if n.data.kind == "cabinet":
			f = n
			break
	me.inv.fill(null)
	me.position = f.position + Vector2(0, 6)
	c.start_strip(me, f.data.id)
	simulate(Crafting.STRIP_TIME * 0.6)
	check(not f.stripped, "pulling a cupboard apart by hand takes a while")
	simulate(Crafting.STRIP_TIME * 0.5)
	check(f.stripped and count(me, "wood") == 2 and count(me, "nails") == 1, "a cupboard gives 2 boards and a nail (%s)" % bag(me))
	var verbs := Interact.actions(main, me, {kind = "container", id = f.data.id}).filter(func(a): return a.verb == "strip")
	check(not verbs.is_empty() and not verbs[0].ok, "and it can't be pulled apart twice")

