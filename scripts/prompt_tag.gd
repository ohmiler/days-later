class_name PromptTag
extends Control
## The small "E  open" tag over whatever is in reach. It's drawn on the HUD, so
## it stays the same size at any zoom, and says only the verb; what the thing
## is (a bike's fuel, why it can't be done) fades in underneath once you stay
## on it for a moment. Dots after the verb: hold E for more. Main fills it in
## every frame (see Main._update_prompt).

const SIZE := 15  # text size of the verb
const DETAIL := 12
const DWELL := 0.35  # seconds on a target before its details show

var verb := ""  # "" hides the tag
var key := "E"
var ok := true
var more := false  # other things to do: hold E for the wheel
var second := ""  # a second key's action, e.g. "R ตอกไม้"
var detail := ""
var always_detail := false  # riding: the bike's fuel stays shown
var world_pos := Vector2.ZERO
var dwell := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if verb == "":
		return
	var at := get_viewport().get_canvas_transform() * world_pos
	var f := UiTheme.medium()
	var fb := UiTheme.body()
	var alpha := 1.0 if ok else 0.6
	var kw := maxf(f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE - 1).x + 10.0, 22.0)
	var vw := f.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	var dots := 14.0 if more else 0.0
	var sw := 0.0
	var s_key := ""
	var s_text := ""
	if second != "":
		s_key = second.get_slice(" ", 0)
		s_text = second.substr(s_key.length() + 1)
		sw = 10.0 + 22.0 + 6.0 + f.get_string_size(s_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	var w := 5.0 + kw + 7.0 + vw + dots + sw + 9.0
	var h := 28.0
	var screen := get_viewport_rect().size
	var r := Rect2(at.x - w / 2, at.y - h, w, h)
	r.position.x = clampf(r.position.x, 8.0, maxf(8.0, screen.x - w - 8.0))  # (kept on screen)
	r.position.y = clampf(r.position.y, 8.0, maxf(8.0, screen.y - h - 120.0))
	draw_style_box(UiTheme.box(Color(0.06, 0.06, 0.06, 0.62 * alpha), 6), r)
	var x := r.position.x + 5.0
	_key(Rect2(x, r.position.y + 4, kw, h - 8), key, alpha)
	x += kw + 7.0
	var base := r.position.y + h / 2 + SIZE * 0.36
	draw_string(f, Vector2(x, base), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(UiTheme.PAPER, alpha))
	x += vw
	if more:
		for i in 3:
			draw_circle(Vector2(x + 4 + i * 4.0, base - 3), 1.3, Color(UiTheme.PAPER, 0.6 * alpha))
		x += dots
	if second != "":
		x += 10.0
		_key(Rect2(x, r.position.y + 4, 22.0, h - 8), s_key, alpha)
		x += 28.0
		draw_string(f, Vector2(x, base), s_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(UiTheme.PAPER, alpha))
	# What it is, once you stay on it.
	var k := 1.0 if always_detail else clampf((dwell - DWELL) / 0.25, 0.0, 1.0)
	if detail != "" and k > 0.0:
		var dw := fb.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL).x
		var p := Vector2(r.get_center().x - dw / 2, r.end.y + 15)
		draw_string_outline(fb, p, detail, HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL, 5, Color(0, 0, 0, 0.6 * k))
		draw_string(fb, p, detail, HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL, Color(UiTheme.PAPER, 0.85 * k))


func _key(r: Rect2, k: String, alpha: float) -> void:
	draw_style_box(UiTheme.box(Color(UiTheme.WARN, alpha), 4), r)
	draw_string(UiTheme.medium(), Vector2(r.position.x, r.get_center().y + (SIZE - 1) * 0.36), k, HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, SIZE - 1, UiTheme.INK)
