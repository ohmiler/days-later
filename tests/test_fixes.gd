extends "res://tests/test_base.gd"
## Small things that were wrong once: picking up keeps an item as it was;
## a survivor who turned leaves no body and the next one is an ordinary
## survivor; bodies stay on the floor they fell on and can be burned up there;
## no lying down on a bike or a car roof; travelling forgets this zone's beds.


func _player_bodies() -> Array:
	return main.get_children().filter(func(n): return n is Corpse and not n.zombie)


func run() -> void:
	SaveGame.wipe()
	seed(8)
	await host(9504)
	main.spawn_timer = 1e9

	# Dropped and picked up again, a worn thing is still worn.
	main.inventory._give(me, "matches")
	var slot := -1
	for i in me.inv.size():
		if me.inv[i] != null and me.inv[i].id == "matches":
			slot = i
	me.inv[slot].hp = 1
	main._spawn_pickup(me.position + Vector2(6, 0), me.inv[slot].duplicate())
	me.inv[slot] = null
	await frames(1)
	var pid: int = main.pickups.keys().max()
	main.actions._do_action(me, {kind = "pickup", id = pid, pos = main.pickups[pid].pos}, "take")
	var got: Array = me.inv.filter(func(it): return it != null and it.id == "matches")
	check(got.size() == 1 and got[0].hp == 1, "picked up again, the matches still have one strike left")

	# Things that pile up still join the pile you carry.
	var food := ""
	for id in Items.DEFS:
		if Items.stack(id) > 1:
			food = id
			break
	main.inventory._give(me, food)
	main._spawn_pickup(me.position + Vector2(6, 0), {id = food, n = 1, hp = 0})
	await frames(1)
	pid = main.pickups.keys().max()
	main.actions._do_action(me, {kind = "pickup", id = pid, pos = main.pickups[pid].pos}, "take")
	check(me.inv.filter(func(it): return it != null and it.id == food).size() == 1 and count(me, food) == 2,
			"a %s picked up joins the one in the bag" % food)

	# Upstairs: a body can be burned, and a player's body stays up there.
	me.up = true
	main.add_corpse(me.position + Vector2(10, 0), 1.0, zombie_at(me.position + Vector2(300, 300)).body_look(), "", true)
	await frames(1)
	var cid: int = main.corpses.keys().max()
	check(Interact._candidates(main, me).any(func(c): return c.kind == "corpse" and c.id == cid),
			"upstairs, a body at your feet is there to burn")
	me.take_damage(9999)
	await frames(2)
	simulate(Player.RESPAWN_TIME + 0.5)
	await frames(2)
	var bodies := _player_bodies()
	check(bodies.size() == 1 and bodies[0].up, "died upstairs, the body stays upstairs")

	# Turned: no body left behind, and the next death is an ordinary one.
	me.up = false
	main.survival._turn(me)
	await frames(2)
	check(me.turned, "the infection won: turned")
	simulate(Player.RESPAWN_TIME + 0.5)
	await frames(2)
	check(_player_bodies().size() == 1, "a survivor who turned leaves no body (it walked off)")
	check(not me.turned, "the next survivor is not marked as turned")
	me.take_damage(9999)
	await frames(2)
	simulate(Player.RESPAWN_TIME + 0.5)
	await frames(2)
	check(_player_bodies().size() == 2, "and when they die, they leave a body")

	# No lying down on a bike or up on a car roof.
	me.riding = 0
	check(main.survival.can_sleep(me) != "", "no sleeping while riding")
	me.riding = -1
	me.on_car = 0
	check(main.survival.can_sleep(me) != "", "no sleeping on a car roof")
	me.on_car = -1

	# Travelling: this zone's bed and open cupboard mean nothing in the next.
	me.bed = 3
	me.sleep_bed = 3
	me.open_box = 3
	me.search_id = 3
	main.switch_zone("pratunam", "north")
	check(me.bed == -1 and me.sleep_bed == -1 and me.open_box == -1 and me.search_id == -1,
			"after travelling, no bed or cupboard from the zone left behind")

	await close_game()
