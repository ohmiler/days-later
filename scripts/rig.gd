class_name Rig
## Pose -> joints. Works out where every part of a body is for one frame (hips,
## knees, feet, shoulders, elbows, hands, head, what the hand holds) from what
## the character is doing. It draws nothing: Look draws layers on top of a rig,
## so anything worn or held just attaches to a joint and follows every pose.
##
## All positions are in the character's local, possibly mirrored space: feet at
## the origin, up is -y, facing +x when side-on.

## `st` keys (all optional except view): view [view, flip], angle, phase,
## moving, zombie, attack, ext, guard, weapon (draw dict), fall, fall_dir,
## girth, recoil, crouch.
static func build(st: Dictionary, lk: Dictionary) -> Dictionary:
	var vf: Array = st.view
	var angle: float = st.get("angle", 0.0)
	var phase: float = st.get("phase", 0.0)
	var moving: bool = st.get("moving", false)
	var zombie: bool = st.get("zombie", false)
	var attack: int = st.get("attack", Look.NONE)
	var ext: float = st.get("ext", 0.0)
	var guard: bool = st.get("guard", false)
	var weapon: Dictionary = st.get("weapon", {})
	var fall: float = st.get("fall", 0.0)
	var fall_dir: float = st.get("fall_dir", 1.0)
	var girth: float = st.get("girth", 1.0) * lk.get("build", 1.0)
	var recoil: Vector2 = st.get("recoil", Vector2.ZERO)
	var crouch: float = st.get("crouch", 0.0)

	# Dying: knees buckle, then the body topples like a plank around the feet
	# (accelerating as it goes) and settles with a small bounce.
	var sink := 0.0
	var tip := 0.0
	var base := Transform2D.IDENTITY
	if fall > 0.0:
		vf = [Look.SIDE, fall_dir > 0]  # seen side-on, falling backwards
		moving = false
		attack = Look.NONE
		weapon = {}
		sink = 3.0 * clampf(fall / 0.25, 0, 1)
		var u := clampf((fall - 0.25) / 0.75, 0, 1)
		tip = u * u
		var bounce := sin(clampf((u - 0.85) / 0.15, 0, 1) * PI) * 0.08
		base = Transform2D(fall_dir * PI * 0.5 * (tip - bounce), Vector2(0, -2.0 * tip))

	var view: int = vf[0]
	var sx := -1.0 if vf[1] else 1.0
	var s := sin(phase) if moving else 0.0  # walk cycle, -1..1
	var bob := absf(s) * 1.0
	if zombie and moving:
		bob += maxf(0.0, sin(phase * 0.5)) * 0.8  # limp

	var r := {view = view, sx = sx, girth = girth, base = base, tip = tip, fall_dir = fall_dir,
			zombie = zombie, closed = fall >= 1.0}
	r.legs = _legs(view, s, angle, sx, attack, ext)

	# The upper body bobs with the walk, leans in (zombies), lunges into punches,
	# rocks back from kicks and hits, and drops when crouching.
	var lean := 1.2 if zombie and view == Look.SIDE else 0.0
	var lunge := Vector2.from_angle(angle) * Vector2(1.6, 1.0) * ext if attack in [Look.PUNCH_L, Look.PUNCH_R] else Vector2.ZERO
	if attack == Look.KICK:
		var k := Look.kick_pose(ext)
		lunge = -Vector2.from_angle(angle) * Vector2(1.4, 0.7) * k.y + Vector2(0, 0.7 * k.x)
	r.upper = Vector2(lean * sx, -bob + sink * (1.0 - tip) + crouch) + lunge + recoil

	# Fists come up when fighting; otherwise arms hang and swing with the walk.
	# A falling body's arms go limp, even a zombie's.
	var arms: Array
	if zombie and fall <= 0.0:
		arms = _zombie_arms(view, phase, girth)
	elif not zombie and (attack != Look.NONE or guard or not weapon.is_empty()):
		arms = _fist_arms(view, angle, sx, attack, ext, weapon)
	else:
		arms = _idle_arms(view, s)
	r.arms_back = arms.filter(func(a): return a.behind)
	r.arms_front = arms.filter(func(a): return not a.behind)
	r.head = Look.HEAD + (Vector2(0.7, 0.4) if zombie else Vector2.ZERO)  # zombies tilt their head
	r.front_kick = _front_kick(angle, sx, ext) if attack == Look.KICK and view == Look.FRONT else {}
	return r


## Aim direction in the character's (possibly mirrored) local space.
static func local_dir(angle: float, sx: float) -> Vector2:
	var d := Vector2.from_angle(angle)
	return Vector2(d.x * sx, d.y * 0.85)


## Where the arms attach. Side-on, both shoulders sit near the middle of the body.
static func shoulders(view: int) -> Array:
	if view == Look.SIDE:
		return [Vector2(-0.6, -18.6), Vector2(0.6, -18.3)]
	return [Vector2(-4.0, -18.6), Vector2(4.0, -18.6)]


# --- Legs ------------------------------------------------------------------------
# Leg entries, in draw order:
#   {type = "rect", x, lift, far}           straight down, front/back view
#   {type = "line", hip, foot, far}         side view, knee bent a little forward
#   {type = "limb", hip, knee, foot, far, shoe, e}   kicking

static func _legs(view: int, s: float, angle: float, sx: float, attack: int, ext: float) -> Array:
	if attack == Look.KICK:
		return _kick_legs(view, angle, sx, ext)
	if view == Look.SIDE:
		# Pendulum legs from the hip; whichever foot swings forward lifts a little.
		return [{type = "line", hip = Vector2(-0.3, -10), foot = Vector2(-0.3 - s * 4.0, -maxf(0.0, -s) * 1.5), far = true},
				{type = "line", hip = Vector2(0.3, -10), foot = Vector2(0.3 + s * 4.0, -maxf(0.0, s) * 1.5), far = false}]
	return [{type = "rect", x = -3.1, lift = maxf(0.0, s) * 2.2, far = false},
			{type = "rect", x = 0.3, lift = maxf(0.0, -s) * 2.2, far = false}]


static func _kick_legs(view: int, angle: float, sx: float, t: float) -> Array:
	var k := Look.kick_pose(t)
	var c := k.x
	var e := k.y
	var d := local_dir(angle, sx)
	if view == Look.SIDE:
		# Standing leg braces back a little as the weight shifts.
		var hip := Vector2(0.6, -10)
		return [{type = "line", hip = Vector2(-0.3, -10), foot = Vector2(-1.8 * c, 0), far = true},
				{type = "limb", hip = hip, far = false, shoe = "side_kick", e = e,
				knee = (hip + Vector2(0.8, 5)).lerp(hip + Vector2(5.5, -2.5), c).lerp(hip + Vector2(6.2, -1.2 + d.y * 2.5), e),
				foot = (hip + Vector2(0, 10)).lerp(hip + Vector2(4.0, 3.5), c).lerp(hip + Vector2(12.5, -1.0 + d.y * 5.0), e)}]
	if view == Look.FRONT:
		return [{type = "rect", x = -3.1, lift = 0.0, far = true}]  # the kicking leg is drawn over the body later
	# Kicking away from the camera: the leg drives up the screen, mostly behind the body.
	var hip := Vector2(1.7, -10)
	return [{type = "rect", x = -3.1, lift = 0.0, far = true},
			{type = "limb", hip = hip, far = false, shoe = "rect", e = e,
			knee = (hip + Vector2(0.3, 5)).lerp(hip + Vector2(0.8, 1.0), c).lerp(hip + Vector2(0.6 + d.x * 1.5, 2.0), e),
			foot = (hip + Vector2(0, 10)).lerp(hip + Vector2(0.6, 5.0), c).lerp(hip + Vector2(2.0 + d.x * 3.5, -2.0), e)}]


## Front kick toward the camera: the knee rises in front of the belly, then the
## foot drives out at the viewer.
static func _front_kick(angle: float, sx: float, t: float) -> Dictionary:
	var k := Look.kick_pose(t)
	var c := k.x
	var e := k.y
	var d := local_dir(angle, sx)
	var hip := Vector2(1.7, -10.5)
	return {hip = hip, e = e,
			knee = (hip + Vector2(0.3, 5)).lerp(hip + Vector2(0.8, -3.5), c).lerp(hip + Vector2(0.6 + d.x * 1.5, -1.0), e),
			foot = (hip + Vector2(0, 10)).lerp(hip + Vector2(0.6, 2.5), c).lerp(hip + Vector2(d.x * 3.5, 3.0), e)}


# --- Arms ------------------------------------------------------------------------
# Arm entries: {sh, elbow, hand, behind, fist, dim, sleeve_dark, skin_dark,
#               big_hand, weapon = {dir, draw, trail} or {}}

static func _arm(sh: Vector2, elbow: Vector2, hand: Vector2, behind: bool, extra := {}) -> Dictionary:
	var a := {sh = sh, elbow = elbow, hand = hand, behind = behind, fist = false, dim = 0.0,
			sleeve_dark = 0.05, skin_dark = 0.0, big_hand = false, weapon = {}}
	a.merge(extra, true)
	return a


## Relaxed arms, swinging opposite to the legs.
static func _idle_arms(view: int, s: float) -> Array:
	if view == Look.SIDE:
		var out := []
		for behind in [true, false]:
			var sw := s if behind else -s
			var sh := Vector2(0.3, -18.4)
			var elbow := sh + Vector2(sw * 1.8, 4.3)
			out.append(_arm(sh, elbow, elbow + Vector2(sw * 2.4 + 0.6, 3.9), behind, {dim = 0.25 if behind else 0.0}))
		return out
	var out := []
	for side in [-1.0, 1.0]:
		out.append(_arm(Vector2(4.0 * side, -18.6), Vector2(4.9 * side, -14.6), Vector2(5.0 * side, -10.9 + s * side * 1.3), false))
	return out


## Boxing guard with fists by the chin; a punch drives one fist straight out
## along the aim. With a weapon, the right hand holds it instead.
static func _fist_arms(view: int, angle: float, sx: float, attack: int, ext: float, weapon: Dictionary) -> Array:
	var d := local_dir(angle, sx)
	var side := d.orthogonal().normalized()
	var sh := shoulders(view)
	var chin := Vector2(0, -19.5) + d * 3.0
	var guard := [chin + side * 2.4, chin - side * 2.4 + d * 1.2]
	var reach := [Look.PUNCH_L, Look.PUNCH_R]
	var out := []
	for i in 2:
		# Back view: both arms are behind the body. Side view: the far arm (i == 0) is.
		var behind := view == Look.BACK or (view == Look.SIDE and i == 0)
		var dim := 0.25 if behind and view == Look.SIDE else 0.0
		if i == 1 and not weapon.is_empty():
			out.append(_weapon_arm(d, sh[1], attack, ext, weapon, behind, dim))
			continue
		var fist: Vector2 = guard[i]
		if attack == reach[i]:
			# Full reach sideways; foreshortened when punching toward or away from the camera.
			fist = fist.lerp(sh[i] + Vector2(d.x * 13.0, d.y * 6.0) + Vector2(0, 2.0 * absf(d.y)), ext)
		var bend := 1.0 - (ext if attack == reach[i] else 0.0)
		var elbow: Vector2 = sh[i].lerp(fist, 0.5) + Vector2(0, 2.6 * bend) - side * (1.0 if i == 0 else -1.0) * 0.8 * bend
		out.append(_arm(sh[i], elbow, fist, behind, {fist = true, dim = dim}))
	return out


## The weapon hand: holds the weapon raised and ready, or swings it through an arc.
static func _weapon_arm(d: Vector2, sh: Vector2, attack: int, t: float, weapon: Dictionary, behind: bool, dim: float) -> Dictionary:
	var base := atan2(d.y, d.x)
	var a := base + (Look.swing_angle(t) if attack == Look.SWING else -1.1)
	var dv := Vector2.from_angle(a)
	var hand := sh + Vector2(dv.x, dv.y * 0.8) * 6.5 + Vector2(0, 1.0)
	var trail := PackedVector2Array()
	if attack == Look.SWING and t > 0.3 and t < 0.62:
		# Motion trail along the arc the weapon tip just travelled.
		var reach: float = 6.5 + weapon.len
		for k in 7:
			var ak := lerpf(base - 2.3, a, k / 6.0)
			trail.append(sh + Vector2(cos(ak), sin(ak) * 0.8) * reach)
	return _arm(sh, sh.lerp(hand, 0.5) + Vector2(0, 1.4), hand, behind,
			{fist = true, dim = dim, sleeve_dark = 0.05 + dim, sleeve_dim = 0.0, weapon = {dir = dv, draw = weapon, trail = trail}})


static func _zombie_arms(view: int, phase: float, girth: float) -> Array:
	var sway := sin(phase * 0.7) * 1.0
	var z := {sleeve_dark = 0.1, skin_dark = 0.1}
	match view:
		Look.SIDE:
			var out := []
			for behind in [true, false]:
				var y := -17.8 + (0.0 if behind else 0.8)
				var sh := Vector2(0.4, y)
				var hand := Vector2(10.0, y + 0.5 + (sway if behind else -sway))
				var extra := z.duplicate()
				extra.dim = 0.25 if behind else 0.0
				out.append(_arm(sh, sh.lerp(hand, 0.5) + Vector2(0, 0.6), hand, behind, extra))
			return out
		Look.FRONT:
			var out := []
			for s in [-1.0, 1.0]:
				# Reaching toward the camera: foreshortened, hands big and low.
				var sh := Vector2(4.0 * s * girth, -18.6)
				var hand := Vector2(2.8 * s * girth, -12.3 + sway * s)
				var extra := z.duplicate()
				extra.big_hand = true
				out.append(_arm(sh, sh.lerp(hand, 0.5) + Vector2(0.6 * s, 0), hand, false, extra))
			return out
	return []  # from behind, the arms reach away from the camera, hidden by the body
