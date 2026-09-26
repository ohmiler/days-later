extends SceneTree
## Base for automated tests. A test extends this file and writes `func run()`,
## using `await` freely (wait(), frames()). Each check() prints PASS or FAIL;
## when run() returns the process exits with code 1 if anything failed.
##
## Run one:   godot --headless --path . -s res://tests/test_inventory.gd
## Run all:   godot --headless --path . -s res://tests/run_all.gd
##
## Tests always use the "test" save slot (see SaveGame.dir), never real saves.

var main: Node
var me: Player
var failures := 0
var passes := 0
var _name := ""


func _initialize() -> void:
	_name = (get_script() as Script).resource_path.get_file().get_basename()
	_go.call_deferred()


func _go() -> void:
	await run()
	print("RESULT %s: %d passed, %d failed" % [_name, passes, failures])
	quit(1 if failures > 0 else 0)


## Override in the test.
func run() -> void:
	pass


func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
		print("  PASS  " + what)
	else:
		failures += 1
		print("  FAIL  " + what)


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func frames(n := 1) -> void:
	for i in n:
		await process_frame


## A fresh game hosted on `port`, with its zombies cleared out of the way so
## each test places exactly the ones it wants.
func host(port: int, resume := false, clear_zombies := true) -> void:
	Zombie.grab_chance = 0.0  # (a lunge bites, every time: grabbing is test_grab's, which asks for it)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await frames(2)
	main.port = port
	main.player_name = "Tester"
	main._host(false, resume)
	me = main.players.get(1)  # none if the game refused to start
	if clear_zombies and me:
		for z in main.zombies.values():
			z.queue_free()
		main.zombies.clear()
	await frames(2)


## Shut the current game down (so another can be hosted in the same process).
func close_game() -> void:
	if main == null:
		return
	if main.multiplayer.multiplayer_peer:
		main.multiplayer.multiplayer_peer.close()
	main.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	main.queue_free()
	main = null
	me = null
	await frames(3)


## A zombie of a given breed right where you want it.
func zombie_at(pos: Vector2, kind := "normal") -> Zombie:
	var z: Zombie = main._add_zombie(main.next_zid, pos)
	main.next_zid += 1
	z.set_kind(kind)
	z.hp = z.max_hp
	return z


## Run the server for `seconds` of game time, in fixed steps.
func simulate(seconds: float, step := 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		main._server_tick(step)
		t += step


func bag(p: Player) -> String:
	var parts := []
	for it in p.inv:
		parts.append("-" if it == null else "%s%d" % [it.id, it.n])
	return " ".join(parts)


func count(p: Player, id: String) -> int:
	var n := 0
	for it in p.inv:
		if it != null and it.id == id:
			n += it.n
	return n
