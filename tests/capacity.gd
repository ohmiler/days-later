extends "res://tests/test_base.gd"
## How many players one server process can carry (not in run_all: it's a
## measurement). Bots stand in for players: survivors walking about the zone,
## each with the zombies the game gives a player (Survival._spawn_zombie up
## to MAX_ZOMBIES round each), the shut-in dead of the big buildings let out
## when they come near, the camp's guards, everything a real server runs.
## What it can't count is sending the snapshots (the bots have no connection:
## see test_bandwidth for that, ~3.5 KB/s a player).
##
## Run: godot --headless --path . -s res://tests/capacity.gd
##      (-- --counts=1,10,20 --spread=apart|together --secs=6)

const TICK := 1.0 / 30.0  # the server's step (it runs at 30 a second: Main.SERVER_FPS)


func _bots(n: int, together: bool, rng: RandomNumberGenerator) -> void:
	var w: World = main.world
	var base := me.position
	for i in n - main.players.size():
		var q: Player = main._add_player(1000 + main.players.size())
		q.pname = "bot%d" % q.peer_id
		for tries in 200:
			var at := base + Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90)) if together \
					else w.to_pos(Vector2i(rng.randi_range(8, World.W - 8), rng.randi_range(8, World.H - 8)))
			if w.can_stand(at, 5) and not w.building_at.has(w.to_cell(at)):
				q.position = at
				break
		q.hp = 1e9  # (bots don't die: a dead one stops costing anything)


## Bots wander: a new direction every few seconds, now and then standing still.
func _steer(rng: RandomNumberGenerator) -> void:
	for p: Player in main.players.values():
		p.hp = 1e9
		if rng.randf() < TICK / 3.0:
			p.move = Vector2.ZERO if rng.randf() < 0.25 else Vector2.from_angle(rng.randf() * TAU)


func _measure(secs: float, rng: RandomNumberGenerator) -> Dictionary:
	var times := []
	var t := 0.0
	while t < secs:
		_steer(rng)
		var t0 := Time.get_ticks_usec()
		main._server_tick(TICK)
		times.append(Time.get_ticks_usec() - t0)
		t += TICK
	times.sort()
	var sum := 0.0
	for x in times:
		sum += x
	return {avg = sum / times.size() / 1000.0, p95 = times[int(times.size() * 0.95)] / 1000.0, zombies = main.zombies.size()}


func run() -> void:
	var counts := [1, 5, 10, 20, 40]
	var together := false
	var secs := 6.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--counts="):
			counts = Array(a.trim_prefix("--counts=").split(",")).map(func(s): return int(s))
		elif a == "--spread=together":
			together = true
		elif a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
	Survival.trapped_on = true
	Camp.safe_on = true
	await host(9412)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	me.hp = 1e9
	print("")
	print("players  zombies  server tick avg / p95 (ms)  share of one core at 30/s   where it goes")
	for n in counts:
		_bots(n, together, rng)
		# Fill each player's surroundings with zombies, as a while of play would.
		for i in n * Main.MAX_ZOMBIES * 2:
			main.survival._spawn_zombie()
		var warm := _measure(2.0, rng)  # (let them settle: targets, paths, the shut-in let out)
		Main.profiling = true
		for k in main.prof:
			main.prof[k] = 0
		var m := _measure(secs, rng)
		Main.profiling = false
		var total: float = m.avg * secs / TICK * 1000.0
		print("%7d  %7d  %10.2f / %6.2f          %5.0f%%     (zombie thinking %.0f%%, pushing apart %.0f%%, the rest %.0f%%)" % [n, m.zombies, m.avg, m.p95,
				m.avg * 30.0 / 10.0, 100.0 * main.prof.ai / total, 100.0 * main.prof.separate / total, 100.0 * (1.0 - float(main.prof.ai + main.prof.separate) / total)])
	print("")
	quit(0)
