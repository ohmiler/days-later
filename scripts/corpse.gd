class_name Corpse
extends Node2D
## A body left on the ground: plays the fall, bleeds out, then fades away.

const LIFE := 40.0

var skin: Color
var shirt: Color
var pants: Color
var hair: Color
var zombie := true
var fall_dir := 1.0
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	if t > LIFE:
		queue_free()
		return
	modulate.a = clampf((LIFE - t) / 4.0, 0.0, 1.0)
	if t < 3.0 or t > LIFE - 4.0:
		queue_redraw()


func _draw() -> void:
	Look.draw_blood_pool(self, fall_dir, clampf((t - 0.5) / 3.0, 0.0, 1.0))
	Look.draw_human(self, [Look.SIDE, fall_dir > 0], 0.0, 0.0, false, skin, shirt, pants, hair, zombie,
			Look.NONE, 0.0, false, false, Vector2.ZERO, {}, clampf(t / 0.75, 0.001, 1.0), fall_dir)
