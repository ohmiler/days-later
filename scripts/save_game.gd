class_name SaveGame
## Saving and loading. The world is saved as its seed plus everything that
## changed since it was generated; each player is saved in their own file,
## keyed by name, so player data can later move to a central database
## without touching the world format.
##
##   user://saves/<world>/world.save
##   user://saves/<world>/players/<name>.save

const VERSION := 1


## One save slot unless `-- --slot=name` picks another. Automated test runs
## (started with `-s script`, which replaces the main loop) always get their
## own slot so they never touch a real save.
static func dir() -> String:
	var slot := "city"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			slot = arg.trim_prefix("--slot=").validate_filename()
	if Engine.get_main_loop().get_script() != null:
		slot = "test"
	return "user://saves/%s" % slot


static func has_world() -> bool:
	return FileAccess.file_exists(dir() + "/world.save")


## Small summary for the title menu, or {} if there is no save.
static func world_info() -> Dictionary:
	var w := _read(dir() + "/world.save")
	return {day = w.get("day", 1)} if not w.is_empty() else {}


static func save_world(main: Node) -> void:
	var world: World = main.world
	var doors := []
	for d in world.doors:
		doors.append([d.id, d.closed, d.hp, d.boards, d.broken, d.kind if world.is_built(d.id) else "", d.cell])
	var searched := []
	for f: FurnitureProp in world.container_nodes:
		if f.searched:
			searched.append(f.data.id)
	var items := []
	for pid in main.pickups:
		items.append([pid, main.pickups[pid].pos, main.pickups[pid].item])
	var zs := []
	for z: Zombie in main.zombies.values():
		zs.append([z.zid, z.position, z.hp, z.outfit])
	_write(dir() + "/world.save", {
		version = VERSION, seed = main.world_seed, day = main.day, time = main.time,
		next_zid = main.next_zid, next_pickup = main.next_pickup,
		doors = doors, searched = searched, pickups = items, zombies = zs,
	})


## Load the saved world into a freshly generated one (server only).
## Returns false if there is nothing usable to load.
static func load_world_into(main: Node, w: Dictionary) -> bool:
	if w.get("version", 0) != VERSION:
		return false
	var world: World = main.world
	main.day = w.day
	main.time = w.time
	main.next_zid = w.next_zid
	main.next_pickup = w.next_pickup
	for e in w.doors:
		if e[5] != "":
			world.add_structure(e[0], e[6], e[5], e[2])
		if e[0] < world.doors.size():
			world.set_door(e[0], e[1], e[2], e[3], e[4])
	for id in w.searched:
		if id < world.container_nodes.size():
			world.container_nodes[id].set_searched(true)
	for e in w.pickups:
		main.pickups[e[0]] = {pos = e[1], item = e[2]}
	for e in w.zombies:
		if not e[3].is_empty():
			main.outfits[e[0]] = e[3]
		var z: Zombie = main._add_zombie(e[0], e[1])
		z.hp = e[2]
	return true


static func read_world() -> Dictionary:
	return _read(dir() + "/world.save")


static func save_player(p: Player) -> void:
	if p.pname == "":
		return
	_write(_player_path(p.pname), {
		version = VERSION, name = p.pname, alive = p.alive(),
		pos = p.position, on_roof = p.on_roof, hp = p.hp, kills = p.kills,
		hunger = p.hunger, thirst = p.thirst, infection = p.infection, bleeding = p.bleeding, stamina = p.stamina,
		inv = p.inv, sel = p.sel,
	})


## Put a returning player back how they left. Returns false for a new name.
static func load_player_into(p: Player, name: String) -> bool:
	var d := _read(_player_path(name))
	if d.get("version", 0) != VERSION or not d.get("alive", false):
		return false  # new survivor, or they were dead when they left
	p.position = d.pos
	p.net_pos = d.pos
	p.on_roof = d.on_roof
	p.hp = d.hp
	p.kills = d.kills
	p.hunger = d.hunger
	p.thirst = d.thirst
	p.infection = d.infection
	p.bleeding = d.bleeding
	p.stamina = d.stamina
	var inv: Array = d.inv
	inv.resize(Items.INV_SIZE)
	p.inv = inv
	p.sel = clampi(d.sel, 0, Items.INV_SIZE - 1)
	return true


static func wipe() -> void:
	for sub in ["/players", ""]:
		var da := DirAccess.open(dir() + sub)
		if da == null:
			continue
		for f in da.get_files():
			da.remove(f)


static func _player_path(name: String) -> String:
	var safe := name
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]:
		safe = safe.replace(bad, "_")
	return dir() + "/players/%s.save" % safe


static func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	# Write to a temp file first so a crash mid-save never leaves a broken save.
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save %s" % path)
		return
	f.store_var(data)
	f.close()
	DirAccess.rename_absolute(tmp, path)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = f.get_var()
	return v if v is Dictionary else {}
