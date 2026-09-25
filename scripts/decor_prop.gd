class_name DecorProp
extends Node2D
## Non-interactive dressing inside a shop or home: plastic chairs, a noodle
## pot, tyres, a fan, a spirit house, litter, a hanging bulb... Origin is the
## bottom of its cell so upright things y-sort with characters.

var data: Dictionary  # {kind, cell, seed}


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed
	match data.kind:
		"chairs":
			_shadow(8)
			draw_rect(Rect2(-6, -8, 12, 2), Color("d84a3a"))  # folding table top
			draw_rect(Rect2(-5, -6, 1, 6), Color("8a8a8a"))
			draw_rect(Rect2(4, -6, 1, 6), Color("8a8a8a"))
			for x in [-9.0, 7.0]:  # red plastic stools
				draw_rect(Rect2(x, -5, 3, 1.5), Color("c83a2e"))
				draw_rect(Rect2(x + 0.5, -3.5, 2, 3.5), Color("a82e24"))
			draw_circle(Vector2(-2, -9), 1.2, Color("e8e2d4"))  # bowls
			draw_circle(Vector2(2, -9), 1.2, Color("e8e2d4"))
		"pot":
			_shadow(6)
			draw_rect(Rect2(-4, -5, 8, 5), Color("5a5a5a"))  # gas ring stand
			draw_rect(Rect2(-5, -11, 10, 6), Color("b8bcc0"))
			draw_rect(Rect2(-5, -11, 10, 1.5), Color("d8dce0"))
			draw_rect(Rect2(-6, -12, 12, 1), Color("8a8e92"))
		"tires":
			_shadow(7)
			for i in 3:
				var y := -2.0 - i * 2.6
				draw_set_transform(Vector2(0, y), 0, Vector2(1, 0.45))
				draw_circle(Vector2.ZERO, 6, Color("1e1e1e"))
				draw_circle(Vector2.ZERO, 3, Color("3a3a3a"))
			draw_set_transform(Vector2.ZERO)
		"bike":
			_shadow(8)
			draw_circle(Vector2(-5, -2.5), 2.5, Color("1a1a1a"))
			draw_line(Vector2(-5, -3), Vector2(3, -7), Color("6a2a24"), 2.0)  # frame on a stand, back wheel off
			draw_rect(Rect2(-3, -9, 6, 1.5), Color("1e1e1e"))
			draw_rect(Rect2(3, -3, 4, 3), Color("7a7a7a"))  # engine block
		"oil":
			draw_set_transform(Vector2(0, -3), 0, Vector2(1.4, 0.5))
			draw_circle(Vector2.ZERO, 5, Color(0.05, 0.05, 0.08, 0.5))
			draw_set_transform(Vector2.ZERO)
		"boxes":
			_shadow(7)
			draw_rect(Rect2(-6, -6, 7, 6), Color("b89a6a"))
			draw_rect(Rect2(0, -5, 6, 5), Color("a88a5a"))
			draw_rect(Rect2(-4, -11, 7, 5), Color("c8aa7a"))
			draw_line(Vector2(-4, -8.5), Vector2(3, -8.5), Color("8a7040"), 0.6)  # tape
		"mattress":
			draw_rect(Rect2(-7, -5, 14, 4), Color("8a9ab0"))
			draw_rect(Rect2(-7, -5, 14, 1), Color("aabacf"))
			draw_rect(Rect2(-6, -6, 4, 2), Color("e8e4dc"))
		"fan":
			_shadow(4)
			draw_line(Vector2(0, 0), Vector2(0, -9), Color("dcdcd4"), 1.2)
			draw_circle(Vector2(0, -12), 3.8, Color("7ab0d0"))
			draw_circle(Vector2(0, -12), 1.2, Color("e8e8e0"))
			draw_rect(Rect2(-3, -1, 6, 1.5), Color("dcdcd4"))
		"tv":
			_shadow(6)
			draw_rect(Rect2(-6, -5, 12, 5), Color("6a4a30"))  # low cabinet
			draw_rect(Rect2(-4.5, -12, 9, 7), Color("2a2a2c"))  # old tube TV
			draw_rect(Rect2(-3.5, -11, 6, 5), Color("3a4450"))
		"shrine":
			# A small spirit house on a post, garlands and a red strawberry soda offering.
			_shadow(4)
			draw_rect(Rect2(-0.8, -8, 1.6, 8), Color("c8a878"))
			draw_rect(Rect2(-4, -13, 8, 5), Color("d8b04a"))
			draw_colored_polygon(PackedVector2Array([Vector2(-5, -13), Vector2(5, -13), Vector2(0, -18)]), Color("c83a2e"))
			draw_circle(Vector2(-2.5, -8), 0.9, Color("f0d060"))
			draw_rect(Rect2(1.5, -9.5, 1.2, 2), Color("e03a4a"))
		"litter":
			for i in 5:
				var p := Vector2(rng.randf_range(-7, 7), rng.randf_range(-6, 0))
				draw_rect(Rect2(p, Vector2(rng.randf_range(1.5, 3), 1.2)), Color.from_hsv(rng.randf(), 0.3, rng.randf_range(0.5, 0.9)))
		"bulb":
			draw_line(Vector2(0, -40), Vector2(0, -24), Color("1e1e1e"), 0.5)  # hanging from the ceiling
			draw_circle(Vector2(0, -23), 1.6, Color("f0e0a0"))


func _shadow(r: float) -> void:
	draw_set_transform(Vector2(0, -0.5), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO)
