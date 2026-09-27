class_name Sight
extends RefCounted
## What your character can actually see: a wide view the way they face (170
## degrees, eyes plus the corners of them) as far as the screen, and a small
## circle all round (what you'd hear or feel right behind you). Walls,
## buildings and closed doors block it. Zombies and other people out of sight
## fade away (see Main._update_sight); the city itself is always shown.
##
## Only on your own screen, and only for looks: the server decides who sees
## whom (zombies have their own eyes, see Zombie._nearest_player).

const CONE := deg_to_rad(170.0)
const NEAR := 26.0  # all round you: close enough to hear, or feel

var world: World
var eye := Vector2.INF
var facing := 0.0
var reach := 400.0  # how far you see (about the screen)
var on := 0.0  # off up on the roofs (you see over everything), asleep, or dead
var cone := CONE  # a mascot's big head, a mask: less of it
var mirror := false  # a mirror on the helmet: a narrow glimpse behind (see MIRROR)
const MIRROR := deg_to_rad(40.0)
const MIRROR_REACH := 0.45  # of the usual reach


## Every frame, on the local machine.
func update(me: Player, delta: float, view_radius: float) -> void:
	var want := me != null and me.alive() and not me.on_roof and me.storey == 0 and not me.sleeping  # (upstairs, you look out of the windows)
	on = move_toward(on, 1.0 if want else 0.0, delta * 3.0)
	if me == null:
		return
	reach = view_radius
	eye = me.position + Vector2(0, -2)
	facing = me.aim.angle()
	mirror = me.has_mirror()
	cone = CONE * me.wear_mult("view")


## Is `pos` in view (for showing a zombie or another player there)?
func sees(pos: Vector2) -> bool:
	if on < 0.5 or eye == Vector2.INF:
		return true
	var v := pos - eye
	var d := v.length()
	if d < NEAR:
		return true
	var behind := mirror and absf(angle_difference(v.angle(), facing + PI)) < MIRROR * 0.5 and d < reach * MIRROR_REACH
	if not behind and (absf(angle_difference(v.angle(), facing)) > cone * 0.5 or d > reach):
		return false
	var hit: Array = world.sight_ray(eye, v / d, d)
	return hit[0] >= d - 6.0
