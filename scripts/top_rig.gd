class_name TopRig
## A body lying flat on the ground, seen from above: the side-on rig (Rig) is
## for bodies standing up, sitting or lying across the screen; lying along it
## (head up or down the screen) a figure drawn upright reads as standing on its
## head, so these are worked out as they'd look from above, the way the cars
## are drawn: the top face lit, the end turned to you darker, near parts over
## far ones.
##
## The pose: supine, on the back (asleep): the face up to the sky, the chest,
## arms by the sides; head up or down the screen. (There was a crawl on the
## front too; it went: a view from above for every garment wasn't worth it.)
## Like Rig, it only says where the joints are; draw() paints the body and
## calls Clothes.top at each layer, so what's worn follows these poses too.

const SHOE := Color("1e1a16")


## On the back, flat out (asleep, or lying down): feet at the origin, head up
## the screen at -30 (draw() flips it for head-down). `breath` lifts the chest;
## `closed`: eyes shut.
static func supine(head_up: bool, breath := 0.0, closed := true) -> Dictionary:
	var chest := -22.5 - breath
	var r := {mode = "supine", head_up = head_up, face = true, a = 0.0, closed = closed,
			neck = Vector2(0, chest), waist = Vector2(0, -13.5), head = Vector2(0, chest - 3.6),
			shadow = [Vector2(0, -14), 15.0], sh = [], el = [], hand = [], hip = [], knee = [], foot = []}
	for s in [-1.0, 1.0]:
		r.sh.append(Vector2(s * 5.9, chest + 1.2))
		r.el.append(Vector2(s * 6.7, -17.0))
		r.hand.append(Vector2(s * 6.4, -12.2))
		r.hip.append(Vector2(s * 2.2, -13.5))
		r.knee.append(Vector2(s * 2.2, -8.2))
		r.foot.append(Vector2(s * 2.2, -1.7))
	return r


## Paint `r` with look `lk` (as Look takes it: colours, build, wear) at `lift`
## off the ground, `squash` as wide (turning over from side-on).
static func draw(ci, r: Dictionary, lk: Dictionary, lift := 0.0, squash := 1.0) -> void:
	var dl := Look._dress(lk, false)
	var flip: bool = r.mode == "supine" and not r.head_up
	ci.draw_set_transform(Vector2(0, -lift), 0, Vector2(lk.get("build", 1.0) * squash, -1.0 if flip else 1.0))
	Look._girth = 1.0  # (the build is in the transform's width)
	var sh: Vector2 = r.shadow[0]
	var sr: float = r.shadow[1]
	for i in 3:  # (a soft oval under the whole length)
		Look._dot(ci, sh + Vector2(0, (i - 1) * sr * 0.45), sr * (0.62 - absf(i - 1) * 0.12), Color(0, 0, 0, 0.09))
	Clothes.top(ci, "under", r, lk)  # (a backpack under someone lying on it)
	_legs(ci, r, dl, lk)
	_back(ci, r, dl, lk)
	_arms(ci, r, dl, lk)
	_head(ci, r, dl, lk)
	ci.draw_set_transform(Vector2.ZERO)


static func _limb(ci, p: Vector2, q: Vector2, w: float, col: Color) -> void:
	Look._limb(ci, p, q, w, w, col)


## The legs the way Look draws them standing (the same widths and colours, the
## far ones darker, bare shins in shorts), then the seat and the belt.
static func _legs(ci, r: Dictionary, dl: Dictionary, lk: Dictionary) -> void:
	var pants: Color = dl.pants
	var shin: Color = (dl.skin as Color).darkened(0.05) if dl.get("shorts", false) else pants
	var shoe: Color = dl.shoes
	var boot := 1.1 if dl.get("boots", false) else 0.0
	for i in 2:
		var h: Vector2 = r.hip[i]
		var k: Vector2 = r.knee[i]
		var f: Vector2 = r.foot[i]
		Look._limb(ci, h, k, 3.2, 2.9, pants)
		Look._limb(ci, k, f, 2.9, 2.5, shin)
		Clothes.leg_marks(ci, h, k, f, dl, false)
		# The soles, the tread across them.
		Look._rect(ci, Rect2(f.x - 1.8, f.y - 0.8, 3.6, 3.0 + boot), shoe)
		Look._rect(ci, Rect2(f.x - 1.5, f.y, 3.0, 0.5), shoe.lightened(0.3))
		Look._rect(ci, Rect2(f.x - 1.5, f.y + 1.1, 3.0, 0.5), shoe.lightened(0.3))
	Clothes.top(ci, "knee", r, lk)
	var w: Vector2 = r.waist
	var dy := -1.0
	var g: float = Look._girth
	Look._poly(ci, PackedVector2Array([w + Vector2(-3.7 * g, 0), w + Vector2(3.7 * g, 0), w + Vector2(3.6 * g, 2.6 * dy), w + Vector2(-3.6 * g, 2.6 * dy)]),
			(dl.pants as Color).darkened(0.06))  # the seat, as the hips join the legs standing
	Look._rect(ci, Rect2(w.x - 3.75 * g, w.y - 0.6, 7.5 * g, 1.2), (dl.pants as Color).darkened(0.35))  # belt


## The chest, shaded as Look shades a shirt: lighter at the shoulders, darker at the waist, a shadow down one side.
static func _back(ci, r: Dictionary, dl: Dictionary, lk: Dictionary) -> void:
	var shirt: Color = dl.shirt
	var top := shirt.lightened(0.08)
	var bot := shirt.darkened(0.25)
	var n: Vector2 = r.neck
	var w: Vector2 = r.waist
	var g: float = Look._girth
	var dn := 1.0 if n.y > w.y else -1.0  # (which way the shoulders lie from the waist)
	var sw := 4.4 * g
	Look._poly(ci, PackedVector2Array([w + Vector2(-sw * 0.85, 0), w + Vector2(sw * 0.85, 0), n + Vector2(sw, -0.8 * dn), n + Vector2(sw - 1.2, 0.8 * dn),
			n + Vector2(-sw + 1.2, 0.8 * dn), n + Vector2(-sw, -0.8 * dn)]), PackedColorArray([bot, bot, shirt, top, top, shirt]))
	Look._poly(ci, PackedVector2Array([w + Vector2(sw * 0.3, 0), w + Vector2(sw * 0.85, 0), n + Vector2(sw, -0.8 * dn), n + Vector2(sw * 0.35, 0.4 * dn)]),
			Color(0, 0, 0, 0.12))  # shadow side
	Look._polyline(ci, PackedVector2Array([n + Vector2(-1.5, 0.4), n + Vector2(0, 2.0), n + Vector2(1.5, 0.4)]), shirt.darkened(0.35), 0.6)  # collar
	Clothes.shirt_marks(ci, [n + Vector2(-sw + 0.8, 0), n + Vector2(sw - 0.8, 0), w + Vector2(sw * 0.85, 0), w + Vector2(-sw * 0.85, 0)],
			dl, true)
	Clothes.top(ci, "back", r, lk)
	Clothes.top(ci, "waist", r, lk)


## The arms exactly as Look draws them (outlined, the sleeve and the bare
## forearm, the hand), and on them what's worn there, the same as standing.
static func _arms(ci, r: Dictionary, dl: Dictionary, lk: Dictionary) -> void:
	var wear: Dictionary = lk.get("wear", {})
	for i in 2:
		var sleeve: Color = Color(0, 0, 0, 0) if dl.get("sleeveless", false) else (dl.shirt as Color).darkened(0.05)
		Look._arm(ci, r.sh[i], r.el[i], r.hand[i], sleeve, dl.skin, false, dl.get("long_sleeves", false))
		if not wear.get("arms", {}).is_empty():
			Clothes.arm_guard(ci, r.el[i], r.hand[i], wear.arms, r.sh[i])
		if not wear.get("hands", {}).is_empty():
			Clothes.glove(ci, r.hand[i], false, wear.hands)


static func _head(ci, r: Dictionary, dl: Dictionary, lk: Dictionary) -> void:
	# The very same head as standing up (Look._head: the hair style, the face,
	# the hat and whatever's on the face), face up.
	Clothes.top(ci, "neck", r, lk)
	var wear: Dictionary = lk.get("wear", {})
	Look._head(ci, Look.FRONT, r.head, dl.skin, dl.hair, lk.get("hair_style", "short"), false,
			r.get("closed", false), wear.get("head", {}), 0.0, false, false, wear.get("face", {}))
	Clothes.top(ci, "over_head", r, lk)  # (a costume's big head, over the real one)
