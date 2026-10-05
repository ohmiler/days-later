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
	me.storey = 1
	main.add_corpse(me.position + Vector2(10, 0), 1.0, zombie_at(me.position + Vector2(300, 300)).body_look(), "", 1)
	await frames(1)
	var cid: int = main.corpses.keys().max()
	check(Interact._candidates(main, me).any(func(c): return c.kind == "corpse" and c.id == cid),
			"upstairs, a body at your feet is there to burn")
	me.take_damage(9999)
	await frames(2)
	simulate(Player.RESPAWN_TIME + 0.5)
	await frames(2)
	var bodies := _player_bodies()
	check(bodies.size() == 1 and bodies[0].storey == 1, "died upstairs, the body stays upstairs")

	# Turned: no body left behind, and the next death is an ordinary one.
	me.storey = 0
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

	# A door in a wall running up and down the screen is drawn edge on (not
	# facing us), and a blow doesn't go through it shut.
	var w: World = main.world
	var sd := {}
	for d in w.doors:
		if d.get("side", false) and not d.broken:
			sd = d
			break
	check(not sd.is_empty(), "doors in side walls are known as such")
	if not sd.is_empty():
		var dc: Vector2 = w.to_pos(sd.cell)
		me.position = dc + Vector2(-11, 0)
		me.storey = 0
		me.aim = Vector2(20, 0)
		var zd := zombie_at(dc + Vector2(11, 0))
		zd.hp = zd.max_hp
		sd.closed = true
		main.combat._resolve_melee(me, Look.PUNCH_L, main.combat.PUNCH)
		check(zd.hp == zd.max_hp, "no punching through a shut door at a zombie on the far side")
		sd.closed = false
		zd.position = dc + Vector2(11, 0)
		main.combat._resolve_melee(me, Look.PUNCH_L, main.combat.PUNCH)
		check(zd.hp < zd.max_hp, "open, the punch lands")
		main.zombies.erase(zd.zid)
		zd.queue_free()

	# Climbing onto a car, the camera follows the body up: no jump when it's done.
	me.climb_from = Vector2(100, 100)
	me.climb_to = Vector2(100, 84)
	me.climb_h = 14.0
	me.climb_dur = 0.8
	me.climb_t = 0.8
	me.on_car = -1
	me.lift = 0.0
	var during := me.climb_from + me.climb_offset()  # (still standing where the climb began, lift 0)
	var after := me.climb_to + Vector2(0, -me.climb_h)
	check(during.distance_to(after) < 0.5, "climbing up a car, the camera ends where the body does (%s / %s)" % [during, after])
	me.climb_dur = 0.0
	# ...and jumping down off one: it comes down with the body.
	me.lift = 14.0
	var before_jump := Vector2(0, -me.lift)
	main.actions.fx_vault(me.peer_id, me.position, me.position + Vector2(0, 20), 0.45, 4.0, 14.0)
	check((Vector2(0, -me.lift) + me.climb_offset()).distance_to(before_jump) < 0.5, "jumping down off a car, the camera starts from the roof, no snap")
	me.vault_dur = 0.0

	# You walk right up to a wall above or below you (the footprint is shallow, as feet are seen from here).
	var probe := {}
	for d in w.doors:
		var c: Vector2i = d.cell
		# (A front door with bare wall beside it and clear floor inside, to walk down to that wall.)
		if d.kind == "door" and not d.get("side", false) and w.get_tile(c + Vector2i(1, 0)) in [World.IWALL, World.BUILDING] 				and not w.door_at.has(c + Vector2i(1, 0)) and not w.is_solid(c + Vector2i(1, -1)) and not w.is_solid(c + Vector2i(1, -2)) 				and not w.is_solid(c + Vector2i(0, -1)) and not w.is_solid(c + Vector2i(2, -1)):
			probe = d
			break
	if not probe.is_empty():
		# Stand in the doorway's room side and walk up into the wall beside the door.
		var inside: Vector2 = w.to_pos(probe.cell + Vector2i(1, -2))
		var p := inside
		for i in 240:
			p = w.slide(p, Vector2(0, 0.5), Player.RADIUS)
		var edge := float((probe.cell.y) * World.TILE)
		check(not w.is_solid(probe.cell + Vector2i(1, -1)) and edge - p.y < Player.RADIUS - 1.5,  # (it was a whole RADIUS)
				"walking up to a wall, the feet stop right at it (%.1f px short)" % (edge - p.y))


	# Travelling: this zone's bed and open cupboard mean nothing in the next.
	me.bed = 3
	me.sleep_bed = 3
	me.open_box = 3
	me.search_id = 3
	main.switch_zone("pratunam", "north")
	check(me.bed == -1 and me.sleep_bed == -1 and me.open_box == -1 and me.search_id == -1,
			"after travelling, no bed or cupboard from the zone left behind")

	await close_game()
