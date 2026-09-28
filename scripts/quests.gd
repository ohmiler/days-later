class_name Quests
extends Node
## What a survivor is working toward right now (data/quests.cfg): the start,
## a quest at a time, then two everyday tasks each day. The engine is here;
## the quests are rows in the table, so adding one needs no code.
##
## Each survivor's own (Player.quests): {active: {id: [count per objective]},
## done: {id: true}, day: the game day the everyday tasks were last handed
## out}. The server counts what happens (note, from where it happens: a kill,
## a search, a board nailed up) and what is carried (_refresh), hands out the
## rewards, and sends the owner their quests when they change (the tracker).

const PATH := "res://data/quests.cfg"
const DAILY_COUNT := 2
const SYNC_EVERY := 0.5
## Objectives about what you have rather than what you did: counted afresh.
const HELD := ["have_tag", "have_item", "hold_weapon"]

static var DEFS: Dictionary = _load()

var main: Main
var _t := 0.0
var _was_night := false
var _out_tonight := {}  # peer -> true: alive since dusk (for "dawn")


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


static func first_id() -> String:
	for id in DEFS:
		if DEFS[id].get("first", false):
			return id
	return ""


## What is wrong with the table, one line each ([] when all is well).
static func problems() -> Array:
	var out := []
	var kinds := ["kill", "kill_head", "silent_kill", "have_tag", "have_item", "hold_weapon", "board", "craft", "search",
			"cook", "boil", "treat", "eat", "drink", "dawn"]
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		for key in ["name", "desc", "objectives"]:
			if not d.has(key):
				out.append("%s: no %s" % [id, key])
		for o in d.get("objectives", []):
			if not o.get("do", "") in kinds:
				out.append("%s: unknown objective '%s'" % [id, o.get("do", "")])
		for sk in d.get("reward", {}).get("xp", {}):
			if not Skills.DEFS.has(sk):
				out.append("%s: no skill '%s'" % [id, sk])
		for it in d.get("reward", {}).get("items", {}):
			if not Items.DEFS.has(it):
				out.append("%s: no item '%s'" % [id, it])
		if d.get("next", "") != "" and not DEFS.has(d.next):
			out.append("%s: next '%s' doesn't exist" % [id, d.next])
	return out


# --- Server -------------------------------------------------------------------

## A new survivor (or one from before quests): the start, if not done yet.
func ensure(p: Player) -> void:
	if not p.quests.has("active"):
		p.quests = {active = {}, done = {}, day = -1}
	if p.quests.active.is_empty() and not p.quests.done.has(first_id()) and first_id() != "":
		start(p, first_id())


func start(p: Player, id: String) -> void:
	if not DEFS.has(id) or p.quests.active.has(id):
		return
	var counts := []
	for o in DEFS[id].objectives:
		counts.append(0)
	p.quests.active[id] = counts
	p.quests_dirty = true
	_refresh(p)


## `p` did `what` (an objective's "do"); `info` says more (kind, item).
func note(p: Player, what: String, info := {}, n := 1) -> void:
	if p == null or not p.quests.has("active"):
		return
	for id in p.quests.active.keys():
		var objs: Array = DEFS[id].objectives
		var counts: Array = p.quests.active[id]
		for i in objs.size():
			var o: Dictionary = objs[i]
			if o.do != what or counts[i] >= o.n:
				continue
			if o.has("kind") and info.get("kind", "") != o.kind:
				continue
			if o.has("item") and info.get("item", "") != o.item:
				continue
			counts[i] = mini(o.n, counts[i] + n)
			p.quests_dirty = true
		_check(p, id)


## What is carried or held, counted again (after the bag changes, and now and then).
func _refresh(p: Player) -> void:
	for id in p.quests.get("active", {}).keys():
		var objs: Array = DEFS[id].objectives
		var counts: Array = p.quests.active[id]
		for i in objs.size():
			var o: Dictionary = objs[i]
			if not o.do in HELD:
				continue
			var have := 0
			match o.do:
				"have_tag":
					for it in p.inv:
						if it != null and Items.has_tag(it.id, o.tag):
							have += it.n
				"have_item":
					have = Crafting.count_in(p.inv, o.item)
				"hold_weapon":
					have = 1 if p.hand_weapon("r") != "" or p.hand_weapon("l") != "" else 0
			var c := mini(o.n, have)
			if c != counts[i]:
				counts[i] = c
				p.quests_dirty = true
		_check(p, id)


func _check(p: Player, id: String) -> void:
	if not p.quests.active.has(id):
		return
	var objs: Array = DEFS[id].objectives
	var counts: Array = p.quests.active[id]
	for i in objs.size():
		if counts[i] < objs[i].n:
			return
	_complete(p, id)


func _complete(p: Player, id: String) -> void:
	var d: Dictionary = DEFS[id]
	p.quests.active.erase(id)
	if not d.get("daily", false):
		p.quests.done[id] = true
	p.quests_dirty = true
	var reward: Dictionary = d.get("reward", {})
	for sk in reward.get("xp", {}):
		main.skills.add(p, sk, float(reward.xp[sk]))
	for it in reward.get("items", {}):
		for k in int(reward.items[it]):
			if not main.inventory._give(p, it):
				main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 6), Items.make(it), p.storey)
	main.inventory._send_inv(p)
	main._notify(p.peer_id, &"quest_done", [id])
	if d.get("next", "") != "":
		start(p, d.next)


## Everyone out through the night and alive at first light; each day's tasks.
func server_tick(delta: float) -> void:
	var night: bool = main.world.is_night
	if night:
		for p: Player in main.players.values():
			if p.alive() and not _was_night:
				_out_tonight[p.peer_id] = true
	elif _was_night:
		for p: Player in main.players.values():
			if p.alive() and _out_tonight.has(p.peer_id):
				note(p, "dawn")
		_out_tonight.clear()
	_was_night = night
	_t -= delta
	if _t > 0.0:
		return
	_t = SYNC_EVERY
	for p: Player in main.players.values():
		if not p.quests.has("active"):
			ensure(p)  # (someone new, or from before there were quests)
		_refresh(p)
		_hand_out_daily(p)
		if p.quests_dirty:
			p.quests_dirty = false
			main._notify(p.peer_id, &"quests_sync", [p.quests])


## Once the start is done: two everyday tasks for each game day.
func _hand_out_daily(p: Player) -> void:
	if not _start_done(p) or int(p.quests.get("day", -1)) == main.day:
		return
	p.quests.day = main.day
	for id in p.quests.active.keys():
		if DEFS[id].get("daily", false):
			p.quests.active.erase(id)  # (yesterday's, undone: no harm)
	var pool := DEFS.keys().filter(func(id): return DEFS[id].get("daily", false))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [p.pname, main.day])
	for i in mini(DAILY_COUNT, pool.size()):
		var k := rng.randi() % pool.size()
		start(p, pool[k])
		pool.remove_at(k)
	p.quests_dirty = true


func _start_done(p: Player) -> bool:
	for id in DEFS:
		if not DEFS[id].get("daily", false) and not p.quests.done.has(id):
			return false
	return true


## Dying breaks a night out.
func on_death(p: Player) -> void:
	_out_tonight.erase(p.peer_id)


# --- The owner's screen -----------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func quests_sync(q: Dictionary) -> void:
	var me: Player = main.players.get(multiplayer.get_unique_id())
	if me:
		me.quests = q


## A quest done: the news in gold, the chime.
@rpc("authority", "call_remote", "reliable")
func quest_done(id: String) -> void:
	if not DEFS.has(id):
		return
	var d: Dictionary = DEFS[id]
	var got := []
	for sk in d.get("reward", {}).get("xp", {}):
		got.append("%s +%d" % [Skills.DEFS[sk].name, int(d.reward.xp[sk])])
	for it in d.get("reward", {}).get("items", {}):
		got.append("%s ×%d" % [Items.display_name(it), int(d.reward.items[it])])
	main.ui.announce("ภารกิจสำเร็จ: %s%s" % [d.name, ("\n" + " · ".join(got)) if not got.is_empty() else ""], true)
	Sfx.play_ui(main, "levelup", -4.0)
