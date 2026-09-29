extends SceneTree
## Clothes patterns on 3D box people, all from code (not part of the game):
## one shader draws every pattern from the item table's own words (col,
## col2, pattern), a print is text drawn into a texture, grime and blood are
## shader numbers too.
##   godot --path . --resolution 1280x720 -s res://tests/_mock3d_cloth.gd -- --out=DIR

var root3d: Node3D
var out := "user://mock3d"

const CLOTH := """
shader_type spatial;
uniform vec4 col : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 col2 : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform int pattern = 0;  // 0 plain, 1 stripe, 2 plaid, 3 dots, 4 camo, 5 print
uniform float scale = 9.0;
uniform float grime = 0.0;  // how dirty
uniform float blood = 0.0;  // how bloodied
uniform sampler2D print_tex : source_color;
varying vec3 p;
void vertex() { p = VERTEX; }
float hash(vec2 v) { return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 v) {
	vec2 i = floor(v); vec2 f = fract(v); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 q = vec2(p.x + p.z, p.y) * scale;
	vec3 c = col.rgb;
	if (pattern == 1 && fract(q.y * 0.5) < 0.5) c = col2.rgb;
	if (pattern == 2) {
		float a = step(0.5, fract(q.x * 0.35)); float b = step(0.5, fract(q.y * 0.35));
		c = mix(col.rgb, col2.rgb, 0.35 * a + 0.35 * b);
		if (fract(q.x * 0.35) < 0.08 || fract(q.y * 0.35) < 0.08) c = col2.rgb * 0.8;
	}
	if (pattern == 3 && length(fract(q) - 0.5) < 0.22) c = col2.rgb;
	if (pattern == 4) {
		float n = noise(q * 0.35) + 0.5 * noise(q * 0.9);
		c = n < 0.6 ? col.rgb : (n < 0.95 ? col2.rgb : col2.rgb * 0.55);
	}
	if (pattern == 5 && abs(p.z) > 0.1) {
		vec2 uv = vec2(0.5 + p.x * 2.3, 0.5 - (p.y - 0.02) * 3.2);
		if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
			vec4 t = texture(print_tex, uv);
			c = mix(c, t.rgb, t.a);
		}
	}
	float g = noise(q * 0.7 + 3.1);
	c = mix(c, c * vec3(0.55, 0.5, 0.42), grime * g);
	float bl = noise(q * 0.5 + 9.7);
	if (bl < blood * 0.7) c = mix(c, vec3(0.35, 0.03, 0.02), 0.85);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""

var shader: Shader
var print_tex: Texture2D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_build.call_deferred()


func cloth(c: Color, c2: Color, pattern: int, grime := 0.0, blood := 0.0, scale := 9.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("col2", c2)
	m.set_shader_parameter("pattern", pattern)
	m.set_shader_parameter("grime", grime)
	m.set_shader_parameter("blood", blood)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("print_tex", print_tex)
	return m


func plain(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func box(size: Vector3, mat: Material, pos: Vector3, parent: Node3D, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)


## A standing person: `top`/`bottom` the shirt's and trousers' materials,
## `extra` what else they wear: "vest", "helmet", "cap", "backpack", "mask", "armguards".
func person(x: float, top: Material, bottom: Material, skin: Color, hair: Color, extra: Array, caption: String) -> void:
	var p := Node3D.new()
	p.position = Vector3(x, 0, 0)
	p.rotation_degrees.y = -18.0
	root3d.add_child(p)
	for side in [-1.0, 1.0]:
		box(Vector3(0.15, 0.82, 0.17), bottom, Vector3(side * 0.1, 0.45, 0), p)
		box(Vector3(0.16, 0.08, 0.26), plain(Color("2a2622")), Vector3(side * 0.1, 0.04, 0.04), p)
		box(Vector3(0.12, 0.3, 0.13), top, Vector3(side * 0.27, 1.26, 0), p)
		box(Vector3(0.1, 0.34, 0.11), plain(skin), Vector3(side * 0.27, 0.95, 0), p)
		if extra.has("armguards"):
			box(Vector3(0.13, 0.2, 0.14), plain(Color("3a3c40")), Vector3(side * 0.27, 0.98, 0), p)
	box(Vector3(0.42, 0.58, 0.24), top, Vector3(0, 1.16, 0), p)
	box(Vector3(0.26, 0.3, 0.26), plain(skin), Vector3(0, 1.6, 0), p)
	box(Vector3(0.28, 0.1, 0.28), plain(hair), Vector3(0, 1.74, -0.02), p)
	for side in [-1.0, 1.0]:
		box(Vector3(0.05, 0.04, 0.02), plain(Color("1a1614")), Vector3(side * 0.06, 1.62, 0.13), p)
	if extra.has("vest"):
		box(Vector3(0.46, 0.46, 0.3), cloth(Color("3a4a3a"), Color("2a342a"), 0, 0.3), Vector3(0, 1.2, 0), p)
		for i in 3:
			box(Vector3(0.1, 0.08, 0.04), plain(Color("2a342a")), Vector3(-0.13 + i * 0.13, 1.06, 0.16), p)
	if extra.has("helmet"):
		box(Vector3(0.32, 0.16, 0.32), plain(Color("4a5a3a")), Vector3(0, 1.8, 0), p)
	if extra.has("cap"):
		box(Vector3(0.29, 0.08, 0.29), plain(Color("c83a2e")), Vector3(0, 1.78, 0), p)
		box(Vector3(0.24, 0.03, 0.14), plain(Color("c83a2e")), Vector3(0, 1.75, 0.18), p)
	if extra.has("backpack"):
		box(Vector3(0.36, 0.46, 0.18), cloth(Color("4a5038"), Color("5a6a3a"), 4, 0.2), Vector3(0, 1.18, -0.22), p)
	if extra.has("mask"):
		box(Vector3(0.2, 0.12, 0.04), plain(Color("e8ecef")), Vector3(0, 1.54, 0.14), p)
	var l := Label3D.new()
	l.text = caption
	l.font_size = 48
	l.pixel_size = 0.005
	l.font = load("res://fonts/Kanit-Medium.ttf")
	l.position = Vector3(x, 2.15, 0)
	l.modulate = Color("ece4d2")
	root3d.add_child(l)


## The slogan printed on a T-shirt: drawn as text into a texture.
func _make_print() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 128)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var lab := Label.new()
	lab.text = "ไม่ตาย\nไม่เลิก"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size = Vector2(256, 128)
	lab.add_theme_font_override("font", load("res://fonts/Kanit-Bold.ttf"))
	lab.add_theme_font_size_override("font_size", 44)
	lab.add_theme_color_override("font_color", Color("f2c230"))
	vp.add_child(lab)
	root.add_child(vp)
	print_tex = vp.get_texture()


func _build() -> void:
	shader = Shader.new()
	shader.code = CLOTH
	_make_print()
	root3d = Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("262829")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c8c8d8")
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	root3d.add_child(sun)
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(20, 0.1, 6)
	ground.mesh = gm
	ground.material_override = plain(Color("5a5c5e"))
	ground.position = Vector3(0, -0.05, 0)
	root3d.add_child(ground)
	var skin := Color("a8704e")
	var zskin := Color("8a9a7a")
	person(-5.0, cloth(Color("e8e4dc"), Color("2a3a6a"), 1), cloth(Color("2a3a5a"), Color.BLACK, 0), skin, Color("1a1614"), ["cap"], "ลายทาง")
	person(-3.0, cloth(Color("8a2a26"), Color("1e1e22"), 2), cloth(Color("4a4a50"), Color.BLACK, 0), skin, Color("3a2a20"), [], "ลายสก๊อต")
	person(-1.0, cloth(Color("2a62a8"), Color("f0ece4"), 3, 0.0, 0.0, 12.0), cloth(Color("2a2a30"), Color.BLACK, 0), skin, Color("1a1614"), ["mask"], "ลายจุด")
	person(1.0, cloth(Color("4a5038"), Color("5a6a3a"), 4), cloth(Color("4a5038"), Color("5a6a3a"), 4), skin, Color("1a1614"), ["vest", "helmet", "backpack", "armguards"], "ลายพราง + เกราะ")
	person(3.0, cloth(Color("2a2c30"), Color.BLACK, 5), cloth(Color("3a4a6a"), Color.BLACK, 0), skin, Color("1a1614"), [], "เสื้อสกรีน")
	person(5.0, cloth(Color("e8e4dc"), Color("2a3a6a"), 1, 0.9, 0.8), cloth(Color("2a3a5a"), Color.BLACK, 0, 0.8, 0.4), zskin, Color("2a2622"), [], "ซอมบี้ (สกปรก+เลือด)")
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 7.4
	cam.rotation_degrees = Vector3(-22, 0, 0)
	cam.position = Vector3(0, 2.6, 5)
	root3d.add_child(cam)
	cam.current = true
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out)
	root.get_viewport().get_texture().get_image().save_png(out + "/mock3d_cloth.png")
	quit(0)
