class_name Thrown
extends Node2D
## Something thrown (a bottle, a can, a lump of scrap), seen flying: an arc from
## the hand to where it lands, turning over as it goes. Only the look: the
## server decides where it lands and what hears it (see Combat.req_throw).

const ARC := 0.18  # how high it goes, for how far it's thrown
const SIZE := 15.0  # drawn size of the item's bag icon, in pixels (a bit big: it has to read in flight)

var from := Vector2.ZERO
var to := Vector2.ZERO
var time := 0.5
var id := ""
var lift := 0.0  # thrown from upstairs or a roof: drawn this far up (it may land lower)
var land_lift := 0.0
var t := 0.0


func _ready() -> void:
	z_index = 3
	position = from


func _process(delta: float) -> void:
	t += delta
	var k := clampf(t / time, 0.0, 1.0)
	position = from.lerp(to, k)
	queue_redraw()
	if k >= 1.0:
		queue_free()


func _draw() -> void:
	var k := clampf(t / time, 0.0, 1.0)
	var h := sin(k * PI) * (from.distance_to(to) * ARC + 8.0) + lerpf(lift, land_lift, k) + 14.0 * (1.0 - k)
	draw_circle(Vector2(0, 1), 2.2, Color(0, 0, 0, 0.25))  # its shadow on the ground
	draw_set_transform(Vector2(0, -h), t * 14.0, Vector2.ONE)
	Items.draw_icon(self, Rect2(-Vector2(SIZE, SIZE) * 0.5, Vector2(SIZE, SIZE)), id)
	draw_set_transform(Vector2.ZERO)
