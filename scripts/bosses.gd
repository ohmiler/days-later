class_name Bosses
extends Node
## The bosses (data/bosses.cfg): one of each kind of big building's worst,
## waiting among its shut-in dead. Survival lets it out with them when someone
## comes near; it stays dead for `respawn` game hours (the building remembers
## when, in WorldState), then another takes its place. Everyone who hurt it
## gets its drops, their own.
##
## A boss's zombie id says which it is (BASE and up: the building and its row
## in the file), so every screen knows it for a boss without being told.

const PATH := "res://data/bosses.cfg"
const BASE := 1 << 30
const PER_BUILDING := 8  # rows of the file a building can have bosses from
const BAR_RANGE := 260.0  # this close, and seen, its health shows at the top of the screen
const TICK := 0.25

static var DEFS: Dictionary = _load()
static var IDS: Array = DEFS.keys()

var main: Main
var _t := 0.0
var _met := {}  # client: bosses already introduced (zid -> true)


static func _load() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		push_error("Could not read " + PATH)
		return {}
	var out := {}
	for id in cf.get_sections():
		var d := {}
		for key in cf.get_section_keys(id):
			d[key] = cf.get_value(id, key)
		out[id] = d
	return out


## What is wrong with the table, one line each (the tests run it).
static func problems() -> Array:
	var out := []
	if IDS.size() > PER_BUILDING:
		out.append("more than %d bosses: raise PER_BUILDING" % PER_BUILDING)
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		if not Zombie.KINDS.has(id) or not Zombie.KINDS[id].get("boss", false):
			out.append("%s: no boss kind of that name in Zombie.KINDS" % id)
		if d.get("building", "") not in Items.BUILDING_TIER:
			out.append("%s: unknown building %s" % [id, d.get("building")])
		for key in ["name", "hint", "respawn"]:
			if not d.has(key):
				out.append("%s: no %s" % [id, key])
		for slot in d.get("wear", {}):
			if Items.def(d.wear[slot]).is_empty():
				out.append("%s: wears unknown item %s" % [id, d.wear[slot]])
		for it in d.get("drops", {}):
			if not Items.DEFS.has(it):
				out.append("%s: drops unknown item %s" % [id, it])
		for sk in d.get("xp", {}):
			if not Skills.DEFS.has(sk):
				out.append("%s: xp for unknown skill %s" % [id, sk])
	return out


static func is_zid(zid: int) -> bool:
	return zid >= BASE


## The id of building `bid`'s boss `id`.
static func zid_for(bid: int, id: String) -> int:
	return BASE + bid * PER_BUILDING + IDS.find(id)


static func kind_at(zid: int) -> String:
	var i := (zid - BASE) % PER_BUILDING
	return IDS[i] if i < IDS.size() else "normal"


## The building a boss makes its lair in: the biggest of its kind in the zone
## (one per zone, a place worth the trip), -1 if the zone has none.
static var _lairs := {}  # "world instance:boss" -> building (the map asks often)


static func lair(w: World, id: String) -> int:
	var key := "%d:%s" % [w.get_instance_id(), id]
	if not _lairs.has(key):
		_lairs[key] = _find_lair(w, id)
	return _lairs[key]


static func _find_lair(w: World, id: String) -> int:
	var best := -1
	var area := 0
	for i in w.buildings.size():
		var rec: Dictionary = w.buildings[i]
		if rec.get("kind", "") == DEFS[id].building and rec.rect.get_area() > area:
			best = i
			area = rec.rect.get_area()
	return best


## Where each boss of this zone lives, for the city map: [cell, name, game
## hours till it's back (0: it's there now)].
func map_marks() -> Array:
	var out := []
	for id in IDS:
		var bid := lair(main.world, id)
		if bid < 0:
			continue
		var rec: Dictionary = main.world.buildings[bid]
		var dead = main.world_state.state("building", bid).get("boss_" + id)
		var left := 0.0 if dead == null else (float(DEFS[id].respawn) * Main.HOUR - (main.now() - float(dead))) / Main.HOUR
		out.append([rec.rect.get_center(), DEFS[id].name, maxf(0.0, left)])
	return out


## Server: the building's shut-in dead are let out (Survival._let_out); its
## bosses come too, unless one was killed too recently. `spots` [cell, storey]:
## where there's room to stand; bosses keep to the ground floor if they can.
func let_out(rec: Dictionary, spots: Array, zids: Array) -> void:
	var st: Dictionary = main.world_state.state("building", rec.id)
	for id in IDS:
		var d: Dictionary = DEFS[id]
		if d.building != rec.get("kind", "") or lair(main.world, id) != int(rec.id):
			continue
		var dead = st.get("boss_" + id)
		if dead != null and main.now() - float(dead) < float(d.respawn) * Main.HOUR:
			continue
		var zid := zid_for(rec.id, id)
		var z: Zombie = main.zombies.get(zid)
		if z == null:  # (else it's still about: loaded from the save)
			var ground := spots.filter(func(s): return s[1] == 0)
			var s: Array = (ground if not ground.is_empty() else spots)[(rec.id * 7 + zid) % (ground.size() if not ground.is_empty() else spots.size())]
			var pos: Vector2 = main.world.to_pos(s[0])
			z = main._add_zombie(zid, pos)
			z.storey = s[1]
			z.lift = BuildingProp.storey_lift(s[1])
		z.home = rec.id
		if not zids.has(zid):
			zids.append(zid)


## Server: a boss is dead. The building remembers when; each survivor who hurt
## it gets its drops and its experience.
func died(z: Zombie) -> void:
	var d: Dictionary = DEFS.get(z.kind, {})
	if z.home >= 0:
		main.world_state.set_state("building", z.home, {"boss_" + z.kind: main.now()})
	for peer in z.hurt_by:
		var p: Player = main.players.get(peer)
		if p == null:
			continue
		for it in d.get("drops", {}):
			for k in int(d.drops[it]):
				if not main.inventory._give(p, it):
					main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 6), Items.make(it), p.storey)
		for sk in d.get("xp", {}):
			main.skills.add(p, sk, float(d.xp[sk]))
		main.quests.note(p, "kill", {kind = z.kind})  # (the story's "bring it down": all who fought it)
		main.inventory._send_inv(p)
		main._notify(p.peer_id, &"boss_down", [z.kind, z.hurt_by.size()])


## Server: past half its health a boss comes on faster, and lets out a roar
## that brings the rest of the building.
func server_tick(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	for z: Zombie in main.zombies.values():
		if not is_zid(z.zid) or z.enraged or z.hp > z.max_hp * 0.5:
			continue
		z.enraged = true
		z.speed = Zombie.KINDS[z.kind].speed * Zombie.ENRAGE_SPEED
		main._make_noise(z.position, main.NOISE_HIT * 4.0, z.storey)
		fx_enrage.rpc(z.zid)


@rpc("authority", "call_local", "reliable")
func fx_enrage(zid: int) -> void:
	var z: Zombie = main.zombies.get(zid)
	if z == null:
		return
	z.flinch(Vector2.UP, true)
	var me: Player = main.players.get(multiplayer.get_unique_id())
	if me and me.position.distance_to(z.position) < BAR_RANGE * 1.5:
		main.show_toast("%s คลั่ง! เร็วขึ้น และเรียกตัวอื่นมา" % DEFS[z.kind].name)


@rpc("authority", "call_remote", "reliable")
func boss_down(kind: String, helpers: int) -> void:
	var d: Dictionary = DEFS.get(kind, {})
	var got := []
	for it in d.get("drops", {}):
		got.append("%s ×%d" % [Items.display_name(it), int(d.drops[it])])
	for sk in d.get("xp", {}):
		got.append("%s +%d" % [Skills.DEFS[sk].name, int(d.xp[sk])])
	var who := "" if helpers <= 1 else " (ช่วยกัน %d คน)" % helpers
	main.ui.announce("ล้ม%sได้แล้ว!%s\n%s" % [d.get("name", kind), who, " · ".join(got)], true)
	Sfx.play_ui(main, "levelup", -2.0)


## Client: the nearest boss you can see gets a health bar at the top of the
## screen; the first time you see one, it says how to beat it.
func _process(_delta: float) -> void:
	if main == null or not main.in_game or main.ui == null or main.ui.boss_bar == null:
		return
	var me: Player = main.players.get(multiplayer.get_unique_id())
	var best: Zombie = null
	if me and me.alive():
		for z: Zombie in main.zombies.values():
			if not is_zid(z.zid) or z.storey != me.storey or z.sight_k < 0.5 or z.hp <= 0:
				continue
			if z.position.distance_to(me.position) < BAR_RANGE and (best == null or z.position.distance_to(me.position) < best.position.distance_to(me.position)):
				best = z
	var bar: BossBar = main.ui.boss_bar
	if best == null:
		bar.boss = ""
		return
	var d: Dictionary = DEFS[best.kind]
	bar.boss = d.name
	bar.frac = clampf(best.hp / best.max_hp, 0.0, 1.0)
	if not _met.has(best.zid):
		_met[best.zid] = true
		main.show_toast("%s · %s" % [d.name, d.hint])
