class_name Phantoms
extends Node
## Things that aren't there, for someone on a junkie's pills (Body condition
## "high"): zombies that come at you out of the corner of your eye and are
## gone before they reach you, groans from nowhere. On your own screen only:
## nobody else sees them, the server knows nothing of them.

const EVERY := Vector2(2.5, 6.0)  # seconds between one turning up and the next
const LIFE := 5.0
const SPEED := 46.0
const VANISH := 34.0  # this close, it's gone

var main: Main
var _t := 3.0
var _live: Array = []  # [zombie node, age]
var _next_id := 0


func tick(me: Player, delta: float) -> void:
	var on: bool = me != null and me.alive() and me.conditions.has("high")
	for e in _live.duplicate():
		_step(e, me, delta, on)
	if not on:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = randf_range(EVERY.x, EVERY.y)
	if randf() < 0.3:
		Sfx.play(main, "groan", me.position + Vector2.from_angle(randf() * TAU) * 60.0, -2.0, randf_range(0.7, 1.3))
		return
	var pos: Vector2 = me.position + Vector2.from_angle(randf() * TAU) * randf_range(110.0, 170.0)
	if not main.world.can_stand(pos, 5):
		return
	var z := Zombie.new()
	z.world = main.world
	z.players = {}
	z.zid = 2000000000 + _next_id * 8  # (from the street, as far as its looks go; never a real id)
	_next_id += 1
	z.position = pos
	z.net_pos = pos
	z.storey = me.storey
	z.z_index = 1
	main.add_child(z)
	z.set_kind("runner" if randf() < 0.3 else "normal")
	z.sight_k = 0.0
	_live.append([z, 0.0])


func _step(e: Array, me: Player, delta: float, on: bool) -> void:
	var z: Zombie = e[0]
	if not is_instance_valid(z):
		_live.erase(e)
		return
	e[1] += delta
	var near: bool = me != null and z.position.distance_to(me.position) < VANISH
	var going: bool = not on or near or e[1] > LIFE
	z.sight_k = move_toward(z.sight_k, 0.0 if going else 0.85, delta * (4.0 if near else 1.5))
	if going and z.sight_k <= 0.0:
		z.queue_free()
		_live.erase(e)
		return
	if me != null and not going:
		var step := (me.position - z.position).normalized() * SPEED * (1.5 if z.kind == "runner" else 1.0) * delta
		z.position += step
		z.net_pos = z.position
		z.state = 2


## Gone at once (a new zone, death...).
func clear() -> void:
	for e in _live:
		if is_instance_valid(e[0]):
			e[0].queue_free()
	_live.clear()
