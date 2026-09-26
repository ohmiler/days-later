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
## girth, recoil, crouch, anchors, breath (a clock: standing still, the chest
## rises and falls with it), run (0 walking .. 1 running: see RUN below).
## `anchors` poses the body by where it touches something instead of by an
## action (with `free_arms`, only the seat and feet: the arms fight or hold a
## weapon as they would standing): {seat, hands: [far, near], feet: [far, near]}, in the same space
## (facing +x side-on). The hips sit on `seat`, and elbows and knees bend to
## put the hands and feet where they're asked (see _reach). A bike, a chair,
## a jerrycan held in both hands: each just says where its handholds are.
## Zombies also take: breed ("normal", "runner", "fat", "screamer"), bite
## (0..1 through a lunge, or absent), scream (0..1), hit (head snap offset),
## rise (0..1 getting up off the ground, with fall_dir: the side it lay on),
## and vary: {tilt, arm_y, droop, limp} so no two shamble quite the same.


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
	var weapon_l: Dictionary = st.get("weapon_l", {})  # a second weapon, in the left hand
	var aiming: bool = st.get("aiming", false)  # a gun raised to the aim
	var fall: float = st.get("fall", 0.0)
	var fall_dir: float = st.get("fall_dir", 1.0)
	var girth: float = st.get("girth", 1.0) * lk.get("build", 1.0)
	var recoil: Vector2 = st.get("recoil", Vector2.ZERO)
	var crouch: float = st.get("crouch", 0.0)
	var breed: String = st.get("breed", "normal")
	var vary: Dictionary = st.get("vary", {})
	var bite: float = st.get("bite", -1.0)
	var scream: float = st.get("scream", 0.0)
	var run: float = clampf(st.get("run", 0.0), 0.0, 1.0)

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
	var c := cos(phase) if moving else 0.0  # (where in the cycle: a foot on its way forward or back)
	if not moving:
		run = 0.0
	var bob := absf(s) * lerpf(1.0, RUN.bob, run)  # running: up off the ground between strides
	if zombie and moving:
		bob += maxf(0.0, sin(phase * 0.5)) * 0.8 * vary.get("limp", 1.0)  # limp

	var r := {view = view, sx = sx, girth = girth, base = base, tip = tip, fall_dir = fall_dir,
			zombie = zombie, closed = fall >= 1.0, hips = Vector2.ZERO, shadow = st.get("shadow", true)}
	if st.has("anchors") and fall <= 0.0:
		var ar := _anchored(r, st.anchors, view, st.get("lean", 0.0))
		if st.get("free_arms", false):
			# Sat, but fighting: the arms as they'd be on foot (the torso stays upright).
			ar.torso = 0.0
			var arms := _fist_arms(view, angle, sx, attack, ext, weapon, weapon_l, girth, st.get("aiming", false))
			for i in arms.size():
				arms[i].idx = i
			ar.arms_back = arms.filter(func(a): return a.behind)
			ar.arms_front = arms.filter(func(a): return not a.behind)
		return ar
	if st.get("rise", -1.0) >= 0.0 and fall <= 0.0:
		r.view = Look.SIDE
		r.sx = -1.0 if fall_dir > 0 else 1.0  # (seen side-on, the way it fell)
		return _rising(r, st.rise, girth, zombie)
	var walk := {}
	if zombie and breed != "runner":
		# A shamble: short steps, and some drag one foot along the ground.
		var drag := -1
		if vary.get("limp", 1.0) > 1.1:
			drag = 1 if vary.get("arm_y", 0.0) > 0.0 else 0
		walk = {stride = 3.0, drag = drag}
	walk.run = run
	walk.c = c
	r.legs = _legs(view, s, angle, sx, attack, ext, walk)

	# The upper body bobs with the walk, lunges into punches, rocks back from
	# kicks and hits, and drops when crouching. Zombies lean and throw
	# themselves by bending at the hips (`tilt`, forward; `roll`, side to side),
	# so the body stays on its legs instead of sliding off them.
	var tilt := 0.13 if zombie else 0.0
	var roll := 0.0
	tilt += RUN.lean * run  # running: leaning into it
	crouch += RUN.sink * run
	# (Only a little for a punch: the shoulder turns into it instead, see _fist_arms.)
	var lunge := Vector2.from_angle(angle) * Vector2(0.8, 0.5) * ext if attack in [Look.PUNCH_L, Look.PUNCH_R] else Vector2.ZERO
	if attack == Look.KICK:
		var k := Look.kick_pose(ext)
		lunge = -Vector2.from_angle(angle) * Vector2(1.4, 0.7) * k.y + Vector2(0, 0.7 * k.x)
	if zombie and fall <= 0.0:
		match breed:
			"runner":  # hunched low and forward, like it's about to pounce
				tilt = 0.3
				crouch += 1.2
			"fat":  # rolls from side to side as it walks
				if moving:
					roll = sin(phase * 0.5) * 0.1
		if bite >= 0.0:
			# Lunge: rear back, then throw itself at the target, bending at the hips
			# (and a short step in).
			var strike := sin(clampf((bite - 0.6) / 0.4, 0, 1) * PI)
			tilt += -0.2 * clampf(bite / 0.6, 0, 1) if bite < 0.6 else 0.45 * strike
			lunge += Vector2.from_angle(angle) * Vector2(1.2, 0.8) * strike
		if scream > 0.0:
			crouch -= 1.0 * sin(clampf(scream, 0, 1) * PI)  # rises up to scream
	if st.has("breath") and not moving and fall <= 0.0:
		bob += (sin(st.get("breath", 0.0)) * 0.5 + 0.5) * 0.35  # breathing, so standing still isn't frozen
	r.upper = Vector2(0, -bob + sink * (1.0 - tip) + crouch) + lunge + recoil
	if fall <= 0.0:
		if view == Look.SIDE:
			r.torso = tilt * sx  # (forward is +x, mirrored)
		else:
			# Bending toward or away from the camera just shortens the body a little;
			# rolling side to side shows as a tilt.
			r.torso = roll * (1.0 if view == Look.FRONT else -1.0)
			r.upper.y += absf(tilt - (0.13 if zombie else 0.0)) * 2.5

	# Fists come up when fighting; otherwise arms hang and swing with the walk.
	# A falling body's arms go limp, even a zombie's.
	var arms: Array
	if zombie and fall <= 0.0 and breed == "runner" and moving and bite < 0.0:
		arms = _idle_arms(view, s * 1.8, girth)  # sprinting, arms pumping, like it still remembers how to run
		for a in arms:
			a.merge({sleeve_dark = 0.1, skin_dark = 0.1}, true)
	elif zombie and fall <= 0.0:
		arms = _zombie_arms(view, phase, girth, breed, vary, bite, scream)
	elif not zombie and (attack != Look.NONE or guard or not weapon.is_empty() or not weapon_l.is_empty()):
		arms = _fist_arms(view, angle, sx, attack, ext, weapon, weapon_l, girth, aiming)
	else:
		arms = _idle_arms(view, s, girth, run)
	for i in arms.size():
		arms[i].idx = i  # 0 = left (far side-on), 1 = right: lets Look leave off a missing arm
	r.arms_back = arms.filter(func(a): return a.behind)
	r.arms_front = arms.filter(func(a): return not a.behind)
	r.head = Look.HEAD + (vary.get("tilt", Vector2(0.7, 0.4)) if zombie else Vector2.ZERO)  # zombies tilt their head
	if zombie and fall <= 0.0:
		r.head += st.get("hit", Vector2.ZERO)  # snaps back when struck
		if bite >= 0.6:
			r.head += local_dir(angle, sx) * 1.6 * sin(clampf((bite - 0.6) / 0.4, 0, 1) * PI)  # jaws first
		if scream > 0.0:
			r.head += (Vector2(-1.2, -0.9) if view == Look.SIDE else Vector2(0, -1.0)) * sin(clampf(scream, 0, 1) * PI)
	r.front_kick = _front_kick(angle, sx, ext) if attack == Look.KICK and view == Look.FRONT else {}
	return r


# --- Skeleton --------------------------------------------------------------------
# Every limb is two bones of fixed length. Poses say where a hand or foot should
# go; _reach bends the elbow or knee to get it there, so nothing ever stretches.

const HIP_Y := -10.0  # where the legs join the body (feet at 0)
## Running, as far as it differs from walking: how high the body bounces, how
## far it leans in and sinks, the stride, how high a heel kicks up behind
## (side-on) and a knee comes up (front/back), how far the fists pump.
const RUN := {bob = 2.0, lean = 0.2, sink = 0.7, stride = 5.0, heel = 6.0, knee = 4.2, pump = 3.4}
const THIGH := 5.2
const SHIN := 5.2
const UPPER_ARM := 4.4
const FOREARM := 4.2
const ARM := UPPER_ARM + FOREARM


## Where the middle joint of a two-part limb goes for its end to reach `target`
## from `root`: the elbow or knee, bent to the `bend` side (+1 or -1). Out of
## reach, the limb points straight at the target.
static func _reach(root: Vector2, target: Vector2, l1: float, l2: float, bend: float) -> Array:
	var to := target - root
	var d := clampf(to.length(), 0.5, l1 + l2 - 0.01)
	var dir := to.normalized() if to.length() > 0.01 else Vector2.DOWN
	var a := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var mid := root + dir.rotated(a * bend) * l1
	var end := root + dir * d
	return [mid, end]


## _reach, bent whichever way puts the elbow or knee more toward `pref`.
static func _bend_toward(root: Vector2, target: Vector2, l1: float, l2: float, pref: Vector2) -> Array:
	var a := _reach(root, target, l1, l2, 1.0)
	var b := _reach(root, target, l1, l2, -1.0)
	return a if ((a[0] as Vector2) - root).dot(pref) >= ((b[0] as Vector2) - root).dot(pref) else b


## An arm from `sh` reaching for `target`, the elbow bending toward `pref`.
## Out of reach, the arm goes straight and the hand stops at its full length.
## `bend` caps how far the elbow sticks out from the line shoulder to hand: seen
## from the front or back, most of a bent arm's bend is toward or away from the
## camera, so it shows as a shorter arm, not a wide elbow.
static func _reach_arm(sh: Vector2, target: Vector2, pref: Vector2, behind: bool, extra := {}, bend := INF) -> Dictionary:
	var k := _bend_toward(sh, target, UPPER_ARM, FOREARM, pref)
	var hand: Vector2 = k[1]
	var elbow: Vector2 = k[0]
	if bend < INF and hand.distance_to(sh) > 0.01:
		# The same elbow, pulled in toward the line (which only shortens both bones).
		var dir := (hand - sh).normalized()
		var foot := sh + dir * (elbow - sh).dot(dir)
		elbow = foot + (elbow - foot).limit_length(bend)
	return _arm(sh, elbow, hand, behind, extra)


## Which way an elbow points: down and a little back side-on, down and out
## from the front or back.
static func _elbow_pref(view: int, i: int) -> Vector2:
	if view == Look.SIDE:
		return Vector2(-0.4, 1.0)
	return Vector2(-0.7 if i == 0 else 0.7, 1.0)


## How far an elbow can stick out, as seen from this view (see _reach_arm).
static func _elbow_bend(view: int) -> float:
	return INF if view == Look.SIDE else 1.2


## A leg from `hip` to `foot`, the knee bending toward `pref` (forward, side-on).
static func _leg(hip: Vector2, foot: Vector2, far: bool, pref := Vector2.RIGHT, extra := {}) -> Dictionary:
	var k := _bend_toward(hip, foot, THIGH, SHIN, pref)
	var leg := {type = "line", hip = hip, knee = k[0], foot = k[1], far = far}
	leg.merge(extra, true)
	return leg


# --- Getting up ----------------------------------------------------------------------

## Getting up off the ground, u in 0..1, from lying on its back (as `fall`
## leaves it): sit up propped on the hands, draw the legs in to a crouch, then
## stand. The upper body turns about the hips (`torso`, see Look.draw_rig).
static func _rising(r: Dictionary, u: float, girth: float, zombie: bool) -> Dictionary:
	var fd: float = r.fall_dir
	var lie := fd * PI * 0.5  # the body's turn lying flat
	var a := smoothstep(0.0, 1.0, clampf(u / 0.4, 0, 1))  # sitting up
	var b := smoothstep(0.0, 1.0, clampf((u - 0.4) / 0.4, 0, 1))  # legs under it
	var c := smoothstep(0.0, 1.0, clampf((u - 0.8) / 0.2, 0, 1))  # standing
	var turn := lie * (1.0 - b)
	var sink := 4.5 * b * (1.0 - c)  # how low the hips are, crouched
	r.base = Transform2D(turn, Vector2.ZERO)
	r.tip = 1.0 - b
	r.torso = -lie * a if b <= 0.0 else -turn  # sitting up, then kept upright
	var torso: float = r.torso
	r.upper = Vector2(0, sink)
	r.hips = Vector2(0, sink)
	r.closed = false
	r.legs = [_leg(Vector2(-0.3, HIP_Y + sink), Vector2(-0.3, 0), true), _leg(Vector2(0.3, HIP_Y + sink), Vector2(0.3, 0), false)]
	# Hands on the ground behind the hips while it pushes up, then back to reaching.
	var hips_w: Vector2 = (r.base as Transform2D) * Vector2(0, HIP_Y + sink)
	var ground := Vector2(hips_w.x + fd * 3.0, 0.0)
	var pivot := Vector2(0, HIP_Y + sink)
	var to_world: Transform2D = (r.base as Transform2D) * (Transform2D(0, pivot) * Transform2D(r.torso, Vector2.ZERO) * Transform2D(0, -pivot)) 			* Transform2D(0, Vector2(r.sx, 1), 0, r.upper as Vector2)
	var on_ground: Vector2 = to_world.affine_inverse() * ground
	var shs := shoulders(Look.SIDE, girth)
	var z := {sleeve_dark = 0.1, skin_dark = 0.1} if zombie else {}
	var reach := _zombie_arms(Look.SIDE, 0.0, girth) if zombie else _idle_arms(Look.SIDE, 0.0, girth)
	var limp := _idle_arms(Look.SIDE, 0.0, girth)  # (how the arms lay, fallen)
	var arms := []
	for i in 2:
		var hand: Vector2 = (limp[i].hand as Vector2).lerp(on_ground + Vector2(0.8 * i, 0), clampf(u / 0.15, 0, 1)).lerp(reach[i].hand, c)
		var extra := z.duplicate()
		extra.dim = 0.25 if i == 0 else 0.0
		extra.idx = i
		arms.append(_reach_arm(shs[i], hand, Vector2(-0.4, 1.0), i == 0, extra))
	r.arms_back = arms.filter(func(x): return x.behind)
	r.arms_front = arms.filter(func(x): return not x.behind)
	r.head = Look.HEAD + (Vector2(0.7, 0.4) if zombie else Vector2.ZERO)
	r.front_kick = {}
	return r


# --- Anchored poses ------------------------------------------------------------------

## Sat on something with hands and feet on its holds (see build's `anchors`).
## `lean` bends the body forward at the hips (radians; side-on), the hands
## staying where they hold.
static func _anchored(r: Dictionary, an: Dictionary, view: int, lean := 0.0) -> Dictionary:
	var seat: Vector2 = an.get("seat", Vector2(0, HIP_Y))
	var up := seat - Vector2(0, HIP_Y)
	r.upper = Vector2(up.x * r.sx, up.y)  # (the body is placed unmirrored; its parts are drawn mirrored)
	r.hips = up
	var feet: Array = an.get("feet", [])
	var hands: Array = an.get("hands", [])
	var side := view == Look.SIDE
	# Arms: from the shoulders (which ride with the upper body) to each hold.
	var arms := []
	var shs := shoulders(view, r.girth)
	var pivot := Vector2(0, HIP_Y)  # (the upper body turns about the hips: see Look.draw_rig)
	var holds := []
	for i in 2:
		holds.append((hands[i] if i < hands.size() else up + shs[i] + Vector2(0, 8)) - up)
	if side:
		# Lean forward as far as it takes for the hands to reach the bars (a real
		# rider does), and if that's not enough sit further forward on the seat;
		# then lean as much more as asked.
		var need := 0.0
		var slide := 0.0
		while not _reaches(shs, holds, pivot, need, slide):
			if need < 0.3:
				need += 0.02
			elif slide < 5.0:
				slide += 0.25
			else:
				break
		lean += need
		if slide > 0.0:
			up.x += slide
			r.upper = Vector2(up.x * r.sx, up.y)
			r.hips = up
			for i in 2:
				holds[i] -= Vector2(slide, 0)
		if lean != 0.0:
			r.torso = lean * r.sx
	for i in 2:
		var sh: Vector2 = shs[i]
		var hand: Vector2 = holds[i]
		if side and lean != 0.0:
			hand = pivot + (hand - pivot).rotated(-lean)  # (so after the lean they are still on the holds)
		# (Elbows down side-on; out to the sides from the front or back.)
		var pref := Vector2(0, 1) if side else Vector2(-1.0 if i == 0 else 1.0, 0)
		arms.append(_reach_arm(sh, hand, pref, side and i == 0, {dim = 0.25 if side and i == 0 else 0.0, fist = true, idx = i}))
	# Legs: from each hip down to its foothold, knees forward (side-on) or out.
	r.legs = []
	for i in 2:
		var hip := up + (Vector2(-0.3 + 0.6 * i, HIP_Y) if side else Vector2(-1.7 + 3.4 * i, HIP_Y))
		var foot: Vector2 = feet[i] if i < feet.size() else hip + Vector2(0, -HIP_Y)
		var pref := Vector2.RIGHT if side else Vector2(-1.0 if i == 0 else 1.0, 0)
		r.legs.append(_leg(hip, foot, side and i == 0, pref, {type = "limb", shoe = "rect", e = 0.0}))
	r.arms_back = arms.filter(func(a): return a.behind)
	r.arms_front = arms.filter(func(a): return not a.behind)
	r.head = Look.HEAD
	r.front_kick = {}
	return r


## Would both hands reach their holds, leaning `lean` and sat `slide` further forward?
static func _reaches(shs: Array, holds: Array, pivot: Vector2, lean: float, slide: float) -> bool:
	for i in 2:
		var h: Vector2 = holds[i] - Vector2(slide, 0)
		if (shs[i] as Vector2).distance_to(pivot + (h - pivot).rotated(-lean)) > ARM - 0.2:
			return false
	return true


## Aim direction in the character's (possibly mirrored) local space.
static func local_dir(angle: float, sx: float) -> Vector2:
	var d := Vector2.from_angle(angle)
	return Vector2(d.x * sx, d.y * 0.85)


## Where the arms attach. Side-on, both shoulders sit near the middle of the
## body; from the front or back they sit at its edges, so a broader build has
## them further apart.
static func shoulders(view: int, girth := 1.0) -> Array:
	if view == Look.SIDE:
		return [Vector2(-0.6, -18.6), Vector2(0.6, -18.3)]
	return [Vector2(-4.0 * girth, -18.6), Vector2(4.0 * girth, -18.6)]


# --- Legs ------------------------------------------------------------------------
# Every leg has hip, knee, foot and far; `type` says how Look draws it:
#   "rect"  a straight column, front/back view (plus x, lift)
#   "line"  side view, bent at the knee
#   "limb"  kicking or sat on something (plus shoe, e)

## `walk` changes the gait: {stride, drag}; drag is the leg (0 far/left, 1
## near/right) that scrapes along the ground instead of stepping, or -1.
static func _legs(view: int, s: float, angle: float, sx: float, attack: int, ext: float, walk := {}) -> Array:
	if attack == Look.KICK:
		return _kick_legs(view, angle, sx, ext)
	var stride: float = walk.get("stride", 4.0)
	var drag: int = walk.get("drag", -1)
	var run: float = walk.get("run", 0.0)
	var c: float = walk.get("c", 0.0)
	if view == Look.SIDE:
		# Pendulum legs from the hip; whichever foot swings forward lifts a little.
		# A dragged foot swings half as far and never leaves the ground.
		# Running, the stride is longer and the foot comes forward high: the
		# heel kicks up behind as it leaves the ground, the knee drives through.
		var legs := []
		for i in 2:
			var sw := s if i == 1 else -s
			var cw := c if i == 1 else -c  # > 0: this foot is on its way forward
			var hip := Vector2(-0.3 + 0.6 * i, HIP_Y)
			var foot := hip + Vector2(sw * stride, 10.0 - maxf(0.0, sw) * 1.5)
			if i == drag:
				foot = hip + Vector2(sw * stride * 0.5 - 0.8, 10.0)
			if run > 0.0:
				var up := maxf(0.0, (cw - sw) * 0.7) * RUN.heel
				foot = foot.lerp(hip + Vector2(sw * RUN.stride, 10.0 - up), run)
			legs.append(_leg(hip, foot, i == 0))
		return legs
	# From the front or back: the knee comes up higher with each running stride.
	var lift := lerpf(2.2, RUN.knee, run)
	return [_rect_leg(-3.1, 0.0 if drag == 0 else maxf(0.0, s) * lift), _rect_leg(0.3, 0.0 if drag == 1 else maxf(0.0, -s) * lift)]


## A front/back leg: a column from the hip down, its foot lifted by `lift`.
static func _rect_leg(x: float, lift: float, far := false) -> Dictionary:
	var c := x + 1.4
	return {type = "rect", x = x, lift = lift, far = far,
			hip = Vector2(c, HIP_Y - 0.5), knee = Vector2(c, -5.6 - lift * 0.5), foot = Vector2(c, -lift)}


static func _kick_legs(view: int, angle: float, sx: float, t: float) -> Array:
	var k := Look.kick_pose(t)
	var c := k.x
	var e := k.y
	var d := local_dir(angle, sx)
	if view == Look.SIDE:
		# Standing leg braces back a little as the weight shifts. The kicking foot
		# chambers up by the knee, then snaps out; the knee follows it.
		var hip := Vector2(0.6, HIP_Y)
		var foot := (hip + Vector2(0, 10)).lerp(hip + Vector2(4.0, 3.5), c).lerp(hip + Vector2(12.5, -1.0 + d.y * 5.0), e)
		return [_leg(Vector2(-0.3, HIP_Y), Vector2(-1.8 * c, 0), true),
				_leg(hip, foot, false, Vector2(1.0, -1.0), {type = "limb", shoe = "side_kick", e = e})]
	if view == Look.FRONT:
		return [_rect_leg(-3.1, 0.0, true)]  # the kicking leg is drawn over the body later
	# Kicking away from the camera: the leg drives up the screen, mostly behind the body.
	var hip := Vector2(1.7, HIP_Y)
	return [_rect_leg(-3.1, 0.0, true),
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
	var hip := Vector2(1.7, HIP_Y - 0.5)
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


## Relaxed arms, swinging opposite to the legs. Running (`run` toward 1) the
## elbows bend to a right angle and the fists pump, forward up to the chest
## and back past the hip.
static func _idle_arms(view: int, s: float, girth := 1.0, run := 0.0) -> Array:
	var shs := shoulders(view, girth)
	var out := []
	var fist := {fist = true} if run > 0.5 else {}
	if view == Look.SIDE:
		for i in 2:
			var behind := i == 0
			var sw := s if behind else -s
			var hand: Vector2 = shs[i] + Vector2(sw * 4.2 + 0.6, 8.2)
			hand = hand.lerp(shs[i] + Vector2(sw * RUN.pump + 0.5, 6.2 - maxf(0.0, sw) * 2.6), run)
			var pref := _elbow_pref(view, i).lerp(Vector2(-1.0, 0.5), run)  # (the elbow goes back, not out)
			var extra := {dim = 0.25 if behind else 0.0}
			extra.merge(fist)
			out.append(_reach_arm(shs[i], hand, pref, behind, extra, _elbow_bend(view)))
		return out
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hand: Vector2 = shs[i] + Vector2(1.0 * side, 7.7 + s * side * 1.3)
		hand = hand.lerp(shs[i] + Vector2(-0.4 * side, 5.6 + s * side * 2.4), run)  # (bent toward the camera: shorter)
		out.append(_reach_arm(shs[i], hand, _elbow_pref(view, i), false, fist.duplicate(), _elbow_bend(view)))
	return out


## Boxing guard with fists by the chin; a punch drives one fist straight out
## along the aim. With a weapon, the right hand holds it instead.
static func _fist_arms(view: int, angle: float, sx: float, attack: int, ext: float, weapon: Dictionary,
		weapon_l := {}, girth := 1.0, aiming := false) -> Array:
	var d := local_dir(angle, sx)
	var side := d.orthogonal().normalized()
	var sh := shoulders(view, girth)
	var chin := Vector2(0, -19.5) + d * 3.0
	var guard := [chin + side * 2.4, chin - side * 2.4 + d * 1.2]
	var reach := [Look.PUNCH_L, Look.PUNCH_R]
	var out := []
	var grip: String = weapon.get("grip", "swing")
	var two_hands := grip in ["chop", "sweep", "rifle"]
	for i in 2:
		# Back view: both arms are behind the body. Side view: the far arm (i == 0) is.
		var behind := view == Look.BACK or (view == Look.SIDE and i == 0)
		var dim := 0.25 if behind and view == Look.SIDE else 0.0
		if i == 1 and not weapon.is_empty():
			# Held in both hands, a weapon swings from the middle of the body, not
			# from one shoulder: otherwise the other arm has to reach right across.
			# Facing the camera or away, it's held low, by the belly, so the arms
			# hang down to it in a V instead of folding across the chest.
			var pivot: Vector2 = sh[1]
			if two_hands:  # (a long gun from the chest, not dropped to the belly)
				pivot = (sh[0] + sh[1]) * 0.5 + (Vector2.ZERO if view == Look.SIDE or grip == "rifle" else Vector2(0, 3.0))
			var main_arm := _weapon_arm(d, sh[1], Look.SWING if attack == Look.SWING else Look.NONE, ext, weapon, behind, dim,
					_elbow_pref(view, 1), _elbow_bend(view), pivot, aiming)
			if two_hands:
				# The other hand holds the handle lower down, so both arms follow the swing.
				var far := view == Look.BACK or view == Look.SIDE
				var dim0 := 0.25 if view == Look.SIDE else 0.0
				# (A long gun's other hand is out along the barrel; a club's is lower on the handle.)
				var off := _on_handle(sh[0], main_arm.hand, main_arm.weapon.dir, 5.0 if grip == "rifle" else -2.6,
						weapon.get("len", 10.0))
				var off_arm := _reach_arm(sh[0], off, _elbow_pref(view, 0), far, {fist = true, dim = dim0}, _elbow_bend(view))
				out.insert(0, off_arm)  # replaces the guard arm
				out.remove_at(1)
			out.append(main_arm)
			continue
		if i == 0 and not weapon_l.is_empty() and not two_hands:
			# A second weapon in the left hand: held and swung the same way, from the left shoulder.
			out.append(_weapon_arm(d, sh[0], Look.SWING if attack == Look.SWING_L else Look.NONE, ext, weapon_l, behind, dim,
					_elbow_pref(view, 0), _elbow_bend(view), Vector2.INF, aiming))
			continue
		var fist: Vector2 = guard[i]
		var from: Vector2 = sh[i]
		if attack == reach[i]:
			# The shoulder turns forward into the punch, adding to the arm's reach
			# without the whole body sliding off its hips.
			from += Vector2(d.x, d.y * 0.5) * 1.8 * ext
			# Straight out along the aim; foreshortened when punching toward or away from the camera.
			fist = fist.lerp(from + Vector2(d.x * 13.0, d.y * 6.0) + Vector2(0, 2.0 * absf(d.y)), ext)
		out.append(_reach_arm(from, fist, _elbow_pref(view, i), behind, {fist = true, dim = dim}, _elbow_bend(view)))
	return out


## Where a second hand grips a handle held at `hand` pointing along `dir`:
## `want` along it (negative = toward the butt), or as near to that as an arm
## from `sh` reaches. It stays on the handle either way.
static func _on_handle(sh: Vector2, hand: Vector2, dir: Vector2, want: float, length: float) -> Vector2:
	var lo := -3.0
	var hi := length * 0.6
	# Where along the handle is within reach: |hand + dir * t - sh| <= ARM.
	var w := hand - sh
	var b := w.dot(dir)
	var disc := b * b - w.length_squared() + ARM * ARM
	if disc < 0.0:
		return hand + dir * clampf(-b, lo, hi)  # nowhere: as close as the handle comes
	var root := sqrt(disc)
	var t0 := maxf(lo, -b - root)
	var t1 := minf(hi, -b + root)
	if t0 > t1:
		return hand + dir * (lo if -b < lo else hi)
	return hand + dir * clampf(want, t0, t1)


## How each grip moves, as angles from the aim direction (radians):
## [ready, wound back, follow-through, arm length, depth squash].
##   swing  one hand, over the shoulder and across (machete, hammer)
##   chop   two hands, raised high and brought straight down (axe, pipe)
##   sweep  two hands, a wide flat arc at waist height (bat, plank)
const GRIPS := {
	swing = [-1.1, -2.3, 0.9, 6.5, 0.8],
	chop = [-1.6, -2.7, 1.0, 5.5, 0.9],
	sweep = [-0.8, -2.4, 1.5, 7.0, 0.5],
}


## Weapon angle (relative to the aim) through an attack, t in 0..1: wind up,
## whip through, follow through, then return to the ready pose.
static func grip_angle(grip: String, t: float) -> float:
	var g: Array = GRIPS.get(grip, GRIPS.swing)
	if t < 0.3:
		return lerpf(g[0], g[1], t / 0.3)
	if t < 0.55:
		return lerpf(g[1], g[2], ease((t - 0.3) / 0.25, 0.5))
	if t < 0.7:
		return g[2]
	return lerpf(g[2], g[0], (t - 0.7) / 0.3)


## Knife thrust, t in 0..1: 0 = held back by the hip, 1 = arm fully out.
static func stab_reach(t: float) -> float:
	if t < 0.3:
		return lerpf(0.0, -0.4, t / 0.3)  # draw back
	if t < 0.5:
		return lerpf(-0.4, 1.0, ease((t - 0.3) / 0.2, 0.4))
	if t < 0.65:
		return 1.0
	return lerpf(1.0, 0.0, (t - 0.65) / 0.35)


## The weapon hand: holds the weapon ready, or moves it through its attack.
static func _weapon_arm(d: Vector2, sh: Vector2, attack: int, t: float, weapon: Dictionary, behind: bool, dim: float,
		elbow_pref: Vector2, bend: float, pivot := Vector2.INF, aiming := false) -> Dictionary:
	var at := sh if pivot == Vector2.INF else pivot  # what the weapon moves around
	var grip: String = weapon.get("grip", "swing")
	var base := atan2(d.y, d.x)
	var trail := PackedVector2Array()
	var dv: Vector2
	var hand: Vector2
	var k := 0.0
	if grip in ["pistol", "rifle"] and attack != Look.SWING:
		# A gun: raised along the aim when aiming, else held low and forward.
		if aiming:
			dv = d.normalized()
			hand = at + Vector2(d.x, d.y * 0.8) * (7.5 if grip == "pistol" else 5.0) + Vector2(0, 1.0)
		else:
			dv = (Vector2(d.x, d.y * 0.6) + Vector2(0, 0.9)).normalized()
			hand = at + Vector2(d.x * 2.0, 5.5)
	elif grip == "stab":
		# Blade held low and forward, point toward the target; the thrust drives straight out.
		k = stab_reach(t) if attack == Look.SWING else 0.0
		dv = Vector2.from_angle(base + 0.35 * (1.0 - maxf(k, 0.0)))
		hand = sh + Vector2(d.x, d.y * 0.8) * (4.0 + 4.5 * k) + Vector2(0, 3.0 - 1.5 * maxf(k, 0.0))
	else:
		var g: Array = GRIPS.get(grip, GRIPS.swing)
		var a := base + (grip_angle(grip, t) if attack == Look.SWING else (g[0] as float))
		dv = Vector2.from_angle(a)
		dv = Vector2(dv.x, dv.y * (1.0 if grip != "sweep" else 0.7)).normalized()
		hand = at + Vector2(dv.x, dv.y * (g[4] as float)) * (g[3] as float) + Vector2(0, 1.0)
		if attack == Look.SWING and t > 0.3 and t < 0.62:
			# Motion trail along the arc the weapon tip just travelled.
			var reach: float = (g[3] as float) + weapon.len
			for i in 7:
				var ak := lerpf(base + (g[1] as float), a, i / 6.0)
				trail.append(at + Vector2(cos(ak), sin(ak) * (g[4] as float)) * reach)
	var arm := _reach_arm(sh, hand, elbow_pref, behind,
			{fist = true, dim = dim, sleeve_dark = 0.05 + dim, sleeve_dim = 0.0, weapon = {dir = dv, draw = weapon, trail = trail}}, bend)
	if grip == "stab" and attack == Look.SWING and k > 0.5:
		var tip: Vector2 = (arm.hand as Vector2) + dv * (weapon.len as float)
		arm.weapon.trail = PackedVector2Array([tip - dv * 6.0, tip])  # a short streak behind the point
	return arm


## Arms reaching for you. Fat ones hang heavy by their sides, a screamer throws
## its arms back to howl, and a lunge flings both hands out to grab.
static func _zombie_arms(view: int, phase: float, girth: float, breed := "normal", vary := {}, bite := -1.0,
		scream := 0.0) -> Array:
	var sway := sin(phase * 0.7) * 1.0
	var z := {sleeve_dark = 0.1, skin_dark = 0.1}
	var arm_y: float = vary.get("arm_y", 0.0)
	var droop: int = vary.get("droop", -1)  # this arm has given up reaching and just hangs
	# How far the hands are thrown out: pulled in while rearing back, flung wide on the strike.
	var grab := 0.0
	if bite >= 0.0:
		grab = -0.4 * clampf(bite / 0.6, 0, 1) if bite < 0.6 else sin(clampf((bite - 0.6) / 0.4, 0, 1) * PI)
	var howl := sin(clampf(scream, 0, 1) * PI)
	var shs := shoulders(view, girth)
	match view:
		Look.SIDE:
			var out := []
			for i in 2:
				var behind := i == 0
				var sh: Vector2 = shs[i] + Vector2(0.6, 0.9)  # slumped forward
				var hand := Vector2(10.0, sh.y + 0.5 + arm_y + (sway if behind else -sway))
				if breed == "fat" or droop == i:
					hand = Vector2(2.2, -10.8 + (sway if behind else -sway) * 0.4)
				hand += Vector2(3.0 * grab, -1.5 * maxf(grab, 0.0))
				hand = hand.lerp(Vector2(-3.0, -12.5), howl)
				var extra := z.duplicate()
				extra.dim = 0.25 if behind else 0.0
				out.append(_reach_arm(sh, hand, Vector2(0, 1), behind, extra))
			return out
		Look.FRONT:
			var out := []
			for i in 2:
				var s := -1.0 if i == 0 else 1.0
				# Reaching toward the camera: foreshortened, hands big and low.
				var sh: Vector2 = shs[i]
				var hand := Vector2(2.8 * s * girth, -12.3 + sway * s + arm_y * 0.5)
				var big := true
				if breed == "fat" or droop == i:
					hand = Vector2(5.2 * s * girth, -11.0)
					big = false
				hand += Vector2(1.6 * s * grab, 1.8 * maxf(grab, 0.0))
				hand = hand.lerp(Vector2(6.5 * s * girth, -12.0), howl)
				var extra := z.duplicate()
				extra.big_hand = big and howl < 0.5
				out.append(_reach_arm(sh, hand, Vector2(s, 0.2), false, extra, _elbow_bend(view)))
			return out
		Look.BACK:
			# Reaching away from the camera: the arms go up past the shoulders,
			# hands out either side of the head (behind the body), unless they hang.
			var out := []
			for i in 2:
				var s := -1.0 if i == 0 else 1.0
				var sh: Vector2 = shs[i]
				var hand := Vector2(5.0 * s * girth, -20.4 + sway * s * 0.4 + arm_y * 0.3)
				var behind := true
				if breed == "fat" or droop == i:
					hand = Vector2(5.2 * s * girth, -11.0)
					behind = false
				hand += Vector2(2.0 * s * grab, -0.8 * maxf(grab, 0.0))
				hand = hand.lerp(Vector2(6.5 * s * girth, -12.0), howl)  # thrown back to howl: toward the camera
				if howl > 0.5:
					behind = false
				out.append(_reach_arm(sh, hand, Vector2(s, 0.2), behind, z.duplicate(), _elbow_bend(view)))
			return out
	return []


# --- Easing between poses ------------------------------------------------------------
# Most moves are animated from one end to the other, but some changes happen in
# a frame: raising the fists, stopping mid-stride, drawing a weapon, crouching.
# ease_into eases the joints over from the pose that was showing instead.

const BLEND_TIME := 0.1  # seconds


## What kind of pose `st` asks for: a change of kind starts an ease.
static func pose_kind(st: Dictionary) -> Array:
	var fight: bool = st.get("attack", Look.NONE) != Look.NONE or st.get("guard", false) 			or not st.get("weapon", {}).is_empty() or not st.get("weapon_l", {}).is_empty()
	return [fight, st.get("weapon", {}).get("kind", ""), st.get("weapon_l", {}).get("kind", ""),
			st.get("moving", false), st.get("crouch", 0.0) > 0.0, st.get("aiming", false)]


## Build `st`'s rig, eased in from what this character last showed. `mem` is the
## character's own (an empty dictionary to start); `now` a clock in seconds.
## Turning to another view, falling or sitting on something doesn't ease: those
## change the whole drawing.
static func build_eased(st: Dictionary, lk: Dictionary, mem: Dictionary, now: float) -> Dictionary:
	var r := build(st, lk)
	if st.get("fall", 0.0) > 0.0 or st.has("anchors"):
		mem.clear()
		return r
	var kind := pose_kind(st)
	var seen := [r.view, r.sx]
	if mem.get("seen", []) != seen:
		mem.erase("from")  # a new view: nothing to ease from
	elif mem.get("kind", []) != kind:
		mem.from = mem.shown  # (mid-ease too: carry on from where it had got to)
		mem.t0 = now
	mem.kind = kind
	mem.seen = seen
	if mem.has("from"):
		var k := (now - (mem.t0 as float)) / BLEND_TIME
		if k >= 1.0:
			mem.erase("from")
		else:
			r = blend(mem.from, r, smoothstep(0.0, 1.0, k))
	mem.shown = r
	return r


## Part way (k in 0..1) from rig `a` to rig `b`, both of the same view. Joints
## move in straight lines; a limb between two poses can only come out shorter,
## never stretched. Anything not a position is `b`'s.
static func blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := b.duplicate()
	for key in ["upper", "head", "hips"]:
		if a.has(key) and b.has(key):
			out[key] = (a[key] as Vector2).lerp(b[key], k)
	var was := {}
	for arm in a.arms_back + a.arms_front:
		was[arm.idx] = arm
	var arms := []
	for arm in b.arms_back + b.arms_front:
		var m: Dictionary = arm
		if was.has(arm.idx):
			var p: Dictionary = was[arm.idx]
			m = arm.duplicate()
			for j in ["sh", "elbow", "hand"]:
				m[j] = (p[j] as Vector2).lerp(arm[j], k)
			if not p.weapon.is_empty() and not arm.weapon.is_empty():
				m.weapon = arm.weapon.duplicate()
				m.weapon.dir = (p.weapon.dir as Vector2).slerp(arm.weapon.dir, k)
		arms.append(m)
	out.arms_back = arms.filter(func(x): return x.behind)
	out.arms_front = arms.filter(func(x): return not x.behind)
	if a.legs.size() == b.legs.size():
		var legs := []
		for i in b.legs.size():
			var leg: Dictionary = b.legs[i].duplicate()
			for j in ["hip", "knee", "foot"]:
				leg[j] = (a.legs[i][j] as Vector2).lerp(b.legs[i][j], k)
			if leg.type == "rect":  # (a column is drawn from x and lift)
				leg.x = (leg.hip as Vector2).x - 1.4
				leg.lift = -(leg.foot as Vector2).y
			legs.append(leg)
		out.legs = legs
	return out
