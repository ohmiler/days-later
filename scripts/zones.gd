class_name Zones
## The city is split into zones, each its own map loaded on its own, joined by
## ways out at the edges (a checkpoint on an avenue, for now). A server runs
## one zone at a time: played with friends, the group travels together; run
## as separate servers (one per zone, see data/zones.cfg `port`), each
## survivor is handed over to the next zone's server on their own.

const DATA := "res://data/zones.cfg"  # (exports must include *.cfg)
const EXIT_DEPTH := 3  # cells in from the map edge that count as the way out

static var ORDER: Array = []  # ids in the order they're written (the first is where you start)
## id -> {name, size: Vector2i, port, exits: [{id, to, to_exit}]}
static var ZONES: Dictionary = _load()


static func _load() -> Dictionary:
	var cf := ConfigFile.new()
	var err := cf.load(DATA)
	if err != OK:
		push_error("Could not read %s (error %d)" % [DATA, err])
		return {}
	var out := {}
	ORDER = []
	for id in cf.get_sections():
		var z := {name = cf.get_value(id, "name", id), port = cf.get_value(id, "port", 0),
				exits = cf.get_value(id, "exits", []), todo = cf.get_value(id, "todo", false), plan = {}}
		var sz: Array = cf.get_value(id, "size", [320, 240])
		var plan_file: String = cf.get_value(id, "plan", "")
		if plan_file != "":
			z.plan = _load_plan(plan_file)
			sz = z.plan.get("size", sz)
		z.size = Vector2i(sz[0], sz[1])
		out[id] = z
		if not z.todo:
			ORDER.append(id)
	return out


## A hand-drawn zone's plan (data/zones/*.cfg, section [plan]) as a dictionary.
static func _load_plan(path: String) -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		push_error("Could not read zone plan %s" % path)
		return {}
	var out := {}
	for key in cf.get_section_keys("plan"):
		out[key] = cf.get_value("plan", key)
	return out


## Is there a zone there to go to (not one still to be made)?
static func open(id: String) -> bool:
	return ZONES.has(id) and not ZONES[id].todo


## A zone's ways out: [{id, edge, to, to_exit, rect}]. A plan says where
## they are; otherwise the edge's avenue across the middle.
static func exits_of(id: String) -> Array:
	var z := def(id)
	var out := []
	if not z.plan.is_empty():
		for e in z.plan.get("exits", []):
			var r: Array = e.rect
			out.append({id = e.id, edge = e.edge, to = e.to, to_exit = e.to_exit, rect = Rect2i(r[0], r[1], r[2], r[3])})
		return out
	for e in z.exits:
		out.append({id = e.id, edge = e.id, to = e.to, to_exit = e.to_exit, rect = exit_rect(e.id, z.size)})
	return out


static func first() -> String:
	return ORDER[0] if not ORDER.is_empty() else ""


static func def(id: String) -> Dictionary:
	return ZONES.get(id, ZONES.get(first(), {}))


static func name_of(id: String) -> String:
	return def(id).get("name", id)


## The cells of a way out, in a zone of `size`: the end of the avenue across
## the middle at that edge.
static func exit_rect(edge: String, size: Vector2i) -> Rect2i:
	var ys := CityGen.repeat(CityGen.YS, CityGen.SECTION.y, size.y)
	var xs := CityGen.repeat(CityGen.XS, CityGen.SECTION.x, size.x)
	var y: int = ys[ys.size() / 2]
	var x: int = xs[xs.size() / 2]
	match edge:
		"east":
			return Rect2i(size.x - EXIT_DEPTH, y, EXIT_DEPTH, CityGen.ROAD_W)
		"west":
			return Rect2i(0, y, EXIT_DEPTH, CityGen.ROAD_W)
		"north":
			return Rect2i(x, 0, CityGen.ROAD_W, EXIT_DEPTH)
		_:
			return Rect2i(x, size.y - EXIT_DEPTH, CityGen.ROAD_W, EXIT_DEPTH)


## Where someone coming in by a way out appears: a few steps in from it.
static func arrival(e: Dictionary) -> Vector2i:
	var r: Rect2i = e.rect
	var edge: String = e.edge
	var mid := r.position + r.size / 2
	match edge:
		"east":
			return Vector2i(r.position.x - 4, mid.y)
		"west":
			return Vector2i(r.end.x + 3, mid.y)
		"north":
			return Vector2i(mid.x, r.end.y + 3)
		_:
			return Vector2i(mid.x, r.position.y - 4)
