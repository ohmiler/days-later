extends "res://tests/test_base.gd"
## City 2: photograph the one-block trial zone (data/zones/proto.cfg).
##   godot --path . --resolution 1600x900 -s res://tests/look_city2.gd -- DIR

var out := ""


func run() -> void:
	out = OS.get_cmdline_user_args()[0]
	Zombie.grab_chance = 0.0
	Camp.safe_on = false
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await frames(2)
	main.port = 9196
	main.zone = "proto"
	main.seed_override = 5
	main.player_name = "Tester"
	main._host(false, false)
	me = main.players.get(1)
	for z in main.zombies.values():
		z.queue_free()
	main.zombies.clear()
	me.god = true
	main.time = 0.35
	# The whole block, then round it: the south fronts, the north, the east, the soi.
	for shot in [["c2_block.png", Vector2i(59, 50), 1.2], ["c2_south.png", Vector2i(40, 84), 3.0], ["c2_north.png", Vector2i(45, 14), 3.0],
			["c2_east.png", Vector2i(101, 45), 3.0], ["c2_west.png", Vector2i(16, 45), 3.0], ["c2_soi.png", Vector2i(59, 60), 3.0]]:
		me.position = main.world.to_pos(shot[1])
		main.play_zoom = Vector2(shot[2], shot[2])
		main.camera.zoom = main.play_zoom
		main.cam_pos = Vector2.INF
		await wait(1.5)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out + "/" + shot[0])
		print("shot ", shot[0])
	# Inside one facing each way: the thin walls, the rooms, the doors.
	for facing in ["n", "e", "s"]:
		for b in main.world.buildings:
			if b.get("facing", "s") == facing and b.kind == "shop":
				var spot: Vector2 = main.world.to_pos(b.rect.get_center())
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						var p: Vector2 = main.world.to_pos(b.rect.get_center() + Vector2i(dx, dy))
						if main.world.can_stand(p, Player.RADIUS):
							spot = p
				me.position = spot
				main.play_zoom = Vector2(3.4, 3.4)
				main.camera.zoom = main.play_zoom
				main.cam_pos = Vector2.INF
				await wait(1.5)
				await RenderingServer.frame_post_draw
				root.get_viewport().get_texture().get_image().save_png(out + "/c2_inside_%s.png" % facing)
				print("shot inside ", facing)
				break
	check(main.world.zone == "proto", "the trial zone")
