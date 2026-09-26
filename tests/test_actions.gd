extends "res://tests/test_base.gd"
## What E does, through the same path a key press takes: find the target in
## reach, pick its main action, carry it out on the server.


func _nearest_container() -> FurnitureProp:
	var best: FurnitureProp
	for f: FurnitureProp in main.world.container_nodes:
		if f.data.get("up", false):
			continue  # (downstairs, where you are)
		if best == null or f.position.distance_to(me.position) < best.position.distance_to(me.position):
			best = f
	return best


func run() -> void:
	await host(9340)
	var w: World = main.world

	# E at a door opens or shuts it.
	var door := -1
	for d in w.doors:
		if d.kind == "door" and not d.broken:
			door = d.id
			break
	var dd: Dictionary = w.doors[door]
	me.position = w.to_pos(dd.cell) + Vector2(0, 14)
	me.aim = Vector2(0, -1)
	var was: bool = dd.closed
	main.actions.req_interact()
	check(dd.closed != was, "E at a door toggles it")

	# E at furniture searches it, and the search finishes into its contents.
	var f := _nearest_container()
	me.position = f.position + Vector2(0, 8)
	me.aim = Vector2(0, -1)
	var t := Interact.target(main, me)
	check(t.get("kind") == "container", "the furniture is what E points at (%s)" % t.get("kind", "nothing"))
	main.actions.req_interact()
	check(me.search_id == f.data.id, "E starts searching it")
	simulate(main.inventory.SEARCH_TIME + 0.2)
	check(f.searched and me.open_box == f.data.id, "the search ends with the furniture open")
	main.inventory.req_close_box()
	main.actions.req_interact()
	check(me.open_box == f.data.id, "E on searched furniture opens it again straight away")

	# A zombie knocked flat can be finished with E.
	main.inventory.req_close_box()
	me.position = w.to_pos(w.spawn_cell)
	var z := zombie_at(me.position + Vector2(10, 0))
	z.knock_down()
	z.server_tick(0.016)
	me.aim = Vector2(1, 0)
	var k0 := me.kills
	main.actions.req_act("zombie", z.zid, "stomp")
	check(not main.zombies.has(z.zid) and me.kills == k0 + 1, "stomping a downed zombie kills it")

	# Picking something up off the ground.
	var before := count(me, "water")
	main._spawn_pickup(me.position + Vector2(4, 2), {id = "water", n = 1, hp = 0})
	var pid: int = main.pickups.keys().back()
	main.actions.req_act("pickup", pid, "take")
	check(count(me, "water") == before + 1 and not main.pickups.has(pid), "E picks things up")

	# Things out of reach cannot be acted on, whatever the client asks.
	main._spawn_pickup(me.position + Vector2(200, 0), {id = "knife", n = 1, hp = 30})
	var far_id: int = main.pickups.keys().back()
	main.actions.req_act("pickup", far_id, "take")
	check(main.pickups.has(far_id), "a pickup out of reach stays where it is")
