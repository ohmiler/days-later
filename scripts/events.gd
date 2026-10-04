class_name Events
extends Node
## Things that happen in the city now and then (data/events.cfg): a tune from
## an ice-cream truck that draws the dead along a street, a shop's door chime in
## a dark minimart, a house phone that rings, karaoke in the small hours, a
## lottery seller who turns up still selling. One at a time, every few minutes,
## near a survivor; whoever is close is told what they can hear.

const PATH := "res://data/events.cfg"
const EVERY := [150.0, 400.0]  # seconds between one and the next
const FIRST := 60.0  # the first, this long after the world starts
const HEAR := 520.0  # who is told of it

static var DEFS: Dictionary = _load()

var main: Main
var _wait := FIRST
var active: Array = []  # [{id, pos, left, beep, dir}]


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
		d.merge({when = "any", weight = 1, every = 5.0, seconds = 40.0, radius = 150.0, drift = 0.0, reach = 0.0, reward = {}, hear = ""}, false)
		out[id] = d
	return out


static func problems() -> Array:
	var out := []
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		for key in ["name", "type", "where"]:
			if not d.has(key):
				out.append("%s: no %s" % [id, key])
		if not d.get("type", "") in ["sound", "spawn"]:
			out.append("%s: unknown type %s" % [id, d.get("type", "")])
		if not d.get("where", "") in ["street", "store", "home"]:
			out.append("%s: unknown place %s" % [id, d.get("where", "")])
		if not d.when in ["day", "night", "any"]:
			out.append("%s: unknown time %s" % [id, d.when])
		for it in d.reward:
			if not Items.DEFS.has(it):
				out.append("%s: no item '%s'" % [id, it])
	return out


func server_tick(delta: float) -> void:
	if main.world == null:
		return
	for ev in active.duplicate():
		_run(ev, delta)
	_wait -= delta
	if _wait > 0.0 or not active.is_empty():
		return
	_wait = randf_range(EVERY[0], EVERY[1])
	start_one()


## Start one that suits the hour and somewhere near a survivor; returns its id ("" if none).
func start_one(only := "") -> String:
	var around: Array = main.players.values().filter(func(q): return q.alive() and not q.on_roof and q.storey == 0 and not main.world.in_camp(q.position, 2))
	if around.is_empty():
		return ""
	var p: Player = around[randi() % around.size()]
	var pool := {}
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		if only != "" and id != only:
			continue
		if d.when == "night" and not main.world.is_night or d.when == "day" and main.world.is_night:
			continue
		pool[id] = float(d.weight)
	while not pool.is_empty():
		var total := 0.0
		for id in pool:
			total += pool[id]
		var roll := randf() * total
		var pick: String = pool.keys()[0]
		for id in pool:
			roll -= pool[id]
			if roll <= 0.0:
				pick = id
				break
		var at := _place(DEFS[pick].where, p)
		if at != Vector2.INF:
			_begin(pick, at, p)
			return pick
		pool.erase(pick)  # (nowhere near for that one: try another)
	return ""


func _begin(id: String, at: Vector2, near: Player) -> void:
	var d: Dictionary = DEFS[id]
	if d.hear != "":
		for p: Player in main.players.values():
			if p.alive() and p.position.distance_to(at) < HEAR:
				main._toast(p, d.hear)
	if d.type == "spawn":
		# An id whose kind is the one wanted: everyone's game works the kind out
		# from the id (Zombie.kind_for), so the seller looks the same to all.
		var kind: String = d.get("kind", "normal")
		var zid := main.new_zid(at)
		for attempt in 64:
			if Zombie.kind_for(zid) == kind:
				break
			zid = main.new_zid(at)
		var z: Zombie = main._add_zombie(zid, at)
		z.set_kind(kind)
		z.set_meta("lotto", true)
		z.sense(near.position, 4.0)  # (shambling the way of the nearest survivor)
		return
	var dir := Vector2.RIGHT
	if d.drift > 0.0:
		dir = _road_axis(at)
	active.append({id = id, pos = at, left = d.seconds, beep = 0.0, dir = dir})


func _run(ev: Dictionary, delta: float) -> void:
	var d: Dictionary = DEFS[ev.id]
	ev.left -= delta
	if d.drift > 0.0:
		var step: Vector2 = ev.dir * d.drift * delta
		var c := main.world.to_cell(ev.pos + step * 4.0)
		if main.world.get_tile(c) == World.ROAD and not main.world.blocked.has(c):
			ev.pos += step
		else:
			ev.dir = -ev.dir
	if d.reach > 0.0:
		for p: Player in main.players.values():
			if p.alive() and p.storey == 0 and p.position.distance_to(ev.pos) < d.reach:
				_reward(p, ev)
				return
	ev.beep -= delta
	if ev.beep <= 0.0:
		ev.beep = d.every
		main.fx_sound.rpc(d.sound, ev.pos)
		main.stimulus("sound", ev.pos, d.radius)
	if ev.left <= 0.0:
		active.erase(ev)


## A survivor got to the source: it stops, and there is something there.
func _reward(p: Player, ev: Dictionary) -> void:
	var d: Dictionary = DEFS[ev.id]
	active.erase(ev)
	for it in d.reward:
		for k in int(d.reward[it]):
			if not main.inventory._give(p, it):
				main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 6), Items.make(it), p.storey)
	main.inventory._send_inv(p)
	main._toast(p, "%s หยุดลงแล้ว · มีของวางอยู่ข้างเครื่อง" % d.name)


## The lottery seller down: tickets, and now and then one that won.
func lotto_died(z: Zombie, killer: Player) -> void:
	for k in randi_range(1, 3):
		main._spawn_pickup(z.position + Vector2(randf_range(-7, 7), 4), Items.make("lotto"), z.storey)
	if randf() < 0.2:
		for k in 3:
			main._spawn_pickup(z.position + Vector2(randf_range(-7, 7), -4), Items.make("gold"), z.storey)
		if killer:
			main._toast(killer, "ในสลากมีใบที่ถูกรางวัลจริง ๆ · สร้อยทองขายต่อได้")


func _place(where: String, near: Player) -> Vector2:
	var w: World = main.world
	match where:
		"street":
			for attempt in 40:
				var pos: Vector2 = near.position + Vector2.from_angle(randf() * TAU) * randf_range(280.0, 480.0)
				var c := w.to_cell(pos)
				if w.in_bounds(c) and w.get_tile(c) == World.ROAD and not w.blocked.has(c) and not w.in_camp(pos, 4):
					return pos
		"store", "home":
			var list := []
			for b in w.building_nodes:
				var r: Dictionary = b.data
				if where == "store" and r.kind != "store" or where == "home" and (r.kind != "shop" or r.floors < 2):
					continue
				var pos: Vector2 = w.to_pos(r.rect.get_center())
				var dist := pos.distance_to(near.position)
				if dist < 700.0 and dist > 160.0 and not w.in_camp(pos, 4):
					list.append(pos)
			if not list.is_empty():
				return list[randi() % list.size()]
	return Vector2.INF


## Which way the road a truck is on runs: along it, east or south (the way
## the road goes on further from here; across it, it soon ends).
func _road_axis(at: Vector2) -> Vector2:
	return Vector2.RIGHT if _road_run(at, Vector2i.RIGHT) >= _road_run(at, Vector2i.DOWN) else Vector2.DOWN


## Road cells in a line through `at`, both ways along `step` (up to 40 each).
func _road_run(at: Vector2, step: Vector2i) -> int:
	var w: World = main.world
	var c := w.to_cell(at)
	var n := 0
	for s in [step, -step]:
		for i in range(1, 41):
			var cc: Vector2i = c + s * i
			if not w.in_bounds(cc) or w.get_tile(cc) != World.ROAD:
				break
			n += 1
	return n
