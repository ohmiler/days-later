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
##   waist       round the waist (a pha khao ma, a bum bag, a tool belt)
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
const BASE_SHAPES := ["long", "hoodie", "shorts", "boots", "shoes", "tee", "tank", "shirt", "sandals", "heels"]

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
	bucket = ["hat"],
	beanie = ["hat"],
	hardhat = ["hat"],
	whistle = ["neck"],
	apron = ["coat", "torso"],
	sash = ["waist"],
	bumbag = ["waist"],
	toolbelt = ["waist"],
	skirt = ["coat"],
	sarong = ["coat"],
	ngop = ["hat"],
	halfhelmet = ["hat"],
	headlamp = ["hat"],
	gasmask = ["face"],
	lifejacket = ["torso"],
	armband = ["arm"],
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
static func draw_layer(ci, layer: String, r: Dictionary, lk: Dictionary) -> void:
	var wear: Dictionary = lk.get("wear", {})
	if wear.is_empty():
		return
	for e in _by_layer(wear, "_layers", TEMPLATES).get(layer, []):
		_draw(ci, layer, e[0], e[1], r, lk)


## What's worn, sorted by the layer it draws at: {layer: [[shape, part], ...]}
## in slot order. Worked out the first time a set of clothes is drawn and kept
## in it (under `key`): a body is drawn every frame, the clothes rarely change.
static func _by_layer(wear: Dictionary, key: String, templates: Dictionary) -> Dictionary:
	var idx = wear.get(key)
	if idx != null:
		return idx
	idx = {}
	for slot in Items.SLOTS:
		if not wear.has(slot):
			continue
		for p in parts(wear[slot]):
			var shape: String = p.get("shape", "")
			for layer in templates.get(shape, []):
				if not idx.has(layer):
					idx[layer] = []
				idx[layer].append([shape, p])
	wear[key] = idx
	return idx


static func _draw(ci, layer: String, shape: String, p: Dictionary, r: Dictionary, lk: Dictionary) -> void:
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
			for leg in r.legs:  # (every leg from the rig says where its knee and foot are)
				var k: Vector2 = leg.knee
				var a := k.lerp(leg.foot, 0.15)
				var b := k.lerp(leg.foot, 0.75)
				Look._limb(ci, a, b, 3.0, 2.6, (p.col as Color).darkened(0.2 if leg.far else 0.0))
		["kneepads", "knee"]:
			for leg in r.legs:
				var k: Vector2 = leg.knee
				Look._rect(ci, Rect2(k + Vector2(-1.6, -1.2), Vector2(3.2, 2.2)), (p.col as Color).darkened(0.2 if leg.far else 0.0))
				Look._rect(ci, Rect2(k + Vector2(-1.2, -1.0), Vector2(2.4, 0.6)), (p.col as Color).lightened(0.25))
		["whistle", "neck"]:
			if view != Look.BACK:
				var lan: Color = p.get("col2", Color("c83a2e"))
				var x := 0.3 if view == Look.SIDE else 0.0
				Look._line(ci, Vector2(-1.8 + x, -20.4), Vector2(x, -16.4), lan, 0.4)
				Look._line(ci, Vector2(1.8 + x, -20.4), Vector2(x, -16.4), lan, 0.4)
				Look._rect(ci, Rect2(x - 0.6, -16.6, 1.6, 0.9), p.col)  # the whistle
		["apron", "coat"]:
			if view != Look.BACK:  # the skirt of it, down over the thighs
				var w := (2.6 if view == Look.SIDE else 3.6) * Look._girth
				var x := 0.8 if view == Look.SIDE else 0.0
				Look._poly(ci, PackedVector2Array([Vector2(-w + x, -11.2), Vector2(w + x, -11.2), Vector2(w * 1.05 + x, -5.6), Vector2(-w * 1.05 + x, -5.6)]),
						(p.col as Color).darkened(0.05))
		["apron", "torso"]:
			var w := (2.6 if view == Look.SIDE else 3.4) * Look._girth
			var col: Color = p.col
			if view == Look.BACK:
				Look._line(ci, Vector2(-4.2 * Look._girth, -12.2), Vector2(4.2 * Look._girth, -12.2), col.darkened(0.2), 0.5)  # the ties
				Look._line(ci, Vector2(-0.4, -12.2), Vector2(-1.2, -10.4), col.darkened(0.2), 0.4)
				Look._line(ci, Vector2(0.4, -12.2), Vector2(1.2, -10.4), col.darkened(0.2), 0.4)
			else:
				var x := 0.8 if view == Look.SIDE else 0.0
				Look._poly(ci, PackedVector2Array([Vector2(-w * 0.6 + x, -18.4), Vector2(w * 0.6 + x, -18.4), Vector2(w + x, -11.2), Vector2(-w + x, -11.2)]), col)
				Look._rect(ci, Rect2(-w * 0.55 + x, -13.8, w * 1.1, 1.8), col.darkened(0.15))  # the pocket across the front
				if p.has("col2"):
					Look._line(ci, Vector2(-w * 0.6 + x, -18.0), Vector2(w * 0.6 + x, -18.0), p.col2, 0.5)
		["sash", "waist"], ["bumbag", "waist"], ["toolbelt", "waist"]:
			_waist(ci, view, shape, p)
		["skirt", "coat"], ["sarong", "coat"]:
			# From the hips down over the legs: to the knee, or (a pha thung) to the ankle.
			var col: Color = p.col
			var w := (3.0 if view == Look.SIDE else 3.8) * Look._girth
			var bot := -5.4 if shape == "skirt" else -1.6
			var flare := 1.12 if shape == "skirt" else 0.98
			Look._poly(ci, PackedVector2Array([Vector2(-w, -11.6), Vector2(w, -11.6), Vector2(w * flare, bot), Vector2(-w * flare, bot)]), col)
			Look._line(ci, Vector2(-w * flare, bot), Vector2(w * flare, bot), col.darkened(0.3), 0.5)  # the hem
			if shape == "sarong":
				# A pha thung's woven band round the bottom, and the tuck at the waist.
				Look._rect(ci, Rect2(-w * flare, bot - 1.6, w * flare * 2, 1.2), p.get("col2", col.darkened(0.3)))
				if view == Look.FRONT:
					Look._line(ci, Vector2(w * 0.3, -11.6), Vector2(w * 0.2, bot), col.darkened(0.2), 0.4)
			elif p.get("pattern", "") == "plaid":
				var c2: Color = p.get("col2", col.darkened(0.3))
				Look._line(ci, Vector2(-w, -9.0), Vector2(w, -9.0), c2, 0.6)
				Look._line(ci, Vector2(0, -11.6), Vector2(0, bot), c2, 0.6)
		["lifejacket", "torso"]:
			# A bulky orange life jacket: fat panels, a reflective strip, the buckles.
			var w := (3.6 if view == Look.SIDE else 5.0) * Look._girth
			var col: Color = p.col
			Look._poly(ci, PackedVector2Array([Vector2(-w + 1.0, -20.2), Vector2(w - 1.0, -20.2), Vector2(w, -18.0), Vector2(w * 0.95, -11.0),
					Vector2(-w * 0.95, -11.0), Vector2(-w, -18.0)]), col)
			Look._line(ci, Vector2(-w * 0.9, -15.0), Vector2(w * 0.9, -15.0), Color("e8e4d0"), 0.7)
			if view == Look.FRONT:
				Look._line(ci, Vector2(0, -19.6), Vector2(0, -11.2), col.darkened(0.35), 0.5)
				for y in [-17.0, -13.0]:
					Look._rect(ci, Rect2(-0.9, y, 1.8, 0.9), Color("2a2c30"))


## A hoodie's hood is the shirt's colour; a raincoat's is the coat's.
static func _hood_col(shape: String, p: Dictionary, lk: Dictionary) -> Color:
	return ((lk.shirt as Color) if shape == "hoodie" else (p.col as Color)).darkened(0.2)


# --- On the head (called by Look._head) ---------------------------------------------

## Hats and helmets, over the hair.
static func hat(ci, view: int, c: Vector2, h: Dictionary) -> void:
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
			"bucket":
				# A bucket hat: soft crown, the brim all round, drooping.
				Look._poly(ci, Look._arc(c + Vector2(0, -1.0), 4.4, PI, TAU), col)
				Look._poly(ci, PackedVector2Array([c + Vector2(-6.0, -0.4), c + Vector2(6.0, -0.4), c + Vector2(5.0, -1.8), c + Vector2(-5.0, -1.8)]),
						col.darkened(0.12))
				if p.get("pattern", "") == "camo":
					Look._dot(ci, c + Vector2(-1.8, -3.0), 0.9, (p.get("col2", col.darkened(0.3)) as Color))
					Look._dot(ci, c + Vector2(1.6, -2.4), 0.8, (p.get("col2", col.darkened(0.3)) as Color))
			"beanie":
				# A knitted hat pulled down to the ears: a turned-up cuff.
				Look._poly(ci, Look._arc(c + Vector2(0, -0.4), 4.6, PI, TAU), col)
				Look._rect(ci, Rect2(c.x - 4.6, c.y - 1.6, 9.2, 1.5), col.darkened(0.15))
				Look._dot(ci, c + Vector2(0, -5.0), 0.9, (p.get("col2", col.lightened(0.2)) as Color))  # the bobble
			"hardhat":
				# A builder's hard hat: a shell with a ridge down the middle, a short peak.
				Look._poly(ci, Look._arc(c + Vector2(0, -0.8), 4.8, PI, TAU), col)
				Look._rect(ci, Rect2(c.x - 5.4, c.y - 1.2, 10.8, 1.0), col.darkened(0.1))
				if view != Look.SIDE:
					Look._rect(ci, Rect2(c.x - 0.5, c.y - 5.4, 1.0, 4.4), col.lightened(0.15))  # the ridge
				else:
					Look._rect(ci, Rect2(c.x + 3.0, c.y - 1.6, 3.0, 1.0), col.darkened(0.12))
			"ngop":
				# A ngop: the farmer's wide palm-leaf hat, a shallow cone on a headband.
				Look._poly(ci, PackedVector2Array([c + Vector2(-8.4, 0.2), c + Vector2(8.4, 0.2), c + Vector2(0, -6.2)]), col)
				Look._line(ci, c + Vector2(-8.4, 0.2), c + Vector2(8.4, 0.2), col.darkened(0.3), 0.6)
				for k in [-4.2, 0.0, 4.2]:
					Look._line(ci, c + Vector2(k, 0.0), c + Vector2(0, -6.0), col.darkened(0.15), 0.3)  # the ribs
			"halfhelmet":
				# A half helmet, as the motorbike taxis wear: a bowl over the crown, a strap.
				Look._poly(ci, Look._arc(c + Vector2(0, -1.2), 4.6, PI, TAU), col)
				Look._rect(ci, Rect2(c.x - 4.6, c.y - 1.6, 9.2, 0.8), col.darkened(0.2))
				Look._poly(ci, Look._arc(c + Vector2(-1.4, -3.0), 1.2, PI, TAU), col.lightened(0.3))
				if view != Look.BACK:
					Look._line(ci, c + Vector2(3.8 if view == Look.FRONT else 0.4, -0.8), c + Vector2(2.0 if view == Look.FRONT else 1.6, 3.8), Color("2a2a2a"), 0.4)
				if p.get("mirror", false) and view != Look.BACK:
					var mx := 5.2 if view == Look.FRONT else 4.4
					Look._line(ci, c + Vector2(mx - 1.0, -2.4), c + Vector2(mx, -4.4), Color("5a5a5a"), 0.4)
					Look._rect(ci, Rect2(c.x + mx - 0.4, c.y - 5.8, 1.6, 1.4), Color("9ab8c8"))  # the little mirror
			"headlamp":
				# A lamp on a strap round the head.
				Look._rect(ci, Rect2(c.x - 4.3, c.y - 2.2, 8.6, 0.9), Color("2a2c30"))
				if view != Look.BACK:
					var lx := 0.0 if view == Look.FRONT else 3.4
					Look._rect(ci, Rect2(c.x + lx - 1.3, c.y - 3.0, 2.6, 2.2), col)
					Look._dot(ci, c + Vector2(lx, -1.9), 0.7, Color("fff6c8") if p.get("lit", true) else Color("5a5a52"))
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
static func face(ci, view: int, c: Vector2, f: Dictionary) -> void:
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
			"gasmask":
				# A gas mask: a rubber face, two round eyes, a filter at the mouth.
				match view:
					Look.FRONT:
						Look._dot(ci, c + Vector2(0, 0.8), 3.6, col)
						for sx in [-1.0, 1.0]:
							Look._dot(ci, c + Vector2(1.5 * sx, -0.2), 1.0, Color("2a3a44"))
						Look._dot(ci, c + Vector2(0, 3.0), 1.4, col.darkened(0.3))
					Look.SIDE:
						Look._poly(ci, PackedVector2Array([c + Vector2(0.8, -2.0), c + Vector2(4.4, -1.4), c + Vector2(4.6, 3.4), c + Vector2(1.0, 3.6)]), col)
						Look._dot(ci, c + Vector2(3.4, -0.2), 0.9, Color("2a3a44"))
						Look._dot(ci, c + Vector2(4.8, 2.6), 1.3, col.darkened(0.3))
					Look.BACK:
						for sx in [-1.0, 1.0]:
							Look._line(ci, c + Vector2(4.0 * sx, -1.2), c + Vector2(2.4 * sx, 1.8), col.darkened(0.2), 0.5)  # the straps
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
static func arm_guard(ci, elbow: Vector2, hand: Vector2, g: Dictionary, sh := Vector2.INF) -> void:
	for p in parts(g):
		if p.get("shape", "") == "armband" and sh != Vector2.INF:
			# A pra jiad: cloth knotted round the upper arm, the tails hanging.
			var at := sh.lerp(elbow, 0.55)
			var n := (elbow - sh).orthogonal().normalized()
			Look._line(ci, at - n * 1.6, at + n * 1.6, p.col, 1.0)
			Look._line(ci, at + n * 1.4, at + n * 1.4 + (elbow - sh).normalized() * 1.8, (p.col as Color).darkened(0.15), 0.5)
		elif p.get("shape", "") == "armguards":
			var col: Color = p.col
			var a := elbow.lerp(hand, 0.12)
			var b := elbow.lerp(hand, 0.78)
			Look._limb(ci, a, b, 3.0, 2.7, col)
			for t in [0.3, 0.6]:
				var m := a.lerp(b, t)
				var n := (b - a).orthogonal().normalized() * 1.4
				Look._line(ci, m - n, m + n, Color("8a9098"), 0.5)  # tape


## A glove over the hand (drawn by Look._draw_arm).
static func glove(ci, hand: Vector2, fist: bool, g: Dictionary) -> void:
	for p in parts(g):
		if p.get("shape", "") == "gloves":
			var col: Color = p.col
			var big: bool = p.get("big", false)  # boxing gloves
			Look._dot(ci, hand, (2.5 if big else (1.7 if fist else 1.45)), col)
			Look._dot(ci, hand + Vector2(-0.4, -0.4) * (1.6 if big else 1.0), 0.9 if big else 0.6, col.lightened(0.2))
			if big:
				Look._dot(ci, hand + Vector2(0.9, 1.0), 0.8, Color("f0ece4"))  # the cuff


# --- Body pieces (moved here from Look unchanged) -----------------------------------

## Armour vest (or a hi-vis rider's vest) over the shirt: panel front and back.
static func _vest(ci, view: int, v: Dictionary) -> void:
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
	if v.get("pockets", false) and view != Look.BACK:
		# A work vest: pockets all over the front.
		for x in ([-w * 0.55, w * 0.2] if view == Look.FRONT else [w * 0.1]):
			Look._rect(ci, Rect2(x, -17.2, w * 0.35, 1.8), col.darkened(0.2))
			Look._rect(ci, Rect2(x, -14.4, w * 0.35, 2.2), col.darkened(0.2))


## Backpack seen from the front (only the straps) or from behind (the whole bag).
static func _pack(ci, view: int, p: Dictionary) -> void:
	var col: Color = p.col
	var big: bool = p.get("big", false)
	var g := Look._girth
	if view == Look.FRONT:
		for sx in [-1.0, 1.0]:
			Look._line(ci, Vector2(2.9 * sx * g, -19.6), Vector2(2.6 * sx * g, -12.8), col.darkened(0.25), 1.0)
		return
	if p.get("basket", false):
		# A rattan basket on the back: woven, open at the top.
		var bk := Rect2(-4.0, -20.4, 8.0, 8.6)
		Look._rect(ci, bk, col)
		for i in 4:
			Look._line(ci, Vector2(bk.position.x, bk.position.y + 1.5 + i * 2.0), Vector2(bk.end.x, bk.position.y + 1.5 + i * 2.0), col.darkened(0.25), 0.4)
		Look._rect(ci, Rect2(bk.position, Vector2(bk.size.x, 1.0)), col.lightened(0.15))  # the rim
		return
	if p.get("box", false):
		# A food-delivery box: square, bright, the lid lighter, a stripe round it.
		var br := Rect2(-4.4, -21.0, 8.8, 9.0)
		Look._rect(ci, Rect2(br.position + Vector2(0.3, 0.6), br.size), Color(0, 0, 0, 0.25))
		Look._rect(ci, br, col)
		Look._rect(ci, Rect2(br.position, Vector2(br.size.x, 1.6)), col.lightened(0.15))
		Look._rect(ci, Rect2(br.position + Vector2(0, 4.2), Vector2(br.size.x, 1.2)), p.get("col2", Color.WHITE))
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
static func _pack_side(ci, p: Dictionary) -> void:
	var col: Color = p.col
	var big: bool = p.get("big", false)
	var h := 9.5 if big else 7.0
	var d := 3.4 if big else 2.6
	if p.get("box", false):
		h = 9.0
		d = 5.2
	var x := -3.0 * Look._girth
	Look._rect(ci, Rect2(x - d, -19.8, d + 1.0, h), col.darkened(0.08))
	Look._rect(ci, Rect2(x - d, -19.8, d + 1.0, 2.2), col.darkened(0.22))
	if big:
		Look._rect(ci, Rect2(x - d - 0.2, -21.2, d + 1.4, 1.6), Color("6a5a3a"))


# --- New pieces -------------------------------------------------------------------------

## A shoulder bag: the strap runs from the right shoulder to the left hip,
## where the bag hangs. Side-on it hangs at the hip nearest us, or behind.
static func _satchel_strap(ci, view: int, p: Dictionary) -> void:
	var col: Color = (p.col as Color).darkened(0.3)
	var g := Look._girth
	match view:
		Look.FRONT:
			Look._line(ci, Vector2(3.0 * g, -19.4), Vector2(-3.0 * g, -11.6), col, 0.9)
		Look.BACK:
			Look._line(ci, Vector2(-3.0 * g, -19.4), Vector2(3.0 * g, -11.6), col, 0.9)
		Look.SIDE:
			Look._line(ci, Vector2(0.4, -19.4), Vector2(-0.6, -11.4), col, 0.9)


static func _satchel_bag(ci, view: int, p: Dictionary, behind: bool) -> void:
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
static func _coat(ci, view: int, r: Dictionary, p: Dictionary) -> void:
	# (Drawn with the upper body, so it bobs and sits with it.)
	var col: Color = p.col
	var w := (3.1 if view == Look.SIDE else 4.0) * Look._girth
	var top := -11.0
	var bot := -5.2
	Look._poly(ci, PackedVector2Array([Vector2(-w, top), Vector2(w, top), Vector2(w * 1.08, bot), Vector2(-w * 1.08, bot)]), col.darkened(0.06))
	if view == Look.FRONT:
		Look._line(ci, Vector2(0, top), Vector2(0, bot), col.darkened(0.3), 0.4)  # where it buttons
	Look._line(ci, Vector2(-w * 1.08, bot), Vector2(w * 1.08, bot), col.darkened(0.25), 0.5)  # hem


## Round the waist: a pha khao ma (checked cloth, knotted at the side), a bum
## bag (a pouch at the front), a tool belt (pouches, a hammer's handle).
static func _waist(ci, view: int, shape: String, p: Dictionary) -> void:
	var col: Color = p.col
	var w := (3.1 if view == Look.SIDE else 4.0) * Look._girth
	var y := -12.0
	match shape:
		"sash":
			Look._rect(ci, Rect2(-w, y - 0.4, w * 2, 2.2), col)
			var c2: Color = p.get("col2", col.darkened(0.35))
			for i in 5:
				Look._rect(ci, Rect2(-w + i * w * 0.42, y - 0.4, w * 0.18, 2.2), c2)  # the checks
			if view != Look.BACK:
				var x := w * 0.55 if view == Look.FRONT else 0.4
				Look._rect(ci, Rect2(x, y + 1.6, 1.2, 3.0), col.darkened(0.08))  # the knot's ends
				Look._rect(ci, Rect2(x + 1.3, y + 1.6, 1.0, 2.4), c2)
		"bumbag":
			Look._line(ci, Vector2(-w, y + 0.4), Vector2(w, y + 0.4), col.darkened(0.35), 0.5)
			if view == Look.FRONT:
				Look._rect(ci, Rect2(-2.2, y - 0.6, 4.4, 2.8), col)
				Look._line(ci, Vector2(-2.0, y), Vector2(2.0, y), col.lightened(0.3), 0.3)  # the zip
			elif view == Look.SIDE:
				Look._rect(ci, Rect2(w - 1.2, y - 0.6, 2.2, 2.8), col)
		"toolbelt":
			Look._rect(ci, Rect2(-w, y - 0.2, w * 2, 1.4), col.darkened(0.2))
			for x in ([-w * 0.9, w * 0.35] if view != Look.SIDE else [-0.6]):
				Look._rect(ci, Rect2(x, y + 1.0, w * 0.55, 2.6), col)  # pouches
			if view != Look.BACK:
				Look._line(ci, Vector2(w * 0.7, y + 1.0), Vector2(w * 0.8, y + 5.0), Color("7a5a3a"), 0.8)  # a hammer's handle


# --- Seen from above (TopRig: a body lying flat along the screen) ------------------

## template -> the TopRig layers it draws at. Every template in TEMPLATES
## needs its entry here too, so what's worn shows on a body lying down
## (tests/test_clothes.gd checks). TopRig calls top() at each layer:
##   under  beneath the body (a backpack someone lies on)
##   knee   on the legs      back   on the back / chest   front  the shoulders turned to you
##   arms   gloves and arm guards: drawn with the arms themselves, the same
##          Clothes.glove and arm_guard as standing (nothing to do here)
##   neck   at the neck, before the head
##   head   hats and what's on the face: drawn with the head itself, the same
##          Look._head as standing up (so nothing to do here)
const TOP_TEMPLATES := {
	hoodie = ["neck"],
	hood = ["neck"],
	vest = ["back", "front"],
	pack = ["under", "back"],
	satchel = ["back"],
	coat = ["back"],
	helmet = ["head"],
	cap = ["head"],
	fullface = ["head"],
	mask = ["head"],
	glasses = ["head"],
	gloves = ["arms"],
	armguards = ["arms"],
	kneepads = ["knee"],
	shinguards = ["knee"],
	scarf = ["neck"],
	bucket = ["head"],
	beanie = ["head"],
	hardhat = ["head"],
	whistle = ["neck"],
	apron = ["back"],
	sash = ["waist"],
	bumbag = ["waist"],
	toolbelt = ["waist"],
	skirt = ["back"],
	sarong = ["back"],
	ngop = ["head"],
	halfhelmet = ["head"],
	headlamp = ["head"],
	gasmask = ["head"],
	lifejacket = ["back"],
	armband = ["arms"],
}


## Everything worn that draws at TopRig layer `layer`, in slot order.
static func top(ci, layer: String, r: Dictionary, lk: Dictionary) -> void:
	var wear: Dictionary = lk.get("wear", {})
	if wear.is_empty():
		return
	for e in _by_layer(wear, "_top_layers", TOP_TEMPLATES).get(layer, []):
		_top(ci, layer, e[0], e[1], r, lk)


static func _top(ci, layer: String, shape: String, p: Dictionary, r: Dictionary, lk: Dictionary) -> void:
	var col: Color = p.get("col", Color.GRAY)
	var hc: Vector2 = r.head
	var n: Vector2 = r.neck
	var w: Vector2 = r.waist
	var face: bool = r.face  # (the face is turned up or toward you)
	var prone: bool = r.mode == "prone"
	var mid := w.lerp(n, 0.6)  # the middle of the upper back (or chest)
	var dn := 1.0 if n.y > w.y else -1.0  # which way the shoulders lie from the waist
	match [shape, layer]:
		["hoodie", "neck"], ["hood", "neck"]:
			var hood := ((lk.shirt as Color) if shape == "hoodie" else col).darkened(0.18)
			if prone and not r.toward:
				Look._poly(ci, _half(n + Vector2(0, 0.6), 3.8, false), hood)  # lying on the back of the neck
			else:
				Look._dot(ci, hc + Vector2(0, -1.6), 4.3, hood)  # behind the head
		["scarf", "neck"]:
			Look._rect(ci, Rect2(n.x - 3.4, n.y - 1.2, 6.8, 2.4), col)
			Look._rect(ci, Rect2(n.x - 3.4, n.y - 1.2, 6.8, 0.7), col.lightened(0.15))
		["vest", "back"]:
			Look._poly(ci, PackedVector2Array([w + Vector2(-3.9, 0.3 * dn), w + Vector2(3.9, 0.3 * dn), n + Vector2(5.0, -0.4 * dn), n + Vector2(-5.0, -0.4 * dn)]), col)
			if p.get("plate", false):
				Look._rect(ci, Rect2(mid.x - 2.6, mid.y - 2.2, 5.2, 4.4), col.darkened(0.2))
		["vest", "front"]:
			Look._poly(ci, PackedVector2Array([n + Vector2(-5.2, -0.6), n + Vector2(5.2, -0.6), n + Vector2(4.6, 1.4), n + Vector2(-4.6, 1.4)]), col.darkened(0.2))
		["pack", "under"]:
			if not prone:
				var hw := 5.4 if p.get("big", false) else 4.6
				Look._rect(ci, Rect2(mid.x - hw - 1.4, mid.y - 3.0, (hw + 1.4) * 2.0, 6.0), col.darkened(0.25))  # peeking out either side
		["pack", "back"]:
			if prone:
				var big: bool = p.get("big", false)
				var hw := 3.8 if big else 3.2
				var hh := 4.6 if big else 3.6
				var c := n.lerp(w, 0.42)
				for s in [-1.0, 1.0]:
					Look._line(ci, c + Vector2(s * hw * 0.7, -hh * dn), n + Vector2(s * 3.4, 0), col.darkened(0.3), 0.9)  # straps
				Look._rect(ci, Rect2(c.x - hw, c.y - hh, hw * 2.0, hh * 2.0), col)
				Look._rect(ci, Rect2(c.x - hw, c.y - hh * dn - (1.4 if dn > 0 else 0.0), hw * 2.0, 1.4), col.lightened(0.18))  # the flap
				if big:
					Look._rect(ci, Rect2(c.x - hw + 1.0, c.y + (hh - 2.6) * dn - (1.6 if dn < 0 else 0.0), hw * 2.0 - 2.0, 1.6), col.darkened(0.15))  # a pocket
		["satchel", "back"]:
			var a: Vector2 = r.sh[0]
			Look._line(ci, a, w + Vector2(3.6, 0), col.darkened(0.2), 1.0)
			Look._rect(ci, Rect2(w.x + 2.6, w.y - 1.8, 3.2, 3.6), col)
		["coat", "back"]:
			# The tails over the seat, a little down the legs.
			Look._poly(ci, PackedVector2Array([w + Vector2(-4.6, 0), w + Vector2(4.6, 0), w + Vector2(4.8, -4.0 * dn), w + Vector2(-4.8, -4.0 * dn)]),
					(lk.shirt as Color).darkened(0.1) if p.get("covers", false) else col)
		["skirt", "back"], ["sarong", "back"]:
			# Over the thighs (and a pha thung on down the shins).
			var k0: Vector2 = (r.knee[0] as Vector2).lerp(r.knee[1], 0.5)
			var f0: Vector2 = (r.foot[0] as Vector2).lerp(r.foot[1], 0.5)
			var end := k0 if shape == "skirt" else k0.lerp(f0, 0.8)
			var hw := 4.2 if shape == "skirt" else 3.6
			Look._poly(ci, PackedVector2Array([w + Vector2(-3.8, 0), w + Vector2(3.8, 0), end + Vector2(hw, 0), end + Vector2(-hw, 0)]), col)
		["lifejacket", "back"]:
			Look._poly(ci, PackedVector2Array([w + Vector2(-4.6, 0.3 * dn), w + Vector2(4.6, 0.3 * dn), n + Vector2(5.6, -0.4 * dn), n + Vector2(-5.6, -0.4 * dn)]), col)
			Look._line(ci, mid + Vector2(-4.4, 0), mid + Vector2(4.4, 0), Color("e8e4d0"), 0.7)
		["whistle", "neck"]:
			if face:
				Look._rect(ci, Rect2(n.x - 0.6, n.y + 1.6 * -dn, 1.6, 0.9), col)
		["apron", "back"]:
			if r.mode == "supine":  # (on the chest: lying on the back)
				Look._poly(ci, PackedVector2Array([w + Vector2(-3.6, 0), w + Vector2(3.6, 0), mid + Vector2(2.2, 0), mid + Vector2(-2.2, 0)]), col)
		["sash", "waist"], ["bumbag", "waist"], ["toolbelt", "waist"]:
			var band: Color = col if shape != "toolbelt" else col.darkened(0.2)
			Look._rect(ci, Rect2(w.x - 3.9, w.y - 1.0, 7.8, 2.0), band)
			if shape == "sash":
				for i in 4:
					Look._rect(ci, Rect2(w.x - 3.6 + i * 2.2, w.y - 1.0, 0.8, 2.0), p.get("col2", col.darkened(0.35)))
			elif shape == "bumbag" and r.mode == "supine":
				Look._rect(ci, Rect2(w.x - 2.0, w.y - 1.4, 4.0, 2.8), col.lightened(0.05))
		["kneepads", "knee"]:
			for k in r.knee:  # (as standing: the pad and its light edge)
				Look._rect(ci, Rect2(k + Vector2(-1.6, -1.2), Vector2(3.2, 2.2)), col)
				Look._rect(ci, Rect2(k + Vector2(-1.2, -1.0), Vector2(2.4, 0.6)), col.lightened(0.25))
		["shinguards", "knee"]:
			for i in 2:
				TopRig._limb(ci, (r.knee[i] as Vector2).lerp(r.foot[i], 0.15), (r.knee[i] as Vector2).lerp(r.foot[i], 0.75), 3.0, col)


## Half a disc: the top half (up the screen), or with `top` false the bottom.
static func _half(c: Vector2, rad: float, top := true) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 9:
		var t := PI + PI * i / 8.0
		pts.append(c + Vector2(cos(t), sin(t) if top else -sin(t)) * rad)
	return pts


# --- Patterns and details on the shirt and trousers ------------------------------
# A shirt's `pattern` (stripe, plaid, floral, dots, camo, print) and `detail`
# (buttons, tie, school, vneck, collar, number, badge) are drawn over the body
# by these, given its four corners (the shoulders' left and right, the waist's
# right and left): the same code standing (Look._torso) and lying (TopRig._back).
# `front`: we see the chest (prints and most details are on the front; a
# jersey's number on the back).

## The point at (u, v) across the body: u 0..1 left to right, v 0..1 shoulders to waist.
static func _at(q: Array, u: float, v: float) -> Vector2:
	return (q[0] as Vector2).lerp(q[1], u).lerp((q[3] as Vector2).lerp(q[2], u), v)


static func _band(ci, q: Array, u0: float, v0: float, u1: float, v1: float, col: Color) -> void:
	Look._poly(ci, PackedVector2Array([_at(q, u0, v0), _at(q, u1, v0), _at(q, u1, v1), _at(q, u0, v1)]), col)


## Spots over a body for flowers and dots: fixed, so every frame looks the same.
const _SPOTS := [Vector2(0.18, 0.15), Vector2(0.62, 0.1), Vector2(0.4, 0.38), Vector2(0.82, 0.42), Vector2(0.15, 0.62),
		Vector2(0.58, 0.7), Vector2(0.86, 0.8), Vector2(0.3, 0.86)]


## The pattern and details of what's worn on the body (none under a coat that covers it).
static func shirt_marks(ci, q: Array, lk: Dictionary, front: bool, side := false) -> void:
	var wear: Dictionary = lk.get("wear", {})
	if wear.get("over", {}).get("covers", false):
		return
	var d: Dictionary = wear.get("body", {})
	if d.is_empty() or (not d.has("pattern") and not d.has("detail")):
		return
	var col: Color = lk.shirt
	var c2: Color = d.get("col2", col.darkened(0.35))
	match d.get("pattern", ""):
		"stripe":
			for i in 5:
				var v0 := 0.06 + i * 0.18
				_band(ci, q, 0.0, v0, 1.0, v0 + 0.07, c2)
		"plaid":
			for i in 4:
				var t := 0.12 + i * 0.25
				_band(ci, q, 0.0, t, 1.0, t + 0.08, Color(c2, 0.55))
				_band(ci, q, t, 0.0, t + 0.08, 0.9, Color(c2, 0.55))
		"floral", "dots":
			# (Little squares, not round dots: at this size they look the same, and
			# they draw in one batch with the rest of the body.)
			var big: bool = d.pattern == "floral"
			for s: Vector2 in _SPOTS:
				var p := _at(q, s.x, s.y)
				if big:
					_spot(ci, p, 0.75, c2)
					_spot(ci, p, 0.3, Color("f0d050"))
				else:
					_spot(ci, p, 0.45, c2)
		"camo":
			for i in _SPOTS.size():
				var s: Vector2 = _SPOTS[i]
				_spot(ci, _at(q, s.x, s.y), 1.0 if i % 2 else 0.75, c2 if i % 3 else col.darkened(0.3))
		"print":
			if front and not side:
				_band(ci, q, 0.28, 0.2, 0.72, 0.55, c2)  # the print on the chest
				_band(ci, q, 0.34, 0.28, 0.66, 0.33, c2.lightened(0.45))  # (its words, too small to read here)
				_band(ci, q, 0.38, 0.4, 0.62, 0.45, c2.lightened(0.45))
	if side:
		return
	var dark := col.darkened(0.35)
	match d.get("detail", ""):
		"buttons":
			if front:
				Look._line(ci, _at(q, 0.5, 0.02), _at(q, 0.5, 0.88), dark, 0.4)
				for v in [0.2, 0.45, 0.7]:
					_spot(ci, _at(q, 0.53, v), 0.3, col.lightened(0.4))
				_collar(ci, q, col.lightened(0.12))
		"tie":
			if front:
				_collar(ci, q, col.lightened(0.12))
				Look._poly(ci, PackedVector2Array([_at(q, 0.46, 0.03), _at(q, 0.54, 0.03), _at(q, 0.53, 0.1), _at(q, 0.47, 0.1)]), c2.darkened(0.2))
				Look._poly(ci, PackedVector2Array([_at(q, 0.47, 0.1), _at(q, 0.53, 0.1), _at(q, 0.56, 0.62), _at(q, 0.5, 0.7), _at(q, 0.44, 0.62)]), c2)
		"school":
			if front:
				Look._line(ci, _at(q, 0.5, 0.02), _at(q, 0.5, 0.88), dark.lightened(0.3), 0.4)
				_collar(ci, q, col.lightened(0.05))
				_band(ci, q, 0.62, 0.22, 0.8, 0.26, c2)  # the school's initials over the pocket
				Look._polyline(ci, PackedVector2Array([_at(q, 0.62, 0.3), _at(q, 0.62, 0.45), _at(q, 0.8, 0.45), _at(q, 0.8, 0.3)]), dark.lightened(0.2), 0.3)
		"vneck":
			if front:
				Look._poly(ci, PackedVector2Array([_at(q, 0.38, 0.0), _at(q, 0.62, 0.0), _at(q, 0.5, 0.22)]), (lk.skin as Color).darkened(0.05))
				Look._polyline(ci, PackedVector2Array([_at(q, 0.36, 0.0), _at(q, 0.5, 0.24), _at(q, 0.64, 0.0)]), dark, 0.4)
				_band(ci, q, 0.18, 0.3, 0.34, 0.42, dark.lightened(0.15))  # the chest pocket
		"collar":
			if front:
				_collar(ci, q, col.lightened(0.12))
				Look._line(ci, _at(q, 0.5, 0.05), _at(q, 0.5, 0.3), dark, 0.4)
		"number":
			var at: Vector2 = _at(q, 0.5, 0.42)
			if not front:  # the big number on the back
				for x in [-1.3, 1.3]:
					Look._rect(ci, Rect2(at + Vector2(x - 0.7, -2.0), Vector2(1.4, 4.0)), c2)
			else:
				_spot(ci, _at(q, 0.7, 0.25), 0.6, c2)  # the club's crest
		"badge":
			if front:
				_spot(ci, _at(q, 0.72, 0.28), 0.7, Color("d8b040"))  # a guard's badge
				_band(ci, q, 0.2, 0.25, 0.38, 0.31, c2)  # the name tag
			_band(ci, q, 0.0, 0.0, 0.16, 0.14, c2)  # shoulder patches
			_band(ci, q, 0.84, 0.0, 1.0, 0.14, c2)


static func _collar(ci, q: Array, col: Color) -> void:
	Look._poly(ci, PackedVector2Array([_at(q, 0.34, 0.0), _at(q, 0.5, 0.0), _at(q, 0.44, 0.13)]), col)
	Look._poly(ci, PackedVector2Array([_at(q, 0.5, 0.0), _at(q, 0.66, 0.0), _at(q, 0.56, 0.13)]), col)


## A pattern down trousers (camo, elephant pants' print): spots along each
## leg from hip to knee to foot.
static func leg_marks(ci, hip: Vector2, knee: Vector2, foot: Vector2, lk: Dictionary, far := false) -> void:
	var d: Dictionary = lk.get("wear", {}).get("legs", {})
	if not d.has("pattern"):
		return
	var c2: Color = (d.get("col2", (lk.pants as Color).darkened(0.35)) as Color).darkened(0.18 if far else 0.0)
	var shorts: bool = lk.get("shorts", false)
	for t in [0.2, 0.55, 0.85]:
		_spot(ci, hip.lerp(knee, t) + Vector2(0.4 if t > 0.5 else -0.3, 0), 0.5 if d.pattern != "camo" else 0.75, c2)
	if not shorts:
		for t in [0.3, 0.7]:
			_spot(ci, knee.lerp(foot, t) + Vector2(-0.3 if t > 0.5 else 0.3, 0), 0.45 if d.pattern != "camo" else 0.7, c2)


## A small square of colour centred on `p` (see shirt_marks).
static func _spot(ci, p: Vector2, r: float, col: Color) -> void:
	Look._rect(ci, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), col)
