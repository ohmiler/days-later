class_name CityMap
extends Control
## The city map (M). Drawn from the tiles once; what you have not walked near
## yet stays dark and fills in as you explore. It shows the part of the city
## around you (the wheel zooms); right-click to drop a pin (your home, a stash,
## a place to avoid), click a pin to remove it. Pins and what you have
## explored are kept per city in the settings file.

const MAX_SIZE := Vector2(960, 600)  # the map panel, in screen pixels (smaller on a small screen)
var panel := MAX_SIZE  # (fitted to the screen each time it shows)
const ZOOMS := [1.25, 2.0, 3.0, 4.5, 6.0]  # screen pixels a tile
const REVEAL := 11  # tiles around you that count as seen
var zoom_i := 2
var px := 3.0  # screen pixels a tile, now
var origin := Vector2.ZERO  # where tile (0, 0) is drawn in the panel
var fog_tex: ImageTexture  # the dark over what you haven't seen, from `shade`
var shade: Image  # fog as a picture: see-through where seen
var _fog_dirty := true

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
	shade = Image.create(World.W, World.H, false, Image.FORMAT_LA8)
	var dark := Color(0.03, 0.03, 0.03, 0.86)
	for y in World.H:
		for x in World.W:
			shade.set_pixel(x, y, dark if fog.get_pixel(x, y).r < 0.5 else Color(0, 0, 0, 0))
	fog_tex = ImageTexture.create_from_image(shade)
	_fog_dirty = false
	pins = cfg.get_value("map", _key("pins"), [])
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -panel.x / 2
	offset_right = panel.x / 2
	offset_top = -panel.y / 2 - 20
	offset_bottom = panel.y / 2 - 20
	clip_contents = true
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
				shade.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
				_dirty = true
				_fog_dirty = true


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
		if _fog_dirty:
			fog_tex.update(shade)
			_fog_dirty = false
		# Centred on you, but never past the edges of the city.
		px = ZOOMS[zoom_i]
		var at: Vector2 = me.position / World.TILE if me else Vector2(World.W, World.H) / 2
		var screen := get_viewport_rect().size
		var fit := Vector2(minf(MAX_SIZE.x, screen.x - 40.0), minf(MAX_SIZE.y, screen.y - 90.0))
		if fit != panel:
			panel = fit
			offset_left = -panel.x / 2
			offset_right = panel.x / 2
			offset_top = -panel.y / 2 - 20
			offset_bottom = panel.y / 2 - 20
		var span := Vector2(World.W, World.H) * px
		origin = panel / 2 - at * px
		# Smaller than the panel: in the middle. Bigger: follow you, but not past the edges.
		origin.x = (panel.x - span.x) / 2 if span.x <= panel.x else clampf(origin.x, panel.x - span.x, 0.0)
		origin.y = (panel.y - span.y) / 2 if span.y <= panel.y else clampf(origin.y, panel.y - span.y, 0.0)
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	accept_event()
	if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_i = clampi(zoom_i + (1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, ZOOMS.size() - 1)
		return
	var cell := Vector2i(((e.position - origin) / px).floor())
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


const BAR := 44.0  # the title bar
const LEGEND := 36.0  # the legend along the bottom


func _draw() -> void:
	if tex == null:
		return
	var sz := panel
	draw_rect(Rect2(-Vector2(4000, 4000), sz + Vector2(8000, 8000)), Color(UiTheme.SURFACE_000, 0.6))  # (the world goes dark behind)
	UiTheme.panel(self, Rect2(Vector2.ZERO, sz))
	var span := Vector2(World.W, World.H) * px
	draw_texture_rect(tex, Rect2(origin, span), false)
	# Unexplored parts: dark, with just the street grid showing through faintly.
	draw_texture_rect(fog_tex, Rect2(origin, span), false)
	# A bar along the top: where, and how to use it.
	draw_style_box(UiTheme.rbox(Color(UiTheme.SURFACE_100, 0.92), 0), Rect2(1, 1, sz.x - 2, BAR))
	draw_line(Vector2(1, BAR + 1), Vector2(sz.x - 1, BAR + 1), UiTheme.BORDER)
	var P := UiTheme.SPACE_4
	draw_string(UiTheme.heading(), Vector2(P, 30), "แผนที่", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_TITLE, UiTheme.TEXT)
	var tw := UiTheme.heading().get_string_size("แผนที่", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_TITLE).x
	draw_string(UiTheme.medium(), Vector2(P + tw + 10, 29), Zones.name_of(world.zone), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_BODY, UiTheme.TEXT_MUTED)
	var hint := "ลูกกลิ้ง ซูม · คลิกขวา ปักหมุด · คลิกหมุด เอาออก · [M] ปิด"
	var hw := UiTheme.draw_rich(self, Vector2.ZERO, hint, UiTheme.body(), UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED, true, true)
	UiTheme.draw_rich(self, Vector2(sz.x - P - hw, 29), hint, UiTheme.body(), UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED, false, true)
	var f := UiTheme.body_bold()
	# The ways out to other zones.
	for e in world.exits:
		var c: Vector2 = origin + Vector2(e.rect.get_center()) * px
		draw_circle(c, 6.0, Color("1e6a3a"))
		draw_arc(c, 6.0, 0, TAU, 16, Color("e8e8e0"), 1.2)
		var label: String = "ไป" + Zones.name_of(e.to)
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var at := c + Vector2(-w - 10.0 if e.id == "east" else 10.0, 4.0)
		draw_string_outline(f, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.8))
		draw_string(f, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e8f0e0"))
	for i in pins.size():
		var p := origin + (Vector2(pins[i]) + Vector2(0.5, 0.5)) * px
		draw_circle(p + Vector2(0, -8), 5.5, UiTheme.DANGER_DEEP)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -6), p + Vector2(4, -6), p]), UiTheme.DANGER_DEEP)
		draw_string(f, p + Vector2(-5, -5), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 10, 9, Color.WHITE)
	for o in others:
		var p: Vector2 = origin + o[0] / World.TILE * px
		draw_circle(p, 3.5, UiTheme.INFO)
		UiTheme.over_world(self, p + Vector2(7, 4), o[1], f, UiTheme.SIZE_LABEL, UiTheme.INFO)
	if me:
		var p := origin + me.position / World.TILE * px
		var d := me.aim.normalized() if me.aim.length() > 0.1 else Vector2.DOWN
		draw_colored_polygon(PackedVector2Array([p + d * 9, p + d.orthogonal() * 5 - d * 4, p - d.orthogonal() * 5 - d * 4]), UiTheme.ACCENT)
		draw_arc(p, 11, 0, TAU, 20, Color(UiTheme.ACCENT, 0.5 + 0.3 * sin(Time.get_ticks_msec() / 200.0)), 1.5)
	# The legend along the bottom: a swatch for each thing, then its name.
	var ly := sz.y - LEGEND
	draw_style_box(UiTheme.rbox(Color(UiTheme.SURFACE_100, 0.92), 0), Rect2(1, ly, sz.x - 2, LEGEND - 1))
	draw_line(Vector2(1, ly), Vector2(sz.x - 1, ly), UiTheme.BORDER)
	var x := P
	for item in [[Color("b8452a"), "วัด"], [Color("3a72b8"), "มินิมาร์ท"], [Color("8e949a"), "คอนโด"], [Color("1e6a3a"), "ทางไปย่านอื่น"],
			[UiTheme.ACCENT, "คุณ"], [UiTheme.INFO, "คนอื่น"], [UiTheme.DANGER_DEEP, "หมุด"], [Color(0.03, 0.03, 0.03), "ยังไม่เคยไป"]]:
		var cy := ly + LEGEND / 2
		draw_style_box(UiTheme.rbox(item[0], 2, UiTheme.BORDER_STRONG), Rect2(x, cy - 5, 10, 10))
		draw_string(UiTheme.medium(), Vector2(x + 16, cy + 5), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED)
		x += 16 + UiTheme.medium().get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL).x + UiTheme.SPACE_4
