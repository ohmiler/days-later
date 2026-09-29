extends Node3D
## Step 0 of the 3D move, to walk around in: a code-made survivor on a street
## corner, zombies shambling in, the camera up high. Not the game: nothing here
## touches the real systems. Run tests/look3d/play3d.tscn with Forward+.
## WASD walk · Shift run · mouse aim · left click hit (or shoot) · right
## hold aim the pistol · 1-4 fists, machete, axe, pistol · wheel zoom ·
## N night · Z more zombies · Esc quit

const Person := preload("res://tests/look3d/person.gd")
const Pose := preload("res://tests/look3d/pose.gd")
const W := preload("res://tests/look3d/weapons.gd")

const WALK := 1.8  # m/s: a real walking pace
const RUN := 5.0
const PUNCH_TIME := 0.4

var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var torch: SpotLight3D
var lamps: Array[OmniLight3D] = []
var me: Node3D  # the survivor's holder (position, facing)
var me_sk: Skeleton3D
var phase := 0.0
var run_k := 0.0
var punch_t := -1.0
var punch_hit := false
var weapon := "fists"
var held: Node3D  # the weapon model in the right hand
var aim_k := 0.0  # 0 .. 1 the pistol raised
var kick := 0.0  # a shot's recoil, dying away
var flash: OmniLight3D
var tracer: MeshInstance3D
var tracer_t := 0.0
var aim_at = null  # (a recorded demo aims here instead of at the mouse)
var zoom := 0.45  # 0 close .. 1 far
var night := false
var bites := 0
var zombies: Array = []  # {node, sk, phase, speed, hp, down_t, fall, knock}
var help: Label
var rng := RandomNumberGenerator.new()

const SHIRTS := [Color("3a6aa8"), Color("c83a3a"), Color("e8e4dc"), Color("4a7a4a"), Color("d8a030"), Color("6a4a8a"), Color("2a2a2a"), Color("8aa0b8")]
const PANTS := [Color("2a3a5a"), Color("3a3434"), Color("4a4038"), Color("5a6a4a"), Color("1e2a4a"), Color("6a5a4a")]
const SKINS := [Color("c8906a"), Color("d8a882"), Color("b8845a"), Color("a8744e"), Color("d0a080")]


func _ready() -> void:
	rng.randomize()
	_world()
	var sk: Skeleton3D = Person.new().build({skin = Color("c8906a"), shirt = {kind = "tee", col = Color("3a6aa8")}, pants = {kind = "long", col = Color("2a3a5a")}})
	me = Node3D.new()
	add_child(me)
	me.add_child(sk)
	me_sk = sk
	torch = SpotLight3D.new()
	torch.position = Vector3(0.12, 1.25, 0.15)
	torch.rotation_degrees = Vector3(-8, 180, 0)
	torch.spot_range = 16.0
	torch.spot_angle = 24.0
	torch.light_energy = 6.0
	torch.light_color = Color("fff2d8")
	torch.shadow_enabled = true
	torch.visible = false
	me.add_child(torch)
	flash = OmniLight3D.new()
	flash.light_color = Color("ffc070")
	flash.light_energy = 0.0
	flash.omni_range = 6.0
	add_child(flash)
	tracer = MeshInstance3D.new()
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.85, 0.5)
	tracer.material_override = tm
	add_child(tracer)
	cam = Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	cam.current = true
	for i in 8:
		_spawn_zombie()
	var layer := CanvasLayer.new()
	add_child(layer)
	help = Label.new()
	help.position = Vector2(16, 12)
	var font := load("res://fonts/Kanit-Medium.ttf")
	if font:
		help.add_theme_font_override("font", font)
	help.add_theme_font_size_override("font_size", 18)
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	help.add_theme_constant_override("outline_size", 5)
	layer.add_child(help)


# --- The street ---------------------------------------------------------------

func _mat(base: Color, scale: float, seams: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform vec3 base : source_color;
uniform float scale;
uniform float seams;
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)); float a = n(p) * 0.5; p = r * p * 2.1 + 3.1; a += n(p) * 0.28; p = r * p * 2.2 + 1.7; a += n(p) * 0.14; p = r * p * 2.3; return a + n(p) * 0.08; }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = (abs(NORMAL.y) > 0.5 ? wp.xz : vec2(wp.x + wp.z, wp.y)) * scale;
	float grit = n(p * 40.0);
	vec3 c = base * (0.8 + fbm(p * 0.35) * 0.35) * (0.94 + grit * 0.1);
	c = mix(c, c * vec3(0.72, 0.7, 0.62), smoothstep(0.45, 0.8, fbm(p * 0.7 + 7.0)) * 0.55);
	if (seams > 0.0) {
		vec2 g = abs(fract(p / seams) - 0.5);
		c *= mix(0.62, 1.0, smoothstep(0.0, 0.012, 0.5 - max(g.x, g.y)));
	}
	ALBEDO = c;
	ROUGHNESS = 0.85 + grit * 0.1;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("seams", seams)
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("6a8cb8")
	sm.sky_horizon_color = Color("c8cdc8")
	sm.ground_horizon_color = Color("a8a49a")
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.fog_enabled = true
	env.fog_light_color = Color("c8c4b8")
	env.fog_density = 0.004
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -40, 0)
	sun.light_color = Color("ffe8c8")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	# Two rows of shophouse fronts facing each other across a street.
	var pave := _mat(Color("a8a296"), 1.0, 0.6)
	var kerb := _mat(Color("b8b2a6"), 1.0, 1.0)
	var road := _mat(Color("4a4b4c"), 0.6, 0.0)
	var wall := _mat(Color("d8cdb4"), 0.5, 0.0)
	var wall2 := _mat(Color("c8d0c0"), 0.5, 0.0)
	var shutter := _mat(Color("8a9098"), 2.0, 0.0)
	_box(Vector3(60, 0.15, 4), Vector3(0, -0.075, -1.5), pave)
	_box(Vector3(60, 0.15, 4), Vector3(0, -0.075, 12.5), pave)
	_box(Vector3(60, 0.15, 0.2), Vector3(0, -0.07, 0.6), kerb)
	_box(Vector3(60, 0.15, 0.2), Vector3(0, -0.07, 10.4), kerb)
	_box(Vector3(60, 0.1, 10), Vector3(0, -0.2, 5.5), road)
	for x in range(-28, 29, 4):
		var back := -3.6
		_box(Vector3(4, 7, 0.3), Vector3(x, 3.5, back), wall if (x / 4) % 2 == 0 else wall2)
		_box(Vector3(4, 7, 0.3), Vector3(x, 3.5, 14.6), wall2 if (x / 4) % 2 == 0 else wall)
		_box(Vector3(0.2, 7.2, 0.5), Vector3(x - 2, 3.6, back + 0.1), kerb)
		if (x / 4) % 3 != 1:
			for i in 11:
				_box(Vector3(3.4, 0.24, 0.08), Vector3(x, 0.14 + i * 0.26, back + 0.18), shutter)
		# Upstairs windows with grilles.
		for wx in [-0.9, 0.9]:
			_box(Vector3(1.1, 1.3, 0.06), Vector3(x + wx, 5.0, back + 0.18), _mat(Color("2a3440"), 1.0, 0.0))
	# Street lamps (lit at night).
	for x in [-16, -4, 8, 20]:
		_box(Vector3(0.12, 6.0, 0.12), Vector3(x, 3.0, 0.9), _mat(Color("7a7e84"), 2.0, 0.0))
		_box(Vector3(1.2, 0.1, 0.25), Vector3(x, 6.0, 1.4), _mat(Color("7a7e84"), 2.0, 0.0))
		var l := OmniLight3D.new()
		l.position = Vector3(x, 5.8, 1.9)
		l.omni_range = 11.0
		l.light_energy = 3.0
		l.light_color = Color("ffc890")
		l.shadow_enabled = true
		l.visible = false
		add_child(l)
		lamps.append(l)


# --- Zombies ------------------------------------------------------------------

func _spawn_zombie() -> void:
	var female := rng.randf() < 0.4
	var params := {
		zombie = true, female = female, height = rng.randf_range(1.5, 1.62) if female else rng.randf_range(1.6, 1.78),
		girth = rng.randf_range(0.92, 1.1), fat = rng.randf() * 0.5 if rng.randf() < 0.3 else 0.0,
		skin = SKINS[rng.randi() % SKINS.size()], hair_style = ["short", "long", "fringe", "bald"][rng.randi() % 4],
		shirt = {kind = ["tee", "shirt", "long", "tank"][rng.randi() % 4], col = SHIRTS[rng.randi() % SHIRTS.size()], col2 = Color("e8e4dc"), pattern = [0, 0, 1, 2, 3][rng.randi() % 5]},
		pants = {kind = ["long", "long", "shorts", "knee"][rng.randi() % 4], col = PANTS[rng.randi() % PANTS.size()]},
		grime = rng.randf_range(0.4, 0.9), blood = rng.randf_range(0.2, 1.0), torn = rng.randf_range(0.05, 0.25), seed = rng.randi() % 1000,
	}
	var sk: Skeleton3D = Person.new().build(params)
	var n := Node3D.new()
	add_child(n)
	n.add_child(sk)
	var from := me.position if me else Vector3.ZERO
	var a := rng.randf() * TAU
	n.position = Vector3(clampf(from.x + cos(a) * 14.0, -27, 27), 0, clampf(from.z + sin(a) * 6.0 + 4.0, -1.5, 12.5))
	zombies.append({node = n, sk = sk, phase = rng.randf() * TAU, speed = rng.randf_range(0.8, 1.4), hp = 3, down_t = 0.0, fall = 0.0, knock = Vector3.ZERO, tilt = rng.randf_range(-0.3, 0.3), bite_cd = 0.0})


# --- Play ---------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT and weapon == "pistol":
			if punch_t < 0.0:
				_shoot()
		elif e.button_index == MOUSE_BUTTON_LEFT and punch_t < 0.0:
			punch_t = 0.0
			punch_hit = false
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.07, 0.0, 1.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.07, 0.0, 1.0)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_N:
				_set_night(not night)
			KEY_1, KEY_2, KEY_3, KEY_4:
				_equip(["fists", "machete", "axe", "pistol"][e.keycode - KEY_1])
			KEY_Z:
				for i in 5:
					_spawn_zombie()


func _set_night(on: bool) -> void:
	night = on
	sun.light_energy = 0.06 if on else 1.25
	sun.light_color = Color("8aa0d0") if on else Color("ffe8c8")
	env.ambient_light_energy = 0.08 if on else 0.9
	(env.sky.sky_material as ProceduralSkyMaterial).sky_top_color = Color("0a1020") if on else Color("6a8cb8")
	(env.sky.sky_material as ProceduralSkyMaterial).sky_horizon_color = Color("1a2030") if on else Color("c8cdc8")
	env.fog_light_color = Color("1a2030") if on else Color("c8c4b8")
	torch.visible = on
	for l in lamps:
		l.visible = on


func _equip(kind: String) -> void:
	if held:
		held.get_parent().queue_free()
		held = null
	weapon = kind
	punch_t = -1.0
	if kind == "fists":
		return
	var att := BoneAttachment3D.new()
	me_sk.add_child(att)
	att.bone_name = "hand_r"
	held = W.build(kind)
	held.position = W.FIST
	att.add_child(held)


## A pistol shot: from the muzzle along the facing, hitting the first zombie
## near the line.
func _shoot() -> void:
	punch_t = 0.0
	punch_hit = true
	kick = 1.0
	if aim_k < 0.5:
		aim_k = 0.6  # a snap shot, raised in a hurry
	var mz: Vector3 = held.global_transform * W.KINDS.pistol.muzzle
	var fwd := Vector3(sin(me.rotation.y), 0, cos(me.rotation.y))
	var best = null
	var best_d := 25.0
	for z in zombies:
		if z.down_t > 0.0:
			continue
		var to: Vector3 = z.node.position - me.position
		to.y = 0.0
		var along := to.dot(fwd)
		if along > 0.3 and along < best_d and (to - fwd * along).length() < 0.4:
			best = z
			best_d = along
	var end := mz + fwd * best_d
	if best != null:
		best.hp -= W.KINDS.pistol.dmg
		best.knock = fwd * 2.5
		if best.hp <= 0:
			best.down_t = 6.0
			best.hp = 3
	flash.global_position = mz
	flash.light_energy = 4.0
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(mz)
	im.surface_add_vertex(Vector3(end.x, mz.y, end.z))
	im.surface_end()
	tracer.mesh = im
	tracer_t = 0.05


func _aim_point() -> Vector3:
	if aim_at != null:
		return aim_at
	var m := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(m)
	var d := cam.project_ray_normal(m)
	if absf(d.y) < 0.001:
		return me.position
	var t := (0.9 - o.y) / d.y
	return o + d * t


func _process(delta: float) -> void:
	# Moving: screen-relative WASD; the body faces the mouse.
	var dir := Vector3(Input.get_axis("ui_left", "ui_right"), 0, Input.get_axis("ui_up", "ui_down"))
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1
	if Input.is_physical_key_pressed(KEY_W): dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S): dir.z += 1
	dir = dir.limit_length(1.0)
	var running := Input.is_physical_key_pressed(KEY_SHIFT) and dir != Vector3.ZERO and punch_t < 0.0
	run_k = move_toward(run_k, 1.0 if running else 0.0, delta * 4.0)
	var aiming := weapon == "pistol" and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	aim_k = move_toward(aim_k, 1.0 if aiming else 0.0, delta * 5.0)
	kick = move_toward(kick, 0.0, delta * 7.0)
	flash.light_energy = move_toward(flash.light_energy, 0.0, delta * 60.0)
	tracer_t -= delta
	tracer.visible = tracer_t > 0.0
	if aiming:
		running = false
		run_k = move_toward(run_k, 0.0, delta * 8.0)
	var slow := 0.45 if aiming else (0.4 if punch_t >= 0.0 and weapon != "pistol" else 1.0)
	var speed := lerpf(WALK, RUN, run_k) * slow
	var step := dir * speed * delta
	me.position += step
	me.position.x = clampf(me.position.x, -27.0, 27.0)
	me.position.z = clampf(me.position.z, -3.0, 14.0)
	var aim := _aim_point() - me.position
	aim.y = 0.0
	if aim.length() > 0.2:
		me.rotation.y = lerp_angle(me.rotation.y, atan2(aim.x, aim.z), minf(1.0, delta * 14.0))
	phase += step.length() / lerpf(1.4, 2.6, run_k) * TAU
	# The legs walk (or stand); the weapon's pose goes on the upper body.
	if punch_t >= 0.0 and weapon == "fists":
		punch_t += delta
		var k := sin(clampf(punch_t / PUNCH_TIME, 0.0, 1.0) * PI)
		Pose.punch(me_sk, k)
		if not punch_hit and punch_t > PUNCH_TIME * 0.4:
			punch_hit = true
			_land_punch()
		if punch_t > PUNCH_TIME:
			punch_t = -1.0
		W.hands(me_sk, weapon)
	else:
		if dir != Vector3.ZERO:
			Pose.walk(me_sk, phase, run_k)
		else:
			Pose.stand(me_sk, Time.get_ticks_msec() / 1000.0)
		var info: Dictionary = W.KINDS[weapon]
		if punch_t >= 0.0:
			punch_t += delta
			if not punch_hit and punch_t > info.get("hit_at", 0.2):
				punch_hit = true
				_land_punch(info.get("reach", 1.3), info.get("dmg", 1))
			if punch_t > info.get("time", PUNCH_TIME):
				punch_t = -1.0
		if weapon != "fists" and not (running and punch_t < 0.0):
			W.upper(me_sk, weapon, punch_t if weapon != "pistol" else -1.0, aim_k, kick)
		W.hands(me_sk, weapon, aim_k, punch_t)
	_zombies_step(delta)
	# The camera: high and far when zoomed out, lower when zoomed in.
	var pitch := deg_to_rad(lerpf(30.0, 62.0, zoom))
	var dist := lerpf(5.0, 26.0, zoom)
	var target := me.position + Vector3(0, 1.0, 0)
	cam.position = cam.position.lerp(target + Vector3(0, sin(pitch), cos(pitch)) * dist, minf(1.0, delta * 6.0)) if cam.position != Vector3.ZERO else target
	cam.look_at(cam.position + Vector3(0, -sin(pitch), -cos(pitch)))
	var names := {fists = "มือเปล่า", machete = "มีดพร้า", axe = "ขวานดับเพลิง", pistol = "ปืนพก (คลิกขวาค้างเล็ง)"}
	help.text = "WASD เดิน · Shift วิ่ง · เมาส์หันตัว · คลิกซ้ายตี/ยิง · 1 มือ 2 มีดพร้า 3 ขวาน 4 ปืน · ล้อเมาส์ซูม · N กลางวัน/กลางคืน · Z เพิ่มซอมบี้ · Esc ออก\nถือ: %s · ซอมบี้ %d ตัว · โดนกัด %d ครั้ง · %d fps" % [names[weapon], zombies.size(), bites, Engine.get_frames_per_second()]


func _land_punch(reach := 1.3, dmg := 1) -> void:
	var fwd := Vector3(sin(me.rotation.y), 0, cos(me.rotation.y))
	for z in zombies:
		if z.down_t > 0.0:
			continue
		var to: Vector3 = z.node.position - me.position
		if to.length() < reach and to.normalized().dot(fwd) > 0.5:
			z.hp -= dmg
			z.knock = fwd * 1.8
			if z.hp <= 0:
				z.down_t = 6.0
				z.hp = 3
			return


func _zombies_step(delta: float) -> void:
	for z in zombies:
		var n: Node3D = z.node
		z.bite_cd = maxf(0.0, z.bite_cd - delta)
		n.position += z.knock * delta
		z.knock = z.knock.move_toward(Vector3.ZERO, delta * 6.0)
		if z.down_t > 0.0:
			# Knocked flat: fall back, lie there, then get up again.
			z.down_t -= delta
			z.fall = move_toward(z.fall, 1.0 if z.down_t > 1.0 else 0.0, delta * (3.0 if z.down_t > 1.0 else 1.2))
			n.rotation.x = -z.fall * PI * 0.47
			n.position.y = z.fall * 0.12
			Pose.stand(z.sk)
			continue
		n.rotation.x = 0.0
		n.position.y = 0.0
		var to: Vector3 = me.position - n.position
		to.y = 0.0
		var d := to.length()
		n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 3.0))
		if d > 0.75:
			var mv: Vector3 = to / d * z.speed * delta
			n.position += mv
			z.phase += mv.length() / 1.1 * TAU
		elif z.bite_cd <= 0.0:
			bites += 1
			z.bite_cd = 1.5
		Pose.zombie(z.sk, z.phase, z.tilt)
		# Don't stand inside each other.
		for o in zombies:
			if o != z:
				var away: Vector3 = n.position - o.node.position
				away.y = 0.0
				if away.length() < 0.55 and away.length() > 0.001:
					n.position += away.normalized() * (0.55 - away.length()) * 0.5
