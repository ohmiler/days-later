class_name Proportions
## Body proportion knobs. The game uses BODY_STYLE (V5: 1 : 5 heads, chosen
## 2026-09-28 from the study in docs/reviews/2026-09-28/4-character.md). The body
## is hand-drawn in Look/Clothes in today's numbers ("canonical": feet 0, hips
## -10, shoulders -18.6, collar -20, head centre (0, -24), head radius 4.2).
## Changing proportions works in two halves:
##   * the skeleton moves for real: Rig's bone lengths, hip height, shoulders
##     and the head's place come from the knobs, and every pose number that is a
##     length on the body (a stride, where a hand hangs, a punch's reach) is
##     scaled by the leg or arm factor, so IK still bends real bones;
##   * everything drawn from hard-coded numbers (the torso, belt, hips, clothes
##     on the body, the head and what is on it) goes through a proxy canvas
##     (Warp) that maps each point from the canonical body onto the new one:
##     BODY: y piecewise-linear between the landmarks (feet, hips, shoulders,
##     collar), x scaled by the body's width; HEAD: a uniform scale about the
##     head's centre. Limbs drawn from the rig's joints are left alone (OFF).
## With every knob at its default, nothing changes: `on` stays false and no
## proxy is used; with `force` the proxy runs anyway (its maps are then exact
## identities, which the identity check proves pixel for pixel).

enum { OFF, BODY, HEAD }

const BODY_STYLE := "V5"

# Today's body (canonical landmarks).
const C_HIP := -10.0
const C_SH := -18.6
const C_COLLAR := -20.0
const C_HEAD := Vector2(0, -24)
const C_THIGH := 5.2
const C_SHIN := 5.2
const C_UPPER := 4.4
const C_FORE := 4.2
const C_SH_X := 4.0
const C_NECK_W := 2.4
const C_CHEST := Vector2(0, -15)

# --- Knobs (defaults: today's body) --------------------------------------------------
static var hip_y := C_HIP  # where the legs join (Rig.HIP_Y)
static var sh_y := C_SH  # shoulder joints
static var collar_y := C_COLLAR  # top of the torso (the collar line)
static var head := C_HEAD  # head centre
static var head_s := 1.0  # head size (1 = radius 4.2)
static var thigh := C_THIGH
static var shin := C_SHIN
static var upper_arm := C_UPPER
static var forearm := C_FORE
static var sh_x := C_SH_X  # shoulder joints' half spread from the front (x girth)
static var wx := 1.0  # torso / clothes width from the front or back
static var wx_side := 1.0  # torso depth side-on
static var limb_w := 1.0  # arm thickness
static var leg_w := 1.0  # leg thickness
static var leg_x := 1.0  # how far apart the legs stand (front/back)
static var eye_k := 1.0  # eyes, relative to the head's scale (1: they shrink with it)
static var neck_w := C_NECK_W  # (only drawn with `on`)
static var leg_girth := 0.0  # how much a wide build (girth) thickens the legs too (0: not at all, as today)

static var force := false  # use the warp path even with today's values

# --- Derived (apply()) ---------------------------------------------------------------
static var on := false
static var L := 1.0  # leg factor: hip height / 10 (strides, lifts, knee heights)
static var A := 1.0  # arm factor: arm length / 8.6 (where hands go)
static var W := 1.0  # shoulder spread factor (hands' x from the front)
static var KN := 1.0  # shin factor (front-view knee height)
static var TH := 1.0  # thigh factor (a kick's knee, placed by hand)
static var T := 1.0  # torso band slope (hips..shoulders)
static var CB := 1.0  # collar band slope (shoulders..collar)
static var name := "C0"

# --- Warp state (set by Look while drawing) ----------------------------------------------
static var mode := OFF
static var side := false  # side-on: x is the body's depth
static var hc := Vector2.ZERO  # HEAD mode: the head's centre (new space)
static var shift := Vector2.ZERO  # moved after mapping (BODY: the hips' offset; HEAD: canonical to new head)
static var _warp: Warp


## Where a blow counts as the head: at the chin (Combat.zone_at).
static func head_line() -> float:
	return (head.y + 4.2 * head_s) if on else -23.0


## Below this a blow counts as the legs: the crotch.
static func legs_line() -> float:
	return (hip_y * (1.0 - 0.11)) if on else -9.0


## Every knob back to today's body.
static func reset() -> void:
	hip_y = C_HIP
	sh_y = C_SH
	collar_y = C_COLLAR
	head = C_HEAD
	head_s = 1.0
	thigh = C_THIGH
	shin = C_SHIN
	upper_arm = C_UPPER
	forearm = C_FORE
	sh_x = C_SH_X
	wx = 1.0
	wx_side = 1.0
	limb_w = 1.0
	leg_w = 1.0
	leg_x = 1.0
	eye_k = 1.0
	neck_w = C_NECK_W
	leg_girth = 0.0
	force = false
	name = "C0"
	apply()


## Push the knobs into the rig and work out the factors.
static func apply() -> void:
	L = hip_y / C_HIP
	A = (upper_arm + forearm) / (C_UPPER + C_FORE)
	W = sh_x / C_SH_X
	KN = shin / C_SHIN
	TH = thigh / C_THIGH
	T = (sh_y - hip_y) / (C_SH - C_HIP)
	CB = (collar_y - sh_y) / (C_COLLAR - C_SH)
	Rig.HIP_Y = hip_y
	Rig.THIGH = thigh
	Rig.SHIN = shin
	Rig.UPPER_ARM = upper_arm
	Rig.FOREARM = forearm
	Rig.ARM = upper_arm + forearm
	Look.HEAD = head
	on = force or not (hip_y == C_HIP and sh_y == C_SH and collar_y == C_COLLAR and head == C_HEAD and head_s == 1.0
			and thigh == C_THIGH and shin == C_SHIN and upper_arm == C_UPPER and forearm == C_FORE and sh_x == C_SH_X
			and wx == 1.0 and wx_side == 1.0 and limb_w == 1.0 and leg_w == 1.0 and leg_x == 1.0 and eye_k == 1.0 and leg_girth == 0.0)
	Look.CHEST = map_body(C_CHEST) if on else C_CHEST


## Set the knobs from targets, everything as fractions of the height H to the
## top of the hair (kept at 29 px, the scale rule's person), feet at 0:
##   n       heads tall (skull crown to chin = H / n)
##   neck    px of neck showing between chin and collar
##   drop    px from the collar line down to the shoulder joints
##   crotch  crotch height / H     knee  knee height / H
##   span    shoulder width incl. the arms / H
##   arm     shoulder-to-fist / H
##   limb, leg  arm and leg thickness factors; side  torso depth factor; eye  eye factor
static func design(d: Dictionary) -> void:
	reset()
	var H := 29.0
	var hh: float = H / float(d.n)  # crown to chin
	head_s = hh / 8.4
	# Hair top (c.y - 5.0 s) stays at -H.
	head = Vector2(0, -H + 5.0 * head_s)
	var chin := head.y + 4.2 * head_s
	collar_y = chin + float(d.neck)
	sh_y = collar_y + float(d.drop)
	# Crotch: the hips' bottom edge, 1.1 below the joint in today's body (x L).
	hip_y = -float(d.crotch) * H / (1.0 - 0.11)
	var knee := float(d.knee) * H
	shin = knee  # (side-on the knee sits about a shin above the sole)
	thigh = (-hip_y - knee) * 1.08  # (a little slack, as today: legs never quite straight)
	var arm: float = float(d.arm) * H
	upper_arm = arm * 0.515
	forearm = arm - upper_arm
	limb_w = d.limb
	leg_w = d.leg
	# Span: 2 (shoulder joint + the arm's outline half-width 1.8).
	sh_x = float(d.span) * H * 0.5 - 1.8 * limb_w
	# The torso's edge at the shoulder sits 0.4 (x limb) outside the joint, as today.
	wx = (sh_x + 0.4 * limb_w) / 4.4
	wx_side = d.side
	leg_x = d.get("legx", wx)
	eye_k = d.get("eye", 1.0)
	neck_w = d.get("neck_w", C_NECK_W * sqrt(head_s))
	leg_girth = d.get("leg_girth", 0.5)
	name = d.get("name", "?")
	apply()


const VARIANTS := {
	C0 = {},
	V5 = {name = "V5", n = 5.0, neck = 0.3, drop = 1.0, crotch = 0.44, knee = 0.27, span = 0.32, arm = 0.355, limb = 0.85, leg = 0.92, side = 0.85, eye = 1.15},
	V6 = {name = "V6", n = 6.0, neck = 0.45, drop = 0.9, crotch = 0.46, knee = 0.28, span = 0.29, arm = 0.365, limb = 0.76, leg = 0.85, side = 0.75, eye = 1.3},
	V7 = {name = "V7", n = 7.0, neck = 0.55, drop = 0.8, crotch = 0.47, knee = 0.285, span = 0.26, arm = 0.376, limb = 0.68, leg = 0.8, side = 0.68, eye = 1.45},
}


static func use(key: String) -> void:
	if key == "C0" or not VARIANTS.has(key):
		reset()
		return
	design(VARIANTS[key])


# --- The maps --------------------------------------------------------------------------
# (Written as p + offset so that with today's values each is an exact identity.)

## Canonical y on the body -> new y (piecewise linear between the landmarks;
## above the collar it carries on at the torso's slope, so a pack's top or a
## hood keeps its size).
static func map_y(y: float) -> float:
	if y >= C_HIP:
		return y * L if y <= 0.0 else y
	if y >= C_SH:
		return y + (hip_y - C_HIP) + (y - C_HIP) * (T - 1.0)
	if y >= C_COLLAR:
		return y + (sh_y - C_SH) + (y - C_SH) * (CB - 1.0)
	return y + (collar_y - C_COLLAR) + (y - C_COLLAR) * (T - 1.0)


static func map_body(p: Vector2) -> Vector2:
	return Vector2(p.x * (wx_side if side else wx), map_y(p.y)) + shift


static func map_head(p: Vector2) -> Vector2:
	return p + (p - hc) * (head_s - 1.0) + shift


## Leg thickness for a body of this girth (Look._girth while drawing).
static func leg_k(girth: float) -> float:
	return leg_w * (1.0 + (girth - 1.0) * leg_girth)


## Canonical upper-body y (a hand's target, relative to the shoulders) -> new:
## the shoulders' move plus the arm's length.
static func ay(y: float) -> float:
	return y + (sh_y - C_SH) + (y - C_SH) * (A - 1.0)


## How far the shoulders moved (0 with today's values).
static func dsh() -> float:
	return sh_y - C_SH


## The canvas Look should draw into: the real one, or (with the knobs on) the
## warp proxy in front of it.
static func canvas(ci):
	if not on:
		return ci
	if _warp == null:
		_warp = Warp.new()
	_warp.target = ci
	mode = OFF
	shift = Vector2.ZERO
	return _warp


## Stands in for the CanvasItem (or MeshCanvas) Look and Clothes draw into:
## maps every point of every primitive by the current mode, passes the rest on.
## (Look, Clothes and TopRig only ever call these three.)
class Warp extends RefCounted:
	var target

	func draw_set_transform(pos: Vector2, rotation := 0.0, scale := Vector2.ONE) -> void:
		target.draw_set_transform(pos, rotation, scale)

	func draw_set_transform_matrix(m: Transform2D) -> void:
		target.draw_set_transform_matrix(m)

	# (The maps below are map_body and map_head written out with the
	# landmarks in locals: this runs for every point of every character every
	# frame, and GDScript calls and static lookups per point cost more than the
	# arithmetic.)
	func draw_primitive(pts: PackedVector2Array, cols: PackedColorArray, uvs: PackedVector2Array, tex: Texture2D = null) -> void:
		var m: int = Proportions.mode
		if m == Proportions.OFF:
			target.draw_primitive(pts, cols, uvs, tex)
			return
		var q := PackedVector2Array(pts)
		var n := q.size()
		var sh: Vector2 = Proportions.shift
		if m == Proportions.HEAD:
			var c: Vector2 = Proportions.hc
			var k: float = Proportions.head_s - 1.0
			for i in n:
				var p: Vector2 = q[i]
				q[i] = p + (p - c) * k + sh
		else:
			var sx: float = Proportions.wx_side if Proportions.side else Proportions.wx
			var l: float = Proportions.L
			var hip_d: float = Proportions.hip_y - C_HIP
			var sh_d: float = Proportions.sh_y - C_SH
			var col_d: float = Proportions.collar_y - C_COLLAR
			var t1: float = Proportions.T - 1.0
			var cb1: float = Proportions.CB - 1.0
			for i in n:
				var p: Vector2 = q[i]
				var y := p.y
				if y >= C_HIP:
					if y <= 0.0:
						y *= l
				elif y >= C_SH:
					y += hip_d + (y - C_HIP) * t1
				elif y >= C_COLLAR:
					y += sh_d + (y - C_SH) * cb1
				else:
					y += col_d + (y - C_COLLAR) * t1
				q[i] = Vector2(p.x * sx + sh.x, y + sh.y)
		target.draw_primitive(q, cols, uvs, tex)
