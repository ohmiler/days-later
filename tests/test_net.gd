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
	await wait(2.2)
	main.net.req_chat("hello from the host")
	check(joined.say == "hello from the client", "its chat arrived here")
	var f: FurnitureProp = main.world.container_nodes[0]
	f.searched = true
	joined.position = f.position + Vector2(0, 8)
	main.actions._do_action(joined, {kind = "container", id = 0}, "look")
	# Wait for its report.
	var path := ProjectSettings.globalize_path("user://net_client.txt")
	for i in 100:
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
	check(int(seen.get("zombies", "0")) == main.zombies.size(), "the client sees the same zombies (%s / %d)" % [seen.get("zombies"), main.zombies.size()])
	check(seen.get("own_code") == str(want), "the client kept its own look")
	check(seen.get("host_name") == "Tester", "the client knows the host's name")
	check(seen.get("host_said") == "hello from the host", "the host's chat reached the client")
	check(seen.get("box") == "0", "opening a cupboard for the client opened its bag screen")
