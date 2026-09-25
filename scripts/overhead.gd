class_name Overhead
extends Node2D
## Things above everyone's heads: sagging power lines and the skytrain deck.

var world: World


func _draw() -> void:
	var T := World.TILE
	if world.bts_row >= 0:
		# Deck spans rows bts_row-1 .. bts_row+2, lifted BTS_H above the road.
		var top := (world.bts_row - 1) * T - World.BTS_H
		var front := (world.bts_row + 3) * T - World.BTS_H
		var width := World.W * T
		draw_rect(Rect2(0, top, width, front - top), Color("8e8b85"))
		for track in [top + 8, top + 34]:
			draw_rect(Rect2(0, track, width, 16), Color("5e5a54"))  # ballast bed
			for x in range(0, int(width), 5):
				draw_rect(Rect2(x, track + 1, 2.5, 14), Color("7a7670"))  # sleepers
			draw_rect(Rect2(0, track + 3, width, 1.5), Color("b8b8b4"))  # rails
			draw_rect(Rect2(0, track + 11, width, 1.5), Color("b8b8b4"))
		draw_rect(Rect2(0, top + 27, width, 3), Color("6e6b66"))  # walkway between tracks
		draw_rect(Rect2(0, top, width, 3), Color("b0ada6"))  # parapet
		draw_rect(Rect2(0, front, width, 9), Color("6a6862"))
		draw_rect(Rect2(0, front + 7, width, 2), Color("4e4c48"))
		for x in range(0, int(width), 160):
			draw_line(Vector2(x, front), Vector2(x, front + 9), Color("55534e"), 1.0)  # segment joints

	# Bangkok's cable spaghetti: power, phone and a dozen internet lines, all sagging differently.
	for n in world.wires.size():
		var a: Vector2 = world.wires[n][0]
		var b: Vector2 = world.wires[n][1]
		var lines := 4 + n % 3
		for k in lines:
			var sag := a.distance_to(b) * (0.05 + World.hash01(n, k, 50) * 0.06) + k * 1.2
			var pts := PackedVector2Array()
			for i in 11:
				var t := i / 10.0
				pts.append(a.lerp(b, t) + Vector2(k * 0.6 - 1.0, sag * 4.0 * t * (1.0 - t) - k * 0.5))
			var grey := 0.06 + World.hash01(n, k, 51) * 0.12
			draw_polyline(pts, Color(grey, grey, grey, 0.85), 0.5 if k > 1 else 0.7)
		if n % 4 == 1:
			# A coil of spare cable hanging off the line.
			var m := a.lerp(b, 0.3) + Vector2(0, a.distance_to(b) * 0.04 + 2)
			draw_arc(m + Vector2(0, 3), 2.6, 0, TAU, 10, Color(0.1, 0.1, 0.1, 0.85), 0.6)
			draw_arc(m + Vector2(0.6, 3.4), 2.2, 0, TAU, 10, Color(0.15, 0.15, 0.15, 0.85), 0.5)
