extends RefCounted
## Weapons made in code, held for real: each is built in its hand's own space
## with the grip at the origin (hanging arm: fingers point -Y, the index is
## at +Z, the palm faces the body). The right hand carries it; a two-handed
## weapon's second grip pulls the left hand on by IK, so both hands stay on
## the handle through every swing. Poses are key frames (bone -> euler) eased
## between, only on the upper body, so the legs keep walking underneath.

## Where a closed fist's hole is, from the hand bone (x: toward the palm).
const FIST := Vector3(0.018, -0.064, 0.004)

const KINDS := {
	"fists": {hands = 1},
	"machete": {hands = 1, hit_at = 0.30, time = 0.8, reach = 1.5, dmg = 2},
	"axe": {hands = 2, hit_at = 0.5, time = 1.15, reach = 1.8, dmg = 3, second = Vector3(0, 0, 0.36)},
	"pistol": {hands = 2, time = 0.25, reach = 25.0, dmg = 3, second = Vector3(0.036, 0.004, -0.028), muzzle = Vector3(0, -0.17, 0.068)},
}


# --- Models -------------------------------------------------------------------

static func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## A rod along Z from z0 to z1.
static func _rod(parent: Node3D, r: float, z0: float, z1: float, mat: Material, sides := 10) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = z1 - z0
	c.radial_segments = sides
	c.rings = 1
	_mesh(parent, c, mat, Vector3(0, 0, (z0 + z1) * 0.5), Vector3(PI * 0.5, 0, 0))


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var b := BoxMesh.new()
	b.size = size
	_mesh(parent, b, mat, pos, rot)


## A flat plate from an outline in the YZ plane ([z, y] points, going around),
## `thick` across X, thinning to `edge` along its -Y side (a blade's edge).
static func _plate(parent: Node3D, outline: Array, thick: float, mat: Material, edge := -1.0) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ys: Array = outline.map(func(q): return q[1])
	var lo: float = ys.min()
	var hi: float = ys.max()
	var faces := []
	for sx in [1.0, -1.0]:
		var ring := []
		for q in outline:
			var t := 1.0 if edge < 0.0 else lerpf(edge, 1.0, clampf((q[1] - lo) / maxf(hi - lo, 0.001) * 2.0, 0.0, 1.0))
			ring.append(Vector3(sx * thick * 0.5 * t, q[1], q[0]))
		faces.append(ring)
	var c := Vector3.ZERO
	for v in faces[0]:
		c += v / faces[0].size()
	for f in 2:
		var ring: Array = faces[f]
		var cc := Vector3(c.x * (1 if f == 0 else -1), c.y, c.z)
		for i in ring.size():
			var a: Vector3 = ring[i]
			var b: Vector3 = ring[(i + 1) % ring.size()]
			if f == 0:
				st.add_vertex(cc); st.add_vertex(b); st.add_vertex(a)
			else:
				st.add_vertex(cc); st.add_vertex(a); st.add_vertex(b)
	for i in outline.size():
		var a0: Vector3 = faces[0][i]
		var a1: Vector3 = faces[0][(i + 1) % outline.size()]
		var b0: Vector3 = faces[1][i]
		var b1: Vector3 = faces[1][(i + 1) % outline.size()]
		st.add_vertex(a0); st.add_vertex(a1); st.add_vertex(b0)
		st.add_vertex(a1); st.add_vertex(b1); st.add_vertex(b0)
	st.generate_normals()
	var m := st.commit()
	var mi := _mesh(parent, m, mat)
	(mi.material_override as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED


static func build(kind: String) -> Node3D:
	var n := Node3D.new()
	var steel := _mat(Color("b8bcc2"), 0.85, 0.32)
	var dark := _mat(Color("1e1c1a"), 0.0, 0.7)
	match kind:
		"machete":
			_rod(n, 0.017, -0.065, 0.08, _mat(Color("2a2018"), 0.0, 0.85))
			_box(n, Vector3(0.036, 0.05, 0.008), Vector3(0, -0.01, 0.082), dark)
			_plate(n, [[0.085, 0.014], [0.3, 0.018], [0.5, 0.022], [0.56, 0.0], [0.545, -0.03], [0.45, -0.055], [0.25, -0.05], [0.085, -0.034]], 0.005, steel, 0.25)
		"axe":
			var wood := _mat(Color("d8a838"), 0.0, 0.6)
			_rod(n, 0.017, -0.06, 0.8, wood)
			var red := _mat(Color("b8201c"), 0.3, 0.45)
			_box(n, Vector3(0.03, 0.07, 0.08), Vector3(0, 0.0, 0.74), red)
			_plate(n, [[0.705, -0.02], [0.775, -0.02], [0.83, -0.19], [0.65, -0.19]], 0.028, red, 0.12)
			_plate(n, [[0.72, 0.02], [0.76, 0.02], [0.745, 0.15]], 0.02, red)
			_box(n, Vector3(0.006, 0.012, 0.18), Vector3(0, -0.186, 0.74), steel)  # the bright edge
		"pistol":
			_box(n, Vector3(0.028, 0.032, 0.1), Vector3(0, 0.004, 0.0), dark, Vector3(-0.25, 0, 0))
			_box(n, Vector3(0.026, 0.2, 0.032), Vector3(0, -0.07, 0.068), _mat(Color("2a2c30"), 0.7, 0.35))
			_box(n, Vector3(0.022, 0.07, 0.012), Vector3(0, -0.045, 0.043), dark)
			_box(n, Vector3(0.004, 0.012, 0.03), Vector3(0, -0.028, 0.03), dark)
	return n


# --- Holding and swinging -----------------------------------------------------

static func _q(e: Vector3) -> Quaternion:
	return Quaternion.from_euler(e)


## Key frames [[time, {bone: euler}], ...] at `t`, eased between; only the
## bones named are set.
static func keys(sk: Skeleton3D, track: Array, t: float) -> void:
	var i := 0
	while i < track.size() - 2 and t > track[i + 1][0]:
		i += 1
	var a: Array = track[i]
	var b: Array = track[mini(i + 1, track.size() - 1)]
	var f := clampf((t - a[0]) / maxf(b[0] - a[0], 0.0001), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	for bone in a[1]:
		var qa := _q(a[1][bone])
		var qb := _q(b[1].get(bone, a[1][bone]))
		sk.set_bone_pose_rotation(sk.find_bone(bone), qa.slerp(qb, f))


static func fingers(sk: Skeleton3D, side: String, curl: float, thumb := 0.6) -> void:
	var s := -1.0 if side == "_l" else 1.0  # toward the palm
	sk.set_bone_pose_rotation(sk.find_bone("fing1" + side), _q(Vector3(0, 0, s * curl * 1.45)))
	sk.set_bone_pose_rotation(sk.find_bone("fing2" + side), _q(Vector3(0, 0, s * curl * 1.5)))
	sk.set_bone_pose_rotation(sk.find_bone("thumb" + side), _q(Vector3(thumb * 0.5, 0, s * thumb * 0.9)))


const READY := {
	"machete": {upperarm_r = Vector3(-0.35, 0, -0.12), forearm_r = Vector3(-1.1, 0, 0), hand_r = Vector3(0.35, 0, 0),
			upperarm_l = Vector3(-0.2, 0, 0.12), forearm_l = Vector3(-0.5, 0, 0)},
	"axe": {chest = Vector3(0, 0.25, 0), upperarm_r = Vector3(-0.25, 0, -0.1), forearm_r = Vector3(-0.9, 0, 0), hand_r = Vector3(0.4, 0.6, 0.2)},
	"pistol": {upperarm_r = Vector3(-0.3, 0, 0.05), forearm_r = Vector3(-0.6, 0, 0), hand_r = Vector3(-0.2, 0, 0)},
	"pistol_aim": {chest = Vector3(0, -0.12, 0), upperarm_r = Vector3(-1.48, 0.0, 0.22), forearm_r = Vector3(-0.05, 0, 0), hand_r = Vector3(-0.08, 0.1, 0), head = Vector3(0.05, -0.1, 0)},
	"fists": {upperarm_r = Vector3(-0.7, 0, -0.1), forearm_r = Vector3(-1.9, 0, 0), upperarm_l = Vector3(-0.8, 0, 0.12), forearm_l = Vector3(-1.9, 0, 0)},
}

## A machete, one hand: back over the shoulder, a fast cut down across the
## body led by the hips, the blade carrying on past, then back up.
const MACHETE := [
	[0.0, {spine = Vector3(0, 0, 0), chest = Vector3(0, 0, 0), upperarm_r = Vector3(-0.35, 0, -0.12), forearm_r = Vector3(-1.1, 0, 0), hand_r = Vector3(0.35, 0, 0), upperarm_l = Vector3(-0.2, 0, 0.12), forearm_l = Vector3(-0.5, 0, 0)}],
	[0.22, {spine = Vector3(-0.05, -0.2, 0), chest = Vector3(-0.1, -0.45, 0), upperarm_r = Vector3(-2.4, 0.3, -0.75), forearm_r = Vector3(-1.75, 0, 0), hand_r = Vector3(-0.2, 0, 0), upperarm_l = Vector3(-0.9, 0, 0.35), forearm_l = Vector3(-1.2, 0, 0)}],
	[0.34, {spine = Vector3(0.15, 0.2, 0), chest = Vector3(0.2, 0.3, 0), upperarm_r = Vector3(-1.25, 0, 0.3), forearm_r = Vector3(-0.3, 0, 0), hand_r = Vector3(0.2, 0, 0), upperarm_l = Vector3(0.15, 0, 0.3), forearm_l = Vector3(-0.7, 0, 0)}],
	[0.46, {spine = Vector3(0.25, 0.3, 0), chest = Vector3(0.3, 0.5, 0), upperarm_r = Vector3(-0.55, 0, 0.6), forearm_r = Vector3(-0.2, 0, 0), hand_r = Vector3(0.6, 0, 0), upperarm_l = Vector3(0.3, 0, 0.35), forearm_l = Vector3(-0.6, 0, 0)}],
	[0.8, {spine = Vector3(0, 0, 0), chest = Vector3(0, 0, 0), upperarm_r = Vector3(-0.35, 0, -0.12), forearm_r = Vector3(-1.1, 0, 0), hand_r = Vector3(0.35, 0, 0), upperarm_l = Vector3(-0.2, 0, 0.12), forearm_l = Vector3(-0.5, 0, 0)}],
]

## A fire axe, both hands: a slow lift overhead leaning back, the drop with the
## whole body bending into it, the head buried low, a heavy recovery.
const AXE := [
	[0.0, {spine = Vector3(0, 0, 0), chest = Vector3(0, 0.25, 0), upperarm_r = Vector3(-0.25, 0, -0.1), forearm_r = Vector3(-0.9, 0, 0), hand_r = Vector3(0.4, 0.6, 0.2)}],
	[0.42, {spine = Vector3(-0.18, 0, 0), chest = Vector3(-0.15, 0.1, 0), upperarm_r = Vector3(-2.75, 0, -0.15), forearm_r = Vector3(-1.1, 0, 0), hand_r = Vector3(-0.5, 0.5, 0.2)}],
	[0.56, {spine = Vector3(0.22, 0, 0), chest = Vector3(0.2, 0.05, 0), upperarm_r = Vector3(-1.05, 0, 0.1), forearm_r = Vector3(-0.25, 0, 0), hand_r = Vector3(0.7, 0.4, 0.2)}],
	[0.72, {spine = Vector3(0.28, 0, 0), chest = Vector3(0.24, 0.05, 0), upperarm_r = Vector3(-0.55, 0, 0.1), forearm_r = Vector3(-0.15, 0, 0), hand_r = Vector3(0.9, 0.4, 0.2)}],
	[1.15, {spine = Vector3(0, 0, 0), chest = Vector3(0, 0.25, 0), upperarm_r = Vector3(-0.25, 0, -0.1), forearm_r = Vector3(-0.9, 0, 0), hand_r = Vector3(0.4, 0.6, 0.2)}],
]


## The upper body for `kind`: `attack` seconds into a blow (< 0: none),
## `aim` 0..1 raising a gun, `kick` 0..1 a shot's recoil. Call after the legs'
## pose (walk/stand); then hands() to close the fingers and pull the left hand on.
static func upper(sk: Skeleton3D, kind: String, attack: float, aim := 0.0, kick := 0.0) -> void:
	match kind:
		"machete":
			if attack >= 0.0:
				keys(sk, MACHETE, attack)
			else:
				keys(sk, [[0.0, READY.machete]], 0.0)
		"axe":
			keys(sk, AXE if attack >= 0.0 else [[0.0, READY.axe]], maxf(attack, 0.0))
		"pistol":
			keys(sk, [[0.0, READY.pistol], [1.0, READY.pistol_aim]], aim)
			if kick > 0.0:
				var h := sk.find_bone("hand_r")
				var f := sk.find_bone("forearm_r")
				var c := sk.find_bone("chest")
				sk.set_bone_pose_rotation(h, sk.get_bone_pose_rotation(h) * _q(Vector3(-0.45 * kick, 0, 0)))
				sk.set_bone_pose_rotation(f, sk.get_bone_pose_rotation(f) * _q(Vector3(-0.2 * kick, 0, 0)))
				sk.set_bone_pose_rotation(c, sk.get_bone_pose_rotation(c) * _q(Vector3(-0.06 * kick, 0, 0)))
		"fists":
			if attack < 0.0:
				keys(sk, [[0.0, READY.fists]], 0.0)


## Close the hands on what they hold, and bring the left hand to the second
## grip (two-handed weapons, and a gun being aimed).
## How far up the axe's handle the left hand is, through a blow: it slides
## down to meet the right as the head drops, as it does with a real axe.
const AXE_SLIDE := [[0.0, 0.36], [0.42, 0.33], [0.53, 0.1], [0.85, 0.1], [1.15, 0.36]]


static func _along(track: Array, t: float) -> float:
	for i in range(track.size() - 1):
		if t <= track[i + 1][0]:
			var f := clampf((t - track[i][0]) / (track[i + 1][0] - track[i][0]), 0.0, 1.0)
			return lerpf(track[i][1], track[i + 1][1], f * f * (3.0 - 2.0 * f))
	return track[-1][1]


static func hands(sk: Skeleton3D, kind: String, aim := 0.0, attack := -1.0) -> void:
	var holding := kind != "fists"
	fingers(sk, "_r", 0.95 if holding else 1.0, 0.7)
	var info: Dictionary = KINDS[kind]
	var two: bool = info.hands == 2 and (kind != "pistol" or aim > 0.5)
	fingers(sk, "_l", 0.95 if two or kind == "fists" else 0.25, 0.7 if two else 0.2)
	if two:
		sk.force_update_all_bone_transforms()
		var grip := hand_xform(sk, "_r") * Transform3D(Basis(), FIST)
		var second: Vector3 = info.second
		if kind == "axe":
			second.z = _along(AXE_SLIDE, maxf(attack, 0.0))
		var at := grip * Transform3D(Basis(), second)
		# The left hand's fist goes round that point, turned like the right.
		var left := at * Transform3D(Basis(), -Vector3(-FIST.x, FIST.y, FIST.z))
		var chest := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("chest"))
		var pole := chest * Vector3(0.6, -0.5, -0.3)
		ik_arm(sk, "_l", left, pole)


## A hand's transform in the world (from the pose as set so far).
static func hand_xform(sk: Skeleton3D, side: String) -> Transform3D:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand" + side))


## Two-bone IK: put the hand of `side` at `target` (world), the elbow bending
## toward `pole` (world). The shoulder stays where the body put it.
static func ik_arm(sk: Skeleton3D, side: String, target: Transform3D, pole: Vector3) -> void:
	var inv := sk.global_transform.affine_inverse()
	var t := inv * target
	var ua := sk.find_bone("upperarm" + side)
	var fa := sk.find_bone("forearm" + side)
	var hd := sk.find_bone("hand" + side)
	var la := sk.get_bone_rest(fa).origin.length()
	var lb := sk.get_bone_rest(hd).origin.length()
	var s := sk.get_bone_global_pose(ua).origin
	var d := t.origin - s
	var c := clampf(d.length(), 0.02, (la + lb) * 0.999)
	var dn := d.normalized()
	var cos_a := clampf((la * la + c * c - lb * lb) / (2.0 * la * c), -1.0, 1.0)
	var pp := (inv * pole) - s
	pp = (pp - dn * pp.dot(dn)).normalized()
	var elbow := s + dn * cos_a * la + pp * sqrt(1.0 - cos_a * cos_a) * la
	var wrist := s + dn * c
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(ua)).basis.orthonormalized()
	_aim_bone(sk, ua, parent, sk.get_bone_rest(fa).origin.normalized(), (elbow - s).normalized())
	sk.force_update_all_bone_transforms()
	var p2 := sk.get_bone_global_pose(ua).basis.orthonormalized()
	_aim_bone(sk, fa, p2, sk.get_bone_rest(hd).origin.normalized(), (wrist - elbow).normalized())
	sk.force_update_all_bone_transforms()
	var p3 := sk.get_bone_global_pose(fa).basis.orthonormalized()
	sk.set_bone_pose_rotation(hd, (p3.inverse() * t.basis.orthonormalized()).get_rotation_quaternion())


static func _aim_bone(sk: Skeleton3D, bone: int, parent: Basis, rest_dir: Vector3, want: Vector3) -> void:
	var now := parent * rest_dir
	var turn := Basis(Quaternion(now.normalized(), want))
	sk.set_bone_pose_rotation(bone, (parent.inverse() * turn * parent).get_rotation_quaternion())
