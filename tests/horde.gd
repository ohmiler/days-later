extends "res://tests/test_base.gd"
## A horde night, measured: 160 zombies (Survival.HORDE_MAX_ZOMBIES) closing
## in on you from every side, and where each frame's time goes. In a real
## window (not part of run_all):
##
##   godot --path . --resolution 1280x720 -s res://tests/horde.gd -- --slot=test
##
## Prints the frame (median, 95%, worst), and of it: the server's tick, the
## zombies' thinking in it, pushing them apart, their per-frame updates here,
## drawing them; what's left is Godot drawing it all on the screen.

const SECS := 6.0


var rng := RandomNumberGenerator.new()  # (the same crowd every run, to compare)


func _measure(label: String, n_zombies: int) -> void:
	while main.zombies.size() < n_zombies:
		var pos := me.position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(50.0, 220.0)
		if main.world.can_stand(pos, 5):
			var z: Zombie = main._add_zombie(main.new_zid(pos), pos)
			z.target = me
	await wait(3.0)  # (they close in round you, as they do on a horde night)
	for k in main.prof:
		main.prof[k] = 0
	Main.profiling = true
	var times := []
	var t0 := Time.get_ticks_usec()
	var elapsed := 0.0
	var draws := 0.0
	while elapsed < SECS:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - t0) / 1000.0
		t0 = now
		times.append(dt)
		elapsed += dt / 1000.0
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		me.hp = 100.0  # (you don't die in a measurement)
		me.bleeding = false
	Main.profiling = false
	var n := times.size()
	var total := 0.0
	for t in times:
		total += t
	times.sort()
	var per := func(k: String) -> float: return main.prof[k] / 1000.0 / n
	var mine: float = per.call("server") + per.call("zproc") + per.call("zdraw")
	print("HORDE %s (%d zombies): frame median %.1f ms, 95%% %.1f, worst %.1f · %d draw calls" % [label, main.zombies.size(),
			times[n / 2], times[int(n * 0.95)], times[n - 1], draws / n])
	print("  in the zombies' thinking: looking for you %.2f ms, finding the way %.2f ms, moving %.2f ms" % [per.call("look"), per.call("path"), per.call("move")])
	print("  of an average %.1f ms: server tick %.1f (zombies thinking %.1f, pushing apart %.1f) · zombie updates %.1f · drawing zombies %.1f · the rest (Godot, the town, the UI) %.1f"
			% [total / n, per.call("server"), per.call("ai"), per.call("separate"), per.call("zproc"), per.call("zdraw"), total / n - mine])


func run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	SaveGame.wipe()
	rng.seed = 7
	await host(9387, false, true, 4242)  # (the same city every run)
	main.spawn_timer = 1e9
	main.time = 0.9  # (night)
	me.position = main.world.to_pos(main.world.spawn_cell)
	await frames(30)
	await _measure("a street", 40)
	await _measure("a horde", 100)
	await _measure("a full horde", 160)
	SaveGame.wipe()
	await close_game()
