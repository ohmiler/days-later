class_name CityMap
extends Control
## The city map (M). Drawn from the tiles once; what you have not walked near
## yet stays dark and fills in as you explore. Right-click to drop a pin (your
## home, a stash, a place to avoid), click a pin to remove it. Pins and what
## you have explored are kept per city in the settings file.

const SCALE := 4.5
const REVEAL := 11  # tiles around you that count as seen

var world: World
var cfg: ConfigFile
var tex: ImageTexture
var fog: Image  # one pixel per tile: 0 unseen, 1 seen
var pins: Array = []  # [cell]
var me: Player
var others: Array = []  # [pos, name]
var seed_key := 0
var _dirty := false
var _save_t := 0.0


func setup(w: World, settings: ConfigFile, city_seed: int) -> void:
	world = w
	seed_key = city_seed
	cfg = settings
	var img := Image.create(World.W, World.H, false, Image.FORMAT_RGBA8)
	for y in World.H:
		for x in World.W:
			img.set_pixel(x, y, _colour(w.get_tile(Vector2i(x, y))))
	for rec in w.buildings:
		var r: Rect2i = rec.rect
		var col: Color = {temple = Color("b8452a"), chedi = Color("e8e2d4"), sala = Color("b8452a"),
				condo = Color("8e949a"), store = Color("3a72b8")}.get(rec.kind, Color("6e665a"))
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				img.set_pixel(x, y, col if x > r.position.x and y > r.position.y else col.darkened(0.3))
	tex = ImageTexture.create_from_image(img)
	fog = Image.create(World.W, World.H, false, Image.FORMAT_L8)
	var saved := PackedByteArray()
	if FileAccess.file_exists(_seen_path()):
		saved = FileAccess.get_file_as_bytes(_seen_path())
	# Older copies kept this in the settings file, which made every settings save
	# slow (it became a huge line of text). Move it out once.
	if cfg.has_section("map"):
		var moved := false
		for k in cfg.get_section_keys("map"):
			if k.begins_with("seen_"):
				if k == _key("seen") and saved.is_empty():
					saved = cfg.get_value("map", k)
				cfg.erase_section_key("map", k)
				moved = true
		if moved:
			cfg.save(GameUI.SETTINGS)
	if saved.size() == World.W * World.H:
		fog.set_data(World.W, World.H, false, Image.FORMAT_L8, saved)
	pins = cfg.get_value("map", _key("pins"), [])
	set_anchors_preset(Control.PRESET_CENTER)
	var sz := Vector2(World.W, World.H) * SCALE
	offset_left = -sz.x / 2
	offset_right = sz.x / 2
	offset_top = -sz.y / 2 - 20
	offset_bottom = sz.y / 2 - 20
	mouse_filter = Control.MOUSE_FILTER_STOP


func _key(what: String) -> String:
	return "%s_%d" % [what, seed_key]


func _colour(t: int) -> Color:
	match t:
		World.ROAD:
			return Color("2e3032")
		World.SIDEWALK, World.SOI, World.PLAZA:
			return Color("8a867c")
		World.WATER:
			return Color("3a6a78")
		World.GRASS, World.TREE, World.DIRT:
			return Color("4e6038")
		World.WALL:
			return Color("c8c0b0")
	return Color("6e665a")


## Mark what is around you as seen (called a few times a second while playing).
func reveal(pos: Vector2) -> void:
	if fog == null:
		return
	var c := world.to_cell(pos)
	for dy in range(-REVEAL, REVEAL + 1):
		for dx in range(-REVEAL, REVEAL + 1):
			var p := c + Vector2i(dx, dy)
			if dx * dx + dy * dy <= REVEAL * REVEAL and world.in_bounds(p) and fog.get_pixel(p.x, p.y).r < 0.5:
				fog.set_pixel(p.x, p.y, Color.WHITE)
				_dirty = true


## What you have explored lives in its own small file, one byte per tile.
func _seen_path() -> String:
	return "user://map/seen_%d.bin" % seed_key


func save_seen() -> void:
	if fog == null:
		return
	DirAccess.make_dir_recursive_absolute("user://map")
	var f := FileAccess.open(_seen_path(), FileAccess.WRITE)
	if f:
		f.store_buffer(fog.get_data())
		f.close()
	_dirty = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _dirty:
			save_seen()


func _process(delta: float) -> void:
	_save_t -= delta
	if _dirty and _save_t <= 0.0:
		_save_t = 30.0
		save_seen()
	if visible:
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	accept_event()
	var cell := Vector2i((e.position / SCALE).floor())
	if e.button_index == MOUSE_BUTTON_RIGHT:
		if pins.size() < 20:
			pins.append(cell)
	elif e.button_index == MOUSE_BUTTON_LEFT:
		for i in pins.size():
			if Vector2(pins[i]).distance_to(Vector2(cell)) < 3.0:
				pins.remove_at(i)
				break
	cfg.set_value("map", _key("pins"), pins)
	cfg.save(GameUI.SETTINGS)


func _draw() -> void:
	if tex == null:
		return
	var sz := Vector2(World.W, World.H) * SCALE
	draw_style_box(UiTheme.box(Color(0.06, 0.055, 0.045, 0.97), 10, UiTheme.LINE, 1), Rect2(Vector2(-14, -44), sz + Vector2(28, 84)))
	draw_texture_rect(tex, Rect2(Vector2.ZERO, sz), false)
	# Unexplored parts: dark, with just the street grid showing through faintly.
	_draw_fog(sz)
	draw_rect(Rect2(Vector2.ZERO, sz), UiTheme.LINE, false, 1)
	draw_string(UiTheme.heading(), Vector2(0, -16), "แผนที่เมือง", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.PAPER)
	draw_string(UiTheme.body(), Vector2(0, -16), "คลิกขวาปักหมุด · คลิกหมุดเพื่อเอาออก · [M] ปิด", HORIZONTAL_ALIGNMENT_RIGHT, sz.x, 13,
			Color(UiTheme.PAPER, 0.6))
	var f := UiTheme.body_bold()
	for i in pins.size():
		var p := (Vector2(pins[i]) + Vector2(0.5, 0.5)) * SCALE
		draw_circle(p + Vector2(0, -8), 5.5, Color("c83a2e"))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -6), p + Vector2(4, -6), p]), Color("c83a2e"))
		draw_string(f, p + Vector2(-5, -5), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 10, 9, Color.WHITE)
	for o in others:
		var p: Vector2 = o[0] / World.TILE * SCALE
		draw_circle(p, 3.5, Color("e8e4d0"))
		draw_string(f, p + Vector2(6, 4), o[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e8e4d0"))
	if me:
		var p := me.position / World.TILE * SCALE
		var d := me.aim.normalized() if me.aim.length() > 0.1 else Vector2.DOWN
		draw_colored_polygon(PackedVector2Array([p + d * 9, p + d.orthogonal() * 5 - d * 4, p - d.orthogonal() * 5 - d * 4]), UiTheme.WARN)
		draw_arc(p, 11, 0, TAU, 20, Color(UiTheme.WARN, 0.5 + 0.3 * sin(Time.get_ticks_msec() / 200.0)), 1.5)
	draw_string(UiTheme.body(), Vector2(0, sz.y + 26), "สีแดง = วัด · สีฟ้า = มินิมาร์ท · สีเทาอ่อน = คอนโด · ที่มืดคือที่ยังไม่เคยไป",
			HORIZONTAL_ALIGNMENT_LEFT, sz.x, 13, Color(UiTheme.PAPER, 0.55))


## Dark squares over every unseen tile, merged into runs so it stays cheap.
func _draw_fog(_sz: Vector2) -> void:
	for y in World.H:
		var run := -1
		for x in World.W + 1:
			var unseen := x < World.W and fog.get_pixel(x, y).r < 0.5
			if unseen and run < 0:
				run = x
			elif not unseen and run >= 0:
				draw_rect(Rect2(run * SCALE, y * SCALE, (x - run) * SCALE, SCALE), Color(0.03, 0.03, 0.025, 0.86))
				run = -1
