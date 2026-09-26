extends "res://tests/test_base.gd"
## How fast the game draws, in a real window (so not part of run_all: headless
## has no renderer). Run it after visual work to see nothing got slower:
##
##   godot --path . --resolution 1280x720 -s res://tests/perf.gd
##
## It hosts a game, stands in the middle of town with its zombies, and measures
## at the normal zoom and zoomed out. A check fails if drawing goes over budget.
## (Numbers depend on the machine; the budgets have room for slower ones. On
## 2026-09-26, on the dev PC: 108 draw calls and 3.6 ms a frame at zoom 4;
## with 80 bodies about, 229 calls and 4.3 ms.)

const BUDGET := {4.0: [400, 12.0], 1.0: [2500, 25.0]}  # zoom -> [draw calls, ms a frame]


func _measure(zoom: float) -> Array:
	main.play_zoom = Vector2(zoom, zoom)
	main.camera.zoom = main.play_zoom
	await frames(30)
	var n := 150
	var draws := 0.0
	var t0 := Time.get_ticks_usec()
	for i in n:
		await frames(1)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	return [draws / n, (Time.get_ticks_usec() - t0) / 1000.0 / n]


func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("perf.gd needs a window: run it without --headless")
		check(false, "has a renderer to measure")
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await host(9386, false, false)
	await frames(30)
	for zoom: float in BUDGET:
		var m := await _measure(zoom)
		var b: Array = BUDGET[zoom]
		print("  zoom %.0f: %.0f draw calls, %.2f ms a frame (%.0f fps)" % [zoom, m[0], m[1], 1000.0 / m[1]])
		check(m[0] <= b[0], "zoom %.0f: draw calls within %d" % [zoom, b[0]])
		check(m[1] <= b[1], "zoom %.0f: a frame within %.0f ms" % [zoom, b[1]])

	# A street full of bodies (the most a zone keeps), rotting with their flies
	# and some of them burning: each body is one batch, so it hardly costs.
	var z := zombie_at(me.position + Vector2(400, 0))
	var body: Dictionary = z.body_look()
	for i in Main.MAX_CORPSES:
		main.add_corpse(me.position + Vector2(randf_range(-150, 150), randf_range(-90, 90)), 1.0, body, "")
	var k := 0
	for cid in main.corpses:
		main.corpses[cid].age = Corpse.ROT + 5.0
		main.corpse_nodes[cid].t = Corpse.ROT + 5.0
		if k < 15:
			main.corpses[cid].burn = 0.0
			main.corpse_nodes[cid].burn = 0.0
		k += 1
	var m := await _measure(4.0)
	print("  %d bodies, zoom 4: %.0f draw calls, %.2f ms a frame" % [Main.MAX_CORPSES, m[0], m[1]])
	check(m[0] <= BUDGET[4.0][0], "a street of bodies: draw calls within %d" % BUDGET[4.0][0])
	check(m[1] <= BUDGET[4.0][1], "a street of bodies: a frame within %.0f ms" % BUDGET[4.0][1])
