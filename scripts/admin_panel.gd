class_name AdminPanel
extends Control
## The developer panel (F2, host only): every item by category, click to
## conjure one (shift: ten), and buttons for healing, zombies and the time.
## See Admin for what the server does with each.

signal give_requested(id: String, n: int)
signal heal_requested
signal zombie_requested(kind: String)  # at the mouse, placed by main
signal clear_requested(radius: float)
signal time_requested(t: float)

const W := 820.0
const H := 520.0
const CELL := 64.0
const COLS := 11
const CATS := [["all", "ทั้งหมด"], ["weapon", "อาวุธ"], ["clothes", "เสื้อผ้า"], ["medicine", "ยา"], ["food", "อาหาร"],
		["drink", "น้ำ"], ["material", "วัสดุ"], ["junk", "อื่นๆ"]]
const ACTIONS := [["heal", "รักษาเต็ม"], ["z_normal", "ซอมบี้"], ["z_runner", "ตัววิ่ง"], ["z_fat", "ตัวอ้วน"],
		["z_screamer", "ตัวกรีดร้อง"], ["clear", "ลบซอมบี้ใกล้ๆ"], ["morning", "เช้า"], ["noon", "เที่ยง"], ["night", "กลางคืน"]]

var cat := "all"
var scroll := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -W / 2
	offset_right = W / 2
	offset_top = -H / 2 - 30
	offset_bottom = H / 2 - 30
	mouse_filter = Control.MOUSE_FILTER_STOP


func _items() -> Array:
	var ids := Items.DEFS.keys().filter(func(id): return cat == "all" or Items.category(id) == cat)
	ids.sort_custom(func(a, b): return Items.category(a) + a < Items.category(b) + b)
	return ids


func _cell(i: int) -> Rect2:
	var row := i / COLS - scroll
	return Rect2(20 + (i % COLS) * (CELL + 8), 92 + row * (CELL + 8), CELL, CELL)


func _cat_rect(i: int) -> Rect2:
	return Rect2(20 + i * 86, 50, 80, 28)


func _action_rect(i: int) -> Rect2:
	return Rect2(20 + i * 87, H - 50, 82, 32)


func _visible(r: Rect2) -> bool:
	return r.position.y >= 88 and r.end.y <= H - 62


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		accept_event()
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll = mini(scroll + 1, maxi(0, ceili(_items().size() / float(COLS)) - 5))
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll = maxi(0, scroll - 1)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			for i in CATS.size():
				if _cat_rect(i).has_point(e.position):
					cat = CATS[i][0]
					scroll = 0
			var ids := _items()
			for i in ids.size():
				var r := _cell(i)
				if _visible(r) and r.has_point(e.position):
					give_requested.emit(ids[i], 10 if e.shift_pressed else 1)
			for i in ACTIONS.size():
				if _action_rect(i).has_point(e.position):
					_act(ACTIONS[i][0])
		queue_redraw()
	elif e is InputEventMouseMotion:
		queue_redraw()


func _act(a: String) -> void:
	match a:
		"heal":
			heal_requested.emit()
		"clear":
			clear_requested.emit(400.0)
		"morning":
			time_requested.emit(0.28)
		"noon":
			time_requested.emit(0.5)
		"night":
			time_requested.emit(0.85)
		_:
			zombie_requested.emit(a.trim_prefix("z_"))


func _draw() -> void:
	var head := UiTheme.heading()
	var body := UiTheme.body()
	var m := get_local_mouse_position()
	draw_style_box(UiTheme.box(Color(0.06, 0.055, 0.045, 0.98), 10, Color("8a3a2a"), 2), Rect2(Vector2.ZERO, size))
	draw_string(head, Vector2(20, 34), "เมนูแอดมิน (ทดสอบ)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.PAPER)
	draw_string(body, Vector2(220, 34), "คลิกเพื่อเสก 1 ชิ้น · Shift+คลิก 10 ชิ้น · ล้อเมาส์เลื่อน · [F2] ปิด", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(UiTheme.PAPER, 0.5))
	for i in CATS.size():
		var r := _cat_rect(i)
		var on: bool = cat == CATS[i][0]
		draw_style_box(UiTheme.box(UiTheme.WARN if on else Color(0.91, 0.88, 0.81, 0.12 if r.has_point(m) else 0.05), 6), r)
		draw_string(head, r.position + Vector2(0, 19), CATS[i][1], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, UiTheme.INK if on else UiTheme.PAPER)
	var ids := _items()
	var tip := ""
	for i in ids.size():
		var r := _cell(i)
		if not _visible(r):
			continue
		var lit := r.has_point(m)
		draw_style_box(UiTheme.box(Color("ad9870"), 6, UiTheme.WARN if lit else Color("6e5b3c"), 2), r)
		Items.draw_icon(self, r.grow(-12), ids[i])
		var rarity := Items.rarity_of(ids[i])
		if rarity != "common":
			draw_colored_polygon(PackedVector2Array([r.position + Vector2(4, 4), r.position + Vector2(14, 4), r.position + Vector2(4, 14)]),
					Items.RARITY_COLORS[rarity])
		if lit:
			tip = "%s  ·  %s" % [Items.display_name(ids[i]), ids[i]]
	draw_string(body, Vector2(20, H - 66), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.PAPER)
	for i in ACTIONS.size():
		var r := _action_rect(i)
		draw_style_box(UiTheme.box(UiTheme.WARN if r.has_point(m) else Color(0.91, 0.88, 0.81, 0.08), 6), r)
		draw_string(head, r.position + Vector2(0, 21), ACTIONS[i][1], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12,
				UiTheme.INK if r.has_point(m) else UiTheme.PAPER)
