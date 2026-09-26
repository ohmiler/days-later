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


## Every frame, on the local machine.
func update(me: Player, delta: float, view_radius: float) -> void:
	var want := me != null and me.alive() and not me.on_roof and not me.sleeping
	on = move_toward(on, 1.0 if want else 0.0, delta * 3.0)
	if me == null:
		return
	reach = view_radius
	eye = me.position + Vector2(0, -2)
	facing = me.aim.angle()


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
