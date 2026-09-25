extends "res://tests/test_base.gd"
## Saves survive updates: old formats are upgraded, damaged saves fall back to
## their backup, and saves the game cannot use are never written over.


func _path() -> String:
	return SaveGame.dir() + "/world.save"


func _raw(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = f.get_var()
	return v if v is Dictionary else {}


func _store(path: String, d: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_var(d)
	f.close()


func run() -> void:
	SaveGame.wipe()

	# --- A version 1 save (the old format) loads and is upgraded. ---
	await host(9320)
	main.day = 6
	main.next_zid = 500
	var z := zombie_at(me.position + Vector2(200, 0))
	var zid := z.zid
	main._give(me, "water")
	me.hunger = 44.0
	main._save_all()
	await close_game()
	var w := _raw(_path())
	w.version = 1
	w.erase("boxes")
	w.erase("game")
	w.erase("saved_at")
	for e in w.zombies:
		e.resize(4)  # v1 had no lost-arm bits
	_store(_path(), w)
	var ppath := SaveGame._player_path("Tester")
	var pl := _raw(ppath)
	pl.version = 1
	pl.erase("worn")
	_store(ppath, pl)

	await host(9321, true, false)
	check(main.in_game, "a version 1 save still loads")
	check(main.day == 6, "its day came back (%d)" % main.day)
	check(main.zombies.has(zid), "its zombies came back")
	check(absf(me.hunger - 44.0) < 0.5 and count(me, "water") == 1, "the version 1 player came back")
	check(FileAccess.file_exists(_path() + ".v1"), "the version 1 file was kept as world.save.v1")
	main._save_all()
	check(_raw(_path()).version == SaveGame.VERSION, "saving writes the new version (%d)" % _raw(_path()).version)
	check(FileAccess.file_exists(_path() + ".bak"), "the save before it is kept as .bak")
	await close_game()

	# --- A damaged save falls back to its backup. ---
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	f.store_string("this is not a save file")
	f.close()
	check(SaveGame.load_world().state == "ok", "a damaged save loads from its .bak")
	await host(9322, true, false)
	check(main.in_game and main.day == 6, "and the game starts from it (day %d)" % main.day)
	await close_game()

	# --- Both damaged: refuse, and leave the files alone. ---
	for p in [_path(), _path() + ".bak"]:
		var g := FileAccess.open(p, FileAccess.WRITE)
		g.store_string("broken")
		g.close()
	check(SaveGame.load_world().state == "corrupt", "save and backup both damaged: reported as corrupt")
	check(SaveGame.world_info().has("problem"), "the menu gets a message instead of 'continue'")
	await host(9323, true, false)
	check(not main.in_game, "the game refuses to start over it")
	check(FileAccess.get_file_as_string(_path()) == "broken", "and does not write over it")
	await close_game()

	# --- A save from a newer game is not touched either. ---
	_store(_path(), {version = SaveGame.VERSION + 5, seed = 1, day = 99})
	check(SaveGame.load_world().state == "newer", "a save from a newer game is recognised")
	await host(9324, true, false)
	check(not main.in_game, "the game will not run it")
	check(_raw(_path()).version == SaveGame.VERSION + 5, "and leaves it exactly as it was")
	await close_game()

	# --- A new city moves the old one aside instead of deleting it. ---
	SaveGame.wipe()
	var prev := ProjectSettings.globalize_path(SaveGame.dir()) + "-previous"
	check(FileAccess.file_exists(prev + "/world.save"), "'new city' keeps the old one in <slot>-previous")
	check(not SaveGame.has_world(), "and the slot is empty for the new city")

	# A new player's save, written while a newer one exists, does not overwrite it.
	await host(9325)
	_store(ppath, {version = SaveGame.VERSION + 1, name = "Tester", alive = true})
	SaveGame.save_player(me)
	check(_raw(ppath).version == SaveGame.VERSION + 1, "a newer player save is not written over")
	await close_game()
	SaveGame.wipe()
