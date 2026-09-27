class_name BigPlans
## The big buildings: a hospital, a block of flats, an office block, a mall,
## a covered market. Their plans are made to measure for each plot, a floor at
## a time, in the letters the hand-drawn shophouse plans use
## (data/prefabs/README.txt), so the same code builds them (CityGen._add_big).
##
## A hospital, the flats and the offices are built the Bangkok way: a corridor
## down the middle, rooms either side, stairs at both ends (and a lift that
## stopped with the power). The mall is shop units either side of a hall with
## the escalators in the middle; the market is a shed of stalls, open along
## its front and back.

## kind -> its size (cells, walls included), how many storeys, its sign.
const KINDS := {
	hospital = {w = [30, 44], d = [17, 21], storeys = [4, 5], name = "โรงพยาบาล"},
	flats = {w = [24, 34], d = [15, 17], storeys = [5, 7], name = "แฟลต"},
	office = {w = [22, 34], d = [16, 19], storeys = [5, 7], name = "อาคารสำนักงาน"},
	mall = {w = [20, 56], d = [24, 34], storeys = [3, 3], name = "ห้างสรรพสินค้า"},
	market = {w = [16, 28], d = [12, 18], storeys = [1, 1], name = "ตลาดสด"},
}
## How wide the rooms off a corridor are (inside), by kind.
const ROOM_W := {hospital = [5, 8], flats = [5, 6], office = [7, 11]}
## What each kind of room holds when searched (Items tables).
const TABLES := {ward = "med", exam = "med", pharmacy = "med", nurse = "med", store = "med", toilet = "home",
		office = "home", plant = "tools", lobby = "med", unit = "home", minimart = "store", desks = "home",
		pantry = "food", meeting = "home", supermarket = "store", foodcourt = "food"}


## A plan for a `kind` building `size` cells big with `storeys` floors, in the
## shape CityGen reads plans: {rows, storeys (the rows of each floor up),
## rooms ([storey, Rect2i inside it, Items table]), width, stretch, widen, upper}.
static func make(kind: String, size: Vector2i, storeys: int, rng: RandomNumberGenerator) -> Dictionary:
	var out := {rows = [], storeys = [], rooms = [], width = size.x, widen = -1, upper = [], kinds = [kind], signs = []}
	var floors: Array
	match kind:
		"mall":
			floors = _mall(size, storeys, rng, out.rooms)
		"market":
			floors = _market(size, rng, out.rooms)
		_:
			floors = _corridor(kind, size, storeys, rng, out.rooms)
	for rm in out.rooms:
		rm[2] = TABLES.get(rm[2], rm[2])  # (a room's use -> what it holds)
	out.rows = floors[0]
	out.storeys = floors.slice(1)
	out.stretch = []
	for i in size.y:
		out.stretch.append(false)
	return out


# --- A corridor down the middle -------------------------------------------------

static func _corridor(kind: String, size: Vector2i, storeys: int, rng: RandomNumberGenerator, rooms: Array) -> Array:
	var W := size.x
	var D := size.y
	var back := (D - 6) / 2  # how deep the rooms behind the corridor are
	var cy := back + 2  # the corridor: rows cy and cy + 1
	var fy := cy + 3  # the front rooms' first row
	var mid := W / 2
	# The walls between rooms: the frame of the building, the same all the way up.
	var back_rooms := _split(1, W - 2, ROOM_W[kind], rng)
	var front_rooms := _split(1, W - 2, ROOM_W[kind], rng)
	# The front rooms the lobby takes on the ground floor (the middle ones).
	var lobby := Rect2i()
	for rm in front_rooms:
		if rm[1] >= mid - 4 and rm[0] <= mid + 3:
			var r := Rect2i(rm[0], fy, rm[1] - rm[0] + 1, D - 1 - fy)
			lobby = r if lobby.size == Vector2i.ZERO else lobby.merge(r)
	var floors := []
	for f in storeys:
		var g := _grid(size)
		_box(g, Rect2i(1, cy, W - 2, 2), ".")
		var list := []  # [inside, the side its door is on, role]
		for i in back_rooms.size():
			var rm: Array = back_rooms[i]
			list.append([Rect2i(rm[0], 1, rm[1] - rm[0] + 1, back), Vector2i.DOWN, _role(kind, f, -1, i, rm, mid, rng)])
		for i in front_rooms.size():
			var rm: Array = front_rooms[i]
			var r := Rect2i(rm[0], fy, rm[1] - rm[0] + 1, D - 1 - fy)
			if f == 0 and lobby.encloses(r):
				continue
			list.append([r, Vector2i.UP, _role(kind, f, 1, i, rm, mid, rng)])
		for e in list:
			var r: Rect2i = e[0]
			_box(g, r, ".")
			# The way in from the corridor, not right at a corner.
			var dx := rng.randi_range(r.position.x, r.end.x - 1)
			var door := Vector2i(dx, cy - 1 if e[1] == Vector2i.DOWN else cy + 2)
			_put(g, door, "d")
			_furnish(g, r, e[1], e[2], rng)
			rooms.append([f, r, e[2]])
			if f == 0 and e[1] == Vector2i.DOWN and rng.randf() < 0.4:
				_put(g, Vector2i(r.position.x + r.size.x / 2, 0), "w")  # a window out the back
			if f == 0 and e[1] == Vector2i.UP:
				_put(g, Vector2i(r.position.x + r.size.x / 2, D - 1), "w")
		if f == 0:
			_box(g, lobby, ".")
			_box(g, Rect2i(lobby.position.x, cy + 2, lobby.size.x, 1), ".")  # open onto the corridor
			for x in range(lobby.position.x, lobby.end.x):
				_put(g, Vector2i(x, D - 1), "D" if absi(x - mid) <= 1 else "w")
			_furnish_lobby(g, lobby, kind, mid)
			rooms.append([0, lobby, "lobby" if kind == "hospital" else "unit"])
			# Fire doors out at both ends of the corridor.
			_put(g, Vector2i(0, cy + 1), "D")
			_put(g, Vector2i(W - 1, cy + 1), "D")
		# Stairs at both ends, the lift in the middle (dead, doors shut).
		_put(g, Vector2i(1, cy), "S")
		_put(g, Vector2i(W - 2, cy), "S")
		if _ch(g, Vector2i(mid, cy - 1)) == "W" and _ch(g, Vector2i(mid - 1, cy - 1)) != "d" and _ch(g, Vector2i(mid + 1, cy - 1)) != "d":
			_put(g, Vector2i(mid, cy - 1), "Y")
		floors.append(_rows(g))
	return floors


## Split columns `from`..`to` (inside, inclusive) into rooms `widths` wide
## with a wall between each: [[first, last], ...].
static func _split(from: int, to: int, widths: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var x := from
	while x <= to:
		var wd := rng.randi_range(widths[0], widths[1])
		if to - (x + wd) < widths[0] + 1:
			wd = to - x + 1  # the last one takes what's left
		out.append([x, x + wd - 1])
		x += wd + 1
	return out


## What a room off the corridor is for.
static func _role(kind: String, f: int, side: int, i: int, rm: Array, mid: int, rng: RandomNumberGenerator) -> String:
	var near_mid: bool = rm[0] <= mid + 8 and rm[1] >= mid - 8
	match kind:
		"hospital":
			if f == 0:
				if side < 0:
					return "plant" if i == 0 else ["exam", "store", "toilet", "office", "exam"][i % 5]
				return "pharmacy" if near_mid else "exam"
			if side > 0 and near_mid:
				return "nurse"
			return ["ward", "ward", "toilet", "ward", "store"][i % 5] if side < 0 else "ward"
		"flats":
			if f == 0 and side < 0 and i == 0:
				return "plant"
			if f == 0 and side > 0 and near_mid and rng.randf() < 0.6:
				return "minimart"
			return "unit"
		_:
			if f == 0 and side < 0 and i == 0:
				return "plant"
			if side < 0:
				return ["pantry", "toilet", "meeting", "desks"][i % 4]
			return "desks"


# --- Furnishing ---------------------------------------------------------------
# A room is filled in terms of (along, deep): `deep` 0 is the wall across from
# its door; the row by the door is always left clear, so everything can be
# walked up to.

static func _at(r: Rect2i, side: Vector2i, along: int, deep: int) -> Vector2i:
	match side:
		Vector2i.DOWN:
			return Vector2i(r.position.x + along, r.position.y + deep)
		Vector2i.UP:
			return Vector2i(r.position.x + along, r.end.y - 1 - deep)
		Vector2i.RIGHT:
			return Vector2i(r.position.x + deep, r.position.y + along)
	return Vector2i(r.end.x - 1 - deep, r.position.y + along)


## (how long a room is along its far wall, how deep it is from there to its door)
static func _span(r: Rect2i, side: Vector2i) -> Vector2i:
	return r.size if side.y != 0 else Vector2i(r.size.y, r.size.x)


static func _furnish(g: Array, r: Rect2i, side: Vector2i, role: String, rng: RandomNumberGenerator) -> void:
	var s := _span(r, side)
	var n := s.x  # along
	var last := s.y - 2  # the deepest row that may hold anything (the one by the door stays clear)
	var put := func(a: int, k: int, ch: String) -> void:
		if a >= 0 and a < n and k >= 0 and k <= last:
			_put(g, _at(r, side, a, k), ch)
	match role:
		"ward":
			for a in range(0, n, 2):
				put.call(a, 0, "b")
				put.call(a, 1, "b")
				if a + 1 < n:
					put.call(a + 1, 0, "C" if rng.randf() < 0.7 else "c")
			if last >= 3:
				put.call(n - 1, last, "N" if rng.randf() < 0.5 else "c")
		"exam":
			put.call(0, 0, "V")
			put.call(1, 0, "C")
			put.call(n - 1, 0, "c")
			put.call(n - 2, 0, "t")
			put.call(n - 1, 2, "K")
		"pharmacy":
			for a in n:
				put.call(a, 0, "s")
			for a in n - 2:
				put.call(a, 2, "g")
			put.call(n - 1, last, "N")
		"nurse":
			put.call(0, 0, "c")
			put.call(1, 0, "f")
			put.call(n - 1, 0, "c")
			for a in n - 2:
				put.call(a, 2, "k")
		"store":
			for a in n:
				put.call(a, 0, "s" if a % 2 == 0 else "x")
			put.call(0, 2, "o")
		"toilet":
			for a in range(0, n - 1, 2):
				put.call(a, 0, "q")
			put.call(n - 1, 0, "T")
			put.call(n - 1, 1, "K")
		"office":
			put.call(0, 0, "c")
			put.call(n - 1, 0, "c")
			put.call(n / 2, 1, "t")
			put.call(n / 2 - 1, 0, "v" if rng.randf() < 0.3 else "n")
		"plant":
			put.call(0, 0, "Q")
			put.call(2, 0, "x")
			put.call(3, 0, "x")
			put.call(n - 1, 0, "o")
			put.call(n - 1, 1, "i" if rng.randf() < 0.3 else "o")
		"unit":
			put.call(0, 0, "b")
			put.call(0, 1, "b")
			put.call(1, 0, "c")
			put.call(n - 2, 0, "v")
			put.call(n - 1, 0, "n")
			put.call(n - 1, 1, "f")
			put.call(n - 1, 2, "K")
			put.call(0, 2, "T")
			put.call(0, 3, "q")
			if rng.randf() < 0.5:
				put.call(2, 2, "m" if rng.randf() < 0.3 else "O")
		"minimart":
			for a in n:
				put.call(a, 0, "s")
			put.call(0, 2, "f")
			put.call(0, 3, "f")
			for a in range(2, n - 1):
				if last >= 3:
					put.call(a, 2, "s")
			put.call(n - 1, last, "k")
		"desks":
			for a in range(0, n, 2):
				put.call(a, 0, "c")
			for k in [2, 4]:
				if k <= last - 1:
					for a in range(1, n - 1):
						if a % 3 != 0:
							put.call(a, k, "t")
		"pantry":
			put.call(0, 0, "f")
			put.call(1, 0, "K")
			put.call(2, 0, "T")
			put.call(n - 1, 0, "k")
			put.call(n / 2, 2, "t")
		"meeting":
			put.call(n / 2, 0, "v")
			for a in range(1, n - 1):
				put.call(a, 2, "t")


static func _furnish_lobby(g: Array, r: Rect2i, kind: String, mid: int) -> void:
	# Benches either side of the way through from the doors to the corridor.
	for y in range(r.position.y + 1, r.end.y - 1, 2):
		for x in range(r.position.x + 1, r.end.x - 1):
			if absi(x - mid) > 2 and x != r.end.x - 2:
				_put(g, Vector2i(x, y), "z" if kind == "hospital" else ("O" if (x + y) % 5 == 0 else "."))
	# The counter along one side, the Buddha high on the wall, plants by the doors.
	for y in range(r.position.y, mini(r.position.y + 3, r.end.y - 1)):
		_put(g, Vector2i(r.end.x - 1, y), "k")
	_put(g, Vector2i(r.position.x, r.position.y), "I")
	_put(g, Vector2i(r.position.x, r.end.y - 1), "P")
	_put(g, Vector2i(r.end.x - 1, r.end.y - 1), "P")
	if kind == "hospital":
		_put(g, Vector2i(r.position.x, r.end.y - 2), "N")


# --- The mall -------------------------------------------------------------------

## Shop units down both sides of a hall, the escalators in the middle; the
## supermarket takes one side of the ground floor, the food court the top.
static func _mall(size: Vector2i, storeys: int, rng: RandomNumberGenerator, rooms: Array) -> Array:
	var W := size.x
	var D := size.y
	var hall := clampi(W / 4, 6, 12)
	var hx := (W - hall) / 2  # the hall's first column
	var mid := W / 2
	var sides := [Rect2i(1, 1, hx - 2, D - 2), Rect2i(hx + hall + 1, 1, W - 2 - (hx + hall), D - 2)]
	var cuts := []
	for s in sides:
		cuts.append(_split(1, D - 2, [5, 7], rng))
	var floors := []
	for f in storeys:
		var g := _grid(size)
		_box(g, Rect2i(hx, 1, hall, D - 2), ".")
		for si in 2:
			var s: Rect2i = sides[si]
			if s.size.x < 3:
				continue
			var toward := Vector2i.RIGHT if si == 0 else Vector2i.LEFT  # the hall is this way from the units
			var door_x := hx - 1 if si == 0 else hx + hall
			if f == 0 and si == 0:
				# The supermarket: the whole side, open to the hall.
				_box(g, s, ".")
				for y in range(2, D - 2, 3):
					_put(g, Vector2i(door_x, y), "d")
				for y in range(2, D - 3, 3):
					for x in range(s.position.x + 1, s.end.x - 1):
						_put(g, Vector2i(x, y), "s")
				for y in range(1, D - 2):
					_put(g, Vector2i(s.position.x, y), "f" if y % 2 == 0 else ".")
				rooms.append([f, s, "supermarket"])
				continue
			for u in cuts[si]:
				var r := Rect2i(s.position.x, u[0], s.size.x, u[1] - u[0] + 1)
				_box(g, r, ".")
				_put(g, Vector2i(door_x, rng.randi_range(r.position.y, r.end.y - 1)), "d")
				var role := _shop_role(f, storeys, rng)
				_furnish_shop(g, r, toward, role, rng)
				rooms.append([f, r, role])
		if f == storeys - 1:
			# The food court: tables and stools down the hall.
			for y in range(3, D - 3, 3):
				for x in [hx + 1, hx + hall - 2]:
					_put(g, Vector2i(x, y), "r")
		else:
			for y in range(4, D - 4, 6):
				_put(g, Vector2i(hx + 1, y), "z")  # (a cell in from the shop fronts: never across a doorway)
				_put(g, Vector2i(hx + hall - 2, y), "P")
		if f == 0:
			for x in range(hx, hx + hall):
				_put(g, Vector2i(x, D - 1), "D" if absi(x - mid) <= 1 else "w")
			_put(g, Vector2i(mid, 0), "B")
		# The escalators (stopped: stairs now), in the middle of the hall.
		_put(g, Vector2i(mid - 1, D / 2), "S")
		_put(g, Vector2i(mid + 1, D / 2), "S")
		floors.append(_rows(g))
	return floors


static func _shop_role(f: int, storeys: int, rng: RandomNumberGenerator) -> String:
	if f == storeys - 1:
		return "food"
	var list := ["clothes", "clothes", "phone", "valuables", "med", "barber", "tools", "food"] if f == 0 \
			else ["clothes", "clothes", "phone", "phone", "barber", "tools", "clothes", "med"]
	return list[rng.randi() % list.size()]


## A shop unit in the mall, for what it sells (an Items table).
static func _furnish_shop(g: Array, r: Rect2i, side: Vector2i, role: String, rng: RandomNumberGenerator) -> void:
	var s := _span(r, side)
	var n := s.x
	var last := s.y - 2
	var put := func(a: int, k: int, ch: String) -> void:
		if a >= 0 and a < n and k >= 0 and k <= last:
			_put(g, _at(r, side, a, k), ch)
	match role:
		"clothes":
			for a in n:
				put.call(a, 0, "s")
			put.call(1, 3, "E")
			put.call(n - 2, 3, "E")
			put.call(n - 1, last, "k")
		"phone", "valuables":
			for a in n:
				put.call(a, 0, "g" if a % 2 == 0 else "s")
			for a in range(1, n - 1):
				put.call(a, 3, "g")
			if role == "valuables":
				put.call(0, 2, "Z")
		"med":
			for a in n:
				put.call(a, 0, "s")
			for a in range(0, n - 1):
				put.call(a, 2, "g")
		"barber":
			for a in range(0, n, 2):
				put.call(a, 0, "M")
				put.call(a, 1, "A")
			put.call(n - 1, 0, "u")
		"tools":
			put.call(0, 0, "X")
			for a in range(1, n):
				put.call(a, 0, "s" if a % 2 == 0 else "x")
			put.call(n - 1, 2, "i")
		"food":
			for a in n:
				put.call(a, 0, "k" if a % 3 != 1 else "f")
			put.call(1, 2, "G")
			put.call(n - 2, 1, "p")
			put.call(n / 2, 3, "r")


# --- The market -----------------------------------------------------------------

## One floor under a tin roof, open along the front and back between pillars:
## rows of stalls back to back, aisles between.
static func _market(size: Vector2i, rng: RandomNumberGenerator, rooms: Array) -> Array:
	var W := size.x
	var D := size.y
	var g := _grid(size)
	_box(g, Rect2i(1, 1, W - 2, D - 2), ".")
	for x in range(1, W - 1):
		if x % 4 != 0:
			_put(g, Vector2i(x, 0), ".")
			_put(g, Vector2i(x, D - 1), ".")
	_put(g, Vector2i(0, D / 2), "D")
	_put(g, Vector2i(W - 1, D / 2), "D")
	var y := 3
	var row := 0
	while y + 1 < D - 3:
		var table: String = "food" if row % 3 != 2 else ["clothes", "tools", "home"][rng.randi() % 3]
		for x in range(2, W - 2):
			if (x - 2) % 6 == 5:
				continue  # a way through
			for yy in [y, y + 1]:
				var roll := rng.randf()
				_put(g, Vector2i(x, yy), "k" if roll < 0.45 else ("t" if roll < 0.7 else ("y" if roll < 0.82 else ("o" if roll < 0.92 else "p"))))
		rooms.append([0, Rect2i(2, y, W - 4, 2), table])
		y += 5
		row += 1
	_put(g, Vector2i(1, 1), "h")  # the market's spirit house
	_put(g, Vector2i(W - 2, 1), "T")
	return [_rows(g)]


# --- The grid ---------------------------------------------------------------------

static func _grid(size: Vector2i) -> Array:
	var g := []
	for y in size.y:
		var row := []
		row.resize(size.x)
		row.fill("W")
		g.append(row)
	return g


static func _box(g: Array, r: Rect2i, ch: String) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_put(g, Vector2i(x, y), ch)


static func _put(g: Array, c: Vector2i, ch: String) -> void:
	if c.y >= 0 and c.y < g.size() and c.x >= 0 and c.x < g[c.y].size():
		g[c.y][c.x] = ch


static func _ch(g: Array, c: Vector2i) -> String:
	return g[c.y][c.x] if c.y >= 0 and c.y < g.size() and c.x >= 0 and c.x < g[c.y].size() else ""


static func _rows(g: Array) -> Array:
	return g.map(func(row): return "".join(row))
