extends RefCounted
## Poses for a Person skeleton, worked out in code (like Rig does in 2D):
## each sets bone rotations from a few numbers. Rest = standing, arms down,
## facing +Z.


static func _rot(sk: Skeleton3D, bone: String, e: Vector3) -> void:
	sk.set_bone_pose_rotation(sk.find_bone(bone), Quaternion.from_euler(e))


static func reset(sk: Skeleton3D) -> void:
	for i in sk.get_bone_count():
		sk.set_bone_pose_rotation(i, Quaternion.IDENTITY)
		sk.set_bone_pose_position(i, sk.get_bone_rest(i).origin)


## Standing at ease: arms a little out, elbows soft, weight on one leg.
static func stand(sk: Skeleton3D, t := 0.0) -> void:
	reset(sk)
	var br := sin(t * 1.7) * 0.015
	_rot(sk, "upperarm_l", Vector3(0.05, 0, 0.09))
	_rot(sk, "upperarm_r", Vector3(0.03, 0, -0.08))
	_rot(sk, "forearm_l", Vector3(-0.18, 0, 0))
	_rot(sk, "forearm_r", Vector3(-0.22, 0, 0))
	_rot(sk, "chest", Vector3(br, 0, 0))
	_rot(sk, "hips", Vector3(0, 0.05, 0.03))
	_rot(sk, "thigh_l", Vector3(0.0, 0, -0.03))
	_rot(sk, "thigh_r", Vector3(-0.08, 0.1, 0.02))
	_rot(sk, "shin_r", Vector3(0.12, 0, 0))
	_rot(sk, "foot_r", Vector3(-0.05, 0, 0))


## Walking (run = 0) or running (run = 1), at `ph` radians into the stride.
static func walk(sk: Skeleton3D, ph: float, run := 0.0) -> void:
	reset(sk)
	var s := sin(ph)
	var swing := lerpf(0.42, 0.7, run)
	var lean := lerpf(0.04, 0.2, run)
	var hips := sk.find_bone("hips")
	var bob := absf(cos(ph)) * lerpf(0.025, 0.06, run)
	sk.set_bone_pose_position(hips, sk.get_bone_rest(hips).origin + Vector3(0, bob - lerpf(0.01, 0.05, run), 0))
	_rot(sk, "hips", Vector3(0, s * 0.12, 0))
	_rot(sk, "spine", Vector3(lean * 0.5, -s * 0.06, 0))
	_rot(sk, "chest", Vector3(lean * 0.5, -s * 0.1, 0))
	_rot(sk, "head", Vector3(-lean * 0.6 + 0.04, s * 0.05, 0))
	for side in [["_l", 1.0], ["_r", -1.0]]:
		var n: String = side[0]
		var f: float = side[1]
		var ls := s * f  # > 0: this leg forward
		var lift := maxf(0.0, -cos(ph + (0.0 if f > 0 else PI)))  # the leg coming through
		_rot(sk, "thigh" + n, Vector3(-ls * swing - lift * lerpf(0.15, 0.6, run), 0, 0))
		_rot(sk, "shin" + n, Vector3(lift * lerpf(0.7, 1.7, run) + 0.05, 0, 0))
		_rot(sk, "foot" + n, Vector3(-ls * 0.15 - lift * 0.2, 0, 0))
		# The arm on the other side swings with it.
		_rot(sk, "upperarm" + n, Vector3(ls * lerpf(0.42, 0.62, run) * lerpf(0.7, 1.0, run), 0, 0.08 * f))
		_rot(sk, "forearm" + n, Vector3(-lerpf(0.25, 1.35, run) - maxf(0.0, -ls) * lerpf(0.3, 0.1, run), 0, 0))


## A punch with the right hand, `k` 0 (guard) .. 1 (arm out).
static func punch(sk: Skeleton3D, k: float) -> void:
	reset(sk)
	_rot(sk, "hips", Vector3(0, 0.25 - k * 0.45, 0))
	_rot(sk, "chest", Vector3(0.08, -k * 0.3, 0))
	_rot(sk, "thigh_l", Vector3(-0.35, 0, 0.05))
	_rot(sk, "shin_l", Vector3(0.35, 0, 0))
	_rot(sk, "thigh_r", Vector3(0.25, 0, -0.04))
	_rot(sk, "shin_r", Vector3(0.2, 0, 0))
	_rot(sk, "upperarm_l", Vector3(-0.9, 0, 0.25))
	_rot(sk, "forearm_l", Vector3(-1.9, 0, 0))
	_rot(sk, "upperarm_r", Vector3(lerpf(-0.6, -1.45, k), 0, lerpf(-0.3, 0.05, k)))
	_rot(sk, "forearm_r", Vector3(lerpf(-2.0, -0.1, k), 0, 0))


## A two-handed overhead swing (a machete, a club): `k` 0 raised .. 1 down.
static func swing(sk: Skeleton3D, k: float) -> void:
	reset(sk)
	_rot(sk, "spine", Vector3(lerpf(-0.15, 0.3, k), 0, 0))
	_rot(sk, "chest", Vector3(lerpf(-0.1, 0.2, k), 0.1, 0))
	_rot(sk, "thigh_l", Vector3(-0.4, 0, 0.05))
	_rot(sk, "shin_l", Vector3(0.4, 0, 0))
	_rot(sk, "thigh_r", Vector3(0.3, 0, -0.05))
	_rot(sk, "upperarm_r", Vector3(lerpf(-2.8, -0.9, k), 0, 0.1))
	_rot(sk, "forearm_r", Vector3(lerpf(-0.8, -0.2, k), 0, 0))
	_rot(sk, "upperarm_l", Vector3(lerpf(-2.6, -0.8, k), 0, -0.1))
	_rot(sk, "forearm_l", Vector3(lerpf(-0.9, -0.3, k), 0, 0))


## A zombie shambling, arms up and reaching, head hanging; `ph` into the step.
static func zombie(sk: Skeleton3D, ph: float, tilt := 0.2, run := 0.0) -> void:
	walk(sk, ph, run)
	var s := sin(ph)
	_rot(sk, "spine", Vector3(0.22, 0, tilt * 0.4))
	_rot(sk, "chest", Vector3(0.12, s * 0.08, tilt * 0.3))
	_rot(sk, "head", Vector3(0.35, 0.2, tilt))
	_rot(sk, "upperarm_l", Vector3(-1.25 + s * 0.12, 0, 0.12))
	_rot(sk, "upperarm_r", Vector3(-1.05 - s * 0.12, 0, -0.2))
	_rot(sk, "forearm_l", Vector3(-0.35, 0, 0))
	_rot(sk, "forearm_r", Vector3(-0.15, 0, 0))
	_rot(sk, "hand_l", Vector3(0.4, 0, 0))
	_rot(sk, "hand_r", Vector3(0.5, 0, 0))


## Sat on a bike (or behind the rider, `pillion`), hands on the bars; in a
## car, sat upright with the hands on the wheel.
static func ride(sk: Skeleton3D, pillion := false, car := false) -> void:
	reset(sk)
	var hips := sk.find_bone("hips")
	sk.set_bone_pose_position(hips, sk.get_bone_rest(hips).origin + Vector3(0, -0.12, 0))
	_rot(sk, "thigh_l", Vector3(-1.35, 0, 0.18))
	_rot(sk, "thigh_r", Vector3(-1.35, 0, -0.18))
	_rot(sk, "shin_l", Vector3(1.25, 0, 0))
	_rot(sk, "shin_r", Vector3(1.25, 0, 0))
	if pillion:
		_rot(sk, "upperarm_l", Vector3(-0.5, 0, 0.3))
		_rot(sk, "upperarm_r", Vector3(-0.5, 0, -0.3))
		_rot(sk, "forearm_l", Vector3(-1.2, 0, 0))
		_rot(sk, "forearm_r", Vector3(-1.2, 0, 0))
		return
	_rot(sk, "spine", Vector3(0.12 if not car else 0.0, 0, 0))
	_rot(sk, "upperarm_l", Vector3(-0.95, 0, 0.12))
	_rot(sk, "upperarm_r", Vector3(-0.95, 0, -0.12))
	_rot(sk, "forearm_l", Vector3(-0.35, 0, 0))
	_rot(sk, "forearm_r", Vector3(-0.35, 0, 0))
