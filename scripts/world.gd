class_name World
extends Node2D
## Tile grid, collision, pathfinding and ground drawing. The layout comes
## from CityGen; buildings, trees, poles and cars are separate y-sorted nodes
## so characters can walk behind them.

const TILE := 16
const W := 160
const H := 120
const CHUNK := 16
const BTS_H := 64.0  # how high the skytrain deck floats above the road
const DOOR_HP := 60.0
const WINDOW_HP := 15.0  # glass: one good hit
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
var stairs := {}  # cell -> true: stairwells up to the roof
var door_at := {}  # cell -> door id
var door_nodes: Array = []
var overhead: Overhead

# Layout records filled in by CityGen.
var buildings: Array = []
var street_props: Array = []
var roads: Array = []  # {rect: Rect2i, horizontal: bool}
var intersections: Array = []  # Rect2i
var wires: Array = []  # [from, to] pole tops
var checkpoint := Rect2i()  # the junction the army held
var bts_row := -1
var spawn_cell := Vector2i(W / 2, H / 2)

var chunks := {}


func generate(seed_val: int) -> void:
	tint.seed = seed_val + 1
	tint.frequency = 0.04
	tiles.resize(W * H)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	CityGen.build(self, rng)

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
		prop_parent.add_child(b)
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
		n.z_index = 1
		prop_parent.add_child(n)
		door_nodes.append(n)
		astar.set_point_solid(d.cell, d.closed)
	var bnode := {}
	for b: BuildingProp in building_nodes:
		bnode[b.data] = b
	for rec in decor:
		var dp := DecorProp.new()
		dp.data = rec
		dp.position = to_pos(rec.cell) + Vector2(0, TILE * 0.45)
		var flat: bool = rec.kind in ["oil", "litter", "mattress"]
		dp.z_index = 0 if flat else (3 if rec.kind == "bulb" else 1)
		prop_parent.add_child(dp)
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
			prop_parent.add_child(light)
	for rec in containers:
		var f := FurnitureProp.new()
		f.data = rec
		f.position = to_pos(rec.cell) + Vector2(0, TILE * 0.45)
		f.z_index = 1
		prop_parent.add_child(f)
		container_nodes.append(f)
	for rec in street_props:
		var p := StreetProp.new()
		p.data = rec
		p.position = rec.pos
		p.z_index = 0 if rec.get("flat", false) else 1  # litter lies under everyone
		prop_parent.add_child(p)
	overhead = Overhead.new()
	overhead.world = self
	overhead.z_index = 4
	prop_parent.add_child(overhead)


func _add_tree(c: Vector2i) -> void:
	var t := TreeProp.new()
	t.cell = c
	t.position = to_pos(c) + Vector2(0, TILE * 0.3)
	t.z_index = 1
	prop_parent.add_child(t)
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


func is_solid(c: Vector2i) -> bool:
	if door_at.has(c):
		return doors[door_at[c]].closed
	return get_tile(c) in [WATER, TREE, WALL, BUILDING, IWALL] or blocked.has(c)


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
		prop_parent.add_child(n)
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
	if is_window(id):
		return WINDOW_SLOW
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
func slide(pos: Vector2, v: Vector2, r: float, roof := false) -> Vector2:
	var stuck := _solid_corner_cells(pos, r, roof)
	if not stuck.is_empty():
		# Already overlapping something solid (a door shut on us): only allow
		# moves heading away from it, never deeper in or along it.
		var centre := Vector2.ZERO
		for c in stuck:
			centre += to_pos(c) / stuck.size()
		var away := pos - centre
		for step in [v, Vector2(v.x, 0), Vector2(0, v.y)]:
			if step.dot(away) > 0.0 and _solid_corner_cells(pos + step, r, roof).size() <= stuck.size():
				return pos + step
		return pos
	var nx := pos + Vector2(v.x, 0)
	if can_stand(nx, r, roof):
		pos = nx
	var ny := pos + Vector2(0, v.y)
	if can_stand(ny, r, roof):
		pos = ny
	return pos


func _solid_corner_cells(p: Vector2, r: float, roof: bool) -> Array:
	var out := []
	for o in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		var c := to_cell(p + o)
		if (not is_roof(c)) if roof else is_solid(c):
			out.append(c)
	return out


## On the ground, stand anywhere not solid; on the roof, only on shophouse roofs.
func can_stand(p: Vector2, r: float, roof := false) -> bool:
	for o in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		var c := to_cell(p + o)
		if (not is_roof(c)) if roof else is_solid(c):
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


func _draw_chunk(ci: Node2D, area: Rect2i) -> void:
	for y in range(area.position.y, mini(area.end.y, H)):
		for x in range(area.position.x, mini(area.end.x, W)):
			_draw_tile(ci, x, y)


func _draw_tile(ci: Node2D, x: int, y: int) -> void:
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
func _tuft(ci: Node2D, p: Vector2, k: int, size := 1.0) -> void:
	var col := Color("5a6a38").lightened((hash01(k, 3, 40) - 0.5) * 0.2)
	for i in 3:
		var tip := p + Vector2((i - 1) * 1.3, -2.2 - (i % 2) * 0.8) * size
		ci.draw_line(p, tip, col if i != 1 else col.lightened(0.1), 0.6)


func _crack(ci: Node2D, r: Rect2, x: int, y: int, col: Color) -> void:
	var p := r.position + Vector2(hash01(x, y, 9), hash01(x, y, 10)) * TILE
	var q := p + Vector2(hash01(x, y, 41) * 8 - 4, hash01(x, y, 42) * 6)
	ci.draw_polyline(PackedVector2Array([p, p.lerp(q, 0.5) + Vector2(1.2, -0.6), q, q + Vector2(2, 1.5)]), col, 0.5)


func _stain(ci: Node2D, r: Rect2, x: int, y: int, col: Color) -> void:
	var p := r.position + Vector2(hash01(x, y, 43), hash01(x, y, 44)) * TILE
	ci.draw_set_transform(p, 0, Vector2(1.4, 0.8))
	ci.draw_circle(Vector2.ZERO, 3.0 + hash01(x, y, 45) * 3.0, col)
	ci.draw_set_transform(Vector2.ZERO)


## Rainwater lying in a dip, with the sky in it.
func _puddle(ci: Node2D, r: Rect2, x: int, y: int) -> void:
	var p := r.position + Vector2(4, 5) + Vector2(hash01(x, y, 46), hash01(x, y, 47)) * 6
	ci.draw_set_transform(p, 0, Vector2(1.6, 0.7))
	ci.draw_circle(Vector2.ZERO, 3.6, Color("4a5256"))
	ci.draw_circle(Vector2(-0.8, -0.6), 2.4, Color("6a7880"))
	ci.draw_set_transform(Vector2.ZERO)
	ci.draw_line(p + Vector2(-2, -1), p + Vector2(1, -1), Color(1, 1, 1, 0.25), 0.5)


func _draw_markings(ci: Node2D) -> void:
	var white := Color(0.85, 0.83, 0.78, 0.8)
	var yellow := Color(0.85, 0.68, 0.2, 0.85)
	for rd in roads:
		var rect: Rect2i = rd.rect
		if rd.horizontal:
			var y0 := rect.position.y * TILE
			for x in W:
				if in_intersection(Vector2i(x, rect.position.y)):
					continue
				var px := x * TILE
				ci.draw_line(Vector2(px, y0 + 46.5), Vector2(px + 16, y0 + 46.5), yellow, 1.0)
				ci.draw_line(Vector2(px, y0 + 49.5), Vector2(px + 16, y0 + 49.5), yellow, 1.0)
				if x % 2 == 0:
					ci.draw_line(Vector2(px + 3, y0 + 24), Vector2(px + 13, y0 + 24), white, 1.0)
					ci.draw_line(Vector2(px + 3, y0 + 72), Vector2(px + 13, y0 + 72), white, 1.0)
		else:
			var x0 := rect.position.x * TILE
			for y in H:
				if in_intersection(Vector2i(rect.position.x, y)):
					continue
				var py := y * TILE
				ci.draw_line(Vector2(x0 + 46.5, py), Vector2(x0 + 46.5, py + 16), yellow, 1.0)
				ci.draw_line(Vector2(x0 + 49.5, py), Vector2(x0 + 49.5, py + 16), yellow, 1.0)
				if y % 2 == 0:
					ci.draw_line(Vector2(x0 + 24, py + 3), Vector2(x0 + 24, py + 13), white, 1.0)
					ci.draw_line(Vector2(x0 + 72, py + 3), Vector2(x0 + 72, py + 13), white, 1.0)
	# Zebra crossings on every side of every junction.
	for it: Rect2i in intersections:
		var o := Vector2(it.position) * TILE
		var sz := it.size.x * TILE
		var north := get_tile(it.position + Vector2i(0, -1)) == ROAD
		var south := get_tile(it.position + Vector2i(0, it.size.y)) == ROAD
		var west := get_tile(it.position + Vector2i(-1, 0)) == ROAD
		var east := get_tile(it.position + Vector2i(it.size.x, 0)) == ROAD
		for k in 12:
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
