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

const CHEST := Vector2(0, -15)  # where guns and flashlights sit
const HEAD := Vector2(0, -24)

enum { FRONT, BACK, SIDE }
enum { NONE, PUNCH_L, PUNCH_R, KICK, SWING }  # attack poses

static var _cone: Texture2D
static var _base := Transform2D.IDENTITY
static var _girth := 1.0  # body width multiplier (fat and skinny zombies)  # whole-body transform (used to topple a falling body)
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


static func draw_human(ci: CanvasItem, vf: Array, angle: float, phase: float, moving: bool,
		skin: Color, shirt: Color, pants: Color, hair: Color, zombie: bool,
		attack: int = NONE, ext: float = 0.0, armed: bool = false, guard: bool = false,
		recoil := Vector2.ZERO, weapon: Dictionary = {}, fall := 0.0, fall_dir := 1.0, girth := 1.0) -> void:
	_girth = girth
	# Dying: knees buckle, then the body topples like a plank around the feet
	# (accelerating as it goes) and settles with a small bounce.
	var sink := 0.0
	var tip := 0.0
	if fall > 0.0:
		vf = [SIDE, fall_dir > 0]  # seen side-on, falling backwards
		moving = false
		attack = NONE
		weapon = {}
		sink = 3.0 * clampf(fall / 0.25, 0, 1)
		var u := clampf((fall - 0.25) / 0.75, 0, 1)
		tip = u * u
		var bounce := sin(clampf((u - 0.85) / 0.15, 0, 1) * PI) * 0.08
		_base = Transform2D(fall_dir * PI * 0.5 * (tip - bounce), Vector2(0, -2.0 * tip))
	else:
		_base = Transform2D.IDENTITY
	var view: int = vf[0]
	var sx := -1.0 if vf[1] else 1.0
	var s := sin(phase) if moving else 0.0  # walk cycle, -1..1
	var bob := absf(s) * 1.0
	if zombie and moving:
		bob += maxf(0.0, sin(phase * 0.5)) * 0.8  # limp

	# Contact shadow, stretching out under the body as it falls.
	ci.draw_set_transform(Vector2(fall_dir * 12.0 * tip, 0), 0, Vector2(1 + 1.6 * tip, 0.38))
	ci.draw_circle(Vector2.ZERO, 7.5, Color(0, 0, 0, 0.35))

	# Legs stay planted; everything above them bobs.
	_xf(ci, Vector2.ZERO, Vector2(sx, 1))
	_legs(ci, view, s, angle, sx, pants, attack, ext)

	var lean := 1.2 if zombie and view == SIDE else 0.0
	# Punches lunge the upper body into the blow; getting hit rocks it back.
	var lunge := Vector2.from_angle(angle) * Vector2(1.6, 1.0) * ext if attack in [PUNCH_L, PUNCH_R] else Vector2.ZERO
	if attack == KICK:
		var k := kick_pose(ext)
		lunge = -Vector2.from_angle(angle) * Vector2(1.4, 0.7) * k.y + Vector2(0, 0.7 * k.x)
	_xf(ci, Vector2(lean * sx, -bob + sink * (1.0 - tip)) + lunge + recoil, Vector2(sx, 1))
	# Fists come up when fighting; otherwise arms hang and swing with the walk.
	var fists := not zombie and (attack != NONE or guard or armed or not weapon.is_empty())
	# A falling body's arms go limp, even a zombie's.
	var reaching := zombie and fall <= 0.0
	if reaching:
		_zombie_arms(ci, view, skin, shirt, phase, true)
	elif fists:
		_player_arms(ci, view, angle, sx, skin, shirt, attack, ext, armed, true, weapon)
	else:
		_idle_arms(ci, view, s, skin, shirt, true)
	_torso(ci, view, shirt, pants, zombie)
	_head(ci, view, skin, hair, zombie, fall >= 1.0)
	if reaching:
		_zombie_arms(ci, view, skin, shirt, phase, false)
	elif fists:
		_player_arms(ci, view, angle, sx, skin, shirt, attack, ext, armed, false, weapon)
	else:
		_idle_arms(ci, view, s, skin, shirt, false)
	if attack == KICK and view == FRONT:
		_xf(ci, Vector2.ZERO, Vector2(sx, 1))
		_front_kick_leg(ci, angle, sx, pants, ext)
	ci.draw_set_transform(Vector2.ZERO)


const SHOE := Color("1e1a16")


## Set the drawing transform for a body part, on top of the whole-body transform.
static func _xf(ci: CanvasItem, pos: Vector2, scale: Vector2) -> void:
	ci.draw_set_transform_matrix(_base * Transform2D(0.0, scale, 0.0, pos))


## Pool of blood spreading from a body lying toward `dir` (k grows 0..1 over time).
static func draw_blood_pool(ci: CanvasItem, dir: float, k: float) -> void:
	ci.draw_set_transform(Vector2(dir * 12.0, -0.5), 0, Vector2(1.3, 0.45))
	ci.draw_circle(Vector2.ZERO, 3.0 + 9.0 * k, Color(0.28, 0.02, 0.02, 0.75))
	ci.draw_circle(Vector2(dir * 3.0, 0), 2.0 + 5.0 * k, Color(0.2, 0.01, 0.01, 0.8))
	ci.draw_set_transform(Vector2.ZERO)


static func _legs(ci: CanvasItem, view: int, s: float, angle: float, sx: float, pants: Color,
		attack: int, ext: float) -> void:
	var far := pants.darkened(0.18)
	if attack == KICK:
		_kick_legs(ci, view, angle, sx, pants, far, ext)
	elif view == SIDE:
		# Pendulum legs from the hip; whichever foot swings forward lifts a little.
		_leg_line(ci, Vector2(-0.3, -10), Vector2(-0.3 - s * 4.0, -maxf(0.0, -s) * 1.5), far)
		_leg_line(ci, Vector2(0.3, -10), Vector2(0.3 + s * 4.0, -maxf(0.0, s) * 1.5), pants)
	else:
		_leg_rect(ci, -3.1, maxf(0.0, s) * 2.2, pants)
		_leg_rect(ci, 0.3, maxf(0.0, -s) * 2.2, pants)
	ci.draw_rect(Rect2(-3.3, -11.5, 6.6, 2.6), pants.darkened(0.06))  # hips join the legs to the body


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


static func _kick_legs(ci: CanvasItem, view: int, angle: float, sx: float, pants: Color, far: Color, t: float) -> void:
	var k := kick_pose(t)
	var c := k.x
	var e := k.y
	var d := _local_dir(angle, sx)
	if view == SIDE:
		# Standing leg braces back a little as the weight shifts.
		_leg_line(ci, Vector2(-0.3, -10), Vector2(-1.8 * c, 0), far)
		var hip := Vector2(0.6, -10)
		var knee := (hip + Vector2(0.8, 5)).lerp(hip + Vector2(5.5, -2.5), c).lerp(hip + Vector2(6.2, -1.2 + d.y * 2.5), e)
		var foot := (hip + Vector2(0, 10)).lerp(hip + Vector2(4.0, 3.5), c).lerp(hip + Vector2(12.5, -1.0 + d.y * 5.0), e)
		_limb(ci, hip, knee, 3.1, 2.8, pants)
		_limb(ci, knee, foot, 2.8, 2.4, pants)
		# Shoe turns from toes-forward (chambered) to sole-first (extended).
		var toe := Vector2(2.6, 0.2).lerp(Vector2(0.4, -2.6), e)
		_limb(ci, foot + Vector2(-0.6, 0.4).lerp(Vector2(0.4, 1.3), e), foot + toe, 2.1, 2.0, SHOE)
	elif view == FRONT:
		_leg_rect(ci, -3.1, 0.0, far)  # standing leg; the kicking leg is drawn over the body later
	else:
		# Kicking away from the camera: the leg drives up the screen, mostly behind the body.
		_leg_rect(ci, -3.1, 0.0, far)
		var hip := Vector2(1.7, -10)
		var knee := (hip + Vector2(0.3, 5)).lerp(hip + Vector2(0.8, 1.0), c).lerp(hip + Vector2(0.6 + d.x * 1.5, 2.0), e)
		var foot := (hip + Vector2(0, 10)).lerp(hip + Vector2(0.6, 5.0), c).lerp(hip + Vector2(2.0 + d.x * 3.5, -2.0), e)
		_limb(ci, hip, knee, 3.2, 2.9, pants)
		_limb(ci, knee, foot, 2.9, 2.5, pants)
		ci.draw_rect(Rect2(foot + Vector2(-1.6, -1.0), Vector2(3.2, 2.0)), SHOE)


## Front kick toward the camera: the knee rises in front of the belly, then the
## foot drives out at the viewer, sole growing as it comes closer.
static func _front_kick_leg(ci: CanvasItem, angle: float, sx: float, pants: Color, t: float) -> void:
	var k := kick_pose(t)
	var c := k.x
	var e := k.y
	var d := _local_dir(angle, sx)
	var hip := Vector2(1.7, -10.5)
	var knee := (hip + Vector2(0.3, 5)).lerp(hip + Vector2(0.8, -3.5), c).lerp(hip + Vector2(0.6 + d.x * 1.5, -1.0), e)
	var foot := (hip + Vector2(0, 10)).lerp(hip + Vector2(0.6, 2.5), c).lerp(hip + Vector2(d.x * 3.5, 3.0), e)
	var lit := pants.lightened(0.06)  # nearer the camera, catches more light
	_limb(ci, hip, knee, 3.3, 3.1, lit)
	_limb(ci, knee, foot, 3.1, 2.7, lit)
	var size := Vector2(3.2, 2.0) + Vector2(2.0, 2.6) * e
	var sole := Rect2(foot - Vector2(size.x * 0.5, size.y * 0.5), size)
	ci.draw_rect(sole, SHOE)
	for i in 3:  # tread lines on the sole
		var y := sole.position.y + (i + 1) * sole.size.y / 4.0
		ci.draw_line(Vector2(sole.position.x + 0.5, y), Vector2(sole.end.x - 0.5, y), SHOE.lightened(0.18), 0.4)


## Front/back leg: straight down, lifted by `lift` mid-stride.
static func _leg_rect(ci: CanvasItem, x: float, lift: float, pants: Color) -> void:
	ci.draw_rect(Rect2(x, -10.5, 2.8, 10.5 - lift - 1.7), pants)
	ci.draw_rect(Rect2(x - 0.3, -lift - 1.9, 3.4, 1.9), SHOE)


## Side leg from hip to foot with a slight forward knee; the shoe points forward.
static func _leg_line(ci: CanvasItem, hip: Vector2, foot: Vector2, pants: Color) -> void:
	var knee := hip.lerp(foot, 0.5) + Vector2(0.8, 0)
	ci.draw_line(hip, knee, pants, 2.9)
	ci.draw_line(knee, foot + Vector2(0, -1.4), pants, 2.6)
	ci.draw_rect(Rect2(foot + Vector2(-1.3, -1.9), Vector2(3.8, 1.9)), SHOE)


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


## Relaxed arms, swinging opposite to the legs.
static func _idle_arms(ci: CanvasItem, view: int, s: float, skin: Color, shirt: Color, behind: bool) -> void:
	var sleeve := shirt.darkened(0.05)
	if view == SIDE:
		var sw := s if behind else -s
		var sh := Vector2(0.3, -18.4)
		var elbow := sh + Vector2(sw * 1.8, 4.3)
		var hand := elbow + Vector2(sw * 2.4 + 0.6, 3.9)
		if behind:
			_arm(ci, sh, elbow, hand, sleeve.darkened(0.25), skin.darkened(0.25))
		else:
			_arm(ci, sh, elbow, hand, sleeve, skin)
	elif not behind:
		for side in [-1.0, 1.0]:
			var sh := Vector2(4.0 * side, -18.6)
			var elbow := Vector2(4.9 * side, -14.6)
			var hand := Vector2(5.0 * side, -10.9 + s * side * 1.3)
			_arm(ci, sh, elbow, hand, sleeve, skin)


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


static func _head(ci: CanvasItem, view: int, skin: Color, hair: Color, zombie: bool, closed := false) -> void:
	var c := HEAD + (Vector2(0.7, 0.4) if zombie else Vector2.ZERO)  # zombies tilt their head
	ci.draw_rect(Rect2(-1.2, -21, 2.4, 2), skin.darkened(0.25))  # neck
	ci.draw_circle(c, 4.2, skin.darkened(0.18))
	ci.draw_circle(c + Vector2(-0.4, -0.4), 3.7, skin)
	var eye := Color("e6e2c8") if zombie else Color("1c1612")
	if closed:
		eye = skin.darkened(0.45)  # eyes shut
	var dark := skin.darkened(0.4)
	match view:
		FRONT:
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
			ci.draw_circle(c + Vector2(0, -0.2), 4.3, hair)
			ci.draw_rect(Rect2(c.x - 2.5, c.y + 3.2, 5, 0.8), hair.darkened(0.15))  # nape
		SIDE:
			# Back and crown of the head; the hairline curves in behind the eye instead of cutting across it.
			var hp := _arc(c + Vector2(-0.4, -0.4), 4.4, PI * 0.55, PI * 1.78)
			hp.append(c + Vector2(1.2, -1.6))
			hp.append(c + Vector2(-0.6, -0.2))
			ci.draw_colored_polygon(hp, hair)
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


## Aim direction in the character's (possibly mirrored) local space.
static func _local_dir(angle: float, sx: float) -> Vector2:
	var d := Vector2.from_angle(angle)
	return Vector2(d.x * sx, d.y * 0.85)


## Where the arms attach. Side-on, both shoulders sit near the middle of the body.
static func _shoulders(view: int) -> Array:
	if view == SIDE:
		return [Vector2(-0.6, -18.6), Vector2(0.6, -18.3)]
	return [Vector2(-4.0, -18.6), Vector2(4.0, -18.6)]


## `behind` selects which arms to draw in this pass: arms facing away from the
## camera go behind the torso, the others in front.
static func _player_arms(ci: CanvasItem, view: int, angle: float, sx: float, skin: Color, shirt: Color,
		attack: int, ext: float, armed: bool, behind: bool, weapon: Dictionary = {}) -> void:
	if armed:
		if behind == (view == BACK):
			_draw_gun_arms(ci, view, angle, sx, skin, shirt)
		return
	_draw_fists(ci, view, angle, sx, skin, shirt, attack, ext, behind, weapon)


## Boxing guard with fists by the chin; a punch drives one fist straight out
## along the aim while the other stays up.
static func _draw_fists(ci: CanvasItem, view: int, angle: float, sx: float, skin: Color, shirt: Color,
		attack: int, ext: float, behind: bool, weapon: Dictionary = {}) -> void:
	var d := _local_dir(angle, sx)
	var side := d.orthogonal().normalized()
	var sh := _shoulders(view)
	var chin := Vector2(0, -19.5) + d * 3.0
	var guard := [chin + side * 2.4, chin - side * 2.4 + d * 1.2]
	var reach := [PUNCH_L, PUNCH_R]
	var sleeve := shirt.darkened(0.05)
	for i in 2:
		# Back view: both arms are behind the body. Side view: the far arm (i == 0) is.
		var is_behind := view == BACK or (view == SIDE and i == 0)
		if is_behind != behind:
			continue
		if i == 1 and not weapon.is_empty():
			_weapon_arm(ci, view, d, sh[1], skin, shirt, attack, ext, weapon, is_behind)
			continue
		var fist: Vector2 = guard[i]
		if attack == reach[i]:
			# Full reach sideways; foreshortened when punching toward or away from the camera.
			fist = fist.lerp(sh[i] + Vector2(d.x * 13.0, d.y * 6.0) + Vector2(0, 2.0 * absf(d.y)), ext)
		var bend := (1.0 - (ext if attack == reach[i] else 0.0))
		var elbow: Vector2 = sh[i].lerp(fist, 0.5) + Vector2(0, 2.6 * bend) - side * (1.0 if i == 0 else -1.0) * 0.8 * bend
		var dim := 0.25 if is_behind and view == SIDE else 0.0
		_arm(ci, sh[i], elbow, fist, sleeve.darkened(dim), skin.darkened(dim), true)


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


## The weapon hand: holds the weapon raised and ready, or swings it through an arc.
static func _weapon_arm(ci: CanvasItem, view: int, d: Vector2, sh: Vector2, skin: Color, shirt: Color,
		attack: int, t: float, weapon: Dictionary, behind: bool) -> void:
	var base := atan2(d.y, d.x)
	var a := base + (swing_angle(t) if attack == SWING else -1.1)
	var dv := Vector2.from_angle(a)
	var hand := sh + Vector2(dv.x, dv.y * 0.8) * 6.5 + Vector2(0, 1.0)
	var elbow := sh.lerp(hand, 0.5) + Vector2(0, 1.4)
	var dim := 0.25 if behind and view == SIDE else 0.0
	if attack == SWING and t > 0.3 and t < 0.62:
		# Motion trail along the arc the weapon tip just travelled.
		var pts := PackedVector2Array()
		var reach: float = 6.5 + weapon.len
		var a0 := base - 2.3
		for k in 7:
			var ak := lerpf(a0, a, k / 6.0)
			pts.append(sh + Vector2(cos(ak), sin(ak) * 0.8) * reach)
		ci.draw_polyline(pts, Color(1, 1, 1, 0.35), 1.6)
	_arm(ci, sh, elbow, hand, shirt.darkened(0.05 + dim), skin.darkened(dim), true)
	_draw_weapon(ci, hand, dv, weapon)
	ci.draw_circle(hand, 1.5, skin.darkened(dim))  # fingers wrap over the handle


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


## Rifle held at the chest, pointing at `angle`, with both arms reaching it.
static func _draw_gun_arms(ci: CanvasItem, view: int, angle: float, sx: float, skin: Color, shirt: Color) -> void:
	var d := Vector2.from_angle(angle)
	d = Vector2(d.x * sx, d.y * 0.85)  # undo mirroring; squash depth a little
	var base := CHEST + Vector2(0, 1)
	var sleeve := shirt.darkened(0.15)
	var h1 := base + d * 4.5
	var h2 := base + d * 9.0
	ci.draw_line(base - d * 2.5, base + d * 13.5, Color("1a1a1a"), 2.2)  # rifle
	ci.draw_line(base + d * 6, base + d * 8, Color("3a2a1e"), 2.6)  # grip/wood
	var sh := _shoulders(view)
	ci.draw_line(sh[0], h1, sleeve, 2.2)
	ci.draw_line(sh[1], h2, sleeve, 2.2)
	ci.draw_circle(h1, 1.3, skin)
	ci.draw_circle(h2, 1.3, skin)


static func _zombie_arms(ci: CanvasItem, view: int, skin: Color, shirt: Color, phase: float, behind: bool) -> void:
	var sway := sin(phase * 0.7) * 1.0
	var arm := skin.darkened(0.1)
	var sleeve := shirt.darkened(0.1)
	match view:
		SIDE:
			var y := -17.8 + (0.0 if behind else 0.8)
			var sh := Vector2(0.4, y)
			var hand := Vector2(10.0, y + 0.5 + (sway if behind else -sway))
			var dim := 0.25 if behind else 0.0
			_arm(ci, sh, sh.lerp(hand, 0.5) + Vector2(0, 0.6), hand, sleeve.darkened(dim), arm.darkened(dim))
		FRONT:
			if not behind:
				for s in [-1.0, 1.0]:
					# Reaching toward the camera: foreshortened, hands big and low.
					var sh := Vector2(4.0 * s * _girth, -18.6)
					var hand := Vector2(2.8 * s * _girth, -12.3 + sway * s)
					_arm(ci, sh, sh.lerp(hand, 0.5) + Vector2(0.6 * s, 0), hand, sleeve, arm, false)
					ci.draw_circle(hand, 1.7, arm)
		BACK:
			pass  # arms reach away from the camera, hidden by the body


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
