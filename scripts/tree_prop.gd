class_name TreeProp
extends Node2D
## One tree, drawn standing up. Origin is the trunk base so it y-sorts
## correctly against characters.

const SCALE := 1.4  # drawn this much bigger than the sketch below

var cell := Vector2i.ZERO


func _draw() -> void:
	var h := func(k: int) -> float: return World.hash01(cell.x, cell.y, k)
	var r: float = 10.0 + h.call(1) * 4.0
	var green := Color("3f5431").lightened((h.call(2) - 0.5) * 0.18)
	var bark := Color("4a3a2c")

	draw_set_transform(Vector2(6, -1), 0, Vector2(1.5, 0.45))
	draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	draw_polygon(PackedVector2Array([Vector2(-2.4, 0), Vector2(2.4, 0), Vector2(1.5, -18), Vector2(-1.5, -18)]),
			PackedColorArray([bark.darkened(0.3), bark.lightened(0.05), bark, bark.darkened(0.4)]))

	var top := Vector2((h.call(3) - 0.5) * 3.0, -25.0 - h.call(4) * 4.0)
	var clumps := []
	for i in 6:
		var a: float = i * TAU / 6 + h.call(5) * TAU
		clumps.append(top + Vector2(cos(a) * r * 0.55, sin(a) * r * 0.42))
	clumps.append(top)
	for c in clumps:
		draw_circle(c + Vector2(0.5, 1.5), r * 0.58, green.darkened(0.35))
	for c in clumps:
		draw_circle(c + Vector2(-0.6, -0.8), r * 0.48, green)
	for i in 3:
		draw_circle(clumps[i] + Vector2(-1.8, -2.2), r * 0.22, green.lightened(0.14))
