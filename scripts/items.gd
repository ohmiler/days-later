class_name Items
## Every item in the game, the loot tables that fill shops and homes, and
## how items are drawn as icons. Add an entry to DEFS to add an item.
##
## Weapon fields: range, dmg, cd (cooldown), stun, knock, dur (swing time),
## hp (durability), cleave (hits everything in front), draw (see Look._draw_weapon).

const INV_SIZE := 8
const STACK := 5

## Places on the body something can be worn, and what they're called.
const SLOTS := ["head", "body", "legs", "feet", "back"]
const SLOT_NAMES := {head = "หัว", body = "ตัว", legs = "ขา", feet = "เท้า", back = "หลัง"}
const MAX_ARMOR := 0.6

const DEFS := {
	# Melee weapons
	"plank": {name = "ไม้หน้าสาม", type = "weapon", range = 22.0, dmg = 16.0, cd = 0.55, stun = 0.4, knock = 5.0,
			dur = 0.34, hp = 25, draw = {kind = "plank", len = 11.0, col = Color("9a7a52")}},
	"bat": {name = "ไม้เบสบอล", type = "weapon", range = 24.0, dmg = 22.0, cd = 0.6, stun = 0.5, knock = 7.0,
			dur = 0.34, hp = 40, draw = {kind = "bat", len = 11.5, col = Color("c8a878")}},
	"pipe": {name = "ท่อเหล็ก", type = "weapon", range = 24.0, dmg = 26.0, cd = 0.7, stun = 0.55, knock = 8.0,
			dur = 0.38, hp = 60, draw = {kind = "pipe", len = 12.0, col = Color("8a9096")}},
	"knife": {name = "มีดทำครัว", type = "weapon", range = 17.0, dmg = 18.0, cd = 0.35, stun = 0.2, knock = 2.0,
			dur = 0.24, hp = 30, draw = {kind = "knife", len = 6.5, col = Color("d0d4d8")}},
	"machete": {name = "มีดพร้า", type = "weapon", range = 22.0, dmg = 30.0, cd = 0.55, stun = 0.3, knock = 3.0,
			dur = 0.32, hp = 45, draw = {kind = "machete", len = 10.0, col = Color("b8bcc0")}},
	"axe": {name = "ขวาน", type = "weapon", range = 23.0, dmg = 40.0, cd = 0.9, stun = 0.6, knock = 9.0,
			dur = 0.45, hp = 35, cleave = true, draw = {kind = "axe", len = 11.0, col = Color("7a8088")}},
	"hammer": {name = "ค้อน", type = "weapon", range = 18.0, dmg = 24.0, cd = 0.55, stun = 0.5, knock = 5.0,
			dur = 0.3, hp = 50, draw = {kind = "hammer", len = 8.0, col = Color("5a5e64")}},
	# Consumables. heal = health, food / drink = hunger / thirst restored,
	# cure = infection removed, stop_bleed, stamina.
	"bandage": {name = "ผ้าพันแผล", type = "use", heal = 10.0, stop_bleed = true},
	"painkiller": {name = "ยาแก้ปวด", type = "use", heal = 20.0},
	"firstaid": {name = "ชุดปฐมพยาบาล", type = "use", heal = 50.0, stop_bleed = true},
	"antibiotic": {name = "ยาปฏิชีวนะ", type = "use", cure = 60.0},
	"water": {name = "น้ำดื่ม", type = "use", drink = 45.0},
	"mama": {name = "บะหมี่กึ่งสำเร็จรูป", type = "use", food = 40.0, drink = -5.0},
	"snack": {name = "ขนมถุง", type = "use", food = 20.0},
	"energy": {name = "เครื่องดื่มชูกำลัง", type = "use", food = 5.0, drink = 25.0, stamina = 100.0},
	# Traps: F sets one down on the ground in front of you
	"wire": {name = "ลวดหนาม", type = "trap"},
	"spikes": {name = "กับดักตะปู", type = "trap"},
	# Building material: reinforce or repair doors (R)
	"wood": {name = "ไม้กระดาน", type = "material"},
	# Clothes and armour: F puts one on, Tab shows what you're wearing.
	# armor = share of a bite's damage and infection stopped (pieces add up),
	# hp = bites it takes before it's torn apart, bag = extra hotbar slots,
	# speed = move speed multiplier, draw = how it looks (see Look).
	"hoodie": {name = "เสื้อฮู้ด", type = "wear", slot = "body", armor = 0.05, hp = 15,
			draw = {shape = "hoodie", col = Color("5a5e66")}},
	"jacket": {name = "แจ็กเก็ตหนัง", type = "wear", slot = "body", armor = 0.15, hp = 30,
			draw = {shape = "long", col = Color("3a2a22")}},
	"rider": {name = "เสื้อวินมอไซค์", type = "wear", slot = "body", armor = 0.04, hp = 10,
			draw = {shape = "vest", col = Color("d8781e"), plate = false}},
	"vest": {name = "เสื้อเกราะตำรวจ", type = "wear", slot = "body", armor = 0.3, hp = 60, speed = 0.92,
			draw = {shape = "vest", col = Color("2e3238"), plate = true}},
	"jeans": {name = "กางเกงยีนส์", type = "wear", slot = "legs", armor = 0.08, hp = 25,
			draw = {shape = "long", col = Color("34507a")}},
	"shorts": {name = "กางเกงขาสั้น", type = "wear", slot = "legs", armor = 0.0, hp = 10,
			draw = {shape = "shorts", col = Color("6a6a5e")}},
	"helmet": {name = "หมวกกันน็อก", type = "wear", slot = "head", armor = 0.12, hp = 40,
			draw = {shape = "helmet", col = Color("c8c4b8")}},
	"cap": {name = "หมวกแก๊ป", type = "wear", slot = "head", armor = 0.0, hp = 10,
			draw = {shape = "cap", col = Color("8a2a26")}},
	"boots": {name = "รองเท้าบูท", type = "wear", slot = "feet", armor = 0.05, hp = 40,
			draw = {shape = "boots", col = Color("3a2a1c")}},
	"sneakers": {name = "รองเท้าผ้าใบ", type = "wear", slot = "feet", armor = 0.0, hp = 25, speed = 1.05,
			draw = {shape = "shoes", col = Color("d8d8d0")}},
	"schoolbag": {name = "กระเป๋านักเรียน", type = "wear", slot = "back", bag = 1, hp = 30,
			draw = {shape = "pack", col = Color("2a3a6a"), big = false}},
	"backpack": {name = "เป้เดินป่า", type = "wear", slot = "back", bag = 2, hp = 40, speed = 0.97,
			draw = {shape = "pack", col = Color("4a5a3a"), big = true}},
	# Valuables, for trading later
	"gold": {name = "สร้อยทอง", type = "junk"},
}

## What each kind of place can hold: [item, weight].
const LOOT := {
	"store": [["water", 4], ["mama", 3], ["snack", 4], ["energy", 2], ["painkiller", 1]],
	"med": [["bandage", 4], ["painkiller", 3], ["firstaid", 1], ["antibiotic", 2], ["water", 1]],
	"food": [["knife", 2], ["mama", 2], ["snack", 2], ["water", 2], ["energy", 1]],
	"tools": [["helmet", 2], ["boots", 2], ["rider", 1], ["backpack", 1], ["pipe", 3], ["hammer", 3], ["plank", 3], ["axe", 1], ["machete", 1], ["wood", 5], ["wire", 2], ["spikes", 2]],
	"valuables": [["vest", 1], ["jacket", 1], ["gold", 3], ["bat", 1], ["knife", 1]],
	"clothes": [["hoodie", 3], ["jacket", 2], ["jeans", 3], ["shorts", 3], ["cap", 3], ["sneakers", 2], ["schoolbag", 2]],
	"home": [["hoodie", 1], ["jeans", 1], ["shorts", 1], ["cap", 1], ["schoolbag", 1], ["plank", 2], ["bat", 1], ["knife", 2], ["water", 3], ["mama", 3], ["snack", 2], ["bandage", 2], ["wood", 3], ["spikes", 1]],
}

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
		out.body = "rider"
	elif roll < 0.1:
		out.head = "helmet"
	elif roll < 0.16:
		out.head = "cap"
	roll = rng.randf()
	if not out.has("body"):
		if roll < 0.02:
			out.body = "vest"
		elif roll < 0.1:
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
	var s := r.size.x / 40.0
	match id:
		"bandage":
			ci.draw_circle(c, 11 * s, Color("e8e2d4"))
			ci.draw_circle(c, 4 * s, Color("b8b0a0"))
		"painkiller":
			ci.draw_rect(Rect2(c - Vector2(12, 7) * s, Vector2(24, 14) * s), Color("e8e8f0"))
			for i in 4:
				ci.draw_circle(c + Vector2(-8 + i * 5.3, 0) * s, 2 * s, Color("d84a4a"))
		"firstaid":
			ci.draw_rect(Rect2(c - Vector2(13, 10) * s, Vector2(26, 20) * s), Color("e8e4dc"))
			ci.draw_rect(Rect2(c - Vector2(2.5, 7) * s, Vector2(5, 14) * s), Color("c83030"))
			ci.draw_rect(Rect2(c - Vector2(7, 2.5) * s, Vector2(14, 5) * s), Color("c83030"))
		"water":
			ci.draw_rect(Rect2(c - Vector2(5, 11) * s, Vector2(10, 22) * s), Color("a8d0e8"))
			ci.draw_rect(Rect2(c - Vector2(3, 14) * s, Vector2(6, 4) * s), Color("3a6ac8"))
			ci.draw_rect(Rect2(c - Vector2(5, 3) * s, Vector2(10, 6) * s), Color("3a8ad0"))
		"mama":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-11, -8) * s, c + Vector2(11, -8) * s,
					c + Vector2(8, 11) * s, c + Vector2(-8, 11) * s]), Color("e8c040"))
			ci.draw_rect(Rect2(c + Vector2(-11, -10) * s, Vector2(22, 3) * s), Color("c83a2e"))
		"snack":
			ci.draw_rect(Rect2(c - Vector2(9, 12) * s, Vector2(18, 24) * s), Color("3a9a4a"))
			ci.draw_circle(c, 5 * s, Color("e8d040"))
		"energy":
			ci.draw_rect(Rect2(c - Vector2(5, 10) * s, Vector2(10, 20) * s), Color("8a4a1a"))
			ci.draw_rect(Rect2(c - Vector2(5, 3) * s, Vector2(10, 6) * s), Color("e8c040"))
		"antibiotic":
			ci.draw_rect(Rect2(c - Vector2(7, 8) * s, Vector2(14, 20) * s), Color("e0802a"))
			ci.draw_rect(Rect2(c - Vector2(8, 13) * s, Vector2(16, 6) * s), Color("f0ece4"))
			ci.draw_rect(Rect2(c - Vector2(5, 2) * s, Vector2(10, 7) * s), Color("f0ece4"))
			ci.draw_rect(Rect2(c - Vector2(1, 1) * s, Vector2(2, 5) * s), Color("3a8a4a"))
		"wire":
			for i in 3:
				ci.draw_arc(c + Vector2(-7 + i * 7, 0) * s, 6 * s, 0, TAU, 12, Color("8a8e90"), 1.5 * s)
		"spikes":
			ci.draw_rect(Rect2(c - Vector2(12, 4) * s, Vector2(24, 9) * s), Color("7a5634"))
			for i in 5:
				ci.draw_line(c + Vector2(-9 + i * 4.5, -4) * s, c + Vector2(-9 + i * 4.5, -11) * s, Color("c8ccd0"), 1.5 * s)
		"wood":
			for i in 3:
				var y := (-8 + i * 7) * s
				ci.draw_rect(Rect2(c + Vector2(-13 * s, y), Vector2(26, 5) * s), Color("a8885a").darkened(i * 0.08))
				ci.draw_rect(Rect2(c + Vector2(-13 * s, y), Vector2(26, 1.2) * s), Color("c8a878"))
		"gold":
			ci.draw_arc(c, 9 * s, 0, TAU, 20, Color("e0b840"), 3 * s)
			ci.draw_circle(c + Vector2(0, 9) * s, 3 * s, Color("f0d060"))
		_:
			ci.draw_circle(c, 8 * s, Color("888888"))


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
