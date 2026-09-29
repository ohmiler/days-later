extends SceneTree
## Step 0 of the 3D move: weapons in hand, frame by frame. Not part of the game.
##   godot --path . --resolution 1600x900 -s res://tests/look3d/shoot_weapons.gd -- --out=DIR

const Person := preload("res://scripts/view3d/person.gd")
const Pose := preload("res://scripts/view3d/pose.gd")
const W := preload("res://scripts/view3d/weapons.gd")

var out := "user://look3d"
var holder: Node3D
var sk: Skeleton3D
var cam: Camera3D
var held: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_build.call_deferred()


func _build() -> void:
	var r := Node3D.new()
	root.add_child(r)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("9aa0a4")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c8ccd0")
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	we.environment = e
	r.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	r.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("8a867e")
	floor.material_override = fm
	r.add_child(floor)
	holder = Node3D.new()
	r.add_child(holder)
	sk = Person.new().build({shirt = {kind = "tee", col = Color("3a6aa8")}, pants = {kind = "long", col = Color("2a3a5a")}})
	holder.add_child(sk)
	cam = Camera3D.new()
	cam.fov = 30.0
	r.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(out)

	# Hands: open and closed, close up.
	_hold("fists")
	var imgs: Array[Image] = []
	Pose.stand(sk)
	W.fingers(sk, "_r", 0.0, 0.0)
	W.fingers(sk, "_l", 0.0, 0.0)
	await _look_hand()
	imgs.append(await _grab())
	_hold("machete")
	Pose.stand(sk)
	W.upper(sk, "machete", -1.0)
	W.hands(sk, "machete")
	await _look_hand()
	imgs.append(await _grab())
	_hold("axe")
	Pose.stand(sk)
	W.upper(sk, "axe", -1.0)
	W.hands(sk, "axe")
	_view(Vector3(-1.8, 1.4, 2.2), Vector3(0, 1.0, 0.2), 30.0)
	imgs.append(await _grab())
	_hold("pistol")
	Pose.stand(sk)
	W.upper(sk, "pistol", -1.0, 1.0)
	W.hands(sk, "pistol", 1.0)
	_view(Vector3(-1.6, 1.5, 1.6), Vector3(0, 1.3, 0.4), 26.0)
	imgs.append(await _grab())
	_strip(imgs, 4, "hold.png", 0.34)

	# The machete and the axe, frame by frame, from the front-right.
	for kind in ["machete", "axe"]:
		_hold(kind)
		var frames: Array[Image] = []
		var info: Dictionary = W.KINDS[kind]
		_view(Vector3(-2.6, 1.5, 3.2), Vector3(0, 1.0, 0.3), 32.0)
		for i in 8:
			Pose.stand(sk)
			W.upper(sk, kind, info.time * i / 7.0)
			W.hands(sk, kind, 0.0, info.time * i / 7.0)
			frames.append(await _grab())
		_strip(frames, 8, kind + "_swing.png", 0.3)
	# The pistol: raising it, aimed, the shot's kick, from the side.
	_hold("pistol")
	var pf: Array[Image] = []
	_view(Vector3(-3.2, 1.4, 1.2), Vector3(0, 1.2, 0.5), 30.0)
	for step in [[0.0, 0.0], [0.5, 0.0], [1.0, 0.0], [1.0, 1.0], [1.0, 0.5]]:
		Pose.stand(sk)
		W.upper(sk, "pistol", -1.0, step[0], step[1])
		W.hands(sk, "pistol", step[0])
		pf.append(await _grab())
	_strip(pf, 5, "pistol.png", 0.3)
	quit(0)


func _hold(kind: String) -> void:
	if held:
		held.get_parent().queue_free()
		held = null
	if kind == "fists":
		return
	var att := BoneAttachment3D.new()
	sk.add_child(att)
	att.bone_name = "hand_r"
	held = W.build(kind)
	held.position = W.FIST
	att.add_child(held)


func _look_hand() -> void:
	sk.force_update_all_bone_transforms()
	var h := W.hand_xform(sk, "_r").origin
	_view(h + Vector3(-0.45, 0.12, 0.35), h + Vector3(0, -0.05, 0), 30.0)


func _view(pos: Vector3, at: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.position = pos
	cam.look_at(at)


func _grab() -> Image:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


func _strip(imgs: Array[Image], cols: int, file: String, keep: float) -> void:
	var w := imgs[0].get_width()
	var h := imgs[0].get_height()
	var cw := int(w * keep)
	var cx := int((w - cw) / 2)
	var rows := ceili(imgs.size() / float(cols))
	var sheet := Image.create(cw * cols, h * rows, false, imgs[0].get_format())
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(cx, 0, cw, h), Vector2i((i % cols) * cw, (i / cols) * h))
	if sheet.get_width() > 2400:
		sheet.resize(2400, int(sheet.get_height() * 2400.0 / sheet.get_width()))
	sheet.save_png(out + "/" + file)
