extends "res://tests/test_base.gd"
## Round 1 of the 3D move: the real game in 3D, photographed. Hosts a test
## game (the "test" save slot) windowed, walks a little, and saves shots.
##   godot --path . --resolution 1600x900 -s res://tests/look3d/shoot_game.gd -- --out=DIR

var out := "user://look3d"


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	await host(9197, false, false, 11)
	main.time = 0.25  # (morning light)
	await wait(4.0)
	await _shot("game_start.png")
	main.play_zoom = Vector2(2.2, 2.2)
	main.camera.zoom = main.play_zoom
	await wait(1.5)
	await _shot("game_far.png")
	main.play_zoom = Vector2(5.5, 5.5)
	main.camera.zoom = main.play_zoom
	await wait(1.5)
	await _shot("game_close.png")
	# Walk into the nearest shophouse with its door open.
	var best := -1
	var best_d := 1e9
	for b in main.world.buildings:
		if b.kind == "shop" and b.get("enter", false):
			var d: float = main.world.to_pos(b.rect.get_center()).distance_to(me.position)
			if d < best_d:
				best_d = d
				best = b.id
	if best >= 0:
		var r: Rect2i = main.world.buildings[best].rect
		me.position = main.world.to_pos(r.get_center())
		main.play_zoom = Vector2(4.0, 4.0)
		main.camera.zoom = main.play_zoom
		await wait(2.5)
		await _shot("game_inside.png")
	# Out on a street with parked bikes: zombies, a body, blood, a hit.
	var bike: Dictionary = {}
	for v in main.world.vehicles:
		if v.get("upright", true) and main.world.get_tile(main.world.to_cell(v.pos)) in [World.SIDEWALK, World.ROAD]:
			bike = v
			break
	if not bike.is_empty():
		me.position = bike.pos + Vector2(40, 30)
		main.play_zoom = Vector2(3.6, 3.6)
		main.camera.zoom = main.play_zoom
		for i in 5:
			var zp: Vector2 = me.position + Vector2(-50 + i * 22, -40 + (i % 2) * 20)
			var z = main._add_zombie(main.new_zid(zp), zp)
			z.skin = Color("9a9a80")
			z.shirt = Color.from_hsv(i * 0.2, 0.5, 0.6)
			z.pants = Color("3a3a40")
		main.add_corpse(me.position + Vector2(30, -10), 1.0, {skin = Color("9a9a80"), shirt = Color("c83a3a"), pants = Color("2a2a3a"), grime = 0.7}, "slump")
		for i in 12:
			main.blood.append([me.position + Vector2(30 + randf_range(-10, 10), -10 + randf_range(-6, 6)), randf_range(1.0, 3.0), Color(0.4, 0.03, 0.03, 0.8)])
		main.dmg_numbers.append([me.position + Vector2(-20, -30), "24", true, 0.2])
		await wait(2.0)
		await _shot("game_street.png")
	main.time = 0.9  # night
	await wait(2.0)
	await _shot("game_night.png")
	check(main.view3d != null, "the 3D view is on")


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + "/" + file)
	print("shot ", file, " fps ", Engine.get_frames_per_second(), " chunks ", main.view3d.chunks.size(), " people ", main.view3d.people.size())
