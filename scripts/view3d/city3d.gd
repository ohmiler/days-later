class_name City3D
extends RefCounted
## The city in 3D, built from the same records the 2D city is drawn from
## (World tiles, buildings, storeys, street props, furniture), one chunk
## (World.CHUNK cells square) at a time. A cell is a metre. Walls are drawn
## thin along the middle of their cells; the game still walks on the grid.
## Everything is code: boxes with vertex colours and one ground shader.

const PX := 16.0  # pixels per metre on the ground (World.TILE)
const GROUND_H := 3.6  # the street-level storey (a shophouse's tall shop floor)
const UP_H := 3.1  # each storey above
const WALL_T := 0.2  # how thick a wall is drawn
const DOOR_H := 2.15
const COMPOUND_H := 2.2  # a wall round a compound

var world: World
var mat: ShaderMaterial  # everything solid: vertex colour x noise


## Metres up to the floor of storey `f`.
static func storey_y(f: int) -> float:
	return 0.0 if f <= 0 else GROUND_H + (f - 1) * UP_H


static func storey_h(f: int) -> float:
	return GROUND_H if f <= 0 else UP_H


## A point in the game's pixels (on the ground) to metres in 3D.
static func to3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x / PX, y, p.y / PX)


static func to2(v: Vector3) -> Vector2:
	return Vector2(v.x * PX, v.z * PX)


func _init(w: World) -> void:
	world = w
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 wp;
varying vec3 wn;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)); float a = n(p) * 0.5; p = r * p * 2.1 + 3.1; a += n(p) * 0.28; p = r * p * 2.2 + 1.7; a += n(p) * 0.14; return a + n(r * p * 2.3) * 0.08; }
uniform vec3 eye_pos;
uniform vec3 you_pos;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wn = NORMAL; }
void fragment() {
	// Between the camera and you, above your head: dithered away, so trees,
	// awnings and roof edges never hide you.
	vec3 seg = eye_pos - you_pos;
	float k = clamp(dot(wp - you_pos, seg) / dot(seg, seg), 0.0, 1.0);
	float d = length(wp - (you_pos + seg * k));
	if (wp.y > you_pos.y + 2.0 && k > 0.02 && d < 2.6) {
		float fade = smoothstep(2.6, 1.4, d);
		if (fract(dot(FRAGCOORD.xy, vec2(0.5, 0.25))) < fade * 0.85) { discard; }
	}
	vec2 p = abs(wn.y) > 0.5 ? wp.xz : (abs(wn.x) > 0.5 ? wp.zy : wp.xy);
	float grit = n(p * 30.0);
	vec3 c = COLOR.rgb * (0.82 + fbm(p * 0.45) * 0.3) * (0.95 + grit * 0.08);
	c = mix(c, c * vec3(0.72, 0.7, 0.62), smoothstep(0.5, 0.85, fbm(p * 0.6 + 7.0)) * 0.45);
	// grime near the ground on walls
	if (abs(wn.y) < 0.5) { c *= mix(0.7, 1.0, smoothstep(0.0, 1.2, fract(wp.y / 3.1) * 3.1)); }
	ALBEDO = c;
	ROUGHNESS = 0.88 + grit * 0.08;
}
"""
	mat = ShaderMaterial.new()
	mat.shader = sh


# --- Box building -------------------------------------------------------------

## A box with its faces (skipping the bottom), into `st` with colour `col`.
static func box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, bottom := false) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.UP, [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.BACK, [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3.FORWARD, [Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3.RIGHT, [Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)]],
		[Vector3.LEFT, [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
	]
	if bottom:
		faces.append([Vector3.DOWN, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]])
	st.set_color(col)
	for f in faces:
		var q: Array = f[1]
		st.set_normal(f[0])
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(c + q[i])


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _commit(st: SurfaceTool, parent: Node3D, name_ := "", shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.name = name_ if name_ != "" else "mesh"
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# --- The ground ---------------------------------------------------------------

const GROUND := {
	World.GRASS: [0.03, Color("5a6a3c")], World.DIRT: [0.03, Color("7a684c")], World.WATER: [-0.6, Color("3a4a40")],
	World.TREE: [0.03, Color("56663a")], World.ROAD: [0.0, Color("4a4b4c")], World.SIDEWALK: [0.15, Color("a8a296")],
	World.SOI: [0.03, Color("7a766e")], World.PLAZA: [0.12, Color("b8b0a0")], World.BUILDING: [0.1, Color("8a847a")],
	World.FLOOR: [0.1, Color("b0a48c")], World.IWALL: [0.1, Color("b0a48c")], World.DOOR: [0.1, Color("b0a48c")],
	World.WALL: [0.1, Color("8a847a")],
}


func ground_h(c: Vector2i) -> float:
	var g: Array = GROUND.get(world.get_tile(c), [0.0, Color.GRAY])
	return g[0]


## One chunk: its ground, compound walls, trees, street props, furniture,
## and the buildings whose corner is in it. Returns the chunk's node; the
## buildings are also listed in `out_buildings` (id -> node) for cutaways.
func build_chunk(cc: Vector2i, out_buildings: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "chunk_%d_%d" % [cc.x, cc.y]
	var r := Rect2i(cc * World.CHUNK, Vector2i(World.CHUNK, World.CHUNK)).intersection(Rect2i(0, 0, World.W, World.H))
	var g := _begin()
	var props := _begin()
	var water := false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var t := world.get_tile(c)
			var info: Array = GROUND.get(t, [0.0, Color.GRAY])
			var hgt: float = info[0]
			var col: Color = info[1]
			if t == World.ROAD and (x + y) % 7 == 0:
				col = col.darkened(0.04)
			# The top, and sides down to lower neighbours (kerbs, canal banks).
			var low := hgt
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				low = minf(low, ground_h(c + d) if world.in_bounds(c + d) else hgt)
			var bottom := minf(low, 0.0) - 0.05
			box(g, Vector3(x + 0.5, (hgt + bottom) * 0.5, y + 0.5), Vector3(1.0, hgt - bottom, 1.0), col)
			if t == World.WATER:
				water = true
			elif t == World.TREE:
				_tree(props, Vector3(x + 0.5, hgt, y + 0.5), World.hash01(x, y, 3))
			elif t == World.WALL and not world.building_at.has(c):
				_wall_cell(props, c, 0.0, COMPOUND_H, Color("c8c0b0"), func(q: Vector2i): return world.get_tile(q) == World.WALL and not world.building_at.has(q), func(_q): return false)
	_road_marks(g, r)
	_commit(g, root, "ground", false)
	if water:
		var wm := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(r.size)
		wm.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.28, 0.24, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.08
		m.metallic = 0.2
		wm.material_override = m
		wm.position = Vector3(r.position.x + r.size.x * 0.5, -0.3, r.position.y + r.size.y * 0.5)
		root.add_child(wm)
	for sp in world.street_props:
		var c := world.to_cell(sp.pos)
		if r.has_point(c):
			_street_prop(props, sp)
	for list in [world.containers, world.decor, world.things]:
		for f in list:
			if r.has_point(f.cell) and not (list == world.things and f.kind in ["stove", "jar", "volunteer"]):
				if f.kind == "stairs":
					_stairs(props, f)
				else:
					_furniture(props, f)
	_commit(props, root, "props")
	for b in world.buildings:
		var br: Rect2i = b.rect
		if r.has_point(br.position):
			var bn := _building(b)
			root.add_child(bn)
			out_buildings[b.id] = bn
	return root


## Paint on the roads in this chunk: a dashed line down the middle, solid
## lines along the edges.
func _road_marks(st: SurfaceTool, area: Rect2i) -> void:
	var paint := Color("d8d2c0")
	for road in world.roads:
		var rr: Rect2i = road.rect
		var cut := rr.intersection(area)
		if cut.size.x <= 0 or cut.size.y <= 0:
			continue
		var horiz: bool = road.horizontal
		var mid: float = rr.position.y + rr.size.y * 0.5 if horiz else rr.position.x + rr.size.x * 0.5
		var from := cut.position.x if horiz else cut.position.y
		var to := cut.end.x if horiz else cut.end.y
		var t := from
		while t < to:
			var at := float(t) + 0.5
			if not road.get("median", false) and posmod(t, 4) < 2:
				var c := Vector3(at, 0.006, mid) if horiz else Vector3(mid, 0.006, at)
				box(st, c, Vector3(1.0, 0.012, 0.12) if horiz else Vector3(0.12, 0.012, 1.0), paint)
			for edge in [0.35, (rr.size.y if horiz else rr.size.x) - 0.35]:
				var e: float = (rr.position.y if horiz else rr.position.x) + edge
				var ce := Vector3(at, 0.006, e) if horiz else Vector3(e, 0.006, at)
				box(st, ce, Vector3(1.0, 0.012, 0.1) if horiz else Vector3(0.1, 0.012, 1.0), paint.darkened(0.1))
			t += 1


func _tree(st: SurfaceTool, at: Vector3, k: float) -> void:
	var tall := 4.5 + k * 3.0
	box(st, at + Vector3(0, tall * 0.35, 0), Vector3(0.28, tall * 0.7, 0.28), Color("5a4634"))
	var green := Color("4a6a38").lerp(Color("3a5a30"), k)
	for i in 5:
		var a := TAU * (i / 5.0 + k)
		var o := Vector3(cos(a), 0, sin(a)) * (1.0 + k * 0.5)
		var s := 2.0 + fmod(k * 7.0 + i, 1.0) * 1.2
		box(st, at + o + Vector3(0, tall * 0.8 + (i % 2) * 0.6, 0), Vector3(s, s * 0.7, s), green.lightened(0.05 * (i % 3)))


## A wall along the middle of cell `c`: a post, and an arm toward each
## neighbour that `joins`; over a neighbouring doorway (`door`), a lintel.
func _wall_cell(st: SurfaceTool, c: Vector2i, y0: float, h: float, col: Color, joins: Callable, door: Callable) -> void:
	var cx := c.x + 0.5
	var cz := c.y + 0.5
	box(st, Vector3(cx, y0 + h * 0.5, cz), Vector3(WALL_T, h, WALL_T), col)
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var q: Vector2i = c + d
		var along := Vector3(d.x, 0, d.y) * 0.25
		var size := Vector3(0.5 if d.x != 0 else WALL_T, h, 0.5 if d.y != 0 else WALL_T)
		if joins.call(q):
			box(st, Vector3(cx, y0 + h * 0.5, cz) + along, size, col)
		elif door.call(q):
			# Up to the doorway (the wall over it is the doorway's own).
			box(st, Vector3(cx, y0 + h * 0.5, cz) + along, size, col)


# --- Buildings ----------------------------------------------------------------

## A building: a node per storey (walls and floor meshes apart, so the ones
## hiding you can go), and the roof.
func _building(b: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "b%d" % b.id
	var r: Rect2i = b.rect
	var floors: int = maxi(1, b.get("floors", 1))
	var outside: Color = b.get("color", Color("d8cdb4"))
	var inside := Color("e0d8c8")
	for f in floors:
		var sn := Node3D.new()
		sn.name = "s%d" % f
		node.add_child(sn)
		var walls := _begin()
		var slab := _begin()
		var y0 := storey_y(f)
		var h := storey_h(f)
		var cells := {}  # cell -> tile, this storey
		if f == 0:
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					cells[Vector2i(x, y)] = world.get_tile(Vector2i(x, y))
		else:
			var up: Dictionary = world.storey_map(f)
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					if up.has(Vector2i(x, y)):
						cells[Vector2i(x, y)] = up[Vector2i(x, y)]
		if cells.is_empty():
			# A storey with nothing inside it in the game: a closed shell.
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
					cells[Vector2i(x, y)] = World.IWALL if edge else World.FLOOR
		var is_wall := func(q: Vector2i) -> bool: return cells.get(q, -1) in [World.IWALL, World.WALL, World.BUILDING]
		var is_door := func(q: Vector2i) -> bool: return cells.get(q, -1) == World.DOOR
		for c: Vector2i in cells:
			var t: int = cells[c]
			var edge := c.x == r.position.x or c.y == r.position.y or c.x == r.end.x - 1 or c.y == r.end.y - 1
			if t in [World.IWALL, World.WALL, World.BUILDING]:
				_wall_cell(walls, c, y0, h, outside if edge else inside, is_wall, is_door)
			elif t == World.DOOR:
				var across: bool = is_wall.call(c + Vector2i.LEFT) or is_wall.call(c + Vector2i.RIGHT) or is_door.call(c + Vector2i.LEFT) or is_door.call(c + Vector2i.RIGHT)
				var lh := h - DOOR_H
				box(walls, Vector3(c.x + 0.5, y0 + DOOR_H + lh * 0.5, c.y + 0.5), Vector3(1.0, lh, WALL_T) if across else Vector3(WALL_T, lh, 1.0), outside if edge else inside)
			# The floor of this storey (the ground floor's is the ground).
			if f > 0:
				box(slab, Vector3(c.x + 0.5, y0 - 0.1, c.y + 0.5), Vector3(1.0, 0.2, 1.0), Color("b8ac94"), true)
		_commit(walls, sn, "walls")
		if f > 0:
			_commit(slab, sn, "floor")
	# The roof, with a low wall round it.
	var roof := _begin()
	var top := storey_y(floors)
	box(roof, Vector3(r.position.x + r.size.x * 0.5, top - 0.1, r.position.y + r.size.y * 0.5), Vector3(r.size.x, 0.2, r.size.y), Color("9a948a"), true)
	for side in 4:
		var horiz := side < 2
		var len_ := float(r.size.x if horiz else r.size.y)
		var at := Vector3(r.position.x + r.size.x * 0.5, top + 0.4, r.position.y + (0.1 if side == 0 else r.size.y - 0.1)) if horiz \
				else Vector3(r.position.x + (0.1 if side == 2 else r.size.x - 0.1), top + 0.4, r.position.y + r.size.y * 0.5)
		box(roof, at, Vector3(len_, 0.8, 0.2) if horiz else Vector3(0.2, 0.8, len_), outside.darkened(0.08))
	var rn := Node3D.new()
	rn.name = "roof"
	node.add_child(rn)
	_commit(roof, rn, "roof")
	# The shop's sign over its front (the south side, toward the camera).
	var sign_text: String = b.get("sign", "")
	if sign_text != "":
		var board := _begin()
		var sy := GROUND_H - 0.45
		box(board, Vector3(r.position.x + r.size.x * 0.5, sy, r.end.y + 0.08), Vector3(minf(r.size.x - 0.4, 6.0), 0.8, 0.12), outside.darkened(0.35))
		_commit(board, node.get_node("s0"), "sign")
		var l := Label3D.new()
		l.text = sign_text
		l.font = UiTheme.medium()
		l.font_size = 72
		l.pixel_size = 0.006
		l.modulate = Color("f4ecd8")
		l.outline_size = 0
		l.position = Vector3(r.position.x + r.size.x * 0.5, sy, r.end.y + 0.15)
		l.shaded = true
		node.get_node("s0").add_child(l)
	return node


# --- Street props and furniture (grey stand-ins with the right size) ---------

## length x width x height (metres) and colour; length runs along the street.
const PROPS := {
	car = [4.4, 1.8, 1.45], taxi = [4.4, 1.8, 1.5], pickup = [5.0, 1.9, 1.8], van = [5.0, 1.9, 2.0], songthaew = [5.0, 1.9, 2.4],
	bus = [11.0, 2.5, 3.1], army = [7.0, 2.4, 3.0], tuktuk = [2.7, 1.3, 1.7], motorbike = [1.9, 0.7, 1.1], wreck = [4.4, 1.8, 1.1],
	cart = [1.6, 0.8, 1.1], stall = [2.0, 1.2, 2.2], trash = [0.9, 0.9, 0.6], bin = [0.6, 0.6, 0.9], pole = [0.25, 0.25, 9.0],
	pillar = [1.4, 1.4, 11.0], debris = [1.2, 1.0, 0.3], luggage = [0.5, 0.3, 0.7], spirit = [0.9, 0.9, 1.9], boat = [6.0, 1.4, 0.6],
	sandbags = [2.0, 0.5, 0.6], zonesign = [2.4, 0.2, 2.6], monument = [4.0, 4.0, 40.0], busstop = [4.0, 1.6, 2.6], btsstairs = [3.0, 8.0, 6.0],
}
const PROP_COL := {taxi = Color("d86a9a"), bus = Color("c8b060"), army = Color("4a5a3a"), tuktuk = Color("3a6aa8"), songthaew = Color("c83a3a"),
		wreck = Color("4a3a30"), pole = Color("8a8e94"), pillar = Color("a8a49c"), spirit = Color("d8b050"), monument = Color("c8c0b0"), boat = Color("7a5a3a")}


func _street_prop(st: SurfaceTool, sp: Dictionary) -> void:
	var s: Array = PROPS.get(sp.kind, [])
	if s.is_empty() or sp.kind == "motorbike":
		return  # (marks on the ground: papers, drag marks, glass; bikes are View3D's, they move)
	var col: Color = PROP_COL.get(sp.kind, sp.get("color", Color("8a8680")))
	var at := to3(sp.pos)
	at.y = ground_h(world.to_cell(sp.pos))
	# Along the street, one way or the other (the seed says which).
	var seed: int = sp.get("seed", 0)
	var yaw := (0.0 if sp.get("horizontal", true) else PI * 0.5) + (PI if seed % 2 else 0.0)
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	Props3D.build(st, xf, sp, Vector3(s[0], s[2], s[1]), col)


## A piece of furniture (or a decor, or a Thing) in its cell, its back to the
## nearest wall; a long bed runs the way the generator laid it.
func _furniture(st: SurfaceTool, f: Dictionary) -> void:
	var cell: Vector2i = f.cell
	var storey: int = f.get("storey", 0)
	var y := storey_y(storey) + (ground_h(cell) if storey == 0 else 0.0)
	var yaw := 0.0
	var long: int = f.get("long", 0)
	if f.kind == "bed" and long != 0:
		yaw = 0.0 if long == 2 else (PI * 0.5 if long == 1 else -PI * 0.5)
	else:
		for d in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			if _is_wall_at(cell + d, storey):
				# The model's back (-Z) toward that wall.
				yaw = atan2(-float(d.x), -float(d.y))
				break
	var shop := ""
	if world.building_at.has(cell):
		var b: Dictionary = world.building_at[cell].data
		shop = b.get("table", b.get("kind", ""))
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(cell.x + 0.5, y, cell.y + 0.5))
	Furniture3D.build(st, xf, f.kind, f.get("seed", f.get("id", 0)), shop, long != 0)


## One cell of a flight of stairs: the flight is the line of stairs cells it
## is in (up and down the room, or across); it climbs a whole storey from the
## front end (+Z, or +X) to the back.
var _stair_cells := {}


func _stairs(st: SurfaceTool, f: Dictionary) -> void:
	if _stair_cells.is_empty():
		for d in world.decor:
			if d.kind == "stairs":
				_stair_cells[Vector3i(d.cell.x, d.cell.y, d.get("storey", 0))] = true
	var c: Vector2i = f.cell
	var s: int = f.get("storey", 0)
	var along := Vector2i.DOWN if _stair_cells.has(Vector3i(c.x, c.y + 1, s)) or _stair_cells.has(Vector3i(c.x, c.y - 1, s)) else Vector2i.RIGHT
	# Where this cell is in the flight, counting from its front (bottom) end.
	var front := c
	while _stair_cells.has(Vector3i(front.x + along.x, front.y + along.y, s)):
		front += along
	var back := c
	while _stair_cells.has(Vector3i(back.x - along.x, back.y - along.y, s)):
		back -= along
	var n := (front - back).x + (front - back).y + 1
	var i := (front - c).x + (front - c).y
	var y0 := storey_y(s)
	var rise := storey_h(s)
	var per := 5
	for k in per:
		var t := float(i * per + k + 1) / (n * per)
		var off := 0.5 - (k + 0.5) / per  # (toward the back of the cell as it climbs)
		var at := Vector3(c.x + 0.5, y0 + t * rise - 0.06, c.y + 0.5) + Vector3(along.x, 0, along.y) * off
		box(st, at, Vector3(1.0 / per + 0.02 if along.x != 0 else 0.9, 0.12, 0.9 if along.x != 0 else 1.0 / per + 0.02), Color("b0a490"))


func _is_wall_at(c: Vector2i, storey: int) -> bool:
	if storey > 0:
		return world.storeys.get(storey, {}).get(c, -1) == World.IWALL
	return world.get_tile(c) in [World.IWALL, World.WALL, World.BUILDING]
