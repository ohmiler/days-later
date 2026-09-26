class_name World
extends Node2D
## Tile grid, collision, pathfinding and ground drawing. The layout comes
## from CityGen; buildings, trees, poles and cars are separate y-sorted nodes
## so characters can walk behind them.

const TILE := 16
## The map's size in cells (about a metre each): the zone's (see Zones). One
## zone is loaded at a time, so this belongs to the class.
static var W := 320
static var H := 240
var zone := ""  # which zone this is (see Zones)
var exits: Array = []  # ways out to other zones: [{id, to, to_exit, rect}]
const CHUNK := 16
const BTS_H := 64.0  # how high the skytrain deck floats above the road
const DOOR_HP := 60.0
const WINDOW_HP := 15.0  # glass: one good hit
const SHUTTER_HP := 150.0  # a rolling steel shutter, per section
const WINDOW_SLOW := 0.35  # climbing through a smashed window
const BOARD_HP := 60.0  # each board nailed across a door
const MAX_BOARDS := 3
## Traps players set down from their bag (F). You walk over them; zombies
## that do get hurt. The key matches the trap item's id in Items.
const BUILDS := {
	"wire": {name = "ลวดหนาม", hp = 60.0, solid = false},
	"spikes": {name = "กับดักตะปู", hp = 5.0, solid = false},
}
const WIRE_SLOW := 0.4
enum { GRASS, DIRT, WATER, TREE, WALL, ROAD, SIDEWALK, SOI, BUILDING, PLAZA, FLOOR, IWALL, DOOR }
const COLORS := {
	GRASS: Color("4a5733"),
	DIRT: Color("6a5a43"),
	WATER: Color("37514c"),  # murky khlong green
	TREE: Color("3f5431"),
	WALL: Color("e2dccc"),
	ROAD: Color("3a3b3c"),
	SIDEWALK: Color("8e8a82"),
	SOI: Color("6b6862"),
	BUILDING: Color("4a4640"),
	PLAZA: Color("aaa293"),
	FLOOR: Color("a89a82"),  # terrazzo inside shops and homes
	IWALL: Color("3a3632"),  # a wall seen from above, once the roof is lifted off
	DOOR: Color("a89a82"),
}

var tiles := PackedInt32Array()
var blocked := {}  # cells blocked by props (cars, carts, pillars)
var wall_hp := {}
var wood := 10
var is_night := false
var astar := AStarGrid2D.new()
var tint := FastNoiseLite.new()  # large soft colour patches on the ground
var prop_parent: Node  # y-sorted node that props are added to
var props := {}  # cell -> TreeProp
var building_nodes: Array = []
var building_at := {}  # cell -> BuildingProp, for every cell of every footprint
var containers: Array = []  # {id, kind, cell, table}, filled by CityGen
var container_nodes: Array = []  # FurnitureProp, indexed by container id
var doors: Array = []  # {id, cell, closed, hp, boards, broken}, filled by CityGen
var decor: Array = []  # {kind, cell, seed, building}, filled by CityGen
var stairs := {}  # cell -> true: stairwells up to the roof (by way of the floor upstairs, if there is one)
var upper := {}  # cell -> FLOOR or IWALL: the floor upstairs in shophouses that have one (see CityGen._build_upper)
var upper_blocked := {}  # cells upstairs taken by beds and cupboards
var door_at := {}  # cell -> door id
var door_nodes: Array = []
var overhead: Overhead

# Layout records filled in by CityGen.
var buildings: Array = []
var street_props: Array = []
var roads: Array = []  # {rect: Rect2i, horizontal: bool}
var intersections: Array = []  # Rect2i
var wires: Array = []  # [from, to] pole tops
var light_spots: Array = []  # [position, radius]: where street lamps and lit rooms light up the night (see is_lit)
var checkpoint := Rect2i()  # the junction the army held
var city_seed := 0  # the seed this city was built from
var vehicles: Array = []  # bikes you can ride (see Vehicles)
var things: Array = []  # {id, kind, cell, state}: taps, radios, vending machines (see Things)
var thing_nodes: Array = []
var bts_row := -1
var bts_path := PackedVector2Array()  # a drawn zone's skytrain: the line it follows, in pixels (see CityGen._skytrain_plan)
var bts_station := Vector2(-1, -1)  # ...and the rows (pixels, from..to) its station spans
var circle := {}  # a drawn zone's roundabout: {at (cell), r, island}
var medians: Array = []  # raised islands down the middle of wide streets (Rect2i)
var blocks: Array = []  # a drawn zone's blocks: [{rect, use, name}]
var spawn_cell := Vector2i(W / 2, H / 2)

var chunks := {}


## Build zone `zone_id` (see Zones) from its seed. "backdrop": a small town
## for behind the title menu.
func generate(seed_val: int, zone_id := "") -> void:
	zone = Zones.first() if zone_id == "" else zone_id
	var size: Vector2i = CityGen.SECTION if zone == "backdrop" else Zones.def(zone).size
	W = size.x
	H = size.y
	exits = [] if zone == "backdrop" else Zones.exits_of(zone)
	city_seed = seed_val
	tint.seed = seed_val + 1
	tint.frequency = 0.04
	tiles.resize(W * H)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	CityGen.build(self, rng)
	Vehicles.setup(self)

	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE, TILE) / 2
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in H:
		for x in W:
			astar.set_point_solid(Vector2i(x, y), is_solid(Vector2i(x, y)))

	# Ground is split into chunks so only what is on screen gets drawn.
	for cy in ceili(float(H) / CHUNK):
		for cx in ceili(float(W) / CHUNK):
			var n := Node2D.new()
			n.draw.connect(_draw_chunk.bind(n, Rect2i(cx * CHUNK, cy * CHUNK, CHUNK, CHUNK)))
			add_child(n)
			chunks[Vector2i(cx, cy)] = n
	var marks := Node2D.new()
	marks.draw.connect(_draw_markings.bind(marks))
	add_child(marks)
	_spawn_props()


func _spawn_props() -> void:
	for y in H:
		for x in W:
			if tiles[y * W + x] == TREE:
				_add_tree(Vector2i(x, y))
	for rec in buildings:
		var b := BuildingProp.new()
		b.setup(rec)
		b.z_index = 1
		_stream(b, b.position)
		building_nodes.append(b)
		var r: Rect2i = rec.rect
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				building_at[Vector2i(x, y)] = b
	for d in doors:
		door_at[d.cell] = d.id
		if d.broken:
			d.closed = false
		var n := DoorProp.new()
		n.door = d
		# A hair below the building's front wall so it draws on top of the facade.
		n.position = Vector2(d.cell.x * TILE, (d.cell.y + 1) * TILE + 0.2)
		if not World.BUILDS.has(d.kind):
			# Drawn at the old height, stretched to the storey: a door a person walks through upright.
			n.scale = Vector2(1, DoorProp.DOOR_STRETCH if d.kind in ["door", "shutter"] else DoorProp.WINDOW_STRETCH)
		n.z_index = 1
		_stream(n, n.position)
		door_nodes.append(n)
		astar.set_point_solid(d.cell, d.closed)
	var bnode := {}
	for b: BuildingProp in building_nodes:
		bnode[b.data] = b
	for i in decor.size():
		decor[i].id = i  # (what you sit on is known by this)
	for rec in decor:
		var dp := DecorProp.new()
		dp.data = rec
		dp.position = to_pos(rec.cell) + Vector2(0, TILE * 0.45)
		var flat: bool = rec.kind in ["oil", "litter", "mattress", "toilet", "shoes"]
		if rec.get("outside", false):
			dp.position.y = to_pos(rec.cell).y  # (out on the pavement: stands a little further back, by the wall)
		dp.z_index = 0 if flat else (3 if rec.kind == "bulb" else 1)
		if rec.get("up", false):
			_upstairs(dp, bnode.get(rec.building))
		_stream(dp, dp.position)
		var b: BuildingProp = bnode.get(rec.building)
		if rec.kind == "bulb":
			# The bulb hangs above everyone, so only show it with the roof lifted;
			# its light shows from outside too, like a lit window.
			dp.visible = false
			if b:
				b.interior.append(dp)
			var light := PointLight2D.new()
			light.texture = StreetProp._lamp_texture()
			light.texture_scale = 0.9
			light.color = Color("ffcf80")
			light.energy = 0.7
			light.position = dp.position
			light.visible = false
			light.add_to_group("street_lights")
			_stream(light, light.position)
			light_spots.append([dp.position, BULB_LIGHT])
	for rec in containers:
		var f := FurnitureProp.new()
		f.data = rec
		f.position = to_pos(rec.cell) + Vector2(0, TILE * 0.45)
		if rec.get("long", 0) == 2:
			f.position.y += TILE  # a bed down the room: sorts by its foot end
		f.z_index = 1
		if rec.get("up", false):
			_upstairs(f, building_at.get(rec.cell))
		_stream(f, f.position)
		container_nodes.append(f)
	for b: BuildingProp in building_nodes:
		if b.data.get("upper", false):
			var n := Node2D.new()
			n.draw.connect(_draw_upper.bind(n, b.data))
			_upstairs(n, b)
			n.z_index = 2
			_stream(n, b.position)
	for th in things:
		var tp := ThingProp.new()
		tp.thing = th
		tp.position = to_pos(th.cell) + Vector2(0, TILE * 0.45)
		tp.z_index = 1
		_stream(tp, tp.position)
		thing_nodes.append(tp)
	for i in street_props.size():
		street_props[i].id = i  # (a car you stand on is known by this)
	for rec in street_props:
		if rec.kind == "pole" and rec.get("lamp", Vector2.ZERO) != Vector2.ZERO:
			light_spots.append([rec.pos + Vector2(rec.lamp.x, 0), LAMP_LIGHT])  # (the pool it throws on the street below)
		var p := StreetProp.new()
		p.data = rec
		p.position = rec.pos
		p.z_index = 0 if rec.get("flat", false) else 1  # litter lies under everyone
		if rec.kind in StreetProp.VEHICLES:
			p.scale = Vector2.ONE * StreetProp.VEHICLE_SCALE  # vehicles the size of vehicles
		if rec.has("vehicle"):
			_own(p)  # (bikes get ridden about: always in the scene)
		else:
			_stream(p, p.position)
		if rec.has("vehicle"):
			vehicles[rec.vehicle].node = p
	overhead = Overhead.new()
	overhead.world = self
	overhead.z_index = 4
	_own(overhead)


## Something that belongs upstairs: hidden until someone local goes up there,
## and drawn above the ground floor's things when they do.
func _upstairs(n: Node2D, b: BuildingProp) -> void:
	n.visible = false
	n.z_index = 2  # (with the people up there, sorted by their feet)
	if b:
		b.upstairs.append(n)


## The floor upstairs of one building, a storey up: where you stand when you're
## up there (the node sits at the top of the map so it sorts behind everyone).
## Its front is the ground floor's front wall, seen from above.
func _draw_upper(node: Node2D, rec: Dictionary) -> void:
	var mc := MeshCanvas.new()
	var r: Rect2i = rec.rect
	var lift := BuildingProp.GROUND_H
	var col: Color = rec.color
	mc.draw_rect(Rect2(r.position.x * TILE, r.end.y * TILE - lift, r.size.x * TILE, lift), col.darkened(0.2))
	mc.draw_rect(Rect2(r.position.x * TILE, r.end.y * TILE - lift, r.size.x * TILE, 2), col.lightened(0.1))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var t: int = upper.get(c, IWALL)
			var cr := Rect2(x * TILE, y * TILE - lift, TILE, TILE)
			if t == FLOOR:
				# Floorboards up here, not terrazzo.
				var wood := Color("9a7a58").lightened((hash01(x, y, 50) - 0.5) * 0.08)
				mc.draw_rect(cr, wood)
				for i in 3:
					mc.draw_line(cr.position + Vector2(0, 4 + i * 5), cr.position + Vector2(TILE, 4 + i * 5), wood.darkened(0.15), 0.4)
			else:
				mc.draw_rect(cr, COLORS[IWALL])
				for d in DIRS:
					if upper.get(c + d, IWALL) == FLOOR:
						mc.draw_rect(_edge(cr, d, 3), Color("6e665c"))
				# Windows in the front and back walls (not at the corners: the party walls).
				if (y == r.position.y or y == r.end.y - 1) and x > r.position.x and x < r.end.x - 1 and (x - r.position.x) % 2 == 1:
					mc.draw_rect(Rect2(cr.position + Vector2(2, 5), Vector2(TILE - 4, 6)), Color("8ab0c0"))
					mc.draw_line(cr.position + Vector2(TILE / 2.0, 5), cr.position + Vector2(TILE / 2.0, 11), Color("4a4640"), 0.8)
			if stairs.has(c):
				# The stairwell: steps coming up from below, and on up to the roof hatch.
				for i in 5:
					var sy := cr.position.y + 2 + i * 2.6
					mc.draw_rect(Rect2(cr.position.x + 2, sy, TILE - 4, 2), Color("8a8078").darkened(0.08 * (4 - i)))
				mc.draw_rect(Rect2(cr.position.x + 1, cr.position.y + 1, TILE - 2, TILE - 2), Color("4a4038"), false, 0.8)
	mc.commit(node)


# --- Streaming ----------------------------------------------------------------
# Everything in the city exists (the server's rules use it all), but only what
# is near the camera is in the scene: a scene of tens of thousands of things
# costs every frame even when they're off screen (sorting, culling).

var stream := {}  # chunk -> [Node2D]: what stands in that CHUNK x CHUNK of cells
var stream_on := {}  # chunks now in the scene
const STREAM_MARGIN := 1  # chunks beyond the screen kept in (and one more before they go)
const STREAM_PER_FRAME := 3  # chunks brought in a frame at most, so walking doesn't stutter


func _chunk_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / (CHUNK * TILE)), floori(pos.y / (CHUNK * TILE)))


## The props registered in the chunks around `pos` (r chunks each way), in or
## out of the scene: for finding what's near without going through the whole city.
func near(pos: Vector2, r := 1) -> Array:
	var k := _chunk_of(pos)
	var out := []
	for y in range(k.y - r, k.y + r + 1):
		for x in range(k.x - r, k.x + r + 1):
			out.append_array(stream.get(Vector2i(x, y), []))
	return out


## Register a prop; it goes into the scene when the camera comes near.
func _stream(n: Node2D, pos: Vector2) -> void:
	var k := _chunk_of(pos)
	if not stream.has(k):
		stream[k] = []
	stream[k].append(n)
	if stream_on.has(k):
		_attach(n)


var owned: Array = []  # what this world put straight into the scene (bikes, the skytrain)


## Freed without dispose() (the game closing): still free what it made.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for list in stream.values():
			for n in list:
				if is_instance_valid(n) and n.get_parent() == null:
					n.free()


func _own(n: Node) -> void:
	prop_parent.add_child(n)
	owned.append(n)


## Take everything this world made out of the scene and free it: props sit
## in the scene beside the players (so they sort with them), not under the
## world, so freeing the world alone would leave them behind.
func dispose() -> void:
	for list in stream.values():
		for n in list:
			if is_instance_valid(n):
				if n.get_parent():
					n.get_parent().remove_child(n)
				n.free()
	stream.clear()
	stream_on.clear()
	for n in owned:
		if is_instance_valid(n):
			n.queue_free()
	owned.clear()


func _attach(n: Node2D) -> void:
	prop_parent.add_child(n)
	# Lights and lit windows that came in after dusk: on, like the rest.
	for x in [n] + n.get_children():
		if x.is_in_group("street_lights") or x.is_in_group("night_glow"):
			x.visible = is_night


## Every frame on a machine with a screen: bring in what's around the view,
## take out what's well off it. (A headless server never calls this.)
func stream_around(view: Rect2) -> void:
	var cs := float(CHUNK * TILE)
	var a := Vector2i(floori(view.position.x / cs), floori(view.position.y / cs)) - Vector2i.ONE * STREAM_MARGIN
	var b := Vector2i(floori(view.end.x / cs), floori(view.end.y / cs)) + Vector2i.ONE * STREAM_MARGIN
	var added := 0
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var k := Vector2i(x, y)
			if stream_on.has(k) or added >= STREAM_PER_FRAME:
				continue
			stream_on[k] = true
			added += 1
			for n: Node2D in stream.get(k, []):
				_attach(n)
	for k: Vector2i in stream_on.keys():
		if k.x < a.x - 1 or k.x > b.x + 1 or k.y < a.y - 1 or k.y > b.y + 1:
			stream_on.erase(k)
			for n: Node2D in stream.get(k, []):
				if n.get_parent():
					n.get_parent().remove_child(n)


const LAMP_LIGHT := 64.0  # how far a street lamp lights the ground around it (pixels)
const BULB_LIGHT := 40.0


## At night, is `pos` somewhere lit (under a street lamp, in a lit room)? By day
## everywhere is.
func is_lit(pos: Vector2) -> bool:
	if not is_night:
		return true
	for l in light_spots:
		if pos.distance_squared_to(l[0]) < l[1] * l[1]:
			return true
	return false


func _add_tree(c: Vector2i) -> void:
	var t := TreeProp.new()
	t.cell = c
	t.position = to_pos(c) + Vector2(0, TILE * 0.3)
	t.scale = Vector2.ONE * TreeProp.SCALE  # Bangkok's street trees spread over the road
	t.z_index = 1
	_stream(t, t.position)
	props[c] = t


# --- Grid -------------------------------------------------------------------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func get_tile(c: Vector2i) -> int:
	return tiles[c.y * W + c.x] if in_bounds(c) else WATER


## Layout-time write: no pathfinding or redraw updates.
func fill(r: Rect2i, t: int) -> void:
	for y in range(maxi(r.position.y, 0), mini(r.end.y, H)):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, W)):
			tiles[y * W + x] = t


func set_tile(c: Vector2i, t: int) -> void:
	if props.has(c):
		props[c].queue_free()
		props.erase(c)
	tiles[c.y * W + c.x] = t
	astar.set_point_solid(c, is_solid(c))
	chunks[c / CHUNK].queue_redraw()


## Where someone comes in by way out `exit_id` (the spawn corner if there's no such way).
func arrival_of(exit_id: String) -> Vector2:
	for e in exits:
		if e.id == exit_id:
			return to_pos(Zones.arrival(e))
	return spawn_point()


## Upstairs, only the floor up there is somewhere to stand.
func is_solid_up(c: Vector2i) -> bool:
	return upper.get(c, WALL) != FLOOR or upper_blocked.has(c)


## Path upstairs from a to b (cells, not counting where you are): the rooms
## up there are small, so a plain breadth-first search.
func path_up(a: Vector2, b: Vector2) -> Array:
	var from := to_cell(a)
	var to := to_cell(b)
	if is_solid_up(to) or from == to:
		return []
	var came := {from: from}
	var queue := [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			var out := []
			while c != from:
				out.push_front(c)
				c = came[c]
			return out
		for d in DIRS:
			var n: Vector2i = c + d
			if not came.has(n) and not is_solid_up(n):
				came[n] = c
				queue.append(n)
	return []


func is_solid(c: Vector2i) -> bool:
	if door_at.has(c):
		return doors[door_at[c]].closed
	return get_tile(c) in [WATER, TREE, WALL, BUILDING, IWALL] or blocked.has(c)


## Cells taken by something low enough to jump over at a run: a line of
## sandbags, a bin, a dropped bag, a heap of rubble, the bonnet of a car or a
## wreck (not a van, a bus or a stall with its roof). And cells under
## something high enough off the ground to crawl under and hide: a bus, a
## songthaew, a pickup, a van, the army truck (not a car: too low). Both
## worked out from the props already there, the first time either is asked.
const LOW_PROPS := ["sandbags", "barrier", "bin", "luggage", "debris"]
const LOW_VEHICLES := {car = 2, taxi = 2, wreck = 2, tuktuk = 1}
const HIGH_VEHICLES := {van = 2, pickup = 2, songthaew = 2, bus = 7, army = 3}
var _low: Dictionary = {}
var _under: Dictionary = {}
var _props_read := false


func is_low(c: Vector2i) -> bool:
	_read_props()
	return _low.has(c)


func is_under(c: Vector2i) -> bool:
	_read_props()
	return _under.has(c)


func _read_props() -> void:
	if _props_read:
		return
	_props_read = true
	for sp in street_props:
		var pos: Vector2 = sp.pos
		if sp.kind in LOW_PROPS:
			var at := to_cell(pos - Vector2(0, 5))
			if blocked.has(at):
				_low[at] = true
		for table in [[LOW_VEHICLES, _low], [HIGH_VEHICLES, _under]]:
			if not table[0].has(sp.kind):
				continue
			# (A vehicle's pos is the bottom-left corner of its last cell.)
			var n: int = table[0][sp.kind]
			var x := int(pos.x / TILE)
			var last := int(pos.y / TILE) - 1
			for i in n:
				var at := Vector2i(x + i, last) if sp.get("horizontal", false) or sp.kind == "army" else Vector2i(x, last - n + 1 + i)
				if blocked.has(at):
					table[1][at] = true


func is_built(id: int) -> bool:
	return BUILDS.has(doors[id].get("kind", "door"))


## Add or replace a trap someone set down (every peer, from the server).
func add_structure(id: int, cell: Vector2i, kind: String, hp: float) -> void:
	var d := {id = id, cell = cell, kind = kind, closed = BUILDS[kind].solid, hp = hp, boards = 0, broken = false}
	if id < doors.size():
		doors[id] = d
		door_nodes[id].door = d
		door_nodes[id].queue_redraw()
	else:
		doors.append(d)
		var n := DoorProp.new()
		n.door = d
		n.position = Vector2(cell.x * TILE, (cell.y + 1) * TILE)
		n.z_index = 0 if not BUILDS[kind].solid else 1
		_stream(n, n.position)
		door_nodes.append(n)
	door_at[cell] = id
	astar.set_point_solid(cell, d.closed)


## Can a trap go here?
func can_build(cell: Vector2i) -> bool:
	if not in_bounds(cell) or stairs.has(cell):
		return false
	var id: int = door_at.get(cell, -1)
	if id >= 0:
		return is_built(id) and doors[id].broken  # over a trap that's worn out
	return get_tile(cell) not in [WATER, TREE, WALL, BUILDING, IWALL] and not blocked.has(cell)


func is_window(id: int) -> bool:
	return doors[id].get("kind", "door") == "window"


## Movement multiplier at a position: climbing through a smashed window is slow.
func slow_at(pos: Vector2) -> float:
	var id: int = door_at.get(to_cell(pos), -1)
	if id < 0 or doors[id].closed or doors[id].broken and is_built(id):
		return 1.0
	if is_window(id) or doors[id].kind == "shutter" and doors[id].broken:
		return WINDOW_SLOW  # (ducking under a prised-up shutter too)
	return WIRE_SLOW if doors[id].kind == "wire" else 1.0


## Update a door from the server's state.
func set_door(id: int, closed: bool, hp: float, boards: int, broken: bool) -> void:
	var d: Dictionary = doors[id]
	d.closed = closed
	d.hp = hp
	d.boards = boards
	d.broken = broken
	if is_built(id) and broken:
		d.closed = false  # a smashed fence is just debris
	astar.set_point_solid(d.cell, d.closed)
	door_nodes[id].queue_redraw()


## Would a body at `pos` overlap this door's cell? 0 = clear, 1 = only its edge
## (can be nudged out), 2 = standing in the doorway itself.
func door_overlap(id: int, pos: Vector2, r := 5.0) -> int:
	var off := pos - to_pos(doors[id].cell)
	var reach := TILE * 0.5 + r
	if absf(off.x) >= reach or absf(off.y) >= reach:
		return 0
	return 2 if absf(off.y) < 6.0 else 1


## Push a body that overlaps a door's cell out to the side it's already on.
## Doors sit in east-west walls, so that's straight north or south.
func nudge_out_of_door(id: int, pos: Vector2, r := 5.0) -> Vector2:
	var c := to_pos(doors[id].cell)
	var side := 1.0 if pos.y >= c.y else -1.0
	var out := Vector2(pos.x, c.y + side * (TILE * 0.5 + r + 0.5))
	return out if can_stand(out, r) else pos


func door_near(pos: Vector2, reach: float) -> int:
	var c := to_cell(pos)
	var best := -1
	var best_d := reach
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var id: int = door_at.get(c + Vector2i(dx, dy), -1)
			if id >= 0:
				var d := pos.distance_to(to_pos(doors[id].cell))
				if d < best_d:
					best_d = d
					best = id
	return best


func closed_door_near(pos: Vector2, reach: float) -> int:
	var id := door_near(pos, reach)
	return id if id >= 0 and doors[id].closed else -1


## Path from a to b. If b is inside a building shut behind its door, the path
## leads to that door instead (so zombies know where to start pounding).
func path_between(a: Vector2, b: Vector2) -> Array:
	var from := to_cell(a)
	var p: Array = astar.get_id_path(from, to_cell(b))
	if p.is_empty():
		var bld: BuildingProp = building_at.get(to_cell(b))
		if bld and bld.data.get("enter", false):
			var dc := Vector2i(bld.data.rect.position.x + bld.data.door, bld.data.rect.end.y - 1)
			var id: int = door_at.get(dc, -1)
			if id >= 0 and doors[id].closed:
				astar.set_point_solid(dc, false)
				p = astar.get_id_path(from, dc)
				astar.set_point_solid(dc, true)
	if not p.is_empty():
		p.remove_at(0)
	return p


func in_intersection(c: Vector2i) -> bool:
	for r: Rect2i in intersections:
		if r.has_point(c):
			return true
	return false


func to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


func to_pos(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2(TILE, TILE) / 2


## Move a body by `v`, sliding along walls one axis at a time.
## `road`: for a bike, which can't go indoors (floors and doorways are walls to it).
## `prone`: crawling, which fits under a bus or a truck (see is_under).
func slide(pos: Vector2, v: Vector2, r: float, roof := false, road := false, up := false, prone := false) -> Vector2:
	var stuck := _solid_corner_cells(pos, r, roof, road, up, prone)
	if not stuck.is_empty():
		# Already overlapping something solid (a door shut on us): only allow
		# moves heading away from it, never deeper in or along it.
		var centre := Vector2.ZERO
		for c in stuck:
			centre += to_pos(c) / stuck.size()
		var away := pos - centre
		for step in [v, Vector2(v.x, 0), Vector2(0, v.y)]:
			if step.dot(away) > 0.0 and _solid_corner_cells(pos + step, r, roof, road, up, prone).size() <= stuck.size():
				return pos + step
		return pos
	var nx := pos + Vector2(v.x, 0)
	if can_stand(nx, r, roof, road, up, prone):
		pos = nx
	var ny := pos + Vector2(0, v.y)
	if can_stand(ny, r, roof, road, up, prone):
		pos = ny
	return pos


func _solid_corner_cells(p: Vector2, r: float, roof: bool, road := false, up := false, prone := false) -> Array:
	var out := []
	for o in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		var c := to_cell(p + o)
		if prone and not up and not roof and is_under(c):
			continue  # (flat on the ground, under a bus or a truck)
		if (not is_roof(c)) if roof else (is_solid_up(c) if up else (is_solid(c) or road and get_tile(c) in [FLOOR, DOOR])):
			out.append(c)
	return out


## On the ground, stand anywhere not solid; on the roof, only on shophouse
## roofs; upstairs, only on the floor up there.
func can_stand(p: Vector2, r: float, roof := false, road := false, up := false, prone := false) -> bool:
	for o in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		var c := to_cell(p + o)
		if prone and not up and not roof and is_under(c):
			continue
		if (not is_roof(c)) if roof else (is_solid_up(c) if up else is_solid(c)):
			return false
		if road and get_tile(c) in [FLOOR, DOOR]:
			return false
	return true


## Flat shophouse roofs join up along a row, so you can walk from one to the next.
func is_roof(c: Vector2i) -> bool:
	var b: BuildingProp = building_at.get(c)
	return b != null and b.data.kind in ["shop", "store"]


## How far above the street the roof at `pos` is, in screen pixels.
func roof_height(pos: Vector2) -> float:
	var b: BuildingProp = building_at.get(to_cell(pos))
	return b.h if b and b.data.kind in ["shop", "store"] else 0.0


func spawn_point() -> Vector2:
	var base := to_pos(spawn_cell)
	for i in 20:
		var p := base + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		if can_stand(p, 5):
			return p
	return base


## Distance a hit travels from `from` along `dir` before hitting something solid.
func ray_length(from: Vector2, dir: Vector2, max_len: float) -> float:
	var t := 0.0
	while t < max_len:
		var c := to_cell(from + dir * t)
		if not in_bounds(c) or get_tile(c) in [TREE, WALL, BUILDING, IWALL] or _blocks_sight(c):
			return t
		t += 4.0
	return max_len


## How far you can see from `from` along `dir` (unit) before a wall, a
## building or a closed door, up to `max_len`. Walks the tiles the line crosses
## one by one, so it is quick enough to cast a hundred times a frame (see
## Sight). Trees don't block it: you see past a trunk. Returns [distance,
## the tile that stopped it or (-1, -1)].
func sight_ray(from: Vector2, dir: Vector2, max_len: float) -> Array:
	var c := to_cell(from)
	var step := Vector2i(1 if dir.x > 0 else -1, 1 if dir.y > 0 else -1)
	var inv := Vector2(1.0 / dir.x if absf(dir.x) > 0.00001 else INF, 1.0 / dir.y if absf(dir.y) > 0.00001 else INF)
	var next := Vector2((c.x + (1 if step.x > 0 else 0)) * TILE, (c.y + (1 if step.y > 0 else 0)) * TILE)
	var t_max := Vector2((next.x - from.x) * inv.x if inv.x != INF else INF, (next.y - from.y) * inv.y if inv.y != INF else INF)
	var t_delta := Vector2(absf(TILE * inv.x), absf(TILE * inv.y))
	var t := 0.0
	while t < max_len:
		if t_max.x < t_max.y:
			t = t_max.x
			t_max.x += t_delta.x
			c.x += step.x
		else:
			t = t_max.y
			t_max.y += t_delta.y
			c.y += step.y
		if t >= max_len:
			break
		if not in_bounds(c):
			return [t, c]
		var k := tiles[c.y * W + c.x]
		if k == WALL or k == BUILDING or k == IWALL or (door_at.has(c) and _blocks_sight(c)):
			return [t, c]
	return [max_len, Vector2i(-1, -1)]


## Closed doors and boarded windows block the view; bare glass doesn't.
func _blocks_sight(c: Vector2i) -> bool:
	var id: int = door_at.get(c, -1)
	if id < 0 or not doors[id].closed:
		return false
	return not is_window(id) or doors[id].boards > 0


func free_neighbor(c: Vector2i) -> Vector2i:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if in_bounds(c + d) and not is_solid(c + d):
			return c + d
	return Vector2i(-1, -1)


func chop(c: Vector2i) -> void:
	if get_tile(c) == TREE:
		set_tile(c, GRASS)
		wood += 3


func place_wall(c: Vector2i) -> bool:
	if not in_bounds(c) or get_tile(c) not in [GRASS, DIRT] or wood < 2:
		return false
	set_tile(c, WALL)
	wall_hp[c] = 100.0
	wood -= 2
	return true


func hit_wall(c: Vector2i, dmg: float) -> void:
	if not wall_hp.has(c):
		return
	wall_hp[c] -= dmg
	if wall_hp[c] <= 0:
		wall_hp.erase(c)
		set_tile(c, DIRT)


# --- Drawing ----------------------------------------------------------------
# Flat shapes; variety comes from deterministic per-tile hashes, so every
# client draws the same city from the same seed.

## Deterministic 0..1 value for tile (x, y) and channel k.
static func hash01(x: int, y: int, k: int) -> float:
	var h := x * 374761393 + y * 668265263 + k * 982451653
	h = (h ^ (h >> 13)) * 1274126177
	return float((h >> 8) & 0xffff) / 65535.0


const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


## Thin strip along the edge of tile rect `r` facing direction `d`.
static func _edge(r: Rect2, d: Vector2i, thick: float) -> Rect2:
	return Rect2(r.position + Vector2(maxi(d.x, 0), maxi(d.y, 0)) * (TILE - thick),
			Vector2(thick if d.x != 0 else TILE, thick if d.y != 0 else TILE))


## A chunk of ground, drawn as one batch of triangles (see MeshCanvas): the
## ground doesn't move, and drawn shape by shape it was most of every frame.
func _draw_chunk(node: Node2D, area: Rect2i) -> void:
	var mc := MeshCanvas.new()
	for y in range(area.position.y, mini(area.end.y, H)):
		for x in range(area.position.x, mini(area.end.x, W)):
			_draw_tile(mc, x, y)
	mc.commit(node)


func _draw_tile(ci: MeshCanvas, x: int, y: int) -> void:
	var c := Vector2i(x, y)
	var t := tiles[y * W + x]
	var r := Rect2(x * TILE, y * TILE, TILE, TILE)
	var g := GRASS if t == TREE else t
	var base: Color = COLORS[g]
	base = base.lightened(tint.get_noise_2d(x, y) * (0.12 if g == GRASS else 0.05) + (hash01(x, y, 0) - 0.5) * 0.03)
	ci.draw_rect(r, base)
	match g:
		GRASS:
			for i in 3:
				var p := r.position + Vector2(hash01(x, y, i + 1), hash01(x, y, i + 4)) * TILE
				ci.draw_rect(Rect2(p, Vector2(1, 2)), base.lightened(0.12) if i % 2 else base.darkened(0.15))
			if hash01(x, y, 29) < 0.3:
				_tuft(ci, r.position + Vector2(hash01(x, y, 30), hash01(x, y, 31)) * TILE, x + y, 1.6)  # grown long
			if hash01(x, y, 32) < 0.04:
				ci.draw_circle(r.position + Vector2(hash01(x, y, 33), hash01(x, y, 34)) * TILE, 0.8,
						[Color("e8d040"), Color("e8e4d8"), Color("d86a8a")][int(hash01(x, y, 35) * 3)])  # wild flowers
		DIRT:
			if hash01(x, y, 7) < 0.4:
				var p := r.position + Vector2(hash01(x, y, 8), hash01(x, y, 9)) * (TILE - 3)
				ci.draw_rect(Rect2(p, Vector2(2, 2)), base.darkened(0.25))
		WATER:
			# Ripples catching the light, and rafts of water hyacinth drifting.
			for i in 2:
				if hash01(x, y, 5 + i) < 0.6:
					var p := r.position + Vector2(hash01(x, y, 6 + i) * 10, hash01(x, y, 7 + i) * 14)
					ci.draw_line(p, p + Vector2(4 + hash01(x, y, 9) * 3, 0), base.lightened(0.18), 0.6)
			if hash01(x, y, 12) < 0.14:
				var p := r.position + Vector2(hash01(x, y, 13), hash01(x, y, 14)) * (TILE - 4) + Vector2(2, 2)
				for k in 3:
					ci.draw_circle(p + Vector2(k * 2.2 - 2, (k % 2) * 1.2), 1.8, Color("4e7a3a").lightened(k * 0.06))
				ci.draw_circle(p + Vector2(0.4, -0.6), 0.6, Color("b89ad8"))  # a flower
			elif hash01(x, y, 12) < 0.17:
				ci.draw_rect(Rect2(r.position + Vector2(5, 6), Vector2(3, 2)), Color("c8c4b8"))  # floating rubbish
			for d in DIRS:
				if get_tile(c + d) != WATER:
					ci.draw_rect(_edge(r, d, 3), Color("8a877f"))
					var wet := _edge(r, d, 5)
					ci.draw_rect(Rect2(wet.position + Vector2(maxi(-d.x, 0), maxi(-d.y, 0)) * 3, wet.size - Vector2(absi(d.x), absi(d.y)) * 3), Color(0, 0, 0, 0.18))
		ROAD:
			if hash01(x, y, 7) < 0.05:
				ci.draw_rect(Rect2(r.position + Vector2(2, 3), Vector2(9, 7)), base.darkened(0.12))  # patched asphalt
			if hash01(x, y, 8) < 0.16:
				_crack(ci, r, x, y, base.darkened(0.3))
			if hash01(x, y, 15) < 0.04:
				_stain(ci, r, x, y, Color(0.05, 0.05, 0.06, 0.35))  # oil
			elif hash01(x, y, 15) < 0.05:
				_puddle(ci, r, x, y)
			# Nobody has cut the grass for months: it pushes up along the kerb.
			for d in DIRS:
				if get_tile(c + d) == SIDEWALK and hash01(x, y, 16) < 0.3:
					var e := _edge(r, d, 3)
					_tuft(ci, e.position + e.size * Vector2(hash01(x, y, 17), 0.5), x + y)
		SIDEWALK:
			var line := base.darkened(0.12)
			ci.draw_line(r.position + Vector2(0, 8), r.position + Vector2(16, 8), line, 0.5)
			ci.draw_line(r.position + Vector2(8, 0), r.position + Vector2(8, 16), line, 0.5)
			ci.draw_line(r.position, r.position + Vector2(16, 0), line.darkened(0.1), 0.5)
			if hash01(x, y, 18) < 0.08:
				ci.draw_rect(Rect2(r.position + Vector2(8, 0) * float(hash01(x, y, 19) < 0.5), Vector2(8, 8)), base.darkened(0.14))  # a lifted slab
			if hash01(x, y, 20) < 0.22:
				_tuft(ci, r.position + Vector2(8, 8), x * 3 + y)  # weeds in the joints
			if hash01(x, y, 21) < 0.05:
				_stain(ci, r, x, y, Color(0.2, 0.15, 0.1, 0.18))
			for d in DIRS:
				if get_tile(c + d) == ROAD:
					# Bangkok's red-and-white painted curbs.
					var e := _edge(r, d, 3)
					var half := Vector2(e.size.x / 2, e.size.y) if d.y != 0 else Vector2(e.size.x, e.size.y / 2)
					var step := Vector2(half.x, 0) if d.y != 0 else Vector2(0, half.y)
					var red := Color("b3372e")
					var white := Color("d9d5cc")
					ci.draw_rect(Rect2(e.position, half), red if (x + y) % 2 else white)
					ci.draw_rect(Rect2(e.position + step, half), white if (x + y) % 2 else red)
		SOI:
			if hash01(x, y, 8) < 0.22:
				_crack(ci, r, x, y, base.darkened(0.25))
			if hash01(x, y, 22) < 0.025:
				_puddle(ci, r, x, y)
			if hash01(x, y, 23) < 0.18:
				_tuft(ci, r.position + Vector2(hash01(x, y, 24), hash01(x, y, 25)) * TILE, x + y * 7)
			if hash01(x, y, 11) < 0.03:
				ci.draw_rect(Rect2(r.position + Vector2(4, 5), Vector2(8, 5)), Color("2e2c2a"))  # drain
		PLAZA:
			ci.draw_rect(r, base.darkened(0.08), false, 0.5)
			if hash01(x, y, 26) < 0.12:
				_tuft(ci, r.position + Vector2(hash01(x, y, 27) * TILE, 0), x + y)
			if hash01(x, y, 28) < 0.03:
				ci.draw_circle(r.position + Vector2(8, 8), 2.5, Color("7a5a2a", 0.5))  # fallen leaves
		FLOOR, DOOR:
			ci.draw_rect(r, base.darkened(0.1), false, 0.5)
			for i in 4:  # terrazzo chips
				var p := r.position + Vector2(hash01(x, y, i + 20), hash01(x, y, i + 30)) * (TILE - 1)
				ci.draw_rect(Rect2(p, Vector2(1, 1)), base.darkened(0.25) if i % 2 else base.lightened(0.15))
			if get_tile(c + Vector2i.DOWN) not in [FLOOR, IWALL]:
				ci.draw_rect(Rect2(r.position + Vector2(0, TILE - 2), Vector2(TILE, 2)), Color("6a5a42"))  # threshold
		IWALL:
			ci.draw_rect(r, base)
			for d in DIRS:
				if get_tile(c + d) == FLOOR:
					ci.draw_rect(_edge(r, d, 3), Color("6e665c"))  # lit inner face of the wall
		WALL:
			ci.draw_rect(Rect2(r.position, Vector2(TILE, 3)), base.lightened(0.1))
			ci.draw_rect(Rect2(r.position + Vector2(0, TILE - 4), Vector2(TILE, 4)), base.darkened(0.3))


## A small clump of weeds.
func _tuft(ci: MeshCanvas, p: Vector2, k: int, size := 1.0) -> void:
	var col := Color("5a6a38").lightened((hash01(k, 3, 40) - 0.5) * 0.2)
	for i in 3:
		var tip := p + Vector2((i - 1) * 1.3, -2.2 - (i % 2) * 0.8) * size
		ci.draw_line(p, tip, col if i != 1 else col.lightened(0.1), 0.6)


func _crack(ci: MeshCanvas, r: Rect2, x: int, y: int, col: Color) -> void:
	var p := r.position + Vector2(hash01(x, y, 9), hash01(x, y, 10)) * TILE
	var q := p + Vector2(hash01(x, y, 41) * 8 - 4, hash01(x, y, 42) * 6)
	ci.draw_polyline(PackedVector2Array([p, p.lerp(q, 0.5) + Vector2(1.2, -0.6), q, q + Vector2(2, 1.5)]), col, 0.5)


func _stain(ci: MeshCanvas, r: Rect2, x: int, y: int, col: Color) -> void:
	var p := r.position + Vector2(hash01(x, y, 43), hash01(x, y, 44)) * TILE
	ci.draw_set_transform(p, 0, Vector2(1.4, 0.8))
	ci.draw_circle(Vector2.ZERO, 3.0 + hash01(x, y, 45) * 3.0, col)
	ci.draw_set_transform(Vector2.ZERO)


## Rainwater lying in a dip, with the sky in it.
func _puddle(ci: MeshCanvas, r: Rect2, x: int, y: int) -> void:
	var p := r.position + Vector2(4, 5) + Vector2(hash01(x, y, 46), hash01(x, y, 47)) * 6
	ci.draw_set_transform(p, 0, Vector2(1.6, 0.7))
	ci.draw_circle(Vector2.ZERO, 3.6, Color("4a5256"))
	ci.draw_circle(Vector2(-0.8, -0.6), 2.4, Color("6a7880"))
	ci.draw_set_transform(Vector2.ZERO)
	ci.draw_line(p + Vector2(-2, -1), p + Vector2(1, -1), Color(1, 1, 1, 0.25), 0.5)


func _draw_markings(node: Node2D) -> void:
	var ci := MeshCanvas.new()  # (one batch for the whole city's paint)
	var white := Color(0.85, 0.83, 0.78, 0.8)
	var yellow := Color(0.85, 0.68, 0.2, 0.85)
	for rd in roads:
		var rect: Rect2i = rd.rect
		# Lane lines a quarter and three quarters across; down the middle, the
		# double yellow (or on the wide streets, a raised island).
		var wd := float((rect.size.y if rd.horizontal else rect.size.x) * TILE)
		var mid := wd / 2.0
		var median: bool = rd.get("median", false)
		if rd.horizontal:
			var y0 := rect.position.y * TILE
			for x in range(rect.position.x, rect.end.x):
				if in_intersection(Vector2i(x, rect.position.y)) or get_tile(Vector2i(x, rect.position.y + 1)) != ROAD:
					continue
				var px := x * TILE
				if median:
					ci.draw_rect(Rect2(px, y0 + mid - 12, 16, 24), Color("9a968c"))
					ci.draw_rect(Rect2(px, y0 + mid - 12, 16, 2.5), Color("d8d0bc"))
					ci.draw_rect(Rect2(px, y0 + mid + 9.5, 16, 2.5), Color("c8302a") if x % 2 else Color("e8e4dc"))
				else:
					ci.draw_line(Vector2(px, y0 + mid - 1.5), Vector2(px + 16, y0 + mid - 1.5), yellow, 1.0)
					ci.draw_line(Vector2(px, y0 + mid + 1.5), Vector2(px + 16, y0 + mid + 1.5), yellow, 1.0)
				if x % 2 == 0:
					ci.draw_line(Vector2(px + 3, y0 + wd / 4.0), Vector2(px + 13, y0 + wd / 4.0), white, 1.0)
					ci.draw_line(Vector2(px + 3, y0 + wd * 0.75), Vector2(px + 13, y0 + wd * 0.75), white, 1.0)
		else:
			var x0 := rect.position.x * TILE
			for y in range(rect.position.y, rect.end.y):
				if in_intersection(Vector2i(rect.position.x, y)) or get_tile(Vector2i(rect.position.x + 1, y)) != ROAD:
					continue
				var py := y * TILE
				if median:
					ci.draw_rect(Rect2(x0 + mid - 12, py, 24, 16), Color("9a968c"))
					ci.draw_rect(Rect2(x0 + mid - 12, py, 24, 3), Color("d8d0bc"))
					ci.draw_rect(Rect2(x0 + mid - 12, py, 2.5, 16), Color("c8302a") if y % 2 else Color("e8e4dc"))
					ci.draw_rect(Rect2(x0 + mid + 9.5, py, 2.5, 16), Color("c8302a") if y % 2 else Color("e8e4dc"))
				else:
					ci.draw_line(Vector2(x0 + mid - 1.5, py), Vector2(x0 + mid - 1.5, py + 16), yellow, 1.0)
					ci.draw_line(Vector2(x0 + mid + 1.5, py), Vector2(x0 + mid + 1.5, py + 16), yellow, 1.0)
				if y % 2 == 0:
					ci.draw_line(Vector2(x0 + wd / 4.0, py + 3), Vector2(x0 + wd / 4.0, py + 13), white, 1.0)
					ci.draw_line(Vector2(x0 + wd * 0.75, py + 3), Vector2(x0 + wd * 0.75, py + 13), white, 1.0)
	if not circle.is_empty():
		# The roundabout: a kerb round the island, a lane line round the road.
		var c := to_pos(circle.at)
		ci.draw_arc(c, (circle.island + 0.5) * TILE, 0, TAU, 64, Color("d8d0bc"), 3.0)
		ci.draw_arc(c, (circle.island + circle.r) * 0.5 * TILE + 8, 0, TAU, 64, Color(0.85, 0.83, 0.78, 0.5), 1.0)
	# Zebra crossings on every side of every junction.
	for it: Rect2i in intersections:
		var o := Vector2(it.position) * TILE
		var sz := it.size.x * TILE
		var north := get_tile(it.position + Vector2i(0, -1)) == ROAD
		var south := get_tile(it.position + Vector2i(0, it.size.y)) == ROAD
		var west := get_tile(it.position + Vector2i(-1, 0)) == ROAD
		var east := get_tile(it.position + Vector2i(it.size.x, 0)) == ROAD
		for k in int(sz / 8):
			var s := k * 8.0 + 1.5
			if north:
				ci.draw_rect(Rect2(o.x + s, o.y - 26, 5, 22), white)
			if south:
				ci.draw_rect(Rect2(o.x + s, o.y + sz + 4, 5, 22), white)
			if west:
				ci.draw_rect(Rect2(o.x - 26, o.y + s, 22, 5), white)
			if east:
				ci.draw_rect(Rect2(o.x + sz + 4, o.y + s, 22, 5), white)
	if bts_row >= 0:
		ci.draw_rect(Rect2(0, (bts_row - 1) * TILE, W * TILE, 4 * TILE), Color(0, 0, 0, 0.2))  # skytrain shadow
	for i in bts_path.size() - 1:
		ci.draw_line(bts_path[i], bts_path[i + 1], Color(0, 0, 0, 0.18), 4 * TILE)  # (and a drawn zone's)
	ci.commit(node)
