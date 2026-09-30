class_name Temple3D
extends RefCounted
## A Thai temple's buildings in 3D, from code (the refugee camp is in one):
## the ordination hall (ubosot) with its tiered roof, gold finials (chofa)
## and white walls on a raised base; the bell-shaped chedi; open salas.
## The rect is the building's cells (a cell is a metre); built into `st`.

const ROOF := Color("c8501e")  # glazed orange tiles
const ROOF_EDGE := Color("2a7a4a")  # green tile border
const GOLD := Color("d8a838")
const WHITE := Color("ece6da")
const BASE := Color("d8d0c0")


## A gabled roof: a triangular prism along X from x0 to x1, eaves `w` wide
## (along Z) at height y, peak `h` above.
static func gable(st: SurfaceTool, c: Vector3, len: float, w: float, h: float, col: Color) -> void:
	var hw := w * 0.5
	var hl := len * 0.5
	var l0 := c + Vector3(-hl, 0, -hw)
	var l1 := c + Vector3(hl, 0, -hw)
	var r0 := c + Vector3(-hl, 0, hw)
	var r1 := c + Vector3(hl, 0, hw)
	var p0 := c + Vector3(-hl, h, 0)
	var p1 := c + Vector3(hl, h, 0)
	st.set_color(col)
	var nb := Vector3(0, hw, -h).normalized()
	var nf := Vector3(0, hw, h).normalized()
	for tri in [[l0, l1, p1, nb], [l0, p1, p0, nb], [r0, p1, r1, nf], [r0, p0, p1, nf]]:
		st.set_normal(tri[3])
		for v in [tri[0], tri[1], tri[2]]:
			st.add_vertex(v)
	# The gable ends (triangles), a shade darker.
	st.set_color(col.darkened(0.25))
	for e in [[l0, p0, r0, Vector3.LEFT], [l1, r1, p1, Vector3.RIGHT]]:
		st.set_normal(e[3])
		for v in [e[0], e[1], e[2]]:
			st.add_vertex(v)


## The ordination hall: base, walls with gold-framed windows, three roof
## tiers stepping up and in, green borders, a chofa at each gable peak.
static func ubosot(st: SurfaceTool, r: Rect2i) -> void:
	var xf := Transform3D.IDENTITY
	var c := Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
	var L := float(r.size.x)
	var W := float(r.size.y)
	Props3D.xbox(st, xf, c + Vector3(0, 0.45, 0), Vector3(L, 0.9, W), BASE)
	Props3D.xbox(st, xf, c + Vector3(0, 0.95, W * 0.5 + 0.6), Vector3(3.0, 0.1, 1.2), BASE.darkened(0.08))  # the steps
	Props3D.xbox(st, xf, c + Vector3(0, 3.3, 0), Vector3(L - 1.6, 4.8, W - 2.0), WHITE)
	for i in 4:
		var x := -L * 0.5 + 2.2 + i * (L - 4.4) / 3.0
		for side in [-1.0, 1.0]:
			Props3D.xbox(st, xf, c + Vector3(x, 3.4, side * (W * 0.5 - 0.98)), Vector3(0.9, 1.7, 0.06), Color("5a2a1a"))
			Props3D.xbox(st, xf, c + Vector3(x, 4.35, side * (W * 0.5 - 0.96)), Vector3(1.1, 0.25, 0.08), GOLD)
	Props3D.xbox(st, xf, c + Vector3(0, 2.6, W * 0.5 - 0.98), Vector3(1.4, 2.8, 0.06), Color("7a2a1a"))  # the door
	# Pillars round the hall under the eaves.
	for i in 6:
		var x := -L * 0.5 + 0.4 + i * (L - 0.8) / 5.0
		for side in [-1.0, 1.0]:
			Props3D.xcyl(st, xf, c + Vector3(x, 3.3, side * (W * 0.5 - 0.4)), 0.18, 4.8, 1, WHITE, 8)
	# The roof: tiers, each shorter and higher, with its green border.
	var y := 5.7
	for t in 3:
		var len_ := L + 1.2 - t * 2.4
		var wid := W + 1.4 - t * 1.6
		var hh := 2.6 - t * 0.2
		gable(st, c + Vector3(0, y, 0), len_, wid, hh, ROOF)
		gable(st, c + Vector3(0, y - 0.12, 0), len_ + 0.2, wid + 0.25, hh + 0.08, ROOF_EDGE)
		y += 0.9
	# Chofa: the gold horns at the peaks, and gold along the ridge.
	var peak := 5.7 + 1.8 + 2.2
	for side in [-1.0, 1.0]:
		var at := c + Vector3(side * (L * 0.5 - 1.8), peak, 0)
		Props3D.xbox(st, xf, at + Vector3(side * 0.2, 0.5, 0), Vector3(0.18, 1.1, 0.18), GOLD)
		Props3D.xbox(st, Transform3D(Basis(Vector3.BACK, -side * 0.7), at + Vector3(side * 0.45, 1.1, 0)), Vector3.ZERO, Vector3(0.14, 0.6, 0.14), GOLD)
	Props3D.xbox(st, xf, c + Vector3(0, peak - 0.05, 0), Vector3(L - 3.6, 0.12, 0.2), GOLD)


## The chedi: square steps, a round base, the bell, rings, then a gold spire.
static func chedi(st: SurfaceTool, r: Rect2i) -> void:
	var xf := Transform3D.IDENTITY
	var c := Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
	var s := float(mini(r.size.x, r.size.y))
	for i in 3:
		Props3D.xbox(st, xf, c + Vector3(0, 0.4 + i * 0.8, 0), Vector3(s - i * 0.8, 0.8, s - i * 0.8), WHITE.darkened(0.04 * i))
	Props3D.xcyl(st, xf, c + Vector3(0, 2.9, 0), s * 0.36, 0.6, 1, WHITE, 16)
	Props3D.xblob(st, xf, c + Vector3(0, 4.4, 0), Vector3(s * 0.62, 3.4, s * 0.62), WHITE, 16, 8)  # the bell
	Props3D.xbox(st, xf, c + Vector3(0, 6.3, 0), Vector3(1.2, 0.6, 1.2), WHITE)
	for i in 6:
		Props3D.xcyl(st, xf, c + Vector3(0, 6.8 + i * 0.45, 0), 0.5 - i * 0.06, 0.35, 1, GOLD, 12, 0.46 - i * 0.06)
	Props3D.xcyl(st, xf, c + Vector3(0, 11.0, 0), 0.14, 3.2, 1, GOLD, 8, 0.01)


## A sala: an open pavilion, a raised floor, posts and an orange gabled roof.
static func sala(st: SurfaceTool, r: Rect2i) -> void:
	var xf := Transform3D.IDENTITY
	var c := Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
	var L := float(r.size.x)
	var W := float(r.size.y)
	Props3D.xbox(st, xf, c + Vector3(0, 0.25, 0), Vector3(L, 0.5, W), BASE)
	for i in 4:
		var x := -L * 0.5 + 0.4 + i * (L - 0.8) / 3.0
		for side in [-1.0, 1.0]:
			Props3D.xbox(st, xf, c + Vector3(x, 1.9, side * (W * 0.5 - 0.35)), Vector3(0.22, 2.8, 0.22), Color("8a5a3a"))
	gable(st, c + Vector3(0, 3.3, 0), L + 1.0, W + 1.2, 1.9, ROOF)
	gable(st, c + Vector3(0, 3.2, 0), L + 1.2, W + 1.45, 1.95, ROOF_EDGE)
	# Mats and bundles of people sheltering there.
	for i in 3:
		Props3D.xbox(st, xf, c + Vector3(-L * 0.3 + i * L * 0.3, 0.52, 0.3 * (i % 2)), Vector3(1.6, 0.04, 0.9), Color.from_hsv(0.08 + i * 0.3, 0.4, 0.7))
		Props3D.xbox(st, xf, c + Vector3(-L * 0.3 + i * L * 0.3 + 0.5, 0.7, -0.5), Vector3(0.5, 0.35, 0.4), Color.from_hsv(0.6 - i * 0.2, 0.35, 0.55))


## Tents pitched in the camp grounds, in rows (for the look of it; they
## hold nothing).
static func tent(st: SurfaceTool, at: Vector3, seed: int) -> void:
	var col: Color = [Color("3a6aa8"), Color("4a7a4a"), Color("c8b060"), Color("7a6a5a")][seed % 4]
	gable(st, at + Vector3(0, 0, 0), 2.4, 2.2, 1.5, col)
	Props3D.xbox(st, Transform3D.IDENTITY, at + Vector3(1.21, 0.5, 0), Vector3(0.02, 1.0, 0.6), col.darkened(0.4))
