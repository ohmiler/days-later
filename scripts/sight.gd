class_name Sight
extends Node2D
## What your character can actually see. From their eyes, lines are cast
## across the map: a wide view the way they face (170 degrees, eyes plus the
## corners of them) as far as the screen, and a small circle all round (what
## you'd hear or feel right behind you). Walls, buildings and closed doors
## stop them. Everything outside is shaded over like a memory of the place,
## and zombies and other people there aren't shown (see sees()).
##
## Only on your own screen, and only for looks: the server decides who sees
## whom (zombies have their own eyes, see Zombie._nearest_player).

const CONE := deg_to_rad(170.0)
const NEAR := 26.0  # all round you: close enough to hear, or feel
const FEATHER := 10.0  # the edge of the view fades over this many pixels
const FACADE := 44.0  # a building seen from the street: its front wall is in view, up to its first floor
const SHADE := Color(0.02, 0.02, 0.04, 0.62)
const FAR := 3000.0

var world: World
var eye := Vector2.INF
var facing := 0.0
var reach := 400.0  # how far the view is cast (about the screen)
var on := 0.0  # fades in and out: off up on the roofs, asleep, or dead
var _pts := PackedVector2Array()  # where each line stopped, going round
var _dirs := PackedVector2Array()
var _refresh := 0.0


## Every frame, on the local machine.
func update(me: Player, delta: float, view_radius: float) -> void:
	var want := me != null and me.alive() and not me.on_roof and not me.sleeping
	on = move_toward(on, 1.0 if want else 0.0, delta * 3.0)
	visible = on > 0.01
	modulate.a = on
	if me == null or not visible:
		return
	reach = view_radius
	var e := me.position + Vector2(0, -2)
	var f := me.aim.angle()
	_refresh -= delta
	# (Cast again only when you've moved or turned, or now and then for doors opening.)
	if e.distance_to(eye) > 1.0 or absf(angle_difference(f, facing)) > 0.015 or _refresh <= 0.0:
		eye = e
		facing = f
		_refresh = 0.2
		_cast()
		queue_redraw()


func _cast() -> void:
	_pts = PackedVector2Array()
	_dirs = PackedVector2Array()
	var half := CONE * 0.5
	# Round the full circle: a line every 1.5 degrees within the view, every 12 outside it.
	var angles := PackedFloat32Array()
	var a := -half
	while a < half:
		angles.append(a)
		a += deg_to_rad(1.5)
	angles.append(half)
	a = half + deg_to_rad(12.0)
	# (Out in the street, a building's front wall is seen up to its first floor;
	# from inside, a wall is just a wall.)
	var outside := world.get_tile(world.to_cell(eye)) not in [World.FLOOR, World.DOOR]
	while a < TAU - half - 0.001:
		angles.append(a)
		a += deg_to_rad(12.0)
	for rel in angles:
		var in_view := rel <= half + 0.0001 or rel >= TAU - half
		var d := Vector2.from_angle(facing + rel)
		var lim := reach if in_view else NEAR
		var hit: Array = world.sight_ray(eye, d, lim)
		var r: float = hit[0]
		if outside and in_view and hit[1] != Vector2i(-1, -1) and d.y < -0.2:
			r = minf(r + FACADE, lim)  # a front wall facing you is seen, not just its foot
		_pts.append(eye + d * r)
		_dirs.append(d)


## Is `pos` in view (for showing a zombie or another player there)?
func sees(pos: Vector2) -> bool:
	if on < 0.5 or eye == Vector2.INF:
		return true
	var v := pos - eye
	var d := v.length()
	if d < NEAR:
		return true
	if absf(angle_difference(v.angle(), facing)) > CONE * 0.5 or d > reach:
		return false
	var hit: Array = world.sight_ray(eye, v / d, d)
	return hit[0] >= d - 6.0


## The shade over everything out of view: between each pair of lines, from
## where they stopped out to beyond the screen, with a soft edge. One batch.
func _draw() -> void:
	var n := _pts.size()
	if n < 3:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var clear := Color(SHADE, 0.0)
	for i in n:
		var j := (i + 1) % n
		var p0 := _pts[i]
		var p1 := _pts[j]
		var q0 := p0 + _dirs[i] * FEATHER
		var q1 := p1 + _dirs[j] * FEATHER
		var f0 := eye + _dirs[i] * FAR
		var f1 := eye + _dirs[j] * FAR
		pts.append_array(PackedVector2Array([p0, p1, q1, p0, q1, q0, q0, q1, f1, q0, f1, f0]))
		cols.append_array(PackedColorArray([clear, clear, SHADE, clear, SHADE, SHADE, SHADE, SHADE, SHADE, SHADE, SHADE, SHADE]))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), pts, cols)
