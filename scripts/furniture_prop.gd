class_name FurnitureProp
extends Node2D
## A searchable piece of furniture inside a building. Origin is the bottom of
## its cell so it y-sorts with characters. Looks emptier once searched.

var data: Dictionary  # {id, kind, cell, table}
var searched := false
var highlight := false


func set_searched(v: bool) -> void:
	searched = v
	queue_redraw()


func set_highlight(v: bool) -> void:
	if highlight != v:
		highlight = v
		queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = data.id * 7919
	draw_set_transform(Vector2(0, -1), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 8, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	match data.kind:
		"shelf":
			_box(Rect2(-7, -20, 14, 20), Color("8a8e92"))
			for row in 3:
				var y := -18.0 + row * 6.0
				draw_rect(Rect2(-6, y + 4, 12, 1), Color("5a5e62"))
				var n := 1 if searched else 4
				for i in n:
					if rng.randf() < 0.8:
						draw_rect(Rect2(-5.5 + i * 2.8 + rng.randf(), y + 1, 2.2, 3), Color.from_hsv(rng.randf(), 0.5, 0.75))
		"fridge":
			_box(Rect2(-7, -21, 14, 21), Color("d8dcdc"))
			draw_rect(Rect2(-5.5, -19, 11, 15), Color(0.6, 0.8, 0.85, 0.8) if not searched else Color("5a6a6e"))
			if not searched:
				for i in 4:
					draw_rect(Rect2(-4.5 + i * 2.6, -12, 1.6, 5), Color.from_hsv(rng.randf(), 0.6, 0.8))
			draw_rect(Rect2(-7, -4, 14, 4), Color("3a6ac8"))
		"counter":
			_box(Rect2(-8, -10, 16, 10), Color("7a5a3e"))
			draw_rect(Rect2(-8, -11, 16, 2), Color("b8a888"))
			draw_rect(Rect2(1, -15, 5, 4), Color("2e2e30"))  # cash register
			draw_rect(Rect2(1.5, -14.5, 4, 1.5), Color("6ac86a"))
			if searched:
				draw_rect(Rect2(-7, -7, 7, 3), Color("3a2a1e"))  # drawer pulled out
		"cabinet":
			_box(Rect2(-7, -13, 14, 13), Color("8a6a48"))
			for i in 2:
				var y := -12.0 + i * 6.0
				draw_rect(Rect2(-6, y, 12, 5), Color("7a5a3a"))
				draw_rect(Rect2(-1, y + 2, 2, 1), Color("c8b070"))
			if searched:
				draw_rect(Rect2(-6, -8, 12, 3), Color("3a2a1a"))
		"table":
			draw_rect(Rect2(-7, -8, 14, 2), Color("9a7a5a"))
			draw_rect(Rect2(-6, -6, 1.5, 6), Color("6a4a30"))
			draw_rect(Rect2(4.5, -6, 1.5, 6), Color("6a4a30"))
			if not searched:
				draw_circle(Vector2(-2, -9), 1.6, Color("e8e2d4"))
				draw_rect(Rect2(1, -10.5, 3, 2.5), Color.from_hsv(rng.randf(), 0.5, 0.7))
		"crate":
			_box(Rect2(-7, -9, 14, 9), Color("a8885a"))
			draw_line(Vector2(-7, -9), Vector2(7, 0), Color("7a603c"), 1.0)
			draw_line(Vector2(7, -9), Vector2(-7, 0), Color("7a603c"), 1.0)
			if searched:
				draw_rect(Rect2(-7, -11, 14, 2), Color("7a603c"))  # lid knocked off
		"bed":
			draw_rect(Rect2(-8, -6, 16, 6), Color("6a4a30"))
			draw_rect(Rect2(-7.5, -8, 15, 4), Color("d8d0c0") if not searched else Color("b8a890"))
			draw_rect(Rect2(-7, -8.5, 4, 2.5), Color("f0ece4"))  # pillow
	if highlight and not searched:
		var r := Rect2(-9, -23, 18, 24)
		draw_rect(r, Color(1, 0.9, 0.5, 0.8), false, 0.8)


## Box with a lit top edge and a darker right side.
func _box(r: Rect2, col: Color) -> void:
	draw_rect(r, col)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1.5)), col.lightened(0.2))
	draw_rect(Rect2(r.end.x - 2, r.position.y, 2, r.size.y), col.darkened(0.2))
	if searched:
		draw_rect(r, Color(0, 0, 0, 0.12))
