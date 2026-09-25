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
enum { GRASS, DIRT, WATER, TREE, WALL, ROAD, SIDEWALK, SOI, BUILDING, PLAZA }
const COLORS := {
	GRASS: Color("4a5733"),
	DIRT: Color("6a5a43"),
	WATER: Color("3b4838"),
	TREE: Color("3f5431"),
	WALL: Color("e2dccc"),
	ROAD: Color("3a3b3c"),
	SIDEWALK: Color("8e8a82"),
	SOI: Color("6b6862"),
	BUILDING: Color("4a4640"),
	PLAZA: Color("aaa293"),
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
var overhead: Overhead

# Layout records filled in by CityGen.
var buildings: Array = []
var street_props: Array = []
var roads: Array = []  # {rect: Rect2i, horizontal: bool}
var intersections: Array = []  # Rect2i
var wires: Array = []  # [from, to] pole tops
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
	for rec in street_props:
		var p := StreetProp.new()
		p.data = rec
		p.position = rec.pos
		p.z_index = 1
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
	return get_tile(c) in [WATER, TREE, WALL, BUILDING] or blocked.has(c)


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
func slide(pos: Vector2, v: Vector2, r: float) -> Vector2:
	var nx := pos + Vector2(v.x, 0)
	if can_stand(nx, r):
		pos = nx
	var ny := pos + Vector2(0, v.y)
	if can_stand(ny, r):
		pos = ny
	return pos


func can_stand(p: Vector2, r: float) -> bool:
	for o in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		if is_solid(to_cell(p + o)):
			return false
	return true


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
		if not in_bounds(c) or get_tile(c) in [TREE, WALL, BUILDING]:
			return t
		t += 4.0
	return max_len


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
		DIRT:
			if hash01(x, y, 7) < 0.4:
				var p := r.position + Vector2(hash01(x, y, 8), hash01(x, y, 9)) * (TILE - 3)
				ci.draw_rect(Rect2(p, Vector2(2, 2)), base.darkened(0.25))
		WATER:
			if hash01(x, y, 5) < 0.5:
				var p := r.position + Vector2(hash01(x, y, 6) * 10, hash01(x, y, 7) * 14)
				ci.draw_line(p, p + Vector2(5, 0), base.lightened(0.1), 0.6)
			for d in DIRS:
				if get_tile(c + d) != WATER:
					ci.draw_rect(_edge(r, d, 3), Color("8a877f"))
		ROAD:
			if hash01(x, y, 7) < 0.05:
				ci.draw_rect(Rect2(r.position + Vector2(2, 3), Vector2(9, 7)), base.darkened(0.12))  # patched asphalt
			if hash01(x, y, 8) < 0.08:
				var p := r.position + Vector2(hash01(x, y, 9), hash01(x, y, 10)) * TILE
				ci.draw_line(p, p + Vector2(5, 3), base.darkened(0.3), 0.5)
		SIDEWALK:
			var line := base.darkened(0.12)
			ci.draw_line(r.position + Vector2(0, 8), r.position + Vector2(16, 8), line, 0.5)
			ci.draw_line(r.position + Vector2(8, 0), r.position + Vector2(8, 16), line, 0.5)
			ci.draw_line(r.position, r.position + Vector2(16, 0), line.darkened(0.1), 0.5)
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
				var p := r.position + Vector2(hash01(x, y, 9), hash01(x, y, 10)) * TILE
				ci.draw_line(p, p + Vector2(4, 5), base.darkened(0.25), 0.5)
			if hash01(x, y, 11) < 0.03:
				ci.draw_rect(Rect2(r.position + Vector2(4, 5), Vector2(8, 5)), Color("2e2c2a"))  # drain
		PLAZA:
			ci.draw_rect(r, base.darkened(0.08), false, 0.5)
		WALL:
			ci.draw_rect(Rect2(r.position, Vector2(TILE, 3)), base.lightened(0.1))
			ci.draw_rect(Rect2(r.position + Vector2(0, TILE - 4), Vector2(TILE, 4)), base.darkened(0.3))


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
