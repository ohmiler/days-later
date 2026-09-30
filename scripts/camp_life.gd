class_name CampLife
extends Node2D
## Life in a refugee camp (World.camps): people and their things, so the
## grounds look lived in: tents in rows with someone sat outside, cooking
## fires, washing lines, people talking in twos, children, and soldiers on
## the gates and walking the wall. They are only drawn: they don't think,
## talk or move off their spot (the patrol walks its beat). Where they stand
## is laid out from the city's seed, the same on every machine, and those
## cells are blocked (World.blocked) so nobody walks through them.
## One CampLife node draws one thing (`data`), y-sorted with everyone else.

const BODIES := ["tshirt", "polo", "shirt_short", "tanktop", "hawaii", "pajama_top", "mohom", "shirt_long"]
const LEGS := ["shorts", "jeans", "sarong", "fisherman", "elephant", "pajama_pants", "slacks"]
const TARPS := [Color("2e6aa8"), Color("4a7a44"), Color("b89a5a"), Color("c8642a"), Color("6a6e74")]

var data: Dictionary  # {kind, cell, seed, pose, face, ...}: see plan()
var world: World
var _t := 0.0
var _look := {}


## Lay out a world's camps (fills World.camp_life and blocks those cells).
## Called from World.generate, before its paths are worked out.
static func plan(w: World) -> void:
	w.camp_life = []
	for i in w.camps.size():
		var r: Rect2i = w.camps[i].rect
		var rng := RandomNumberGenerator.new()
		rng.seed = w.city_seed * 31 + i * 7919 + 5
		_plan_camp(w, r, rng)


static func _free(w: World, c: Vector2i, r: Rect2i, taken: Dictionary) -> bool:
	if not r.grow(-2).has_point(c) or taken.has(c) or w.blocked.has(c):
		return false
	if w.get_tile(c) != World.PLAZA or w.building_at.has(c):
		return false
	var mid := r.get_center()
	if absi(c.x - mid.x) <= 3 or absi(c.y - mid.y) <= 2:
		return false  # (the ways in from the gates, and across)
	if c.distance_to(w.spawn_cell) < 5.0:
		return false  # (room round where newcomers wake up)
	for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if w.building_at.has(c + d) or w.get_tile(c + d) in [World.WALL, World.TREE]:
			return false
	for t in w.things:
		if (t.cell as Vector2i).distance_to(c) < 3.0:
			return false  # (the volunteer's table, the board: people come to them)
	return true


static func _put(w: World, kind: String, c: Vector2i, rng: RandomNumberGenerator, extra := {}, block := true) -> void:
	var rec := {kind = kind, cell = c, seed = rng.randi()}
	rec.merge(extra, true)
	w.camp_life.append(rec)
	if block:
		w.blocked[c] = true


static func _plan_camp(w: World, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var taken := {}
	# Tents: three cells by two, in rows, someone sat out in front of most.
	for y in range(r.position.y + 3, r.end.y - 4, 4):
		for x in range(r.position.x + 3, r.end.x - 4, 5):
			var cells := []
			var ok := true
			for dy in 2:
				for dx in 3:
					var c := Vector2i(x + dx, y + dy)
					if not _free(w, c, r, taken):
						ok = false
					cells.append(c)
			if not ok or rng.randf() > 0.7:
				continue
			for c in cells:
				taken[c] = true
				w.blocked[c] = true
			w.camp_life.append({kind = "tent", cell = Vector2i(x + 1, y + 1), seed = rng.randi()})
			var front := Vector2i(x + rng.randi_range(0, 2), y + 2)
			if rng.randf() < 0.8 and _free(w, front, r, taken):
				taken[front] = true
				var kid := rng.randf() < 0.25
				_put(w, "person", front, rng, {pose = "sit", face = 2, kid = kid, old = not kid and rng.randf() < 0.3})
	# Cooking fires, a cook squatting at each, people sat round.
	var fires := 0
	for tries in 60:
		if fires >= 3:
			break
		var c := Vector2i(rng.randi_range(r.position.x + 3, r.end.x - 4), rng.randi_range(r.position.y + r.size.y / 2, r.end.y - 4))
		var ring := [c, c + Vector2i.RIGHT, c + Vector2i.LEFT, c + Vector2i.DOWN]
		if ring.any(func(q): return not _free(w, q, r, taken)):
			continue
		for q in ring:
			taken[q] = true
		fires += 1
		_put(w, "fire", c, rng)
		_put(w, "person", c + Vector2i.RIGHT, rng, {pose = "squat", face = 2})
		_put(w, "person", c + Vector2i.LEFT, rng, {pose = "sit", face = 2, old = rng.randf() < 0.4})
		_put(w, "person", c + Vector2i.DOWN, rng, {pose = "sit", face = 3, kid = rng.randf() < 0.3})
	# Washing lines strung between two posts.
	var lines := 0
	for tries in 40:
		if lines >= 2:
			break
		var c := Vector2i(rng.randi_range(r.position.x + 3, r.end.x - 8), rng.randi_range(r.position.y + 3, r.end.y - 4))
		var span := [c, c + Vector2i(1, 0), c + Vector2i(2, 0), c + Vector2i(3, 0), c + Vector2i(4, 0)]
		if span.any(func(q): return not _free(w, q, r, taken)):
			continue
		for q in span:
			taken[q] = true
		lines += 1
		_put(w, "line", c, rng, {}, false)
		w.blocked[c] = true
		w.blocked[c + Vector2i(4, 0)] = true
	# People standing about in twos, talking; children.
	var pairs := 0
	for tries in 60:
		if pairs >= 4:
			break
		var c := Vector2i(rng.randi_range(r.position.x + 3, r.end.x - 4), rng.randi_range(r.position.y + 3, r.end.y - 4))
		if not _free(w, c, r, taken) or not _free(w, c + Vector2i.RIGHT, r, taken):
			continue
		taken[c] = true
		taken[c + Vector2i.RIGHT] = true
		pairs += 1
		var kids := rng.randf() < 0.3
		_put(w, "person", c, rng, {pose = "stand", face = 0, kid = kids})
		_put(w, "person", c + Vector2i.RIGHT, rng, {pose = "stand", face = 1, kid = kids, old = not kids and rng.randf() < 0.3})
	# Soldiers: two just inside each gate, looking out; one walking the wall.
	var mid := r.get_center()
	for g in [[Vector2i(0, 1), 3, 0], [Vector2i(0, -1), 2, 0], [Vector2i(1, 0), 0, 1], [Vector2i(-1, 0), 1, 1]]:
		var inward: Vector2i = g[0]
		var edge := Vector2i(mid.x, r.position.y) if inward.y > 0 else (Vector2i(mid.x, r.end.y - 1) if inward.y < 0 \
				else (Vector2i(r.position.x, mid.y) if inward.x > 0 else Vector2i(r.end.x - 1, mid.y)))
		for side in [-3, 3]:
			var c: Vector2i = edge + inward + (Vector2i(side, 0) if g[2] == 0 else Vector2i(0, side))
			if not w.building_at.has(c) and not w.get_tile(c) in [World.WALL, World.TREE]:
				_put(w, "soldier", c, rng, {face = g[1]})
	w.camp_life.append({kind = "patrol", cell = Vector2i(r.position.x + 3, r.position.y + 2), seed = rng.randi(), to = r.end.x - 4})


# --- Drawing ---------------------------------------------------------------------

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed
	match data.kind:
		"person":
			_look = Look.look_of(Look.unpack(rng.randi() % 100000))
			var wear := {body = "%s#%d" % [BODIES[rng.randi() % BODIES.size()], rng.randi() % 6],
					legs = "%s#%d" % [LEGS[rng.randi() % LEGS.size()], rng.randi() % 6], feet = "flipflops"}
			if data.get("old", false):
				_look.hair = Color("c8c4bc")
				_look.hair_style = "short"
			_look.wear = Items.wear_draw(wear)
			if data.get("kid", false):
				scale = Vector2(0.72, 0.72)
		"soldier", "patrol":
			_look = Look.look_of(Look.unpack(rng.randi() % 100000))
			_look.hair_style = "buzz"
			_look.wear = Items.wear_draw({body = "army_shirt", legs = "cargo", feet = "boots", head = "helmet"})
		"fire":
			var light := PointLight2D.new()
			light.texture = StreetProp._lamp_texture()
			light.texture_scale = 0.7
			light.color = Color("ff9a48")
			light.energy = 0.9
			light.position = Vector2(0, -6)
			light.visible = false
			light.add_to_group("night_glow")
			add_child(light)
	set_process(data.kind in ["fire", "patrol", "person", "soldier"])


func _process(delta: float) -> void:
	_t += delta
	if data.kind == "patrol":
		# Along the wall and back, at a stroll.
		var from := world.to_pos(data.cell)
		var to := world.to_pos(Vector2i(data.to, data.cell.y))
		var span := from.distance_to(to)
		var k := fmod(_t * 18.0 / span, 2.0)
		position = from.lerp(to, k if k < 1.0 else 2.0 - k) + Vector2(0, 7)
		queue_redraw()
	elif data.kind == "fire" or Engine.get_process_frames() % 6 == data.seed % 6:
		queue_redraw()  # (a fire flickers; people only breathe: every sixth frame)


func _draw() -> void:
	var breath := sin(_t * 1.5 + float(data.seed % 100)) * 0.5
	match data.kind:
		"person":
			_shadow(8.0)
			var face: int = data.get("face", 2)
			match data.get("pose", "stand"):
				"sit", "squat":
					var squat: bool = data.pose == "squat"
					var hip := Vector2(0, -6.0 if squat else -2.5)
					var feet := [Vector2(-4.2, -0.5), Vector2(4.2, -0.5)] if not squat else [Vector2(-2.5, 0), Vector2(2.5, 0)]
					var hands := [Vector2(-3.8, hip.y + 0.5), Vector2(3.8, hip.y + 0.5)] if not squat else [Vector2(-2.0, -5.5), Vector2(3.0, -6.5)]
					# (From the front or back only: side-on the rig has only the
					# getting-up motion, which reads as a kick.)
					Look.draw(self, {view = [Look.BACK if face == 3 else Look.FRONT, false], anchors = {seat = hip, hands = hands, feet = feet}}, _look)
				_:
					var view := [Look.SIDE, face == 1] if face <= 1 else [Look.FRONT if face == 2 else Look.BACK, false]
					Look.draw(self, {view = view, breath = breath}, _look)
		"soldier", "patrol":
			_shadow(8.0)
			var face: int = data.get("face", 2)
			var view := [Look.SIDE, face == 1] if face <= 1 else [Look.FRONT if face == 2 else Look.BACK, false]
			var st := {view = view, breath = breath, weapon = Items.def("shotgun").get("draw", {})}
			if data.kind == "patrol":
				var k := fmod(_t * 18.0 / maxf(1.0, world.to_pos(data.cell).distance_to(world.to_pos(Vector2i(data.to, data.cell.y)))), 2.0)
				st.view = [Look.SIDE, k >= 1.0]
				st.moving = true
				st.phase = _t * 7.0
			Look.draw(self, st, _look)
		"tent":
			_tent()
		"fire":
			_fire()
		"line":
			_line()


func _shadow(r: float) -> void:
	draw_set_transform(Vector2(0, -1), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO)


## A ridge tent seen from the front and above: the far roof slope lit, the
## near slope in shade, the door flap open on the dark inside.
func _tent() -> void:
	var col: Color = TARPS[data.seed % TARPS.size()]
	var w := 44.0
	var h := 20.0
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5, 2), Vector2(w * 0.5, 2), Vector2(w * 0.5 + 2, 5), Vector2(-w * 0.5 - 2, 5)]), Color(0, 0, 0, 0.25))
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5, -10), Vector2(w * 0.5, -10), Vector2(w * 0.5 - 4, -h - 8), Vector2(-w * 0.5 + 4, -h - 8)]), col.lightened(0.15))
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5, -10), Vector2(w * 0.5, -10), Vector2(w * 0.5, 2), Vector2(-w * 0.5, 2)]), col.darkened(0.1))
	draw_colored_polygon(PackedVector2Array([Vector2(-6, 2), Vector2(6, 2), Vector2(0, -10)]), Color("1a1814"))  # the open door
	draw_line(Vector2(-6, 2), Vector2(0, -10), col.darkened(0.35), 1.0)
	draw_line(Vector2(6, 2), Vector2(0, -10), col.darkened(0.35), 1.0)
	draw_line(Vector2(-w * 0.5 + 4, -h - 8), Vector2(w * 0.5 - 4, -h - 8), col.lightened(0.3), 1.0)  # the ridge
	for x in [-w * 0.5, w * 0.5]:
		draw_line(Vector2(x, 2), Vector2(x + signf(x) * 4, 5), Color(0.6, 0.55, 0.45), 0.6)  # guy ropes
	# Their things by the door: a bag, a bucket.
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed
	draw_rect(Rect2(10, -3, 6, 5), Color.from_hsv(rng.randf(), 0.4, 0.55))
	draw_rect(Rect2(-17, -2, 4, 4), Color("3a6aa8"))


## A cooking fire in a ring of stones, a blackened pot on it, flames that flicker.
func _fire() -> void:
	for i in 7:
		var a := TAU * i / 7.0
		draw_circle(Vector2(cos(a) * 5.5, -1.5 + sin(a) * 2.2), 1.6, Color("7a7670"))
	draw_circle(Vector2(0, -1.5), 3.5, Color("2a2420"))
	for i in 4:
		var f := sin(_t * 9.0 + i * 1.7) * 0.5 + 0.5
		var x := -2.4 + i * 1.6
		draw_colored_polygon(PackedVector2Array([Vector2(x - 1.3, -1.5), Vector2(x + 1.3, -1.5), Vector2(x + sin(_t * 6.0 + i) * 0.8, -5.5 - f * 4.0)]),
				Color(1.0, 0.55 + f * 0.3, 0.15, 0.9))
	draw_rect(Rect2(-4, -10, 8, 5), Color("2e2c2a"))  # the pot
	draw_rect(Rect2(-4.5, -10.5, 9, 1.2), Color("4a4846"))
	for i in 2:
		var k := fmod(_t * 0.5 + i * 0.5, 1.0)
		draw_circle(Vector2(sin(_t + i) * 2.0, -13 - k * 12.0), 1.5 + k * 3.0, Color(0.85, 0.85, 0.85, 0.28 * (1.0 - k)))


## A washing line between two posts, clothes pegged out along it.
func _line() -> void:
	var span := 4.0 * World.TILE
	draw_line(Vector2(0, 0), Vector2(0, -22), Color("7a5a3a"), 1.4)
	draw_line(Vector2(span, 0), Vector2(span, -22), Color("7a5a3a"), 1.4)
	var pts := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		pts.append(Vector2(span * t, -21 + sin(t * PI) * 2.5))
	draw_polyline(pts, Color(0.85, 0.85, 0.8), 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed
	for i in 6:
		var t := (i + 0.7) / 7.0
		var at := Vector2(span * t, -21 + sin(t * PI) * 2.5)
		var sway := sin(_t * 1.3 + i) * 0.6
		var col := Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.6), rng.randf_range(0.55, 0.9))
		draw_colored_polygon(PackedVector2Array([at + Vector2(-3, 0), at + Vector2(3, 0), at + Vector2(3.2 + sway, 7 + i % 2 * 2), at + Vector2(-2.8 + sway, 7 + i % 2 * 2)]), col)
