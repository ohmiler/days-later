class_name QuestTracker
extends Control
## What you're working toward, under the clock: each quest's name and what's
## left to do ("ฆ่าซอมบี้ 1/3"), the first one with a line of why. When
## something changes it shows in full for a while, then settles back to just
## the objectives (a clean screen: see ROADMAP "UI").

const W := 300.0
const FULL_TIME := 10.0  # seconds it shows the why after a change

var me: Player
var _last := {}
var _full_t := FULL_TIME


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if me == null:
		return
	var now: Dictionary = me.quests.get("active", {})
	if str(now) != str(_last):
		_last = now.duplicate(true)
		_full_t = FULL_TIME
	_full_t = maxf(0.0, _full_t - delta)
	queue_redraw()


func _draw() -> void:
	if me == null or not me.alive():
		return
	var active: Dictionary = me.quests.get("active", {})
	if active.is_empty():
		return
	var head := UiTheme.heading()
	var body := UiTheme.body()
	var y := 0.0
	var first := true
	for id in active:
		if not Quests.DEFS.has(id):
			continue
		var d: Dictionary = Quests.DEFS[id]
		var counts: Array = active[id]
		var lines: int = 1 + d.objectives.size()
		var why: bool = first and _full_t > 0.0
		var why_lines := 0
		if why:
			why_lines = mini(3, ceili(body.get_string_size(d.desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x / (W - 20)) + 0)
		var h: float = 12.0 + lines * 20.0 + why_lines * 15.0 + (4.0 if why else 0.0)
		draw_style_box(UiTheme.box(Color(0.06, 0.055, 0.045, 0.72), 6, Color(UiTheme.WARN, 0.35 if d.get("daily", false) else 0.7), 1),
				Rect2(0, y, W, h))
		var tag: String = "ประจำวัน · " if d.get("daily", false) else ""
		draw_string(head, Vector2(10, y + 20), tag + d.name, HORIZONTAL_ALIGNMENT_LEFT, W - 20, 14, UiTheme.WARN)
		var ly := y + 20
		if why:  # (wrapped: it says how, too)
			draw_multiline_string(body, Vector2(10, ly + 16), d.desc, HORIZONTAL_ALIGNMENT_LEFT, W - 20, 11, why_lines,
					Color(UiTheme.PAPER, 0.65 * clampf(_full_t, 0.0, 1.0)))
			ly += why_lines * 15.0 + 4.0
		for i in d.objectives.size():
			var o: Dictionary = d.objectives[i]
			var c: int = counts[i] if i < counts.size() else 0
			var done: bool = c >= int(o.n)
			ly += 20
			var box := Rect2(10, ly - 10, 10, 10)
			draw_rect(box, Color(UiTheme.WARN, 0.9) if done else Color(UiTheme.PAPER, 0.5), done)
			var text: String = o.text + ("" if int(o.n) <= 1 else "  %d/%d" % [c, int(o.n)])
			draw_string(body, Vector2(28, ly), _fit(text, body, 13, W - 38), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(UiTheme.PAPER, 0.45) if done else UiTheme.PAPER)
		y += h + 6
		first = false


## `text` cut to fit `width`, with "…" if it had to be.
static func _fit(text: String, font: Font, fs: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		t = t.left(t.length() - 1)
	return t + "…"
