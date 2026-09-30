class_name CarArt
## A car drawn at any heading (trial: see tests/carlab.gd). The car is a few
## boxes in 3D (the wheels, the body, the cabin with its sloping glass),
## turned to where it faces and drawn the way the city is: the ground as it
## is (16 px a metre), height straight up the screen (16 px a metre). Only
## the faces turned toward you are drawn, lit from above and a little behind.
##
## Local space: x forward, y to the car's right, z up (pixels). The origin is
## the middle of the car on the ground.

## How a sedan is built (pixels: 4.5 m long, 1.8 m wide, 1.45 m high).
const SEDAN := {len = 72.0, wid = 29.0, clear = 3.0, body = 12.0, top = 23.0,
		cabin = [-0.34, 0.16], roof = [-0.24, 0.02], roof_in = 3.0, wheel_r = 5.0, wheels = [0.31, -0.31],
		col = Color("b8302a"), glass = Color("2a3a48"), dark = Color("1a1a1c")}
const COLOURS := [Color("b8302a"), Color("e8e4dc"), Color("2a62a8"), Color("3a3c40"), Color("8a8e94"), Color("c8a040")]


## The sedan in its own colour (from the vehicle's seed).
static func spec_of(v: Dictionary) -> Dictionary:
	var s := SEDAN.duplicate()
	s.col = v.color if v.get("color") is Color else COLOURS[int(v.get("seed", 0)) % COLOURS.size()]
	return s


const LIGHT := Vector3(-0.35, 0.45, 0.82)  # (toward the light, in the world: high up, a little from the left and the front)


## Draw a car `spec` facing `heading` (radians, 0 = east) at `at`.
## `lights`: headlights on.
static func draw(ci: CanvasItem, heading: float, spec: Dictionary, at := Vector2.ZERO, lights := false) -> void:
	var L: float = spec.len
	var W: float = spec.wid
	var h := L * 0.5
	var w := W * 0.5
	var fwd := Vector2.from_angle(heading)
	var right := fwd.orthogonal()  # (+y local: the car's right side)
	# Its shadow on the road.
	var sh := PackedVector2Array()
	for c in [Vector2(h + 1, w + 1), Vector2(h + 1, -w - 1), Vector2(-h - 1, -w - 1), Vector2(-h - 1, w + 1)]:
		sh.append(at + fwd * c.x + right * c.y + Vector2(1.5, 1.5))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.28))
	var proj := func(p: Vector3) -> Vector2:
		return at + fwd * p.x + right * p.y + Vector2(0, -p.z)
	var r: float = spec.wheel_r
	var near_side := 1.0 if right.y >= 0.0 else -1.0  # which side faces the camera
	# The body: a lower box (bumpers darker at each end), with the near
	# wheels drawn over its side as round tyres in the arches.
	var bump := 2.5
	_solid(ci, proj, _box(-h, -h + bump, -w + 1, w - 1, spec.clear, spec.body - 3.0), spec.col.darkened(0.45), null, fwd, right)
	_solid(ci, proj, _box(h - bump, h, -w + 1, w - 1, spec.clear, spec.body - 3.0), spec.col.darkened(0.45), null, fwd, right)
	_solid(ci, proj, _box(-h + bump, h - bump, -w, w, spec.clear, spec.body), spec.col, null, fwd, right)
	var near := right * near_side
	if absf(right.y) > 0.08:  # (end-on, the tyres hide under the body)
		for fx in spec.wheels:
			var c3 := Vector3(fx * L, near_side * (w + 0.3), r)
			var tyre := PackedVector2Array()
			var hub := PackedVector2Array()
			for k in 14:
				var a := TAU * k / 14.0
				var p3 := c3 + Vector3(cos(a) * r, 0, sin(a) * r)
				tyre.append(proj.call(p3))
				hub.append(proj.call(c3 + Vector3(cos(a) * r * 0.45, 0, sin(a) * r * 0.45)))
			ci.draw_colored_polygon(tyre, spec.dark)
			ci.draw_colored_polygon(hub, Color("6a6c70"))
		# The doors' shut lines and handles along the near side.
		for fx in [spec.cabin[1] - 0.02, (spec.cabin[0] + spec.cabin[1]) * 0.5, spec.cabin[0] + 0.02]:
			var a: Vector2 = proj.call(Vector3(fx * L, near_side * w, spec.body - 0.5))
			var b: Vector2 = proj.call(Vector3(fx * L, near_side * w, spec.clear + 2.0))
			ci.draw_line(a, b, spec.col.darkened(0.4), 0.6)
	# The cabin: glass sloping in to the roof.
	var c0: float = spec.cabin[0] * L
	var c1: float = spec.cabin[1] * L
	var r0: float = spec.roof[0] * L
	var r1: float = spec.roof[1] * L
	var ri: float = spec.roof_in
	var cabin := [Vector3(c1, -w + 1, spec.body), Vector3(c1, w - 1, spec.body), Vector3(c0, w - 1, spec.body), Vector3(c0, -w + 1, spec.body),
			Vector3(r1, -w + ri, spec.top), Vector3(r1, w - ri, spec.top), Vector3(r0, w - ri, spec.top), Vector3(r0, -w + ri, spec.top)]
	_solid(ci, proj, cabin, spec.glass, spec.col, fwd, right)
	# The pillars between the windows, and a glint on the glass.
	var pil: Color = spec.col.darkened(0.15)
	for side in [-1.0, 1.0]:
		if (right * side).y <= 0.05:
			continue
		var bm: Vector2 = proj.call(Vector3((c0 + c1) * 0.5, side * (w - 1), spec.body))
		var tm: Vector2 = proj.call(Vector3((r0 + r1) * 0.5, side * (w - ri), spec.top))
		ci.draw_line(bm, tm, pil, 1.6)
	for idx in [[0, 4], [1, 5], [2, 6], [3, 7]]:
		var a3: Vector3 = cabin[idx[0]]
		var b3: Vector3 = cabin[idx[1]]
		ci.draw_line(proj.call(a3), proj.call(b3), pil, 1.4)
	# Lights: two at the front, two at the back, on whichever end you can see.
	for end in [1.0, -1.0]:
		var face_n: Vector2 = fwd * end
		if face_n.y <= 0.02:
			continue  # (that end faces away)
		var col := (Color("fff4c8") if lights else Color("e8e4d0")) if end > 0.0 else Color("c8201c")
		for s in [-1.0, 1.0]:
			var a: Vector2 = proj.call(Vector3(end * (h + 0.2), s * (w - 2.5), spec.body - 3.0))
			var b: Vector2 = proj.call(Vector3(end * (h + 0.2), s * (w - 7.5), spec.body - 3.0))
			ci.draw_line(a, b, col, 2.2)
	if lights:
		var tip: Vector2 = proj.call(Vector3(h, 0, 4))
		ci.draw_colored_polygon(PackedVector2Array([tip + right * 9, tip + fwd * 30 + right * 16, tip + fwd * 30 - right * 16, tip - right * 9]),
				Color(1, 0.95, 0.75, 0.18))


## The 8 corners of a box, bottom four then top four.
static func _box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> Array:
	return [Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0),
			Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(x0, y0, z1)]


## The faces of a 6-sided solid from its 8 corners (bottom 0-3, top 4-7), each
## wound so it runs one way on screen when it faces you.
const FACES := [[4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]


## Draw the faces of a solid that face the camera, each shaded by how it
## faces the light. `top_col`: another colour for the top face (a cabin's roof).
static func _solid(ci: CanvasItem, proj: Callable, corners: Array, col: Color, top_col = null, fwd := Vector2.RIGHT, right := Vector2.DOWN) -> void:
	for f in FACES:
		var pts := PackedVector2Array()
		for i in f:
			pts.append(proj.call(corners[i]))
		if _area(pts) >= -0.01:
			continue  # (turned away from you)
		var a: Vector3 = corners[f[0]]
		var n: Vector3 = (corners[f[1]] - a).cross(corners[f[3]] - a).normalized()
		var mid := Vector3.ZERO
		var fmid := Vector3.ZERO
		for c in corners:
			mid += c / 8.0
		for i in f:
			fmid += corners[i] / 4.0
		if n.dot(fmid - mid) < 0.0:
			n = -n  # (outward)
		var base: Color = top_col if top_col != null and f == FACES[0] else col
		var nw := Vector3(fwd.x * n.x + right.x * n.y, fwd.y * n.x + right.y * n.y, n.z)  # (turned with the car)
		var k := 0.62 + 0.38 * maxf(0.0, nw.dot(LIGHT))
		ci.draw_colored_polygon(pts, Color(base.r * k, base.g * k, base.b * k, base.a))
		pts.append(pts[0])
		ci.draw_polyline(pts, base.darkened(0.55), 0.6)


static func _area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % pts.size()]
		s += p.x * q.y - q.x * p.y
	return s * 0.5
