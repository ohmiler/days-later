class_name WorldState
extends Node
## The one way the world's changeable state is kept (ROADMAP core 10): each
## kind of thing ("thing", "building", ...) registers how it starts, and from
## then on only what differs from that is stored, saved, sent to everyone as
## it changes, and sent in one go to someone joining. A new kind of state
## needs no saving or syncing code of its own: register it and set_state.
##
## (Doors, containers, pickups, corpses and bikes still keep their own older
## ways; they can move over when they're next worked on.)

var main: Main
var _kinds := {}  # kind -> {start: Callable(id) -> Dictionary, changed: Callable(id, state) or null}
var _states := {}  # kind -> {id: state}, only those that differ from how they started


## `start(id)` gives how one begins; `changed(id, state)` (optional) is told
## whenever one changes, on every machine (to redraw it, say).
func register(kind: String, start: Callable, changed := Callable()) -> void:
	_kinds[kind] = {start = start, changed = changed}
	if not _states.has(kind):
		_states[kind] = {}


## How one is now: how it started, with whatever has changed on top.
func state(kind: String, id: int) -> Dictionary:
	var s: Dictionary = _kinds[kind].start.call(id)
	s.merge(_states[kind].get(id, {}), true)
	return s


## Server: change one for everyone.
func set_state(kind: String, id: int, s: Dictionary) -> void:
	_apply.rpc(kind, id, s)


@rpc("authority", "call_local", "reliable")
func _apply(kind: String, id: int, s: Dictionary) -> void:
	if not _kinds.has(kind):
		return
	var start: Dictionary = _kinds[kind].start.call(id)
	var full := start.duplicate()
	full.merge(s, true)
	if full == start:
		_states[kind].erase(id)
	else:
		_states[kind][id] = full
	var cb: Callable = _kinds[kind].changed
	if cb.is_valid():
		cb.call(id, full)


## Everything that isn't as it started: {kind: {id: state}} (for a save).
func changed() -> Dictionary:
	return _states.duplicate(true)


## Put saved (or sent) states back, telling each kind as it goes.
func restore(all: Dictionary) -> void:
	for kind in all:
		if not _kinds.has(kind):
			continue
		for id in all[kind]:
			if id is int or id is float:
				_apply(kind, int(id), all[kind][id])


## Server: someone joining gets all of it.
func send_all(peer_id: int) -> void:
	_sync.rpc_id(peer_id, changed())


@rpc("authority", "call_remote", "reliable")
func _sync(all: Dictionary) -> void:
	restore(all)


## A fresh world: nothing has changed yet.
func clear() -> void:
	for kind in _states:
		_states[kind] = {}
