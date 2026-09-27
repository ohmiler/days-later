class_name PerfOverlay
extends Label
## F3: how fast the game is running here, in the corner. For measuring on
## other machines (the browser, a phone), where tests/perf.gd can't run.
## Over the last second: frames a second, the average and the worst frame,
## draw calls, and zombies (all of them / on screen).
##
## In the browser the address can do it too (keys don't always reach a page):
## ?perf shows it; ?bench=N, on a server started with --admin, makes it noon
## and brings N zombies around you (you can't be hurt meanwhile), to measure
## against: all of them coming at you, the worst case.

var _times: Array[float] = []
var _t := 0.0
var _bench := -1  # zombies still to ask for (?bench=N); -1: none asked


func _query() -> String:
	return str(JavaScriptBridge.eval("window.location.search", true)) if OS.has_feature("web") else ""


func _ready() -> void:
	visible = false
	position = Vector2(12, 60)
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", Color(1, 1, 0.6))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var q := _query()
	visible = "perf" in q
	for part in q.trim_prefix("?").split("&"):
		if part.begins_with("bench="):
			_bench = int(part.trim_prefix("bench="))


func _process(delta: float) -> void:
	_start_bench()
	_times.append(delta)
	if _times.size() > 120:
		_times.pop_front()
	_t -= delta
	if not visible or _t > 0.0:
		return
	_t = 0.25
	var sum := 0.0
	var worst := 0.0
	for d in _times:
		sum += d
		worst = maxf(worst, d)
	var avg := sum / maxf(1.0, _times.size())
	var main = get_parent().get_parent()
	var zs := 0
	var shown := 0
	if main is Main:
		zs = main.zombies.size()
		for z in main.zombies.values():
			if z.visible:
				shown += 1
	text = "%d fps · frame %.1f ms (worst %.1f) · draw calls %d · zombies %d (on screen %d)%s" % [
			Engine.get_frames_per_second(), avg * 1000.0, worst * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), zs, shown,
			" · web" if OS.has_feature("web") else ""]


## Once in the game: noon, and the zombies asked for, in rows around you.
func _start_bench() -> void:
	if _bench <= 0:
		return
	var main = get_parent().get_parent()
	if not (main is Main) or not main.in_game:
		return
	var me: Player = main.players.get(main.multiplayer.get_unique_id())
	if me == null:
		return
	main._request(&"req_time", [0.5])
	main._request(&"req_toggle", ["god"])
	var left := _bench
	var ring := 0
	while left > 0:
		var n := mini(left, 20)
		main._request(&"req_zombie", [me.position + Vector2.from_angle(ring * 1.7) * (70.0 + ring * 25.0), "", n, false, false])
		left -= n
		ring += 1
	_bench = 0
