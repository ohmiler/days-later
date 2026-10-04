class_name Remains
extends Node
## What a dead survivor had on them stays with their body: a bundle where they
## fell, for LIFE real seconds (an hour: time to get back to it), that only its
## owner can take back (later their group too; a lawless zone, anyone). E on it
## gives everything back at once: the clothes go on again where nothing is
## worn, the rest into the bag, anything that won't fit at your feet.
## (ROADMAP "ตายแล้วเสียอะไร", decided 2026-09-28.)
##
## Every peer keeps `seen` (where each one is, whose, until when) for drawing,
## the prompt and the map; only the server holds what is in them.

const LIFE := 3600.0  # real seconds a bundle lasts
const REACH := 16.0

var main: Main
var seen := {}  # every peer: rid -> {pos, storey, owner, ends (this peer's unix time)}
var items := {}  # server: rid -> {worn: {slot: item}, inv: [item]}
var next_rid := 1
var _t := 0.0


static func now() -> float:
	return Time.get_unix_time_from_system()


# --- Server --------------------------------------------------------------------

## `p` died: everything they had goes into a bundle where they fell. When they
## `turned`, the clothes stay on the zombie they became (it drops them when it
## dies); the bag still stays here.
func leave(p: Player, turned := false) -> void:
	var worn := {} if turned else p.worn.duplicate()
	var inv := p.inv.filter(func(it): return it != null)
	p.worn.clear()  # still drawn on the body until respawn (see Player.refresh_wear)
	for i in p.inv.size():
		p.inv[i] = null
	main.inventory._send_inv(p)
	if worn.is_empty() and inv.is_empty():
		return
	if p.pname == "":
		_scatter(p.position, p.storey, worn.values() + inv)  # (nobody to keep it for)
		return
	var rid := next_rid
	next_rid += 1
	items[rid] = {worn = worn, inv = inv}
	add.rpc(rid, p.position, p.storey, p.pname, LIFE)
	main._toast(p, "ของทั้งหมดอยู่ที่ศพ · กลับไปเก็บคืนได้ภายใน 1 ชั่วโมง (หมุดบนแผนที่ M)")


## Whether `p` may take bundle `rid` back.
func can_take(p: Player, rid: int) -> bool:
	return seen.has(rid) and p.pname != "" and seen[rid].owner == p.pname


## E on your own bundle: all of it back.
func take(p: Player, rid: int) -> void:
	if not can_take(p, rid) or not items.has(rid):
		return
	var got: Dictionary = items[rid]
	items.erase(rid)
	gone.rpc(rid)
	var left := []
	for slot in got.worn:
		if not p.worn.has(slot):
			p.worn[slot] = got.worn[slot]
		else:
			left.append(got.worn[slot])
	p.refresh_wear()
	p.inv.resize(p.bag_size())  # (a bag back on: its slots too)
	for it in got.inv + left:
		var slot := p.inv.find(null)
		if slot >= 0 and slot < p.inv.size():
			p.inv[slot] = it
		else:
			main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 6), it, p.storey)
	main.inventory._send_inv(p)
	main.fx_sound.rpc("rustle", p.position)
	main._toast(p, "เก็บของคืนจากศพแล้ว")


func _scatter(pos: Vector2, storey: int, list: Array) -> void:
	for i in list.size():
		main._spawn_pickup(pos + Vector2.from_angle(i * TAU / maxf(1.0, list.size())) * 8.0, list[i], storey)


## Every second or so: bundles past their hour are gone, and what was in them.
func server_tick(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var t := now()
	for rid in seen.keys():
		if seen[rid].ends <= t:
			items.erase(rid)
			gone.rpc(rid)


## To someone joining: every bundle lying about.
func send_all(peer: int) -> void:
	var t := now()
	for rid in seen:
		var r: Dictionary = seen[rid]
		add.rpc_id(peer, rid, r.pos, r.storey, r.owner, r.ends - t)


## For the world save: [rid, pos, storey, owner, ends (unix), worn, inv].
func save_list() -> Array:
	var out := []
	for rid in items:
		var r: Dictionary = seen[rid]
		out.append([rid, r.pos, r.storey, r.owner, r.ends, items[rid].worn, items[rid].inv])
	return out


func load_list(list: Array, next: int) -> void:
	next_rid = maxi(next, 1)
	var t := now()
	for e in list:
		if float(e[4]) <= t:
			continue  # (its hour ran out while the world was shut)
		items[int(e[0])] = {worn = e[5], inv = e[6]}
		seen[int(e[0])] = {pos = e[1], storey = int(e[2]), owner = e[3], ends = float(e[4])}
		next_rid = maxi(next_rid, int(e[0]) + 1)


func clear() -> void:
	seen.clear()
	items.clear()


# --- Every peer ----------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func add(rid: int, pos: Vector2, storey: int, owner: String, left: float) -> void:
	seen[rid] = {pos = pos, storey = storey, owner = owner, ends = now() + left}
	if main.decals:
		main.decals.queue_redraw()
		main.decals_up.queue_redraw()


@rpc("authority", "call_local", "reliable")
func gone(rid: int) -> void:
	seen.erase(rid)
	if main.decals:
		main.decals.queue_redraw()
		main.decals_up.queue_redraw()


## What it says on the prompt: whose, and for how long yet.
func title(rid: int) -> String:
	var r: Dictionary = seen[rid]
	return "ของของ %s · อีก %d นาที" % [r.owner, maxi(1, ceili((r.ends - now()) / 60.0))]


## For the map: [cell, minutes left] of `pname`'s own bundles.
func map_marks(pname: String) -> Array:
	var out := []
	for rid in seen:
		var r: Dictionary = seen[rid]
		if r.owner == pname:
			out.append([main.world.to_cell(r.pos), maxi(1, ceili((r.ends - now()) / 60.0))])
	return out


## A bundle on the ground: a cloth tied up round what's in it.
static func draw(ci: CanvasItem, at: Vector2, mine: bool) -> void:
	ci.draw_set_transform(at + Vector2(0, 1), 0, Vector2(1, 0.4))
	Look._dot(ci, Vector2.ZERO, 6.0, Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2.ZERO)
	var cloth := Color("6a5a48") if not mine else Color("8a6a3a")
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 0), at + Vector2(-5, -5), at + Vector2(-1, -7), at + Vector2(4, -6),
			at + Vector2(6, -2), at + Vector2(5, 0)]), cloth)
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-2, -7), at + Vector2(0, -10), at + Vector2(2, -7)]), cloth.darkened(0.2))
	ci.draw_line(at + Vector2(-3, -6), at + Vector2(3, -6), cloth.darkened(0.4), 1.0)
	if mine:
		Look._dot(ci, at + Vector2(3, -8), 1.0, Color(1, 0.9, 0.5, 0.95))  # (a glint: yours)
