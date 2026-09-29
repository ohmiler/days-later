class_name Props3D
extends RefCounted
## Street things in 3D, from code: parked vehicles of Bangkok (taxis in their
## colours, pickups, songthaews, buses, the army truck, tuk-tuks, burnt
## wrecks), power poles with their tangle of wires, food carts and stalls,
## bins, spirit houses, bus stops, sandbags, the monument. Each is a few boxes
## and cylinders with vertex colours, added into a chunk's one mesh.
## A model is made in its own space: length along +X (the front at +X), up +Y.


## A box at `c` (model space) of `size`, placed by `xf`.
static func xbox(st: SurfaceTool, xf: Transform3D, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.UP, [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.BACK, [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3.FORWARD, [Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3.RIGHT, [Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)]],
		[Vector3.LEFT, [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
	]
	st.set_color(col)
	for f in faces:
		var q: Array = f[1]
		st.set_normal(xf.basis * f[0])
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(xf * (c + q[i]))


## A cylinder at `c` along `axis` (0 x, 1 y, 2 z), radius `r`, length `len`.
static func xcyl(st: SurfaceTool, xf: Transform3D, c: Vector3, r: float, len: float, axis: int, col: Color, sides := 10, r2 := -1.0) -> void:
	var top := r if r2 < 0.0 else r2
	st.set_color(col)
	var dir := [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis] as Vector3
	var u := [Vector3.UP, Vector3.RIGHT, Vector3.RIGHT][axis] as Vector3
	var v := dir.cross(u)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var n0 := u * cos(a0) + v * sin(a0)
		var n1 := u * cos(a1) + v * sin(a1)
		var b0 := c - dir * len * 0.5 + n0 * r
		var b1 := c - dir * len * 0.5 + n1 * r
		var t0 := c + dir * len * 0.5 + n0 * top
		var t1 := c + dir * len * 0.5 + n1 * top
		for e in [[b0, n0], [t1, n1], [t0, n0], [b0, n0], [b1, n1], [t1, n1]]:
			st.set_normal(xf.basis * e[1])
			st.add_vertex(xf * e[0])
		# The ends.
		for e in [[c + dir * len * 0.5, t0, t1, dir], [c - dir * len * 0.5, b1, b0, -dir]]:
			st.set_normal(xf.basis * e[3])
			for p in [e[0], e[2], e[1]]:
				st.add_vertex(xf * p)


const TAXI := [Color("e0607e"), Color("6ab04a"), Color("e89a2e"), Color("3a7ac8"), Color("d8c83a")]  # pink, green-yellow, orange, blue, yellow
const GLASS := Color("222a32")
const TYRE := Color("1a1a1c")


static func _wheels(st: SurfaceTool, xf: Transform3D, xs: Array, half_w: float, r: float) -> void:
	for x in xs:
		for z in [half_w, -half_w]:
			xcyl(st, xf, Vector3(x, r, z), r, 0.24, 2, TYRE, 12)


static func _lights(st: SurfaceTool, xf: Transform3D, front: float, back: float, y: float, half_w: float) -> void:
	for z in [half_w - 0.2, -half_w + 0.2]:
		xbox(st, xf, Vector3(front, y, z), Vector3(0.04, 0.12, 0.28), Color("f4ecd0"))
		xbox(st, xf, Vector3(back, y, z), Vector3(0.04, 0.12, 0.24), Color("b8201c"))


static func sedan(st: SurfaceTool, xf: Transform3D, col: Color, burnt := false) -> void:
	var body := col if not burnt else Color("3a302a")
	xbox(st, xf, Vector3(0, 0.55, 0), Vector3(4.4, 0.62, 1.76), body)
	xbox(st, xf, Vector3(-0.25, 1.1, 0), Vector3(2.3, 0.52, 1.58), GLASS if not burnt else Color("1e1a18"))
	xbox(st, xf, Vector3(-0.25, 1.38, 0), Vector3(1.9, 0.06, 1.5), body)
	_wheels(st, xf, [1.35, -1.35], 0.8, 0.32)
	if not burnt:
		_lights(st, xf, 2.2, -2.2, 0.62, 0.88)


static func taxi(st: SurfaceTool, xf: Transform3D, seed: int) -> void:
	var col: Color = TAXI[seed % TAXI.size()]
	sedan(st, xf, col)
	xbox(st, xf, Vector3(-0.25, 1.5, 0), Vector3(0.5, 0.18, 0.28), Color("f0e8d0"))  # the TAXI-METER sign


static func pickup(st: SurfaceTool, xf: Transform3D, col: Color) -> void:
	xbox(st, xf, Vector3(0.9, 0.62, 0), Vector3(1.9, 0.7, 1.8), col)  # the front and cab base
	xbox(st, xf, Vector3(0.5, 1.22, 0), Vector3(1.2, 0.55, 1.7), GLASS)
	xbox(st, xf, Vector3(0.5, 1.52, 0), Vector3(1.1, 0.06, 1.6), col)
	xbox(st, xf, Vector3(-1.4, 0.5, 0), Vector3(2.2, 0.35, 1.8), col.darkened(0.15))  # the bed floor
	for z in [0.88, -0.88]:
		xbox(st, xf, Vector3(-1.4, 0.85, z), Vector3(2.2, 0.4, 0.06), col)
	xbox(st, xf, Vector3(-2.47, 0.85, 0), Vector3(0.06, 0.4, 1.8), col)
	_wheels(st, xf, [1.5, -1.5], 0.82, 0.34)
	_lights(st, xf, 1.87, -2.52, 0.7, 0.9)


static func songthaew(st: SurfaceTool, xf: Transform3D) -> void:
	var red := Color("c02a24")
	pickup(st, xf, red)
	# The covered back: a roof on posts, benches along the sides.
	for x in [-0.4, -2.4]:
		for z in [0.86, -0.86]:
			xbox(st, xf, Vector3(x, 1.4, z), Vector3(0.06, 1.2, 0.06), Color("8a8e94"))
	xbox(st, xf, Vector3(-1.4, 2.02, 0), Vector3(2.2, 0.08, 1.9), red)
	for z in [0.6, -0.6]:
		xbox(st, xf, Vector3(-1.4, 0.95, z), Vector3(2.0, 0.08, 0.34), Color("6a4a30"))


static func van(st: SurfaceTool, xf: Transform3D, col: Color) -> void:
	xbox(st, xf, Vector3(0, 1.08, 0), Vector3(5.0, 1.55, 1.86), col)
	xbox(st, xf, Vector3(0.2, 1.45, 0), Vector3(4.2, 0.5, 1.88), GLASS)
	xbox(st, xf, Vector3(2.3, 1.2, 0), Vector3(0.44, 0.9, 1.7), GLASS)
	_wheels(st, xf, [1.6, -1.6], 0.84, 0.33)
	_lights(st, xf, 2.5, -2.5, 0.7, 0.9)


static func bus(st: SurfaceTool, xf: Transform3D, seed: int) -> void:
	var col: Color = [Color("e8d8b0"), Color("d8702a"), Color("3a6aa8")][seed % 3]
	xbox(st, xf, Vector3(0, 1.75, 0), Vector3(11.0, 2.6, 2.5), col)
	xbox(st, xf, Vector3(0, 2.25, 0), Vector3(10.4, 0.9, 2.52), GLASS)
	xbox(st, xf, Vector3(5.49, 1.9, 0), Vector3(0.04, 1.4, 2.2), GLASS)
	xbox(st, xf, Vector3(0, 1.1, 0), Vector3(11.02, 0.2, 2.52), col.darkened(0.35))
	_wheels(st, xf, [3.8, -3.2], 1.12, 0.5)


static func army(st: SurfaceTool, xf: Transform3D) -> void:
	var green := Color("4a5438")
	xbox(st, xf, Vector3(2.5, 1.2, 0), Vector3(1.9, 1.5, 2.3), green)
	xbox(st, xf, Vector3(2.8, 1.75, 0), Vector3(1.0, 0.55, 2.2), GLASS)
	xbox(st, xf, Vector3(-0.9, 0.95, 0), Vector3(4.6, 0.3, 2.4), green.darkened(0.2))
	xbox(st, xf, Vector3(-0.9, 2.0, 0), Vector3(4.6, 1.8, 2.4), Color("5a5a40"))  # the canvas
	_wheels(st, xf, [2.4, -0.4, -2.2], 1.1, 0.52)


static func tuktuk(st: SurfaceTool, xf: Transform3D, seed: int) -> void:
	var col: Color = [Color("3a6aa8"), Color("2a8a4a"), Color("c83a2e")][seed % 3]
	xbox(st, xf, Vector3(0.95, 0.72, 0), Vector3(0.55, 0.9, 0.7), col)  # the driver's front
	xbox(st, xf, Vector3(-0.35, 0.7, 0), Vector3(1.4, 0.6, 1.3), col)  # the seat box behind
	xbox(st, xf, Vector3(-0.35, 1.0, 0), Vector3(1.1, 0.12, 1.2), Color("2a2624"))
	xbox(st, xf, Vector3(0.1, 1.82, 0), Vector3(2.4, 0.08, 1.38), Color("1e2a3a"))  # the canopy
	for x in [1.2, -1.0]:
		for z in [0.65, -0.65]:
			xbox(st, xf, Vector3(x, 1.38, z), Vector3(0.04, 0.9, 0.04), Color("c8c8c8"))
	xcyl(st, xf, Vector3(1.15, 0.27, 0), 0.27, 0.14, 2, TYRE, 10)
	for z in [0.62, -0.62]:
		xcyl(st, xf, Vector3(-0.8, 0.27, z), 0.27, 0.16, 2, TYRE, 10)


## A concrete power pole, with its crossbars and (some) a transformer.
static func pole(st: SurfaceTool, xf: Transform3D, seed: int) -> void:
	xcyl(st, xf, Vector3(0, 4.5, 0), 0.15, 9.0, 1, Color("9a968e"), 8, 0.11)
	for y in [7.6, 8.4]:
		xbox(st, xf, Vector3(0, y, 0), Vector3(0.1, 0.1, 1.6), Color("7a7a78"))
	if seed % 3 == 0:
		xcyl(st, xf, Vector3(0, 6.2, 0.3), 0.3, 0.9, 1, Color("6a7072"), 10)
	# The street lamp arm.
	xbox(st, xf, Vector3(0, 6.8, 0.8), Vector3(0.06, 0.06, 1.6), Color("7a7a78"))
	xbox(st, xf, Vector3(0, 6.72, 1.55), Vector3(0.22, 0.1, 0.4), Color("e8e0c8"))


static func stall(st: SurfaceTool, xf: Transform3D, seed: int) -> void:
	var cloth: Color = [Color("d84a3a"), Color("2a6aa8"), Color("e8b43a"), Color("3a8a5a")][seed % 4]
	xbox(st, xf, Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 1.0), Color("b8a888"))  # the table
	for x in [0.85, -0.85]:
		for z in [0.45, -0.45]:
			xbox(st, xf, Vector3(x, 1.4, z), Vector3(0.04, 1.0, 0.04), Color("8a8e94"))
	xbox(st, xf, Vector3(0, 2.0, 0), Vector3(2.2, 0.06, 1.4), cloth)
	for i in 4:
		xbox(st, xf, Vector3(-0.6 + i * 0.4, 0.98, 0.1 * (i % 2)), Vector3(0.3, 0.14, 0.3), Color.from_hsv(fmod(seed * 0.13 + i * 0.21, 1.0), 0.5, 0.8))


## A food cart: a glass case on wheels, a gas tank, a little umbrella.
static func cart(st: SurfaceTool, xf: Transform3D, seed: int) -> void:
	xbox(st, xf, Vector3(0, 0.6, 0), Vector3(1.4, 0.7, 0.7), Color("c8c0b0"))
	xbox(st, xf, Vector3(0.1, 1.15, 0), Vector3(1.0, 0.4, 0.6), Color(0.7, 0.8, 0.85))
	xcyl(st, xf, Vector3(-0.55, 0.3, 0), 0.14, 0.45, 1, Color("c83a2e"), 8)  # the gas tank
	for z in [0.36, -0.36]:
		xcyl(st, xf, Vector3(0.3, 0.2, z), 0.2, 0.06, 2, TYRE, 10)
	xbox(st, xf, Vector3(0, 1.8, 0), Vector3(0.03, 1.2, 0.03), Color("8a8e94"))
	xcyl(st, xf, Vector3(0, 2.35, 0), 0.9, 0.12, 1, [Color("e8b43a"), Color("d84a3a"), Color("3a6aa8")][seed % 3], 10, 0.05)


static func spirit_house(st: SurfaceTool, xf: Transform3D) -> void:
	var gold := Color("d8b050")
	xcyl(st, xf, Vector3(0, 0.6, 0), 0.12, 1.2, 1, Color("e8e0d0"), 8)
	xbox(st, xf, Vector3(0, 1.25, 0), Vector3(0.8, 0.1, 0.8), Color("e8e0d0"))
	xbox(st, xf, Vector3(0, 1.55, 0), Vector3(0.5, 0.5, 0.5), gold)
	xcyl(st, xf, Vector3(0, 2.0, 0), 0.4, 0.45, 1, Color("b8302a"), 4, 0.02)  # the roof
	for i in 3:
		xbox(st, xf, Vector3(0.3, 1.34, -0.2 + i * 0.2), Vector3(0.06, 0.08, 0.06), Color.from_hsv(i * 0.3, 0.6, 0.9))  # garlands, drinks


static func bus_stop(st: SurfaceTool, xf: Transform3D) -> void:
	for x in [1.8, -1.8]:
		xbox(st, xf, Vector3(x, 1.25, -0.6), Vector3(0.08, 2.5, 0.08), Color("8a8e94"))
	xbox(st, xf, Vector3(0, 2.55, 0), Vector3(4.0, 0.1, 1.6), Color("3a6aa8"))
	xbox(st, xf, Vector3(0, 0.45, -0.5), Vector3(3.2, 0.06, 0.4), Color("a8a49c"))
	xbox(st, xf, Vector3(0, 1.3, -0.72), Vector3(3.6, 1.6, 0.04), Color(0.6, 0.7, 0.75))


static func sandbags(st: SurfaceTool, xf: Transform3D) -> void:
	for row in 3:
		for i in 4:
			xbox(st, xf, Vector3(-0.75 + i * 0.5 + (0.25 if row % 2 else 0.0), 0.12 + row * 0.2, 0), Vector3(0.46, 0.2, 0.4), Color("a89a70").darkened(0.05 * (i % 2)))


## The Victory Monument: a stepped base and five bayonets round an obelisk.
static func monument(st: SurfaceTool, xf: Transform3D) -> void:
	var stone := Color("c8c0b0")
	xbox(st, xf, Vector3(0, 1.0, 0), Vector3(14, 2.0, 14), stone.darkened(0.1))
	xbox(st, xf, Vector3(0, 3.0, 0), Vector3(9, 2.0, 9), stone)
	xcyl(st, xf, Vector3(0, 22.0, 0), 1.6, 36.0, 1, stone, 5, 0.3)
	for i in 5:
		var a := TAU * i / 5.0
		xcyl(st, xf, Vector3(cos(a) * 2.6, 17.0, sin(a) * 2.6), 0.9, 26.0, 1, stone.lightened(0.05), 4, 0.05)


## Everything else: a box (bins, bags, luggage, debris...).
static func plain(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	xbox(st, xf, Vector3(0, size.y * 0.5, 0), size, col)


## Build the thing `sp` (a World.street_props record) at `xf` (the ground under it, turned).
static func build(st: SurfaceTool, xf: Transform3D, sp: Dictionary, size: Vector3, col: Color) -> void:
	var seed: int = sp.get("seed", 0)
	match sp.kind:
		"car": sedan(st, xf, sp.get("color", col))
		"wreck": sedan(st, xf, col, true)
		"taxi": taxi(st, xf, seed)
		"pickup": pickup(st, xf, sp.get("color", col))
		"van": van(st, xf, sp.get("color", Color("e8e4dc")))
		"songthaew": songthaew(st, xf)
		"bus": bus(st, xf, seed)
		"army": army(st, xf)
		"tuktuk": tuktuk(st, xf, seed)
		"pole": pole(st, xf, seed)
		"stall": stall(st, xf, seed)
		"cart": cart(st, xf, seed)
		"spirit": spirit_house(st, xf)
		"busstop": bus_stop(st, xf)
		"sandbags": sandbags(st, xf)
		"monument": monument(st, xf)
		"bin": xcyl(st, xf, Vector3(0, 0.45, 0), 0.3, 0.9, 1, Color("2a6a3a"), 10)
		"trash":
			for i in 3:
				xcyl(st, xf, Vector3(-0.25 + i * 0.25, 0.25, 0.1 * (i % 2)), 0.22, 0.5, 1, Color("1e1e20"), 7, 0.12)
		_: plain(st, xf, size, col)
