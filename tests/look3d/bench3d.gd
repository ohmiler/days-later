extends SceneTree
## Step 0 of the 3D move: how many code-made zombies can shamble on screen.
## Builds N zombies around the survivor in play3d, all in view, then times
## frames with v-sync off. Prints build time, frame ms (avg, worst 1%) and
## where the time goes. Not part of the game.
##   godot --path . --resolution 1920x1080 -s res://tests/look3d/bench3d.gd -- 100
##   (add --gpu-index 1 before -s to try the other graphics card)

var s
var n := 100
var low := false  # "low" after the count: the settings a weak graphics card would use


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	low = "low" in args
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	s = load("res://tests/look3d/play3d.tscn").instantiate()
	root.add_child(s)
	await process_frame
	s.aim_at = Vector3(0, 0.9, 20)
	if low:
		s.env.ssil_enabled = false
		s.env.ssao_enabled = false
		s.env.glow_enabled = false
		s.sun.directional_shadow_max_distance = 20.0
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		root.get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		root.get_viewport().scaling_3d_scale = 0.67
	var t0 := Time.get_ticks_usec()
	while s.zombies.size() < n:
		s._spawn_zombie()
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	# A ring of them around the survivor, all on screen, walking in.
	for i in s.zombies.size():
		var z = s.zombies[i]
		var a: float = TAU * i / s.zombies.size()
		var r: float = 3.0 + (i % 5) * 1.6
		z.node.position = s.me.position + Vector3(cos(a) * r, 0, sin(a) * r * 0.7)
		z.speed = 0.15
		z.bite_cd = 9999.0
	s.zoom = 0.62
	for i in 120:
		await process_frame
	var times: Array[float] = []
	var proc := 0.0
	var last := Time.get_ticks_usec()
	for i in 600:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t / times.size()
	var worst: float = times[int(times.size() * 0.99)]
	print("BENCH low=%s zombies=%d gpu=%s build=%.0f ms (%.1f each) frame avg=%.2f ms (%.0f fps) 1%%-worst=%.2f ms script(process)=%.2f ms draw_calls=%d prims=%d" % [
		low, n, RenderingServer.get_video_adapter_name(), build_ms, build_ms / n, avg, 1000.0 / avg, worst, proc / 600.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/bench3d.png")
	quit(0)
