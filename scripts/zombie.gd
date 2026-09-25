class_name Zombie
extends Node2D
## AI runs on the server only; clients just interpolate to snapshots.

const RADIUS := 5.0
## Zombie breeds. The breed comes from the zombie's id, so every peer agrees
## without sending it. door = how hard it hits doors.
const KINDS := {
	"normal": {speed = 38.0, hp = 60.0, dmg = 8.0, girth = 1.0, door = 1.0},
	"runner": {speed = 64.0, hp = 35.0, dmg = 6.0, girth = 0.8, door = 0.7},
	"fat": {speed = 25.0, hp = 170.0, dmg = 14.0, girth = 1.5, door = 3.0},
	"screamer": {speed = 34.0, hp = 45.0, dmg = 6.0, girth = 0.9, door = 0.6},
}

var world: World
var players: Dictionary  # shared reference to main's peer_id -> Player
var zid := 0
var kind := "normal"
var speed := 38.0
var max_hp := 60.0
var hp := 60.0
var scream_cd := 0.0
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
const SIGHT_DAY := 120.0
const SIGHT_NIGHT := 180.0
var investigate := Vector2.ZERO  # server: where it heard something
var investigate_t := 0.0
var state := 0  # 0 idle, 1 heard something, 2 sees a player (sent to clients)
var alert_t := 0.0  # client: how long to show the ? / ! mark
var shown_state := 0
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


## Server only. Chase what it can see; otherwise go and look at what it heard.
func server_tick(delta: float) -> void:
	attack_cd -= delta
	repath -= delta
	investigate_t -= delta
	if stun > 0:
		stun -= delta
		return
	if repath <= 0:
		repath = 0.5
		target = _nearest_player(SIGHT_NIGHT if world.is_night else SIGHT_DAY)
		path.clear()
		var goal := Vector2.INF
		if target:
			goal = target.position
			investigate_t = 0.0
		elif investigate_t > 0.0:
			goal = investigate
		if goal != Vector2.INF:
			path.assign(world.path_between(position, goal))
		elif randf() < 0.3:
			wander = Vector2.from_angle(randf() * TAU) if randf() < 0.6 else Vector2.ZERO
	var prev_state := state
	state = 2 if target else (1 if investigate_t > 0.0 else 0)
	scream_cd -= delta
	if kind == "screamer" and state == 2 and prev_state != 2 and scream_cd <= 0.0 and get_parent().has_method("zombie_scream"):
		scream_cd = 8.0
		get_parent().zombie_scream(self)

	if target == null or not target.alive():
		if investigate_t > 0.0:
			if _bash_door_ahead():
				return
			if position.distance_to(investigate) < 10.0 or path.is_empty():
				investigate_t = minf(investigate_t, 1.5)  # arrived: look around a moment, then lose interest
				_move(wander, delta * 0.3)
			else:
				_follow(delta)
			return
		_move(wander, delta * 0.5)
		return
	var d := position.distance_to(target.position)
	if d >= 12 and _bash_door_ahead():
		return
	if d < 12:
		if attack_cd <= 0:
			target.take_damage(KINDS[kind].dmg)
			target.bitten = true
			attack_cd = 1.0
	elif d < 20 or path.is_empty():
		_move((target.position - position).normalized(), delta)
	else:
		_follow(delta)


## If a closed door is in the way, pound on it. Returns true while bashing.
func _bash_door_ahead() -> bool:
	var id := world.closed_door_near(position, 17.0)
	if id < 0:
		return false
	var dc: Vector2i = world.doors[id].cell
	var ahead := not path.is_empty() and path[0] == dc
	if not (ahead or path.is_empty()):
		return false
	facing = (world.to_pos(dc) - position).angle()
	if attack_cd <= 0.0:
		attack_cd = 1.1
		get_parent().damage_door(id, 12.0 * KINDS[kind].door)
	return true


func _follow(delta: float) -> void:
	var step := world.to_pos(path[0])
	if position.distance_to(step) < 3:
		path.remove_at(0)
		if path.is_empty():
			return
		step = world.to_pos(path[0])
	_move((step - position).normalized(), delta)


## A noise reached this zombie. Unless it is already chasing someone, it goes to look.
func hear(pos: Vector2) -> void:
	if target != null:
		return
	investigate = pos + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	investigate_t = 9.0
	repath = 0.0


func _move(dir: Vector2, delta: float) -> void:
	position = world.slide(position, dir * speed * delta, RADIUS)


## Closest player it can actually see: sneaking halves the range, walls block
## the view (except right up close, where it smells you).
func _nearest_player(max_dist: float) -> Player:
	var best: Player = null
	var best_d := INF
	for p: Player in players.values():
		if not p.alive():
			continue
		var d := position.distance_to(p.position)
		var reach := max_dist * (0.5 if p.sneak else 1.0)
		if d > reach or d > best_d:
			continue
		if d > 28.0:
			var eye := position + Vector2(0, -15)
			var to := p.position + Vector2(0, -15) - eye
			if world.ray_length(eye, to.normalized(), to.length()) < to.length() - 4.0:
				continue
		best_d = d
		best = p
	return best


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = zid
	set_kind(kind_for(zid) if outfit.is_empty() else "normal")
	skin = Look.ZOMBIE_SKINS[rng.randi() % Look.ZOMBIE_SKINS.size()]
	shirt = Look.SHIRTS[rng.randi() % Look.SHIRTS.size()].darkened(0.15)
	pants = Look.PANTS[rng.randi() % Look.PANTS.size()]
	hair = Look.HAIRS[rng.randi() % Look.HAIRS.size()].darkened(0.3)
	match kind:
		"runner":
			skin = skin.darkened(0.25)  # dried out and wiry
		"fat":
			skin = skin.lightened(0.12).lerp(Color("b8b890"), 0.4)
		"screamer":
			skin = Color("c8c6bc")
	if not outfit.is_empty():
		apply_outfit(outfit)


static func kind_for(id: int) -> String:
	var h := (id * 2654435761) % 1000
	if h < 680:
		return "normal"
	if h < 830:
		return "runner"
	if h < 940:
		return "fat"
	return "screamer"


func set_kind(k: String) -> void:
	var was_full := hp >= max_hp
	kind = k
	var d: Dictionary = KINDS[k]
	speed = d.speed
	max_hp = d.hp
	if was_full:
		hp = max_hp


func apply_outfit(o: Array) -> void:
	outfit = o
	if kind != "normal":
		set_kind("normal")
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
	# Show ? when it hears something, ! when it spots someone.
	if state > shown_state:
		alert_t = 1.3
		if state == 2:
			var cam := get_viewport().get_camera_2d()
			if cam and cam.global_position.distance_to(global_position) < 300:
				Sfx.play(get_parent(), "groan", position, -2.0, randf_range(1.05, 1.25))
	shown_state = state
	alert_t = maxf(0.0, alert_t - delta)
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
			Look.NONE, 0.0, false, false, recoil, {}, 0.0, 1.0, KINDS[kind].girth)
	Look.draw_hp(self, hp / max_hp)
	if alert_t > 0.0 and state > 0:
		var a := clampf(alert_t / 0.4, 0.0, 1.0)
		var pop := 1.0 + 0.4 * clampf((alert_t - 1.1) / 0.2, 0.0, 1.0)
		var f := UiTheme.world("Kanit-ExtraBold")
		var mark := "!" if state == 2 else "?"
		var col := Color(UiTheme.BLOOD, a) if state == 2 else Color(UiTheme.WARN, a)
		var sz := int(12 * pop)
		draw_string_outline(f, Vector2(-10, -38), mark, HORIZONTAL_ALIGNMENT_CENTER, 20, sz, 3, Color(0, 0, 0, a * 0.8))
		draw_string(f, Vector2(-10, -38), mark, HORIZONTAL_ALIGNMENT_CENTER, 20, sz, col)
