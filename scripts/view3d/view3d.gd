class_name View3D
extends Node3D
## The game seen in 3D (ROADMAP "ย้ายเป็น 3D", round 1). It draws; it decides
## nothing. Every frame it reads what Main already knows (the world, the
## players, the zombies, doors, corpses, the clock) and shows it: the city a
## chunk at a time around you, the people as code-made bodies. The 2D drawing
## is hidden while this is on (F3 switches between them).

const Person := preload("res://scripts/view3d/person.gd")
const Pose := preload("res://scripts/view3d/pose.gd")
const W := preload("res://scripts/view3d/weapons.gd")

const RADIUS := 3  # chunks each way from the one you're in
const BUILD_PER_FRAME := 2  # new chunks made per frame at most (no hitch walking on)

static var on := true  # (F3; saved nowhere yet)
static var current: View3D = null

var main: Main
var city: City3D
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var chunks := {}  # Vector2i -> Node3D
var bnodes := {}  # building id -> Node3D (its storeys and roof)
var people := {}  # Player or Zombie -> {holder, sk, kind, phase, last, weapon}
var doors := {}  # door id -> Node3D
var pickups := {}  # pickup id -> Node3D
var corpses := {}  # cid -> Node3D
var cam_target := Vector3.ZERO
var built_for: World = null
var hidden_now: Array = []  # storey/roof nodes hidden this frame (put back next)
var lamps: Array[OmniLight3D] = []  # the nearest lit spots at night (World.light_spots)
const LAMPS := 12


func _ready() -> void:
	current = self
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.fog_enabled = true
	env.fog_density = 0.004
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	we.environment = env
	for i in LAMPS:
		var l := OmniLight3D.new()
		l.light_color = Color("ffc890")
		l.light_energy = 2.2
		l.shadow_enabled = i < 4
		l.visible = false
		add_child(l)
		lamps.append(l)
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true


func _exit_tree() -> void:
	if current == self:
		current = null


## Where on screen a point of the game (pixels on the ground, up `lift` px) is.
static func screen_of(vp: Viewport, pos: Vector2, lift := 0.0) -> Vector2:
	if current and current.visible and current.cam:
		return current.cam.unproject_position(City3D.to3(pos, lift / City3D.PX + 1.0))
	return vp.get_canvas_transform() * pos


## The point on the ground (game pixels) under the mouse, at chest height.
func mouse_ground(height := 1.2) -> Vector2:
	var m := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(m)
	var d := cam.project_ray_normal(m)
	if absf(d.y) < 0.0001:
		return City3D.to2(o)
	return City3D.to2(o + d * ((height - o.y) / d.y))


func _process(delta: float) -> void:
	if main == null or main.world == null:
		return
	if built_for != main.world:
		_clear()
		built_for = main.world
		city = City3D.new(main.world)
	var me: Player = main.players.get(multiplayer.get_unique_id()) if main.in_game else null
	var focus := City3D.to3(main.camera.position) if me == null else City3D.to3(me.position, _floor_of(me))
	cam_target = cam_target.lerp(focus, 1.0 - exp(-10.0 * delta)) if cam_target.distance_to(focus) < 6.0 else focus
	_stream(focus)
	_camera()
	_light()
	_cutaway(me)
	_lamps()
	# The 2D film grade was made for flat colours: gentler over the 3D.
	main.grade_mat.set_shader_parameter("saturation", 1.0)
	main.grade_mat.set_shader_parameter("tint", Vector3(1.02, 1.01, 0.98))
	main.grade_mat.set_shader_parameter("vignette", 0.5)
	_sync_people(delta)
	_sync_doors()
	_sync_pickups()
	_sync_corpses()


func _clear() -> void:
	for n in chunks.values() + people.values().map(func(e): return e.holder) + doors.values() + pickups.values() + corpses.values():
		if is_instance_valid(n):
			n.queue_free()
	chunks.clear()
	bnodes.clear()
	people.clear()
	doors.clear()
	pickups.clear()
	corpses.clear()


# --- City ---------------------------------------------------------------------

func _stream(focus: Vector3) -> void:
	var here := Vector2i(int(focus.x) / World.CHUNK, int(focus.z) / World.CHUNK)
	var made := 0
	# Nearest first.
	var want: Array[Vector2i] = []
	for dy in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var c := here + Vector2i(dx, dy)
			if c.x >= 0 and c.y >= 0 and c.x * World.CHUNK < World.W and c.y * World.CHUNK < World.H:
				want.append(c)
	want.sort_custom(func(a, b): return (a - here).length_squared() < (b - here).length_squared())
	for c in want:
		if not chunks.has(c) and made < BUILD_PER_FRAME:
			var n := city.build_chunk(c, bnodes)
			add_child(n)
			chunks[c] = n
			made += 1
	for c: Vector2i in chunks.keys():
		if absi(c.x - here.x) > RADIUS + 1 or absi(c.y - here.y) > RADIUS + 1:
			var n: Node3D = chunks[c]
			for b in bnodes.keys():
				if not is_instance_valid(bnodes[b]) or bnodes[b].get_parent() == n:
					bnodes.erase(b)
			n.queue_free()
			chunks.erase(c)


func _camera() -> void:
	# The 2D zoom (mouse wheel, 1..6) sets how close: in close, the camera comes
	# down lower; out far, it looks down from high up.
	var z := clampf((main.camera.zoom.x - 1.0) / 5.0, 0.0, 1.0)
	var pitch := deg_to_rad(lerpf(62.0, 34.0, z))
	var dist := lerpf(34.0, 7.0, z)
	var at := cam_target + Vector3(0, 1.0, 0)
	cam.position = at + Vector3(0, sin(pitch), cos(pitch)) * dist
	cam.look_at(at)


## Sun and sky from the game's clock (Main.time: 0..1 through the day).
func _light() -> void:
	var hour := fmod(main.time * 24.0 + 2.4, 24.0)
	var day := clampf((hour - 6.0) / 12.5, 0.0, 1.0)
	var up := sin(day * PI)
	var sky_col: Color = Main.sky_color(main.time, main.raining)
	var night := hour < 5.8 or hour > 19.0
	sun.rotation = Vector3(-lerpf(0.12, 1.45, up) if not night else -0.9, lerpf(-1.4, 1.4, day), 0.0)
	sun.light_color = Color("8aa4d8") if night else sky_col.lerp(Color("fff0d8"), up)
	sun.light_energy = (0.22 if night else lerpf(0.35, 1.25, up)) * (0.55 if main.raining else 1.0)
	env.ambient_light_energy = 0.3 if night else lerpf(0.4, 0.9, up)
	sky_mat.sky_top_color = sky_col * Color(0.55, 0.65, 0.85) if not night else Color("0a1020")
	sky_mat.sky_horizon_color = sky_col if not night else Color("1a2030")
	sky_mat.ground_horizon_color = sky_col.darkened(0.2)
	env.fog_light_color = sky_col.darkened(0.1)
	env.fog_density = 0.012 if main.raining else 0.004


## Take away what stands between the camera and you: in a building, its
## floors above you and its roof; out on the street, the fronts of the
## buildings on the camera's side of you.
func _cutaway(me: Player) -> void:
	for n in hidden_now:
		if is_instance_valid(n):
			n.visible = true
	hidden_now.clear()
	if me == null:
		return
	var at := main.world.to_cell(me.position)
	var inside_id := -1
	if main.world.building_at.has(at):
		inside_id = main.world.building_at[at].data.id
	for id in bnodes:
		var bn: Node3D = bnodes[id]
		if not is_instance_valid(bn):
			continue
		var r: Rect2i = main.world.buildings[id].rect
		var mine: bool = id == inside_id
		# In front of you (toward the camera), close by?
		var front: bool = r.position.y > at.y - 1 and r.position.y < at.y + 14 and r.end.x > at.x - 7 and r.position.x < at.x + 7
		if not mine and not front:
			continue
		for child in bn.get_children():
			var hide := false
			if child.name == "roof":
				hide = true
			elif child.name.begins_with("s"):
				var f := int(String(child.name).substr(1))
				hide = f > me.storey if mine else f >= 0
			if hide and child.visible:
				child.visible = false
				hidden_now.append(child)


## Street lamps and lit rooms (the same spots zombies see you by), the nearest few.
func _lamps() -> void:
	var spots: Array = []
	if main.world.is_night:
		var at := City3D.to2(cam_target)
		spots = main.world.light_spots.filter(func(s): return (s.size() < 3 or main.world.powered.has(s[2])) and (s[0] as Vector2).distance_to(at) < 30.0 * City3D.PX)
		spots.sort_custom(func(a, b): return (a[0] as Vector2).distance_to(at) < (b[0] as Vector2).distance_to(at))
	for i in LAMPS:
		var l := lamps[i]
		l.visible = i < spots.size()
		if l.visible:
			var s: Array = spots[i]
			var indoor: bool = s.size() > 2 and s[2] != null
			l.position = City3D.to3(s[0], 2.6 if indoor else 5.5)
			l.omni_range = maxf(4.0, s[1] / City3D.PX * 1.4)


func _floor_of(p) -> float:
	if p is Player and p.on_roof:
		var b = main.world.building_at.get(main.world.to_cell(p.position))
		return City3D.storey_y(b.data.get("floors", 1)) if b else 0.0
	var s: int = p.storey
	if s > 0:
		return City3D.storey_y(s)
	return city.ground_h(main.world.to_cell(p.position)) if city else 0.0


# --- People ---------------------------------------------------------------------

func _weapon_of(id: String) -> String:
	if id == "":
		return "fists"
	var d: Dictionary = Items.def(id)
	if d.get("type", "") == "gun":
		return "pistol"
	if id in ["axe", "fireaxe"]:
		return "axe"
	return "machete"


func _body_of(p) -> Dictionary:
	if p is Player:
		var lk: Dictionary = p.look
		var tall: float = lk.get("tall", 1.0) * Look.FULL_HEIGHT
		return {height = tall, female = tall < 1.62, skin = p.skin, hair = p.hair, shirt = {kind = "tee", col = p.shirt},
				pants = {kind = "long", col = p.pants}, girth = lk.get("build", 1.0), hair_style = ["short", "long", "long", "fringe", "bald"][Look.HAIR_STYLES.find(lk.get("hair_style", "short")) if Look.HAIR_STYLES.has(lk.get("hair_style", "short")) else 0]}
	var z: Zombie = p
	var r := RandomNumberGenerator.new()
	r.seed = z.zid
	return {zombie = true, detail = "low", height = 1.7 * z.height, female = r.randf() < 0.4, skin = z.skin, hair = z.hair,
			shirt = {kind = ["tee", "shirt", "long", "tank"][r.randi() % 4], col = z.shirt, col2 = Color("e8e4dc"), pattern = [0, 0, 1, 2, 3][r.randi() % 5]},
			pants = {kind = ["long", "long", "shorts", "knee"][r.randi() % 4], col = z.pants},
			grime = z.grime, blood = r.randf_range(0.2, 1.0), torn = r.randf_range(0.05, 0.25), seed = z.zid,
			girth = Zombie.KINDS.get(z.kind, {}).get("girth", 1.0), fat = 0.7 if z.kind == "fat" else 0.0}


func _sync_people(delta: float) -> void:
	var seen := {}
	var built := 0
	for p in main.players.values() + main.zombies.values():
		if not is_instance_valid(p):
			continue
		seen[p] = true
		var e = people.get(p)
		if e == null:
			if built >= 6 and p is Zombie:
				continue  # (a few new bodies a frame)
			built += 1
			var holder := Node3D.new()
			var sk: Skeleton3D = Person.new().build(_body_of(p))
			holder.add_child(sk)
			add_child(holder)
			e = {holder = holder, sk = sk, phase = 0.0, last = p.position, weapon = "fists", held = null}
			people[p] = e
		_pose(p, e, delta)
	for p in people.keys():
		if not seen.has(p):
			people[p].holder.queue_free()
			people.erase(p)


func _pose(p, e: Dictionary, delta: float) -> void:
	var holder: Node3D = e.holder
	var sk: Skeleton3D = e.sk
	holder.position = City3D.to3(p.position, _floor_of(p))
	var step: float = (p.position - e.last).length() / City3D.PX
	e.last = p.position
	holder.rotation.x = 0.0
	if p is Player:
		var pl: Player = p
		holder.visible = true
		if not pl.alive():
			holder.rotation.x = -PI * 0.5 * clampf(pl.death_t / 0.6, 0.0, 1.0)
			Pose.stand(sk)
			return
		if pl.aim.length() > 1.0:
			holder.rotation.y = lerp_angle(holder.rotation.y, atan2(pl.aim.x, pl.aim.y), minf(1.0, delta * 16.0))
		var want := _weapon_of(pl.weapon_id)
		if want != e.weapon:
			if e.held:
				e.held.get_parent().queue_free()
				e.held = null
			e.weapon = want
			if want != "fists":
				var att := BoneAttachment3D.new()
				sk.add_child(att)
				att.bone_name = "hand_r"
				e.held = W.build(want)
				e.held.position = W.FIST
				att.add_child(e.held)
		e.phase += step / lerpf(1.4, 2.6, pl.run_k) * TAU
		if pl.moving or step > 0.002:
			Pose.walk(sk, e.phase, pl.run_k)
		else:
			Pose.stand(sk, Time.get_ticks_msec() / 1000.0)
		var attack := -1.0
		var track: float = W.KINDS[e.weapon].get("time", 0.4)
		if pl.anim != Look.NONE and pl.anim_t < track:
			attack = pl.anim_t
		if e.weapon == "fists" and attack >= 0.0:
			Pose.punch(sk, sin(clampf(pl.anim_t / 0.35, 0.0, 1.0) * PI))
		elif e.weapon != "fists":
			W.upper(sk, e.weapon, attack if e.weapon != "pistol" else -1.0, 1.0 if pl.aiming else 0.0)
		W.hands(sk, e.weapon, 1.0 if pl.aiming else 0.0, attack)
	else:
		var z: Zombie = p
		holder.visible = z.sight_k > 0.05
		holder.rotation.y = lerp_angle(holder.rotation.y, atan2(cos(z.facing), sin(z.facing)), minf(1.0, delta * 8.0))
		if z.flags & 2:
			holder.rotation.x = -PI * 0.47
			Pose.stand(sk)
			return
		e.phase += step / 1.1 * TAU
		Pose.zombie(sk, e.phase, float(z.zid % 7) * 0.08 - 0.24)
		if z.flags & 1:  # lunging: arms right out, leaning in
			sk.set_bone_pose_rotation(sk.find_bone("spine"), Quaternion.from_euler(Vector3(0.45, 0, 0)))


# --- Doors, things on the ground, the dead --------------------------------------

func _near(pos: Vector2) -> bool:
	return City3D.to3(pos).distance_to(cam_target) < (RADIUS + 0.5) * World.CHUNK


func _sync_doors() -> void:
	var w := main.world
	for id in w.doors.size():
		var d: Dictionary = w.doors[id]
		var pos := w.to_pos(d.cell)
		if not _near(pos):
			if doors.has(id):
				doors[id].queue_free()
				doors.erase(id)
			continue
		var n: Node3D = doors.get(id)
		if n == null:
			n = _door_node(d)
			add_child(n)
			doors[id] = n
		var shut: bool = d.closed and not d.get("broken", false)
		if not n.has_meta("shut") or n.get_meta("shut") != shut:
			n.set_meta("shut", shut)
			if d.kind == "shutter":
				n.get_child(0).scale.y = 1.0 if shut else 0.12
				n.get_child(0).position.y = (City3D.DOOR_H + 0.4) * (0.5 if shut else 0.95)
			else:
				n.get_child(0).rotation.y = 0.0 if shut else -PI * 0.5
		n.visible = d.get("storey", 0) == 0 or true


func _door_node(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var c: Vector2i = d.cell
	var w := main.world
	var across := w.get_tile(c + Vector2i.LEFT) in [World.IWALL, World.WALL, World.DOOR] or w.get_tile(c + Vector2i.RIGHT) in [World.IWALL, World.WALL, World.DOOR]
	n.position = Vector3(c.x + 0.5, city.ground_h(c) if city else 0.0, c.y + 0.5)
	n.rotation.y = 0.0 if across else PI * 0.5
	var leaf := MeshInstance3D.new()
	var b := BoxMesh.new()
	var m := StandardMaterial3D.new()
	if d.kind == "shutter":
		b.size = Vector3(1.0, City3D.DOOR_H + 0.4, 0.06)
		m.albedo_color = Color("8a9098")
		m.metallic = 0.5
		leaf.position = Vector3(0, (City3D.DOOR_H + 0.4) * 0.5, 0)
	elif d.kind == "window":
		b.size = Vector3(0.9, 1.1, 0.04)
		m.albedo_color = Color(0.5, 0.6, 0.7, 0.5)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		leaf.position = Vector3(0, 1.5, 0)
	else:
		# A door on its hinge at one side: the leaf's middle sits half a door off.
		var hinge := Node3D.new()
		hinge.position = Vector3(-0.45, 0, 0)
		n.add_child(hinge)
		b.size = Vector3(0.9, City3D.DOOR_H - 0.05, 0.05)
		m.albedo_color = Color("7a5a3a")
		leaf.position = Vector3(0.45, (City3D.DOOR_H - 0.05) * 0.5, 0)
		leaf.mesh = b
		leaf.material_override = m
		hinge.add_child(leaf)
		return n
	leaf.mesh = b
	leaf.material_override = m
	n.add_child(leaf)
	return n


func _sync_pickups() -> void:
	for id in pickups.keys():
		if not main.pickups.has(id):
			pickups[id].queue_free()
			pickups.erase(id)
	for id in main.pickups:
		var pu: Dictionary = main.pickups[id]
		if pickups.has(id) or not _near(pu.pos):
			continue
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.3, 0.15, 0.25)
		mi.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("c8a060")
		m.emission_enabled = true
		m.emission = Color("403010")
		mi.material_override = m
		mi.position = City3D.to3(pu.pos, City3D.storey_y(pu.get("storey", 0)) + 0.18)
		add_child(mi)
		pickups[id] = mi


func _sync_corpses() -> void:
	for cid in corpses.keys():
		if not main.corpses.has(cid):
			corpses[cid].queue_free()
			corpses.erase(cid)
	for cid in main.corpses:
		if corpses.has(cid):
			continue
		var c: Dictionary = main.corpses[cid]
		if not c.has("pos") or not _near(c.pos):
			continue
		var mi := MeshInstance3D.new()
		var b := CapsuleMesh.new()
		b.radius = 0.2
		b.height = 1.6
		mi.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("5a4a40")
		mi.material_override = m
		mi.position = City3D.to3(c.pos, City3D.storey_y(c.get("storey", 0)) + 0.18)
		mi.rotation = Vector3(0, float(cid % 7), PI * 0.5)
		add_child(mi)
		corpses[cid] = mi
