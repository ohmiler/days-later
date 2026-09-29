extends SceneTree
## Step 0 of the 3D move: people made in code, photographed on a street
## corner. Not part of the game.
##   godot --path . --rendering-method forward_plus --resolution 1600x900 -s res://tests/look3d/shoot_people.gd -- --out=DIR

const Person := preload("res://scripts/view3d/person.gd")
const Pose := preload("res://scripts/view3d/pose.gd")

var root3d: Node3D
var out := "user://look3d"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_build.call_deferred()


func _ground_mat(base: Color, scale: float, seams: float) -> ShaderMaterial:
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
	float big = fbm(p * 0.35);
	float grit = n(p * 40.0);
	vec3 c = base * (0.8 + big * 0.35) * (0.94 + grit * 0.1);
	// stains
	c = mix(c, c * vec3(0.72, 0.7, 0.62), smoothstep(0.45, 0.8, fbm(p * 0.7 + 7.0)) * 0.55);
	// slab seams
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


func box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	root3d.add_child(mi)
	return mi


func person(params: Dictionary, at: Vector3, yaw: float) -> Skeleton3D:
	var sk: Skeleton3D = Person.new().build(params)
	var holder := Node3D.new()
	holder.position = at
	holder.rotation_degrees.y = yaw
	root3d.add_child(holder)
	holder.add_child(sk)
	return sk


func machete(sk: Skeleton3D) -> void:
	var att := BoneAttachment3D.new()
	sk.add_child(att)
	att.bone_name = "hand_r"
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("b8bcc0")
	m.metallic = 0.8
	m.roughness = 0.35
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color("2a2018")
	var g := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.03, 0.12, 0.035)
	g.mesh = gm
	g.material_override = grip
	g.position = Vector3(0, -0.12, 0.01)
	att.add_child(g)
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.008, 0.45, 0.06)
	b.mesh = bm
	b.material_override = m
	b.position = Vector3(0, -0.4, 0.02)
	att.add_child(b)


func _build() -> void:
	root3d = Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("6a8cb8")
	sm.sky_horizon_color = Color("c8cdc8")
	sm.ground_horizon_color = Color("a8a49a")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.1
	e.ssao_enabled = true
	e.ssao_radius = 0.6
	e.ssil_enabled = true
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.fog_enabled = true
	e.fog_light_color = Color("c8c4b8")
	e.fog_density = 0.004
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -40, 0)
	sun.light_color = Color("ffe8c8")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	root3d.add_child(sun)

	# A pavement, a kerb, the road, and a shophouse wall with a shutter behind.
	box(Vector3(30, 0.15, 5), Vector3(0, -0.075, -1.0), _ground_mat(Color("a8a296"), 1.0, 0.6))
	box(Vector3(30, 0.15, 0.2), Vector3(0, -0.07, 1.6), _ground_mat(Color("b8b2a6"), 1.0, 1.0))
	box(Vector3(30, 0.1, 12), Vector3(0, -0.2, 7.6), _ground_mat(Color("4a4b4c"), 0.6, 0.0))
	box(Vector3(30, 7, 0.3), Vector3(0, 3.5, -3.6), _ground_mat(Color("d8cdb4"), 0.5, 0.0))
	var shutter := _ground_mat(Color("8a9098"), 2.0, 0.0)
	for i in 11:
		box(Vector3(3.4, 0.24, 0.08), Vector3(-3.0, 0.14 + i * 0.26, -3.42), shutter)

	var people := []
	var man := person({skin = Color("c8906a"), shirt = {kind = "tee", col = Color("3a6aa8"), pattern = 0}, pants = {kind = "long", col = Color("2a3a5a")}}, Vector3(-3.2, 0, 0), 10)
	Pose.stand(man)
	var woman := person({female = true, height = 1.58, skin = Color("d8a882"), hair = Color("2a1a14"), hair_style = "long",
			shirt = {kind = "long", col = Color("e8d8c8"), col2 = Color("b83a3a"), pattern = 3}, pants = {kind = "long", col = Color("3a3434")}, shoes = Color("e8e4dc")}, Vector3(-1.9, 0, 0.3), -15)
	Pose.walk(woman, 0.9)
	var student := person({height = 1.62, skin = Color("c8986e"), hair_style = "fringe", shirt = {kind = "shirt", col = Color("f0f0ec")},
			pants = {kind = "shorts", col = Color("1e2a4a")}, shoes = Color("1a1a1a")}, Vector3(-0.7, 0, -0.2), 5)
	Pose.stand(student, 1.0)
	var rider := person({skin = Color("a8744e"), shirt = {kind = "long", col = Color("4a4a4a")}, pants = {kind = "long", col = Color("2a2a2a")},
			vest = {col = Color("e86a1a"), col2 = Color("f0e8d8"), pattern = 5}}, Vector3(0.6, 0, 0.2), -20)
	Pose.punch(rider, 0.85)
	var uncle := person({girth = 1.12, fat = 0.8, height = 1.66, skin = Color("b8845a"), hair = Color("5a5650"), hair_style = "short",
			shirt = {kind = "tank", col = Color("e8e4dc")}, pants = {kind = "shorts", col = Color("6a8a5a"), col2 = Color("3a4a3a"), pattern = 2}}, Vector3(2.0, 0, 0), -10)
	Pose.walk(uncle, 2.4)
	var fighter := person({skin = Color("c0906c"), shirt = {kind = "tee", col = Color("2a2a2a"), col2 = Color("c8a030"), pattern = 5},
			pants = {kind = "long", col = Color("4a5a6a")}, grime = 0.3}, Vector3(3.4, 0, 0.4), -35)
	Pose.swing(fighter, 0.25)
	machete(fighter)
	var z1 := person({zombie = true, skin = Color("b88c6a"), hair_style = "short", shirt = {kind = "shirt", col = Color("8aa0b8"), col2 = Color("e8e4dc"), pattern = 1},
			pants = {kind = "long", col = Color("4a4038")}, grime = 0.8, blood = 0.7, torn = 0.2, seed = 7}, Vector3(4.9, 0, 1.2), -60)
	Pose.zombie(z1, 0.6)
	var z2 := person({zombie = true, female = true, height = 1.55, skin = Color("d0a080"), hair_style = "long", hair = Color("3a2a20"),
			shirt = {kind = "tee", col = Color("c83a6a"), pattern = 0}, pants = {kind = "knee", col = Color("2a2a3a")}, grime = 0.6, blood = 0.9, torn = 0.25, seed = 3}, Vector3(6.1, 0, 0.6), -70)
	Pose.zombie(z2, 2.2, -0.25)
	people = [man, woman, student, rider, uncle, fighter, z1, z2]

	var cam := Camera3D.new()
	cam.fov = 30.0
	root3d.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(out)
	# 1: the line-up, close and low (the most zoomed-in the game would go).
	cam.position = Vector3(1.5, 1.8, 11.5)
	cam.look_at(Vector3(1.5, 0.95, 0.2))
	await _shot("people_close.png")
	# 2: nearer still, to see faces and hands (what the closest zoom must not reach).
	cam.fov = 22.0
	cam.position = Vector3(-1.2, 1.55, 4.2)
	cam.look_at(Vector3(-1.3, 1.25, 0.0))
	await _shot("people_faces.png")
	# 3: the play view: high up, as in the game now.
	cam.fov = 35.0
	cam.position = Vector3(1.4, 11.0, 10.0)
	cam.look_at(Vector3(1.4, 0.5, 0.3))
	await _shot("people_play.png")
	# 4: a walk cycle, frame by frame on one man (strip).
	for i in people.size():
		(people[i] as Skeleton3D).get_parent().visible = i == 0
	var strip: Array[Image] = []
	cam.fov = 30.0
	cam.position = Vector3(-3.2 + 4.6, 1.1, 0.0)
	cam.look_at(Vector3(-3.2, 0.9, 0.0))
	man.get_parent().rotation_degrees.y = 0
	for f in 6:
		Pose.walk(man, f * TAU / 6.0, 0.0)
		strip.append(await _grab())
	for f in 6:
		Pose.walk(man, f * TAU / 6.0, 1.0)
		strip.append(await _grab())
	_save_strip(strip, 6, "walk_run.png")
	# 5: the head up close, side and three-quarter (checking the shape).
	Pose.stand(man)
	var heads: Array[Image] = []
	cam.fov = 12.0
	for yaw in [0.0, 45.0, 90.0]:
		man.get_parent().rotation_degrees.y = yaw
		cam.position = Vector3(-3.2 + 2.2, 1.62, 0.0)
		cam.look_at(Vector3(-3.2, 1.55, 0.0))
		heads.append(await _grab())
	_save_strip(heads, 3, "heads.png")
	quit(0)


func _grab() -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


func _shot(file: String) -> void:
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + "/" + file)


func _save_strip(imgs: Array[Image], cols: int, file: String) -> void:
	var w := imgs[0].get_width()
	var h := imgs[0].get_height()
	var cw := int(w * 0.28)
	var cx := int((w - cw) / 2)
	var rows := ceili(imgs.size() / float(cols))
	var sheet := Image.create(cw * cols, h * rows, false, imgs[0].get_format())
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(cx, 0, cw, h), Vector2i((i % cols) * cw, (i / cols) * h))
	sheet.resize(sheet.get_width() / 2, sheet.get_height() / 2)
	sheet.save_png(out + "/" + file)
