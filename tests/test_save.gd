extends "res://tests/test_base.gd"
## Save and resume: the world's changes, what is stored in furniture, and the player.


func _nearest_container() -> FurnitureProp:
	var best: FurnitureProp
	for f: FurnitureProp in main.world.container_nodes:
		if best == null or f.position.distance_to(me.position) < best.position.distance_to(me.position):
			best = f
	return best


func run() -> void:
	SaveGame.wipe()
	await host(9304)
	var w: World = main.world

	# Change a few things.
	var door := -1
	for d in w.doors:
		if d.kind == "door" and not d.broken and not d.closed:
			door = d.id
			break
	main.door_state(door, true, 140.0, 2, false)
	var f := _nearest_container()
	me.position = f.position + Vector2(0, 8)
	main._do_action(me, {kind = "container", id = f.data.id}, "search")
	simulate(main.SEARCH_TIME + 0.2)
	check(f.searched and me.open_box == f.data.id, "searching opens the furniture")
	me.inv.fill(null)
	main._give(me, "machete")
	main._give(me, "water")
	main.req_move(["inv", 0], ["box", f.data.id, 7])
	check(f.items[7] != null and f.items[7].id == "machete", "a machete stashed in the furniture")
	main._give(me, "jacket")
	var j := me.inv.find(me.inv.filter(func(x): return x != null and x.id == "jacket")[0])
	main.req_move(["inv", j], ["worn", "body"])
	main.day = 4
	main.time = 0.6
	me.hp = 57.0
	me.hunger = 33.0
	var pos := me.position
	var box_id: int = f.data.id
	main._save_all()
	check(SaveGame.has_world(), "the world was saved")
	await close_game()

	# A fresh game, resumed.
	await host(9305, true, false)
	w = main.world
	var d: Dictionary = w.doors[door]
	check(d.closed and int(d.hp) == 140 and d.boards == 2, "door state came back (closed %s hp %d boards %d)" % [d.closed, d.hp, d.boards])
	var f2: FurnitureProp = w.container_nodes[box_id]
	check(f2.searched, "the furniture is still searched")
	check(f2.items[7] != null and f2.items[7].id == "machete", "the stashed machete is still in it")
	check(main.day == 4 and absf(main.time - 0.6) < 0.01, "day and time came back")
	check(absf(me.hp - 57.0) < 0.5 and absf(me.hunger - 33.0) < 0.5, "player health and hunger came back")
	check(me.position.distance_to(pos) < 1.0, "player position came back")
	check(count(me, "water") == 1, "the bag came back (%s)" % bag(me))
	check(me.wear_ids.get("body") == "jacket", "worn clothes came back")
	SaveGame.wipe()
