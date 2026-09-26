class_name SaveGame
## Saving and loading. The world is saved as its seed plus everything that
## changed since it was generated; each player is saved in their own file,
## keyed by name, so player data can later move to a central database
## without touching the world format.
##
##   user://saves/<world>/zones/<zone>/world.save   (+ .bak: the save before it)
##   user://saves/<world>/players/<name>.save       (+ .bak; one per survivor, whatever zone)
##
## Saves carry a format VERSION. When the format changes, bump VERSION and add
## a step to MIGRATIONS that turns version N into N+1; old saves are upgraded
## one step at a time when loaded, and the file as it was is kept beside it
## (world.save.v1 and so on). A save that cannot be read, or that comes from a
## newer game, is never written over: the game says so and leaves it alone.

const VERSION := 11
const GAME_VERSION := "0.4"  # shown to people; not used for compatibility

## [kind, from version] -> the function that upgrades it one step.
const MIGRATIONS := {
	"world:1": "_world_1_to_2",
	"player:1": "_player_1_to_2",
	"player:2": "_player_2_to_3",
	"world:3": "_world_3_to_4",
	"player:4": "_player_4_to_5",
	"player:5": "_player_5_to_6",
	"world:5": "_world_5_to_6",
	"world:6": "_world_6_to_7",
	"world:7": "_world_7_to_8",
	"player:7": "_player_7_to_8",
	"world:8": "_world_8_to_9",
	"player:9": "_player_9_to_10",
	"player:10": "_player_10_to_11",
}


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


## The zone whose world is saved and loaded (Main sets it; see Zones).
static var zone := ""


## The zone the group was last in (a game with friends resumes there).
static func last_zone() -> String:
	var f := FileAccess.open(dir() + "/zone.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""


static func world_dir() -> String:
	return dir() + "/zones/" + (zone if zone != "" else Zones.first())


static func has_world() -> bool:
	for p in [world_dir() + "/world.save", world_dir() + "/world.save.bak", dir() + "/world.save"]:
		if FileAccess.file_exists(p):
			return true
	return false


## For the title menu: {day} for a save that can be continued, {problem} for
## one that cannot (a message to show), or {} if there is none.
static func world_info() -> Dictionary:
	var r := load_world()
	match r.state:
		"ok":
			return {day = r.data.get("day", 1)}
		"newer":
			return {problem = "เซฟนี้มาจากเกมเวอร์ชันใหม่กว่า · อัปเดตเกมก่อนเล่นต่อ"}
		"oldcity":
			return {day = r.data.get("day", 1), oldcity = true}
		"corrupt":
			return {problem = "อ่านเซฟไม่ได้ · เก็บไฟล์ไว้ให้แล้ว ไม่ได้ลบ"}
	return {}


static func save_world(main: Node) -> void:
	var world: World = main.world
	var doors := []
	for d in world.doors:
		doors.append([d.id, d.closed, d.hp, d.boards, d.broken, d.kind if world.is_built(d.id) else "", d.cell])
	var searched := []
	var stripped := []
	var boxes := {}  # container id -> slots, for any that hold something
	for f: FurnitureProp in world.container_nodes:
		if f.searched:
			searched.append(f.data.id)
		if f.stripped:
			stripped.append(f.data.id)
		if f.items.any(func(x): return x != null):
			boxes[f.data.id] = f.items
	var items := []
	for pid in main.pickups:
		items.append([pid, main.pickups[pid].pos, main.pickups[pid].item, main.pickups[pid].get("up", false)])
	var zs := []
	for z: Zombie in main.zombies.values():
		zs.append([z.zid, z.position, z.hp, z.outfit, z.missing])
	# (No need to check the file first: a world save we cannot use stops the
	# game from starting at all, so we only get here with one we loaded.)
	var zf := FileAccess.open(dir() + "/zone.txt", FileAccess.WRITE)
	if zf:
		zf.store_string(zone)
		zf.close()
	_write(world_dir() + "/world.save", {
		version = VERSION, game = GAME_VERSION, saved_at = int(Time.get_unix_time_from_system()),
		seed = main.world_seed, gen = CityGen.GEN, day = main.day, time = main.time,
		next_zid = main.next_zid, next_pickup = main.next_pickup,
		doors = doors, searched = searched, stripped = stripped, boxes = boxes, pickups = items, zombies = zs,
		things = main.things.changed(), vehicles = main.vehicles.changed(),
	})


## Read the world save: {state, data}. state is "none", "ok", "newer" (from a
## newer game), "corrupt" (neither the save nor its backup could be read) or
## "oldcity" (made by an older city generator: its seed no longer builds the
## same city, so it cannot be carried on; see move_to_new_city).
static func load_world() -> Dictionary:
	var r := _load(world_dir() + "/world.save", "world")
	if r.state == "none" and FileAccess.file_exists(dir() + "/world.save"):
		r = _load(dir() + "/world.save", "world")  # (from before zones: one city for the whole slot)
		if r.state == "ok":
			r.state = "oldcity"
	if r.state == "ok" and r.data.get("gen", 1) != CityGen.GEN:
		r.state = "oldcity"
	return r


## Put an old-generator city aside (world.save becomes world.gen1.save and so
## on, never deleted) so a new city starts in the same slot. The survivors'
## saves stay: they carry their things into the new city.
static func move_to_new_city() -> void:
	var r := load_world()
	var gen: int = r.data.get("gen", 1)
	for base in [dir(), world_dir()]:
		for ext in ["", ".bak"]:
			var from: String = base + "/world.save" + ext
			if FileAccess.file_exists(from):
				DirAccess.rename_absolute(from, base + "/world.gen%d.save%s" % [gen, ext])


## Load the saved world into a freshly generated one (server only).
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
	for id in w.boxes:
		if id < world.container_nodes.size():
			var items: Array = w.boxes[id]
			items.resize(FurnitureProp.SIZE)
			world.container_nodes[id].items = items
	main.things.restore(w.things)
	main.vehicles.restore(w.vehicles)
	for id in w.searched:
		if id < world.container_nodes.size():
			world.container_nodes[id].set_searched(true)
	for id in w.stripped:
		if id < world.container_nodes.size():
			world.container_nodes[id].set_stripped(true)
	for e in w.pickups:
		main.pickups[e[0]] = {pos = e[1], item = e[2], up = e[3] if e.size() > 3 else false}
	for e in w.zombies:
		if not e[3].is_empty():
			main.outfits[e[0]] = e[3]
		var z: Zombie = main._add_zombie(e[0], e[1])
		z.hp = e[2]
		z.missing = e[4]
	return true


static func read_world() -> Dictionary:
	var r := load_world()
	return r.data if r.state == "ok" else {}


static func save_player(p: Player) -> void:
	if p.pname == "":
		return
	var path := _player_path(p.pname)
	if _blocked(path):
		return
	_write(path, {
		version = VERSION, name = p.pname, alive = p.alive(),
		pos = p.position, on_roof = p.on_roof, up = p.up, hp = p.hp, kills = p.kills,
		hunger = p.hunger, thirst = p.thirst, infection = p.infection, bleeding = p.bleeding, stamina = p.stamina,
		inv = p.inv, sel = p.sel, worn = p.worn, secret_hash = p.secret_hash, bed = p.bed, wounds = p.wounds,
		city = p.world.city_seed if p.world else 0, zone = p.world.zone if p.world else "",
		travel_to = p.travel_to, travel_exit = p.travel_exit,
	})


## Fingerprint of the secret that owns this name's save, or "" if nobody does.
static func owner_of(name: String) -> String:
	var r := _load(_player_path(name), "player")
	return r.data.get("secret_hash", "") if r.state == "ok" else ("?" if r.state != "none" else "")


## Put a returning player back how they left. Returns false for a new name.
static func load_player_into(p: Player, name: String) -> bool:
	var r := _load(_player_path(name), "player")
	if r.state != "ok":
		return false
	var d: Dictionary = r.data
	var same_city: bool = p.world != null and d.city == p.world.city_seed and d.get("zone", p.world.zone) == p.world.zone
	p.bed = d.bed if same_city else -1  # kept even after dying: the next survivor wakes there
	if not d.get("alive", false):
		return false  # they were dead when they left: a new survivor
	# Came in from another zone: at the way in they took. Moved to a new
	# city: they keep what they carry, and start at the spawn corner.
	p.position = d.pos if same_city else p.world.spawn_point()
	if d.get("travel_to", "") == p.world.zone and d.get("travel_exit", "") != "":
		p.position = p.world.arrival_of(d.travel_exit)
		same_city = false
	p.travel_to = ""
	p.travel_exit = ""
	p.net_pos = d.pos
	p.on_roof = d.on_roof and same_city
	p.up = d.get("up", false) and same_city and p.world.upper.has(p.world.to_cell(p.position))
	p.hp = d.hp
	p.kills = d.kills
	p.hunger = d.hunger
	p.thirst = d.thirst
	p.infection = d.infection
	p.bleeding = d.bleeding
	p.wounds = d.wounds
	p.stamina = d.stamina
	p.worn = d.worn
	p.refresh_wear()
	var inv: Array = d.inv
	inv.resize(p.bag_size())
	p.inv = inv
	p.sel = clampi(d.sel, 0, mini(inv.size(), Items.INV_SIZE) - 1)
	return true


## Start a new city. The old one is moved aside as <slot>-previous (replacing
## any older one), so a mistaken "new city" can still be undone by hand.
static func wipe() -> void:
	var here := ProjectSettings.globalize_path(dir())
	if not DirAccess.dir_exists_absolute(here):
		return
	var prev := here + "-previous"
	_remove_tree(prev)
	if DirAccess.rename_absolute(here, prev) != OK:
		_remove_tree(here)  # could not move it: at least start clean


# --- Versions -------------------------------------------------------------------

## v2 made every optional field always present.
static func _world_1_to_2(d: Dictionary) -> Dictionary:
	d.merge({boxes = {}, game = "0.3", saved_at = 0}, false)
	for e in d.zombies:
		while e.size() < 5:
			e.append({} if e.size() == 3 else 0)  # outfit, then lost-arm bits
	return d


## v4 saves the state of taps, radios and the like.
static func _world_3_to_4(d: Dictionary) -> Dictionary:
	d.merge({things = {}}, false)
	return d


static func _player_1_to_2(d: Dictionary) -> Dictionary:
	d.merge({worn = {}}, false)
	return d


## v3 remembers who owns the name. Old saves have no owner yet: the first to
## come back with that name claims it.
static func _player_2_to_3(d: Dictionary) -> Dictionary:
	d.merge({secret_hash = ""}, false)
	return d


## v5 remembers the bed a survivor calls home.
static func _player_4_to_5(d: Dictionary) -> Dictionary:
	d.merge({bed = -1}, false)
	return d


## v6 wears vests over shirts: the "over" slot. Vests worn in "body" move up.
const _OVER := ["vest", "rider"]


static func _player_5_to_6(d: Dictionary) -> Dictionary:
	var worn: Dictionary = d.get("worn", {})
	if worn.get("body") != null and worn.body.id in _OVER:
		worn.over = worn.body
		worn.erase("body")
	return d


## ...and so do the clothes of survivors who turned (zombie outfits).
static func _world_5_to_6(d: Dictionary) -> Dictionary:
	for e in d.zombies:
		if e[3] is Array and e[3].size() > 3 and e[3][3].get("body", "") in _OVER:
			e[3][3].over = e[3][3].body
			e[3][3].erase("body")
	return d


## v7 remembers furniture pulled apart for materials.
static func _world_6_to_7(d: Dictionary) -> Dictionary:
	d.merge({stripped = []}, false)
	return d


## v8 remembers which city generator made the city (1 before this) and which
## city each survivor was in.
static func _world_7_to_8(d: Dictionary) -> Dictionary:
	d.merge({gen = 1}, false)
	return d


static func _player_7_to_8(d: Dictionary) -> Dictionary:
	d.merge({city = 0}, false)
	return d


## v9 remembers bikes that were ridden, fuelled or hotwired.
static func _world_8_to_9(d: Dictionary) -> Dictionary:
	d.merge({vehicles = {}}, false)
	return d


## v11 holds weapons in hands: the one selected on the hotbar goes in the right.
static func _player_10_to_11(d: Dictionary) -> Dictionary:
	var inv: Array = d.get("inv", [])
	var sel: int = d.get("sel", 0)
	if sel >= 0 and sel < inv.size() and inv[sel] != null and Items.is_weapon(inv[sel].id):
		d.worn["hand_r"] = inv[sel]
		inv[sel] = null
	return d


## v10 remembers wounds (see Body).
static func _player_9_to_10(d: Dictionary) -> Dictionary:
	d.merge({wounds = []}, false)
	return d


## Bring a save up to VERSION one step at a time.
static func _migrate(kind: String, d: Dictionary) -> Dictionary:
	var v: int = d.get("version", 1)
	while v < VERSION:
		var step: String = MIGRATIONS.get("%s:%d" % [kind, v], "")
		if step != "":
			d = Callable(SaveGame, step).call(d)
		v += 1
		d.version = v
	return d


static func _load(path: String, kind: String) -> Dictionary:
	var d := _read(path)
	var from_backup := false
	if d.is_empty() and FileAccess.file_exists(path):
		d = _read(path + ".bak")  # the save is damaged: the one before it
		from_backup = not d.is_empty()
	if d.is_empty():
		if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
			return {state = "corrupt", data = {}}
		return {state = "none", data = {}}
	var v: int = d.get("version", 1)
	if v > VERSION:
		return {state = "newer", data = {}}
	if v < VERSION:
		# Keep the file exactly as it was before upgrading it.
		var keep := path + ".v%d" % v
		if not FileAccess.file_exists(keep):
			DirAccess.copy_absolute(path if not from_backup else path + ".bak", keep)
		d = _migrate(kind, d)
	if from_backup:
		push_warning("%s was damaged; loaded its backup" % path)
	return {state = "ok", data = d}


## A save we must not write over: from a newer game, or damaged beyond reading.
static func _blocked(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d := _read(path)
	return d.is_empty() or d.get("version", 1) > VERSION


static func _player_path(name: String) -> String:
	var safe := name
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]:
		safe = safe.replace(bad, "_")
	return dir() + "/players/%s.save" % safe


static func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	# Write to a temp file first so a crash mid-save never leaves a broken save,
	# and keep the previous save as .bak in case this one turns out bad.
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save %s" % path)
		return
	f.store_var(data)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	DirAccess.rename_absolute(tmp, path)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = f.get_var()
	return v if v is Dictionary and v.has("version") else {}


static func _remove_tree(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	for sub in da.get_directories():
		_remove_tree(path.path_join(sub))
	for f in da.get_files():
		da.remove(f)
	DirAccess.remove_absolute(path)
