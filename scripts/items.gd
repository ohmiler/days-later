class_name Items
## Every item in the game, how searching turns them up, how much they weigh
## and how they are drawn as icons. The items themselves are in
## data/items.cfg, one section each (its top says what every field means):
## to add an item, add a section there. This file is the rules around them.

const DATA := "res://data/items.cfg"  # (exports must include *.cfg: Export > Resources > filters)
const INV_SIZE := 8  # the hotbar; a bag adds slots after these, reached from the bag screen (Tab)

## Places on the body something can be worn, and what they're called.
## "over" is a second layer on the body: a vest goes on top of a shirt. The
## rest are for things worn with anything: masks and glasses, gloves, knee
## pads, a bag across the shoulder. (How each is drawn: see Clothes.)
const SLOTS := ["head", "face", "neck", "body", "over", "arms", "hands", "legs", "knees", "feet", "back", "strap", "waist"]
const SLOT_NAMES := {head = "หัว", face = "หน้า", neck = "คอ", body = "ตัว", over = "ทับเสื้อ", arms = "แขน", hands = "มือ",
		legs = "ขา", knees = "เข่า/แข้ง", feet = "เท้า", back = "หลัง", strap = "สะพาย", waist = "เอว"}

## What you hold, in each hand (kept with what you wear, under these names).
## A weapon swung two-handed (a chop or a sweep) takes both: it sits in the
## right hand and the left stays empty.
const HANDS := ["hand_r", "hand_l"]
const HAND_NAMES := {hand_r = "มือขวา", hand_l = "มือซ้าย"}
const OFF_HAND := 0.7  # the left hand hits this hard (most people are right-handed)
const DUAL_SPEED := 0.6  # a weapon in each hand: each swing comes this much sooner


static func two_handed(id: String) -> bool:
	return def(id).get("draw", {}).get("grip", "") in ["chop", "sweep", "rifle"]


static func is_gun(id: String) -> bool:
	return def(id).get("type", "") == "gun"


## Where a bite can land. Zombies bite what's nearest their mouth: a forearm
## thrown up to fend one off (most of all), the hands, the neck and shoulders
## when one gets you from behind, the calves when it's on the ground. What you
## wear guards each part on its own (an item's `guard`), so a leather jacket
## saves your arms but not your neck.
const PARTS := ["head", "face", "neck", "torso", "arms", "hands", "legs"]
const PART_NAMES := {head = "หัว", face = "หน้า", neck = "คอ", torso = "ลำตัว", arms = "แขน", hands = "มือ", legs = "ขา"}
## How likely a bite is to land on each part, by where the zombie is.
const BITE_FRONT := {arms = 40, hands = 20, torso = 20, neck = 12, face = 8}
const BITE_BEHIND := {neck = 40, torso = 35, arms = 15, head = 10}
const BITE_GROUND := {legs = 100}
const MAX_GUARD := 0.95

## Kilograms a survivor carries before slowing down (a bag adds its `carry`).
## Past it they slow, down to OVERLOAD_SPEED at OVERLOAD times the limit.
const CARRY := 15.0
const OVERLOAD := 1.5
const OVERLOAD_SPEED := 0.6

const TYPES := ["weapon", "gun", "ammo", "use", "trap", "material", "wear", "junk"]
const PLACES := ["store", "med", "food", "tools", "valuables", "clothes", "home", "barber", "phone",
		"hospital", "office", "market", "mall"]
## The big buildings' own places find what their everyday kind does, and more
## of their own: a hospital's cupboards what a pharmacy's do, and scrubs.
const PLACE_ALSO := {hospital = "med", office = "home", market = "food", mall = "clothes"}
## How often searching turns each up, relative to each other.
const RARITY := {common = 4, uncommon = 2, rare = 1}
const RARITY_NAMES := {common = "ธรรมดา", uncommon = "ไม่บ่อย", rare = "หายาก"}
const RARITY_COLORS := {common = Color("c8c4b8"), uncommon = Color("6ab0e0"), rare = Color("e0b840")}
## Icon shapes an item's `icon` can use (drawn in draw_icon).
const ICONS := ["roll", "blister", "kit", "pillbox", "bottle", "cup", "packet", "can", "coil", "board", "planks", "chain", "rag", "nails", "tape", "scrap", "magazine", "jerrycan", "bullets", "shells", "spray", "battery", "phone", "lighter", "matches", "pot"]

## id -> fields, read from DATA the first time Items is used.
static var DEFS: Dictionary = _load_defs()
## place -> [[item, weight]], built from each item's places and rarity.
static var LOOT: Dictionary = _build_loot()
## Every id in data/items.cfg order: a snapshot names an item by its place here
## (both ends read the same file: the PROTOCOL check makes sure).
static var ID_LIST: Array = DEFS.keys()
static var _index := {}


## 1 + an item's place in ID_LIST (0: no item).
static func index_of(id: String) -> int:
	if _index.is_empty():
		for i in ID_LIST.size():
			_index[ID_LIST[i]] = i + 1
	return _index.get(id, 0)


static func id_at(i: int) -> String:
	return ID_LIST[i - 1] if i > 0 and i <= ID_LIST.size() else ""


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
	for place in PLACE_ALSO:
		for e in out[PLACE_ALSO[place]]:
			if not out[place].any(func(x): return x[0] == e[0]):
				out[place].append(e)
	return out


## Where a cupboard is, for what's in it: its own kind of place, or, in a big
## building (a hospital's pharmacy, an office's desks, a market's stalls), that
## building's.
static func place_in(table: String, building_kind: String) -> String:
	match building_kind:
		"hospital":
			return "hospital" if table in ["med", "home"] else table
		"office":
			return "office" if table == "home" else table
		"market":
			return "market"
		"mall":
			return "mall" if table == "clothes" else table
	return table


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
		if d.has("leaves") and not DEFS.has(d.leaves):
			out.append("%s: leaves unknown item %s" % [id, d.leaves])
		if d.has("cooks") and not DEFS.has(d.cooks.get("into", "")):
			out.append("%s: cooks into unknown item %s" % [id, d.cooks.get("into")])
		if d.get("holds", 0) > 0 and d.get("stack", 1) > 1:
			out.append("%s: something that holds water can't stack (each has its own)" % id)
		match d.get("type"):
			"weapon":
				for key in ["range", "dmg", "cd", "dur", "hp", "draw"]:
					if not d.has(key):
						out.append("%s: a weapon needs %s" % [id, key])
			"gun":
				for key in ["dmg", "pellets", "spread", "range", "cd", "mag", "ammo", "reload", "noise", "hp", "bash", "draw"]:
					if not d.has(key):
						out.append("%s: a gun needs %s" % [id, key])
				if not DEFS.has(d.get("ammo", "")):
					out.append("%s: takes unknown ammo %s" % [id, d.get("ammo")])
			"wear":
				if d.get("slot") not in SLOTS:
					out.append("%s: unknown slot %s" % [id, d.get("slot")])
				for part in d.get("guard", {}):
					if part not in PARTS:
						out.append("%s: guards unknown body part %s" % [id, part])
				if not d.has("draw") or not d.has("hp"):
					out.append("%s: clothes need draw and hp" % id)
				else:
					for part in Clothes.parts(d.draw):
						var sh: String = part.get("shape", "")
						if sh not in Clothes.BASE_SHAPES and not Clothes.TEMPLATES.has(sh):
							out.append("%s: no way to draw shape '%s' (see Clothes)" % [id, sh])
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
	"barber": ["mirror", "cabinet", "shelf"],
	"phone": ["glass", "shelf", "counter"],
	"hospital": ["shelf", "counter", "cabinet"],
	"office": ["cabinet", "table", "counter"],
	"market": ["counter", "table", "crate"],
	"mall": ["shelf", "cabinet", "counter"],
}


static func def(id: String) -> Dictionary:
	var d = DEFS.get(id)
	if d != null:
		return d
	return DEFS.get(id.get_slice("#", 0), {}) if "#" in id else {}


# --- One item, many looks ------------------------------------------------------------
# Clothes with `looks` in data/items.cfg come in many colours, patterns and
# prints: each one found gets its own number (`v` in the item), which picks
# them. What's worn goes by its key, "id#v" (Player.wear_ids, a zombie's
# wear): everything that reads an item (def, weight, guard...) takes a key
# as it takes an id.

## Funny things printed on T-shirts (a `print` pattern picks one by its number).
const PRINTS := ["อย่ากัดเค้า", "ยังไม่ตาย", "ไม่รับแขก", "ลดน้ำหนักด้วยการวิ่งหนี", "รอดมาได้ไง", "วันจันทร์อีกแล้ว",
		"ขอกอดหน่อย", "สายมูไม่กลัวผี", "ข้าวมันไก่ที่ดีที่สุด", "ฉันรอดเพราะแม่สั่ง", "กินก่อนค่อยวิ่ง", "โสดแต่ไม่ตาย",
		"BANGKOK", "SAME SAME", "I ♥ BKK", "NO ZOMBIE"]
const PATTERN_NAMES := {stripe = "ลายทาง", plaid = "ลายสก็อต", floral = "ลายดอก", camo = "ลายพราง", print = "สกรีน",
		dots = "ลายจุด"}


## The key an item is worn by: its id, and its look's number if it has one.
static func key(it: Dictionary) -> String:
	return "%s#%d" % [it.id, it.v] if it.has("v") else String(it.id)


static func base_id(k: String) -> String:
	return k.get_slice("#", 0)


## A new one of `id`, as found: full health, and a look of its own if it has looks.
static func make(id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var it := {id = id, n = 1, hp = def(id).get("hp", 0)}
	if def(id).has("looks"):
		it.v = (rng.randi() if rng else randi()) % 100000
	return it


## An item from a worn key (taken off a body): its look kept.
static func from_key(k: String, hp: int) -> Dictionary:
	var it := {id = base_id(k), n = 1, hp = hp}
	if "#" in k:
		it.v = int(k.get_slice("#", 1))
	return it


static var _draws := {}


## How the item with key `k` is drawn: its `draw`, with its look's colour,
## second colour, pattern and print if it has them.
static func draw_of(k: String) -> Dictionary:
	if _draws.has(k):
		return _draws[k]
	var d := def(k)
	var out: Dictionary = d.get("draw", {}).duplicate(true)
	var looks: Dictionary = d.get("looks", {})
	if "#" in k and not looks.is_empty():
		var v := int(k.get_slice("#", 1))
		var cols: Array = looks.get("cols", [])
		var pats: Array = looks.get("pats", [])
		var col2s: Array = looks.get("col2", [])
		if not cols.is_empty():
			out.col = Color(cols[v % cols.size()])
		v /= maxi(1, cols.size())
		if not pats.is_empty():
			var pat: String = pats[v % pats.size()]
			if pat != "plain":
				out.pattern = pat
			v /= pats.size()
		if not col2s.is_empty():
			out.col2 = Color(col2s[v % col2s.size()])
			v /= col2s.size()
		if out.get("pattern", "") == "print":
			out.print = PRINTS[v % PRINTS.size()]
	_draws[k] = out
	return out


## A word or two on this one's look, for its card: "ลายทาง", "สกรีน 'อย่ากัดเค้า'".
static func look_text(it: Dictionary) -> String:
	if not it.has("v"):
		return ""
	var d := draw_of(key(it))
	var pat: String = d.get("pattern", "")
	if pat == "print":
		return "สกรีน \"%s\"" % d.get("print", "")
	return PATTERN_NAMES.get(pat, "")


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


## Share of a bite stopped at `part` by a set of worn item ids. Layers add up
## the way they would: each stops its share of what gets past the one above.
static func guard_at(ids: Array, part: String) -> float:
	var through := 1.0
	for id in ids:
		through *= 1.0 - float(def(id).get("guard", {}).get(part, 0.0))
	return minf(1.0 - through, MAX_GUARD)


## One line on what a piece of clothing does.
static func wear_text(id: String) -> String:
	var d := def(id)
	var parts := ["สวมที่" + SLOT_NAMES[d.slot]]
	var g: Dictionary = d.get("guard", {})
	if not g.is_empty():
		parts.append("กันกัด " + " ".join(g.keys().map(func(k): return "%s %d%%" % [PART_NAMES[k], roundi(g[k] * 100)])))
	if d.get("hot", 0.0) >= 0.15:
		parts.append("ร้อน")
	if d.get("muffle", false):
		parts.append("ได้ยินไม่ชัด")
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
## Where a zombie was when it turned, as far as its clothes go: a zombie's
## id carries it (zid % 8, see Main.new_zid), so every machine dresses it the
## same with nothing more sent.
const ZOMBIE_PLACES := ["street", "hospital", "office", "market", "mall", "home", "street", "street"]
## What people wore there: [slot, [[item, weight], ...], chance of wearing anything there].
const DRESS := {
	street = [["head", [["cap", 3], ["bucket", 2], ["helmet", 3]], 0.25],
			["body", [["tshirt", 6], ["polo", 2], ["shirt_short", 2], ["hoodie", 1], ["jersey", 2], ["school_shirt", 1], ["jacket", 1]], 0.85],
			["over", [["rider", 3], ["hivis", 1], ["apron", 1]], 0.1],
			["legs", [["jeans", 5], ["shorts", 4], ["slacks", 2], ["cargo", 1], ["school_shorts", 1]], 0.8],
			["feet", [["sneakers", 4], ["flipflops", 4], ["boots", 1], ["schoolshoes", 1]], 0.6],
			["back", [["schoolbag", 2], ["backpack", 1], ["deliverybag", 1]], 0.1],
			["face", [["mask", 3]], 0.1], ["waist", [["bumbag", 1]], 0.05]],
	hospital = [["body", [["scrubs", 6], ["office_shirt", 1], ["tshirt", 2]], 0.95],
			["over", [["labcoat", 1]], 0.2],
			["legs", [["slacks", 3], ["jeans", 1]], 0.6],
			["face", [["n95", 2], ["mask", 3]], 0.5],
			["neck", [["neckbrace", 1]], 0.06],
			["feet", [["sneakers", 2], ["schoolshoes", 1], ["flipflops", 1]], 0.6]],
	office = [["body", [["office_shirt", 6], ["shirt_long", 2], ["polo", 1], ["guard_shirt", 1]], 0.95],
			["legs", [["slacks", 6], ["jeans", 1]], 0.9],
			["feet", [["schoolshoes", 4], ["sneakers", 1]], 0.8],
			["neck", [["whistle", 1]], 0.05],
			["strap", [["satchel", 1]], 0.15]],
	market = [["body", [["tanktop", 3], ["tshirt", 4], ["mohom", 1], ["hawaii", 1]], 0.9],
			["over", [["apron", 1]], 0.4],
			["legs", [["fisherman", 3], ["shorts", 3], ["elephant", 1]], 0.85],
			["feet", [["flipflops", 5], ["rubberboots", 2]], 0.7],
			["head", [["bucket", 2], ["cap", 1]], 0.3],
			["waist", [["pakhaoma", 3], ["bumbag", 1]], 0.3],
			["hands", [["rubbergloves", 1]], 0.1]],
	mall = [["body", [["tshirt", 5], ["hawaii", 1], ["jersey", 2], ["polo", 2], ["denim_jacket", 1], ["mart_shirt", 1]], 0.95],
			["legs", [["jeans", 4], ["cargo", 2], ["shorts", 2], ["elephant", 1]], 0.9],
			["feet", [["sneakers", 5], ["flipflops", 2]], 0.8],
			["head", [["cap", 2], ["bucket", 2], ["beanie", 1]], 0.3],
			["face", [["sunglasses", 2], ["mask", 1]], 0.2],
			["waist", [["bumbag", 1]], 0.15], ["back", [["schoolbag", 2], ["deliverybag", 1]], 0.12]],
	home = [["body", [["tanktop", 4], ["tshirt", 5], ["school_shirt", 1]], 0.85],
			["legs", [["shorts", 4], ["fisherman", 2], ["jeans", 1]], 0.8],
			["feet", [["flipflops", 5]], 0.5],
			["waist", [["pakhaoma", 2]], 0.2]],
}


static func zombie_wear(zid: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = zid * 7919 + 17
	var out := {}
	var place: String = ZOMBIE_PLACES[zid % ZOMBIE_PLACES.size()]
	for e in DRESS[place]:
		if rng.randf() >= e[2]:
			continue
		var weights := {}
		for c in e[1]:
			weights[c[0]] = c[1]
		var id: String = _pick(weights, rng)
		out[e[0]] = "%s#%d" % [id, rng.randi() % 100000] if def(id).has("looks") else id
	if out.has("over") and def(out.over).get("draw", {}).get("covers", false):
		out.erase("body")
	return out


## Which of ZOMBIE_PLACES `pos` is in: the big buildings' blocks by what they
## are, a big building's own inside, else the street.
static func zombie_place(w: World, pos: Vector2) -> int:
	var c := w.to_cell(pos)
	var b = w.building_at.get(c)
	var use := ""
	if b != null and b.data.get("big", false):
		use = {hospital = "hospital", flats = "home", office = "office", mall = "mall", market = "market"}.get(b.data.kind, "")
	if use == "":
		for blk in w.blocks:
			if blk.rect.has_point(c):
				use = {hospital = "hospital", military_hospital = "hospital", office = "office", mall = "mall", market = "market"}.get(blk.use, "")
				break
	return maxi(0, ZOMBIE_PLACES.find(use)) if use != "" else 0


## The look dictionary's `wear` entry for a set of worn item ids.
static func wear_draw(ids: Dictionary) -> Dictionary:
	var out := {}
	for slot in ids:
		if def(ids[slot]).has("draw"):
			out[slot] = draw_of(ids[slot])
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
	return def(id).get("type", "") in ["weapon", "gun"]


static func display_name(id: String) -> String:
	return def(id).get("name", id)


# --- What's inside, and how fresh (one way for every item) -----------------------------
# An item that `holds` sips of something carries it as `fill`: {what, n} (a
# bottle of canal water, a pot of boiled water). One that `spoil`s (game hours)
# remembers when it was made as `made` (Main.now()): nothing counts down, how
# fresh it is is worked out from the clock when it's looked at or eaten.
# Either makes an item its own: it never piles up with a plain one.

## Kinds of water: what a sip does (drink), and the chance a sip makes you ill.
const LIQUIDS := {
	clean = {name = "น้ำสะอาด", drink = 15.0, sick = 0.0},
	tap = {name = "น้ำประปา", drink = 15.0, sick = 0.06},  # (straight from the pipes: Bangkok boils it)
	canal = {name = "น้ำคลอง", drink = 15.0, sick = 0.45},
}


## How many sips it holds (0: it holds nothing).
static func holds(id: String) -> int:
	return int(def(id).get("holds", 0))


## What's in it: {what, n}, or {} if empty (or not a container).
static func fill_of(it: Dictionary) -> Dictionary:
	var f: Dictionary = it.get("fill", {})
	return f if f.get("n", 0) > 0 else {}


## Spoiled, at game time `now`?
static func spoiled(it: Dictionary, now: float) -> bool:
	var h: float = def(it.id).get("spoil", 0.0)
	return h > 0.0 and age(it, now) > h * Main.HOUR


## Game hours until it spoils (-1: it doesn't).
static func hours_left(it: Dictionary, now: float) -> float:
	var h: float = def(it.id).get("spoil", 0.0)
	if h <= 0.0:
		return -1.0
	return maxf(0.0, h - age(it, now) / Main.HOUR)


# --- Fridges ------------------------------------------------------------------
# Food in a fridge keeps while the building has power (Buildings.power). Put
# in, it remembers when and in which building (`cold_in`, `cold_b`); taken out,
# the time it spent cold with the power on is added up (`cold`) and counts only
# FRIDGE_KEEP as much toward spoiling. Nothing ticks while it sits there.

const FRIDGE_KEEP := 0.15  # how fast food goes off in a running fridge (1: as fast as out of it)
## (building, from, to) -> seconds of game time it had power (Main sets it: Buildings.power_between).
static var chill: Callable


## How old it is, as far as going off goes (game seconds).
static func age(it: Dictionary, now: float) -> float:
	var a := now - float(it.get("made", now)) - float(it.get("cold", 0.0))
	if it.has("cold_in") and chill.is_valid():
		a -= float(chill.call(int(it.cold_b), float(it.cold_in), now)) * (1.0 - FRIDGE_KEEP)
	return a


## Into a fridge in building `b` (only food that goes off minds).
static func chill_in(it: Dictionary, b: int, now: float) -> void:
	chill_out(it, now)
	if def(it.id).get("spoil", 0.0) > 0.0 and it.has("made") and b >= 0:
		it.cold_in = now
		it.cold_b = b


## Out of the fridge: the cold time it had is kept.
static func chill_out(it: Dictionary, now: float) -> void:
	if not it.has("cold_in"):
		return
	if chill.is_valid():
		it.cold = float(it.get("cold", 0.0)) + float(chill.call(int(it.cold_b), float(it.cold_in), now)) * (1.0 - FRIDGE_KEEP)
	it.erase("cold_in")
	it.erase("cold_b")


## Plain: nothing inside, no date on it (only plain items pile up together).
static func plain(it: Dictionary) -> bool:
	return not it.has("fill") and not it.has("made") and not it.has("v")


## How it is, for its card and its name in the bag: "น้ำคลอง 2/3", "บูดแล้ว"...
static func state_text(it: Dictionary, now: float) -> String:
	var parts := []
	var look := look_text(it)
	if look != "":
		parts.append(look)
	if holds(it.id) > 0:
		var f := fill_of(it)
		parts.append("ว่าง" if f.is_empty() else "%s %d/%d" % [LIQUIDS.get(f.what, {}).get("name", f.what), f.n, holds(it.id)])
	if def(it.id).get("spoil", 0.0) > 0.0 and it.has("made"):
		if spoiled(it, now):
			parts.append("บูดแล้ว")
		else:
			var h := hours_left(it, now)
			parts.append("สด · เสียในราว %d ชม." % ceili(h) if h >= 1.0 else "ใกล้เสียแล้ว")
	return " · ".join(parts)


## What searching turns up. Two steps, so that adding items never makes the
## essentials rarer: first a *category* (what that piece of furniture holds,
## tipped by the kind of place), then an item of that category that is found
## in that kind of place, the rarer ones less often.
const CATEGORIES := ["food", "drink", "medicine", "material", "clothes", "weapon", "junk"]
## What each piece of furniture holds: category -> weight.
const FURN_LOOT := {
	fridge = {drink = 5, food = 4},
	table = {food = 4, drink = 4, junk = 1, weapon = 1},  # a kitchen table
	shelf = {food = 3, drink = 2, medicine = 1, material = 1, junk = 1},
	counter = {junk = 2, food = 1, drink = 1, medicine = 1, material = 1, weapon = 1},
	cabinet = {medicine = 3, clothes = 2, material = 1, junk = 1},
	crate = {material = 5, weapon = 2, clothes = 1},
	bed = {clothes = 3, junk = 2, medicine = 1},
	glass = {junk = 4, medicine = 2, drink = 0.5},  # a display case: what the shop shows off
	mirror = {weapon = 3, junk = 3, clothes = 1},  # a barber's station: scissors, razors, sprays
	toolchest = {material = 4, weapon = 3},
	stall = {food = 5, drink = 3},  # the food cart at the front of an eatery
	safe = {junk = 5, weapon = 1},
	pantry = {food = 5, drink = 2},  # the kitchen's screened food cupboard
	sink = {junk = 2, material = 1, medicine = 1, drink = 1},
}
## The kind of place tips it: a pharmacy's shelves hold medicine.
const PLACE_BIAS := {
	barber = {weapon = 2.0, junk = 2.0, clothes = 1.5},
	phone = {junk = 5.0},
	med = {medicine = 5.0},
	food = {food = 3.0, drink = 2.0},
	store = {food = 2.0, drink = 2.0},
	tools = {material = 3.0, weapon = 2.0},
	clothes = {clothes = 5.0},
	valuables = {junk = 3.0, weapon = 1.5},
	hospital = {medicine = 5.0, clothes = 1.5},
	office = {junk = 2.0, clothes = 1.5, drink = 1.5},
	market = {food = 3.0, clothes = 2.0, drink = 1.5},
	mall = {clothes = 6.0},
}
## Share of each piece of furniture already picked clean. Fridges most of all:
## everyone raided those first.
const EMPTY := {fridge = 0.3, stall = 0.35, safe = 0.05}
const EMPTY_DEFAULT := 0.15


## An item's category, from its type and tags.
static func category(id: String) -> String:
	var d := def(id)
	match d.get("type"):
		"use":
			if has_tag(id, "medicine"):
				return "medicine"
			return "drink" if has_tag(id, "drink") else "food"
		"material", "trap":
			return "material"
		"wear":
			return "clothes"
		"weapon", "gun", "ammo":
			return "weapon"
	return "junk"


## 0-3 random items from a piece of furniture (`kind`) in a kind of place (`table`).
static func roll(table: String, kind: String, rng: RandomNumberGenerator) -> Array:
	var out := []
	if rng.randf() < EMPTY.get(kind, EMPTY_DEFAULT):
		return out
	var cats: Dictionary = FURN_LOOT.get(kind, FURN_LOOT.shelf)
	var bias: Dictionary = PLACE_BIAS.get(table, {})
	var weighted := {}
	for c in cats:
		if _in_category(table, c).is_empty():
			continue
		# What the place doesn't sell is only there by chance (a pharmacy's snack).
		var sold: bool = table == "home" or LOOT.get(table, []).any(func(e): return category(e[0]) == c)
		weighted[c] = cats[c] * bias.get(c, 1.0) * (1.0 if sold else 0.2)
	if weighted.is_empty():
		return out
	for i in rng.randi_range(1, 3):
		var entries := _in_category(table, _pick(weighted, rng))
		var by_rarity := {}
		for e in entries:
			by_rarity[e[0]] = e[1]
		out.append(_pick(by_rarity, rng))
	return out


## [[item, rarity weight]] of a category found in a kind of place (falling back
## to what homes have, so any furniture anywhere can hold its basics).
static func _in_category(table: String, cat: String) -> Array:
	var out := []
	for e in LOOT.get(table, []):
		if category(e[0]) == cat:
			out.append(e)
	if out.is_empty() and table != "home":
		return _in_category("home", cat)
	return out


static func _pick(weights: Dictionary, rng: RandomNumberGenerator):
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[-1]


# --- Icons ------------------------------------------------------------------

static func draw_icon(ci: CanvasItem, r: Rect2, id: String) -> void:
	var d := def(id)
	var c := r.get_center()
	if d.get("type") in ["weapon", "gun"]:
		var w: Dictionary = d.draw
		var dirv := Vector2(1, -1).normalized()
		var scale: float = r.size.x / (w.len + 6.0) * 0.95
		ci.draw_set_transform(c - dirv * (w.len * 0.5 - 1.0) * scale, 0, Vector2(scale, scale))
		Look._draw_weapon(ci, Vector2.ZERO, dirv, w)
		ci.draw_set_transform(Vector2.ZERO)
		return
	if d.get("type") == "wear":
		_wear_icon(ci, r, draw_of(id), d.get("slot", ""))  # (`id` may be a key: this one's own look)
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
		"pot":  # a cooking pot seen from the side: body, rim, two handles, a lid knob
			ci.draw_rect(Rect2(c + Vector2(-10, -4) * s, Vector2(20, 12) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-11, -6) * s, Vector2(22, 3) * s), col.lightened(0.15))
			ci.draw_rect(Rect2(c + Vector2(-14, -3) * s, Vector2(4, 2) * s), col2)
			ci.draw_rect(Rect2(c + Vector2(10, -3) * s, Vector2(4, 2) * s), col2)
			ci.draw_rect(Rect2(c + Vector2(-2, -9) * s, Vector2(4, 3) * s), col2)
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
		"jerrycan":
			ci.draw_rect(Rect2(c - Vector2(9, 9) * s, Vector2(18, 21) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-9, -13) * s, Vector2(8, 4) * s), col.darkened(0.25))  # handle
			ci.draw_rect(Rect2(c + Vector2(3, -13) * s, Vector2(4, 4) * s), col2)  # spout
			ci.draw_line(c + Vector2(-7, -5) * s, c + Vector2(7, 9) * s, col.darkened(0.2), 1.5 * s)
			ci.draw_line(c + Vector2(7, -5) * s, c + Vector2(-7, 9) * s, col.darkened(0.2), 1.5 * s)
		"bullets":
			for i in 3:
				var x := (-7 + i * 7) * s
				ci.draw_rect(Rect2(c + Vector2(x - 2, -2 * s), Vector2(4, 10) * s), col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(x - 2, -2 * s), c + Vector2(x + 2, -2 * s), c + Vector2(x, -7 * s)]), col2)
		"shells":
			for i in 3:
				var x := (-7 + i * 7) * s
				ci.draw_rect(Rect2(c + Vector2(x - 2.5, -7 * s), Vector2(5, 10) * s), col)
				ci.draw_rect(Rect2(c + Vector2(x - 2.5, 3 * s), Vector2(5, 4) * s), col2)
		"lighter":  # a cheap plastic lighter
			ci.draw_rect(Rect2(c - Vector2(4, 8) * s, Vector2(8, 18) * s), col)
			ci.draw_rect(Rect2(c - Vector2(4, 12) * s, Vector2(8, 4) * s), col2)
			ci.draw_rect(Rect2(c + Vector2(-2, -14) * s, Vector2(3, 2) * s), Color("3a3a3a"))
		"matches":  # a matchbox, a match sticking out
			ci.draw_rect(Rect2(c - Vector2(9, 6) * s, Vector2(18, 12) * s), col)
			ci.draw_rect(Rect2(c - Vector2(9, 2) * s, Vector2(18, 4) * s), Color("f0ece4"))
			ci.draw_line(c + Vector2(4, -6) * s, c + Vector2(11, -13) * s, Color("e8d8b0"), 1.5 * s)
			ci.draw_circle(c + Vector2(11, -13) * s, 1.8 * s, col2)
		"spray":  # an aerosol can with its cap
			ci.draw_rect(Rect2(c - Vector2(5, 8) * s, Vector2(10, 20) * s), col)
			ci.draw_rect(Rect2(c - Vector2(4, 13) * s, Vector2(8, 5) * s), col2)
			ci.draw_rect(Rect2(c + Vector2(-5, -2) * s, Vector2(10, 4) * s), col2.darkened(0.1))
		"battery":  # two AA cells
			for dx in [-5.0, 3.0]:
				ci.draw_rect(Rect2(c + Vector2(dx, -10) * s, Vector2(6, 20) * s), col)
				ci.draw_rect(Rect2(c + Vector2(dx, -10) * s, Vector2(6, 6) * s), col2)
				ci.draw_rect(Rect2(c + Vector2(dx + 2, -12) * s, Vector2(2, 2) * s), Color("b8bcc0"))
		"phone":
			ci.draw_rect(Rect2(c - Vector2(6, 12) * s, Vector2(12, 24) * s), col)
			ci.draw_rect(Rect2(c - Vector2(5, 10) * s, Vector2(10, 17) * s), col2)
			ci.draw_rect(Rect2(c + Vector2(-2, 9) * s, Vector2(4, 1.5) * s), col2.lightened(0.3))
		"magazine":
			ci.draw_rect(Rect2(c - Vector2(9, 12) * s, Vector2(18, 24) * s), col)
			ci.draw_rect(Rect2(c - Vector2(9, 12) * s, Vector2(18, 7) * s), col2)
			ci.draw_rect(Rect2(c + Vector2(-6, 0) * s, Vector2(12, 7) * s), col.darkened(0.25))
		_:
			ci.draw_circle(c, 8 * s, col)


## Clothes drawn flat, like laid out on a table.
static func _wear_icon(ci: CanvasItem, r: Rect2, draw: Dictionary, slot: String) -> void:
	var c := r.get_center()
	var s := r.size.x / 40.0
	var w: Dictionary = draw.duplicate()
	w.shape = w.get("icon_shape", w.get("shape", ""))  # (a garment made of parts names its icon)
	var col: Color = w.col
	var dark := col.darkened(0.3)
	var P := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + p * s)
		return out
	match w.shape:
		"long", "hoodie", "vest", "tee", "tank", "shirt":
			if slot == "legs":
				var legs: PackedVector2Array = P.call([Vector2(-10, -14), Vector2(10, -14), Vector2(11, 16), Vector2(3, 16),
						Vector2(0, -4), Vector2(-3, 16), Vector2(-11, 16)])
				ci.draw_colored_polygon(legs, col)
				ci.draw_rect(Rect2(c + Vector2(-10, -14) * s, Vector2(20, 3) * s), dark)
				if w.has("pattern"):
					var c2: Color = w.get("col2", dark)
					for p in [Vector2(-6, -6), Vector2(5, -2), Vector2(-7, 6), Vector2(7, 9), Vector2(-4, 12)]:
						ci.draw_circle(c + p * s, 1.6 * s, c2)
				return
			var sleeve: float = {vest = 0.0, tank = 0.0, tee = 0.55}.get(w.shape, 1.0)
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
			elif w.shape in ["long", "hoodie"]:
				ci.draw_line(c + Vector2(0, -13) * s, c + Vector2(0, 15) * s, dark, 1.0)  # zip
			_icon_marks(ci, c, s, w)
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
		"sandals":
			for sx in [-1.0, 1.0]:
				var f := c + Vector2(sx * 7, 2) * s
				ci.draw_set_transform(f, 0, Vector2(1, 1.8))
				ci.draw_circle(Vector2.ZERO, 5 * s, col)
				ci.draw_set_transform(Vector2.ZERO)
				ci.draw_line(f + Vector2(0, -6) * s, f + Vector2(-4, 0) * s, Color("f0ece4"), 1.4 * s)
				ci.draw_line(f + Vector2(0, -6) * s, f + Vector2(4, 0) * s, Color("f0ece4"), 1.4 * s)
		"bucket":
			ci.draw_colored_polygon(P.call(_dome(Vector2(0, 2), 9.0)), col)
			ci.draw_colored_polygon(P.call([Vector2(-15, 2), Vector2(15, 2), Vector2(12, 7), Vector2(-12, 7)]), dark)
		"beanie":
			ci.draw_colored_polygon(P.call(_dome(Vector2(0, 5), 12.0)), col)
			ci.draw_rect(Rect2(c + Vector2(-12, 2) * s, Vector2(24, 5) * s), dark)
			ci.draw_circle(c + Vector2(0, -9) * s, 3 * s, w.get("col2", col.lightened(0.2)))
		"hardhat":
			ci.draw_colored_polygon(P.call(_dome(Vector2(0, 4), 12.0)), col)
			ci.draw_rect(Rect2(c + Vector2(-15, 3) * s, Vector2(30, 3) * s), dark)
			ci.draw_rect(Rect2(c + Vector2(-1.5, -8) * s, Vector2(3, 11) * s), col.lightened(0.2))
		"whistle":
			ci.draw_line(c + Vector2(-10, -12) * s, c + Vector2(0, 6) * s, w.get("col2", Color("c83a2e")), 1.5 * s)
			ci.draw_line(c + Vector2(10, -12) * s, c + Vector2(0, 6) * s, w.get("col2", Color("c83a2e")), 1.5 * s)
			ci.draw_rect(Rect2(c + Vector2(-5, 5) * s, Vector2(10, 6) * s), col)
			ci.draw_circle(c + Vector2(4, 8) * s, 3 * s, col.darkened(0.2))
		"apron":
			ci.draw_colored_polygon(P.call([Vector2(-6, -14), Vector2(6, -14), Vector2(11, 0), Vector2(11, 16), Vector2(-11, 16), Vector2(-11, 0)]), col)
			ci.draw_rect(Rect2(c + Vector2(-8, 3) * s, Vector2(16, 5) * s), dark)
			ci.draw_line(c + Vector2(-11, 0) * s, c + Vector2(-16, -2) * s, dark, 1.2)
			ci.draw_line(c + Vector2(11, 0) * s, c + Vector2(16, -2) * s, dark, 1.2)
		"sash":
			ci.draw_rect(Rect2(c + Vector2(-15, -8) * s, Vector2(30, 16) * s), col)
			var c2s: Color = w.get("col2", Color("f0ece4"))
			for i in 4:
				ci.draw_rect(Rect2(c + Vector2(-13 + i * 8, -8) * s, Vector2(3, 16) * s), c2s)
				ci.draw_rect(Rect2(c + Vector2(-15, -6 + i * 4) * s, Vector2(30, 1.5) * s), Color(c2s, 0.6))
		"bumbag":
			ci.draw_line(c + Vector2(-16, -4) * s, c + Vector2(16, -4) * s, dark, 2.0 * s)
			ci.draw_colored_polygon(P.call([Vector2(-10, -6), Vector2(10, -6), Vector2(8, 7), Vector2(-8, 7)]), col)
			ci.draw_line(c + Vector2(-8, -1) * s, c + Vector2(8, -1) * s, col.lightened(0.35), 1.0)
		"toolbelt":
			ci.draw_rect(Rect2(c + Vector2(-16, -8) * s, Vector2(32, 5) * s), dark)
			for x in [-12.0, 3.0]:
				ci.draw_rect(Rect2(c + Vector2(x, -3) * s, Vector2(9, 10) * s), col)
			ci.draw_line(c + Vector2(-2, -3) * s, c + Vector2(0, 12) * s, Color("5a4a3a"), 2.0 * s)
			ci.draw_rect(Rect2(c + Vector2(-5, -6) * s, Vector2(8, 3) * s), Color("8a8e92"))
		"boots", "shoes":
			var tall := 10.0 if w.shape == "boots" else 3.0
			ci.draw_colored_polygon(P.call([Vector2(-8, 8 - tall - 4), Vector2(0, 8 - tall - 4), Vector2(1, 2),
					Vector2(12, 4), Vector2(12, 9), Vector2(-8, 9)]), col)
			ci.draw_rect(Rect2(c + Vector2(-8, 8) * s, Vector2(20, 2) * s), dark if w.shape == "boots" else Color("f0f0e8"))
		"armguards":
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(sx * 7 - 5, -12) * s, Vector2(10, 24) * s), col)
				for i in 3:
					ci.draw_line(c + Vector2(sx * 7 - 5, -8 + i * 8) * s, c + Vector2(sx * 7 + 5, -8 + i * 8) * s, Color("8a9098"), 2.0 * s)
		"fullface":
			ci.draw_circle(c, 13 * s, col)
			ci.draw_rect(Rect2(c + Vector2(-9, -4) * s, Vector2(18, 7) * s), Color("141820"))
			ci.draw_rect(Rect2(c + Vector2(-8, -3) * s, Vector2(6, 2) * s), Color(1, 1, 1, 0.3))
		"scarf":
			ci.draw_rect(Rect2(c + Vector2(-14, -6) * s, Vector2(28, 8) * s), col)
			ci.draw_rect(Rect2(c + Vector2(4, 0) * s, Vector2(7, 16) * s), col.darkened(0.15))
		"shinguards":
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(sx * 7 - 4, -14) * s, Vector2(8, 26) * s), col)
				ci.draw_line(c + Vector2(sx * 7, -12) * s, c + Vector2(sx * 7, 10) * s, col.darkened(0.25), 1.5 * s)
		"mask":
			ci.draw_colored_polygon(P.call([Vector2(-12, -6), Vector2(12, -6), Vector2(10, 7), Vector2(0, 10), Vector2(-10, 7)]), col)
			for i in 3:
				ci.draw_line(c + Vector2(-10, -2 + i * 4) * s, c + Vector2(10, -2 + i * 4) * s, dark, 1.0)
			ci.draw_line(c + Vector2(-12, -5) * s, c + Vector2(-16, -10) * s, dark, 1.2)
			ci.draw_line(c + Vector2(12, -5) * s, c + Vector2(16, -10) * s, dark, 1.2)
		"glasses":
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(-1 + sx * 7 - 5, -4) * s, Vector2(10, 8) * s), col)
			ci.draw_line(c + Vector2(-16, -3) * s, c + Vector2(16, -3) * s, Color("1a1a1a"), 1.5)
		"gloves":
			if w.get("big", false):  # boxing gloves
				for sx in [-1.0, 1.0]:
					ci.draw_circle(c + Vector2(sx * 8, -3) * s, 7.5 * s, col)
					ci.draw_rect(Rect2(c + Vector2(sx * 8 - 5, 3) * s, Vector2(10, 7) * s), Color("f0ece4"))
				return
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(sx * 7 - 5, -8) * s, Vector2(10, 14) * s), col)
				ci.draw_rect(Rect2(c + Vector2(sx * 7 - 5, 4) * s, Vector2(10, 4) * s), dark)
		"kneepads":
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(sx * 7 - 5, -8) * s, Vector2(10, 16) * s), col)
				ci.draw_rect(Rect2(c + Vector2(sx * 7 - 4, -6) * s, Vector2(8, 3) * s), col.lightened(0.25))
		"satchel":
			ci.draw_line(c + Vector2(-12, -14) * s, c + Vector2(8, 2) * s, dark, 2.0)
			ci.draw_rect(Rect2(c + Vector2(-2, -2) * s, Vector2(16, 13) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-2, -2) * s, Vector2(16, 5) * s), dark)
		"raincoat":
			var coat: PackedVector2Array = P.call([Vector2(-7, -14), Vector2(7, -14), Vector2(16, -8), Vector2(16, 4), Vector2(11, 4),
					Vector2(12, 17), Vector2(-12, 17), Vector2(-11, 4), Vector2(-16, 4), Vector2(-16, -8)])
			ci.draw_colored_polygon(coat, col)
			ci.draw_colored_polygon(P.call([Vector2(-6, -14), Vector2(0, -8), Vector2(6, -14), Vector2(0, -18)]), dark)
			ci.draw_line(c + Vector2(0, -12) * s, c + Vector2(0, 17) * s, dark, 1.0)
		"pack":
			if w.get("box", false):
				ci.draw_rect(Rect2(c + Vector2(-12, -12) * s, Vector2(24, 24) * s), col)
				ci.draw_rect(Rect2(c + Vector2(-12, -12) * s, Vector2(24, 4) * s), col.lightened(0.2))
				ci.draw_rect(Rect2(c + Vector2(-12, -1) * s, Vector2(24, 4) * s), w.get("col2", Color.WHITE))
				return
			var hw := 11.0 if w.get("big", false) else 9.0
			ci.draw_rect(Rect2(c + Vector2(-hw, -12) * s, Vector2(hw * 2, 26) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-hw, -12) * s, Vector2(hw * 2, 7) * s), col.darkened(0.2))
			ci.draw_rect(Rect2(c + Vector2(-5, 4) * s, Vector2(10, 7) * s), col.darkened(0.12))
			ci.draw_arc(c + Vector2(0, -12) * s, 4 * s, PI, TAU, 8, dark, 1.5)


## A shirt's pattern and details, on its icon (the body from (-10, -12) to (10, 15)).
static func _icon_marks(ci: CanvasItem, c: Vector2, s: float, w: Dictionary) -> void:
	var col: Color = w.col
	var c2: Color = w.get("col2", col.darkened(0.35))
	var r := func(x: float, y: float, ww: float, hh: float, cc: Color) -> void:
		ci.draw_rect(Rect2(c + Vector2(x, y) * s, Vector2(ww, hh) * s), cc)
	match w.get("pattern", ""):
		"stripe":
			for i in 5:
				r.call(-10, -10 + i * 5, 20, 2, c2)
		"plaid":
			for i in 4:
				r.call(-10, -10 + i * 7, 20, 2, Color(c2, 0.6))
				r.call(-8 + i * 5, -12, 2, 27, Color(c2, 0.6))
		"floral", "dots":
			for p in [Vector2(-6, -7), Vector2(4, -4), Vector2(-3, 3), Vector2(6, 8), Vector2(-7, 11)]:
				ci.draw_circle(c + p * s, (2.2 if w.pattern == "floral" else 1.4) * s, c2)
				if w.pattern == "floral":
					ci.draw_circle(c + p * s, 0.8 * s, Color("f0d050"))
		"camo":
			for p in [Vector2(-5, -6), Vector2(5, -1), Vector2(-4, 6), Vector2(6, 10)]:
				ci.draw_circle(c + p * s, 3.2 * s, c2)
		"print":
			r.call(-6, -6, 12, 9, c2)
			r.call(-4, -4, 8, 1.5, c2.lightened(0.5))
			r.call(-4, -1, 8, 1.5, c2.lightened(0.5))
	match w.get("detail", ""):
		"tie":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-1.5, -12) * s, c + Vector2(1.5, -12) * s, c + Vector2(2.5, 6) * s,
					c + Vector2(0, 9) * s, c + Vector2(-2.5, 6) * s]), c2)
		"buttons", "school":
			ci.draw_line(c + Vector2(0, -12) * s, c + Vector2(0, 15) * s, col.darkened(0.3), 1.0)
			if w.detail == "school":
				r.call(3, -8, 6, 2, c2)
		"number":
			r.call(-4, -6, 3, 9, c2)
			r.call(1, -6, 3, 9, c2)
		"badge":
			ci.draw_circle(c + Vector2(5, -6) * s, 2 * s, Color("d8b040"))
		"vneck":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -14) * s, c + Vector2(4, -14) * s, c + Vector2(0, -7) * s]), col.darkened(0.3))
		"collar":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -14) * s, c + Vector2(0, -14) * s, c + Vector2(-2, -9) * s]), col.lightened(0.15))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14) * s, c + Vector2(6, -14) * s, c + Vector2(2, -9) * s]), col.lightened(0.15))


static func _dome(at: Vector2, rad: float) -> Array:
	var pts := []
	for i in 13:
		pts.append(at + Vector2.from_angle(lerpf(PI, TAU, i / 12.0)) * rad)
	return pts
