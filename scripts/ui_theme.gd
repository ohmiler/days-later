class_name UiTheme
## Fonts, colours and small drawing helpers shared by every piece of UI.
## Kanit for headings (bold, like shop signs), Sarabun for body text.

const PAPER := Color("e9e1cf")
const PAPER_DARK := Color("cfc4ab")
const INK := Color("1d1a16")
const BLOOD := Color("c8302a")
const WARN := Color("f2c230")  # yellow = something you can press or do
const CARD := Color(0.08, 0.07, 0.06, 0.8)
const LINE := Color(0.91, 0.88, 0.81, 0.18)

static var _cache := {}


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


## Draw text where [X] marks a keycap, e.g. "กด [E] ค้นหา". Returns the width used.
static func draw_rich(ci: CanvasItem, pos: Vector2, text: String, f: Font, size: int, col: Color,
		measure_only := false) -> float:
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
