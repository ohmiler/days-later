class_name Items
## Every item in the game, the loot tables that fill shops and homes, and
## how items are drawn as icons. Add an entry to DEFS to add an item.
##
## Weapon fields: range, dmg, cd (cooldown), stun, knock, dur (swing time),
## hp (durability), cleave (hits everything in front), draw (see Look._draw_weapon).

const INV_SIZE := 8
const STACK := 5

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
	# Valuables, for trading later
	"gold": {name = "สร้อยทอง", type = "junk"},
}

## What each kind of place can hold: [item, weight].
const LOOT := {
	"store": [["water", 4], ["mama", 3], ["snack", 4], ["energy", 2], ["painkiller", 1]],
	"med": [["bandage", 4], ["painkiller", 3], ["firstaid", 1], ["antibiotic", 2], ["water", 1]],
	"food": [["knife", 2], ["mama", 2], ["snack", 2], ["water", 2], ["energy", 1]],
	"tools": [["pipe", 3], ["hammer", 3], ["plank", 3], ["axe", 1], ["machete", 1]],
	"valuables": [["gold", 3], ["bat", 1], ["knife", 1]],
	"home": [["plank", 2], ["bat", 1], ["knife", 2], ["water", 3], ["mama", 3], ["snack", 2], ["bandage", 2]],
}

## Furniture that goes in each kind of place.
const FURNITURE := {
	"store": ["shelf", "fridge", "shelf", "counter"],
	"med": ["shelf", "counter", "cabinet"],
	"food": ["fridge", "counter", "table"],
	"tools": ["crate", "shelf", "cabinet"],
	"valuables": ["counter", "cabinet", "crate"],
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
		"gold":
			ci.draw_arc(c, 9 * s, 0, TAU, 20, Color("e0b840"), 3 * s)
			ci.draw_circle(c + Vector2(0, 9) * s, 3 * s, Color("f0d060"))
		_:
			ci.draw_circle(c, 8 * s, Color("888888"))
