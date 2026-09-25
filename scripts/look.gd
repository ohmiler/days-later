class_name Look
## Shared vector drawing for people and zombies (3/4 view) plus palettes.
## Change colours here to restyle every character in the game.
##
## Characters are drawn with their FEET at the node origin, so y-sorting and
## collision both use the feet. Up on screen is -y.

const SKINS := [Color("e8bf98"), Color("d4a27c"), Color("b07a52"), Color("7a5238")]
const SHIRTS := [Color("4a5a6e"), Color("7a3e36"), Color("56603f"), Color("8a7a5a"), Color("3e3e40"), Color("5e4a5e"), Color("9a9488")]
const PANTS := [Color("2e3642"), Color("3e3a32"), Color("4a4a3e"), Color("2a2a2a"), Color("5a4a3a")]
const HAIRS := [Color("2b1d12"), Color("4e3220"), Color("a88a52"), Color("161412"), Color("6e2e1e"), Color("8a8a86")]
const ZOMBIE_SKINS := [Color("9aa58a"), Color("a3a592"), Color("8a9878"), Color("b0ad98")]

const HAIR_STYLES := ["short", "long", "ponytail", "buzz", "bald"]
const HAIR_STYLE_NAMES := ["สั้น", "ยาว", "มัดหาง", "เกรียน", "โล้น"]
const BUILDS := [0.9, 1.0, 1.12]
const BUILD_NAMES := ["ผอม", "กลาง", "ท้วม"]
## What a survivor looks like, as palette indices: small enough to save and to
## send in every snapshot as one int (see pack/unpack).
const APPEARANCE_KEYS := ["skin", "hair", "style", "shirt", "pants", "build"]

## Parts a body can lose (lk.missing bits): left arm, right arm, head.
const LOST_ARM_L := 1
const LOST_ARM_R := 2
const LOST_HEAD := 4
const BLOOD := Color("7a0e0a")
const BLOOD_DARK := Color("3e0605")

const CHEST := Vector2(0, -15)  # where guns and flashlights sit
const HEAD := Vector2(0, -24)

enum { FRONT, BACK, SIDE }
enum { NONE, PUNCH_L, PUNCH_R, KICK, SWING }  # attack poses

static var _cone: Texture2D
static var _base := Transform2D.IDENTITY
static var _girth := 1.0  # body width multiplier (fat and skinny zombies)
static var lift := Vector2.ZERO  # draw everything this far up (standing on a roof); caller sets and resets  # whole-body transform (used to topple a falling body)
static var _font: Font
## Menu option: no flying parts, wounds or spurting blood (fights still play the same).
static var low_gore := false


## Thai font for text drawn in the world (shop signs), rendered as MSDF so it stays sharp when zoomed.
static func thai_font() -> Font:
	return UiTheme.world("Kanit-Medium")


## Pick a view from a facing angle. Returns [view, flip]. `prev` adds
## hysteresis so diagonal angles don't flicker between front and side.
static func pick_view(angle: float, prev: Array) -> Array:
	var v := Vector2.from_angle(angle)
	var to_side := 0.55 if prev[0] == SIDE else 0.85
	if absf(v.x) > to_side:
		return [SIDE, v.x < 0]
	return [FRONT, false] if v.y > 0 else [BACK, false]


static func _sizes() -> Array:
	return [SKINS.size(), HAIRS.size(), HAIR_STYLES.size(), SHIRTS.size(), PANTS.size(), BUILDS.size()]


static func appearance_count() -> int:
	var n := 1
	for k in _sizes():
		n *= k
	return n


static func random_appearance(rng: RandomNumberGenerator) -> Dictionary:
	var app := {}
	var sizes := _sizes()
	for i in sizes.size():
		app[APPEARANCE_KEYS[i]] = rng.randi() % sizes[i]
	app.build = 1 if rng.randf() < 0.6 else app.build
	return app


static func pack(app: Dictionary) -> int:
	var code := 0
	var sizes := _sizes()
	for i in sizes.size():
		code = code * sizes[i] + posmod(int(app.get(APPEARANCE_KEYS[i], 0)), sizes[i])
	return code


static func unpack(code: int) -> Dictionary:
	var app := {}
	var sizes := _sizes()
	for i in range(sizes.size() - 1, -1, -1):
		app[APPEARANCE_KEYS[i]] = code % sizes[i]
		code /= sizes[i]
	return app


## The drawing look (colours and shapes) for an appearance.
static func look_of(app: Dictionary) -> Dictionary:
	return {skin = SKINS[app.skin], hair = HAIRS[app.hair], hair_style = HAIR_STYLES[app.style],
			shirt = SHIRTS[app.shirt], pants = PANTS[app.pants], build = BUILDS[app.build]}


## Old-style entry point, kept so existing callers work: packs the arguments into
## a pose and a look, then draws.
static func draw_human(ci: CanvasItem, vf: Array, angle: float, phase: float, moving: bool,
		skin: Color, shirt: Color, pants: Color, hair: Color, zombie: bool,
		attack: int = NONE, ext: float = 0.0, _armed: bool = false, guard: bool = false,
		recoil := Vector2.ZERO, weapon: Dictionary = {}, fall := 0.0, fall_dir := 1.0, girth := 1.0) -> void:
	draw(ci, {view = vf, angle = angle, phase = phase, moving = moving, zombie = zombie, attack = attack,
			ext = ext, guard = guard, recoil = recoil, weapon = weapon, fall = fall, fall_dir = fall_dir, girth = girth},
			{skin = skin, shirt = shirt, pants = pants, hair = hair})


## Draw a character: `st` is what they are doing (see Rig.build), `lk` what they
## look like: {skin, shirt, pants, hair, shoes?, build?}.
static func draw(ci: CanvasItem, st: Dictionary, lk: Dictionary) -> void:
	draw_rig(ci, Rig.build(st, lk), lk)


## Paint a rig in layers, back to front: shadow, legs, far arms, torso, head,
## near arms (with whatever they hold), and a leg kicking at the camera.
static func draw_rig(ci: CanvasItem, r: Dictionary, lk: Dictionary) -> void:
	_base = r.base
	_girth = r.girth
	lk = _dress(lk, r.zombie)
	var wear: Dictionary = lk.get("wear", {})
	var sx: float = r.sx
	var tip: float = r.tip
	var pants: Color = lk.pants
	var shoe: Color = lk.shoes
	# Contact shadow, stretching out under the body as it falls.
	ci.draw_set_transform(lift + Vector2(r.fall_dir * 12.0 * tip, 0), 0, Vector2(1 + 1.6 * tip, 0.38))
	_dot(ci, Vector2.ZERO, 7.5, Color(0, 0, 0, 0.35))

	# Legs stay planted; everything above them bobs.
	_xf(ci, Vector2.ZERO, Vector2(sx, 1))
	for leg in r.legs:
		_draw_leg(ci, leg, lk)
	_rect(ci, Rect2(-3.3, -11.5, 6.6, 2.6), pants.darkened(0.06))  # hips join the legs to the body

	_xf(ci, r.upper, Vector2(sx, 1))
	var pack: Dictionary = wear.get("back", {})
	if not pack.is_empty() and r.view == SIDE:
		_pack_side(ci, pack)  # behind everything, on the far side of the body
	var missing: int = lk.get("missing", 0)
	for a in r.arms_back:
		_draw_arm_or_stump(ci, a, lk, missing)
	var body: Dictionary = wear.get("body", {})
	if body.get("shape") == "hoodie" and r.view != BACK:
		_dot(ci, Vector2(-0.6 if r.view == SIDE else 0.0, -20.6), 3.4, (lk.shirt as Color).darkened(0.2))  # hood, behind the head
	_torso(ci, r.view, lk.shirt, pants, r.zombie)
	if lk.get("gore", -1) >= 0 and not low_gore:
		_wounds(ci, r.view, lk.gore)
	var over: Dictionary = wear.get("over", {})
	if over.get("shape") == "vest":
		_vest(ci, r.view, over)  # on top of the shirt
	if not pack.is_empty() and r.view != SIDE:
		_pack(ci, r.view, pack)
	if missing & LOST_HEAD:
		_neck_stump(ci, lk.skin)
	else:
		_head(ci, r.view, r.head, lk.skin, lk.hair, lk.get("hair_style", "short"), r.zombie, r.closed, wear.get("head", {}),
				lk.get("mouth", 0.0), true, lk.get("gore", -1) >= 0 and int(lk.gore) % 2 == 0 and not low_gore)
		if lk.get("crushed", false) and not low_gore:
			_crushed(ci, r.head)
	if body.get("shape") == "hoodie" and r.view == BACK:
		_poly(ci, _arc(Vector2(0, -20.2), 3.6, 0.0, PI), (lk.shirt as Color).darkened(0.12))  # hood down the back
	for a in r.arms_front:
		_draw_arm_or_stump(ci, a, lk, missing)
	if lk.get("spurt", 0.0) > 0.0 and not low_gore:
		_spurt(ci, r, missing, lk.spurt, lk.get("spurt_seed", 0))
	if not r.front_kick.is_empty():
		_xf(ci, Vector2.ZERO, Vector2(sx, 1))
		_front_kick_leg(ci, r.front_kick, lk)
	ci.draw_set_transform(Vector2.ZERO)


const SHOE := Color("1e1a16")


## Apply what is worn to the base look: clothes recolour the shirt, trousers and
## shoes and set flags (long sleeves, shorts, boots) that the body parts read.
static func _dress(lk: Dictionary, zombie: bool) -> Dictionary:
	var out := lk.duplicate()
	out.shoes = lk.get("shoes", SHOE)
	var wear: Dictionary = lk.get("wear", {})
	var grime := 0.15 if zombie else 0.0  # the dead's clothes are filthy
	var body: Dictionary = wear.get("body", {})
	if not body.is_empty() and body.shape != "vest":
		out.shirt = (body.col as Color).darkened(grime)
		out.long_sleeves = body.shape in ["long", "hoodie"]
	var legs: Dictionary = wear.get("legs", {})
	if not legs.is_empty():
		out.pants = (legs.col as Color).darkened(grime)
		out.shorts = legs.shape == "shorts"
	var feet: Dictionary = wear.get("feet", {})
	if not feet.is_empty():
		out.shoes = (feet.col as Color).darkened(grime)
		out.boots = feet.shape == "boots"
	return out


## Set the drawing transform for a body part, on top of the whole-body transform.
static func _xf(ci: CanvasItem, pos: Vector2, scale: Vector2) -> void:
	ci.draw_set_transform_matrix(Transform2D(0.0, lift) * _base * Transform2D(0.0, scale, 0.0, pos))


## Pool of blood spreading from a body lying toward `dir` (k grows 0..1 over time).
static func draw_blood_pool(ci: CanvasItem, dir: float, k: float) -> void:
	ci.draw_set_transform(Vector2(dir * 12.0, -0.5), 0, Vector2(1.3, 0.45))
	_dot(ci, Vector2.ZERO, 3.0 + 9.0 * k, Color(0.28, 0.02, 0.02, 0.75))
	_dot(ci, Vector2(dir * 3.0, 0), 2.0 + 5.0 * k, Color(0.2, 0.01, 0.01, 0.8))
	ci.draw_set_transform(Vector2.ZERO)


static func _draw_leg(ci: CanvasItem, leg: Dictionary, lk: Dictionary) -> void:
	var pants: Color = lk.pants
	var shoe: Color = lk.shoes
	var col := pants.darkened(0.18) if leg.far else pants
	# Below the knee: bare legs in shorts.
	var shin: Color = (lk.skin as Color).darkened(0.18 if leg.far else 0.05) if lk.get("shorts", false) else col
	var boot := 1.1 if lk.get("boots", false) else 0.0
	match leg.type:
		"rect":
			_leg_rect(ci, leg.x, leg.lift, col, shoe, shin, boot)
		"line":
			_leg_line(ci, leg.hip, leg.foot, col, shoe, shin, boot)
		"limb":
			var side: bool = leg.shoe == "side_kick"
			var w := [3.1, 2.8, 2.4] if side else [3.2, 2.9, 2.5]
			_limb(ci, leg.hip, leg.knee, w[0], w[1], col)
			_limb(ci, leg.knee, leg.foot, w[1], w[2], shin)
			var foot: Vector2 = leg.foot
			var e: float = leg.e
			if side:
				# Shoe turns from toes-forward (chambered) to sole-first (extended).
				var toe := Vector2(2.6, 0.2).lerp(Vector2(0.4, -2.6), e)
				_limb(ci, foot + Vector2(-0.6, 0.4).lerp(Vector2(0.4, 1.3), e), foot + toe, 2.1, 2.0, shoe)
			else:
				_rect(ci, Rect2(foot + Vector2(-1.6, -1.0), Vector2(3.2, 2.0)), shoe)


## Kick timeline for t in 0..1. Returns (chamber, extension): the knee comes up,
## the foot snaps out, holds for a beat, then pulls back.
static func kick_pose(t: float) -> Vector2:
	var c := clampf(t / 0.28, 0.0, 1.0) if t < 0.75 else clampf((1.0 - t) / 0.25, 0.0, 1.0)
	var e := 0.0
	if t < 0.28:
		e = 0.0
	elif t < 0.45:
		e = ease((t - 0.28) / 0.17, 0.4)  # fast snap out
	elif t < 0.65:
		e = 1.0
	else:
		e = clampf(1.0 - (t - 0.65) / 0.2, 0.0, 1.0)
	return Vector2(c, e)


## Front kick toward the camera; the sole grows as it comes closer.
static func _front_kick_leg(ci: CanvasItem, k: Dictionary, lk: Dictionary) -> void:
	var shoe: Color = lk.shoes
	var foot: Vector2 = k.foot
	var e: float = k.e
	var lit := (lk.pants as Color).lightened(0.06)  # nearer the camera, catches more light
	_limb(ci, k.hip, k.knee, 3.3, 3.1, lit)
	_limb(ci, k.knee, foot, 3.1, 2.7, (lk.skin as Color) if lk.get("shorts", false) else lit)
	var size := Vector2(3.2, 2.0) + Vector2(2.0, 2.6) * e
	var sole := Rect2(foot - Vector2(size.x * 0.5, size.y * 0.5), size)
	_rect(ci, sole, shoe)
	for i in 3:  # tread lines on the sole
		var y := sole.position.y + (i + 1) * sole.size.y / 4.0
		_line(ci, Vector2(sole.position.x + 0.5, y), Vector2(sole.end.x - 0.5, y), shoe.lightened(0.18), 0.4)


## Front/back leg: straight down, lifted by `lift` mid-stride.
static func _leg_rect(ci: CanvasItem, x: float, up: float, pants: Color, shoe: Color, shin: Color, boot: float) -> void:
	_rect(ci, Rect2(x, -10.5, 2.8, 10.5 - up - 1.7), shin)
	if shin != pants:
		_rect(ci, Rect2(x - 0.1, -10.5, 3.0, 5.0 - up * 0.5), pants)  # shorts end above the knee
	_rect(ci, Rect2(x - 0.3, -up - 1.9 - boot, 3.4, 1.9 + boot), shoe)


## Side leg from hip to foot with a slight forward knee; the shoe points forward.
static func _leg_line(ci: CanvasItem, hip: Vector2, foot: Vector2, pants: Color, shoe: Color, shin: Color, boot: float) -> void:
	var knee := hip.lerp(foot, 0.5) + Vector2(0.8, 0)
	_line(ci, knee, foot + Vector2(0, -1.4), shin, 2.6 if shin == pants else 2.2)
	_line(ci, hip, knee, pants, 2.9)
	_rect(ci, Rect2(foot + Vector2(-1.3, -1.9 - boot), Vector2(3.8 - boot * 0.6, 1.9 + boot)), shoe)
	if boot > 0.0:
		_rect(ci, Rect2(foot + Vector2(-1.3, -1.9), Vector2(3.8, 1.9)), shoe)


# --- Fast primitives -------------------------------------------------------------
# Characters are redrawn every frame, and Godot's draw_circle / draw_polygon cost
# 5-9 microseconds each (they rebuild the shape every time). These do the same
# job for a small fraction of that: circles are one textured quad, and convex
# polygons are split into 4-point primitives.

static var _dot_tex: Texture2D


static func _dot(ci: CanvasItem, c: Vector2, r: float, col: Color, just_load := false) -> void:
	if _dot_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				img.set_pixel(x, y, Color(1, 1, 1, 1) if Vector2(x - 31.5, y - 31.5).length() <= 32.0 else Color(1, 1, 1, 0))
		_dot_tex = ImageTexture.create_from_image(img)
	if just_load:
		return
	ci.draw_texture_rect(_dot_tex, Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, col)


## A filled rectangle, drawn from the same texture as everything else so the
## renderer can batch a whole character into a few calls.
static func _rect(ci: CanvasItem, r: Rect2, col: Color) -> void:
	_dot(ci, Vector2.ZERO, 0.0, col, true)
	ci.draw_texture_rect_region(_dot_tex, r, Rect2(30, 30, 4, 4), col)


## A straight stroke as one textured quad (same texture, so it batches too).
static func _line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w := 1.0) -> void:
	var n := (b - a).orthogonal().normalized() * w * 0.5
	if n == Vector2.ZERO:
		return
	_poly(ci, PackedVector2Array([a + n, b + n, b - n, a - n]), col)


static func _polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, w := 1.0) -> void:
	for i in pts.size() - 1:
		_line(ci, pts[i], pts[i + 1], col, w)


## A convex polygon, flat colour or one colour per point.
static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Variant) -> void:
	var n := pts.size()
	if n < 3:
		return
	var per_point: bool = col is PackedColorArray
	var flat := PackedColorArray([col]) if not per_point else PackedColorArray()
	_dot(ci, Vector2.ZERO, 0.0, Color.WHITE, true)
	var uv3 := PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5)])
	var uv4 := PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5)])
	var i := 1
	while i < n - 1:
		# Fan from the first point, two triangles at a time.
		var last := mini(i + 2, n - 1)
		var q := PackedVector2Array([pts[0], pts[i], pts[i + 1]])
		if last > i + 1:
			q.append(pts[last])
		if per_point:
			var cs := PackedColorArray([col[0], col[i], col[i + 1]])
			if last > i + 1:
				cs.append(col[last])
			ci.draw_primitive(q, cs, uv4 if q.size() == 4 else uv3, _dot_tex)
		else:
			ci.draw_primitive(q, flat, uv4 if q.size() == 4 else uv3, _dot_tex)
		i += 2


## A tapered limb segment with round ends, like a capsule.
static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, wa: float, wb: float, col: Color) -> void:
	var n := (b - a).orthogonal().normalized()
	if n == Vector2.ZERO:
		n = Vector2.RIGHT
	_poly(ci, PackedVector2Array([a + n * wa * 0.5, b + n * wb * 0.5, b - n * wb * 0.5, a - n * wa * 0.5]), col)
	_dot(ci, a, wa * 0.5, col)
	_dot(ci, b, wb * 0.5, col)


## One arm: short sleeve over the shoulder, bare forearm, closed hand. A dark
## outline pass first keeps the arm readable against the body behind it.
static func _arm(ci: CanvasItem, sh: Vector2, elbow: Vector2, hand: Vector2, sleeve: Color, skin: Color,
		fist := false, long := false) -> void:
	var line := skin.darkened(0.45)
	var cuff := sh.lerp(elbow, 0.75)
	_limb(ci, sh, elbow, 3.6, 3.0, line)
	_limb(ci, elbow, hand, 3.0, 2.6, line)
	_dot(ci, hand, 2.1 if fist else 1.8, line)
	if long:
		# Sleeve all the way down to the wrist.
		_limb(ci, elbow, elbow.lerp(hand, 0.8), 2.5, 2.2, sleeve.darkened(0.08))
		_limb(ci, sh, elbow, 3.0, 2.6, sleeve)
	else:
		_limb(ci, elbow, hand, 2.2, 1.8, skin)  # forearm
		_limb(ci, cuff, elbow, 2.3, 2.2, skin.darkened(0.05))
		_limb(ci, sh, cuff, 3.0, 2.8, sleeve)  # sleeve
	_dot(ci, hand, 1.5 if fist else 1.2, skin)
	if fist:
		_dot(ci, hand + Vector2(-0.4, -0.4), 0.6, skin.lightened(0.15))  # knuckle highlight


## One arm from the rig, plus anything held in its hand.
static func _draw_arm(ci: CanvasItem, a: Dictionary, lk: Dictionary) -> void:
	var dim: float = a.dim
	var skin: Color = (lk.skin as Color).darkened(a.skin_dark).darkened(dim)
	var sleeve: Color = (lk.shirt as Color).darkened(a.sleeve_dark).darkened(a.get("sleeve_dim", dim))
	var held: Dictionary = a.weapon
	if not held.is_empty() and not held.trail.is_empty():
		_polyline(ci, held.trail, Color(1, 1, 1, 0.35), 1.6)
	_arm(ci, a.sh, a.elbow, a.hand, sleeve, skin, a.fist, lk.get("long_sleeves", false))
	if a.big_hand:
		_dot(ci, a.hand, 1.7, skin)
	if not held.is_empty():
		_draw_weapon(ci, a.hand, held.dir, held.draw)
		_dot(ci, a.hand, 1.5, skin)  # fingers wrap over the handle


## Shirt with rounded shoulders, lit from the top-left.
static func _torso(ci: CanvasItem, view: int, shirt: Color, pants: Color, zombie: bool) -> void:
	var w := (3.0 if view == SIDE else 4.4) * _girth
	var top := shirt.lightened(0.08)
	var bot := shirt.darkened(0.25)
	_poly(ci, PackedVector2Array([Vector2(-w + 1.2, -20), Vector2(w - 1.2, -20), Vector2(w, -18.6),
			Vector2(w * 0.85, -10.2), Vector2(-w * 0.85, -10.2), Vector2(-w, -18.6)]),
			PackedColorArray([top, top, shirt, bot, bot, shirt]))
	_poly(ci, PackedVector2Array([Vector2(w * 0.35, -19.6), Vector2(w, -18.6), Vector2(w * 0.85, -10.2),
			Vector2(w * 0.3, -10.2)]), Color(0, 0, 0, 0.12))  # shadow side
	if view == FRONT:
		_polyline(ci, PackedVector2Array([Vector2(-1.5, -20), Vector2(0, -18.4), Vector2(1.5, -20)]), shirt.darkened(0.35), 0.6)
	_rect(ci, Rect2(-w * 0.85, -11.3, w * 1.7, 1.2), pants.darkened(0.35))  # belt
	if zombie and view != BACK:
		var hem := PackedVector2Array()
		for i in 7:
			hem.append(Vector2(-w * 0.85 + i * w * 1.7 / 6.0, -10.2 - (1.5 if i % 2 else 0.2)))
		_polyline(ci, hem, shirt.darkened(0.45), 0.9)  # ragged hem
		for p in [] if low_gore else [Vector2(w * 0.2, -15.5), Vector2(w * 0.45, -14.3), Vector2(w * 0.05, -13.6), Vector2(-w * 0.3, -16.4)]:
			_dot(ci, p, 0.9, Color(0.33, 0.05, 0.04, 0.8))  # dried blood


## Armour vest (or a hi-vis rider's vest) over the shirt: panel front and back.
static func _vest(ci: CanvasItem, view: int, v: Dictionary) -> void:
	var w := (3.2 if view == SIDE else 4.5) * _girth
	var col: Color = v.col
	var pts := PackedVector2Array([Vector2(-w + 1.6, -19.8), Vector2(-w * 0.35, -19.8), Vector2(-w * 0.2, -18.2),
			Vector2(w * 0.2, -18.2), Vector2(w * 0.35, -19.8), Vector2(w - 1.6, -19.8), Vector2(w, -18.2),
			Vector2(w * 0.88, -11.2), Vector2(-w * 0.88, -11.2), Vector2(-w, -18.2)])
	if view != FRONT:
		pts = PackedVector2Array([Vector2(-w + 1.4, -19.9), Vector2(w - 1.4, -19.9), Vector2(w, -18.2),
				Vector2(w * 0.88, -11.2), Vector2(-w * 0.88, -11.2), Vector2(-w, -18.2)])
	_poly(ci, pts, col)
	_polyline(ci, pts + PackedVector2Array([pts[0]]), col.darkened(0.35), 0.5)
	if v.get("plate", false):
		# Pouches and a light strip where the plate sits.
		_rect(ci, Rect2(-w * 0.7, -14.2, w * 1.4, 2.2), col.darkened(0.2))
		for i in 3:
			_line(ci, Vector2(-w * 0.7 + (i + 1) * w * 0.35, -14.2), Vector2(-w * 0.7 + (i + 1) * w * 0.35, -12.0), col.darkened(0.45), 0.4)
		_line(ci, Vector2(-w * 0.6, -18.0), Vector2(w * 0.6, -18.0), col.lightened(0.18), 0.5)
	else:
		# Hi-vis strips, like Bangkok's motorbike taxi vests.
		_line(ci, Vector2(-w * 0.9, -14.8), Vector2(w * 0.9, -14.8), Color("e8e4d0"), 0.8)
		_line(ci, Vector2(-w * 0.88, -12.6), Vector2(w * 0.88, -12.6), Color("e8e4d0"), 0.6)


## Backpack seen from the front (only the straps) or from behind (the whole bag).
static func _pack(ci: CanvasItem, view: int, p: Dictionary) -> void:
	var col: Color = p.col
	var big: bool = p.get("big", false)
	if view == FRONT:
		for sx in [-1.0, 1.0]:
			_line(ci, Vector2(2.9 * sx * _girth, -19.6), Vector2(2.6 * sx * _girth, -12.8), col.darkened(0.25), 1.0)
		return
	var h := 9.5 if big else 7.0
	var hw := (3.8 if big else 3.2)
	var r := Rect2(-hw, -19.8, hw * 2, h)
	_rect(ci, Rect2(r.position + Vector2(0.3, 0.6), r.size), Color(0, 0, 0, 0.25))
	_rect(ci, r, col)
	_rect(ci, Rect2(r.position, Vector2(r.size.x, 2.6)), col.darkened(0.18))  # flap
	_rect(ci, Rect2(-1.6, r.end.y - 3.6, 3.2, 2.4), col.darkened(0.12))  # front pocket
	_line(ci, Vector2(-hw, r.position.y + 2.6), Vector2(hw, r.position.y + 2.6), col.darkened(0.4), 0.4)
	if big:
		_rect(ci, Rect2(-hw - 0.4, -21.2, hw * 2 + 0.8, 1.6), Color("6a5a3a"))  # rolled mat on top


## Side view: the bag sits against the back, the strap crosses the shoulder.
static func _pack_side(ci: CanvasItem, p: Dictionary) -> void:
	var col: Color = p.col
	var big: bool = p.get("big", false)
	var h := 9.5 if big else 7.0
	var d := 3.4 if big else 2.6
	var x := -3.0 * _girth
	_rect(ci, Rect2(x - d, -19.8, d + 1.0, h), col.darkened(0.08))
	_rect(ci, Rect2(x - d, -19.8, d + 1.0, 2.2), col.darkened(0.22))
	if big:
		_rect(ci, Rect2(x - d - 0.2, -21.2, d + 1.4, 1.6), Color("6a5a3a"))


## Hats and helmets, over the hair.
static func _headwear(ci: CanvasItem, view: int, c: Vector2, h: Dictionary) -> void:
	var col: Color = h.col
	match h.shape:
		"helmet":
			# Open-face motorbike helmet: a shell over the crown, a visor rim, a chin strap.
			_poly(ci, _arc(c + Vector2(0, -0.5), 5.0, PI, TAU), col)
			_rect(ci, Rect2(c.x - 5.0, c.y - 0.9, 10.0, 1.2), col.darkened(0.12))
			_poly(ci, _arc(c + Vector2(-1.4, -2.6), 1.4, PI, TAU), col.lightened(0.3))  # shine
			if view == SIDE:
				_rect(ci, Rect2(c.x + 2.2, c.y - 1.6, 3.2, 0.9), Color("2a3036"))  # visor edge
				_line(ci, c + Vector2(-0.6, 0.2), c + Vector2(1.6, 3.8), Color("2a2a2a"), 0.4)
			elif view == FRONT:
				_rect(ci, Rect2(c.x - 3.8, c.y - 1.6, 7.6, 0.8), Color("2a3036"))
				for sx in [-1.0, 1.0]:
					_line(ci, c + Vector2(4.0 * sx, 0.2), c + Vector2(2.2 * sx, 3.8), Color("2a2a2a"), 0.4)
		"cap":
			_poly(ci, _arc(c + Vector2(0, -0.9), 4.5, PI, TAU), col)
			match view:
				FRONT:
					_rect(ci, Rect2(c.x - 3.6, c.y - 1.5, 7.2, 1.1), col.darkened(0.25))  # brim, from underneath
				SIDE:
					_rect(ci, Rect2(c.x + 2.4, c.y - 1.6, 3.8, 0.9), col.darkened(0.15))
				BACK:
					_rect(ci, Rect2(c.x - 1.2, c.y - 1.2, 2.4, 0.7), col.darkened(0.3))  # strap


## An arm, or what is left of it when it has been cut off.
static func _draw_arm_or_stump(ci: CanvasItem, a: Dictionary, lk: Dictionary, missing: int) -> void:
	var bit := LOST_ARM_L if a.get("idx", 0) == 0 else LOST_ARM_R
	if not missing & bit:
		_draw_arm(ci, a, lk)
		return
	# A short stump, just below the shoulder, so it never reaches across the body.
	var sh: Vector2 = a.sh
	var end: Vector2 = sh.lerp(a.elbow, 0.38)
	var sleeve: Color = (lk.shirt as Color).darkened(0.1 + a.dim)
	_limb(ci, sh, end, 3.4, 3.0, (lk.skin as Color).darkened(0.5))
	_limb(ci, sh, end, 3.0, 2.6, sleeve)
	_dot(ci, end, 1.3, (lk.skin as Color).darkened(0.35) if low_gore else BLOOD)
	if not a.behind and not low_gore:
		_dot(ci, end, 0.5, Color("d8d0c0"))  # bone


## Where the head was.
static func _neck_stump(ci: CanvasItem, skin: Color) -> void:
	_rect(ci, Rect2(-1.3, -21.4, 2.6, 2.2), skin.darkened(0.25))
	_dot(ci, Vector2(0, -21.4), 1.9, BLOOD)
	_dot(ci, Vector2(0, -21.5), 0.8, Color("d8d0c0"))  # spine
	_dot(ci, Vector2(0.6, -20.6), 0.5, BLOOD_DARK)


## Smashed in: the skull caves and blood runs out over it.
static func _crushed(ci: CanvasItem, c: Vector2) -> void:
	_poly(ci, PackedVector2Array([c + Vector2(-4.4, -1.2), c + Vector2(-2.6, -4.6), c + Vector2(-0.4, -2.4),
			c + Vector2(1.6, -4.8), c + Vector2(4.4, -1.6), c + Vector2(3.0, 0.8), c + Vector2(-3.2, 1.2)]), BLOOD)
	_dot(ci, c + Vector2(-0.8, -1.8), 1.4, BLOOD_DARK)
	_dot(ci, c + Vector2(1.8, -0.6), 0.9, BLOOD_DARK)
	_rect(ci, Rect2(c.x - 2.8, c.y + 1.0, 0.6, 3.0), BLOOD)  # running down the face
	_rect(ci, Rect2(c.x + 1.9, c.y + 1.4, 0.5, 2.2), BLOOD)


## Bites, gashes and an open ribcage, picked by `seed` so each zombie keeps its own.
static func _wounds(ci: CanvasItem, view: int, seed: int) -> void:
	if view == BACK and seed % 3 != 0:
		return
	var w := (3.0 if view == SIDE else 4.4) * _girth
	var spots := [Vector2(0.35, -16.5), Vector2(-0.45, -13.8), Vector2(0.1, -18.2), Vector2(-0.2, -12.4)]
	for i in seed % 4:  # a quarter of them show no wounds at all
		var p: Vector2 = spots[(seed + i) % spots.size()]
		var at := Vector2(p.x * w, p.y)
		_dot(ci, at, 1.3, BLOOD_DARK)
		_dot(ci, at + Vector2(-0.2, -0.2), 0.8, BLOOD)
	if seed % 7 == 3 and view != BACK:
		# Torn open: ribs showing through.
		var at := Vector2(-0.3 * w, -15.5)
		_rect(ci, Rect2(at - Vector2(1.6, 1.8), Vector2(3.2, 3.8)), BLOOD_DARK)
		for k in 3:
			_line(ci, at + Vector2(-1.4, -1.2 + k * 1.2), at + Vector2(1.4, -1.0 + k * 1.2), Color("c8bca8"), 0.45)


## Blood pumping out of a fresh stump, in arcs that fall away.
static func _spurt(ci: CanvasItem, r: Dictionary, missing: int, left: float, seed: int) -> void:
	var from := Vector2(0, -21.4) if missing & LOST_HEAD else (Vector2(0.6, -18.3) if missing & LOST_ARM_R else Vector2(-0.6, -18.6))
	var t := Time.get_ticks_msec() / 1000.0
	for i in 9:
		var k := fmod(t * 2.4 + i / 9.0 + seed * 0.13, 1.0)
		var spread := (fmod(i * 0.618 + seed * 0.31, 1.0) - 0.5) * 3.0
		var p := from + Vector2(spread * k * 2.0 - 3.0 * k, -7.0 * k * left + 14.0 * k * k)
		_dot(ci, p, (1.0 - k) * 1.1 + 0.3, Color(BLOOD, (1.0 - k) * minf(1.0, left * 2.0)))


static func _head(ci: CanvasItem, view: int, c: Vector2, skin: Color, hair: Color, style: String,
		zombie: bool, closed := false, hat := {}, mouth := 0.0, neck := true, drip := false) -> void:
	if neck:
		_rect(ci, Rect2(-1.2, -21, 2.4, 2), skin.darkened(0.25))  # neck
	_dot(ci, c, 4.2, skin.darkened(0.18))
	_dot(ci, c + Vector2(-0.4, -0.4), 3.7, skin)
	var eye := Color("e6e2c8") if zombie else Color("1c1612")
	if closed:
		eye = skin.darkened(0.45)  # eyes shut
	var dark := skin.darkened(0.4)
	if style == "bald" and hat.is_empty():
		_dot(ci, c + Vector2(-1.4, -2.2), 1.0, skin.lightened(0.18))  # shine on the scalp
	if not hat.is_empty():
		style = "buzz" if style in ["short", "buzz", "bald"] else style  # hat flattens the hair; long hair still shows
	match view:
		FRONT:
			if style == "long":
				_rect(ci, Rect2(c.x - 4.6, c.y - 1.5, 1.8, 6.2), hair.darkened(0.08))  # hair down to the shoulders
				_rect(ci, Rect2(c.x + 2.8, c.y - 1.5, 1.8, 6.2), hair.darkened(0.08))
			if style == "buzz":
				_poly(ci, _arc(c + Vector2(0, -0.3), 4.2, PI, TAU), hair.lerp(skin, 0.4))
			elif style != "bald":
				_poly(ci, _arc(c + Vector2(0, -0.6), 4.4, PI, TAU), hair)
				_rect(ci, Rect2(c.x - 4.3, c.y - 1, 1.2, 3), hair)  # sideburns
				_rect(ci, Rect2(c.x + 3.1, c.y - 1, 1.2, 3), hair)
			if not zombie:
				_rect(ci, Rect2(c.x - 2.3, c.y - 0.7, 1.6, 0.45), hair.darkened(0.2))  # brows
				_rect(ci, Rect2(c.x + 0.7, c.y - 0.7, 1.6, 0.45), hair.darkened(0.2))
			_dot(ci, c + Vector2(-1.5, 0.4), 0.6, eye)
			_dot(ci, c + Vector2(1.5, 0.4), 0.6, eye)
			_rect(ci, Rect2(c.x - 0.4, c.y + 0.8, 0.8, 1.0), skin.darkened(0.15))  # nose
			if zombie:
				_rect(ci, Rect2(c.x - 1.1 - mouth * 0.3, c.y + 2.2, 2.2 + mouth * 0.6, 1.0 + mouth * 1.4), Color("3a1a16"))
				if drip:
					_rect(ci, Rect2(c.x + 0.3, c.y + 3.1, 0.5, 1.8), BLOOD)  # blood down the chin
			else:
				_rect(ci, Rect2(c.x - 0.9, c.y + 2.3, 1.8, 0.45), dark)
		BACK:
			if style == "buzz":
				_dot(ci, c + Vector2(0, -0.2), 4.2, hair.lerp(skin, 0.4))
			elif style != "bald":
				_dot(ci, c + Vector2(0, -0.2), 4.3, hair)
				_rect(ci, Rect2(c.x - 2.5, c.y + 3.2, 5, 0.8), hair.darkened(0.15))  # nape
			if style == "long":
				_rect(ci, Rect2(c.x - 4.2, c.y, 8.4, 5.2), hair)
				_rect(ci, Rect2(c.x - 4.2, c.y + 4.4, 8.4, 0.8), hair.darkened(0.15))
			elif style == "ponytail":
				_dot(ci, c + Vector2(0, 1.6), 1.1, hair.darkened(0.3))  # hair tie
				_limb(ci, c + Vector2(0, 2.2), c + Vector2(0.3, 6.8), 2.2, 1.4, hair)
		SIDE:
			# Back and crown of the head; the hairline curves in behind the eye instead of cutting across it.
			if style == "long":
				_poly(ci, PackedVector2Array([c + Vector2(-4.4, -1), c + Vector2(-0.8, -1),
						c + Vector2(-0.6, 4.8), c + Vector2(-4.6, 5.2)]), hair.darkened(0.08))
			elif style == "ponytail":
				_limb(ci, c + Vector2(-4.0, -1.2), c + Vector2(-5.6, 4.2), 2.2, 1.4, hair)
				_dot(ci, c + Vector2(-4.0, -1.2), 1.0, hair.darkened(0.3))  # hair tie
			if style != "bald":
				var hp := _arc(c + Vector2(-0.4, -0.4), 4.4 if style != "buzz" else 4.2, PI * 0.55, PI * 1.78)
				hp.append(c + Vector2(1.2, -1.6))
				hp.append(c + Vector2(-0.6, -0.2))
				_poly(ci, hp, hair.lerp(skin, 0.4) if style == "buzz" else hair)
			_dot(ci, c + Vector2(-1.0, 0.6), 0.85, skin.darkened(0.12))  # ear, on the hairline
			if not zombie:
				_rect(ci, Rect2(c.x + 1.6, c.y - 0.9, 1.6, 0.45), hair.darkened(0.2))  # brow
			_dot(ci, c + Vector2(2.4, 0.3), 0.55, eye)
			_dot(ci, c + Vector2(4.0, 1.0), 0.75, skin)  # nose
			_rect(ci, Rect2(c.x + 2.3, c.y + 2.3, 1.3 + mouth * 0.4, 0.45 + mouth * 1.3), Color("3a1a16") if zombie else dark)
			if zombie and drip:
				_rect(ci, Rect2(c.x + 2.8, c.y + 2.8, 0.45, 1.6), BLOOD)
	if not hat.is_empty():
		_headwear(ci, view, c, hat)


static func _arc(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 13:
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, i / 12.0)) * r)
	return pts


## Weapon angle (relative to the aim) through a swing, t in 0..1: cock back
## over the shoulder, whip through, follow through, then return to the ready pose.
static func swing_angle(t: float) -> float:
	if t < 0.3:
		return lerpf(-1.1, -2.3, t / 0.3)
	if t < 0.55:
		return lerpf(-2.3, 0.9, ease((t - 0.3) / 0.25, 0.5))
	if t < 0.7:
		return 0.9
	return lerpf(0.9, -1.1, (t - 0.7) / 0.3)


## A melee weapon gripped at `hand`, pointing along `dv`.
static func _draw_weapon(ci: CanvasItem, hand: Vector2, dv: Vector2, w: Dictionary) -> void:
	var L: float = w.len
	var col: Color = w.col
	var n := dv.orthogonal()
	var butt := hand - dv * 2.0
	var tip := hand + dv * L
	var dark := Color("2a2420")
	match w.kind:
		"plank":
			_limb(ci, butt, tip, 2.3, 2.5, col)
			_line(ci, butt + n * 0.4, tip + n * 0.4, col.lightened(0.15), 0.4)
			for k in 2:
				_line(ci, tip - dv * (1.5 + k * 2.0), tip - dv * (1.5 + k * 2.0) + n * 2.0, Color("9a9a9a"), 0.5)  # nails
		"bat":
			_limb(ci, butt, tip, 1.2, 2.7, col)
			_limb(ci, butt, hand + dv * 1.5, 1.4, 1.4, dark)  # grip tape
		"pipe":
			_limb(ci, butt, tip, 1.8, 1.8, col)
			_line(ci, butt + n * 0.4, tip + n * 0.4, col.lightened(0.3), 0.5)
		"knife":
			_limb(ci, butt, hand + dv * 1.6, 1.7, 1.7, dark)
			_poly(ci, PackedVector2Array([hand + dv * 1.6 + n * 0.9, tip, hand + dv * 1.6 - n * 0.5]), col)
		"machete":
			_limb(ci, butt, hand + dv * 1.8, 1.8, 1.8, dark)
			_poly(ci, PackedVector2Array([hand + dv * 1.8 + n * 1.0, tip - dv * 1.5 + n * 1.4, tip,
					hand + dv * 1.8 - n * 0.6]), col)
			_line(ci, hand + dv * 2.0 + n * 0.9, tip - dv * 1.5 + n * 1.3, col.lightened(0.3), 0.4)
		"axe":
			_limb(ci, butt, tip, 1.4, 1.4, Color("8a6a44"))
			_poly(ci, PackedVector2Array([tip - dv * 3.5 + n * 0.6, tip - dv * 4.5 + n * 4.0,
					tip + dv * 0.5 + n * 4.2, tip + n * 0.6]), col)
			_line(ci, tip - dv * 4.5 + n * 4.0, tip + dv * 0.5 + n * 4.2, col.lightened(0.35), 0.6)  # edge
		"hammer":
			_limb(ci, butt, tip, 1.4, 1.4, Color("8a6a44"))
			_poly(ci, PackedVector2Array([tip - dv * 1.3 - n * 2.4, tip - dv * 1.3 + n * 2.6,
					tip + dv * 1.3 + n * 2.6, tip + dv * 1.3 - n * 2.4]), col)


static func draw_hp(ci: CanvasItem, frac: float) -> void:
	if frac >= 1.0:
		return
	_rect(ci, Rect2(-6, -33, 12, 2), Color(0.3, 0, 0, 0.8))
	_rect(ci, Rect2(-6, -33, 12 * frac, 2), Color("7ad15a"))


## A soft cone plus a small halo, used as the flashlight's light texture.
static func cone_texture() -> Texture2D:
	if _cone:
		return _cone
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2, s / 2)
	for y in s:
		for x in s:
			var d := Vector2(x, y) - c
			var dist := d.length() / (s / 2)
			var a := 0.0
			if dist < 1.0:
				var cone := clampf((0.42 - absf(d.angle())) / 0.18, 0.0, 1.0)
				a = cone * pow(1.0 - dist, 0.7) + clampf(1.0 - dist * 7.0, 0.0, 1.0) * 0.6
			a = clampf(a, 0.0, 1.0)
			img.set_pixel(x, y, Color(a, a, a, a))
	_cone = ImageTexture.create_from_image(img)
	return _cone
