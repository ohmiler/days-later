class_name Skills
extends Node
## What a survivor gets better at by doing it (data/skills.cfg): fighting,
## sneaking, first aid, making things, cooking, endurance. Each is levels
## 1-50 on its own experience; what it changes is small (a quarter at most by
## level 50: better, never so much the dead stop being frightening), and the
## survivor level by your name is them all added up, counted from 1 (a new
## survivor is 1, up to 295 with six skills; more skills, higher still).
##
## The server keeps the experience (Player.skills: id -> xp), sends it to its
## owner when it changes, and tells everyone a survivor's level. Dying costs
## part of the way into each level, never a level (ROADMAP "ความก้าวหน้า").

const PATH := "res://data/skills.cfg"
const MAX_LEVEL := 50
const XP_BASE := 8.0  # experience to reach level L: XP_BASE * (L - 1) ^ XP_POW
const XP_POW := 2.3  # (level 10 in the first hours, 30 in weeks, 50 in months)
const DEATH_LOSS := 0.15  # dying loses this share of the way into each level
const SYNC_EVERY := 0.5  # seconds between sending a changed survivor their experience

static var DEFS: Dictionary = _load()

var main: Main
var _sync_t := 0.0


static func _load() -> Dictionary:
	var cfg := ConfigFile.new()
	var out := {}
	if cfg.load(PATH) != OK:
		push_error("Could not read " + PATH)
		return out
	for id in cfg.get_sections():
		var d := {}
		for key in cfg.get_section_keys(id):
			d[key] = cfg.get_value(id, key)
		out[id] = d
	return out


# --- Numbers --------------------------------------------------------------------

## Experience it takes to reach `level` (level 1: none).
static func xp_for(level: int) -> float:
	return XP_BASE * pow(float(maxi(0, level - 1)), XP_POW)


static func level_of(xp: float) -> int:
	var l := 1
	while l < MAX_LEVEL and xp >= xp_for(l + 1):
		l += 1
	return l


static func level(p: Player, id: String) -> int:
	return level_of(float(p.skills.get(id, 0.0)))


## The survivor level: every level above the first, added up, plus one (so a
## new survivor is 1, and each level gained anywhere is one more).
static func total(skills: Dictionary) -> int:
	var t := 1
	for id in DEFS:
		t += level_of(float(skills.get(id, 0.0))) - 1
	return t


## How far into the current level, 0..1 (1 at the top level).
static func progress(xp: float) -> float:
	var l := level_of(xp)
	if l >= MAX_LEVEL:
		return 1.0
	var a := xp_for(l)
	return clampf((xp - a) / (xp_for(l + 1) - a), 0.0, 1.0)


## What `key` is multiplied by for this survivor: each skill's per_level
## share for every level above the first (1 = nothing changes).
static func mult(p: Player, key: String) -> float:
	var m := 1.0
	for id in DEFS:
		var per: float = DEFS[id].get("per_level", {}).get(key, 0.0)
		if per != 0.0:
			m *= 1.0 + per * float(level(p, id) - 1)
	return m


## What opens at a level (data/skills.cfg `unlocks`): unlock id -> [skill, level].
static var UNLOCKS: Dictionary = _unlocks()


static func _unlocks() -> Dictionary:
	var out := {}
	for id in DEFS:
		var u: Dictionary = DEFS[id].get("unlocks", {})
		for k in u:
			out[u[k][0]] = [id, int(k)]
	return out


## Whether `p` has opened unlock `uid` (a skill at its level). The owner's own
## screen knows too (their skills are sent to them).
static func has(p: Player, uid: String) -> bool:
	var u = UNLOCKS.get(uid)
	return u != null and p != null and level(p, u[0]) >= u[1]


## What the unlock at `lvl` of skill `id` says ("" if none).
static func unlock_text(id: String, lvl: int) -> String:
	var u = DEFS.get(id, {}).get("unlocks", {}).get(str(lvl))
	return u[1] if u is Array else ""


## What is wrong with the table, one line each (the tests run it).
static func problems() -> Array:
	var out := []
	for id in DEFS:
		var u: Dictionary = DEFS[id].get("unlocks", {})
		for k in u:
			if not (u[k] is Array and u[k].size() == 2) or int(k) < 2 or int(k) > MAX_LEVEL:
				out.append("%s: unlock at %s must be [id, text] at level 2-%d" % [id, k, MAX_LEVEL])
	return out


# --- Server ---------------------------------------------------------------------

## `p` did `what` (a key of the skill's `xp` in skills.cfg), `times` over
## (a second of creeping is times = delta).
func gain(p: Player, id: String, what: String, times := 1.0) -> void:
	if p == null or not DEFS.has(id):
		return
	var amount := float(DEFS[id].get("xp", {}).get(what, 0.0)) * times
	if amount <= 0.0:
		return
	var before := level(p, id)
	p.skills[id] = float(p.skills.get(id, 0.0)) + amount
	p.skills_dirty = true
	var after := level(p, id)
	if after > before:
		fx_level_up.rpc(p.peer_id, id, after)
		survivor_level.rpc(p.peer_id, total(p.skills))


## Experience straight into a skill (a quest's reward).
func add(p: Player, id: String, amount: float) -> void:
	if not DEFS.has(id) or amount <= 0.0:
		return
	var before := level(p, id)
	p.skills[id] = float(p.skills.get(id, 0.0)) + amount
	p.skills_dirty = true
	var after := level(p, id)
	if after > before:
		fx_level_up.rpc(p.peer_id, id, after)
		survivor_level.rpc(p.peer_id, total(p.skills))


## Dying: part of the way into each level is lost, never a level.
func on_death(p: Player) -> void:
	for id in p.skills:
		var xp: float = p.skills[id]
		var floor_xp := xp_for(level_of(xp))
		p.skills[id] = floor_xp + (xp - floor_xp) * (1.0 - DEATH_LOSS)
	p.skills_dirty = true


func server_tick(delta: float) -> void:
	_sync_t -= delta
	if _sync_t > 0.0:
		return
	_sync_t = SYNC_EVERY
	for p: Player in main.players.values():
		if p.skills_dirty:
			p.skills_dirty = false
			main._notify(p.peer_id, &"skills_sync", [p.skills])


## Someone joining: everyone's survivor level.
func send_all(peer: int) -> void:
	for p: Player in main.players.values():
		survivor_level.rpc_id(peer, p.peer_id, total(p.skills))


## Everyone: a survivor's level (for the name over their head).
func tell_level(p: Player) -> void:
	survivor_level.rpc(p.peer_id, total(p.skills))


# --- Every screen -------------------------------------------------------------

## The owner's own experience, to show (the bag's skills tab).
@rpc("authority", "call_remote", "reliable")
func skills_sync(xp: Dictionary) -> void:
	var me: Player = main.players.get(multiplayer.get_unique_id())
	if me:
		me.skills = xp


@rpc("authority", "call_local", "reliable")
func survivor_level(peer: int, level_total: int) -> void:
	var p: Player = main.players.get(peer)
	if p:
		p.level_total = level_total


## A level up: a ring of light round whoever it was; for them, the news in
## the middle of the screen and a chime.
@rpc("authority", "call_local", "reliable")
func fx_level_up(peer: int, id: String, lvl: int) -> void:
	var p: Player = main.players.get(peer)
	if p == null:
		return
	p.levelup_t = LEVELUP_TIME
	if peer == multiplayer.get_unique_id():
		var unlock := unlock_text(id, lvl)
		main.ui.announce("%s  เลเวล %d%s" % [DEFS[id].name, lvl, ("\nปลดล็อก: " + unlock) if unlock != "" else ""], true)
		Sfx.play_ui(main, "levelup", -2.0)


const LEVELUP_TIME := 1.4  # seconds the ring of light lasts


## The ring of light round someone who just went up a level (drawn in Main's fx).
static func draw_ring(ci: CanvasItem, p: Player) -> void:
	if p.levelup_t <= 0.0:
		return
	var k := 1.0 - p.levelup_t / LEVELUP_TIME
	var at := p.position + Vector2(0, -2.0 - p.lift)
	var r := 6.0 + 18.0 * ease(k, 0.4)
	var a := 1.0 - k
	ci.draw_set_transform(at, 0.0, Vector2(1.0, 0.45))
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(UiTheme.WARN, a * 0.9), 1.6)
	ci.draw_arc(Vector2.ZERO, r * 0.7, 0.0, TAU, 32, Color(1, 1, 0.8, a * 0.5), 1.0)
	ci.draw_set_transform(Vector2.ZERO)
	for i in 6:  # sparks rising
		var ang := TAU * i / 6.0 + k * 2.0
		var sp := at + Vector2(cos(ang) * 9.0, -6.0 - 26.0 * k + sin(ang) * 3.0)
		ci.draw_circle(sp, 0.9, Color(UiTheme.WARN, a))
