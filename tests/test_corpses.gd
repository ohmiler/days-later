extends "res://tests/test_base.gd"
## Zombie bodies: a kill leaves one that rots to bones and is gone; with a
## lighter or matches you can burn it (it burns down to ash, then goes); a
## rotting body nearby spoils your sleep; bodies are saved and come back.


func run() -> void:
	SaveGame.wipe()
	seed(5)
	await host(9496)
	main.spawn_timer = 1e9
	var w: World = main.world

	# A kill leaves a body, on the server and drawn.
	var z := zombie_at(me.position + Vector2(30, 0))
	var body: Dictionary = z.body_look()
	main.combat._kill_zombie(z, 1.0)
	main.zombies.erase(z.zid)
	z.queue_free()
	await frames(2)
	check(main.corpses.size() == 1, "a dead zombie leaves a body")
	var cid: int = main.corpses.keys()[0]
	check(main.corpse_nodes.has(cid), "and it's drawn")

	# It rots, then is gone.
	main.corpses[cid].age = Corpse.GONE - 0.5
	simulate(1.0)
	await frames(2)
	check(not main.corpses.has(cid) and not main.corpse_nodes.has(cid), "a body rots away and is gone")

	# Burning: needs fire.
	main.add_corpse(me.position + Vector2(14, 0), 1.0, body, "")
	await frames(1)
	cid = main.corpses.keys()[0]
	var t := {kind = "corpse", id = cid, pos = main.corpses[cid].pos}
	var burn: Array = Interact.actions(main, me, t).filter(func(a): return a.verb == "burn")
	check(burn.size() == 1 and not burn[0].ok, "without a lighter you can't burn it")
	main.burn_corpse(me, cid)
	check(main.corpses[cid].burn < 0.0, "and trying does nothing")
	main.inventory._give(me, "matches")
	var hp0: int = me.inv.filter(func(it): return it != null and it.id == "matches")[0].hp
	burn = Interact.actions(main, me, t).filter(func(a): return a.verb == "burn")
	check(burn[0].ok, "with matches you can")
	main.actions._do_action(me, t, "burn")
	check(main.corpses[cid].burn >= 0.0, "E > burn sets it alight")
	var left: Array = me.inv.filter(func(it): return it != null and it.id == "matches")
	check(left.size() == 1 and left[0].hp == hp0 - 1, "using up a match")
	await frames(1)
	check(main.corpse_nodes[cid].burn >= 0.0, "everyone sees it burning")
	check(not Interact.actions(main, me, t).any(func(a): return a.verb == "burn" and a.ok) \
			or Interact._candidates(main, me).all(func(c): return c.kind != "corpse"), "a burning body can't be lit again")

	# Standing in the fire hurts; it burns down to ash, then goes.
	me.position = main.corpses[cid].pos
	var hp := me.hp
	simulate(1.0)
	check(me.hp < hp, "standing in the fire burns you")
	me.position += Vector2(0, 40)
	main.corpses[cid].burn = Corpse.BURN_TIME + Corpse.ASH_TIME - 0.5
	simulate(1.0)
	await frames(2)
	check(not main.corpses.has(cid), "burnt down to ash, then gone")

	# The last match used up goes from the bag.
	for it in me.inv:
		if it != null and it.id == "matches":
			it.hp = 1
	main.add_corpse(me.position + Vector2(10, 0), 1.0, body, "")
	cid = main.corpses.keys().max()
	main.burn_corpse(me, cid)
	check(count(me, "matches") == 0, "the last match used, the box is gone")

	# A rotting body near where you sleep spoils it.
	main.corpses.clear()
	for n in main.corpse_nodes.values():
		n.queue_free()
	main.corpse_nodes.clear()
	me.hp = 40.0
	main.actions.req_sleep()
	simulate(4.0)
	var clean := me.hp - 40.0
	main.actions.req_sleep()
	main.add_corpse(me.position + Vector2(30, 0), 1.0, body, "")
	cid = main.corpses.keys().max()
	main.corpses[cid].age = Corpse.ROT + 5.0
	me.hp = 40.0
	main.actions.req_sleep()
	simulate(4.0)
	var reek := me.hp - 40.0
	check(clean > 0.0 and reek < clean * 0.6, "a rotting body nearby spoils sleep (%.1f vs %.1f)" % [reek, clean])
	check(me.warned.has("reek"), "and you're told why")
	main.actions.req_sleep()

	# Bodies are saved, as they were.
	main.corpses[cid].burn = 2.0
	var pos: Vector2 = main.corpses[cid].pos
	main._save_all()
	await close_game()
	await host(9497, true, false)
	check(main.corpses.size() == 1, "the body came back with the world")
	var c: Dictionary = main.corpses.values()[0]
	check(c.pos.distance_to(pos) < 0.5 and c.burn >= 2.0 and c.age > Corpse.ROT, "where it was, still burning, as rotten")
	check(main.corpse_nodes.size() == 1, "and it's drawn")
	w = main.world
	SaveGame.wipe()
