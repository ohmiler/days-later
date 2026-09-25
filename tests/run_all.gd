extends SceneTree
## Runs every tests/test_*.gd in its own Godot process and prints a summary.
##   godot --headless --path . -s res://tests/run_all.gd
## Exit code is 0 only if every test passed. Add `-- name` to run matching ones only.


func _initialize() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]
	var files := []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_base.gd" and (filter == "" or f.contains(filter)):
			files.append(f)
	files.sort()
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var failed := []
	var total_pass := 0
	var total_fail := 0
	var started := Time.get_ticks_msec()
	for f in files:
		var out := []
		var t0 := Time.get_ticks_msec()
		var code := OS.execute(exe, ["--headless", "--path", project, "-s", "res://tests/" + f], out, true)
		var text: String = "\n".join(out)
		var lines: Array = Array(text.split("\n"))
		var fails: Array = lines.filter(func(l): return l.strip_edges().begins_with("FAIL"))
		var passes: Array = lines.filter(func(l): return l.strip_edges().begins_with("PASS"))
		var errors: Array = lines.filter(func(l): return l.begins_with("SCRIPT ERROR"))
		total_pass += passes.size()
		total_fail += fails.size() + errors.size()
		var ok: bool = code == 0 and fails.is_empty() and errors.is_empty()
		print("%s  %-26s %3d passed  %2d failed  (%.1f s)" % ["OK  " if ok else "FAIL", f.get_basename(), passes.size(),
				fails.size() + errors.size(), (Time.get_ticks_msec() - t0) / 1000.0])
		for l in fails + errors:
			print("        " + l.strip_edges())
		if not ok:
			failed.append(f)
			if passes.is_empty() and fails.is_empty():
				# It never got going: show the end of its output.
				for l in lines.slice(maxi(0, lines.size() - 12)):
					print("        | " + l)
	print("")
	print("%d test files, %d checks passed, %d failed, %.0f s" % [files.size(), total_pass, total_fail,
			(Time.get_ticks_msec() - started) / 1000.0])
	print("ALL PASSED" if failed.is_empty() else "FAILED: " + ", ".join(failed))
	quit(0 if failed.is_empty() else 1)
