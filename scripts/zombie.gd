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

const GROUND_BITE_CD := 1.6  # a zombie on the ground snaps at your legs this often
## A lunge that lands can grab hold instead of biting at once: you can't move
## or fight, only struggle (Actions.req_struggle) before it bites, harder.
## Hit by anyone else, knocked down or killed, it lets go.
static var grab_chance := 0.4  # (a var so tests about biting can turn grabbing off)
const GRAB_TIME := 2.2
const GRAB_BITE := 1.3  # the bite when it had hold of you
var grab_peer := 0  # server: the player it has hold of (0: nobody)

var world: World
var players: Dictionary  # shared reference to main's peer_id -> Player
var zid := 0
var kind := "normal"
var speed := 38.0
var max_hp := 60.0
var hp := 60.0
var scream_cd := 0.0
var trap_cd := 0.0  # server: time until spikes can hurt it again
var net_pos := Vector2.ZERO
var path: Array[Vector2i] = []
var target: Player
var repath := 0.0
var attack_cd := 0.0
var wander := Vector2.ZERO
var stun := 0.0  # staggered after being hit
var hit_t := 0.0  # > 0 while flinching from a hit (visual, every peer)
var hit_dir := Vector2.ZERO
var sight_k := 1.0  # client: 0 when out of your character's sight (see Sight), fading
var freeze := 0.0  # client: the flinch holds still this long when struck (hitstop)
var groan_t := randf_range(2.0, 10.0)
const SIGHT_DAY := 120.0  # how far it sees you in daylight, or at night when you're in the light
const SIGHT_DARK := 55.0  # at night, in the dark: little more than a shape moving close by
const SIGHT_CONE := 0.5  # cos of half its field of view (120 degrees): eyes look ahead
const SENSE := 22.0  # this close it knows you're there whichever way it faces
var investigate := Vector2.ZERO  # server: where it heard something
var investigate_t := 0.0
var state := 0  # 0 idle, 1 heard something, 2 sees a player (sent to clients)
var alert_t := 0.0  # client: how long to show the ? / ! mark
var shown_state := 0
var outfit: Array = []  # [shirt, pants, hair, wear ids] of the player this zombie used to be
var wear := {}  # slot -> item id; ordinary zombies' clothes come from their id (Items.zombie_wear)
var wear_look := {}
var facing := 0.0
var last_pos := Vector2.ZERO
var skin: Color
var shirt: Color
var pants: Color
var hair: Color
var phase := 0.0
var view := [Look.FRONT, false]
var moving := false

## Attacks are telegraphed: it rears back for LUNGE seconds, then bites if you
## are still in reach. Hitting it during the wind-up stops the bite.
const LUNGE := 0.45
const DOWN_TIME := 1.6
const RISE_TIME := 0.8  # the end of DOWN_TIME, spent getting up
var lunge_t := 0.0  # server: counting down to the bite
var down_t := 0.0  # server: knocked flat, getting up when it runs out
var missing := 0  # Look.LOST_* bits; arms can be cut off in a fight
var flags := 0  # 1 = lunging, 2 = down, 4 = upstairs; from the server fields, or from snapshots
var up := false  # upstairs in a shophouse (World.upper): it followed someone up the stairs
var lift := 0.0  # drawn this far up (eases to a storey while upstairs)
var climb := Vector2i(-1, -1)  # server: the stairs it is heading for, after someone on the other floor
const NO_STAIRS := Vector2i(-1, -1)
# Client animation clocks, started when a flag switches on.
var atk_t := -1.0
var down_el := -1.0
var up_el := -1.0
var _risen := 0.0  # how far through getting up it had got when the server let it up
var scream_t := 0.0
var fall_side := 1.0
# Looks that come from the id so every peer agrees.
var vary := {}
var gore := 0
var hair_style := "short"
var gait := 1.0
var _path_goal := Vector2.INF  # where the current path leads, to reuse it while that stays put


## Server only. Chase what it can see; otherwise go and look at what it heard.
func server_tick(delta: float) -> void:
	attack_cd -= delta
	repath -= delta
	investigate_t -= delta
	flags = (1 if lunge_t > 0.0 else 0) | (2 if down_t > 0.0 else 0) | (4 if up else 0) | (8 if grab_peer != 0 else 0)
	if grab_peer != 0 and (down_t > 0.0 or stun > 0.0):
		release()  # (knocked over or hit: it lets go)
	if down_t > 0.0:
		down_t -= delta
		# Flat on the ground it still snaps at ankles that come too close.
		if attack_cd <= 0.0:
			for p: Player in players.values():
				if p.alive() and not p.on_roof and p.on_car < 0 and p.up == up and p.riding < 0 and p.position.distance_to(position) < 11.0:
					attack_cd = GROUND_BITE_CD
					p.bite(bite_damage() * 0.6, "legs")
					break
		return
	if stun > 0:
		stun -= delta
		lunge_t = 0.0  # a hit knocks it out of its lunge
		return
	if grab_peer != 0:
		_hold(delta)
		return
	if lunge_t > 0.0:
		lunge_t -= delta
		if lunge_t <= 0.0 and target and target.alive() and not target.on_roof and target.on_car < 0 and target.up == up and position.distance_to(target.position) < 16.0:
			var arms := 2 - int(missing & Look.LOST_ARM_L != 0) - int(missing & Look.LOST_ARM_R != 0)
			if arms > 0 and target.grabbed_by < 0 and not target.vaulting() and not target.under_vehicle() and randf() < grab_chance:
				grab(target)
			else:
				target.bite(bite_damage(), target.bite_part(position, false))
		return
	if repath <= 0:
		repath = randf_range(0.4, 0.7)  # spread out, so they do not all think on the same frame
		# Someone it was after went up (or down) the stairs: after them. Else
		# whoever it can see on its own floor.
		climb = NO_STAIRS
		if target and target.alive() and not target.on_roof and target.up != up \
				and position.distance_to(target.position) < 160.0:
			climb = _stairs_after(target)
		if climb == NO_STAIRS:
			target = _nearest_player()
		var goal := Vector2.INF
		if climb != NO_STAIRS:
			goal = world.to_pos(climb)
		elif target:
			goal = target.position
			investigate_t = 0.0
		elif investigate_t > 0.0:
			goal = investigate
		if goal == Vector2.INF:
			path.clear()
			if randf() < 0.3:
				wander = Vector2.from_angle(randf() * TAU) if randf() < 0.6 else Vector2.ZERO
		elif up:
			path.assign(world.path_up(position, goal))  # (small rooms up there: a fresh route each time)
			_path_goal = goal
		elif target and climb == NO_STAIRS and position.distance_to(goal) < 140.0 and _clear_line(goal):
			path.clear()  # it can see you and you are close: straight at you, no route needed
		elif path.is_empty() or goal.distance_to(_path_goal) > 24.0:
			_path_goal = goal
			path.assign(world.path_between(position, goal))
			# Standing at a shut door with the only other way in far around the block?
			# Smash through instead of taking the long way.
			if path.size() * World.TILE > 3.0 * position.distance_to(goal) + 48.0 and world.closed_door_near(position, 20.0) >= 0:
				path.clear()
	var prev_state := state
	state = 2 if target else (1 if investigate_t > 0.0 else 0)
	scream_cd -= delta
	if kind == "screamer" and state == 2 and prev_state != 2 and scream_cd <= 0.0 and get_parent() is Main:
		scream_cd = 8.0
		get_parent().survival.zombie_scream(self)

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
	if target.up != up:
		# On its way up (or down) the stairs after them.
		if climb != NO_STAIRS and position.distance_to(world.to_pos(climb)) < 7.0:
			up = target.up
			position = world.to_pos(climb)
			path.clear()
			repath = 0.0
		elif not up and _bash_door_ahead():
			return
		elif not path.is_empty():
			_follow(delta)
		elif climb != NO_STAIRS:
			_move((world.to_pos(climb) - position).normalized(), delta)
		return
	var d := position.distance_to(target.position)
	if d >= 12 and not up and _bash_door_ahead():
		return
	if target.on_car >= 0 and d < 18:
		# Up on a car out of reach: it bangs on the car, and gets others' attention.
		facing = (target.position - position).angle()
		if attack_cd <= 0:
			attack_cd = randf_range(0.9, 1.5)
			if get_parent() is Main:
				get_parent().actions.bang_car(target.on_car, position)
		return
	if d < 12:
		if attack_cd <= 0:
			lunge_t = LUNGE
			attack_cd = 1.2
			facing = (target.position - position).angle()
	elif d < 20 or path.is_empty():
		_move((target.position - position).normalized(), delta)
	else:
		_follow(delta)


## If a closed door is in the way, pound on it. Returns true while bashing.
## Nothing solid between here and `to` (so walking straight there works).
func _clear_line(to: Vector2) -> bool:
	var d := to - position
	return world.ray_length(position + Vector2(0, -4), d.normalized(), d.length()) >= d.length() - 4.0


## Get hold of `p`: they can't move or fight until they struggle free.
func grab(p: Player) -> void:
	grab_peer = p.peer_id
	p.grabbed_by = zid
	p.grab_t = GRAB_TIME
	p.struggle = 0.0
	p.prone = false
	p.stand_up()
	if get_parent() is Main:
		get_parent()._toast(p, "โดนจับ! กด Space หรือคลิกรัว ๆ ให้หลุด")


## Holding someone: face them; if they haven't got free in time, bite.
func _hold(delta: float) -> void:
	var p: Player = players.get(grab_peer)
	if p == null or not p.alive() or p.grabbed_by != zid:
		release()
		return
	facing = (p.position - position).angle()
	p.grab_t -= delta
	if p.grab_t <= 0.0:
		p.bite(bite_damage() * GRAB_BITE, p.bite_part(position, false))
		release()
		attack_cd = 1.5


## Let go of whoever it has hold of.
func release() -> void:
	var p: Player = players.get(grab_peer)
	if p and p.grabbed_by == zid:
		p.grabbed_by = -1
		p.struggle = 0.0
	grab_peer = 0


## Fewer arms, less to grab you with.
func bite_damage() -> float:
	var arms := 2 - int(missing & Look.LOST_ARM_L != 0) - int(missing & Look.LOST_ARM_R != 0)
	return KINDS[kind].dmg * (0.5 + 0.25 * arms)


## Server: knocked flat by a kick.
func knock_down() -> void:
	down_t = DOWN_TIME
	lunge_t = 0.0


## An arm that is still attached, to cut off, or -1.
func arm_left_to_cut() -> int:
	var arms := []
	if not missing & Look.LOST_ARM_L:
		arms.append(Look.LOST_ARM_L)
	if not missing & Look.LOST_ARM_R:
		arms.append(Look.LOST_ARM_R)
	return arms.pick_random() if not arms.is_empty() else -1


## Everything needed to draw this body (for corpses and flying parts).
func body_look() -> Dictionary:
	return {skin = skin, shirt = shirt, pants = pants, hair = hair, hair_style = hair_style, wear = wear_look,
			missing = missing, gore = gore}


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
		get_parent().doors.damage_door(id, 12.0 * KINDS[kind].door)
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
	position = world.slide(position, dir * speed * (1.0 if up else world.slow_at(position)) * delta, RADIUS, false, false, up)


## The stairs to take after someone on the other floor: in the building
## they're up in, or (coming down) the one it's up in. NO_STAIRS if none.
func _stairs_after(p: Player) -> Vector2i:
	var b = world.building_at.get(world.to_cell(position if up else p.position))
	if b == null or not b.data.get("upper", false) or not b.data.has("stairs"):
		return NO_STAIRS
	return b.data.stairs


## Closest player it can actually see. By day, or when you stand in the light
## at night, it sees you a long way off; in the dark only close by. It looks
## the way it faces (a 120 degree view), so you can creep up from behind;
## sneaking halves the range, and walls block the view (except right up close).
func _nearest_player() -> Player:
	var best: Player = null
	var best_d := INF
	for p: Player in players.values():
		if not p.alive() or p.on_roof or p.up != up:
			continue
		if up and world.building_at.get(world.to_cell(p.position)) != world.building_at.get(world.to_cell(position)):
			continue  # upstairs, only the one building
		var d := position.distance_to(p.position)
		var lit := world.is_lit(p.position) or (p.riding >= 0 and p.riding < world.vehicles.size() and Vehicles.headlight_on(world.vehicles[p.riding], world))  # (a headlight shows you up)
		var reach := SIGHT_DAY if lit else SIGHT_DARK
		if p.under_vehicle():
			reach = SENSE  # (under a bus: only right up close does it know you're there)
		elif p.prone:
			reach *= 0.35  # flat on the ground
		elif p.sneak:
			reach *= 0.5
		elif p.sitting != -1 or p.sleeping:
			reach *= 0.65  # (low down, harder to spot)
		if d > reach or d > best_d:
			continue
		# Eyes look ahead; right up close it senses you any way round. Once it
		# has you it keeps turning after you.
		if d > SENSE and p != target and Vector2.from_angle(facing).dot((p.position - position) / d) < SIGHT_CONE:
			continue
		if d > 28.0 and not up:
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
	_set_wear(Items.zombie_wear(zid))
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
	# No two shamble quite the same.
	var r2 := RandomNumberGenerator.new()
	r2.seed = zid * 31 + 7
	vary = {tilt = Vector2(r2.randf_range(-0.6, 1.3), r2.randf_range(-0.2, 0.9)), arm_y = r2.randf_range(-1.6, 1.6),
			droop = (r2.randi() % 2) if r2.randf() < 0.2 else -1, limp = r2.randf_range(0.3, 1.7)}
	gait = r2.randf_range(0.85, 1.2)
	gore = r2.randi() % 30
	hair_style = ["short", "short", "long", "buzz", "bald", "ponytail"][r2.randi() % 6]
	facing = RandomNumberGenerator.new().randf_range(-PI, PI) if zid == 0 else float(zid * 2654435761 % 6283) / 1000.0 - PI  # standing about, facing anywhere
	if outfit.is_empty() and r2.randf() < 0.07:
		missing = Look.LOST_ARM_L if r2.randf() < 0.5 else Look.LOST_ARM_R  # lost an arm before it turned


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
	_set_wear(o[3] if o.size() > 3 else {})


func _set_wear(ids: Dictionary) -> void:
	wear = ids
	wear_look = Items.wear_draw(ids)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		up = flags & 4 != 0
	lift = lerpf(lift, BuildingProp.GROUND_H if up else 0.0, minf(1.0, 12.0 * delta))
	z_index = 2 if lift > 1.0 else 1
	var before := position
	if not multiplayer.is_server():
		position = position.lerp(net_pos, minf(1.0, 15.0 * delta))
	var moved := position - before if not multiplayer.is_server() else position - last_pos
	last_pos = position
	moving = moved.length() > 0.03
	if moving:
		phase += moved.length() * (0.3 if kind == "runner" else 0.45) * gait  # (a runner's strides are long, not quick)
	# Start or finish the lunge and knock-down animations as the flags change.
	if flags & 1 and atk_t < 0.0:
		atk_t = 0.0
	if atk_t >= 0.0:
		atk_t += delta
		if atk_t > LUNGE + 0.2:
			atk_t = -1.0
	if flags & 2:
		if down_el < 0.0:
			down_el = 0.0
			fall_side = -1.0 if hit_dir.x < 0 else 1.0
		down_el += delta
	elif down_el >= 0.0:
		down_el = -1.0
		up_el = 0.0
	if up_el >= 0.0:
		up_el += delta
		if up_el > 0.2:
			up_el = -1.0
	if kind == "screamer" and state == 2 and shown_state != 2:
		scream_t = 1.0
	scream_t = maxf(0.0, scream_t - delta * 0.9)
	if moving and hit_t <= 0:
		facing = lerp_angle(facing, moved.angle(), minf(1.0, 8.0 * delta))
	view = Look.pick_view(facing, view)
	if freeze > 0.0:
		freeze -= delta  # held at the moment of the blow
	else:
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
	modulate.a = sight_k
	_maybe_redraw(delta)


## Drawing a zombie is the costly part of a frame, so only redraw when it
## shows: never off screen, once when it stands still, and less often the
## further it is from the middle of the screen.
var _redraw_t := 0.0
var _drawn_still := false
var _drawn_hp := -1.0


func _maybe_redraw(delta: float) -> void:
	var vp := get_viewport()
	var at := get_global_transform_with_canvas().origin
	var screen := vp.get_visible_rect()
	var on := screen.grow(90.0).has_point(at) and sight_k > 0.01  # (nothing to draw out of sight)
	if visible != on:
		visible = on
		_drawn_still = false
	if not on:
		return
	var busy := moving or flags & 8 != 0 or hit_t > 0.0 or atk_t >= 0.0 or down_el >= 0.0 or up_el >= 0.0 or scream_t > 0.0 or alert_t > 0.0
	if not busy:
		if not _drawn_still or hp != _drawn_hp:
			_drawn_still = true
			_drawn_hp = hp
			queue_redraw()
		return
	_drawn_still = false
	_redraw_t -= delta
	if _redraw_t > 0.0:
		return
	var off_centre := at.distance_to(screen.get_center()) / (screen.size.length() * 0.5)
	_redraw_t = 0.0 if off_centre < 0.35 else (1.0 / 30.0 if off_centre < 0.7 else 1.0 / 20.0)
	_drawn_hp = hp
	queue_redraw()


func flinch(dir: Vector2) -> void:
	hit_t = 0.25
	freeze = Combat.HITSTOP
	hit_dir = dir
	facing = (-dir).angle()  # stay facing whoever hit it while being knocked back


func _draw() -> void:
	var snap := sin(clampf(hit_t / 0.25, 0, 1) * PI * 0.5)
	var st := {view = view, angle = facing, phase = phase, moving = moving and hit_t <= 0 and atk_t < 0.0, zombie = true,
			recoil = hit_dir * 3.0 * snap, girth = KINDS[kind].girth, breed = kind, vary = vary,
			hit = Vector2(hit_dir.x * (-1.0 if view[1] else 1.0), hit_dir.y) * 1.8 * snap, scream = 1.0 - scream_t if scream_t > 0.0 else 0.0}
	if atk_t >= 0.0:
		st.bite = clampf(atk_t / (LUNGE + 0.2), 0.0, 1.0)
	elif flags & 8:
		st.bite = 0.5  # holding someone: arms out, leaning in
	# Knocked down: falls like a body, lies there, then sits up and gets back on
	# its feet (finishing quickly if the server lets it up before that's done).
	if down_el >= 0.0:
		var r := (down_el - (DOWN_TIME - RISE_TIME)) / RISE_TIME
		if r > 0.0:
			_risen = minf(r, 1.0)
			st.rise = _risen
		else:
			_risen = 0.0
			st.fall = clampf(down_el / 0.6, 0.001, 1.0)
		st.fall_dir = fall_side
	elif up_el >= 0.0:
		st.rise = lerpf(_risen, 1.0, clampf(up_el / 0.2, 0.0, 1.0))
		st.fall_dir = fall_side
	var lk := body_look()
	lk.mouth = 1.0 if kind == "screamer" else 0.0
	Look.lift = Vector2(0, -lift)
	Look.draw(self, st, lk)
	Look.lift = Vector2.ZERO
	draw_set_transform(Vector2(0, -lift))
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
