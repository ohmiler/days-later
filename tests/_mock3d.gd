extends SceneTree
## A look at the game in real 3D, everything made from code in Godot (no
## Blender, no image files): a Bangkok shophouse row, a survivor with a
## machete, zombies, a car, a tree, lit by the sun. Not part of the game.
##   godot --path . --resolution 1280x720 -s res://tests/_mock3d.gd -- --out=DIR

var root3d: Node3D
var out := "user://mock3d"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_build.call_deferred()


func _mat(col: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func box(size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation_degrees = rot
	(parent if parent else root3d).add_child(mi)
	return mi


func cyl(r: float, h: float, col: Color, pos: Vector3, rot := Vector3.ZERO, sides := 10, parent: Node3D = null, r_top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r if r_top < 0.0 else r_top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	mi.mesh = c
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation_degrees = rot
	(parent if parent else root3d).add_child(mi)
	return mi


func blob(r: float, col: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.7
	s.radial_segments = 7
	s.rings = 4
	mi.mesh = s
	mi.material_override = _mat(col)
	mi.position = pos
	root3d.add_child(mi)


## A box narrower at the top (a car's cabin): bottom w x d, top inset.
func frustum(size: Vector3, top_in: Vector2, col: Color, pos: Vector3, parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var b := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var t := [Vector3(-hx + top_in.x, size.y, -hz + top_in.y), Vector3(hx - top_in.x * 0.4, size.y, -hz + top_in.y),
			Vector3(hx - top_in.x * 0.4, size.y, hz - top_in.y), Vector3(-hx + top_in.x, size.y, hz - top_in.y)]
	var quads := [[t[0], t[1], t[2], t[3]], [b[0], b[1], t[1], t[0]], [b[1], b[2], t[2], t[1]], [b[2], b[3], t[3], t[2]], [b[3], b[0], t[0], t[3]]]
	for q in quads:
		for tri in [[q[0], q[2], q[1]], [q[0], q[3], q[2]]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(col, 0.3)
	mi.position = pos
	parent.add_child(mi)


## A person made of boxes (1.7 m, 1:5 heads), in a walking stride.
func person(at: Vector3, yaw: float, skin: Color, shirt: Color, pants: Color, hair: Color, zombie := false, machete := false) -> void:
	var p := Node3D.new()
	p.position = at
	p.rotation_degrees.y = yaw
	root3d.add_child(p)
	var stride := 22.0
	# Legs (and shoes), swinging.
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.1, 0.86, 0)
		hip.rotation_degrees.x = stride * side
		p.add_child(hip)
		box(Vector3(0.15, 0.82, 0.17), pants, Vector3(0, -0.41, 0), Vector3.ZERO, hip)
		box(Vector3(0.16, 0.08, 0.26), Color("2a2622"), Vector3(0, -0.84, -0.04), Vector3.ZERO, hip)
	# Body: the shirt over the torso.
	box(Vector3(0.42, 0.58, 0.24), shirt, Vector3(0, 1.16, 0), Vector3(8 if zombie else 0, 0, 0), p)
	# Arms: a zombie's reaching out, a survivor's swinging (one raising the blade).
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.27, 1.4, 0)
		sh.rotation_degrees.x = -80.0 if zombie else (-stride * side if not (machete and side > 0) else -120.0)
		p.add_child(sh)
		box(Vector3(0.12, 0.3, 0.13), shirt, Vector3(0, -0.14, 0), Vector3.ZERO, sh)
		box(Vector3(0.1, 0.34, 0.11), skin, Vector3(0, -0.45, 0), Vector3.ZERO, sh)
		if machete and side > 0:
			box(Vector3(0.04, 0.14, 0.05), Color("2a2420"), Vector3(0, -0.66, 0.02), Vector3.ZERO, sh)
			box(Vector3(0.015, 0.5, 0.07), Color("b8bcc0"), Vector3(0, -0.98, 0.04), Vector3.ZERO, sh)
	# Head, hair, eyes.
	var head := Node3D.new()
	head.position = Vector3(0, 1.6, -0.02 if not zombie else -0.08)
	head.rotation_degrees.x = 12.0 if zombie else 0.0
	p.add_child(head)
	box(Vector3(0.26, 0.3, 0.26), skin, Vector3(0, 0, 0), Vector3.ZERO, head)
	box(Vector3(0.28, 0.1, 0.28), hair, Vector3(0, 0.14, 0.02), Vector3.ZERO, head)
	for side in [-1.0, 1.0]:
		box(Vector3(0.05, 0.04, 0.02), Color("e8e0c8") if zombie else Color("1a1614"), Vector3(side * 0.06, 0.02, -0.13), Vector3.ZERO, head)
	# Its shadow falls from the sun.


## A car of boxes, as CarArt draws it, but real.
func car(at: Vector3, yaw: float, col: Color) -> void:
	var c := Node3D.new()
	c.position = at
	c.rotation_degrees.y = yaw
	root3d.add_child(c)
	box(Vector3(4.5, 0.62, 1.8), col, Vector3(0, 0.5, 0), Vector3.ZERO, c)
	box(Vector3(0.16, 0.34, 1.7), col.darkened(0.45), Vector3(2.3, 0.38, 0), Vector3.ZERO, c)
	box(Vector3(0.16, 0.34, 1.7), col.darkened(0.45), Vector3(-2.3, 0.38, 0), Vector3.ZERO, c)
	frustum(Vector3(2.2, 0.62, 1.66), Vector2(0.45, 0.14), Color("243240"), Vector3(-0.35, 0.81, 0), c)
	box(Vector3(1.5, 0.05, 1.42), col, Vector3(-0.22, 1.44, 0), Vector3.ZERO, c)  # the roof
	for x in [1.4, -1.4]:
		for z in [0.88, -0.88]:
			cyl(0.32, 0.22, Color("1a1a1c"), Vector3(x, 0.32, z), Vector3(90, 0, 0), 12, c)
	for z in [0.6, -0.6]:
		box(Vector3(0.05, 0.12, 0.34), Color("fff4d0"), Vector3(2.38, 0.6, z), Vector3.ZERO, c)
		box(Vector3(0.05, 0.12, 0.34), Color("c8201c"), Vector3(-2.38, 0.6, z), Vector3.ZERO, c)


## A row of shophouses (4 m wide units, 2 storeys and a roof terrace).
func shophouse(x: float, sign_text: String, sign_col: Color, open: bool) -> void:
	var z := -6.0
	box(Vector3(4.0, 7.0, 12.0), Color("d8cdb8"), Vector3(x, 3.5, z - 6.0 + 0.0))
	box(Vector3(4.0, 0.25, 12.2), Color("a8a090"), Vector3(x, 7.1, z - 6.0))
	box(Vector3(0.18, 7.3, 12.2), Color("b8ae98"), Vector3(x - 2.0, 3.6, z - 6.0))  # the party wall
	# The ground floor front: a rolling shutter, half up or down.
	if open:
		box(Vector3(3.4, 0.9, 0.12), Color("8a8e94"), Vector3(x, 2.75, z + 0.02))
		box(Vector3(3.4, 2.3, 0.05), Color("2a2622"), Vector3(x, 1.15, z + 0.0))
		box(Vector3(1.2, 0.9, 0.5), Color("3a8a8a"), Vector3(x - 0.9, 0.45, z + 0.6))  # a shelf out front
	else:
		for i in 12:
			box(Vector3(3.4, 0.24, 0.1), Color("9aa0a6") if i % 2 == 0 else Color("868c92"), Vector3(x, 0.14 + i * 0.26, z + 0.03))
	# The sign board and its words.
	box(Vector3(3.8, 0.7, 0.12), sign_col, Vector3(x, 3.6, z + 0.1))
	var l := Label3D.new()
	l.text = sign_text
	l.font_size = 64
	l.pixel_size = 0.006
	l.modulate = Color.WHITE
	l.outline_size = 0
	l.position = Vector3(x, 3.6, z + 0.17)
	l.font = load("res://fonts/Kanit-Medium.ttf") if ResourceLoader.exists("res://fonts/Kanit-Medium.ttf") else null
	root3d.add_child(l)
	# Upstairs: windows with grilles, an air conditioner.
	for wx in [-0.9, 0.9]:
		box(Vector3(1.1, 1.3, 0.06), Color("2a3440"), Vector3(x + wx, 5.2, z + 0.02))
		for gx in 4:
			box(Vector3(0.03, 1.3, 0.04), Color("5a5a5a"), Vector3(x + wx - 0.45 + gx * 0.3, 5.2, z + 0.07))
	box(Vector3(0.8, 0.5, 0.35), Color("e8e4dc"), Vector3(x + 1.2, 4.2, z + 0.2))


func tree(at: Vector3) -> void:
	cyl(0.16, 3.0, Color("5a4030"), at + Vector3(0, 1.5, 0), Vector3.ZERO, 7, null, 0.12)
	blob(1.3, Color("3a6a3a"), at + Vector3(0, 3.4, 0))
	blob(1.0, Color("4a7a40"), at + Vector3(0.9, 3.0, 0.4))
	blob(0.9, Color("356030"), at + Vector3(-0.8, 3.1, -0.3))


func _build() -> void:
	root3d = Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a2c2e")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b8b8c8")
	e.ambient_light_energy = 0.4
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("fff0d8")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	root3d.add_child(sun)
	# The street: road, lane marks, kerb and pavement.
	box(Vector3(40, 0.1, 9), Color("3a3c3e"), Vector3(0, -0.05, 4.5))
	for i in 8:
		box(Vector3(1.6, 0.02, 0.15), Color("d8d4c8"), Vector3(-16 + i * 4.5, 0.01, 4.5))
	box(Vector3(40, 0.18, 3), Color("a8a296"), Vector3(0, 0.09, -1.5 - 3.0 + 3.0 - 3.0 + 1.5))
	box(Vector3(40, 0.2, 0.2), Color("c83a2e"), Vector3(0, 0.1, -0.05))
	box(Vector3(40, 0.1, 30), Color("4a5a3a"), Vector3(0, -0.12, -20))
	shophouse(-6.0, "ร้านขายยา", Color("2a9a5a"), true)
	shophouse(-2.0, "ร้านทอง", Color("c8201c"), false)
	shophouse(2.0, "ข้าวมันไก่", Color("e0a030"), true)
	shophouse(6.0, "ร้านตัดผม", Color("2a62a8"), false)
	tree(Vector3(-9.5, 0.1, -1.6))
	tree(Vector3(9.5, 0.1, -1.4))
	cyl(0.08, 6.0, Color("8a8e94"), Vector3(-4.0, 3.0, -0.4), Vector3.ZERO, 6)  # a power pole
	car(Vector3(3.5, 0, 3.0), 25.0, Color("b8302a"))
	car(Vector3(-9.0, 0, 6.8), 180.0, Color("e8e4dc"))
	person(Vector3(-1.5, 0.18, -0.8), 200.0, Color("c8906a"), Color("3a6aa8"), Color("2a3a5a"), Color("1a1614"), false, true)
	person(Vector3(0.8, 0, 2.2), 20.0, Color("8a9a7a"), Color("7a6a50"), Color("3a3a3a"), Color("2a2622"), true)
	person(Vector3(-4.2, 0, 3.6), -30.0, Color("9aa08a"), Color("a8a4a0"), Color("4a4040"), Color("3a3028"), true)
	person(Vector3(6.5, 0, 5.8), 60.0, Color("8a947a"), Color("c83a2e"), Color("2a2a30"), Color("1a1614"), true)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 17.0
	cam.rotation_degrees = Vector3(-42, 0, 0)
	cam.position = Vector3(0, 13, 11)
	root3d.add_child(cam)
	cam.current = true
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out)
	root.get_viewport().get_texture().get_image().save_png(out + "/mock3d.png")
	# Closer, from lower down.
	cam.size = 6.5
	cam.position = Vector3(0.5, 5.5, 7.5)
	cam.rotation_degrees = Vector3(-35, 0, 0)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + "/mock3d_close.png")
	quit(0)
