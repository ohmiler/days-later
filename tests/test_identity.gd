extends "res://tests/test_base.gd"
## Names belong to whoever made them (proven by their copy's secret), and an
## out-of-date copy of the game is turned away with a message.

const PORT := 9330


func _fake_player(id: int) -> Player:
	var p: Player = main._add_player(id)
	return p


func run() -> void:
	SaveGame.wipe()
	await host(PORT)
	# The host's own survivor has an owner already.
	check(me.secret_hash != "", "the host's survivor is owned by its secret")

	# Somchai plays and leaves a save.
	var a := _fake_player(501)
	main._claim_name(a, "Somchai", "secret-A")
	check(a.pname == "Somchai", "a new name is yours")
	main._give(a, "machete")
	SaveGame.save_player(a)
	main.players.erase(501)
	a.queue_free()

	# Someone else asks for Somchai: they get a different name, and not his bag.
	var b := _fake_player(502)
	main._claim_name(b, "Somchai", "secret-B")
	check(b.pname != "Somchai" and b.pname.begins_with("Somchai"), "another person gets a variation (%s)" % b.pname)
	check(count(b, "machete") == 0, "and none of the real Somchai's things")
	main.players.erase(502)
	b.queue_free()

	# The real Somchai comes back with his secret and gets everything back.
	var c := _fake_player(503)
	main._claim_name(c, "Somchai", "secret-A")
	check(c.pname == "Somchai" and count(c, "machete") == 1, "the owner comes back to his own survivor")
	main.players.erase(503)
	c.queue_free()

	# A save from before names had owners goes to whoever uses the name first.
	var old_path := SaveGame._player_path("Oldtimer")
	SaveGame._write(old_path, {version = 2, name = "Oldtimer", alive = true, pos = me.position, on_roof = false,
			hp = 77.0, kills = 3, hunger = 50.0, thirst = 50.0, infection = 0.0, bleeding = false, stamina = 100.0,
			inv = [], sel = 0, worn = {}})
	var d := _fake_player(504)
	main._claim_name(d, "Oldtimer", "secret-D")
	check(d.pname == "Oldtimer" and absf(d.hp - 77.0) < 0.5, "an old save with no owner is claimed by the first to use it")
	SaveGame.save_player(d)
	check(SaveGame.owner_of("Oldtimer") == "secret-D".sha256_text(), "and from then on it is theirs")
	check(not FileAccess.get_file_as_string(old_path).contains("secret-D"), "the secret itself is never saved, only its fingerprint")
	main.players.erase(504)
	d.queue_free()

	# Two people online cannot be the same survivor even with the same secret.
	var e1 := _fake_player(505)
	var e2 := _fake_player(506)
	main._claim_name(e1, "Twin", "same")
	main._claim_name(e2, "Twin", "same")
	check(e1.pname != e2.pname, "one name, one person online at a time")

	# An out-of-date copy of the game is turned away with a message.
	var path := ProjectSettings.globalize_path("user://net_client.txt")
	DirAccess.remove_absolute(path)
	var before: int = main.players.size()
	OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tests/helpers/net_client.gd", "--", str(PORT), "old"])
	for i in 80:
		if FileAccess.file_exists(path):
			break
		await wait(0.1)
	await wait(0.2)
	var got := {}
	for l in FileAccess.get_file_as_string(path).split("\n"):
		var parts := l.split(" ", true, 1)
		if parts.size() == 2:
			got[parts[0]] = parts[1]
	check(got.get("in_game") == "false", "an old copy never gets into the city")
	check(got.get("status", "").contains("อัปเดต"), "and is told to update (%s)" % got.get("status", ""))
	check(main.players.size() == before, "the server gave it no body")
	SaveGame.wipe()
