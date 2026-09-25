class_name Things
extends Node
## Things in the world that have a state and can be used: taps, radios, vending
## machines, and in time stoves, beds, generators, light switches...
##
## To add one: put it in DEFS (its name, starting state, whether it blocks the
## way), give it actions in `actions_for`, write `_do_<kind>_<verb>` for what
## each action does, and draw it in ThingProp. Saving, sending the state to
## everyone, the E prompt and the wheel, reach and "same building" checks all
## come from here. The state is a plain dictionary; only what differs from
## the starting state is saved or sent.

var main: Main

const REACH := 18.0
const DEFS := {
	"tap": {name = "ก๊อกน้ำ", state = {water = 10}, solid = true},
	"radio": {name = "วิทยุ", state = {on = false}, solid = false},
	"vending": {name = "ตู้กดน้ำ", state = {broken = false}, solid = true},
}
const RADIO_NOISE := 95.0  # a playing radio calls zombies this far, every few seconds

var _radio_t := 0.0


# --- What can be done ------------------------------------------------------------

## Everything `p` can do with thing `id` right now: the same {verb, label, ok, why}
## as the rest of Interact.
func actions_for(p: Player, id: int) -> Array:
	var th: Dictionary = main.world.things[id]
	var s: Dictionary = th.state
	match th.kind:
		"tap":
			return [_act("drink", "ดื่มน้ำจากก๊อก", s.water > 0 and p.thirst < 98.0,
					"น้ำไม่ไหลแล้ว" if s.water <= 0 else "ยังไม่กระหาย")]
		"radio":
			return [_act("toggle", "ปิดวิทยุ" if s.on else "เปิดวิทยุ (ซอมบี้ได้ยิน)")]
		"vending":
			if not s.broken:
				return [_act("smash", "ทุบตู้เอาเครื่องดื่ม (เสียงดัง)")]
	return []


## What E says it is, with how it is doing.
static func title_of(th: Dictionary) -> String:
	var name: String = DEFS[th.kind].name
	var s: Dictionary = th.state
	match th.kind:
		"tap":
			return name + (" · แห้งแล้ว" if s.water <= 0 else "")
		"radio":
			return name + (" · เปิดอยู่" if s.on else "")
		"vending":
			return name + (" · พังแล้ว" if s.broken else "")
	return name


func _act(verb: String, label: String, ok := true, why := "") -> Dictionary:
	return {verb = verb, label = label, ok = ok, why = why if not ok else "", key = ""}


# --- Doing it (server) -------------------------------------------------------------

## Carry out `verb` on thing `id` for `p`, if it is on offer and possible.
func act(p: Player, id: int, verb: String) -> void:
	if id < 0 or id >= main.world.things.size():
		return
	var a := Interact.find_action(actions_for(p, id), verb)
	if a.is_empty():
		return
	if not a.ok:
		main._toast(p, a.why)
		return
	var th: Dictionary = main.world.things[id]
	var fn := "_do_%s_%s" % [th.kind, verb]
	if has_method(fn):
		call(fn, p, th)


func _do_tap_drink(p: Player, th: Dictionary) -> void:
	p.thirst = minf(100.0, p.thirst + 35.0)
	var s: Dictionary = th.state.duplicate()
	s.water -= 1
	set_state(th.id, s)
	main.fx_sound.rpc("eat", p.position)
	main._toast(p, "ดื่มน้ำจากก๊อก" + (" · น้ำหยดสุดท้ายแล้ว" if s.water <= 0 else ""))


func _do_radio_toggle(p: Player, th: Dictionary) -> void:
	set_state(th.id, {on = not th.state.on})
	main.fx_sound.rpc("ui_click", main.world.to_pos(th.cell))


func _do_vending_smash(p: Player, th: Dictionary) -> void:
	set_state(th.id, {broken = true})
	var at := main.world.to_pos(th.cell)
	main.fx_sound.rpc("glass", at)
	main._make_noise(at, 200.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = th.id * 131 + main.world_seed
	for i in rng.randi_range(2, 4):
		var id: String = ["water", "water", "energy"][rng.randi() % 3]
		main._spawn_pickup(at + Vector2(rng.randf_range(-8, 8), rng.randf_range(8, 14)), {id = id, n = 1, hp = 0})
	main._toast(p, "ทุบตู้แตก · เสียงดังไปทั้งซอย")


## A playing radio keeps drawing zombies to it.
func server_tick(delta: float) -> void:
	_radio_t -= delta
	if _radio_t > 0.0:
		return
	_radio_t = 5.0
	for th in main.world.things:
		if th.kind == "radio" and th.state.on:
			main._make_noise(main.world.to_pos(th.cell), RADIO_NOISE)


# --- State: set, send, save ------------------------------------------------------

## Change a thing's state for everyone (server).
func set_state(id: int, state: Dictionary) -> void:
	thing_state.rpc(id, state)


@rpc("authority", "call_local", "reliable")
func thing_state(id: int, state: Dictionary) -> void:
	var w: World = main.world
	if w == null or id < 0 or id >= w.things.size():
		return
	var th: Dictionary = w.things[id]
	th.state = _with_defaults(th.kind, state)
	if id < w.thing_nodes.size():
		w.thing_nodes[id].refresh()


## Every thing that is not as it started, for a save or a player joining.
func changed() -> Dictionary:
	var out := {}
	for th in main.world.things:
		if th.state != DEFS[th.kind].state:
			out[th.id] = th.state
	return out


## Put saved (or sent) states back.
func restore(states: Dictionary) -> void:
	for id in states:
		if id is int and id >= 0 and id < main.world.things.size():
			thing_state(id, states[id])


## A newly joined player gets everything that has changed.
func send_all(peer_id: int) -> void:
	things_sync.rpc_id(peer_id, changed())


@rpc("authority", "call_remote", "reliable")
func things_sync(states: Dictionary) -> void:
	restore(states)


static func _with_defaults(kind: String, state: Dictionary) -> Dictionary:
	var s: Dictionary = DEFS[kind].state.duplicate()
	s.merge(state, true)
	return s


# --- Placing them in the city (generation) ---------------------------------------

## Put taps in back rooms, radios in some shops, vending machines outside
## mini-marts and a few shops. Runs last in city generation (its random numbers
## come after everything else, so older saved cities keep their layout).
static func place_all(w: World, rng: RandomNumberGenerator) -> void:
	for rec in w.buildings:
		if not rec.has("rooms"):
			continue
		var rooms: Array = rec.rooms
		var clear: Array = rec.keep_clear
		var back: Rect2i = rooms[-1]
		if rng.randf() < 0.7:
			# On the back wall of the back room: the kitchen tap.
			for tries in 6:
				var c := Vector2i(rng.randi_range(back.position.x, back.end.x - 1), back.position.y)
				if c.x not in clear and _free(w, c):
					_add(w, "tap", c)
					break
		if rng.randf() < 0.22:
			var room: Rect2i = rooms[0]
			for tries in 6:
				var c := Vector2i(rng.randi_range(room.position.x, room.end.x - 1), rng.randi_range(room.position.y, room.end.y - 1))
				if c.x not in clear and _free(w, c):
					_add(w, "radio", c)
					break
		var r: Rect2i = rec.rect
		if rec.kind == "store" or rng.randf() < 0.06:
			for tries in 4:
				var c := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), r.end.y)
				if w.get_tile(c) in [World.SIDEWALK, World.SOI] and CityGen._fits(w, [c]):
					_add(w, "vending", c)
					break


static func _free(w: World, c: Vector2i) -> bool:
	if w.get_tile(c) != World.FLOOR or w.blocked.has(c):
		return false
	for d in World.DIRS:
		if w.get_tile(c + d) == World.DOOR or w.blocked.has(c + d):
			return false
	return true


static func _add(w: World, kind: String, c: Vector2i) -> void:
	if DEFS[kind].solid:
		w.blocked[c] = true
	w.things.append({id = w.things.size(), kind = kind, cell = c, state = DEFS[kind].state.duplicate()})
