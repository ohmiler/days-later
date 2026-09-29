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

static var on := true  # (F3; saved nowhere yet)
static var current: View3D = null

var main: Main
var city: City3D
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var chunks := {}  # Vector2i -> Node3D
var job := -1  # the chunk being built on a worker thread (WorkerThreadPool task id), -1 none
var job_cell := Vector2i.ZERO
var job_node: Node3D = null
var job_out := {}
var job_world: World = null
var bnodes := {}  # building id -> Node3D (its storeys and roof)
var people := {}  # Player or Zombie -> {holder, sk, kind, phase, last, weapon}
var doors := {}  # door id -> Node3D
var bikes := {}  # World.vehicles id -> Node3D (motorbikes and the trial car)
var pickups := {}  # pickup id -> Node3D
var corpses := {}  # cid -> Node3D
var cam_target := Vector3.ZERO
var built_for: World = null
var hidden_now: Array = []  # storey/roof nodes hidden this frame (put back next)
var overlay: Control  # names, what people say, damage numbers, the search bar: on screen, over the 3D
var blood_mm: MultiMeshInstance3D  # the blood on the ground (Main.blood)
var blood_n := -1
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
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	layer.add_child(overlay)
	blood_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 10
	disc.rings = 1
	mm.mesh = disc
	blood_mm.multimesh = mm
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.25
	blood_mm.material_override = bm
	blood_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blood_mm)
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true


func _exit_tree() -> void:
	_exit_tree_wait()
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


## The cursor for a blow or a shot, in the game's terms: if the mouse is on
## a zombie's body in 3D, the spot on its drawn 2D figure that stands for the
## same part (head, body, legs: Combat.zone_at reads it from there); else the
## ground under the mouse.
func cursor() -> Vector2:
	var m := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(m)
	var d := cam.project_ray_normal(m)
	var best: Zombie = null
	var best_t := INF
	var best_h := 0.0
	for z: Zombie in main.zombies.values():
		if not is_instance_valid(z) or z.flags & 2:
			continue
		var foot := City3D.to3(z.position, _floor_of(z))
		var tall := 1.7 * z.height
		# The ray's closest pass to the body's upright line.
		var flat := Vector2(d.x, d.z)
		if flat.length_squared() < 0.000001:
			continue
		var t := -Vector2(o.x - foot.x, o.z - foot.z).dot(flat) / flat.length_squared()
		var at := o + d * t
		var h := at.y - foot.y
		if t > 0.0 and t < best_t and Vector2(at.x - foot.x, at.z - foot.z).length() < 0.32 and h > -0.05 and h < tall + 0.08:
			best = z
			best_t = t
			best_h = h / tall
	var ground := mouse_ground()
	if best == null:
		return ground + Look.CHEST
	var k: float = best.height
	var dy: float
	if best_h > 0.84:
		dy = Proportions.head_line() * k - 2.0
	elif best_h < 0.5:
		dy = Proportions.legs_line() * k + 2.0
	else:
		dy = (Proportions.head_line() + Proportions.legs_line()) * 0.5 * k
	return best.position + Vector2(0.0, dy - best.lift)


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
	city.mat.set_shader_parameter("eye_pos", cam.global_position)
	city.mat.set_shader_parameter("you_pos", cam_target)
	_lamps()
	# The 2D film grade was made for flat colours: gentler over the 3D.
	main.grade_mat.set_shader_parameter("saturation", 1.0)
	main.grade_mat.set_shader_parameter("tint", Vector3(1.02, 1.01, 0.98))
	main.grade_mat.set_shader_parameter("vignette", 0.5)
	_sync_people(delta)
	_sync_doors()
	_sync_vehicles()
	_sync_pickups()
	_sync_corpses()
	_sync_blood()
	overlay.visible = visible
	overlay.queue_redraw()


func _exit_tree_wait() -> void:
	if job >= 0:
		WorkerThreadPool.wait_for_task_completion(job)
		job = -1
		if job_node:
			job_node.free()
			job_node = null


## Let go of the world about to be dropped (Main calls this first): wait for
## the chunk being built from it, and take everything made from it away.
func release() -> void:
	_clear()
	built_for = null
	city = null


func _clear() -> void:
	_exit_tree_wait()
	for n in chunks.values() + people.values().map(func(e): return e.holder) + doors.values() + pickups.values() + corpses.values() + bikes.values():
		if is_instance_valid(n):
			n.queue_free()
	chunks.clear()
	bnodes.clear()
	people.clear()
	doors.clear()
	bikes.clear()
	pickups.clear()
	corpses.clear()


# --- City ---------------------------------------------------------------------

func _stream(focus: Vector3) -> void:
	var here := Vector2i(int(focus.x) / World.CHUNK, int(focus.z) / World.CHUNK)
	# Nearest first.
	var want: Array[Vector2i] = []
	for dy in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var c := here + Vector2i(dx, dy)
			if c.x >= 0 and c.y >= 0 and c.x * World.CHUNK < World.W and c.y * World.CHUNK < World.H:
				want.append(c)
	want.sort_custom(func(a, b): return (a - here).length_squared() < (b - here).length_squared())
	# Chunks are built on a worker thread, one at a time (a chunk with a big
	# building takes a tenth of a second or more): the game never waits.
	if job >= 0 and WorkerThreadPool.is_task_completed(job):
		WorkerThreadPool.wait_for_task_completion(job)
		job = -1
		if job_world == main.world and job_node != null:
			add_child(job_node)
			chunks[job_cell] = job_node
			bnodes.merge(job_out)
		elif job_node != null:
			job_node.free()
		job_node = null
	if job < 0:
		for c in want:
			if not chunks.has(c):
				job_cell = c
				job_out = {}
				job_world = main.world
				var w_city := city
				var out := job_out
				job = WorkerThreadPool.add_task(func(): job_node = w_city.build_chunk(c, out))
				break
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
	env.fog_density = 0.01 if main.raining else 0.0022


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
			e = {holder = holder, sk = sk, phase = 0.0, last = p.position, weapon = "fists", held = null, spd = 0.0}
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
	if step > 2.0:
		step = 0.0  # (a jump: the stairs, a respawn, a new zone)
	# The stride follows the speed seen, so feet don't slide: a walk below
	# ~2 m/s, the game's usual pace (3.4 m/s) a jog, a sprint (6 m/s) a run.
	e.spd = lerpf(e.spd, step / maxf(delta, 0.001), minf(1.0, delta * 8.0))
	var run: float = clampf((e.spd - 1.9) / 3.6, 0.0, 1.0)
	var cycle: float = lerpf(1.4, 2.9, run)
	holder.rotation.x = 0.0
	if p is Player:
		var pl: Player = p
		holder.visible = true
		if not pl.alive():
			holder.rotation.x = -PI * 0.5 * clampf(pl.death_t / 0.6, 0.0, 1.0)
			Pose.stand(sk)
			return
		# (Your own body turns to the ground under the mouse: the aim you send
		# leans toward the part of a zombie you point at, for the hit zones.)
		var look: Vector2 = (mouse_ground() - pl.position) if pl.is_local else pl.aim
		if look.length() > 1.0:
			holder.rotation.y = lerp_angle(holder.rotation.y, atan2(look.x, look.y), minf(1.0, delta * 16.0))
		if pl.riding >= 0 and pl.riding < main.world.vehicles.size():
			var v: Dictionary = main.world.vehicles[pl.riding]
			var car := Vehicles.is_car(v)
			holder.rotation.y = _heading_of(v)
			var back := Vector3(sin(holder.rotation.y), 0, cos(holder.rotation.y)) * (-0.55 if pl.seat == 1 else -0.12)
			holder.position = City3D.to3(v.pos, _floor_of(pl) + (0.0 if car else 0.28)) + back
			Pose.ride(sk, pl.seat == 1, car)
			W.hands(sk, "fists")
			return
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
		e.phase += step / cycle * TAU
		if e.spd > 0.15:
			Pose.walk(sk, e.phase, run)
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
		e.phase += step / maxf(1.1, cycle * 0.85) * TAU
		Pose.zombie(sk, e.phase, float(z.zid % 7) * 0.08 - 0.24, run)
		if z.flags & 1:  # lunging: arms right out, leaning in
			sk.set_bone_pose_rotation(sk.find_bone("spine"), Quaternion.from_euler(Vector3(0.45, 0, 0)))


# --- Vehicles -----------------------------------------------------------------

## Which way a vehicle points, as a Y rotation (the model runs along +Z).
func _heading_of(v: Dictionary) -> float:
	var a: float = v.dir
	if not (v.get("rider", 0) != 0 or v.get("spd", 0.0) != 0.0 or v.get("view", "side") == "car"):
		# Parked: it stands in one of the old drawing's views.
		match v.get("view", "side"):
			"front": a = PI * 0.5
			"back": a = -PI * 0.5
			_: a = 0.0 if float(v.dir) > 0.0 else PI
	return atan2(cos(a), sin(a))


func _sync_vehicles() -> void:
	var w := main.world
	for v in w.vehicles:
		var id: int = v.id
		if not _near(v.pos):
			if bikes.has(id):
				bikes[id].queue_free()
				bikes.erase(id)
			continue
		var n: Node3D = bikes.get(id)
		if n == null:
			n = _car_model(v) if Vehicles.is_car(v) else _bike_model(v)
			add_child(n)
			bikes[id] = n
		n.position = City3D.to3(v.pos, city.ground_h(w.to_cell(v.pos)) if city else 0.0)
		n.rotation = Vector3(0, _heading_of(v), 0 if v.get("upright", true) else PI * 0.45)


static func _part(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, rot := Vector3.ZERO, metal := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.4 if metal > 0.0 else 0.6
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)


static func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _wheel(r: float, w: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = w
	c.radial_segments = 14
	c.rings = 1
	return c


## A Thai step-through scooter: two wheels, the body over the back one, a seat,
## a front shield and the bars.
func _bike_model(v: Dictionary) -> Node3D:
	var n := Node3D.new()
	var col := Color.from_hsv(World.hash01(v.seed, 1, 9), 0.55, 0.75)
	var dark := Color("1e1e20")
	for z in [0.62, -0.62]:
		_part(n, _wheel(0.28, 0.1), dark, Vector3(0, 0.28, z), Vector3(0, 0, PI * 0.5))
	_part(n, _boxm(Vector3(0.3, 0.32, 0.8)), col, Vector3(0, 0.52, -0.3))  # the body over the engine
	_part(n, _boxm(Vector3(0.28, 0.1, 0.62)), Color("2a2624"), Vector3(0, 0.72, -0.28))  # the seat
	_part(n, _boxm(Vector3(0.12, 0.2, 0.6)), col.darkened(0.2), Vector3(0, 0.32, 0.18))  # the floor between
	_part(n, _boxm(Vector3(0.34, 0.55, 0.12)), col, Vector3(0, 0.68, 0.45), Vector3(-0.35, 0, 0))  # the front shield
	_part(n, _boxm(Vector3(0.62, 0.04, 0.04)), Color("8a8e94"), Vector3(0, 1.02, 0.4), Vector3.ZERO, 0.7)  # the bars
	_part(n, _boxm(Vector3(0.14, 0.1, 0.06)), Color("f0eadc"), Vector3(0, 0.95, 0.5))  # the headlight
	return n


func _car_model(v: Dictionary) -> Node3D:
	var n := Node3D.new()
	var col := Color.from_hsv(World.hash01(v.seed, 1, 9), 0.5, 0.7)
	_part(n, _boxm(Vector3(1.8, 0.62, 4.5)), col, Vector3(0, 0.55, 0))
	_part(n, _boxm(Vector3(1.6, 0.55, 2.2)), Color("26303a"), Vector3(0, 1.12, -0.3), Vector3.ZERO, 0.3)
	_part(n, _boxm(Vector3(1.5, 0.05, 1.6)), col, Vector3(0, 1.42, -0.3))
	for x in [0.85, -0.85]:
		for z in [1.4, -1.4]:
			_part(n, _wheel(0.32, 0.22), Color("1a1a1c"), Vector3(x, 0.32, z), Vector3(0, 0, PI * 0.5))
	return n


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


## Blood on the ground: discs, darker as they dry (Main.blood).
func _sync_blood() -> void:
	var list: Array = main.blood
	if list.size() == blood_n:
		return
	blood_n = list.size()
	var mm := blood_mm.multimesh
	mm.instance_count = list.size()
	for i in list.size():
		var b: Array = list[i]
		var pos: Vector2 = b[0]
		var rad: float = maxf(0.08, float(b[1]) / City3D.PX * 1.4)
		var y := city.ground_h(main.world.to_cell(pos)) + 0.012 if city else 0.02
		var basis := Basis.from_scale(Vector3(rad, 1.0, rad * (0.7 + 0.3 * fmod(pos.x * 0.37, 1.0))))
		mm.set_instance_transform(i, Transform3D(basis, City3D.to3(pos, y)))
		var col: Color = b[2]
		mm.set_instance_color(i, Color(col.r * 0.8, col.g * 0.5, col.b * 0.5))


## Over the 3D, on screen: others' names and what they say, damage numbers,
## your search bar.
func _draw_overlay() -> void:
	if main == null or main.world == null or not main.in_game:
		return
	var font := UiTheme.medium()
	var local: Player = main.players.get(multiplayer.get_unique_id())
	for p: Player in main.players.values():
		if not p.alive() or not people.has(p):
			continue
		var head: Vector3 = people[p].holder.position + Vector3(0, 2.05, 0)
		if cam.is_position_behind(head):
			continue
		var s := cam.unproject_position(head)
		if p != local and p.pname != "":
			var tag := "%s · %d" % [p.pname, p.level_total]
			var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12.0
			overlay.draw_rect(Rect2(s + Vector2(-w * 0.5, -20), Vector2(w, 20)), Color(0, 0, 0, 0.45 * p.sight_k))
			overlay.draw_string(font, s + Vector2(-w * 0.5, -5), tag, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(UiTheme.PAPER, p.sight_k))
		if p.say_t > 0.0:
			var a := clampf(p.say_t / 0.6, 0.0, 1.0)
			var bw := minf(font.get_string_size(p.say, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 18.0, 320.0)
			var br := Rect2(s + Vector2(-bw * 0.5, -54), Vector2(bw, 26))
			overlay.draw_rect(br, Color(0.95, 0.93, 0.88, 0.92 * a))
			overlay.draw_string(font, br.position + Vector2(9, 19), p.say, HORIZONTAL_ALIGNMENT_LEFT, bw - 18, 16, Color(0.1, 0.1, 0.1, a))
	for dn in main.dmg_numbers:
		var k: float = dn[3] / 0.9
		var at := City3D.to3(dn[0], 1.5 + 0.6 * ease(k, 0.4))
		if cam.is_position_behind(at):
			continue
		var s := cam.unproject_position(at)
		var size := 26 if dn[2] else 20
		var col := Color(UiTheme.WARN, 1.0 - k * k) if dn[2] else Color(1, 1, 1, 1.0 - k * k)
		overlay.draw_string_outline(font, s - Vector2(40, 0), "-" + dn[1], HORIZONTAL_ALIGNMENT_CENTER, 80, size, 6, Color(0.45, 0.06, 0.04, 1.0 - k * k))
		overlay.draw_string(font, s - Vector2(40, 0), "-" + dn[1], HORIZONTAL_ALIGNMENT_CENTER, 80, size, col)
	var now := Time.get_ticks_msec() / 1000.0
	if local and people.has(local) and now < main.search_until:
		var k := 1.0 - (main.search_until - now) / main.search_total
		var s := cam.unproject_position(people[local].holder.position + Vector3(0, 2.1, 0))
		var r := Rect2(s + Vector2(-40, -8), Vector2(80, 8))
		overlay.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.7))
		overlay.draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), Color(1, 0.85, 0.4))


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
		var body: Dictionary = c.get("body", {})
		var r := RandomNumberGenerator.new()
		r.seed = cid
		var holder := Node3D.new()
		var sk: Skeleton3D = Person.new().build({detail = "low", zombie = body.has("wear") or body.has("grime"),
				height = 1.7 * float(body.get("height", 1.0)), skin = body.get("skin", Color("b88c6a")), hair = body.get("hair", Color("2a2622")),
				shirt = {kind = ["tee", "shirt", "long"][r.randi() % 3], col = body.get("shirt", Color("6a6a6a"))}, pants = {kind = "long", col = body.get("pants", Color("3a3a3a"))},
				grime = float(body.get("grime", 0.5)), blood = 0.8, seed = cid})
		holder.add_child(sk)
		Pose.stand(sk)
		# Arms flung out, a knee bent: lying as it fell.
		sk.set_bone_pose_rotation(sk.find_bone("upperarm_l"), Quaternion.from_euler(Vector3(-0.3, 0, 1.1 + r.randf() * 0.6)))
		sk.set_bone_pose_rotation(sk.find_bone("upperarm_r"), Quaternion.from_euler(Vector3(-0.2, 0, -0.9 - r.randf() * 0.8)))
		sk.set_bone_pose_rotation(sk.find_bone("thigh_l"), Quaternion.from_euler(Vector3(-0.3 * r.randf(), 0, 0.15)))
		sk.set_bone_pose_rotation(sk.find_bone("shin_l"), Quaternion.from_euler(Vector3(0.6 * r.randf(), 0, 0)))
		sk.set_bone_pose_rotation(sk.find_bone("head"), Quaternion.from_euler(Vector3(0, r.randf_range(-0.8, 0.8), 0)))
		var face_down: bool = String(c.get("style", "")) in ["kneel", "slump"] and r.randf() < 0.6
		holder.position = City3D.to3(c.pos, City3D.storey_y(c.get("storey", 0)) + 0.12)
		holder.rotation = Vector3(PI * 0.5 if face_down else -PI * 0.5, (0.0 if float(c.get("fall_dir", 1.0)) > 0.0 else PI) + r.randf_range(-0.6, 0.6), 0.0)
		add_child(holder)
		corpses[cid] = holder
