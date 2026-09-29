extends RefCounted
## A person made entirely in code, for the 3D move (ROADMAP "ย้ายเป็น 3D",
## step 0): a skeleton, one skinned body lofted along the bones, clothes lofted
## over the same body (so they always fit) and a simple face. Metres, Y up,
## facing +Z. build() returns a Skeleton3D ready to pose (see Pose).

const RING_STEP := 0.022  # metres between rings along a limb
const SEGS := 16  # points around a ring

const CLOTH := preload("res://tests/look3d/cloth.gdshader")

var p := {}  # build parameters (see DEFAULTS)
var skel: Skeleton3D
var bones := {}  # name -> bone index
var k := 1.0  # height / 1.70

const DEFAULTS := {
	height = 1.70, girth = 1.0, female = false, fat = 0.0,
	skin = Color("c8906a"), hair = Color("1a1614"), hair_style = "short",
	shirt = {kind = "tee", col = Color("3a6aa8"), col2 = Color("e8e4dc"), pattern = 0},
	pants = {kind = "long", col = Color("2a3a5a")},
	shoes = Color("2a2622"), vest = null,
	zombie = false, grime = 0.0, blood = 0.0, torn = 0.0, seed = 1,
}


func build(params: Dictionary) -> Skeleton3D:
	p = DEFAULTS.duplicate()
	p.merge(params, true)
	k = p.height / 1.70
	skel = Skeleton3D.new()
	_bones()
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body(body)
	var mesh := ArrayMesh.new()
	body.commit(mesh)
	mesh.surface_set_material(0, _skin_mat())
	for part in _clothes():
		var st: SurfaceTool = part[0]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
	for extra in _face():
		var st: SurfaceTool = extra[0]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, extra[1])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	return skel


# --- Skeleton -----------------------------------------------------------------

## Joint positions at rest (skeleton space), scaled by height and build.
func _j(name: String) -> Vector3:
	var f: bool = p.female
	var sh: float = (0.152 if f else 0.168) * p.girth
	var hip: float = (0.09 if f else 0.084) * p.girth
	var at := {
		hips = Vector3(0, 0.93, 0), spine = Vector3(0, 1.08, 0), chest = Vector3(0, 1.26, 0),
		neck = Vector3(0, 1.43, 0), head = Vector3(0, 1.53, 0),
		upperarm = Vector3(sh, 1.385, 0), forearm = Vector3(sh + 0.03, 1.11, -0.01), hand = Vector3(sh + 0.05, 0.86, 0.0),
		fing1 = Vector3(sh + 0.05, 0.775, 0.0), fing2 = Vector3(sh + 0.05, 0.73, 0.0), thumb = Vector3(sh + 0.04, 0.835, 0.03),
		thigh = Vector3(hip, 0.91, 0), shin = Vector3(hip + 0.004, 0.49, 0.0), foot = Vector3(hip + 0.008, 0.085, -0.01),
	}
	var side := 1.0
	var base := name
	if name.ends_with("_l"):
		base = name.trim_suffix("_l")
	elif name.ends_with("_r"):
		base = name.trim_suffix("_r")
		side = -1.0
	var v: Vector3 = at[base]
	return Vector3(v.x * side, v.y * k, v.z)


func _bones() -> void:
	var order := [["hips", ""], ["spine", "hips"], ["chest", "spine"], ["neck", "chest"], ["head", "neck"]]
	for s in ["_l", "_r"]:
		order += [["upperarm" + s, "chest"], ["forearm" + s, "upperarm" + s], ["hand" + s, "forearm" + s],
				["fing1" + s, "hand" + s], ["fing2" + s, "fing1" + s], ["thumb" + s, "hand" + s],
				["thigh" + s, "hips"], ["shin" + s, "thigh" + s], ["foot" + s, "shin" + s]]
	for b in order:
		var i := skel.get_bone_count()
		skel.add_bone(b[0])
		bones[b[0]] = i
		var local := _j(b[0])
		if b[1] != "":
			skel.set_bone_parent(i, bones[b[1]])
			local -= _j(b[1])
		skel.set_bone_rest(i, Transform3D(Basis(), local))
		skel.set_bone_pose(i, Transform3D(Basis(), local))


# --- Lofting ------------------------------------------------------------------

## A tube along `pts` ([[position, bone name], ...]). `prof(t, y)` gives the
## cross-section (Vector3: half-width, half-depth, push forward) at a share `t`
## of the length (y: the height there). Only from s0 to s1 of the length;
## `inflate` grows it (clothes); `cap0/cap1` round the ends; `keep(pos)` may drop
## triangles (hair, holes); `sq` > 2 makes the section boxier.
func loft(st: SurfaceTool, pts: Array, prof: Callable, s0 := 0.0, s1 := 1.0, inflate := 0.0,
		cap0 := true, cap1 := true, ref := Vector3(0, 0, 1), sq := 2.0, keep := Callable()) -> void:
	var lens := [0.0]
	for i in range(1, pts.size()):
		lens.append(lens[i - 1] + (pts[i][0] as Vector3).distance_to(pts[i - 1][0]))
	var total: float = lens[-1]
	var a := s0 * total
	var b := s1 * total
	var n := maxi(9, int((b - a) / RING_STEP) + 1)
	var rings := []
	for r in n:
		var s := lerpf(a, b, float(r) / (n - 1))
		rings.append(_ring(pts, lens, total, s, prof, inflate, ref))
	# Rounded ends: a few rings closing in.
	if cap1:
		rings.append_array(_cap(rings[-1], 1.0))
	if cap0:
		var c := _cap(rings[0], -1.0)
		c.reverse()
		rings = c + rings
	for r in range(rings.size() - 1):
		var r0: Dictionary = rings[r]
		var r1: Dictionary = rings[r + 1]
		for i in SEGS:
			var j := (i + 1) % SEGS
			_tri(st, r0, i, r1, i, r1, j, keep)
			_tri(st, r0, i, r1, j, r0, j, keep)


func _at(pts: Array, lens: Array, s: float) -> Array:
	var i := 0
	while i < pts.size() - 2 and s > lens[i + 1]:
		i += 1
	var f := clampf((s - lens[i]) / maxf(lens[i + 1] - lens[i], 0.00001), 0.0, 1.0)
	return [(pts[i][0] as Vector3).lerp(pts[i + 1][0], f), pts[i][1], pts[i + 1][1], smoothstep(0.0, 1.0, f)]


func _ring(pts: Array, lens: Array, total: float, s: float, prof: Callable, inflate: float, ref: Vector3) -> Dictionary:
	var here := _at(pts, lens, s)
	var c: Vector3 = here[0]
	var d: Vector3 = (_at(pts, lens, minf(s + 0.03, total))[0] - _at(pts, lens, maxf(s - 0.03, 0.0))[0]).normalized()
	var side := ref.cross(d)
	if side.length() < 0.2:
		side = Vector3.UP.cross(d)
	side = side.normalized()
	var front := d.cross(side).normalized()
	if front.dot(ref) < 0.0 and absf(d.y) > 0.7:
		front = -front
	var sec: Vector3 = prof.call(s / maxf(total, 0.0001), c.y / k)
	var rx: float = sec.x * p.girth + inflate
	var rz: float = sec.y * p.girth + inflate
	c += front * sec.z
	var w := {}
	w[here[1]] = 1.0 - here[3]
	w[here[2]] = w.get(here[2], 0.0) + here[3]
	return {c = c, side = side, front = front, d = d, rx = rx, rz = rz, w = w, v = s}


func _cap(r: Dictionary, dir: float) -> Array:
	var out := []
	var reach := minf(r.rx, r.rz) * 0.9
	for step in [0.45, 0.75, 0.93, 1.0]:
		var ang: float = step * PI * 0.5
		var q := r.duplicate()
		q.c = r.c + r.d * dir * sin(ang) * reach
		q.rx = r.rx * cos(ang) + 0.0005
		q.rz = r.rz * cos(ang) + 0.0005
		out.append(q)
	return out


func _point(r: Dictionary, i: int, sq := 2.0) -> Array:
	var th := TAU * i / SEGS
	var cx := cos(th)
	var sz := sin(th)
	var ex := 2.0 / sq
	var x := signf(cx) * pow(absf(cx), ex)
	var z := signf(sz) * pow(absf(sz), ex)
	var pos: Vector3 = r.c + r.side * x * r.rx + r.front * z * r.rz
	var nrm: Vector3 = (r.side * cx / maxf(r.rx, 0.001) + r.front * sz / maxf(r.rz, 0.001)).normalized()
	return [pos, nrm, Vector2(float(i) / SEGS, r.v)]


func _tri(st: SurfaceTool, ra: Dictionary, ia: int, rb: Dictionary, ib: int, rc: Dictionary, ic: int, keep: Callable) -> void:
	var a := _point(ra, ia)
	var b := _point(rb, ib)
	var c := _point(rc, ic)
	if keep.is_valid() and not keep.call((a[0] + b[0] + c[0]) / 3.0):
		return
	var out: Vector3 = a[1] + b[1] + c[1]
	var face: Vector3 = (b[0] - a[0]).cross(c[0] - a[0])
	var list := [[a, ra], [b, rb], [c, rc]]
	if face.dot(out) > 0.0:  # Godot's front faces wind clockwise seen from outside
		list = [[a, ra], [c, rc], [b, rb]]
	for e in list:
		var v: Array = e[0]
		var r: Dictionary = e[1]
		var bi := PackedInt32Array([0, 0, 0, 0])
		var bw := PackedFloat32Array([0, 0, 0, 0])
		var n := 0
		for name in r.w:
			if n < 4 and r.w[name] > 0.0:
				bi[n] = bones[name]
				bw[n] = r.w[name]
				n += 1
		st.set_bones(bi)
		st.set_weights(bw)
		st.set_normal(v[1])
		st.set_uv(v[2])
		st.add_vertex(v[0])


# --- The body -----------------------------------------------------------------

## A table of cross-sections by height: [[y, half-width, half-depth, forward], ...].
static func _table(rows: Array, y: float) -> Vector3:
	if y <= rows[0][0]:
		return Vector3(rows[0][1], rows[0][2], rows[0][3])
	for i in range(rows.size() - 1):
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		if y <= b[0]:
			var f := smoothstep(0.0, 1.0, (y - a[0]) / (b[0] - a[0]))
			return Vector3(lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f))
	var l: Array = rows[-1]
	return Vector3(l[1], l[2], l[3])


func _torso_rows() -> Array:
	var f: bool = p.female
	var fat: float = p.fat
	return [
		[0.78, 0.11, 0.09, 0.0],
		[0.86, 0.175 if f else 0.165, 0.112, -0.008],
		[0.95, 0.172 if f else 0.158, 0.106 + fat * 0.05, 0.0 + fat * 0.03],
		[1.05, (0.122 if f else 0.142) + fat * 0.06, 0.098 + fat * 0.08, 0.008 + fat * 0.06],
		[1.17, (0.138 if f else 0.158) + fat * 0.04, (0.108 if f else 0.108) + fat * 0.06, 0.012 + fat * 0.04],
		[1.27, (0.152 if f else 0.172) + fat * 0.02, (0.128 if f else 0.116) + fat * 0.03, (0.03 if f else 0.016)],
		[1.34, 0.152 if f else 0.172, 0.105, 0.005],
		[1.39, 0.132 if f else 0.148, 0.09, -0.004],
		[1.43, 0.085 if f else 0.095, 0.066, -0.006],
		[1.46, 0.052, 0.048, 0.0],
	]


func _torso_pts() -> Array:
	return [[Vector3(0, 0.77 * k, 0), "hips"], [Vector3(0, 0.95 * k, 0), "hips"], [Vector3(0, 1.08 * k, 0), "spine"],
			[Vector3(0, 1.25 * k, 0), "chest"], [Vector3(0, 1.40 * k, 0), "chest"], [Vector3(0, 1.45 * k, 0), "neck"]]


func _arm_pts(s: String) -> Array:
	var ua := _j("upperarm" + s)
	var fa := _j("forearm" + s)
	var h := _j("hand" + s)
	return [[ua + Vector3(-0.012 * signf(ua.x), -0.022, 0), "upperarm" + s], [fa.lerp(ua, 0.12), "upperarm" + s], [fa.lerp(h, 0.1), "forearm" + s],
			[h.lerp(fa, 0.06), "forearm" + s], [h, "hand" + s]]


func _arm_prof(t: float, _y: float) -> Vector3:
	var fat: float = p.fat
	var r: float = [0.047, 0.046, 0.042, 0.036, 0.038, 0.034, 0.026][clampi(int(t * 6.0), 0, 6)]
	var r2: float = [0.047, 0.046, 0.042, 0.036, 0.038, 0.034, 0.026][clampi(int(t * 6.0) + 1, 0, 6)]
	var rr := lerpf(r, r2, fmod(t * 6.0, 1.0)) * (0.92 if p.female else 1.0) + fat * 0.012
	return Vector3(rr, rr * 1.05, 0.0)


func _leg_pts(s: String) -> Array:
	var th := _j("thigh" + s)
	var sh := _j("shin" + s)
	var ft := _j("foot" + s)
	return [[th + Vector3(0, 0.02, 0), "thigh" + s], [sh.lerp(th, 0.1), "thigh" + s], [sh.lerp(ft, 0.1), "shin" + s],
			[ft + Vector3(0, 0.04, 0), "shin" + s], [ft, "foot" + s]]


func _leg_prof(t: float, _y: float) -> Vector3:
	var rows := [0.072, 0.08, 0.066, 0.05, 0.052, 0.056, 0.046, 0.036, 0.032]
	var i := clampi(int(t * 8.0), 0, 7)
	var rr := lerpf(rows[i], rows[i + 1], smoothstep(0.0, 1.0, fmod(t * 8.0, 1.0)))
	rr *= 1.05 if p.female and t < 0.4 else 1.0
	rr += p.fat * 0.02 * (1.0 - t)
	return Vector3(rr, rr * 1.04, -0.006 if t > 0.5 and t < 0.75 else 0.0)


func _body(st: SurfaceTool) -> void:
	var rows := _torso_rows()
	loft(st, _torso_pts(), func(_t, y): return _table(rows, y), 0.0, 1.0, 0.0, true, false, Vector3(0, 0, 1), 2.6)
	# The neck, and the head as an egg on it.
	loft(st, [[Vector3(0, 1.39 * k, -0.005), "chest"], [Vector3(0, 1.47 * k, 0), "neck"], [Vector3(0, 1.56 * k, 0.005), "head"]],
			func(_t, _y): return Vector3(0.048, 0.05, 0.0), 0.0, 1.0, 0.0, false, false)
	var hc := 1.585 * k
	loft(st, [[Vector3(0, hc - 0.108, 0.0), "head"], [Vector3(0, hc + 0.106, 0.0), "head"]], func(t, _y):
		return _head_sec(t * 2.0 - 1.0), 0.0, 1.0, 0.0, false, false)
	for s in ["_l", "_r"]:
		loft(st, _arm_pts(s), _arm_prof, 0.0, 1.0, 0.0, true, false)
		_hand(st, s)
		loft(st, _leg_pts(s), _leg_prof, 0.0, 1.0, 0.0, true, false)
		# Feet: a shoe, drawn as the foot.
		var f := _j("foot" + s)
		loft(st, [[f + Vector3(0, 0.03, -0.055), "foot" + s], [f + Vector3(0, -0.015, 0.05), "foot" + s], [f + Vector3(0, -0.035, 0.14), "foot" + s]],
				func(t, _y): return Vector3(lerpf(0.042, 0.046, t), lerpf(0.05, 0.032, t), 0.0), 0.0, 1.0, 0.0, true, true, Vector3(0, 1, 0), 3.2)


## A hand: a palm, four fingers that bend at two joints (they share the
## fing1/fing2 bones: they close together) and a thumb.
func _hand(st: SurfaceTool, s: String) -> void:
	var h := _j("hand" + s)
	var f1 := _j("fing1" + s)
	var f2 := _j("fing2" + s)
	var th := _j("thumb" + s)
	var w := 0.9 if p.female else 1.0
	loft(st, [[h + Vector3(0, 0.01, 0), "hand" + s], [f1 + Vector3(0, 0.004, 0), "hand" + s]], func(t, _y):
		return Vector3(0.015 * w, lerpf(0.036, 0.042, t) * w, 0.0), 0.0, 1.0, 0.0, true, true, Vector3(0, 0, 1), 3.0)
	for i in 4:
		var z: float = [0.029, 0.01, -0.009, -0.027][i] * w
		var long: float = [0.95, 1.05, 1.0, 0.8][i]
		loft(st, [[f1 + Vector3(0, 0.012, z), "fing1" + s], [f1 + Vector3(0, -0.004, z), "fing1" + s], [f2 + Vector3(0, 0.004, z), "fing2" + s],
				[f2 + Vector3(0, -0.038 * long, z), "fing2" + s]], func(t, _y):
			return Vector3(0.0085 * w, lerpf(0.0085, 0.0075, t) * w, 0.0), 0.0, 1.0, 0.0, true, true)
	var inward := -signf(h.x)
	loft(st, [[h + Vector3(inward * 0.004, -0.02, 0.02 * w), "hand" + s], [th, "thumb" + s], [th + Vector3(inward * 0.004, -0.045, 0.012), "thumb" + s]],
			func(t, _y): return Vector3(lerpf(0.012, 0.009, t) * w, lerpf(0.012, 0.009, t) * w, 0.0), 0.0, 1.0, 0.0, true, true)


# --- Clothes ------------------------------------------------------------------

func _cloth_mat(c: Dictionary, grime_mul := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CLOTH
	m.set_shader_parameter("col", c.get("col", Color.GRAY))
	m.set_shader_parameter("col2", c.get("col2", Color.WHITE))
	m.set_shader_parameter("pattern", c.get("pattern", 0))
	m.set_shader_parameter("grime", p.grime * grime_mul)
	m.set_shader_parameter("blood", p.blood)
	m.set_shader_parameter("seed", float(p.seed % 97))
	return m


func _holes(extra := 0.0) -> Callable:
	var torn: float = p.torn + extra if p.torn > 0.0 else 0.0
	if torn <= 0.0:
		return Callable()
	var nz := FastNoiseLite.new()
	nz.seed = p.seed
	nz.frequency = 9.0
	return func(pos: Vector3) -> bool: return nz.get_noise_3dv(pos) < 0.62 - torn


func _clothes() -> Array:
	var out := []
	var rows := _torso_rows()
	var torso := func(_t, y): return _table(rows, y)
	var sh: Dictionary = p.shirt
	if sh != null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var top := 0.81 if sh.kind != "tank" else 0.86
		var shoulder_cut := Callable()
		if sh.kind == "tank":
			shoulder_cut = func(pos: Vector3) -> bool: return not (absf(pos.x) > 0.105 * p.girth and pos.y > 1.30 * k)
		var holes := _holes()
		var keep := shoulder_cut
		if holes.is_valid():
			keep = func(pos: Vector3) -> bool: return holes.call(pos) and (not shoulder_cut.is_valid() or shoulder_cut.call(pos))
		# Rows from the hips (0.77) up: the shirt starts near the belt.
		var pts := _torso_pts()
		var fem: bool = p.female
		var cover := [[1.26, 0.0, 0.0, 0.0], [1.31, 0.17 if fem else 0.19, 0.0, 0.0], [1.37, 0.17 if fem else 0.188, 0.0, 0.0], [1.405, 0.15 if fem else 0.165, 0.0, 0.0], [1.435, 0.1 if fem else 0.11, 0.0, 0.0], [1.46, 0.06, 0.0, 0.0]]
		var shirt_prof := func(_t, y):
			var sec := _table(rows, y)
			if y > 1.26:
				sec.x = maxf(sec.x, _table(cover, y).x * (1.0 if y > 1.3 else 0.0))
			return sec
		var from := (0.875 - 0.77) / (1.45 - 0.77)
		loft(st, pts, shirt_prof, from, 0.96, 0.017, false, false, Vector3(0, 0, 1), 2.6, keep)
		var sleeve: float = {tee = 0.34, long = 0.9, tank = 0.0, shirt = 0.36}.get(sh.kind, 0.34)
		if sleeve > 0.0:
			for s in ["_l", "_r"]:
				loft(st, _arm_pts(s), _arm_prof, 0.02, sleeve, 0.013, false, false, Vector3(0, 0, 1), 2.0, holes)
		out.append([st, _cloth_mat(sh)])
		if top < 0.0:
			pass
	var pa: Dictionary = p.pants
	if pa != null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var holes := _holes(0.05)
		loft(st, _torso_pts(), torso, 0.0, (0.935 - 0.77) / 0.68, 0.009, true, false, Vector3(0, 0, 1), 2.6)
		var length: float = {long = 0.93, shorts = 0.42, knee = 0.55}.get(pa.kind, 0.93)
		for s in ["_l", "_r"]:
			loft(st, _leg_pts(s), _leg_prof, 0.02, length, 0.013 if pa.kind != "long" else 0.011, false, false, Vector3(0, 0, 1), 2.0, holes)
		out.append([st, _cloth_mat(pa, 1.5)])
	if p.vest != null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cut := func(pos: Vector3) -> bool: return not (absf(pos.x) > 0.118 * p.girth and pos.y > 1.27 * k)
		loft(st, _torso_pts(), torso, (1.0 - 0.77) / 0.68, 0.955, 0.026, false, false, Vector3(0, 0, 1), 2.6, cut)
		out.append([st, _cloth_mat(p.vest, 0.6)])
	# Shoes over the feet.
	var shoes := SurfaceTool.new()
	shoes.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in ["_l", "_r"]:
		var f := _j("foot" + s)
		loft(shoes, [[f + Vector3(0, 0.03, -0.055), "foot" + s], [f + Vector3(0, -0.015, 0.05), "foot" + s], [f + Vector3(0, -0.035, 0.14), "foot" + s]],
				func(t, _y): return Vector3(lerpf(0.042, 0.046, t), lerpf(0.05, 0.032, t), 0.0), 0.0, 1.0, 0.008, true, true, Vector3(0, 1, 0), 3.2)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = p.shoes
	sm.roughness = 0.7
	out.append([shoes, sm])
	return out


# --- Face and hair ------------------------------------------------------------

## The head's cross-section at `yy` (-1 chin .. 1 crown): half-width,
## half-depth, and how far the face pushes forward.
static func _head_sec(yy: float) -> Vector3:
	var round := sqrt(maxf(0.0, 1.0 - yy * yy))
	var jaw := 1.0 if yy > -0.2 else lerpf(1.0, 0.72, (-0.2 - yy) / 0.8)
	var push := 0.008 * maxf(0.0, 1.0 - pow((yy - 0.05) / 0.6, 2.0)) - 0.012 * smoothstep(-0.3, -1.0, yy)
	return Vector3(0.082 * round * jaw + 0.004, 0.098 * round * lerpf(1.0, 0.85, smoothstep(-0.2, -1.0, yy)) + 0.004, push)


## Where the face's surface is, straight ahead, at height `dy` above the head's middle.
func _face_z(dy: float) -> float:
	var yy := clampf(dy / 0.107, -1.0, 1.0)
	var sec := _head_sec(yy)
	return sec.y * p.girth + sec.z


func _skin_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c: Color = p.skin
	if p.zombie:
		c = c.lerp(Color("8a947e"), 0.55).darkened(0.1)
	m.albedo_color = c
	m.roughness = 0.62 if not p.zombie else 0.78
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	return m


func _blob(st: SurfaceTool, at: Vector3, r: Vector3, bone: String, segs_ref := Vector3(0, 0, 1)) -> void:
	loft(st, [[at - Vector3(0, r.y, 0), bone], [at + Vector3(0, r.y, 0), bone]], func(t, _y):
		var yy: float = t * 2.0 - 1.0
		var round := sqrt(maxf(0.0, 1.0 - yy * yy))
		return Vector3(r.x * round + 0.0005, r.z * round + 0.0005, 0.0), 0.0, 1.0, 0.0, false, false, segs_ref)


func _face() -> Array:
	var out := []
	var hc := 1.585 * k
	var eyes := SurfaceTool.new()
	eyes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brows := SurfaceTool.new()
	brows.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx in [-1.0, 1.0]:
		_blob(eyes, Vector3(0.031 * sx, hc + 0.012, _face_z(0.012) - 0.003), Vector3(0.013, 0.0085, 0.006), "head")
		_blob(brows, Vector3(0.033 * sx, hc + 0.031, _face_z(0.031) - 0.001), Vector3(0.018, 0.004, 0.005), "head")
	# The nose and the ears, in skin.
	var skin := SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blob(skin, Vector3(0, hc - 0.012, _face_z(-0.012) - 0.004), Vector3(0.011, 0.02, 0.013), "head")
	for sx in [-1.0, 1.0]:
		_blob(skin, Vector3(0.083 * sx, hc + 0.0, 0.0), Vector3(0.01, 0.026, 0.016), "head")
	var mouth := SurfaceTool.new()
	mouth.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blob(mouth, Vector3(0, hc - 0.048, _face_z(-0.048) - 0.002), Vector3(0.018, 0.003, 0.004), "head")
	var em := StandardMaterial3D.new()
	em.albedo_color = Color("e8e2cc") if p.zombie else Color("1a1210")
	em.roughness = 0.2
	out.append([eyes, em])
	var bm := StandardMaterial3D.new()
	bm.albedo_color = p.hair.darkened(0.1)
	out.append([brows, bm])
	out.append([skin, _skin_mat()])
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color("5a2a26") if p.zombie else (p.skin as Color).darkened(0.45)
	out.append([mouth, mm])
	# Hair: a shell over the head, cut away over the face.
	if p.hair_style != "bald":
		var hair := SurfaceTool.new()
		hair.begin(Mesh.PRIMITIVE_TRIANGLES)
		var long: bool = p.hair_style == "long"
		var fringe := hc + (0.05 if p.hair_style != "fringe" else 0.03)
		var keep := func(pos: Vector3) -> bool:
			if pos.z > 0.035:
				return pos.y > fringe
			if pos.z > -0.01:
				return pos.y > hc + 0.01 - (0.0 if not long else 0.06)
			return pos.y > hc - (0.05 if not long else 0.2)
		loft(hair, [[Vector3(0, hc - (0.108 if not long else 0.24), -0.01), "head"], [Vector3(0, hc + 0.117, -0.005), "head"]], func(t, y):
			var yy := clampf((y * k - hc) / 0.117, -1.0, 1.0) if y * k > hc - 0.108 else -1.0
			var round := sqrt(maxf(0.0, 1.0 - yy * yy)) if y * k > hc - 0.02 else 1.0
			return Vector3(0.09 * round + 0.003, 0.106 * round + 0.003, -0.004), 0.0, 1.0, 0.0, false, false, Vector3(0, 0, 1), 2.0, keep)
		var hm := StandardMaterial3D.new()
		hm.albedo_color = p.hair
		hm.roughness = 0.55
		hm.cull_mode = BaseMaterial3D.CULL_DISABLED
		out.append([hair, hm])
	return out
