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
		var sz: Array = cf.get_value(id, "size", [320, 240])
		out[id] = {name = cf.get_value(id, "name", id), size = Vector2i(sz[0], sz[1]),
				port = cf.get_value(id, "port", 0), exits = cf.get_value(id, "exits", [])}
		ORDER.append(id)
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
static func arrival(edge: String, size: Vector2i) -> Vector2i:
	var r := exit_rect(edge, size)
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
