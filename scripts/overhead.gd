class_name Overhead
extends Node2D
## Things above everyone's heads: sagging power lines and the skytrain deck.
##
## Split into pieces a ground chunk wide, each drawing only its own stretch, so
## what is off screen isn't drawn at all (as one piece, the whole city's wiring
## was drawn every frame). Fading this node (see Main) fades every piece.

var world: World

const PIECE := World.CHUNK * World.TILE  # pixels


func _ready() -> void:
	# Each wire goes to the piece its middle lies in.
	var groups := {}
	for n in world.wires.size():
		var mid: Vector2 = (world.wires[n][0] + world.wires[n][1]) * 0.5
		var key := Vector2i(floori(mid.x / PIECE), floori(mid.y / PIECE))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(n)
	# (The deck first: the wires are strung above it.)
	if world.bts_row >= 0:
		var width := World.W * World.TILE
		for x0 in range(0, width, PIECE):
			_piece(_draw_deck.bind(float(x0), float(mini(x0 + PIECE, width))))
	for key in groups:
		_piece(_draw_wires.bind(groups[key]))


func _piece(draw_fn: Callable) -> void:
	var n := Node2D.new()
	n.draw.connect(func(): draw_fn.call(n))
	add_child(n)


## The skytrain deck from x0 to x1: rows bts_row-1 .. bts_row+2, lifted BTS_H above the road.
func _draw_deck(node: Node2D, x0: float, x1: float) -> void:
	var ci := MeshCanvas.new()
	var T := World.TILE
	var top := (world.bts_row - 1) * T - World.BTS_H
	var front := (world.bts_row + 3) * T - World.BTS_H
	var w := x1 - x0
	ci.draw_rect(Rect2(x0, top, w, front - top), Color("8e8b85"))
	for track in [top + 8, top + 34]:
		ci.draw_rect(Rect2(x0, track, w, 16), Color("5e5a54"))  # ballast bed
		for x in range(int(x0), int(x1), 5):
			ci.draw_rect(Rect2(x, track + 1, 2.5, 14), Color("7a7670"))  # sleepers
		ci.draw_rect(Rect2(x0, track + 3, w, 1.5), Color("b8b8b4"))  # rails
		ci.draw_rect(Rect2(x0, track + 11, w, 1.5), Color("b8b8b4"))
	ci.draw_rect(Rect2(x0, top + 27, w, 3), Color("6e6b66"))  # walkway between tracks
	ci.draw_rect(Rect2(x0, top, w, 3), Color("b0ada6"))  # parapet
	ci.draw_rect(Rect2(x0, front, w, 9), Color("6a6862"))
	ci.draw_rect(Rect2(x0, front + 7, w, 2), Color("4e4c48"))
	for x in range(0, int(x1), 160):
		if x >= x0:
			ci.draw_rect(Rect2(x - 0.5, front, 1.0, 9), Color("55534e"))  # segment joints
	ci.commit(node)


## Bangkok's cable spaghetti: power, phone and a dozen internet lines, all sagging differently.
func _draw_wires(node: Node2D, ids: Array) -> void:
	var ci := MeshCanvas.new()  # (thin lines by the hundred: one batch)
	for n: int in ids:
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
			ci.draw_polyline(pts, Color(grey, grey, grey, 0.85), 0.5 if k > 1 else 0.7)
		if n % 4 == 1:
			# A coil of spare cable hanging off the line.
			var m := a.lerp(b, 0.3) + Vector2(0, a.distance_to(b) * 0.04 + 2)
			ci.draw_arc(m + Vector2(0, 3), 2.6, 0, TAU, 10, Color(0.1, 0.1, 0.1, 0.85), 0.6)
			ci.draw_arc(m + Vector2(0.6, 3.4), 2.2, 0, TAU, 10, Color(0.15, 0.15, 0.15, 0.85), 0.5)
	ci.commit(node)
