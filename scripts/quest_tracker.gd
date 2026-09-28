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
	var small := UiTheme.medium()
	var P := UiTheme.SPACE_3
	var y := 0.0
	var first := true
	for id in active:
		if not Quests.DEFS.has(id):
			continue
		var d: Dictionary = Quests.DEFS[id]
		var counts: Array = active[id]
		var why: bool = first and _full_t > 0.0
		var why_lines := 0
		if why:
			why_lines = mini(3, ceili(body.get_string_size(d.desc, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_CAPTION).x / (W - P * 2)))
		var h: float = P * 2 + 16 + 22 + d.objectives.size() * 22 + (why_lines * 16.0 + 4.0 if why else 0.0)
		UiTheme.card(self, Rect2(0, y, W, h))
		var tag: String = "ภารกิจประจำวัน" if d.get("daily", false) else "ภารกิจ"
		draw_string(small, Vector2(P, y + P + 12), tag, HORIZONTAL_ALIGNMENT_LEFT, W - P * 2, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED)
		draw_string(head, Vector2(P, y + P + 33), d.name, HORIZONTAL_ALIGNMENT_LEFT, W - P * 2, UiTheme.SIZE_HEADING, UiTheme.ACCENT)
		var ly := y + P + 38
		if why:  # (wrapped: it says how, too)
			draw_multiline_string(body, Vector2(P, ly + 13), d.desc, HORIZONTAL_ALIGNMENT_LEFT, W - P * 2, UiTheme.SIZE_CAPTION, why_lines,
					Color(UiTheme.TEXT_MUTED, clampf(_full_t, 0.0, 1.0)))
			ly += why_lines * 16.0 + 4.0
		for i in d.objectives.size():
			var o: Dictionary = d.objectives[i]
			var c: int = counts[i] if i < counts.size() else 0
			var done: bool = c >= int(o.n)
			ly += 22
			var box := Rect2(P, ly - 11, 12, 12)
			if done:
				draw_style_box(UiTheme.rbox(UiTheme.OK, 2), box)
			else:
				draw_style_box(UiTheme.rbox(Color(0, 0, 0, 0), 2, UiTheme.TEXT_MUTED), box)
			var count := "" if int(o.n) <= 1 else "%d/%d" % [mini(c, int(o.n)), int(o.n)]
			var cw := small.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL).x
			var col := UiTheme.TEXT_MUTED if done else UiTheme.TEXT
			draw_string(body, Vector2(P + 20, ly), _fit(o.text, body, UiTheme.SIZE_BODY, W - P * 2 - 28 - cw), HORIZONTAL_ALIGNMENT_LEFT, -1,
					UiTheme.SIZE_BODY, col)
			if count != "":
				draw_string(small, Vector2(P, ly), count, HORIZONTAL_ALIGNMENT_RIGHT, W - P * 2, UiTheme.SIZE_LABEL, col)
		y += h + UiTheme.SPACE_2
		first = false


## `text` cut to fit `width`, with "…" if it had to be.
static func _fit(text: String, font: Font, fs: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		t = t.left(t.length() - 1)
	return t + "…"
