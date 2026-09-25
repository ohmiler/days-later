class_name Zombie
extends Node2D
## AI runs on the server only; clients just interpolate to snapshots.

const SPEED := 38.0
const RADIUS := 5.0
const MAX_HP := 60.0

var world: World
var players: Dictionary  # shared reference to main's peer_id -> Player
var zid := 0
var hp := MAX_HP
var net_pos := Vector2.ZERO
var path: Array[Vector2i] = []
var target: Player
var repath := 0.0
var attack_cd := 0.0
var wander := Vector2.ZERO
var stun := 0.0  # staggered after being hit
var hit_t := 0.0  # > 0 while flinching from a hit (visual, every peer)
var hit_dir := Vector2.ZERO
var groan_t := randf_range(2.0, 10.0)
var outfit: Array = []  # [shirt, pants, hair] of the player this zombie used to be
var facing := 0.0
var last_pos := Vector2.ZERO
var skin: Color
var shirt: Color
var pants: Color
var hair: Color
var phase := 0.0
var view := [Look.FRONT, false]
var moving := false


## Server only.
func server_tick(delta: float) -> void:
	attack_cd -= delta
	repath -= delta
	if stun > 0:
		stun -= delta
		return
	if repath <= 0:
		repath = 0.5
		target = _nearest_player(240.0 if world.is_night else 140.0)
		path.clear()
		if target:
			path.assign(world.astar.get_id_path(world.to_cell(position), world.to_cell(target.position)))
			if not path.is_empty():
				path.remove_at(0)
		elif randf() < 0.3:
			wander = Vector2.from_angle(randf() * TAU) if randf() < 0.6 else Vector2.ZERO

	if target == null or not target.alive():
		_move(wander, delta * 0.5)
		return
	var d := position.distance_to(target.position)
	if d < 12:
		if attack_cd <= 0:
			target.take_damage(8)
			target.bitten = true
			attack_cd = 1.0
	elif d < 20 or path.is_empty():
		_move((target.position - position).normalized(), delta)
	else:
		var step := world.to_pos(path[0])
		if position.distance_to(step) < 3:
			path.remove_at(0)
		_move((step - position).normalized(), delta)


func _move(dir: Vector2, delta: float) -> void:
	position = world.slide(position, dir * SPEED * delta, RADIUS)


func _nearest_player(max_dist: float) -> Player:
	var best: Player = null
	var best_d := max_dist
	for p: Player in players.values():
		var d := position.distance_to(p.position)
		if p.alive() and d < best_d:
			best_d = d
			best = p
	return best


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = zid
	skin = Look.ZOMBIE_SKINS[rng.randi() % Look.ZOMBIE_SKINS.size()]
	shirt = Look.SHIRTS[rng.randi() % Look.SHIRTS.size()].darkened(0.15)
	pants = Look.PANTS[rng.randi() % Look.PANTS.size()]
	hair = Look.HAIRS[rng.randi() % Look.HAIRS.size()].darkened(0.3)
	if not outfit.is_empty():
		apply_outfit(outfit)


func apply_outfit(o: Array) -> void:
	outfit = o
	shirt = Color(o[0]).darkened(0.1)
	pants = o[1]
	hair = o[2]


func _process(delta: float) -> void:
	var before := position
	if not multiplayer.is_server():
		position = position.lerp(net_pos, minf(1.0, 15.0 * delta))
	var moved := position - before if not multiplayer.is_server() else position - last_pos
	last_pos = position
	moving = moved.length() > 0.03
	if moving:
		phase += moved.length() * 0.45
	if moving and hit_t <= 0:
		facing = lerp_angle(facing, moved.angle(), minf(1.0, 8.0 * delta))
	view = Look.pick_view(facing, view)
	hit_t = maxf(0.0, hit_t - delta)
	groan_t -= delta
	if groan_t <= 0:
		groan_t = randf_range(5.0, 12.0)
		var cam := get_viewport().get_camera_2d()
		if cam and cam.global_position.distance_to(global_position) < 260:
			Sfx.play(get_parent(), "groan", position, -8.0, randf_range(0.85, 1.15))
	# Flash bright for an instant when struck.
	modulate = Color(1, 1, 1).lerp(Color(2.2, 1.6, 1.5), clampf(hit_t / 0.25, 0, 1) ** 2)
	queue_redraw()


func flinch(dir: Vector2) -> void:
	hit_t = 0.25
	hit_dir = dir
	facing = (-dir).angle()  # stay facing whoever hit it while being knocked back


func _draw() -> void:
	var recoil := hit_dir * 3.0 * sin(clampf(hit_t / 0.25, 0, 1) * PI * 0.5)
	Look.draw_human(self, view, facing, phase, moving and hit_t <= 0, skin, shirt, pants, hair, true,
			Look.NONE, 0.0, false, false, recoil)
	Look.draw_hp(self, hp / MAX_HP)
