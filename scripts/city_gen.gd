class_name CityGen
## Lays out a Bangkok-style district: avenues with red/white curbs, sois
## lined with shophouses, a temple, a canal (khlong), a park, condo towers,
## an elevated skytrain line, power poles and abandoned traffic.
## Deterministic for a given seed so every client builds the same city.

const ROAD_W := 6
## The town is laid out in sections of SECTION cells, repeated to fill the map
## (until a hand-drawn district plan replaces it). In each section:
const SECTION := Vector2i(160, 120)
const XS := [2, 42, 82, 122]  # left edge of each north-south avenue
const YS := [2, 44, 92]  # top edge of each east-west avenue
const CANAL_Y := 68  # canal rows 68..70, towpaths either side
## ...and across the whole map (a zone's size: see Zones), worked out per build:
static var ALL_XS: Array = []
static var ALL_YS: Array = []
static var CANALS: Array = []
## Scattered things (clutter, parked bikes) are placed per this much map.
static var AREA := 1.0


static func repeat(at: Array, step: int, size: int) -> Array:
	var out := []
	for o in range(0, size, step):
		for v in at:
			out.append(o + v)
	return out
const SOI_W := 3

const SIGNS := ["ข้าวมันไก่", "ก๋วยเตี๋ยวเรือ", "ร้านขายยา", "ซ่อมมอเตอร์ไซค์", "ร้านทอง", "กาแฟโบราณ",
		"ร้านตัดผม", "โรงรับจำนำ", "ส้มตำ ไก่ย่าง", "อาหารตามสั่ง", "คลินิก", "ร้านโทรศัพท์",
		"ขายส่ง", "โจ๊ก ข้าวต้ม", "ร้านวัสดุ", "นวดแผนไทย", "ผ้าไหม", "ร้านเสริมสวย"]
const WALL_COLORS := [Color("e2d3b0"), Color("d8b48a"), Color("a8c8c0"), Color("e0b0a4"), Color("b4c498"),
		Color("c8b8d8"), Color("ecdca8"), Color("9ab4c8"), Color("d89a78"), Color("c8c0b0")]
const CAR_COLORS := [Color("e4e2dc"), Color("a8aaac"), Color("2a2c2e"), Color("8a2a26"), Color("34507a"), Color("6a6a5e")]
const BUS_COLORS := [Color("d8c8a0"), Color("2a5aa8"), Color("e8e4dc")]  # the old red-and-cream, the blue air-con, the white one
## How many cells a parked vehicle takes along its length (see _vehicle; its drawing may overhang a little).
const VEHICLE_CELLS := {car = 2, taxi = 2, van = 2, pickup = 2, songthaew = 2, bus = 7}
const TAXI_COLORS := [Color("e0609a"), Color("e0802a"), Color("3a6ac8"), Color("3a8a4a")]
## Dressing for each kind of place (see DecorProp); floor things never block.
## What a shop sells decides what you can find inside it (see Items.roll).
const SIGN_LOOT := {
	"ร้านขายยา": "med", "คลินิก": "med",
	"ข้าวมันไก่": "food", "ก๋วยเตี๋ยวเรือ": "food", "กาแฟโบราณ": "food", "ส้มตำ ไก่ย่าง": "food",
	"อาหารตามสั่ง": "food", "โจ๊ก ข้าวต้ม": "food",
	"ซ่อมมอเตอร์ไซค์": "tools", "ร้านวัสดุ": "tools", "ขายส่ง": "tools",
	"ร้านทอง": "valuables", "โรงรับจำนำ": "valuables",
	"ผ้าไหม": "clothes", "นวดแผนไทย": "clothes",
	"ร้านตัดผม": "barber", "ร้านเสริมสวย": "barber", "ร้านโทรศัพท์": "phone",
}


## Which city generator this is. Saves remember it: a city saved by an older
## generator cannot be rebuilt from its seed any more (see SaveGame).
## 1: shallow shophouses laid out in code. 2: deep ones from data/prefabs.
const GEN := 8  # 8: zones drawn by hand (Victory Monument)
const PREFAB_DIR := "res://data/prefabs"  # (exports must include *.txt)
const MIN_DEPTH := 13  # plots are at least this deep; no plan may be deeper
const MAX_DEPTH := 15
const PLAN_FURNITURE := {f = "fridge", c = "cabinet", s = "shelf", k = "counter", t = "table", x = "crate",
		g = "glass", M = "mirror", X = "toolchest", H = "stall", Z = "safe", F = "pantry", K = "sink"}
const PLAN_DECOR := {S = "stairs", m = "mattress", v = "tv", n = "fan", h = "shrine", o = "boxes", p = "pot",
		r = "chairs", i = "tires", e = "bike", l = "oil", A = "barberchair", G = "stove", J = "jar", O = "sofa",
		a = "altar", y = "sacks", E = "mannequin", L = "recliner", V = "examcot", u = "washbasin", z = "bench",
		q = "toilet", C = "curtain", j = "shoes", I = "hiphra"}
## Dressing too big to walk through (the rest you step over or past).
const DECOR_BLOCKS := ["barberchair", "stove", "jar", "sofa", "altar", "sacks", "mannequin", "recliner",
		"examcot", "washbasin", "bench"]
const PLAN_OTHER := "WD.BdwU?bTR"
const SHOP_W := [6, 7]  # a shophouse plot, walls included (4-5 m inside); the wall between two is shared
const STORE_W := 8

## name -> {kinds, rows (Strings), stretch (bools), width}
static var PREFABS: Dictionary = _load_prefabs()


static func _load_prefabs() -> Dictionary:
	var out := {}
	for file in DirAccess.get_files_at(PREFAB_DIR):
		if not file.ends_with(".txt") or file == "README.txt":
			continue
		var f := FileAccess.open(PREFAB_DIR.path_join(file), FileAccess.READ)
		var p := {kinds = [], signs = [], widen = -1, rows = [], stretch = [], upper = [], upper_stretch = [], width = 0}
		var rows: Array = p.rows
		var stretches: Array = p.stretch
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line == "" or line.begins_with("#"):
				continue
			if line.begins_with("kinds:"):
				p.kinds = Array(line.trim_prefix("kinds:").strip_edges().split(" ", false))
				continue
			if line.begins_with("signs:"):
				for sg in line.trim_prefix("signs:").split(",", false):
					p.signs.append(sg.strip_edges())
				continue
			if line.begins_with("widen:"):
				p.widen = int(line.trim_prefix("widen:"))
				continue
			if line.begins_with("floor 2:"):
				rows = p.upper
				stretches = p.upper_stretch
				continue
			var stretch := line.begins_with("~")
			rows.append(line.trim_prefix("~"))
			stretches.append(stretch)
		if not p.rows.is_empty():
			p.width = p.rows[0].length()
			out[file.get_basename()] = p
	return out


## What is wrong with the layouts, one line each (the tests run this).
static func prefab_problems() -> Array:
	var out := []
	for name in PREFABS:
		var p: Dictionary = PREFABS[name]
		if p.kinds.is_empty():
			out.append("%s: no kinds:" % name)
		if p.rows.size() > MIN_DEPTH:
			out.append("%s: %d rows deep, more than %d" % [name, p.rows.size(), MIN_DEPTH])
		if not p.stretch.has(true):
			out.append("%s: no ~ row to make it deeper" % name)
		if p.rows[-1].count("D") != 1 and p.rows[-1].count("U") < 2:
			out.append("%s: the bottom row needs one front door D or a shutter UU.." % name)
		if not p.upper.is_empty() and (p.upper.size() != p.rows.size() or p.upper_stretch != p.stretch):
			out.append("%s: floor 2 must have the same rows (and ~ rows) as the ground floor" % name)
		elif not p.upper.is_empty():
			for y in p.rows.size():
				for x in p.width:
					if (p.rows[y][x] == "S") != (p.upper[y][x] == "S"):
						out.append("%s: the stairs must be in the same place on both floors (row %d)" % [name, y + 1])
		if p.widen >= p.width:
			out.append("%s: widen column %d is outside the plan" % [name, p.widen])
		for row in p.rows + p.upper:
			if row.length() != p.width:
				out.append("%s: row '%s' is not %d wide" % [name, row, p.width])
			for ch in row:
				if not (PLAN_FURNITURE.has(ch) or PLAN_DECOR.has(ch) or ch in PLAN_OTHER):
					out.append("%s: unknown letter '%s'" % [name, ch])
	return out


static func build(w: World, rng: RandomNumberGenerator) -> void:
	AREA = float(World.W * World.H) / (SECTION.x * SECTION.y)
	var plan: Dictionary = {} if w.zone == "backdrop" else Zones.def(w.zone).plan
	if plan.is_empty():
		_layout_sections(w, rng)
	else:
		_layout_plan(w, plan, rng)
	# Last, so everything above comes out the same for a given seed as it always has.
	_aftermath(w, rng)
	Things.place_all(w, rng)
	_size_vehicles(w)
	_size_beds(w)
	_shop_fronts(w)
	_zone_exits(w)
	_landmarks(w)


## A zone drawn by hand (data/zones/*.cfg): its streets, roundabout, canal,
## skytrain and blocks where the plan puts them; the blocks filled with
## shophouses and sois as anywhere else.
static func _layout_plan(w: World, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	ALL_XS = []
	ALL_YS = []
	CANALS = []
	w.fill(Rect2i(0, 0, World.W, World.H), World.GRASS)
	var rects := []
	for rd in plan.get("roads", []):
		var a: Array = rd.rect
		rects.append(Rect2i(a[0], a[1], a[2], a[3]))
	for r: Rect2i in rects:
		w.fill(r.grow(2), World.SIDEWALK)
	var circle: Dictionary = plan.get("circle", {})
	if not circle.is_empty():
		_disk(w, Vector2i(circle.at[0], circle.at[1]), circle.r + 2, World.SIDEWALK)
	for cn in plan.get("canals", []):
		w.fill(Rect2i(0, cn.y - 2, World.W, cn.h + 4), World.SIDEWALK)  # towpaths
		w.fill(Rect2i(0, cn.y, World.W, cn.h), World.WATER)
		CANALS.append(cn.y)
	# Streets last, so they're bridges where they cross the canal.
	var roads: Array = plan.get("roads", [])
	for i in rects.size():
		var r: Rect2i = rects[i]
		w.fill(r, World.ROAD)
		var horizontal := r.size.x > r.size.y
		w.roads.append({rect = r, horizontal = horizontal, median = roads[i].get("median", false), name = roads[i].get("name", "")})
		if roads[i].get("median", false):
			# A raised island down the middle (the skytrain's pillars stand on it).
			var wd := r.size.y if horizontal else r.size.x
			var m := Rect2i(r.position.x, r.position.y + wd / 2 - 1, r.size.x, 2) if horizontal \
					else Rect2i(r.position.x + wd / 2 - 1, r.position.y, 2, r.size.y)
			w.medians.append(m)
	for j in plan.get("junctions", []):
		w.intersections.append(Rect2i(j[0], j[1], j[2], j[3]))
	if not circle.is_empty():
		var at := Vector2i(circle.at[0], circle.at[1])
		_disk(w, at, circle.r, World.ROAD)
		_disk(w, at, circle.island, World.GRASS)  # a ring of garden round the paved middle
		_disk(w, at, circle.island - 4, World.PLAZA)
		for k in 8:
			var a := TAU * (k + 0.5) / 8.0
			w.fill(Rect2i(at + Vector2i(roundi(cos(a) * (circle.island - 2)), roundi(sin(a) * (circle.island - 2))), Vector2i.ONE), World.TREE)
		w.circle = {at = at, r = circle.r, island = circle.island}
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				if dx * dx + dy * dy <= 25:
					w.blocked[at + Vector2i(dx, dy)] = true  # the monument's base
	w.fill(Rect2i(0, World.H - 3, World.W, 3), World.SIDEWALK)  # (the south edge: shops face onto it)
	w.blocks = []
	for b in plan.get("blocks", []):
		var br := Rect2i(b.rect[0], b.rect[1], b.rect[2], b.rect[3])
		w.blocks.append({rect = br, use = b.get("use", "shophouses"), name = b.get("name", "")})
		_shophouse_block(w, br, rng)
	if plan.has("bts"):
		_skytrain_plan(w, plan.bts)
	_street_furniture(w, rng)
	var sp: Array = plan.get("spawn", [World.W / 2, World.H / 2])
	w.spawn_cell = Vector2i(sp[0], sp[1])


## Would this lot stand on the roundabout (or its pavement)?
static func _on_circle(w: World, r: Rect2i) -> bool:
	if w.circle.is_empty():
		return false
	var c := Vector2(w.circle.at)
	var near := Vector2(clampf(c.x, r.position.x, r.end.x - 1), clampf(c.y, r.position.y, r.end.y - 1))
	return near.distance_to(c) <= w.circle.r + 3


## Every cell within `r` of `at`.
static func _disk(w: World, at: Vector2i, r: int, tile: int) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				w.fill(Rect2i(at + Vector2i(dx, dy), Vector2i.ONE), tile)


## The skytrain of a drawn zone: up the street at column `x`, round the far side
## of the roundabout at `around` cells, on down; a station over `station`
## (rows). World.bts_path is the line it follows, in pixels.
static func _skytrain_plan(w: World, bts: Dictionary) -> void:
	var T := World.TILE
	var x: float = (bts.x + 0.5) * T
	var path := PackedVector2Array()
	if not w.circle.is_empty():
		var c: Vector2 = w.to_pos(w.circle.at)
		var r: float = bts.get("around", 36) * T
		path.append(Vector2(x, 0))
		for i in 25:
			var a := -PI / 2 + PI * i / 24.0
			path.append(c + Vector2(cos(a), sin(a)) * r)
		path.append(Vector2(x, World.H * T))
	else:
		path.append(Vector2(x, 0))
		path.append(Vector2(x, World.H * T))
	w.bts_path = path
	w.bts_station = Vector2(bts.station[0], bts.station[1]) * T if bts.has("station") else Vector2(-1, -1)
	# Pillars every 10 cells along it, where there's street or pavement to stand them on.
	var d := 0.0
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var seg := a.distance_to(b)
		while d < seg:
			var p := a.lerp(b, d / seg)
			var cell := w.to_cell(p)
			if w.get_tile(cell) in [World.ROAD, World.SIDEWALK, World.PLAZA] and not w.blocked.has(cell) \
					and not (w.circle.has("at") and Vector2(cell).distance_to(Vector2(w.circle.at)) < w.circle.island + 1):
				w.blocked[cell] = true
				w.street_props.append({kind = "pillar", pos = w.to_pos(cell) + Vector2(-8, 8)})
			d += 10.0 * T
		d -= seg
	if w.bts_station.x >= 0:
		# Stairs down from the station to the pavement on both sides of the street.
		var sy := int((w.bts_station.x + w.bts_station.y) / 2 / T)
		for rd in w.roads:
			var r: Rect2i = rd.rect
			if not rd.horizontal and r.has_point(Vector2i(int(x / T), sy)):
				for side in [r.position.x - 2, r.end.x + 1]:
					var cell := Vector2i(side, sy)
					w.blocked[cell] = true
					w.street_props.append({kind = "btsstairs", pos = w.to_pos(cell) + Vector2(0, 8), seed = side})
				break


## The one-off buildings a drawn zone is known by (the monument...).
static func _landmarks(w: World) -> void:
	if w.circle.is_empty():
		return
	var at: Vector2i = w.circle.at
	w.street_props.append({kind = "monument", pos = w.to_pos(at) + Vector2(0, 5 * World.TILE), seed = 0})
	# Round the roundabout: the bus stops everyone waited at, and where the
	# minivans to everywhere used to queue, left as they were.
	var reach: int = w.circle.r + 6
	for arm in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		for side in [-1, 1]:
			var cell: Vector2i = at + arm * reach + Vector2i(arm.y, arm.x) * side * 9
			for k in 6:
				if w.get_tile(cell) == World.SIDEWALK and not w.blocked.has(cell) and w.get_tile(cell + Vector2i.DOWN) == World.SIDEWALK:
					break
				cell += Vector2i(arm.y, arm.x) * side
			if w.get_tile(cell) == World.SIDEWALK and not w.blocked.has(cell):
				w.blocked[cell] = true
				w.street_props.append({kind = "busstop", pos = w.to_pos(cell) + Vector2(0, 6), seed = cell.x * 31 + cell.y})
	# The minivan stand along the street west of the roundabout.
	var rng := RandomNumberGenerator.new()
	rng.seed = w.city_seed + 77
	for k in 5:
		var c := Vector2i(at.x - (w.circle.r + 10 + k * 4), at.y - 6)
		if _fits(w, [c, c + Vector2i.RIGHT], true):
			for cell in [c, c + Vector2i.RIGHT]:
				w.blocked[cell] = true
			w.street_props.append({kind = "van", horizontal = true, pos = Vector2(c.x * World.TILE, (c.y + 1) * World.TILE),
					color = Color("e8e6e0"), seed = rng.randi(), stand = true})


## The old town: sections of avenues, sois, a temple, condos, a park and a
## canal, repeated to fill the map (zones without a plan, the title screen).
static func _layout_sections(w: World, rng: RandomNumberGenerator) -> void:
	ALL_XS = repeat(XS, SECTION.x, World.W)
	ALL_YS = repeat(YS, SECTION.y, World.H)
	CANALS = repeat([CANAL_Y], SECTION.y, World.H)
	w.fill(Rect2i(0, 0, World.W, World.H), World.GRASS)
	for x in ALL_XS:
		w.fill(Rect2i(x - 2, 0, ROAD_W + 4, World.H), World.SIDEWALK)
	for y in ALL_YS:
		w.fill(Rect2i(0, y - 2, World.W, ROAD_W + 4), World.SIDEWALK)
	for y in CANALS:
		w.fill(Rect2i(0, y - 2, World.W, 7), World.SIDEWALK)  # towpaths two wide
		w.fill(Rect2i(0, y, World.W, 3), World.WATER)
	# Roads last, so avenues become bridges where they cross the canal.
	for x in ALL_XS:
		w.fill(Rect2i(x, 0, ROAD_W, World.H), World.ROAD)
		w.roads.append({rect = Rect2i(x, 0, ROAD_W, World.H), horizontal = false})
	for y in ALL_YS:
		w.fill(Rect2i(0, y, World.W, ROAD_W), World.ROAD)
		w.roads.append({rect = Rect2i(0, y, World.W, ROAD_W), horizontal = true})
	for x in ALL_XS:
		for y in ALL_YS:
			w.intersections.append(Rect2i(x, y, ROAD_W, ROAD_W))

	var bx := [[10, 40], [50, 80], [90, 120], [130, SECTION.x]]
	var by := [[10, 42], [52, CANAL_Y - 2], [CANAL_Y + 5, 90], [100, SECTION.y]]
	for ox in range(0, World.W, SECTION.x):
		for oy in range(0, World.H, SECTION.y):
			for i in bx.size():
				for j in by.size():
					var b := Rect2i(ox + bx[i][0], oy + by[j][0], bx[i][1] - bx[i][0], by[j][1] - by[j][0])
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
	# A street corner in the middle of town.
	var mid := Vector2i(World.W / SECTION.x / 2 * SECTION.x, World.H / SECTION.y / 2 * SECTION.y)
	w.spawn_cell = mid + Vector2i(XS[2] - 2, YS[1] + ROAD_W)


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
	if kind in ["shop", "store"]:
		# A plan made for what this shop sells if there is one, else a plain one.
		var fits := PREFABS.keys().filter(func(n): return kind in PREFABS[n].kinds and _fits_width(PREFABS[n], r.size.x))
		var plans := fits.filter(func(n): return rec.sign in PREFABS[n].signs)
		if plans.is_empty():
			plans = fits.filter(func(n): return PREFABS[n].signs.is_empty())
		plans.sort()
		if not plans.is_empty():
			_build_plan(w, rec, PREFABS[plans[rng.randi() % plans.size()]], rng)
	w.buildings.append(rec)


static func _fits_width(plan: Dictionary, width: int) -> bool:
	return plan.width == width or (plan.widen >= 0 and width > plan.width and width - plan.width <= 2)


## A plan's rows made `width` wide by repeating its widen column. What is
## only ever one of (a door, the stairs, a bed) gets what is beside it instead
## of a twin: more wall beside a door in a wall, more floor beside a doorway.
const WIDEN_ONCE := "dBDSbTRqU"


static func _widened(rows: Array, plan: Dictionary, width: int) -> Array:
	if width == plan.width:
		return rows
	var out := []
	for row: String in rows:
		var ch: String = row[plan.widen]
		if ch in WIDEN_ONCE and ch != "U":
			ch = row[plan.widen - 1] if plan.widen > 0 and row[plan.widen - 1] in "W.wU" else "."
		out.append(row.substr(0, plan.widen) + ch.repeat(width - plan.width) + row.substr(plan.widen))
	return out


## A plan's rows made the plot's size: widened, and the ~ rows repeated to fill its depth.
static func _fit(plan_rows: Array, plan: Dictionary, r: Rect2i) -> Array:
	var ground: Array = _widened(plan_rows, plan, r.size.x)
	var extra: int = r.size.y - plan_rows.size()
	var n_stretch: int = plan.stretch.count(true)
	var rows := []
	var k := 0
	for i in ground.size():
		rows.append(ground[i])
		if plan.stretch[i]:
			for j in extra / n_stretch + (1 if k < extra % n_stretch else 0):
				rows.append(ground[i])
			k += 1
	return rows


## The floor upstairs (World.upper): its walls and floor, the beds and
## cupboards up there (containers with `up`), what's on the floor. Doorways
## upstairs are open; the stairs are the same cell as below.
static func _build_upper(w: World, rec: Dictionary, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var r: Rect2i = rec.rect
	var rows := _fit(plan.upper, plan, r)
	rec.upper = true
	for y in rows.size():
		for x in r.size.x:
			var ch: String = rows[y][x]
			var c := r.position + Vector2i(x, y)
			if ch in "WwUDB":
				w.upper[c] = World.IWALL
				continue
			w.upper[c] = World.FLOOR
			if ch == "b" and y > 0 and rows[y - 1][x] == "b":
				continue  # the foot of the bed above
			if PLAN_FURNITURE.has(ch) or ch == "b":
				var data := {id = w.containers.size(), kind = PLAN_FURNITURE.get(ch, "bed"), cell = c, table = "home", sign = rec.sign, up = true}
				if ch == "b" and y + 1 < rows.size() and rows[y + 1][x] == "b":
					data.long = 2
					w.upper_blocked[c + Vector2i.DOWN] = true
				w.upper_blocked[c] = true
				w.containers.append(data)
			elif PLAN_DECOR.has(ch) and ch != "S":
				w.decor.append({kind = PLAN_DECOR[ch], cell = c, seed = rng.randi(), building = rec, up = true})
				if PLAN_DECOR[ch] in DECOR_BLOCKS:
					w.upper_blocked[c] = true


## Build the inside of a shop or home from its plan (see data/prefabs/README.txt).
static func _build_plan(w: World, rec: Dictionary, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var r: Rect2i = rec.rect
	rec.table = "store" if rec.kind == "store" else SIGN_LOOT.get(rec.sign, "home")
	var rows := _fit(plan.rows, plan, r)
	w.fill(r, World.IWALL)
	var furniture := []  # [cell, letter]
	var decor := []
	var beds := {}
	var front := Vector2i(-1, -1)
	rec.taps = []
	rec.radios = []
	var shutter := []
	for y in rows.size():
		for x in r.size.x:
			var ch: String = rows[y][x]
			var c := r.position + Vector2i(x, y)
			match ch:
				"W":
					pass
				"D":
					_add_opening(w, c, "door", rng)
					rec.door = x
					front = c + Vector2i.UP
				"B":
					if w.get_tile(c + Vector2i.UP) in [World.SOI, World.SIDEWALK, World.DIRT, World.GRASS]:
						_add_opening(w, c, "door", rng)
				"d":
					_add_opening(w, c, "door", rng)
					w.doors[-1].closed = false
					w.doors[-1].broken = false
				"w":
					if rng.randf() < 0.6:
						_add_opening(w, c, "window", rng)
				"U":
					_add_opening(w, c, "shutter", rng)
					shutter.append(w.doors.size() - 1)
				_:
					w.fill(Rect2i(c, Vector2i.ONE), World.FLOOR)
					if ch == "b":
						beds[c] = true
					if PLAN_FURNITURE.has(ch) or ch in "?b":
						furniture.append([c, ch])
					elif PLAN_DECOR.has(ch):
						decor.append([c, PLAN_DECOR[ch]])
					elif ch == "T":
						rec.taps.append(c)
					elif ch == "R":
						rec.radios.append(c)
	rec.enter = true
	if not shutter.is_empty():
		# A rolling steel shutter across the whole shop front: all up or all
		# down (padlocked from inside), now and then one slat prised up.
		var down: bool = not rec.open
		var pried := down and rng.randf() < 0.15
		for i in shutter.size():
			var d: Dictionary = w.doors[shutter[i]]
			d.group = shutter
			d.closed = down
			d.broken = pried and i == shutter.size() / 2
			if d.broken:
				d.closed = false
		var mid: Vector2i = w.doors[shutter[shutter.size() / 2]].cell
		rec.door = mid.x - r.position.x
		rec.shutter = true
		front = mid + Vector2i.UP
	# Rooms: floor joined up without passing a door.
	var room_of := {}
	var rooms := []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if w.get_tile(c) != World.FLOOR or room_of.has(c):
				continue
			var cells := [c]
			room_of[c] = rooms.size()
			var box := Rect2i(c, Vector2i.ONE)
			var i := 0
			while i < cells.size():
				for d in World.DIRS:
					var nc: Vector2i = cells[i] + d
					if r.has_point(nc) and w.get_tile(nc) == World.FLOOR and not room_of.has(nc):
						room_of[nc] = rooms.size()
						cells.append(nc)
						box = box.expand(nc)
				i += 1
			rooms.append(box)
	rec.rooms = rooms
	rec.keep_clear = []
	# The shop's own room holds what it sells; the rest is the family's, if
	# they live here (a bed anywhere, down here or upstairs).
	var shop_room: int = room_of.get(front, -1)
	var home_rooms := {}
	for c in beds:
		home_rooms[room_of[c]] = true
	if not plan.upper.is_empty() and "b" in "".join(plan.upper):
		home_rooms[-2] = true  # (-2: the rooms upstairs)
	var sells: Array = Items.FURNITURE[rec.table]
	var next_sold := 0
	for e in furniture:
		var c: Vector2i = e[0]
		var kind: String = PLAN_FURNITURE.get(e[1], "")
		if e[1] == "?":
			if next_sold >= sells.size():
				continue
			kind = sells[next_sold]
			next_sold += 1
		var long := 0
		if e[1] == "b":
			if beds.has(c + Vector2i.UP):
				continue  # the foot of a bed that starts above
			kind = "bed"
			long = 2 if beds.has(c + Vector2i.DOWN) else 0
		var table: String = rec.table if room_of[c] == shop_room or home_rooms.is_empty() else "home"
		var data := {id = w.containers.size(), kind = kind, cell = c, table = table, sign = rec.sign}
		if kind == "bed":
			data.long = long
			if long == 2:
				w.blocked[c + Vector2i.DOWN] = true
		w.blocked[c] = true
		w.containers.append(data)
	for e in decor:
		w.decor.append({kind = e[1], cell = e[0], seed = rng.randi(), building = rec})
		if e[1] in DECOR_BLOCKS:
			w.blocked[e[0]] = true
		if e[1] == "stairs":
			rec.stairs = e[0]
			w.stairs[e[0]] = true
	for box in rooms:
		w.decor.append({kind = "bulb", cell = Vector2i(box.get_center()), seed = 0, building = rec})
	if not plan.upper.is_empty() and rec.kind == "shop":
		_build_upper(w, rec, plan, rng)


## A door or window in a wall. Windows start intact (glass), some already smashed.
static func _add_opening(w: World, cell: Vector2i, kind: String, rng: RandomNumberGenerator) -> void:
	w.fill(Rect2i(cell, Vector2i.ONE), World.DOOR)
	var d := {id = w.doors.size(), cell = cell, kind = kind, boards = 0}
	if kind == "shutter":
		d.merge({closed = true, hp = World.SHUTTER_HP, broken = false})  # (set for the whole front: see _build_plan)
	elif kind == "window":
		var smashed := rng.randf() < 0.3
		d.merge({closed = not smashed, hp = World.WINDOW_HP, broken = smashed})
	else:
		d.merge({closed = rng.randf() < 0.4, hp = World.DOOR_HP, broken = rng.randf() < 0.1})
	w.doors.append(d)


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
		var depth := mini(rng.randi_range(MIN_DEPTH, MAX_DEPTH), b.end.y - y)
		if depth < MIN_DEPTH:
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


## A row of shophouses wall to wall, each sharing its side wall with the next
## (as real ones do: one party wall, not two).
static func _row(w: World, x0: int, x1: int, y: int, depth: int, rng: RandomNumberGenerator) -> void:
	var x := x0  # the next free column
	var shared := false  # the last building ends at x - 1, so the next can share that wall
	while x < x1:
		var start := x - 1 if shared else x
		var left := x1 - start
		if left < SHOP_W[0]:
			if x < x1:
				w.fill(Rect2i(x, y, x1 - x, depth), World.SOI)  # too narrow for a house: an alley
			return
		if rng.randf() < 0.07 and not shared:
			w.fill(Rect2i(x, y, 2, depth), World.SOI)  # narrow walkway between buildings
			x += 2
			continue
		var kind := "shop"
		var bw: int = SHOP_W[rng.randi() % SHOP_W.size()]
		if left >= STORE_W and rng.randf() < 0.1:
			kind = "store"
			bw = STORE_W
		if left - bw < SHOP_W[0] - 1:
			bw = mini(left, STORE_W)  # the last one takes what's left
		if _on_circle(w, Rect2i(start, y, bw, depth)):
			# (on a drawn zone's roundabout: left as an open soi)
			w.fill(Rect2i(x, y, start + bw - x, depth), World.SOI)
			x = start + bw
			shared = false
			continue
		add_building(w, Rect2i(start, y, bw, depth), kind, rng)
		x = start + bw
		shared = true


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
	var y: int = World.H / SECTION.y / 2 * SECTION.y + YS[1]  # (one line, through the middle of town)
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
		var from: int = r.position.x if rd.horizontal else r.position.y
		var to: int = r.end.x if rd.horizontal else r.end.y
		var wd: int = r.size.y if rd.horizontal else r.size.x
		for side in sides:
			var prev: Vector2 = Vector2.INF
			var n := 0
			for i in range(from + 1, to, 6):
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
			for i in range(from + 4, to, 9):
				var c := Vector2i(i, o) if rd.horizontal else Vector2i(o, i)
				if w.get_tile(c) == World.SIDEWALK and rng.randf() < 0.55 						and World.DIRS.all(func(d): return w.get_tile(c + d) != World.DOOR):  # never in front of a door
					w.fill(Rect2i(c, Vector2i.ONE), World.TREE)
		# Abandoned traffic.
		var length := to - from
		for k in length / 7:
			var along := from + rng.randi_range(0, length - 3)
			var lane: int = [0, 1, wd - 2, wd - 1][rng.randi() % 4]
			var c := Vector2i(along, r.position.y + lane) if rd.horizontal else Vector2i(r.position.x + lane, along)
			_vehicle(w, c, rd.horizontal, rng, true)

	# Food carts and rubbish around the shops, and motorbikes along the kerb of
	# the avenues running up and down (those along the shop fronts: see below).
	for i in int(900 * AREA):
		var c := Vector2i(rng.randi_range(0, World.W - 1), rng.randi_range(1, World.H - 1))
		var t := w.get_tile(c)
		if t not in [World.SIDEWALK, World.SOI] or w.blocked.has(c):
			continue
		var in_front := w.get_tile(c + Vector2i.UP) in [World.BUILDING, World.IWALL]
		var by_road := false
		for d in World.DIRS:
			if w.get_tile(c + d) == World.ROAD:
				by_road = true
		var road_side := -1 if w.get_tile(c + Vector2i.LEFT) == World.ROAD else (1 if w.get_tile(c + Vector2i.RIGHT) == World.ROAD else 0)
		var roll := rng.randf()
		if t == World.SIDEWALK and not by_road and roll < 0.08:
			w.blocked[c] = true
			w.street_props.append({kind = "cart", pos = w.to_pos(c) + Vector2(0, 5), seed = rng.randi()})
		elif t == World.SIDEWALK and road_side != 0 and roll < 0.6:
			# Nose to the road, side-on to us, in a row along the kerb.
			if not w.in_intersection(c + Vector2i(road_side, 0)):
				_park(w, {kind = "motorbike", pos = w.to_pos(c) + Vector2(0, rng.randf_range(-4, 4)), seed = rng.randi(),
						view = "side", dir = float(road_side)})
		elif in_front and roll < 0.55:
			w.street_props.append({kind = "trash", pos = w.to_pos(c) + Vector2(rng.randf_range(-4, 4), 5),
					seed = rng.randi()})


## Park a car / taxi / tuk-tuk if its cells are free road.
static func _vehicle(w: World, c: Vector2i, horizontal: bool, rng: RandomNumberGenerator, on_road: bool) -> void:
	var roll := rng.randf()
	var kind := "car"
	if on_road:
		# What's left on Bangkok's streets: taxis and tuk-tuks, minivans, pickups,
		# the red songthaews, and on the wide streets, the city buses.
		var wide: bool = w.roads.any(func(rd): return rd.rect.has_point(c) and mini(rd.rect.size.x, rd.rect.size.y) >= 10)
		for k in [["tuktuk", 0.12], ["taxi", 0.30], ["van", 0.42], ["pickup", 0.52], ["songthaew", 0.58], ["bus", 0.64 if wide else 0.58]]:
			if roll < k[1]:
				kind = k[0]
				break
	var length: int = VEHICLE_CELLS.get(kind, 2)
	var cells := []
	for i in length:
		cells.append(c + (Vector2i.RIGHT if horizontal else Vector2i.DOWN) * i)
	if kind == "tuktuk":
		cells = [c]
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
			else (BUS_COLORS[rng.randi() % BUS_COLORS.size()] if kind == "bus" else CAR_COLORS[rng.randi() % CAR_COLORS.size()])
	if kind == "songthaew":
		color = [Color("b8322a"), Color("2a5aa8")][rng.randi() % 2]
	elif kind == "van":
		color = [Color("e8e6e0"), Color("c8ccd0"), Color("e8e6e0")][rng.randi() % 3]
	w.street_props.append({kind = kind, horizontal = horizontal or kind == "tuktuk",
			pos = Vector2(c.x * World.TILE, (last.y + 1) * World.TILE), color = color, seed = rng.randi()})


# --- The end of the world ---------------------------------------------------
# Traces of the days it all went wrong: pile-ups where people tried to drive out,
# an army checkpoint that did not hold, bags dropped while running. Plus the
# small things every Bangkok soi has: spirit houses, noodle stalls, green bins.

static func _aftermath(w: World, rng: RandomNumberGenerator) -> void:
	var spawn := w.to_pos(w.spawn_cell)
	# Pile-ups near junctions: people tried to get out all at once.
	for it: Rect2i in w.intersections:
		if w.to_pos(it.position).distance_to(spawn) < 160.0 or rng.randf() < 0.35:
			continue
		var jw := mini(it.size.x, it.size.y)
		for k in rng.randi_range(2, 4):
			var arm: Vector2i = World.DIRS[rng.randi() % 4]
			var dist := rng.randi_range(jw + 1, jw + 7)
			var lane := rng.randi_range(0, jw - 2)
			var c := it.position + (arm * dist if arm.x + arm.y > 0 else arm * (dist - jw + 1))
			c += Vector2i(lane, 0) if arm.x == 0 else Vector2i(0, lane)
			_wreck(w, c, rng)
	# Wrecks strung along the avenues.
	for rd in w.roads:
		var r: Rect2i = rd.rect
		var length: int = r.size.x if rd.horizontal else r.size.y
		for k in length / 22:
			var along := rng.randi_range(0, length - 3)
			var rw: int = r.size.y if rd.horizontal else r.size.x
			var c := r.position + (Vector2i(along, rng.randi_range(0, rw - 1)) if rd.horizontal \
					else Vector2i(rng.randi_range(0, rw - 1), along))
			_wreck(w, c, rng)
	_checkpoint(w, rng, spawn)
	# Things along pavements and sois.
	for i in int(1600 * AREA):
		var c := Vector2i(rng.randi_range(1, World.W - 2), rng.randi_range(1, World.H - 2))
		var t := w.get_tile(c)
		var roll := rng.randf()
		var pos := w.to_pos(c) + Vector2(rng.randf_range(-4, 4), 5)
		if t in [World.SIDEWALK, World.SOI, World.ROAD] and roll < 0.12:
			_prop(w, "papers", pos, rng, true)
		elif t in [World.SIDEWALK, World.SOI] and roll < 0.16:
			_prop(w, "luggage", pos, rng, true)
		elif t in [World.SIDEWALK, World.SOI, World.ROAD] and roll < 0.18:
			_prop(w, "drag", pos, rng, true)
		elif t == World.SOI and roll < 0.24 and _fits(w, [c]):
			w.blocked[c] = true
			_prop(w, "debris", w.to_pos(c) + Vector2(0, 5), rng)
		elif t in [World.SOI, World.SIDEWALK] and roll < 0.3 and _fits(w, [c]) \
				and w.get_tile(c + Vector2i.UP) in [World.BUILDING, World.IWALL]:
			w.blocked[c] = true
			_prop(w, "spirit", w.to_pos(c) + Vector2(0, 5), rng)
		elif t == World.SIDEWALK and roll < 0.36 and _fits(w, [c]):
			w.blocked[c] = true
			_prop(w, "stall", w.to_pos(c) + Vector2(0, 5), rng)
		elif t in [World.SIDEWALK, World.SOI] and roll < 0.42 and _fits(w, [c]):
			_prop(w, "bin", w.to_pos(c) + Vector2(0, 5), rng)
	# Motorbikes parked nose-in along the shop fronts, as on every Bangkok street.
	for rec in w.buildings:
		if rec.kind not in ["shop", "store"]:
			continue
		var r: Rect2i = rec.rect
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, r.end.y)
			if rec.kind == "shop" and x == r.position.x and rng.randf() < 0.12 and _fits(w, [c]):
				w.blocked[c] = true
				_prop(w, "spirit", w.to_pos(c) + Vector2(0, 5), rng)
				continue
			# Motorbikes park at the kerb in front, nose to the road, never across the
			# shop front itself (that strip is for walking in and out).
			var kerb := c + Vector2i.DOWN
			if w.get_tile(c) == World.SIDEWALK and w.get_tile(kerb) == World.SIDEWALK and w.get_tile(kerb + Vector2i.DOWN) == World.ROAD \
					and not w.blocked.has(kerb) and not w.in_intersection(kerb + Vector2i.DOWN) and rng.randf() < 0.6:
				_park(w, {kind = "motorbike", pos = w.to_pos(kerb) + Vector2(rng.randf_range(-3, 3), 4), seed = rng.randi(),
						view = "front", dir = 1.0})
			# Facing a soi: across it, nose to the wall at the back of the next row
			# (not at its back door), leaving the middle of the soi to walk down.
			var wall := c + Vector2i.DOWN * 3
			if w.get_tile(c) == World.SOI and w.get_tile(wall - Vector2i.DOWN) == World.SOI \
					and w.get_tile(wall) in [World.BUILDING, World.IWALL] and not w.door_at.has(wall) \
					and not w.blocked.has(wall - Vector2i.DOWN) and rng.randf() < 0.55:
				_park(w, {kind = "motorbike", pos = w.to_pos(wall - Vector2i.DOWN) + Vector2(rng.randf_range(-3, 3), 2), seed = rng.randi(),
						view = "back", dir = 1.0})
	# Long-tail boats left in the canal, some half sunk.
	for cy in CANALS:
		for x in range(4, World.W - 4, 9):
			if rng.randf() < 0.5 and w.get_tile(Vector2i(x, cy + 1)) == World.WATER:
				_prop(w, "boat", w.to_pos(Vector2i(x, cy + 1)) + Vector2(0, 4), rng)


static func _prop(w: World, kind: String, pos: Vector2, rng: RandomNumberGenerator, flat := false) -> void:
	w.street_props.append({kind = kind, pos = pos, seed = rng.randi(), flat = flat})


## Free ground that will not wall anyone in: nothing solid next to it, and not
## in front of a door.
## Park a bike if it has room: bikes side by side in a row, none overlapping.
## (Only decides whether to keep one; draws no random numbers.)
static func _park(w: World, bike: Dictionary) -> void:
	if not _bike_near(w, bike.pos, bike.get("view", "side")):
		w.street_props.append(bike)


## How much ground a parked bike takes: long side-on, narrow end-on.
static func _bike_box(pos: Vector2, view: String) -> Rect2:
	var half := Vector2(17, 4) if view == "side" else Vector2(6, 8)
	return Rect2(pos - half, half * 2.0)


static func _bike_near(w: World, pos: Vector2, view := "side") -> bool:
	var box := _bike_box(pos, view)
	for p in w.street_props:
		if p.kind == "motorbike" and box.intersects(_bike_box(p.pos, p.get("view", "side")).grow(1.0)):
			return true
	return false


static func _fits(w: World, cells: Array, road_ok := false) -> bool:
	for cell: Vector2i in cells:
		var t := w.get_tile(cell)
		if w.blocked.has(cell) or w.in_intersection(cell) or t not in ([World.ROAD, World.SOI, World.SIDEWALK] if road_ok else [World.SOI, World.SIDEWALK]):
			return false
		for d in World.DIRS:
			var n: Vector2i = cell + d
			if cells.has(n):
				continue
			if w.blocked.has(n) or w.get_tile(n) == World.DOOR:
				return false
	return true


## A crashed car: slewed across the lane, burnt out, or on its roof.
static func _wreck(w: World, c: Vector2i, rng: RandomNumberGenerator) -> void:
	var horizontal := rng.randf() < 0.5
	var cells := [c, c + (Vector2i.RIGHT if horizontal else Vector2i.DOWN)]
	if not _fits(w, cells, true):
		return
	for cell in cells:
		if w.get_tile(cell) != World.ROAD:
			return
	for cell in cells:
		w.blocked[cell] = true
	var roll := rng.randf()
	var pose := "burnt" if roll < 0.3 else ("flipped" if roll < 0.45 else "crashed")
	var last: Vector2i = cells[-1]
	w.street_props.append({kind = "wreck", pos = Vector2(c.x * World.TILE, (last.y + 1) * World.TILE), seed = rng.randi(),
			pose = pose, angle = rng.randf_range(0.2, 0.5) * (1 if rng.randf() < 0.5 else -1), color = CAR_COLORS[rng.randi() % CAR_COLORS.size()],
			horizontal = horizontal})
	if rng.randf() < 0.5:
		_prop(w, "glass", w.to_pos(cells[0]) + Vector2(rng.randf_range(-6, 14), 6), rng, true)


## One junction where the army tried to hold the line: sandbags across the
## pavements and half the road, a barrier, a truck left behind. One lane stays open.
static func _checkpoint(w: World, rng: RandomNumberGenerator, spawn: Vector2) -> void:
	var options := w.intersections.filter(func(it): return w.to_pos(it.position).distance_to(spawn) > 400.0)
	if options.is_empty():
		return
	var it: Rect2i = options[rng.randi() % options.size()]
	# Across the road just south of the junction, leaving the far lane open.
	var y := it.end.y + 2
	if w.get_tile(Vector2i(it.position.x, y)) != World.ROAD:
		y = it.position.y - 3
	for x in range(it.position.x - 2, it.position.x + it.size.x - 2):
		var cell := Vector2i(x, y)
		if w.get_tile(cell) in [World.ROAD, World.SIDEWALK] and not w.blocked.has(cell):
			w.blocked[cell] = true
			w.street_props.append({kind = "sandbags", pos = w.to_pos(cell) + Vector2(0, 5), seed = rng.randi()})
	var bar := Vector2i(it.position.x + it.size.x - 2, y)
	if w.get_tile(bar) == World.ROAD and not w.blocked.has(bar):
		_prop(w, "barrier", w.to_pos(bar) + Vector2(0, 5), rng)
	var truck := [Vector2i(it.position.x + 1, y + 2), Vector2i(it.position.x + 2, y + 2), Vector2i(it.position.x + 3, y + 2)]
	if _fits(w, truck, true):
		for cell in truck:
			w.blocked[cell] = true
		w.street_props.append({kind = "army", pos = Vector2(truck[0].x * World.TILE, (y + 3) * World.TILE), seed = rng.randi()})
	w.checkpoint = it


## What each trade puts out on the pavement, so you can tell the shop from
## the street: [kind, where] with where 0 = by the left wall, 1 = middle,
## 2 = by the right wall (see DecorProp). Nothing out here blocks the way.
const FRONTS := {
	"ร้านตัดผม": [["plants", 0], ["lightbox", 2]], "ร้านเสริมสวย": [["lightbox", 0], ["plants", 2]],
	"ร้านขายยา": [["lightbox", 2]], "คลินิก": [["lightbox", 2], ["plants", 0]],
	"ซ่อมมอเตอร์ไซค์": [["tires", 0], ["bike", 1], ["oil", 1], ["flag", 2]],
	"ก๋วยเตี๋ยวเรือ": [["pot", 0], ["chairs", 1], ["menu", 2]], "โจ๊ก ข้าวต้ม": [["pot", 0], ["chairs", 1]],
	"ข้าวมันไก่": [["chairs", 1], ["menu", 2]], "อาหารตามสั่ง": [["chairs", 1], ["menu", 0]],
	"ส้มตำ ไก่ย่าง": [["grill", 0], ["chairs", 1], ["menu", 2]], "กาแฟโบราณ": [["chairs", 1], ["menu", 0]],
	"ร้านโทรศัพท์": [["flag", 0], ["lightbox", 2]], "ร้านวัสดุ": [["sacks", 0], ["pipes", 2]],
	"ขายส่ง": [["sacks", 0], ["boxes", 1], ["pipes", 2]], "นวดแผนไทย": [["lightbox", 0], ["shoes", 1], ["plants", 2]],
	"ผ้าไหม": [["mannequin", 0], ["mannequin", 2]], "ร้านทอง": [["plants", 2]], "โรงรับจำนำ": [["plants", 0]],
	"": [["plants", 0], ["shoes", 1]],
}


## Dress the pavement in front of every shop for its trade. Last in the
## build and from each building's own seed, so the rest of the city (and the
## saves that depend on it) come out exactly as before.
static func _shop_fronts(w: World) -> void:
	for rec in w.buildings:
		if rec.kind != "shop" or not rec.get("enter", false):
			continue
		var list: Array = FRONTS.get(rec.sign, [])
		var rng := RandomNumberGenerator.new()
		rng.seed = rec.seed * 17 + 5
		var r: Rect2i = rec.rect
		var y := r.end.y
		for e in list:
			if rec.sign == "" and rng.randf() < 0.5:
				continue  # (not every home has pots out)
			var x: int = [r.position.x + 1, r.position.x + r.size.x / 2, r.end.x - 2][e[1]]
			var c := Vector2i(x, y)
			if w.get_tile(c) not in [World.SIDEWALK, World.SOI] or w.blocked.has(c) or w.door_at.has(c):
				continue
			w.decor.append({kind = e[0], cell = c, seed = rng.randi(), building = rec, outside = true})


## The ways out of the zone: the avenue's end kept clear, a barrier across
## it with a sign saying where it goes. Last, so the rest of the city comes
## out the same with or without them.
static func _zone_exits(w: World) -> void:
	for e in w.exits:
		var r: Rect2i = e.rect
		for y in range(r.position.y - 1, r.end.y + 1):
			for x in range(r.position.x - 1, r.end.x + 1):
				w.blocked.erase(Vector2i(x, y))
		var keep := r.grow(2)
		w.street_props = w.street_props.filter(func(p): return not keep.has_point(w.to_cell(p.pos)) or p.kind == "pole")
		var to := Zones.name_of(e.to)
		var label: String = {east = "ไป%s →", west = "← ไป%s", north = "↑ ไป%s", south = "↓ ไป%s"}.get(e.edge, "ไป%s") % to
		w.street_props.append({kind = "zonesign", pos = w.to_pos(r.position + r.size / 2) + Vector2(0, 6), seed = 0, label = label})


static func _size_beds(w: World) -> void:
	# A bed is two cells long, a person's length: it takes the cell in front
	# of it (headboard against the wall), or else to its right or left, when
	# that is free floor off the walkway.
	# Otherwise it stays a single mattress. No random numbers (see _size_vehicles).
	# Clutter on the floor (a fan, a bucket) makes way; the stairs don't.
	var stairs := {}
	for d in w.decor:
		if d.kind == "stairs":
			stairs[d.cell] = true
	# The beds in each building, found once (not every building against every cupboard).
	var owner := {}
	for i in w.buildings.size():
		var r: Rect2i = w.buildings[i].rect
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				owner[Vector2i(x, y)] = i
	var beds_in := {}
	for f in w.containers:
		if f.kind == "bed" and not f.has("long") and not f.get("up", false) and owner.has(f.cell):
			if not beds_in.has(owner[f.cell]):
				beds_in[owner[f.cell]] = []
			beds_in[owner[f.cell]].append(f)
	for i in w.buildings.size():
		var rec: Dictionary = w.buildings[i]
		if not rec.has("keep_clear"):
			continue
		for f in beds_in.get(i, []):
			for side in [2, 1, -1]:
				var step := Vector2i.DOWN if side == 2 else Vector2i(side, 0)
				var c: Vector2i = f.cell + step
				if c.x in rec.keep_clear or w.get_tile(c) != World.FLOOR or w.blocked.has(c) or stairs.has(c) or stairs.has(c + Vector2i.DOWN):
					continue
				if w.get_tile(c + step) == World.DOOR or w.get_tile(c + Vector2i.DOWN) == World.DOOR:
					continue
				w.blocked[c] = true
				f.long = side
				w.decor = w.decor.filter(func(d): return d.cell != c or d.kind == "bulb")
				break


## Vehicles are drawn at StreetProp.VEHICLE_SCALE, bigger than the cells they
## were placed on. Block the extra road they cover. This draws no random
## numbers, so the rest of the city (and saved cities) come out as before;
## a cell that is not free is simply left, and the car overhangs it a little.
static func _size_vehicles(w: World) -> void:
	for p in w.street_props:
		var extra := []
		var base := Vector2i((p.pos / World.TILE).floor())
		match p.kind:
			"car", "taxi", "van", "pickup", "songthaew":
				if p.horizontal:
					extra = [Vector2i(base.x + 2, base.y - 1)]  # longer: one more cell ahead
				else:
					extra = [Vector2i(base.x, base.y - 3)]  # seen end-on it grows up the screen
			"tuktuk":
				extra = [Vector2i(base.x + 1, base.y - 1)]
			"wreck":
				extra = [Vector2i(base.x + 2, base.y - 1)] if p.horizontal else [Vector2i(base.x, base.y - 3)]
			"army":
				extra = [Vector2i(base.x + 3, base.y - 1), Vector2i(base.x + 4, base.y - 1)]
			"bus":
				extra = [Vector2i(base.x + 7, base.y - 1), Vector2i(base.x + 8, base.y - 1)] if p.horizontal \
						else [Vector2i(base.x, base.y - 8), Vector2i(base.x, base.y - 9)]
		for c in extra:
			if w.get_tile(c) in [World.ROAD, World.SOI] and not w.blocked.has(c) and not w.in_intersection(c) 					and not World.DIRS.any(func(d): return w.get_tile(c + d) == World.DOOR):
				w.blocked[c] = true
