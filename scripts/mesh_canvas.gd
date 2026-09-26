class_name MeshCanvas
extends RefCounted
## Stands in for a CanvasItem while drawing something that doesn't change: takes
## the same draw_rect / draw_line / draw_circle / draw_polygon /
## draw_set_transform... calls, turns them into triangles, and hands them to the
## real node in one go (commit). Drawn shapes look the same and stay sharp at
## any zoom, but the renderer gets one command instead of hundreds; that was
## most of a frame's drawing time (the ground, buildings, street props).
## Text can't be triangles: it goes to the node as it comes, after what was
## drawn before it, so the order things are drawn in still holds.

var points := PackedVector2Array()
var colors := PackedColorArray()
var xf := Transform2D.IDENTITY
var plain := true  # xf is the identity: points go in as they are (most drawing; faster)
var target: CanvasItem  # the node drawn into (it must be in its _draw)


func _init(to: CanvasItem = null) -> void:
	target = to


func draw_set_transform(pos: Vector2, rotation := 0.0, scale := Vector2.ONE) -> void:
	draw_set_transform_matrix(Transform2D(rotation, scale, 0.0, pos))


func draw_set_transform_matrix(m: Transform2D) -> void:
	xf = m
	plain = m == Transform2D.IDENTITY


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	if plain:
		points.append_array([a, b, c])
	else:
		points.append_array([xf * a, xf * b, xf * c])
	colors.append_array([col, col, col])


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	if not plain:
		a = xf * a
		b = xf * b
		c = xf * c
		d = xf * d
	points.append_array(PackedVector2Array([a, b, c, a, c, d]))
	colors.append_array(PackedColorArray([col, col, col, col, col, col]))


func draw_rect(r: Rect2, col: Color, filled := true, width := -1.0) -> void:
	if filled:
		_quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), col)
		return
	# An outline: four strips centred on the edges, as Godot draws one.
	var w := width if width > 0.0 else 1.0
	var h := w * 0.5
	var p := r.position
	var e := r.end
	draw_rect(Rect2(p.x - h, p.y - h, r.size.x + w, w), col)
	draw_rect(Rect2(p.x - h, e.y - h, r.size.x + w, w), col)
	draw_rect(Rect2(p.x - h, p.y + h, w, r.size.y - w), col)
	draw_rect(Rect2(e.x - h, p.y + h, w, r.size.y - w), col)


func draw_line(a: Vector2, b: Vector2, col: Color, width := -1.0, _antialiased := false) -> void:
	var d := b - a
	if d.length_squared() < 0.000001:
		return
	var n := d.orthogonal().normalized() * ((width if width > 0.0 else 1.0) * 0.5)
	_quad(a + n, b + n, b - n, a - n, col)


func draw_polyline(pts: PackedVector2Array, col: Color, width := -1.0, _antialiased := false) -> void:
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], col, width)


func draw_circle(c: Vector2, radius: float, col: Color, filled := true, width := -1.0, _antialiased := false) -> void:
	var sides := clampi(int(radius * 3.0), 10, 48)  # (enough that a big one stays round up close)
	var prev := c + Vector2(radius, 0)
	for i in range(1, sides + 1):
		var p := c + Vector2.from_angle(TAU * i / sides) * radius
		if filled:
			_tri(c, prev, p, col)
		else:
			draw_line(prev, p, col, width)
		prev = p


func draw_arc(c: Vector2, radius: float, a0: float, a1: float, sides: int, col: Color, width := -1.0, _antialiased := false) -> void:
	var prev := c + Vector2.from_angle(a0) * radius
	for i in range(1, sides + 1):
		var p := c + Vector2.from_angle(lerpf(a0, a1, float(i) / sides)) * radius
		draw_line(prev, p, col, width)
		prev = p


func draw_colored_polygon(pts: PackedVector2Array, col: Color, _uvs := PackedVector2Array(), _texture: Texture2D = null) -> void:
	draw_polygon(pts, PackedColorArray([col]))


## A filled polygon; `cols` is one colour for all, or one per point.
func draw_polygon(pts: PackedVector2Array, cols: PackedColorArray, _uvs := PackedVector2Array(), _texture: Texture2D = null) -> void:
	var tris := Geometry2D.triangulate_polygon(pts)
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		if cols.size() >= pts.size():
			points.append(xf * pts[a])
			points.append(xf * pts[b])
			points.append(xf * pts[c])
			colors.append(cols[a])
			colors.append(cols[b])
			colors.append(cols[c])
		else:
			_tri(pts[a], pts[b], pts[c], cols[0])


## Text goes straight to the node, after what came before it.
func draw_string(font: Font, pos: Vector2, text: String, alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0,
		font_size := 16, modulate := Color(1, 1, 1)) -> void:
	_flush(target)
	target.draw_set_transform_matrix(xf)
	target.draw_string(font, pos, text, alignment, width, font_size, modulate)
	target.draw_set_transform_matrix(Transform2D.IDENTITY)


func _flush(ci: CanvasItem) -> void:
	if points.is_empty():
		return
	# (No indices: the points are taken three at a time.)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), points, colors)
	points = PackedVector2Array()
	colors = PackedColorArray()


## Hand everything drawn so far to `ci` (by default the target; call from its
## _draw) and start afresh.
func commit(ci: CanvasItem = null) -> void:
	_flush(ci if ci else target)
	draw_set_transform_matrix(Transform2D.IDENTITY)
