class_name Crafting
extends Node
## Making things by hand: recipes (data/recipes.cfg), taking things apart
## (an item's `salvage`) and mending them (an item's `repair`). Each is a job
## that takes a few seconds standing still and makes a little noise.
## Only what is in the bag is used up, never what you are wearing.

const DATA := "res://data/recipes.cfg"  # (exports must include *.cfg, like data/items.cfg)
const SALVAGE_TIME := 1.5
const REPAIR_TIME := 2.0
const REPAIR_SHARE := 0.5  # a repair gives back this share of full durability
const STRIP_TIME := 5.0  # pulling a cupboard apart by hand
const STRIP_TOOLS := ["hammer", "axe", "pipe", "machete"]  # ...twice as fast with one of these in hand

## id -> {name, needs, makes, count, time}, read the first time Crafting is used.
static var RECIPES: Dictionary = _load()

var main: Main


static func _load() -> Dictionary:
	var cf := ConfigFile.new()
	var err := cf.load(DATA)
	if err != OK:
		push_error("Could not read %s (error %d)" % [DATA, err])
		return {}
	var out := {}
	for id in cf.get_sections():
		var r := {needs = cf.get_value(id, "needs", {}), makes = cf.get_value(id, "makes", ""),
				count = cf.get_value(id, "count", 1), time = float(cf.get_value(id, "time", 2.0))}
		r.name = cf.get_value(id, "name", Items.display_name(r.makes))
		out[id] = r
	return out


## What is wrong with the recipe table, one line each (the tests run this).
static func problems() -> Array:
	var out := []
	for id in RECIPES:
		var r: Dictionary = RECIPES[id]
		if not Items.DEFS.has(r.makes):
			out.append("%s: makes unknown item %s" % [id, r.makes])
		if r.needs.is_empty():
			out.append("%s: needs nothing" % id)
		for need in r.needs:
			if not need.begins_with("#") and not Items.DEFS.has(need):
				out.append("%s: needs unknown item %s" % [id, need])
	return out


## Does `it` count for the need `need` (an item id, or "#tag" for any material with it)?
static func _fits(it, need: String) -> bool:
	if it == null:
		return false
	if need.begins_with("#"):
		return Items.def(it.id).get("type") == "material" and Items.has_tag(it.id, need.substr(1))
	return it.id == need


static func count_in(inv: Array, need: String) -> int:
	var n := 0
	for it in inv:
		if _fits(it, need):
			n += it.get("n", 1)
	return n


## Everything the recipe needs is in the bag.
static func can_make(inv: Array, id: String) -> bool:
	var r: Dictionary = RECIPES.get(id, {})
	if r.is_empty():
		return false
	for need in r.needs:
		if count_in(inv, need) < r.needs[need]:
			return false
	return true


## The material that mends `it`, if it is worn down and can be mended.
static func repair_with(it) -> String:
	if it == null:
		return ""
	var d := Items.def(it.id)
	if not d.has("repair") or it.get("hp", 0) >= d.get("hp", 0):
		return ""
	return d.repair


# --- Requests (server) ------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func req_craft(id: String) -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.sleeping or not RECIPES.has(id):
		return
	if not can_make(p.inv, id):
		main._toast(p, "ของไม่พอ")
		return
	_start(p, {kind = "craft", id = id}, RECIPES[id].time)


## Take apart the item in bag slot `idx`.
@rpc("any_peer", "call_remote", "reliable")
func req_salvage(idx: int) -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.sleeping or idx < 0 or idx >= p.inv.size() or p.inv[idx] == null:
		return
	if Items.def(p.inv[idx].id).get("salvage", {}).is_empty():
		return
	_start(p, {kind = "salvage", idx = idx, id = p.inv[idx].id}, SALVAGE_TIME)


## Mend what is at `ref` (["inv", i] or ["worn", slot]) with its material from the bag.
@rpc("any_peer", "call_remote", "reliable")
func req_repair(ref: Array) -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.sleeping:
		return
	var it = _at(p, ref)
	var mat := repair_with(it)
	if mat == "":
		return
	if count_in(p.inv, mat) < 1:
		main._toast(p, "ต้องใช้%sซ่อม" % Items.display_name(mat))
		return
	_start(p, {kind = "repair", ref = ref, id = it.id}, REPAIR_TIME)


## Pull a piece of furniture apart for its wood, nails and metal. Loud.
func start_strip(p: Player, id: int) -> void:
	var f: FurnitureProp = main.world.container_nodes[id]
	if f.stripped:
		return
	var tool := p.holds(STRIP_TOOLS)
	_start(p, {kind = "strip", id = id}, STRIP_TIME * (0.5 if tool else 1.0))
	main._make_noise(f.position, main.NOISE_HIT)
	if not tool:
		main._toast(p, "รื้อด้วยมือเปล่า · ถือค้อนหรือขวานจะเร็วกว่า")


@rpc("authority", "call_local", "reliable")
func container_stripped(id: int) -> void:
	main.world.container_nodes[id].set_stripped(true)


func _at(p: Player, ref: Array):
	if ref.size() == 2 and ref[0] == "inv" and ref[1] is int and ref[1] >= 0 and ref[1] < p.inv.size():
		return p.inv[ref[1]]
	if ref.size() == 2 and ref[0] == "worn":
		return p.worn.get(ref[1])
	return null


func _start(p: Player, job: Dictionary, seconds: float) -> void:
	job.t = seconds
	p.craft = job
	main.fx_sound.rpc("rustle", p.position)
	main._notify(p.peer_id, &"search_started", [seconds])  # the progress bar over the head


func server_tick(p: Player, delta: float) -> void:
	if p.craft.is_empty():
		return
	if not p.alive() or p.move.length() > 0.1 or p.sleeping:
		p.craft = {}
		main._notify(p.peer_id, &"search_started", [0.0])
		return
	p.craft.t -= delta
	if p.craft.t > 0.0:
		return
	var job := p.craft
	p.craft = {}
	main._make_noise(p.position, main.NOISE_SEARCH)
	main.fx_sound.rpc("pickup", p.position)
	match job.kind:
		"craft":
			_finish_craft(p, job.id)
		"salvage":
			_finish_salvage(p, job)
		"repair":
			_finish_repair(p, job)
		"strip":
			_finish_strip(p, job.id)
		"hotwire":
			main.vehicles.finish_hotwire(p, job.id)
	main.inventory._send_inv(p)


func _finish_craft(p: Player, id: String) -> void:
	if not can_make(p.inv, id):
		return  # something was dropped meanwhile
	var r: Dictionary = RECIPES[id]
	for need in r.needs:
		_take(p, need, r.needs[need])
	for i in r.count:
		_give_or_drop(p, r.makes)
	main._toast(p, "ทำ%sเสร็จแล้ว" % Items.display_name(r.makes))


func _finish_salvage(p: Player, job: Dictionary) -> void:
	var it = p.inv[job.idx] if job.idx < p.inv.size() else null
	if it == null or it.id != job.id:
		return
	if it.get("n", 1) > 1:
		it.n -= 1
	else:
		p.inv[job.idx] = null
	var parts: Dictionary = Items.def(job.id).salvage
	var got := []
	for part in parts:
		for i in parts[part]:
			_give_or_drop(p, part)
		got.append("%s ×%d" % [Items.display_name(part), parts[part]])
	main._toast(p, "แยก%s ได้ %s" % [Items.display_name(job.id), ", ".join(got)])


func _finish_repair(p: Player, job: Dictionary) -> void:
	var it = _at(p, job.ref)
	var mat := repair_with(it)
	if it == null or it.id != job.id or mat == "" or count_in(p.inv, mat) < 1:
		return
	_take(p, mat, 1)
	var full: int = Items.def(it.id).hp
	it.hp = mini(full, it.hp + ceili(full * REPAIR_SHARE))
	main._toast(p, "ซ่อม%s (%d/%d)" % [Items.display_name(it.id), it.hp, full])


func _finish_strip(p: Player, id: int) -> void:
	var f: FurnitureProp = main.world.container_nodes[id]
	if f.stripped or p.position.distance_to(f.position) > Interact.CONTAINER_REACH + 8.0:
		return
	container_stripped.rpc(id)
	main._make_noise(f.position, main.NOISE_BREAK)
	main.fx_sound.rpc("kick", f.position)
	var parts: Dictionary = FurnitureProp.STRIP.get(f.data.kind, {wood = 1})
	var got := []
	for part in parts:
		for i in parts[part]:
			_give_or_drop(p, part)
		got.append("%s ×%d" % [Items.display_name(part), parts[part]])
	main._toast(p, "รื้อได้ %s" % ", ".join(got))


## Use up `n` of what fits `need` from the bag.
func _take(p: Player, need: String, n: int) -> void:
	for i in p.inv.size():
		if n <= 0:
			return
		var it = p.inv[i]
		if not _fits(it, need):
			continue
		var used := mini(n, it.get("n", 1))
		n -= used
		if it.get("n", 1) > used:
			it.n -= used
		else:
			p.inv[i] = null


func _give_or_drop(p: Player, id: String) -> void:
	if not main.inventory._give(p, id):
		main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 6), {id = id, n = 1, hp = Items.def(id).get("hp", 0)})
