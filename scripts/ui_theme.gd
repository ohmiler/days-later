class_name UiTheme
## Fonts, colours and small drawing helpers shared by every piece of UI.
## Kanit for headings (bold, like shop signs), Sarabun for body text.

const PAPER := Color("e9e1cf")
const PAPER_DARK := Color("cfc4ab")
const PAPER_INK := Color("2a241c")  # text on paper (the story style)
const TAPE := Color("d9c98f")  # the strip holding a paper note on
const INK := Color("1d1a16")
const BLOOD := Color("c8302a")
const WARN := Color("f2c230")  # yellow = something you can press or do
const CARD := Color(0.08, 0.07, 0.06, 0.8)
const LINE := Color(0.91, 0.88, 0.81, 0.18)

# The design system ("Days Later UI"): the same names as its tokens.
# Grounds, back to front: the brighter, the nearer.
const SURFACE_000 := Color("0f0d0b")  # behind everything; the scrim under a panel
const SURFACE_100 := Color("17140f")  # panels and HUD cards
const SURFACE_200 := Color("211d17")  # things inside a panel: rows, empty slots, tracks
const SURFACE_300 := Color("2c2720")  # hover; a slot with something in it
const BORDER := Color("3a3329")  # 1px edges
const BORDER_STRONG := Color("5a4f3f")  # the edge of what's hovered or focused
const TEXT := Color("ece4d2")
const TEXT_MUTED := Color("a79d89")  # hints, counters, descriptions
const TEXT_FAINT := Color("7d7465")  # disabled, empty-slot labels: never what you must read
const ACCENT := Color("f2c230")  # the one colour for what you press or what matters now
const ON_ACCENT := Color("1d1a16")
const DANGER := Color("ea6a52")  # blood and danger (always with a word or an icon)
const DANGER_DEEP := Color("c8302a")  # the health bar's fill
const OK := Color("8fc58a")  # done, safe
const INFO := Color("7fb0e0")  # chat, water

# Six text sizes and no others.
const SIZE_DISPLAY := 28  # the one big line: day, banner
const SIZE_TITLE := 20  # a panel's heading
const SIZE_HEADING := 16  # a card's or row's name, buttons
const SIZE_BODY := 14
const SIZE_LABEL := 12  # labels, keycaps
const SIZE_CAPTION := 12  # hints

const SPACE_1 := 4.0
const SPACE_2 := 8.0
const SPACE_3 := 12.0
const SPACE_4 := 16.0
const SPACE_6 := 24.0
const RADIUS_SM := 4
const RADIUS_LG := 8
const OPACITY_CARD := 0.88

static var _cache := {}
static var _boxes := {}


static func font(name: String) -> Font:
	if not _cache.has(name):
		_cache[name] = load("res://fonts/%s.ttf" % name)
	return _cache[name]


static func heading() -> Font:
	return font("Kanit-Bold")


static func heavy() -> Font:
	return font("Kanit-ExtraBold")


static func medium() -> Font:
	return font("Kanit-Medium")


static func body() -> Font:
	return font("Sarabun-Regular")


static func body_bold() -> Font:
	return font("Sarabun-SemiBold")


## A copy of a font rendered as MSDF, for text drawn in the zoomed game world.
static func world(name := "Kanit-Medium") -> Font:
	var key := "msdf:" + name
	if not _cache.has(key):
		var f: FontFile = font(name).duplicate()
		f.multichannel_signed_distance_field = true
		_cache[key] = f
	return _cache[key]


static func box(bg: Color, radius := 8, border := Color(0, 0, 0, 0), border_w := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


# --- Design-system pieces ----------------------------------------------------
# Each draws one component of the design system, so every screen looks the same.

## A rounded box, cached by its look (drawn every frame by many controls).
static func rbox(bg: Color, radius: int, edge := Color(0, 0, 0, 0), shadow := 0) -> StyleBoxFlat:
	var key := "%s|%d|%s|%d" % [bg.to_html(), radius, edge.to_html(), shadow]
	var s: StyleBoxFlat = _boxes.get(key)
	if s == null:
		if _boxes.size() > 512:  # (colours that pulse make new keys: don't grow forever)
			_boxes.clear()
		s = StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(radius)
		if edge.a > 0.0:
			s.border_color = edge
			s.set_border_width_all(1)
		if shadow > 0:
			s.shadow_color = Color(0, 0, 0, 0.35 if shadow < 12 else 0.5)
			s.shadow_size = shadow
			s.shadow_offset = Vector2(0, shadow * 0.5)
		s.anti_aliasing = radius > 0
		_boxes[key] = s
	return s


## Card: a HUD box over the world, a little see-through. `edge` for a warning.
static func card(ci: CanvasItem, r: Rect2, edge := BORDER) -> void:
	ci.draw_style_box(rbox(Color(SURFACE_100, OPACITY_CARD), RADIUS_LG, edge, 6), r)
	ci.draw_line(r.position + Vector2(RADIUS_LG, 1), Vector2(r.end.x - RADIUS_LG, r.position.y + 1), Color(TEXT, 0.06))


## Panel: a full-screen box (the bag, menus), solid.
static func panel(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_style_box(rbox(SURFACE_100, RADIUS_LG, BORDER, 20), r)
	ci.draw_line(r.position + Vector2(RADIUS_LG, 1), Vector2(r.end.x - RADIUS_LG, r.position.y + 1), Color(TEXT, 0.07))


## Slot: a place for one item. Filled ones are lighter; the selected one has
## an accent edge. `rarity` (a colour) draws the mark under the item.
static func slot(ci: CanvasItem, r: Rect2, filled: bool, sel := false, hover := false, rarity := Color(0, 0, 0, 0)) -> void:
	var bg := SURFACE_300 if filled or hover else SURFACE_200
	ci.draw_style_box(rbox(bg, RADIUS_SM, ACCENT if sel else (BORDER_STRONG if hover else BORDER)), r)
	if sel:
		ci.draw_style_box(rbox(Color(0, 0, 0, 0), RADIUS_SM + 1, ACCENT), r.grow(1))
	if rarity.a > 0.0:
		ci.draw_rect(Rect2(r.position.x + 6, r.end.y - 4, r.size.x - 12, 2), rarity)


## Meter: a thin rounded track with its fill (0..1).
static func meter(ci: CanvasItem, r: Rect2, frac: float, col: Color, track := SURFACE_200) -> void:
	var rad := int(r.size.y / 2)
	ci.draw_style_box(rbox(track, rad), r)
	var w := r.size.x * clampf(frac, 0.0, 1.0)
	if w >= 1.0:
		ci.draw_style_box(rbox(col, rad), Rect2(r.position, Vector2(maxf(w, r.size.y), r.size.y)))


## Keycap: a key to press, sitting on the text baseline at `pos`. Returns its width.
static func keycap(ci: CanvasItem, pos: Vector2, key: String, size := SIZE_LABEL, accent := false, measure_only := false) -> float:
	var f := heading()
	var h := size + 10.0
	var w := maxf(f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 12.0, h)
	if not measure_only:
		var r := Rect2(pos.x, pos.y - size - 3.0, w, h)
		ci.draw_style_box(rbox(ACCENT if accent else SURFACE_300, RADIUS_SM, ACCENT if accent else BORDER_STRONG), r)
		ci.draw_rect(Rect2(r.position.x + 2, r.end.y - 2, r.size.x - 4, 1.5), Color(0, 0, 0, 0.35))
		ci.draw_string(f, Vector2(pos.x, pos.y - 1), key, HORIZONTAL_ALIGNMENT_CENTER, w, size, ON_ACCENT if accent else TEXT)
	return w


## Dress a Godot Button as the design system's Button: `primary` in the accent
## (one per screen: the thing to press), else a quiet one on surface-200.
static func style_button(b: Button, primary := false, font_size := SIZE_HEADING) -> void:
	b.add_theme_font_override("font", heading())
	b.add_theme_font_size_override("font_size", font_size)
	var bg := ACCENT if primary else SURFACE_200
	var looks := {normal = [bg, ACCENT if primary else BORDER], hover = [ACCENT.lightened(0.08) if primary else SURFACE_300, ACCENT if primary else BORDER_STRONG],
			pressed = [ACCENT.darkened(0.08) if primary else SURFACE_200, ACCENT if primary else BORDER_STRONG],
			focus = [bg, ACCENT], disabled = [SURFACE_200, BORDER]}
	for state in looks:
		var s := StyleBoxFlat.new()
		s.bg_color = looks[state][0]
		s.set_corner_radius_all(RADIUS_SM)
		s.border_color = looks[state][1]
		s.set_border_width_all(1)
		s.content_margin_left = SPACE_4
		s.content_margin_right = SPACE_4
		s.content_margin_top = 9
		s.content_margin_bottom = 10
		if state == "focus":
			s.draw_center = false  # (just a faint ring over the look it has: a clicked button keeps focus)
			s.border_color = Color(TEXT, 0.35) if primary else Color(ACCENT, 0.5)
		b.add_theme_stylebox_override(state, s)
	var fg := ON_ACCENT if primary else TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, fg)
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)


## Dress a LineEdit: surface-200, an accent edge while typing in it.
static func style_input(e: LineEdit) -> void:
	e.add_theme_font_override("font", body())
	e.add_theme_font_size_override("font_size", SIZE_HEADING)
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", TEXT_FAINT)
	e.add_theme_color_override("caret_color", ACCENT)
	e.add_theme_color_override("selection_color", Color(ACCENT, 0.3))
	for state in ["normal", "focus", "read_only"]:
		var s := StyleBoxFlat.new()
		s.bg_color = SURFACE_200
		s.set_corner_radius_all(RADIUS_SM)
		s.border_color = ACCENT if state == "focus" else BORDER
		s.set_border_width_all(1)
		s.content_margin_left = SPACE_3
		s.content_margin_right = SPACE_3
		s.content_margin_top = 9
		s.content_margin_bottom = 10
		e.add_theme_stylebox_override(state, s)


## Dress an HSlider as a big Meter you can drag: an accent fill and a round grab.
static func style_slider(sl: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = SURFACE_300
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	sl.add_theme_stylebox_override("slider", track)
	for k in ["grabber_area", "grabber_area_highlight"]:
		var fill := track.duplicate()
		fill.bg_color = ACCENT
		sl.add_theme_stylebox_override(k, fill)
	sl.add_theme_icon_override("grabber", dot_texture(8, TEXT))
	sl.add_theme_icon_override("grabber_highlight", dot_texture(9, Color.WHITE))
	sl.custom_minimum_size.y = 24


## A round dot as a texture (a slider's grab), soft-edged.
static func dot_texture(r: int, col: Color) -> ImageTexture:
	var key := "dot:%d:%s" % [r, col.to_html()]
	if not _cache.has(key):
		var n := r * 2 + 2
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := Vector2(n, n) / 2.0
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
				img.set_pixel(x, y, Color(col, clampf(r - d + 0.5, 0.0, 1.0)))
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## A thin line between groups in a panel.
static func divider() -> Control:
	var l := ColorRect.new()
	l.color = BORDER
	l.custom_minimum_size = Vector2(0, 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A Panel's box for a Container (the same look `panel()` draws).
static func panel_box(pad := SPACE_6, see_through := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(SURFACE_100, OPACITY_CARD) if see_through else SURFACE_100
	s.set_corner_radius_all(RADIUS_LG)
	s.border_color = BORDER
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 20
	s.shadow_offset = Vector2(0, 10)
	s.set_content_margin_all(pad)
	return s


## A toast's box (a line of news in the feed): the kind shows as a dot, not a side bar.
static func toast_box() -> StyleBoxFlat:
	var s: StyleBoxFlat = rbox(Color(SURFACE_100, OPACITY_CARD), RADIUS_SM, BORDER).duplicate()
	s.content_margin_left = SPACE_3 + 14
	s.content_margin_right = SPACE_3
	s.content_margin_top = 5
	s.content_margin_bottom = 6
	return s


## Text drawn over the world with no box behind it: a soft dark edge keeps it readable.
static func over_world(ci: CanvasItem, pos: Vector2, text: String, f: Font, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ci.draw_string_outline(f, pos, text, align, width, size, maxi(4, size / 3), Color(0, 0, 0, 0.5 * col.a))
	ci.draw_string(f, pos, text, align, width, size, col)


## Draw text where [X] marks a keycap, e.g. "กด [E] ค้นหา". Returns the width used.
## `dark` draws the design system's keycaps (on a dark card); else the yellow
## ones that sit on paper.
static func draw_rich(ci: CanvasItem, pos: Vector2, text: String, f: Font, size: int, col: Color,
		measure_only := false, dark := false) -> float:
	if dark:
		var dx := pos.x
		var bits := text.split("[")
		for i in bits.size():
			var bit := bits[i]
			if i > 0 and "]" in bit:
				var k := bit.get_slice("]", 0)
				bit = bit.substr(k.length() + 1)
				dx += keycap(ci, Vector2(dx, pos.y), k, SIZE_LABEL, false, measure_only) + 4.0
			if bit != "":
				if not measure_only:
					ci.draw_string(f, Vector2(dx, pos.y), bit, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
				dx += f.get_string_size(bit, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + (4.0 if i + 1 < bits.size() else 0.0)
		return dx - pos.x
	var x := pos.x
	var parts := text.split("[")
	for i in parts.size():
		var part := parts[i]
		if i > 0 and "]" in part:
			var key := part.get_slice("]", 0)
			part = part.substr(key.length() + 1)
			var kw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + size * 0.7
			kw = maxf(kw, size * 1.35)
			if not measure_only:
				var r := Rect2(x, pos.y - size * 1.02, kw, size * 1.3)
				ci.draw_rect(Rect2(r.position + Vector2(0, size * 0.14), r.size), Color("9a7a18"))
				ci.draw_rect(r, WARN)
				ci.draw_string(f, Vector2(x, pos.y - size * 0.05), key, HORIZONTAL_ALIGNMENT_CENTER, kw, size, INK)
			x += kw + size * 0.3
		if part != "":
			if not measure_only:
				ci.draw_string(f, Vector2(x, pos.y), part, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			x += f.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return x - pos.x


static func heart(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var t := i / 24.0 * TAU
		pts.append(c + Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * s / 17.0)
	ci.draw_colored_polygon(pts, col)
