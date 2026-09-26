extends "res://tests/test_base.gd"
## Two real processes over the network: a client joins this host, and both
## sides should agree on players, looks, chat and snapshots.

const PORT := 9307


func run() -> void:
	await host(PORT, false, false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://net_client.txt"))
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tests/helpers/net_client.gd", "--", str(PORT)])
	check(pid > 0, "client process started")
	# Wait for it to join.
	var joined: Player = null
	for i in 80:
		await wait(0.1)
		for p: Player in main.players.values():
			if p.peer_id != 1:
				joined = p
		if joined and joined.pname != "":
			break
	check(joined != null, "the client joined")
	if joined == null:
		return
	check(joined.pname == "Client", "its name arrived (%s)" % joined.pname)
	var want := Look.pack({skin = 2, hair = 3, style = 1, shirt = 4, pants = 2, build = 2})
	check(joined.app_code == want, "its chosen look arrived (%d)" % joined.app_code)
	# Say something back, and open a cupboard for it.
	# (Waiting for it rather than a fixed time: how long the client takes to
	# build its city depends on the machine.)
	for i in 200:
		if joined.say == "hello from the client":
			break
		await wait(0.1)
	main.net.req_chat("hello from the host")
	check(joined.say == "hello from the client", "its chat arrived here")
	# (A cupboard near the host, so the client stands among the same zombies.)
	var f: FurnitureProp = main.world.container_nodes[0]
	for c: FurnitureProp in main.world.container_nodes:
		if not c.data.get("up", false) and c.position.distance_to(me.position) < f.position.distance_to(me.position):
			f = c
	f.searched = true
	joined.position = f.position + Vector2(0, 8)
	# Two zombies by the client, two far off (poking about, so they stay): it
	# should be sent the two around it.
	main.spawn_timer = 1e9
	for z in main.zombies.values():
		z.queue_free()
	main.zombies.clear()
	for off in [Vector2(40, 0), Vector2(-40, 10), Vector2(Main.NEAR * 2.0, 0), Vector2(0, Main.NEAR * 2.0)]:
		var z := zombie_at(joined.position + off)
		z.stun = 1e9  # (standing still)
		z.investigate_t = 1e9
	main.actions._do_action(joined, {kind = "container", id = f.data.id}, "look")
	# Wait for its report.
	var path := ProjectSettings.globalize_path("user://net_client.txt")
	for i in 200:
		if FileAccess.file_exists(path):
			break
		await wait(0.1)
	check(FileAccess.file_exists(path), "the client reported back")
	if not FileAccess.file_exists(path):
		return
	await wait(0.2)
	var seen := {}
	for l in FileAccess.get_file_as_string(path).split("\n"):
		var parts := l.split(" ", true, 1)
		if parts.size() == 2:
			seen[parts[0]] = parts[1]
	check(seen.get("players") == "2", "the client sees both players")
	check(seen.get("zombies") == "2", "the client is sent the zombies around it, not the ones far off (%s of %d)" % [seen.get("zombies"), main.zombies.size()])
	check(seen.get("own_code") == str(want), "the client kept its own look")
	check(seen.get("host_name") == "Tester", "the client knows the host's name")
	check(seen.get("host_said") == "hello from the host", "the host's chat reached the client")
	check(seen.get("box") == str(f.data.id), "opening a cupboard for the client opened its bag screen")
	check(seen.get("zone") == Zones.first(), "the client is in the host's zone")

	# The host goes on to the next zone: the client comes too.
	var zpath := ProjectSettings.globalize_path("user://net_client_zone.txt")
	DirAccess.remove_absolute(zpath)
	var ex: Dictionary = main.world.exits.filter(func(e): return Zones.open(e.to))[0]
	main.travel(me, ex)
	for i in 200:
		if FileAccess.file_exists(zpath):
			break
		await wait(0.1)
	var after := {}
	for l in FileAccess.get_file_as_string(zpath).split("\n"):
		var parts := l.split(" ", true, 1)
		if parts.size() == 2:
			after[parts[0]] = parts[1]
	check(after.get("zone") == ex.to, "the client followed the group to %s (%s)" % [ex.to, after.get("zone", "nothing")])
	check(after.get("stand") == "true" and after.get("players") == "2", "standing there with the host (%s)" % [after])
