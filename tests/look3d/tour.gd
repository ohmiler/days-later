extends "res://tests/test_base.gd"
## A look round the game in 3D, for a review: the title screen, the first
## minute in the camp, a street with zombies at the usual zoom and zoomed
## right out, upstairs, the roof, sleeping, night, rain. Saves shots and fps.
##   godot --path . --resolution 1600x900 -s res://tests/look3d/tour.gd -- --out=DIR

var out := "user://look3d"


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	# The title screen, before any game.
	var title = load("res://main.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await wait(4.0)
	await _shot("t01_title.png")
	title.queue_free()
	await frames(3)
	# The first minute: where a new survivor wakes, at the usual zoom.
	await host(9198, false, false, 11)
	main.time = 0.3
	await wait(4.0)
	await _shot("t02_spawn.png")
	# Out of the camp onto a street, zombies about.
	var street := _street_spot()
	me.position = street
	me.god = true  # (a look round, not a fight)
	# A trap put down, and a body left by someone who died here before.
	var tc: Vector2i = main.world.to_cell(street) + Vector2i(2, 1)
	main.world.add_structure(main.world.doors.size(), tc, "wire", 60.0)
	main.world.add_structure(main.world.doors.size(), tc + Vector2i(1, 0), "spikes", 5.0)
	main.leave_corpse(street + Vector2(-30, 10), 1.0, {skin = Color("c8906a"), shirt = Color("3a6aa8"), pants = Color("2a3a5a")}, false, 0.0)
	for i in 12:
		var zp: Vector2 = street + Vector2(randf_range(-160, 160), randf_range(-120, 120))
		if main.world.can_stand(zp, 5.0):
			main._add_zombie(main.new_zid(zp), zp)
	await wait(3.0)
	await _shot("t03_street.png")
	main.play_zoom = Vector2(1.0, 1.0)
	main.camera.zoom = main.play_zoom
	await wait(3.0)
	await _shot("t04_far.png")
	main.play_zoom = Vector2(6.0, 6.0)
	main.camera.zoom = main.play_zoom
	await wait(2.0)
	await _shot("t05_closest.png")
	main.play_zoom = Vector2(4.0, 4.0)
	main.camera.zoom = main.play_zoom
	# Upstairs in a shophouse, then on its roof.
	var b := {}
	for bb in main.world.buildings:
		if bb.kind == "shop" and bb.get("upper", false) and bb.get("stairs", null) != null:
			b = bb
			break
	if not b.is_empty():
		for z in main.zombies.values():
			z.queue_free()
		main.zombies.clear()
		me.position = main.world.to_pos(b.stairs)
		main.actions._do_action(me, {kind = "stairs", id = b.stairs, pos = me.position}, "up")
		await wait(2.5)
		await _shot("t06_upstairs.png")
		# Asleep on a bed up there.
		var bed = main.world.containers.filter(func(f): return f.kind == "bed" and f.get("storey", 0) == me.storey and b.rect.has_point(f.cell))
		if not bed.is_empty():
			me.position = main.world.to_pos(bed[0].cell)
			me.sleeping = true
			me.rest_k = 1.0
			await wait(1.5)
			await _shot("t07_asleep.png")
			me.sleeping = false
			me.rest_k = 0.0
		me.storey = 0
		me.on_roof = true
		me.position = main.world.to_pos(b.rect.get_center())
		await wait(2.5)
		await _shot("t08_roof.png")
		me.on_roof = false
	# Night on the street, then rain.
	me.position = street
	main.time = 0.92
	await wait(3.0)
	await _shot("t09_night.png")
	main.time = 0.35
	main.raining = true
	await wait(3.0)
	await _shot("t10_rain.png")
	check(true, "tour done")


func _street_spot() -> Vector2:
	for rd in main.world.roads:
		var r: Rect2i = rd.rect
		var c := r.get_center()
		if main.world.get_tile(c) == World.ROAD and not main.world.in_camp(main.world.to_pos(c)):
			return main.world.to_pos(c)
	return me.position


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + "/" + file)
	print("shot ", file, " fps ", Engine.get_frames_per_second())
