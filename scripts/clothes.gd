class_name Clothes
## How worn things are drawn. Each item's `draw` in data/items.cfg names a
## template (`shape`) and its colour, or lists several `parts` (a raincoat is
## a coat, sleeves and a hood). A template is drawn at the joints of the rig
## at one or more layers of the body, so it follows every pose and view the
## rig can make: walking, riding, falling, anything added later.
##
## Look calls draw_layer at each layer as it draws a body, in this order:
##   back_side   behind everything, side-on (a backpack against the back)
##   coat        over the legs, under the body (coat tails; drawn with the upper body)
##   knee        over the legs (knee pads)
##   behind_head behind the head (a hood down the back, seen from the front)
##   torso       over the shirt (vests, a backpack's straps or the bag itself)
##   strap       over that (a bag's strap across the chest)
##   neck        round the neck, up under the chin (scarves)
##   arm         on each forearm (arm guards) - drawn by Look._draw_arm
##   face        on the face (masks, glasses) - drawn by Look._head
##   hat         on the head (caps, helmets) - drawn by Look._head
##   back_head   over the head, seen from behind (a hood); `neck` just before it
##   hand        on each hand (gloves)
## Some templates also change the base body (see Look._dress): what colour the
## shirt, sleeves and trousers are, shorts, boots.
##
## Adding a garment that looks like an existing one: a new section in
## data/items.cfg with the template's name and colours. A new kind of thing:
## a template here (a function per layer it draws at, listed in TEMPLATES).

## Shapes that only change the base body (Look._dress): shirt or trousers
## colour and cut, shoes.
const BASE_SHAPES := ["long", "hoodie", "shorts", "boots", "shoes"]

## template -> the layers it draws at.
const TEMPLATES := {
	hoodie = ["behind_head", "back_head"],
	vest = ["torso"],
	pack = ["back_side", "torso"],
	helmet = ["hat"],
	cap = ["hat"],
	mask = ["face"],
	glasses = ["face"],
	gloves = ["hand"],
	kneepads = ["knee"],
	satchel = ["back_side", "strap"],
	coat = ["coat"],
	hood = ["behind_head", "back_head"],
	armguards = ["arm"],
	fullface = ["hat"],
	scarf = ["neck"],
	shinguards = ["knee"],
}


## The templates a draw dictionary is made of: its `parts`, or just itself.
static func parts(d: Dictionary) -> Array:
	if d.has("parts"):
		var out := []
		for p in d.parts:
			var q: Dictionary = p.duplicate()
			q.merge({col = d.get("col", Color.GRAY)}, false)  # parts share the garment's colour unless they say
			out.append(q)
		return out
	return [d]


## Everything worn that draws at `layer`, in slot order.
static func draw_layer(ci: CanvasItem, layer: String, r: Dictionary, lk: Dictionary) -> void:
	var wear: Dictionary = lk.get("wear", {})
	if wear.is_empty():
		return
	for slot in Items.SLOTS:
		if not wear.has(slot):
			continue
		for p in parts(wear[slot]):
			var shape: String = p.get("shape", "")
			if layer in TEMPLATES.get(shape, []):
				_draw(ci, layer, shape, p, r, lk)


static func _draw(ci: CanvasItem, layer: String, shape: String, p: Dictionary, r: Dictionary, lk: Dictionary) -> void:
	var view: int = r.view
	match [shape, layer]:
		["hoodie", "behind_head"], ["hood", "behind_head"]:
			if view != Look.BACK:
				Look._dot(ci, Vector2(-0.6 if view == Look.SIDE else 0.0, -20.6), 3.4, _hood_col(shape, p, lk))  # hood, behind the head
		["hoodie", "back_head"], ["hood", "back_head"]:
			if view == Look.BACK:
				var hc: Color = (lk.shirt as Color) if shape == "hoodie" else (p.col as Color)
				Look._poly(ci, Look._arc(Vector2(0, -20.2), 3.6, 0.0, PI), hc.darkened(0.12))  # hood down the back
		["vest", "torso"]:
			_vest(ci, view, p)
		["pack", "back_side"]:
			if view == Look.SIDE:
				_pack_side(ci, p)
		["pack", "torso"]:
			if view != Look.SIDE:
				_pack(ci, view, p)
		["satchel", "back_side"]:
			_satchel_bag(ci, view, p, true)
		["satchel", "strap"]:
			_satchel_strap(ci, view, p)
			_satchel_bag(ci, view, p, false)
		["coat", "coat"]:
			_coat(ci, view, r, p)
		["scarf", "neck"]:
			var col: Color = p.col
			var w := (2.4 if view == Look.SIDE else 3.3) * Look._girth
			Look._rect(ci, Rect2(-w, -20.6, w * 2, 2.4), col)
			Look._rect(ci, Rect2(-w, -20.6, w * 2, 0.7), col.lightened(0.15))
			if view != Look.BACK:
				Look._rect(ci, Rect2(w * 0.25, -18.4, 1.6, 4.0), col.darkened(0.12))  # the loose end
		["shinguards", "knee"]:
			for leg in r.legs:
				var k := _knee_of(leg)
				if k == Vector2.INF:
					continue
				var foot: Vector2 = leg.foot if leg.has("foot") else Vector2(leg.get("x", 0.0) + 1.4, -leg.get("lift", 0.0))
				var a := k.lerp(foot, 0.15)
				var b := k.lerp(foot, 0.75)
				Look._limb(ci, a, b, 3.0, 2.6, (p.col as Color).darkened(0.2 if leg.far else 0.0))
		["kneepads", "knee"]:
			for leg in r.legs:
				var k := _knee_of(leg)
				if k != Vector2.INF:
					Look._rect(ci, Rect2(k + Vector2(-1.6, -1.2), Vector2(3.2, 2.2)), (p.col as Color).darkened(0.2 if leg.far else 0.0))
					Look._rect(ci, Rect2(k + Vector2(-1.2, -1.0), Vector2(2.4, 0.6)), (p.col as Color).lightened(0.25))


## A hoodie's hood is the shirt's colour; a raincoat's is the coat's.
static func _hood_col(shape: String, p: Dictionary, lk: Dictionary) -> Color:
	return ((lk.shirt as Color) if shape == "hoodie" else (p.col as Color)).darkened(0.2)


## Where a leg's knee is, however the rig drew that leg.
static func _knee_of(leg: Dictionary) -> Vector2:
	match leg.type:
		"rect":
			return Vector2(leg.x + 1.4, -5.6 - leg.lift * 0.5)
		"line":
			return (leg.hip as Vector2).lerp(leg.foot, 0.5) + Vector2(0.8, 0)
		"limb":
			return leg.knee
	return Vector2.INF


# --- On the head (called by Look._head) ---------------------------------------------

## Hats and helmets, over the hair.
static func hat(ci: CanvasItem, view: int, c: Vector2, h: Dictionary) -> void:
	for p in parts(h):
		var col: Color = p.col
		match p.get("shape", ""):
			"helmet":
				# Open-face motorbike helmet: a shell over the crown, a visor rim, a chin strap.
				Look._poly(ci, Look._arc(c + Vector2(0, -0.5), 5.0, PI, TAU), col)
				Look._rect(ci, Rect2(c.x - 5.0, c.y - 0.9, 10.0, 1.2), col.darkened(0.12))
				Look._poly(ci, Look._arc(c + Vector2(-1.4, -2.6), 1.4, PI, TAU), col.lightened(0.3))  # shine
				if view == Look.SIDE:
					Look._rect(ci, Rect2(c.x + 2.2, c.y - 1.6, 3.2, 0.9), Color("2a3036"))  # visor edge
					Look._line(ci, c + Vector2(-0.6, 0.2), c + Vector2(1.6, 3.8), Color("2a2a2a"), 0.4)
				elif view == Look.FRONT:
					Look._rect(ci, Rect2(c.x - 3.8, c.y - 1.6, 7.6, 0.8), Color("2a3036"))
					for sx in [-1.0, 1.0]:
						Look._line(ci, c + Vector2(4.0 * sx, 0.2), c + Vector2(2.2 * sx, 3.8), Color("2a2a2a"), 0.4)
			"cap":
				Look._poly(ci, Look._arc(c + Vector2(0, -0.9), 4.5, PI, TAU), col)
				match view:
					Look.FRONT:
						Look._rect(ci, Rect2(c.x - 3.6, c.y - 1.5, 7.2, 1.1), col.darkened(0.25))  # brim, from underneath
					Look.SIDE:
						Look._rect(ci, Rect2(c.x + 2.4, c.y - 1.6, 3.8, 0.9), col.darkened(0.15))
					Look.BACK:
						Look._rect(ci, Rect2(c.x - 1.2, c.y - 1.2, 2.4, 0.7), col.darkened(0.3))  # strap
			"fullface":
				# A full-face helmet: a shell over the whole head, a dark visor where the face is.
				Look._dot(ci, c + Vector2(0, 0.2), 5.1, col)
				Look._poly(ci, Look._arc(c + Vector2(-1.4, -2.4), 1.6, PI, TAU), col.lightened(0.3))  # shine
				match view:
					Look.FRONT:
						Look._rect(ci, Rect2(c.x - 3.4, c.y - 1.4, 6.8, 2.6), Color("141820"))
						Look._rect(ci, Rect2(c.x - 3.0, c.y - 1.2, 2.2, 0.6), Color(1, 1, 1, 0.3))
						Look._rect(ci, Rect2(c.x - 2.0, c.y + 2.6, 4.0, 1.6), col.darkened(0.2))  # chin bar
					Look.SIDE:
						Look._rect(ci, Rect2(c.x + 1.2, c.y - 1.4, 4.0, 2.6), Color("141820"))
						Look._rect(ci, Rect2(c.x + 1.4, c.y + 1.8, 3.6, 2.0), col.darkened(0.2))


## Masks and glasses, on the face (under any hat).
static func face(ci: CanvasItem, view: int, c: Vector2, f: Dictionary) -> void:
	for p in parts(f):
		var col: Color = p.col
		match p.get("shape", ""):
			"mask":
				# A cloth mask over nose and mouth, loops round the ears.
				match view:
					Look.FRONT:
						Look._poly(ci, PackedVector2Array([c + Vector2(-2.6, 0.9), c + Vector2(2.6, 0.9), c + Vector2(2.2, 3.4),
								c + Vector2(0, 3.9), c + Vector2(-2.2, 3.4)]), col)
						Look._line(ci, c + Vector2(-2.4, 1.9), c + Vector2(2.4, 1.9), col.darkened(0.12), 0.35)  # pleat
						for sx in [-1.0, 1.0]:
							Look._line(ci, c + Vector2(2.6 * sx, 1.0), c + Vector2(3.8 * sx, 0.2), col.darkened(0.2), 0.3)
					Look.SIDE:
						Look._poly(ci, PackedVector2Array([c + Vector2(2.0, 0.9), c + Vector2(4.4, 0.9), c + Vector2(4.0, 3.2),
								c + Vector2(2.4, 3.6)]), col)
						Look._line(ci, c + Vector2(2.0, 1.2), c + Vector2(-0.6, 0.5), col.darkened(0.2), 0.3)  # loop to the ear
					Look.BACK:
						for sx in [-1.0, 1.0]:
							Look._line(ci, c + Vector2(3.9 * sx, 0.4), c + Vector2(3.3 * sx, 1.4), col.darkened(0.2), 0.35)
			"glasses":
				var frame := Color("1a1a1a")
				match view:
					Look.FRONT:
						for sx in [-1.0, 1.0]:
							Look._rect(ci, Rect2(c.x + 1.5 * sx - 1.1, c.y - 0.3, 2.2, 1.4), col)
						Look._line(ci, c + Vector2(-2.7, -0.3), c + Vector2(2.7, -0.3), frame, 0.35)
					Look.SIDE:
						Look._rect(ci, Rect2(c.x + 1.8, c.y - 0.3, 1.8, 1.4), col)
						Look._line(ci, c + Vector2(1.8, -0.2), c + Vector2(-0.8, 0.2), frame, 0.35)  # arm to the ear
					Look.BACK:
						for sx in [-1.0, 1.0]:
							Look._line(ci, c + Vector2(4.0 * sx, -0.4), c + Vector2(3.6 * sx, 0.6), frame, 0.3)


## An arm guard wrapped round the forearm (drawn by Look._draw_arm).
static func arm_guard(ci: CanvasItem, elbow: Vector2, hand: Vector2, g: Dictionary) -> void:
	for p in parts(g):
		if p.get("shape", "") == "armguards":
			var col: Color = p.col
			var a := elbow.lerp(hand, 0.12)
			var b := elbow.lerp(hand, 0.78)
			Look._limb(ci, a, b, 3.0, 2.7, col)
			for t in [0.3, 0.6]:
				var m := a.lerp(b, t)
				var n := (b - a).orthogonal().normalized() * 1.4
				Look._line(ci, m - n, m + n, Color("8a9098"), 0.5)  # tape


## A glove over the hand (drawn by Look._draw_arm).
static func glove(ci: CanvasItem, hand: Vector2, fist: bool, g: Dictionary) -> void:
	for p in parts(g):
		if p.get("shape", "") == "gloves":
			var col: Color = p.col
			Look._dot(ci, hand, 1.7 if fist else 1.45, col)
			Look._dot(ci, hand + Vector2(-0.4, -0.4), 0.6, col.lightened(0.2))


# --- Body pieces (moved here from Look unchanged) -----------------------------------

## Armour vest (or a hi-vis rider's vest) over the shirt: panel front and back.
static func _vest(ci: CanvasItem, view: int, v: Dictionary) -> void:
	var w := (3.2 if view == Look.SIDE else 4.5) * Look._girth
	var col: Color = v.col
	var pts := PackedVector2Array([Vector2(-w + 1.6, -19.8), Vector2(-w * 0.35, -19.8), Vector2(-w * 0.2, -18.2),
			Vector2(w * 0.2, -18.2), Vector2(w * 0.35, -19.8), Vector2(w - 1.6, -19.8), Vector2(w, -18.2),
			Vector2(w * 0.88, -11.2), Vector2(-w * 0.88, -11.2), Vector2(-w, -18.2)])
	if view != Look.FRONT:
		pts = PackedVector2Array([Vector2(-w + 1.4, -19.9), Vector2(w - 1.4, -19.9), Vector2(w, -18.2),
				Vector2(w * 0.88, -11.2), Vector2(-w * 0.88, -11.2), Vector2(-w, -18.2)])
	Look._poly(ci, pts, col)
	Look._polyline(ci, pts + PackedVector2Array([pts[0]]), col.darkened(0.35), 0.5)
	if v.get("plate", false):
		# Pouches and a light strip where the plate sits.
		Look._rect(ci, Rect2(-w * 0.7, -14.2, w * 1.4, 2.2), col.darkened(0.2))
		for i in 3:
			Look._line(ci, Vector2(-w * 0.7 + (i + 1) * w * 0.35, -14.2), Vector2(-w * 0.7 + (i + 1) * w * 0.35, -12.0), col.darkened(0.45), 0.4)
		Look._line(ci, Vector2(-w * 0.6, -18.0), Vector2(w * 0.6, -18.0), col.lightened(0.18), 0.5)
	else:
		# Hi-vis strips, like Bangkok's motorbike taxi vests.
		Look._line(ci, Vector2(-w * 0.9, -14.8), Vector2(w * 0.9, -14.8), Color("e8e4d0"), 0.8)
		Look._line(ci, Vector2(-w * 0.88, -12.6), Vector2(w * 0.88, -12.6), Color("e8e4d0"), 0.6)


## Backpack seen from the front (only the straps) or from behind (the whole bag).
static func _pack(ci: CanvasItem, view: int, p: Dictionary) -> void:
	var col: Color = p.col
	var big: bool = p.get("big", false)
	var g := Look._girth
	if view == Look.FRONT:
		for sx in [-1.0, 1.0]:
			Look._line(ci, Vector2(2.9 * sx * g, -19.6), Vector2(2.6 * sx * g, -12.8), col.darkened(0.25), 1.0)
		return
	var h := 9.5 if big else 7.0
	var hw := (3.8 if big else 3.2)
	var r := Rect2(-hw, -19.8, hw * 2, h)
	Look._rect(ci, Rect2(r.position + Vector2(0.3, 0.6), r.size), Color(0, 0, 0, 0.25))
	Look._rect(ci, r, col)
	Look._rect(ci, Rect2(r.position, Vector2(r.size.x, 2.6)), col.darkened(0.18))  # flap
	Look._rect(ci, Rect2(-1.6, r.end.y - 3.6, 3.2, 2.4), col.darkened(0.12))  # front pocket
	Look._line(ci, Vector2(-hw, r.position.y + 2.6), Vector2(hw, r.position.y + 2.6), col.darkened(0.4), 0.4)
	if big:
		Look._rect(ci, Rect2(-hw - 0.4, -21.2, hw * 2 + 0.8, 1.6), Color("6a5a3a"))  # rolled mat on top


## Side view: the bag sits against the back, the strap crosses the shoulder.
static func _pack_side(ci: CanvasItem, p: Dictionary) -> void:
	var col: Color = p.col
	var big: bool = p.get("big", false)
	var h := 9.5 if big else 7.0
	var d := 3.4 if big else 2.6
	var x := -3.0 * Look._girth
	Look._rect(ci, Rect2(x - d, -19.8, d + 1.0, h), col.darkened(0.08))
	Look._rect(ci, Rect2(x - d, -19.8, d + 1.0, 2.2), col.darkened(0.22))
	if big:
		Look._rect(ci, Rect2(x - d - 0.2, -21.2, d + 1.4, 1.6), Color("6a5a3a"))


# --- New pieces -------------------------------------------------------------------------

## A shoulder bag: the strap runs from the right shoulder to the left hip,
## where the bag hangs. Side-on it hangs at the hip nearest us, or behind.
static func _satchel_strap(ci: CanvasItem, view: int, p: Dictionary) -> void:
	var col: Color = (p.col as Color).darkened(0.3)
	var g := Look._girth
	match view:
		Look.FRONT:
			Look._line(ci, Vector2(3.0 * g, -19.4), Vector2(-3.0 * g, -11.6), col, 0.9)
		Look.BACK:
			Look._line(ci, Vector2(-3.0 * g, -19.4), Vector2(3.0 * g, -11.6), col, 0.9)
		Look.SIDE:
			Look._line(ci, Vector2(0.4, -19.4), Vector2(-0.6, -11.4), col, 0.9)


static func _satchel_bag(ci: CanvasItem, view: int, p: Dictionary, behind: bool) -> void:
	var col: Color = p.col
	var g := Look._girth
	# From the front the bag is at our left hip; from behind, at our right. Side-on it's at the hip.
	var at := Vector2(-3.8 * g, -12.0) if view == Look.FRONT else (Vector2(3.8 * g, -12.0) if view == Look.BACK else Vector2(-1.8, -12.0))
	if behind != (view == Look.SIDE):
		return
	Look._rect(ci, Rect2(at + Vector2(-2.2, -1.6), Vector2(4.4, 3.8)), col)
	Look._rect(ci, Rect2(at + Vector2(-2.2, -1.6), Vector2(4.4, 1.5)), col.darkened(0.2))  # flap
	Look._dot(ci, at + Vector2(0, 0.1), 0.4, Color("c8b070"))  # buckle


## A long coat: the skirt from the hips to the knees, over the trousers, split
## at the back so the legs move (a raincoat's tails, a lab coat).
static func _coat(ci: CanvasItem, view: int, r: Dictionary, p: Dictionary) -> void:
	# (Drawn with the upper body, so it bobs and sits with it.)
	var col: Color = p.col
	var w := (3.1 if view == Look.SIDE else 4.0) * Look._girth
	var top := -11.0
	var bot := -5.2
	Look._poly(ci, PackedVector2Array([Vector2(-w, top), Vector2(w, top), Vector2(w * 1.08, bot), Vector2(-w * 1.08, bot)]), col.darkened(0.06))
	if view == Look.FRONT:
		Look._line(ci, Vector2(0, top), Vector2(0, bot), col.darkened(0.3), 0.4)  # where it buttons
	Look._line(ci, Vector2(-w * 1.08, bot), Vector2(w * 1.08, bot), col.darkened(0.25), 0.5)  # hem
