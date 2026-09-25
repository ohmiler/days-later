class_name Items
## Every item in the game, how searching turns them up, how much they weigh
## and how they are drawn as icons. The items themselves are in
## data/items.cfg, one section each (its top says what every field means):
## to add an item, add a section there. This file is the rules around them.

const DATA := "res://data/items.cfg"  # (exports must include *.cfg: Export > Resources > filters)
const INV_SIZE := 8  # the hotbar; a bag adds slots after these, reached from the bag screen (Tab)

## Places on the body something can be worn, and what they're called.
## "over" is a second layer on the body: a vest goes on top of a shirt.
const SLOTS := ["head", "body", "over", "legs", "feet", "back"]
const SLOT_NAMES := {head = "หัว", body = "ตัว", over = "ทับเสื้อ", legs = "ขา", feet = "เท้า", back = "หลัง"}
const MAX_ARMOR := 0.6

## Kilograms a survivor carries before slowing down (a bag adds its `carry`).
## Past it they slow, down to OVERLOAD_SPEED at OVERLOAD times the limit.
const CARRY := 15.0
const OVERLOAD := 1.5
const OVERLOAD_SPEED := 0.6

const TYPES := ["weapon", "use", "trap", "material", "wear", "junk"]
const PLACES := ["store", "med", "food", "tools", "valuables", "clothes", "home"]
## How often searching turns each up, relative to each other.
const RARITY := {common = 4, uncommon = 2, rare = 1}
const RARITY_NAMES := {common = "ธรรมดา", uncommon = "ไม่บ่อย", rare = "หายาก"}
const RARITY_COLORS := {common = Color("c8c4b8"), uncommon = Color("6ab0e0"), rare = Color("e0b840")}
## Icon shapes an item's `icon` can use (drawn in draw_icon).
const ICONS := ["roll", "blister", "kit", "pillbox", "bottle", "cup", "packet", "can", "coil", "board", "planks", "chain", "rag", "nails", "tape", "scrap", "magazine"]

## id -> fields, read from DATA the first time Items is used.
static var DEFS: Dictionary = _load_defs()
## place -> [[item, weight]], built from each item's places and rarity.
static var LOOT: Dictionary = _build_loot()


static func _load_defs() -> Dictionary:
	var cf := ConfigFile.new()
	var err := cf.load(DATA)
	if err != OK:
		push_error("Could not read %s (error %d)" % [DATA, err])
		return {}
	var out := {}
	for id in cf.get_sections():
		var d := {}
		for key in cf.get_section_keys(id):
			d[key] = _colours(key, cf.get_value(id, key))
		out[id] = d
	return out


## Colours are written as hex strings in the file; any field named col... is one.
static func _colours(key, v):
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _colours(k, v[k])
		return out
	if v is String and str(key).begins_with("col"):
		return Color(v)
	return v


static func _build_loot() -> Dictionary:
	var out := {}
	for place in PLACES:
		out[place] = []
	for id in DEFS:
		for place in DEFS[id].get("places", []):
			if out.has(place):
				out[place].append([id, RARITY.get(DEFS[id].get("rarity", "common"), 1)])
	return out


## What is wrong with the item table, one line each ([] when all is well).
## The tests run this, so a typo in data/items.cfg is caught straight away.
static func problems() -> Array:
	var out := []
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		for key in ["name", "type", "weight", "rarity"]:
			if not d.has(key):
				out.append("%s: no %s" % [id, key])
		if d.get("type") not in TYPES:
			out.append("%s: unknown type %s" % [id, d.get("type")])
		if d.get("rarity") not in RARITY:
			out.append("%s: unknown rarity %s" % [id, d.get("rarity")])
		if not (d.get("weight") is float or d.get("weight") is int) or d.get("weight", 0) < 0:
			out.append("%s: weight must be a number" % id)
		for place in d.get("places", []):
			if place not in PLACES:
				out.append("%s: unknown place %s" % [id, place])
		for part in d.get("salvage", {}):
			if not DEFS.has(part):
				out.append("%s: salvage gives unknown item %s" % [id, part])
		if d.has("repair") and not DEFS.has(d.repair):
			out.append("%s: repaired with unknown item %s" % [id, d.repair])
		match d.get("type"):
			"weapon":
				for key in ["range", "dmg", "cd", "dur", "hp", "draw"]:
					if not d.has(key):
						out.append("%s: a weapon needs %s" % [id, key])
			"wear":
				if d.get("slot") not in SLOTS:
					out.append("%s: unknown slot %s" % [id, d.get("slot")])
				if not d.has("draw") or not d.has("hp"):
					out.append("%s: clothes need draw and hp" % id)
			_:
				if d.get("icon", {}).get("shape") not in ICONS:
					out.append("%s: unknown icon shape %s" % [id, d.get("icon", {}).get("shape")])
	return out


## Furniture that goes in each kind of place.
const FURNITURE := {
	"store": ["shelf", "fridge", "shelf", "counter"],
	"med": ["shelf", "counter", "cabinet"],
	"food": ["fridge", "counter", "table"],
	"tools": ["crate", "shelf", "cabinet"],
	"valuables": ["counter", "cabinet", "crate"],
	"clothes": ["shelf", "cabinet", "counter"],
	"home": ["cabinet", "bed", "table"],
}


static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})


## One line on what a consumable does, for the hotbar.
static func effect_text(id: String) -> String:
	var d := def(id)
	var parts := []
	if d.get("heal", 0.0) > 0:
		parts.append("เลือด +%d" % d.heal)
	if d.get("food", 0.0) > 0:
		parts.append("อิ่ม +%d" % d.food)
	if d.get("drink", 0.0) > 0:
		parts.append("น้ำ +%d" % d.drink)
	if d.get("cure", 0.0) > 0:
		parts.append("เชื้อ -%d" % d.cure)
	if d.get("stop_bleed", false):
		parts.append("ห้ามเลือด")
	if d.get("stamina", 0.0) > 0:
		parts.append("แรงเต็ม")
	return " · ".join(parts)


## One line on what a piece of clothing does.
static func wear_text(id: String) -> String:
	var d := def(id)
	var parts := ["สวมที่" + SLOT_NAMES[d.slot]]
	if d.get("armor", 0.0) > 0:
		parts.append("กันกัด %d%%" % roundi(d.armor * 100))
	if d.get("bag", 0) > 0:
		parts.append("ช่องเก็บของ +%d" % d.bag)
	if d.get("speed", 1.0) < 1.0:
		parts.append("เดินช้าลง")
	elif d.get("speed", 1.0) > 1.0:
		parts.append("เดินเร็วขึ้น")
	return " · ".join(parts)


static func is_wear(id: String) -> bool:
	return def(id).get("type", "") == "wear"


## What a zombie is wearing, picked from its id so every machine agrees:
## slot -> item id. Plenty of the city's dead were motorbike taxi riders.
static func zombie_wear(zid: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = zid * 7919 + 17
	var out := {}
	var roll := rng.randf()
	if roll < 0.06:
		out.head = "helmet"
		out.over = "rider"
	elif roll < 0.1:
		out.head = "helmet"
	elif roll < 0.16:
		out.head = "cap"
	roll = rng.randf()
	if not out.has("over") and roll < 0.02:
		out.over = "vest"
	elif not out.has("over"):
		if roll < 0.1:
			out.body = "hoodie"
		elif roll < 0.15:
			out.body = "jacket"
	roll = rng.randf()
	if roll < 0.25:
		out.legs = "jeans"
	elif roll < 0.35:
		out.legs = "shorts"
	roll = rng.randf()
	if roll < 0.06:
		out.feet = "boots"
	elif roll < 0.14:
		out.feet = "sneakers"
	roll = rng.randf()
	if roll < 0.06:
		out.back = "schoolbag"
	elif roll < 0.09:
		out.back = "backpack"
	return out


## The look dictionary's `wear` entry for a set of worn item ids.
static func wear_draw(ids: Dictionary) -> Dictionary:
	var out := {}
	for slot in ids:
		var d := def(ids[slot])
		if d.has("draw"):
			out[slot] = d.draw
	return out


static func stack(id: String) -> int:
	return def(id).get("stack", 1)


static func has_tag(id: String, tag: String) -> bool:
	return tag in def(id).get("tags", [])


## Kilograms of one slot's worth: the item times how many.
static func weight_of(it) -> float:
	return 0.0 if it == null else float(def(it.id).get("weight", 0.0)) * it.get("n", 1)


static func rarity_of(id: String) -> String:
	return def(id).get("rarity", "common")


static func is_weapon(id: String) -> bool:
	return def(id).get("type", "") == "weapon"


static func display_name(id: String) -> String:
	return def(id).get("name", id)


## 0-3 random items from a loot table; about a quarter of places are already picked clean.
static func roll(table: String, rng: RandomNumberGenerator) -> Array:
	var entries: Array = LOOT.get(table, LOOT.home)
	var out := []
	if rng.randf() < 0.25:
		return out
	var total := 0
	for e in entries:
		total += e[1]
	for i in rng.randi_range(1, 3):
		var r := rng.randi_range(1, total)
		for e in entries:
			r -= e[1]
			if r <= 0:
				out.append(e[0])
				break
	return out


# --- Icons ------------------------------------------------------------------

static func draw_icon(ci: CanvasItem, r: Rect2, id: String) -> void:
	var d := def(id)
	var c := r.get_center()
	if d.get("type") == "weapon":
		var w: Dictionary = d.draw
		var dirv := Vector2(1, -1).normalized()
		var scale: float = r.size.x / (w.len + 6.0) * 0.95
		ci.draw_set_transform(c - dirv * (w.len * 0.5 - 1.0) * scale, 0, Vector2(scale, scale))
		Look._draw_weapon(ci, Vector2.ZERO, dirv, w)
		ci.draw_set_transform(Vector2.ZERO)
		return
	if d.get("type") == "wear":
		_wear_icon(ci, r, d)
		return
	_shape_icon(ci, r, d.get("icon", {}))


## The icon shapes (see ICONS). `col` is the main colour, `col2` the detail.
## Many items share one shape in different colours: a new drink is a
## "bottle" with its own colours, no drawing code needed.
static func _shape_icon(ci: CanvasItem, r: Rect2, icon: Dictionary) -> void:
	var c := r.get_center()
	var s := r.size.x / 40.0
	var col: Color = icon.get("col", Color("888888"))
	var col2: Color = icon.get("col2", col.lightened(0.3))
	match icon.get("shape", ""):
		"roll":
			ci.draw_circle(c, 11 * s, col)
			ci.draw_circle(c, 4 * s, col2)
		"blister":
			ci.draw_rect(Rect2(c - Vector2(12, 7) * s, Vector2(24, 14) * s), col)
			for i in 4:
				ci.draw_circle(c + Vector2(-8 + i * 5.3, 0) * s, 2 * s, col2)
		"kit":
			ci.draw_rect(Rect2(c - Vector2(13, 10) * s, Vector2(26, 20) * s), col)
			ci.draw_rect(Rect2(c - Vector2(2.5, 7) * s, Vector2(5, 14) * s), col2)
			ci.draw_rect(Rect2(c - Vector2(7, 2.5) * s, Vector2(14, 5) * s), col2)
		"bottle":
			ci.draw_rect(Rect2(c - Vector2(5, 11) * s, Vector2(10, 22) * s), col)
			ci.draw_rect(Rect2(c - Vector2(3, 14) * s, Vector2(6, 4) * s), col2)
			ci.draw_rect(Rect2(c - Vector2(5, 3) * s, Vector2(10, 6) * s), col2.lightened(0.1))
		"cup":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-11, -8) * s, c + Vector2(11, -8) * s,
					c + Vector2(8, 11) * s, c + Vector2(-8, 11) * s]), col)
			ci.draw_rect(Rect2(c + Vector2(-11, -10) * s, Vector2(22, 3) * s), col2)
		"packet":
			ci.draw_rect(Rect2(c - Vector2(9, 12) * s, Vector2(18, 24) * s), col)
			ci.draw_circle(c, 5 * s, col2)
		"can":
			ci.draw_rect(Rect2(c - Vector2(5, 10) * s, Vector2(10, 20) * s), col)
			ci.draw_rect(Rect2(c - Vector2(5, 3) * s, Vector2(10, 6) * s), col2)
		"pillbox":
			var cap := Color("f0ece4")
			ci.draw_rect(Rect2(c - Vector2(7, 8) * s, Vector2(14, 20) * s), col)
			ci.draw_rect(Rect2(c - Vector2(8, 13) * s, Vector2(16, 6) * s), cap)
			ci.draw_rect(Rect2(c - Vector2(5, 2) * s, Vector2(10, 7) * s), cap)
			ci.draw_rect(Rect2(c - Vector2(1, 1) * s, Vector2(2, 5) * s), col2)
		"coil":
			for i in 3:
				ci.draw_arc(c + Vector2(-7 + i * 7, 0) * s, 6 * s, 0, TAU, 12, col, 1.5 * s)
		"board":
			ci.draw_rect(Rect2(c - Vector2(12, 4) * s, Vector2(24, 9) * s), col)
			for i in 5:
				ci.draw_line(c + Vector2(-9 + i * 4.5, -4) * s, c + Vector2(-9 + i * 4.5, -11) * s, col2, 1.5 * s)
		"planks":
			for i in 3:
				var y := (-8 + i * 7) * s
				ci.draw_rect(Rect2(c + Vector2(-13 * s, y), Vector2(26, 5) * s), col.darkened(i * 0.08))
				ci.draw_rect(Rect2(c + Vector2(-13 * s, y), Vector2(26, 1.2) * s), col2)
		"chain":
			ci.draw_arc(c, 9 * s, 0, TAU, 20, col, 3 * s)
			ci.draw_circle(c + Vector2(0, 9) * s, 3 * s, col2)
		"rag":  # a folded bit of cloth
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -6) * s, c + Vector2(10, -9) * s,
					c + Vector2(12, 7) * s, c + Vector2(-10, 9) * s]), col)
			ci.draw_line(c + Vector2(-11, 0) * s, c + Vector2(11, -1) * s, col2, 1.2 * s)
		"nails":
			for i in 4:
				var x := (-8 + i * 5) * s
				ci.draw_line(c + Vector2(x, -9 * s), c + Vector2(x + 2 * s, 9 * s), col, 1.6 * s)
				ci.draw_line(c + Vector2(x - 2 * s, -9 * s), c + Vector2(x + 2 * s, -9 * s), col2, 2 * s)
		"tape":
			ci.draw_circle(c, 11 * s, col)
			ci.draw_circle(c, 5 * s, Color("c8b890"))
			ci.draw_rect(Rect2(c + Vector2(6, 4) * s, Vector2(8, 5) * s), col2)
		"scrap":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 2) * s, c + Vector2(-4, -10) * s,
					c + Vector2(9, -6) * s, c + Vector2(12, 6) * s, c + Vector2(-2, 10) * s]), col)
			ci.draw_circle(c + Vector2(3, 2) * s, 3 * s, col2)  # rust
		"magazine":
			ci.draw_rect(Rect2(c - Vector2(9, 12) * s, Vector2(18, 24) * s), col)
			ci.draw_rect(Rect2(c - Vector2(9, 12) * s, Vector2(18, 7) * s), col2)
			ci.draw_rect(Rect2(c + Vector2(-6, 0) * s, Vector2(12, 7) * s), col.darkened(0.25))
		_:
			ci.draw_circle(c, 8 * s, col)


## Clothes drawn flat, like laid out on a table.
static func _wear_icon(ci: CanvasItem, r: Rect2, d: Dictionary) -> void:
	var c := r.get_center()
	var s := r.size.x / 40.0
	var w: Dictionary = d.draw
	var col: Color = w.col
	var dark := col.darkened(0.3)
	var P := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + p * s)
		return out
	match w.shape:
		"long", "hoodie", "vest":
			if d.slot == "legs":
				var legs: PackedVector2Array = P.call([Vector2(-10, -14), Vector2(10, -14), Vector2(11, 16), Vector2(3, 16),
						Vector2(0, -4), Vector2(-3, 16), Vector2(-11, 16)])
				ci.draw_colored_polygon(legs, col)
				ci.draw_rect(Rect2(c + Vector2(-10, -14) * s, Vector2(20, 3) * s), dark)
				return
			var sleeve := 0.0 if w.shape == "vest" else 1.0
			var body: PackedVector2Array = P.call([Vector2(-6, -14), Vector2(6, -14), Vector2(10 + 6 * sleeve, -10),
					Vector2(10 + 6 * sleeve, 4 * sleeve - 6 * (1 - sleeve)), Vector2(10, 4 * sleeve - 6 * (1 - sleeve)),
					Vector2(10, 15), Vector2(-10, 15), Vector2(-10, 4 * sleeve - 6 * (1 - sleeve)),
					Vector2(-10 - 6 * sleeve, 4 * sleeve - 6 * (1 - sleeve)), Vector2(-10 - 6 * sleeve, -10)])
			ci.draw_colored_polygon(body, col)
			ci.draw_polyline(body + PackedVector2Array([body[0]]), dark, 1.0)
			if w.shape == "hoodie":
				ci.draw_colored_polygon(P.call([Vector2(-6, -14), Vector2(0, -8), Vector2(6, -14), Vector2(0, -17)]), dark)
			elif w.shape == "vest":
				if w.get("plate", false):
					ci.draw_rect(Rect2(c + Vector2(-8, 2) * s, Vector2(16, 6) * s), col.darkened(0.2))
				else:
					ci.draw_rect(Rect2(c + Vector2(-10, 0) * s, Vector2(20, 2.2) * s), Color("e8e4d0"))
			else:
				ci.draw_line(c + Vector2(0, -13) * s, c + Vector2(0, 15) * s, dark, 1.0)  # zip
		"shorts":
			ci.draw_colored_polygon(P.call([Vector2(-11, -10), Vector2(11, -10), Vector2(12, 8), Vector2(2, 8),
					Vector2(0, 0), Vector2(-2, 8), Vector2(-12, 8)]), col)
			ci.draw_rect(Rect2(c + Vector2(-11, -10) * s, Vector2(22, 3) * s), dark)
		"helmet":
			ci.draw_colored_polygon(P.call(_dome(Vector2(0, 4), 13.0)), col)
			ci.draw_rect(Rect2(c + Vector2(-13, 3) * s, Vector2(26, 3) * s), dark)
			ci.draw_rect(Rect2(c + Vector2(-9, -2) * s, Vector2(18, 3) * s), Color("2a3036"))
		"cap":
			ci.draw_colored_polygon(P.call(_dome(Vector2(-2, 5), 10.0)), col)
			ci.draw_rect(Rect2(c + Vector2(4, 3) * s, Vector2(12, 3) * s), dark)
		"boots", "shoes":
			var tall := 10.0 if w.shape == "boots" else 3.0
			ci.draw_colored_polygon(P.call([Vector2(-8, 8 - tall - 4), Vector2(0, 8 - tall - 4), Vector2(1, 2),
					Vector2(12, 4), Vector2(12, 9), Vector2(-8, 9)]), col)
			ci.draw_rect(Rect2(c + Vector2(-8, 8) * s, Vector2(20, 2) * s), dark if w.shape == "boots" else Color("f0f0e8"))
		"pack":
			var hw := 11.0 if w.get("big", false) else 9.0
			ci.draw_rect(Rect2(c + Vector2(-hw, -12) * s, Vector2(hw * 2, 26) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-hw, -12) * s, Vector2(hw * 2, 7) * s), col.darkened(0.2))
			ci.draw_rect(Rect2(c + Vector2(-5, 4) * s, Vector2(10, 7) * s), col.darkened(0.12))
			ci.draw_arc(c + Vector2(0, -12) * s, 4 * s, PI, TAU, 8, dark, 1.5)


static func _dome(at: Vector2, rad: float) -> Array:
	var pts := []
	for i in 13:
		pts.append(at + Vector2.from_angle(lerpf(PI, TAU, i / 12.0)) * rad)
	return pts
