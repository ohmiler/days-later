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

const CHEST := Vector2(0, -15)  # where guns and flashlights sit
const HEAD := Vector2(0, -24)

enum { FRONT, BACK, SIDE }
enum { NONE, PUNCH_L, PUNCH_R, KICK, SWING }  # attack poses

static var _cone: Texture2D
static var _base := Transform2D.IDENTITY
static var _girth := 1.0  # body width multiplier (fat and skinny zombies)
static var lift := Vector2.ZERO  # draw everything this far up (standing on a roof); caller sets and resets  # whole-body transform (used to topple a falling body)
static var _font: Font


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
	var sx: float = r.sx
	var tip: float = r.tip
	var pants: Color = lk.pants
	var shoe: Color = lk.get("shoes", SHOE)
	# Contact shadow, stretching out under the body as it falls.
	ci.draw_set_transform(lift + Vector2(r.fall_dir * 12.0 * tip, 0), 0, Vector2(1 + 1.6 * tip, 0.38))
	ci.draw_circle(Vector2.ZERO, 7.5, Color(0, 0, 0, 0.35))

	# Legs stay planted; everything above them bobs.
	_xf(ci, Vector2.ZERO, Vector2(sx, 1))
	for leg in r.legs:
		_draw_leg(ci, leg, pants, shoe)
	ci.draw_rect(Rect2(-3.3, -11.5, 6.6, 2.6), pants.darkened(0.06))  # hips join the legs to the body

	_xf(ci, r.upper, Vector2(sx, 1))
	for a in r.arms_back:
		_draw_arm(ci, a, lk)
	_torso(ci, r.view, lk.shirt, pants, r.zombie)
	_head(ci, r.view, r.head, lk.skin, lk.hair, lk.get("hair_style", "short"), r.zombie, r.closed)
	for a in r.arms_front:
		_draw_arm(ci, a, lk)
	if not r.front_kick.is_empty():
		_xf(ci, Vector2.ZERO, Vector2(sx, 1))
		_front_kick_leg(ci, r.front_kick, pants, shoe)
	ci.draw_set_transform(Vector2.ZERO)


const SHOE := Color("1e1a16")


## Set the drawing transform for a body part, on top of the whole-body transform.
static func _xf(ci: CanvasItem, pos: Vector2, scale: Vector2) -> void:
	ci.draw_set_transform_matrix(Transform2D(0.0, lift) * _base * Transform2D(0.0, scale, 0.0, pos))


## Pool of blood spreading from a body lying toward `dir` (k grows 0..1 over time).
static func draw_blood_pool(ci: CanvasItem, dir: float, k: float) -> void:
	ci.draw_set_transform(Vector2(dir * 12.0, -0.5), 0, Vector2(1.3, 0.45))
	ci.draw_circle(Vector2.ZERO, 3.0 + 9.0 * k, Color(0.28, 0.02, 0.02, 0.75))
	ci.draw_circle(Vector2(dir * 3.0, 0), 2.0 + 5.0 * k, Color(0.2, 0.01, 0.01, 0.8))
	ci.draw_set_transform(Vector2.ZERO)


static func _draw_leg(ci: CanvasItem, leg: Dictionary, pants: Color, shoe: Color) -> void:
	var col := pants.darkened(0.18) if leg.far else pants
	match leg.type:
		"rect":
			_leg_rect(ci, leg.x, leg.lift, col, shoe)
		"line":
			_leg_line(ci, leg.hip, leg.foot, col, shoe)
		"limb":
			var side: bool = leg.shoe == "side_kick"
			var w := [3.1, 2.8, 2.4] if side else [3.2, 2.9, 2.5]
			_limb(ci, leg.hip, leg.knee, w[0], w[1], col)
			_limb(ci, leg.knee, leg.foot, w[1], w[2], col)
			var foot: Vector2 = leg.foot
			var e: float = leg.e
			if side:
				# Shoe turns from toes-forward (chambered) to sole-first (extended).
				var toe := Vector2(2.6, 0.2).lerp(Vector2(0.4, -2.6), e)
				_limb(ci, foot + Vector2(-0.6, 0.4).lerp(Vector2(0.4, 1.3), e), foot + toe, 2.1, 2.0, shoe)
			else:
				ci.draw_rect(Rect2(foot + Vector2(-1.6, -1.0), Vector2(3.2, 2.0)), shoe)


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
static func _front_kick_leg(ci: CanvasItem, k: Dictionary, pants: Color, shoe: Color) -> void:
	var foot: Vector2 = k.foot
	var e: float = k.e
	var lit := pants.lightened(0.06)  # nearer the camera, catches more light
	_limb(ci, k.hip, k.knee, 3.3, 3.1, lit)
	_limb(ci, k.knee, foot, 3.1, 2.7, lit)
	var size := Vector2(3.2, 2.0) + Vector2(2.0, 2.6) * e
	var sole := Rect2(foot - Vector2(size.x * 0.5, size.y * 0.5), size)
	ci.draw_rect(sole, shoe)
	for i in 3:  # tread lines on the sole
		var y := sole.position.y + (i + 1) * sole.size.y / 4.0
		ci.draw_line(Vector2(sole.position.x + 0.5, y), Vector2(sole.end.x - 0.5, y), shoe.lightened(0.18), 0.4)


## Front/back leg: straight down, lifted by `lift` mid-stride.
static func _leg_rect(ci: CanvasItem, x: float, up: float, pants: Color, shoe: Color) -> void:
	ci.draw_rect(Rect2(x, -10.5, 2.8, 10.5 - up - 1.7), pants)
	ci.draw_rect(Rect2(x - 0.3, -up - 1.9, 3.4, 1.9), shoe)


## Side leg from hip to foot with a slight forward knee; the shoe points forward.
static func _leg_line(ci: CanvasItem, hip: Vector2, foot: Vector2, pants: Color, shoe: Color) -> void:
	var knee := hip.lerp(foot, 0.5) + Vector2(0.8, 0)
	ci.draw_line(hip, knee, pants, 2.9)
	ci.draw_line(knee, foot + Vector2(0, -1.4), pants, 2.6)
	ci.draw_rect(Rect2(foot + Vector2(-1.3, -1.9), Vector2(3.8, 1.9)), shoe)


## A tapered limb segment with round ends, like a capsule.
static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, wa: float, wb: float, col: Color) -> void:
	var n := (b - a).orthogonal().normalized()
	if n == Vector2.ZERO:
		n = Vector2.RIGHT
	ci.draw_colored_polygon(PackedVector2Array([a + n * wa * 0.5, b + n * wb * 0.5, b - n * wb * 0.5, a - n * wa * 0.5]), col)
	ci.draw_circle(a, wa * 0.5, col)
	ci.draw_circle(b, wb * 0.5, col)


## One arm: short sleeve over the shoulder, bare forearm, closed hand. A dark
## outline pass first keeps the arm readable against the body behind it.
static func _arm(ci: CanvasItem, sh: Vector2, elbow: Vector2, hand: Vector2, sleeve: Color, skin: Color,
		fist := false) -> void:
	var line := skin.darkened(0.45)
	var cuff := sh.lerp(elbow, 0.75)
	_limb(ci, sh, elbow, 3.6, 3.0, line)
	_limb(ci, elbow, hand, 3.0, 2.6, line)
	ci.draw_circle(hand, 2.1 if fist else 1.8, line)
	_limb(ci, elbow, hand, 2.2, 1.8, skin)  # forearm
	_limb(ci, cuff, elbow, 2.3, 2.2, skin.darkened(0.05))
	_limb(ci, sh, cuff, 3.0, 2.8, sleeve)  # sleeve
	ci.draw_circle(hand, 1.5 if fist else 1.2, skin)
	if fist:
		ci.draw_circle(hand + Vector2(-0.4, -0.4), 0.6, skin.lightened(0.15))  # knuckle highlight


## One arm from the rig, plus anything held in its hand.
static func _draw_arm(ci: CanvasItem, a: Dictionary, lk: Dictionary) -> void:
	var dim: float = a.dim
	var skin: Color = (lk.skin as Color).darkened(a.skin_dark).darkened(dim)
	var sleeve: Color = (lk.shirt as Color).darkened(a.sleeve_dark).darkened(a.get("sleeve_dim", dim))
	var held: Dictionary = a.weapon
	if not held.is_empty() and not held.trail.is_empty():
		ci.draw_polyline(held.trail, Color(1, 1, 1, 0.35), 1.6)
	_arm(ci, a.sh, a.elbow, a.hand, sleeve, skin, a.fist)
	if a.big_hand:
		ci.draw_circle(a.hand, 1.7, skin)
	if not held.is_empty():
		_draw_weapon(ci, a.hand, held.dir, held.draw)
		ci.draw_circle(a.hand, 1.5, skin)  # fingers wrap over the handle


## Shirt with rounded shoulders, lit from the top-left.
static func _torso(ci: CanvasItem, view: int, shirt: Color, pants: Color, zombie: bool) -> void:
	var w := (3.0 if view == SIDE else 4.4) * _girth
	var top := shirt.lightened(0.08)
	var bot := shirt.darkened(0.25)
	ci.draw_polygon(PackedVector2Array([Vector2(-w + 1.2, -20), Vector2(w - 1.2, -20), Vector2(w, -18.6),
			Vector2(w * 0.85, -10.2), Vector2(-w * 0.85, -10.2), Vector2(-w, -18.6)]),
			PackedColorArray([top, top, shirt, bot, bot, shirt]))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.35, -19.6), Vector2(w, -18.6), Vector2(w * 0.85, -10.2),
			Vector2(w * 0.3, -10.2)]), Color(0, 0, 0, 0.12))  # shadow side
	if view == FRONT:
		ci.draw_polyline(PackedVector2Array([Vector2(-1.5, -20), Vector2(0, -18.4), Vector2(1.5, -20)]), shirt.darkened(0.35), 0.6)
	ci.draw_rect(Rect2(-w * 0.85, -11.3, w * 1.7, 1.2), pants.darkened(0.35))  # belt
	if zombie and view != BACK:
		var hem := PackedVector2Array()
		for i in 7:
			hem.append(Vector2(-w * 0.85 + i * w * 1.7 / 6.0, -10.2 - (1.5 if i % 2 else 0.2)))
		ci.draw_polyline(hem, shirt.darkened(0.45), 0.9)  # ragged hem
		for p in [Vector2(w * 0.2, -15.5), Vector2(w * 0.45, -14.3), Vector2(w * 0.05, -13.6), Vector2(-w * 0.3, -16.4)]:
			ci.draw_circle(p, 0.9, Color(0.33, 0.05, 0.04, 0.8))  # dried blood


static func _head(ci: CanvasItem, view: int, c: Vector2, skin: Color, hair: Color, style: String,
		zombie: bool, closed := false) -> void:
	ci.draw_rect(Rect2(-1.2, -21, 2.4, 2), skin.darkened(0.25))  # neck
	ci.draw_circle(c, 4.2, skin.darkened(0.18))
	ci.draw_circle(c + Vector2(-0.4, -0.4), 3.7, skin)
	var eye := Color("e6e2c8") if zombie else Color("1c1612")
	if closed:
		eye = skin.darkened(0.45)  # eyes shut
	var dark := skin.darkened(0.4)
	if style == "bald":
		ci.draw_circle(c + Vector2(-1.4, -2.2), 1.0, skin.lightened(0.18))  # shine on the scalp
	match view:
		FRONT:
			if style == "long":
				ci.draw_rect(Rect2(c.x - 4.6, c.y - 1.5, 1.8, 6.2), hair.darkened(0.08))  # hair down to the shoulders
				ci.draw_rect(Rect2(c.x + 2.8, c.y - 1.5, 1.8, 6.2), hair.darkened(0.08))
			if style == "buzz":
				ci.draw_colored_polygon(_arc(c + Vector2(0, -0.3), 4.2, PI, TAU), hair.lerp(skin, 0.4))
			elif style != "bald":
				ci.draw_colored_polygon(_arc(c + Vector2(0, -0.6), 4.4, PI, TAU), hair)
				ci.draw_rect(Rect2(c.x - 4.3, c.y - 1, 1.2, 3), hair)  # sideburns
				ci.draw_rect(Rect2(c.x + 3.1, c.y - 1, 1.2, 3), hair)
			if not zombie:
				ci.draw_rect(Rect2(c.x - 2.3, c.y - 0.7, 1.6, 0.45), hair.darkened(0.2))  # brows
				ci.draw_rect(Rect2(c.x + 0.7, c.y - 0.7, 1.6, 0.45), hair.darkened(0.2))
			ci.draw_circle(c + Vector2(-1.5, 0.4), 0.6, eye)
			ci.draw_circle(c + Vector2(1.5, 0.4), 0.6, eye)
			ci.draw_rect(Rect2(c.x - 0.4, c.y + 0.8, 0.8, 1.0), skin.darkened(0.15))  # nose
			if zombie:
				ci.draw_rect(Rect2(c.x - 1.1, c.y + 2.2, 2.2, 1.0), Color("3a1a16"))
			else:
				ci.draw_rect(Rect2(c.x - 0.9, c.y + 2.3, 1.8, 0.45), dark)
		BACK:
			if style == "buzz":
				ci.draw_circle(c + Vector2(0, -0.2), 4.2, hair.lerp(skin, 0.4))
			elif style != "bald":
				ci.draw_circle(c + Vector2(0, -0.2), 4.3, hair)
				ci.draw_rect(Rect2(c.x - 2.5, c.y + 3.2, 5, 0.8), hair.darkened(0.15))  # nape
			if style == "long":
				ci.draw_rect(Rect2(c.x - 4.2, c.y, 8.4, 5.2), hair)
				ci.draw_rect(Rect2(c.x - 4.2, c.y + 4.4, 8.4, 0.8), hair.darkened(0.15))
			elif style == "ponytail":
				ci.draw_circle(c + Vector2(0, 1.6), 1.1, hair.darkened(0.3))  # hair tie
				_limb(ci, c + Vector2(0, 2.2), c + Vector2(0.3, 6.8), 2.2, 1.4, hair)
		SIDE:
			# Back and crown of the head; the hairline curves in behind the eye instead of cutting across it.
			if style == "long":
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4.4, -1), c + Vector2(-0.8, -1),
						c + Vector2(-0.6, 4.8), c + Vector2(-4.6, 5.2)]), hair.darkened(0.08))
			elif style == "ponytail":
				_limb(ci, c + Vector2(-4.0, -1.2), c + Vector2(-5.6, 4.2), 2.2, 1.4, hair)
				ci.draw_circle(c + Vector2(-4.0, -1.2), 1.0, hair.darkened(0.3))  # hair tie
			if style != "bald":
				var hp := _arc(c + Vector2(-0.4, -0.4), 4.4 if style != "buzz" else 4.2, PI * 0.55, PI * 1.78)
				hp.append(c + Vector2(1.2, -1.6))
				hp.append(c + Vector2(-0.6, -0.2))
				ci.draw_colored_polygon(hp, hair.lerp(skin, 0.4) if style == "buzz" else hair)
			ci.draw_circle(c + Vector2(-1.0, 0.6), 0.85, skin.darkened(0.12))  # ear, on the hairline
			if not zombie:
				ci.draw_rect(Rect2(c.x + 1.6, c.y - 0.9, 1.6, 0.45), hair.darkened(0.2))  # brow
			ci.draw_circle(c + Vector2(2.4, 0.3), 0.55, eye)
			ci.draw_circle(c + Vector2(4.0, 1.0), 0.75, skin)  # nose
			ci.draw_rect(Rect2(c.x + 2.3, c.y + 2.3, 1.3, 0.45), Color("3a1a16") if zombie else dark)


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
			ci.draw_line(butt + n * 0.4, tip + n * 0.4, col.lightened(0.15), 0.4)
			for k in 2:
				ci.draw_line(tip - dv * (1.5 + k * 2.0), tip - dv * (1.5 + k * 2.0) + n * 2.0, Color("9a9a9a"), 0.5)  # nails
		"bat":
			_limb(ci, butt, tip, 1.2, 2.7, col)
			_limb(ci, butt, hand + dv * 1.5, 1.4, 1.4, dark)  # grip tape
		"pipe":
			_limb(ci, butt, tip, 1.8, 1.8, col)
			ci.draw_line(butt + n * 0.4, tip + n * 0.4, col.lightened(0.3), 0.5)
		"knife":
			_limb(ci, butt, hand + dv * 1.6, 1.7, 1.7, dark)
			ci.draw_colored_polygon(PackedVector2Array([hand + dv * 1.6 + n * 0.9, tip, hand + dv * 1.6 - n * 0.5]), col)
		"machete":
			_limb(ci, butt, hand + dv * 1.8, 1.8, 1.8, dark)
			ci.draw_colored_polygon(PackedVector2Array([hand + dv * 1.8 + n * 1.0, tip - dv * 1.5 + n * 1.4, tip,
					hand + dv * 1.8 - n * 0.6]), col)
			ci.draw_line(hand + dv * 2.0 + n * 0.9, tip - dv * 1.5 + n * 1.3, col.lightened(0.3), 0.4)
		"axe":
			_limb(ci, butt, tip, 1.4, 1.4, Color("8a6a44"))
			ci.draw_colored_polygon(PackedVector2Array([tip - dv * 3.5 + n * 0.6, tip - dv * 4.5 + n * 4.0,
					tip + dv * 0.5 + n * 4.2, tip + n * 0.6]), col)
			ci.draw_line(tip - dv * 4.5 + n * 4.0, tip + dv * 0.5 + n * 4.2, col.lightened(0.35), 0.6)  # edge
		"hammer":
			_limb(ci, butt, tip, 1.4, 1.4, Color("8a6a44"))
			ci.draw_colored_polygon(PackedVector2Array([tip - dv * 1.3 - n * 2.4, tip - dv * 1.3 + n * 2.6,
					tip + dv * 1.3 + n * 2.6, tip + dv * 1.3 - n * 2.4]), col)


static func draw_hp(ci: CanvasItem, frac: float) -> void:
	if frac >= 1.0:
		return
	ci.draw_rect(Rect2(-6, -33, 12, 2), Color(0.3, 0, 0, 0.8))
	ci.draw_rect(Rect2(-6, -33, 12 * frac, 2), Color("7ad15a"))


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
