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
	# A drawn zone's skytrain: the line cut into short stretches, one piece each.
	var path := world.bts_path
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var n := maxi(1, ceili(a.distance_to(b) / PIECE))
		for k in n:
			_piece(_draw_path_deck.bind(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n)))
	if world.bts_station.x >= 0 and path.size() > 1:
		_piece(_draw_station)
	if not world.circle.is_empty():
		_piece(_draw_skywalk)
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


## A stretch of a drawn zone's skytrain deck, a to b (ground points; drawn
## BTS_H up): four cells wide, two tracks, parapets, the deck's side below.
func _draw_path_deck(node: Node2D, a: Vector2, b: Vector2) -> void:
	var ci := MeshCanvas.new()
	var up := Vector2(0, -World.BTS_H)
	var d := (b - a).normalized()
	var nrm := Vector2(-d.y, d.x)
	var half := 2.0 * World.TILE
	var e := d * 1.0  # (a hair of overlap, so stretches meet without a seam)
	var quad := func(off0: float, off1: float, col: Color, drop := 0.0) -> void:
		ci.draw_colored_polygon(PackedVector2Array([a - e + nrm * off0 + up + Vector2(0, drop), b + e + nrm * off0 + up + Vector2(0, drop),
				b + e + nrm * off1 + up + Vector2(0, drop), a - e + nrm * off1 + up + Vector2(0, drop)]), col)
	quad.call(-half, half, Color("6a6862"), 9.0)  # the side of the deck, seen below its edge
	quad.call(-half, half, Color("8e8b85"))
	for t in [-half + 8, 10.0]:
		quad.call(t, t + 16, Color("5e5a54"))  # ballast beds
		quad.call(t + 3, t + 4.5, Color("b8b8b4"))  # rails
		quad.call(t + 11, t + 12.5, Color("b8b8b4"))
	quad.call(-half, -half + 3, Color("b0ada6"))  # parapets
	quad.call(half - 3, half, Color("b0ada6"))
	ci.commit(node)


## The station over the street: platforms out either side of the tracks and
## a long curved roof.
func _draw_station(node: Node2D) -> void:
	var ci := MeshCanvas.new(node)  # (text needs the node from the start)
	var x: float = world.bts_path[0].x
	var y0: float = world.bts_station.x - World.BTS_H
	var y1: float = world.bts_station.y - World.BTS_H
	var T := World.TILE
	ci.draw_rect(Rect2(x - 5 * T, y0, 10 * T, y1 - y0 + 9), Color("6a6862"))
	ci.draw_rect(Rect2(x - 5 * T, y0, 10 * T, y1 - y0), Color("a8a49c"))  # platforms
	ci.draw_rect(Rect2(x - 5 * T, y0 + 2, 1.5 * T, y1 - y0 - 4), Color("e8d040"))  # yellow line at the edge
	ci.draw_rect(Rect2(x + 3.5 * T, y0 + 2, 1.5 * T, y1 - y0 - 4), Color("e8d040"))
	# The roof, lifted over it all.
	var ry := y0 - 26
	ci.draw_rect(Rect2(x - 5.5 * T, ry, 11 * T, y1 - y0 + 6), Color("5a7a8a"))
	ci.draw_rect(Rect2(x - 5.5 * T, ry, 11 * T, 4), Color("8ab0c0"))
	for k in range(0, int(y1 - y0), 12):
		ci.draw_line(Vector2(x - 5.5 * T, ry + k), Vector2(x + 5.5 * T, ry + k), Color("4a6a7a"), 1.0)
	ci.draw_rect(Rect2(x - 3 * T, ry - 12, 6 * T, 10), Color("2f6e2b"))  # the station's name board
	ci.draw_string(Look.thai_font(), Vector2(x - 3 * T, ry - 4.5), "อนุสาวรีย์ชัยสมรภูมิ", HORIZONTAL_ALIGNMENT_CENTER, 6 * T, 7, Color("f4f4ec"))
	ci.commit()


## The walkway in the air all round the roundabout (to cross it without
## crossing the traffic), with a roof over it.
func _draw_skywalk(node: Node2D) -> void:
	var ci := MeshCanvas.new()
	var c: Vector2 = world.to_pos(world.circle.at)
	var r: float = (world.circle.r - 6) * World.TILE
	var lift := Vector2(0, -World.BTS_H * 0.6)
	var pts := 72
	for i in pts:
		var a0 := TAU * i / pts
		var a1 := TAU * (i + 1) / pts
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var q0 := c + Vector2(cos(a0), sin(a0)) * (r + 26)
		var q1 := c + Vector2(cos(a1), sin(a1)) * (r + 26)
		ci.draw_colored_polygon(PackedVector2Array([p0 + lift + Vector2(0, 6), p1 + lift + Vector2(0, 6), q1 + lift + Vector2(0, 6), q0 + lift + Vector2(0, 6)]), Color("6e6b64"))
		ci.draw_colored_polygon(PackedVector2Array([p0 + lift, p1 + lift, q1 + lift, q0 + lift]), Color("b8b2a4"))
		ci.draw_line(p0 + lift, p1 + lift, Color("8a857a"), 1.5)
		ci.draw_line(q0 + lift, q1 + lift, Color("8a857a"), 1.5)
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
