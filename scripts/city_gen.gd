class_name CityGen
## Lays out a Bangkok-style district: avenues with red/white curbs, sois
## lined with shophouses, a temple, a canal (khlong), a park, condo towers,
## an elevated skytrain line, power poles and abandoned traffic.
## Deterministic for a given seed so every client builds the same city.

const ROAD_W := 6
const XS := [2, 42, 82, 122]  # left edge of each north-south avenue
const YS := [2, 40, 80]  # top edge of each east-west avenue
const CANAL_Y := 61  # canal rows 61..63, towpaths either side
const SOI_W := 3

const SIGNS := ["ข้าวมันไก่", "ก๋วยเตี๋ยวเรือ", "ร้านขายยา", "ซ่อมมอเตอร์ไซค์", "ร้านทอง", "กาแฟโบราณ",
		"ร้านตัดผม", "โรงรับจำนำ", "ส้มตำ ไก่ย่าง", "อาหารตามสั่ง", "คลินิก", "ร้านโทรศัพท์",
		"ขายส่ง", "โจ๊ก ข้าวต้ม", "ร้านวัสดุ", "นวดแผนไทย", "ผ้าไหม", "ร้านเสริมสวย"]
const WALL_COLORS := [Color("d8cfb8"), Color("c9b89a"), Color("b8c4c0"), Color("d4b8a8"), Color("a8b0a0"),
		Color("c8c0c8"), Color("e0d8c0"), Color("9aa8b0"), Color("c8a888"), Color("b0a898")]
const CAR_COLORS := [Color("e4e2dc"), Color("a8aaac"), Color("2a2c2e"), Color("8a2a26"), Color("34507a"), Color("6a6a5e")]
const TAXI_COLORS := [Color("e0609a"), Color("e0802a"), Color("3a6ac8"), Color("3a8a4a")]
## What a shop sells decides what you can find inside it (see Items.LOOT).
const SIGN_LOOT := {
	"ร้านขายยา": "med", "คลินิก": "med",
	"ข้าวมันไก่": "food", "ก๋วยเตี๋ยวเรือ": "food", "กาแฟโบราณ": "food", "ส้มตำ ไก่ย่าง": "food",
	"อาหารตามสั่ง": "food", "โจ๊ก ข้าวต้ม": "food",
	"ซ่อมมอเตอร์ไซค์": "tools", "ร้านวัสดุ": "tools", "ขายส่ง": "tools",
	"ร้านทอง": "valuables", "โรงรับจำนำ": "valuables",
}


static func build(w: World, rng: RandomNumberGenerator) -> void:
	w.fill(Rect2i(0, 0, World.W, World.H), World.GRASS)
	for x in XS:
		w.fill(Rect2i(x - 2, 0, ROAD_W + 4, World.H), World.SIDEWALK)
	for y in YS:
		w.fill(Rect2i(0, y - 2, World.W, ROAD_W + 4), World.SIDEWALK)
	w.fill(Rect2i(0, CANAL_Y - 1, World.W, 5), World.SIDEWALK)
	w.fill(Rect2i(0, CANAL_Y, World.W, 3), World.WATER)
	# Roads last, so avenues become bridges where they cross the canal.
	for x in XS:
		w.fill(Rect2i(x, 0, ROAD_W, World.H), World.ROAD)
		w.roads.append({rect = Rect2i(x, 0, ROAD_W, World.H), horizontal = false})
	for y in YS:
		w.fill(Rect2i(0, y, World.W, ROAD_W), World.ROAD)
		w.roads.append({rect = Rect2i(0, y, World.W, ROAD_W), horizontal = true})
	for x in XS:
		for y in YS:
			w.intersections.append(Rect2i(x, y, ROAD_W, ROAD_W))

	var bx := [[10, 40], [50, 80], [90, 120], [130, World.W]]
	var by := [[10, 38], [48, CANAL_Y - 1], [CANAL_Y + 4, 78], [88, World.H]]
	for i in bx.size():
		for j in by.size():
			var b := Rect2i(bx[i][0], by[j][0], bx[i][1] - bx[i][0], by[j][1] - by[j][0])
			if i == 1 and j == 0:
				_temple_block(w, b, rng)
			elif i == 2 and j == 3:
				_condo_block(w, b, rng)
			elif i == 3 and j == 3:
				_park_block(w, b, rng)
			else:
				_shophouse_block(w, b, rng)

	_skytrain(w)
	_street_furniture(w, rng)
	w.spawn_cell = Vector2i(XS[2] - 2, YS[1] + ROAD_W)  # a street corner in the middle of town


static func add_building(w: World, r: Rect2i, kind: String, rng: RandomNumberGenerator) -> void:
	w.fill(r, World.BUILDING)
	var rec := {rect = r, kind = kind, seed = rng.randi(), floors = 1, sign = "",
			color = WALL_COLORS[rng.randi() % WALL_COLORS.size()], open = rng.randf() < 0.5}
	match kind:
		"shop":
			rec.floors = rng.randi_range(2, 3)
			if rng.randf() < 0.75:
				rec.sign = SIGNS[rng.randi() % SIGNS.size()]
		"store":
			rec.sign = "มินิมาร์ท 24 ชม."
		"condo":
			rec.floors = rng.randi_range(10, 14)
	if kind in ["shop", "store"] and r.size.x >= 4:
		_make_enterable(w, rec, rng)
	w.buildings.append(rec)


## Hollow the building out: walls round the edge, a floor, a door in the front
## wall, and furniture along the back wall to search.
static func _make_enterable(w: World, rec: Dictionary, rng: RandomNumberGenerator) -> void:
	var r: Rect2i = rec.rect
	var inner := r.grow(-1)
	w.fill(r, World.IWALL)
	w.fill(inner, World.FLOOR)
	var door := r.position.x + rng.randi_range(1, r.size.x - 2)
	w.fill(Rect2i(door, r.end.y - 1, 1, 1), World.DOOR)
	w.doors.append({id = w.doors.size(), cell = Vector2i(door, r.end.y - 1), closed = rng.randf() < 0.4,
			hp = World.DOOR_HP, boards = 0, broken = rng.randf() < 0.1})
	rec.enter = true
	rec.door = door - r.position.x
	rec.table = "store" if rec.kind == "store" else SIGN_LOOT.get(rec.sign, "home")
	var kinds: Array = Items.FURNITURE[rec.table]
	var n := mini(inner.size.x, kinds.size())
	for i in n:
		# Spread along the back wall; the row nearest the door stays clear to walk.
		var x := inner.position.x + int(round(float(i) * (inner.size.x - 1) / maxf(1.0, n - 1.0))) if n > 1 else inner.position.x
		var cell := Vector2i(x, inner.position.y)
		if w.blocked.has(cell):
			continue
		w.blocked[cell] = true
		w.containers.append({id = w.containers.size(), kind = kinds[i], cell = cell, table = rec.table})


# --- Blocks -----------------------------------------------------------------

## Rows of shophouses separated by sois, with a few cross-sois for shortcuts.
static func _shophouse_block(w: World, b: Rect2i, rng: RandomNumberGenerator) -> void:
	var cols := []
	var x := b.position.x + 10 + rng.randi_range(0, 3)
	while x < b.end.x - 7:
		cols.append(x)
		w.fill(Rect2i(x, b.position.y, SOI_W, b.size.y), World.SOI)
		x += 12 + rng.randi_range(0, 4)
	var segs := []
	var sx := b.position.x
	for c in cols:
		segs.append([sx, c])
		sx = c + SOI_W
	segs.append([sx, b.end.x])

	var y := b.position.y
	while y < b.end.y:
		var depth := rng.randi_range(4, 5)
		if y + depth > b.end.y:
			break
		for s in segs:
			_row(w, s[0], s[1], y, depth, rng)
		y += depth
		w.fill(Rect2i(b.position.x, y, b.size.x, mini(SOI_W, b.end.y - y)), World.SOI)
		y += SOI_W
	# Whatever is left over becomes an overgrown vacant lot.
	for yy in range(y, b.end.y):
		for xx in range(b.position.x, b.end.x):
			if w.get_tile(Vector2i(xx, yy)) == World.GRASS:
				var r := rng.randf()
				if r < 0.12:
					w.fill(Rect2i(xx, yy, 1, 1), World.TREE)
				elif r < 0.4:
					w.fill(Rect2i(xx, yy, 1, 1), World.DIRT)


static func _row(w: World, x0: int, x1: int, y: int, depth: int, rng: RandomNumberGenerator) -> void:
	var x := x0
	while x1 - x >= 2:
		var bw := rng.randi_range(3, 5)
		if x1 - x - bw < 2:
			bw = x1 - x  # absorb a leftover sliver
		if rng.randf() < 0.07 and bw >= 3:
			w.fill(Rect2i(x, y, 2, depth), World.SOI)  # narrow walkway between buildings
			x += 2
			continue
		add_building(w, Rect2i(x, y, bw, depth), "store" if rng.randf() < 0.08 and bw >= 4 else "shop", rng)
		x += bw


static func _temple_block(w: World, b: Rect2i, rng: RandomNumberGenerator) -> void:
	w.fill(b, World.PLAZA)
	var c := b.get_center()
	for x in range(b.position.x, b.end.x):
		for y in [b.position.y, b.end.y - 1]:
			if absi(x - c.x) > 2:
				w.fill(Rect2i(x, y, 1, 1), World.WALL)
	for y in range(b.position.y, b.end.y):
		for x in [b.position.x, b.end.x - 1]:
			if absi(y - c.y) > 2:
				w.fill(Rect2i(x, y, 1, 1), World.WALL)
	add_building(w, Rect2i(c.x - 6, b.position.y + 9, 12, 9), "temple", rng)
	add_building(w, Rect2i(b.end.x - 8, b.position.y + 3, 4, 4), "chedi", rng)
	add_building(w, Rect2i(b.position.x + 3, b.end.y - 7, 5, 4), "sala", rng)
	for p in [Vector2i(3, 3), Vector2i(4, 13), Vector2i(-4, -4), Vector2i(-7, -9), Vector2i(10, 4)]:
		var cell := Vector2i(b.position.x + p.x if p.x > 0 else b.end.x + p.x, b.position.y + p.y if p.y > 0 else b.end.y + p.y)
		w.fill(Rect2i(cell, Vector2i.ONE), World.TREE)


static func _condo_block(w: World, b: Rect2i, rng: RandomNumberGenerator) -> void:
	w.fill(b, World.SOI)  # parking lot
	add_building(w, Rect2i(b.position.x + 2, b.position.y + 3, 10, 7), "condo", rng)
	add_building(w, Rect2i(b.position.x + 16, b.position.y + 13, 10, 7), "condo", rng)
	for i in 30:
		var cell := Vector2i(rng.randi_range(b.position.x, b.end.x - 3), rng.randi_range(b.position.y, b.end.y - 1))
		_vehicle(w, cell, true, rng, false)


static func _park_block(w: World, b: Rect2i, rng: RandomNumberGenerator) -> void:
	var c := Vector2(b.get_center())
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			var d := Vector2(x, y) - c
			if (d.x / 7.0) ** 2 + (d.y / 5.0) ** 2 < 1.0:
				w.fill(Rect2i(x, y, 1, 1), World.WATER)
			elif (d.x / 9.0) ** 2 + (d.y / 7.0) ** 2 < 1.0:
				pass  # open lawn around the pond
			elif rng.randf() < 0.14:
				w.fill(Rect2i(x, y, 1, 1), World.TREE)
	w.fill(Rect2i(b.position.x, b.position.y + 3, b.size.x, 2), World.SIDEWALK)  # jogging paths
	w.fill(Rect2i(b.position.x + 4, b.position.y, 2, b.size.y), World.SIDEWALK)


# --- Street furniture -------------------------------------------------------

static func _skytrain(w: World) -> void:
	var y: int = YS[1]
	w.bts_row = y + 2
	for x in range(5, World.W, 10):
		var cells := [Vector2i(x, y + 2), Vector2i(x, y + 3)]
		if w.in_intersection(cells[0]):
			continue
		for c in cells:
			w.blocked[c] = true
		w.street_props.append({kind = "pillar", pos = Vector2(x * World.TILE, (y + 4) * World.TILE)})


static func _street_furniture(w: World, rng: RandomNumberGenerator) -> void:
	# Power poles on the curb, every 6 tiles, wired together; every other one has a street lamp.
	for rd in w.roads:
		var r: Rect2i = rd.rect
		var sides := [[r.position.y - 1, Vector2(0, 20)], [r.end.y, Vector2(0, -20)]] if rd.horizontal \
				else [[r.position.x - 1, Vector2(20, 0)], [r.end.x, Vector2(-20, 0)]]
		for side in sides:
			var prev: Vector2 = Vector2.INF
			var n := 0
			for i in range(1, World.W if rd.horizontal else World.H, 6):
				var c := Vector2i(i, side[0]) if rd.horizontal else Vector2i(side[0], i)
				if w.get_tile(c) != World.SIDEWALK:
					prev = Vector2.INF
					continue
				var pos := w.to_pos(c) + Vector2(0, 5)
				n += 1
				w.street_props.append({kind = "pole", pos = pos, lamp = side[1] if n % 2 == 0 else Vector2.ZERO,
						seed = rng.randi()})
				if prev != Vector2.INF:
					w.wires.append([prev + Vector2(0, -44), pos + Vector2(0, -44)])
				prev = pos
		# Street trees on the outer edge of the pavement.
		var outer := [r.position.y - 2, r.end.y + 1] if rd.horizontal else [r.position.x - 2, r.end.x + 1]
		for o in outer:
			for i in range(4, World.W if rd.horizontal else World.H, 9):
				var c := Vector2i(i, o) if rd.horizontal else Vector2i(o, i)
				if w.get_tile(c) == World.SIDEWALK and rng.randf() < 0.55:
					w.fill(Rect2i(c, Vector2i.ONE), World.TREE)
		# Abandoned traffic.
		var length := World.W if rd.horizontal else World.H
		for k in length / 7:
			var along := rng.randi_range(0, length - 3)
			var lane: int = [0, 1, 4, 5][rng.randi() % 4]
			var c := Vector2i(along, r.position.y + lane) if rd.horizontal else Vector2i(r.position.x + lane, along)
			_vehicle(w, c, rd.horizontal, rng, true)

	# Food carts, parked motorbikes and rubbish around the shops.
	for i in 900:
		var c := Vector2i(rng.randi_range(0, World.W - 1), rng.randi_range(1, World.H - 1))
		var t := w.get_tile(c)
		if t not in [World.SIDEWALK, World.SOI] or w.blocked.has(c):
			continue
		var in_front := w.get_tile(c + Vector2i.UP) in [World.BUILDING, World.IWALL]
		var by_road := false
		for d in World.DIRS:
			if w.get_tile(c + d) == World.ROAD:
				by_road = true
		var roll := rng.randf()
		if t == World.SIDEWALK and not by_road and roll < 0.08:
			w.blocked[c] = true
			w.street_props.append({kind = "cart", pos = w.to_pos(c) + Vector2(0, 5), seed = rng.randi()})
		elif in_front and roll < 0.35:
			w.street_props.append({kind = "motorbike", pos = w.to_pos(c) + Vector2(rng.randf_range(-3, 3), 5),
					seed = rng.randi()})
		elif in_front and roll < 0.55:
			w.street_props.append({kind = "trash", pos = w.to_pos(c) + Vector2(rng.randf_range(-4, 4), 5),
					seed = rng.randi()})


## Park a car / taxi / tuk-tuk if its cells are free road.
static func _vehicle(w: World, c: Vector2i, horizontal: bool, rng: RandomNumberGenerator, on_road: bool) -> void:
	var roll := rng.randf()
	var kind := "tuktuk" if roll < 0.18 and on_road else ("taxi" if roll < 0.42 and on_road else "car")
	var cells := [c] if kind == "tuktuk" else ([c, c + Vector2i.RIGHT] if horizontal else [c, c + Vector2i.DOWN])
	for cell in cells:
		if w.get_tile(cell) not in [World.ROAD, World.SOI] or w.blocked.has(cell) or w.in_intersection(cell):
			return
		# Keep a gap so vehicles never wall off a lane completely.
		for d in World.DIRS:
			if w.blocked.has(cell + d) and not cells.has(cell + d):
				return
	for cell in cells:
		w.blocked[cell] = true
	var last: Vector2i = cells[-1]
	var color: Color = TAXI_COLORS[rng.randi() % TAXI_COLORS.size()] if kind == "taxi" \
			else CAR_COLORS[rng.randi() % CAR_COLORS.size()]
	w.street_props.append({kind = kind, horizontal = horizontal or kind == "tuktuk",
			pos = Vector2(c.x * World.TILE, (last.y + 1) * World.TILE), color = color, seed = rng.randi()})
