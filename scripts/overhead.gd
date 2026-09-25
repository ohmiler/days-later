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

	for pair in world.wires:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		for k in 3:
			var sag := a.distance_to(b) * 0.07 + k * 1.6
			var pts := PackedVector2Array()
			for i in 9:
				var t := i / 8.0
				pts.append(a.lerp(b, t) + Vector2(k * 0.8 - 0.8, sag * 4.0 * t * (1.0 - t) - k * 0.6))
			draw_polyline(pts, Color(0.08, 0.08, 0.08, 0.85), 0.6)
