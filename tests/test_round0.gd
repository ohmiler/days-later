extends "res://tests/test_base.gd"
## Round 0 fixes (docs/reviews/2026-09-28): zombies never appear inside
## buildings, a grabbed rider can't ride off and still be bitten, a house is
## shut when its shell is (and says what's open), a bent shutter can be
## hammered straight, hospitals hold the cures, and seen zombies fade the
## roofs drawn over them.


func _shop() -> Dictionary:
	for rec in main.world.buildings:
		if rec.kind == "shop" and not rec.get("big", false):
			return rec
	return {}


func run() -> void:
	SaveGame.wipe()
	seed(5)
	await host(9371)
	main.spawn_timer = 1e9
	var w: World = main.world

	# --- Spawning: never inside a building ---------------------------------
	var shop := _shop()
	check(not shop.is_empty(), "the city has shophouses")
	me.position = w.to_pos(Vector2i(shop.rect.get_center().x, shop.rect.end.y + 1))
	var inside := 0
	for i in 300:
		main.survival._spawn_zombie()
		for z in main.zombies.values():
			if w.building_at.has(w.to_cell(z.position)):
				inside += 1
			z.queue_free()
		main.zombies.clear()
	check(inside == 0, "300 spawns next to a row of shophouses: none inside a building (%d)" % inside)

	# --- A grabbed rider pulls up; a hold breaks when out of reach -----------
	var v: Dictionary = w.vehicles[0]
	v.key = true
	v.fuel = Vehicles.MODELS[v.model].fuel
	me.position = v.pos
	main.vehicles.mount(me, v.id)
	me.ride_vel = Vector2(150, 0)
	var z := zombie_at(me.position + Vector2(8, 0))
	z.grab(me)
	check(me.grabbed_by == z.zid, "the zombie has hold of the rider")
	for i in 60:
		Vehicles.step(me, v, Vector2.RIGHT, 1.0 / 60.0, w)
	check(me.ride_vel.length() < 20.0, "held, the bike pulls up instead of riding off (%.0f px/s)" % me.ride_vel.length())
	me.position += Vector2(60, 0)
	z._hold(0.1)
	check(me.grabbed_by < 0, "pulled out of reach, the hold breaks: no bite from afar")
	main.vehicles.dismount(me)
	z.queue_free()
	main.zombies.clear()

	# --- Shut tight = the shell is shut ------------------------------------
	var b = w.building_at.get(shop.rect.get_center())
	var shell := 0
	var inner := 0
	for d in w.doors:
		if w.is_built(d.id) or w.building_at.get(d.cell) != b:
			continue
		if Survival._on_shell(w, d.cell, b):
			shell += 1
			w.set_door(d.id, true, d.hp, d.boards, false)
		else:
			inner += 1
			w.set_door(d.id, false, d.hp, d.boards, false)
	var spot := w.to_pos(shop.rect.get_center())
	check(shell > 0, "the shophouse has outside doors and windows (%d, %d inside)" % [shell, inner])
	check(main.survival.spot_safe(spot), "outside shut, inside doors open: still shut tight")
	for d in w.doors:
		if not w.is_built(d.id) and w.building_at.get(d.cell) == b and Survival._on_shell(w, d.cell, b):
			w.set_door(d.id, false, d.hp, d.boards, false)
			check(main.survival.unsafe_because(spot) in ["door", "window", "shutter"], "an open outside opening is named (%s)" % main.survival.unsafe_because(spot))
			w.set_door(d.id, true, d.hp, d.boards, false)
			break

	# --- A bent shutter can be hammered straight ---------------------------
	var sid := -1
	for d in w.doors:
		if d.kind == "shutter":
			sid = d.id
			break
	check(sid >= 0, "the city has shutters")
	if sid >= 0:
		w.set_door(sid, false, 0.0, 0, true)
		me.inv = [null, null, null, null, null, null, null, null]
		main.doors._fix_shutter(me, sid)
		check(w.doors[sid].broken, "no scrap and no hammer: it stays bent")
		me.inv[0] = {id = "scrap", n = 3}
		me.inv[1] = {id = "hammer", n = 1, hp = 100}
		main.doors._fix_shutter(me, sid)
		var d: Dictionary = w.doors[sid]
		check(not d.broken and d.closed and d.hp >= World.SHUTTER_HP, "with scrap and a hammer it rolls down whole again")
		check(me.inv[0] != null and me.inv[0].n == 3 - Interact.SHUTTER_SCRAP, "it took %d scrap" % Interact.SHUTTER_SCRAP)
	check(World.SHUTTER_HP > World.DOOR_HP + World.MAX_BOARDS * World.BOARD_HP, "a shutter outlasts a fully boarded door")

	# --- Hospitals hold the cures ------------------------------------------
	for id in ["antibiotic", "bandage", "painkiller", "firstaid"]:
		check("hospital" in Items.def(id).get("places", []), "%s can be found in a hospital" % id)

	# --- The bathroom water jar is a home's reserve ------------------------
	var jar := {}
	for th in w.things:
		if th.kind == "jar":
			jar = th
			break
	check(not jar.is_empty(), "shophouse bathrooms have water jars you can use")
	if not jar.is_empty():
		var left: int = main.things.jar_water(jar)
		check(left >= Things.JAR_LEFT[0] and left <= Things.JAR_LEFT[1], "a jar starts with some water (%d)" % left)
		me.inv = [{id = "pbottle", n = 1}, null, null, null, null, null, null, null]
		me.position = w.to_pos(jar.cell) + Vector2(0, 14)
		main.things._do_jar_fill(me, jar)
		var f := Items.fill_of(me.inv[0])
		check(f.get("what") == "jar" and f.get("n", 0) > 0, "a bottle fills from the jar (%s)" % str(f))
		check(main.things.jar_water(jar) == left - int(f.get("n", 0)), "and the jar has that much less")
	check(Quests.real_day() > 20000, "everyday tasks follow the real day")

	# --- Seen zombies fade the roof drawn over them -------------------------
	var row := Vector2i(shop.rect.get_center().x, shop.rect.position.y - 1)  # just north of the shop: under its roof
	me.position = w.to_pos(row + Vector2i(0, -6))
	var hidden := zombie_at(w.to_pos(row))
	hidden.set_physics_process(false)
	w.stream_around(Rect2(me.position - Vector2(400, 300), Vector2(800, 600)))
	await frames(3)
	hidden.sight_k = 1.0  # (as Sight sets it for one your character can see: the mouse isn't ours to aim here)
	hidden.visible = true
	main._fade_trees_near(me.position)
	var bp = w.building_at.get(shop.rect.get_center())
	check(bp != null and main.faded.has(bp), "the shophouse whose roof covers a seen zombie turns see-through")
	hidden.sight_k = 0.0
	main._fade_trees_near(me.position)
	check(not main.faded.has(bp), "one you can't see fades nothing (no x-ray)")
	await close_game()
