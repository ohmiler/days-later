class_name AdminPanel
extends Control
## The developer panel (F2, host only), in four tabs:
##   ไอเทม   every item, by category or by search; click to conjure one (shift: ten)
##   ซอมบี้  every kind (Zombie.KINDS), how many, rare costumes, freeze, clear
##   ตัวเรา  heal, god mode, every wound (Body.KINDS) and condition (Body.CONDITIONS)
##   โลก     the time, skipping hours, rain, a horde, going to the big buildings
## The lists are read from the game's own tables, so a new item, zombie kind,
## wound or condition turns up here by itself. See Admin for the server side.

signal give_requested(id: String, n: int)
signal heal_requested
signal zombie_requested(kind: String, n: int, special: bool, dummy: bool)  # around you, placed by main
signal clear_requested(radius: float)
signal time_requested(t: float)
signal command_requested(rpc_name: StringName, args: Array)  # everything else (see Admin)

const W := 860.0
const H := 540.0
const CELL := 60.0
const COLS := 12
const TABS := [["items", "ไอเทม"], ["zombies", "ซอมบี้"], ["self", "ตัวเรา"], ["world", "โลก"]]
const CATS := [["all", "ทั้งหมด"], ["weapon", "อาวุธ"], ["clothes", "เสื้อผ้า"], ["medicine", "ยา"], ["food", "อาหาร"],
		["drink", "น้ำ"], ["material", "วัสดุ"], ["junk", "อื่นๆ"]]
## Names for things the tables only know by id.
const ZOMBIE_NAMES := {normal = "ธรรมดา", runner = "ตัววิ่ง", fat = "ตัวอ้วน", screamer = "ตัวกรีดร้อง",
		junkie = "ติดยา", faker = "ศพปลอม", guard = "ยาม", aerobic = "แอโรบิก"}
const BIG_NAMES := {hospital = "โรงพยาบาล", flats = "แฟลต", office = "ออฟฟิศ", mall = "ห้าง", market = "ตลาด"}

var tab := "items"
var cat := "all"
var scroll := 0
var count := 1  # zombies at a time
var still := false  # spawn practice dummies: standing still, backs to you
var search: LineEdit
var _buttons: Array = []  # [rect, label, callable, lit] for the current tab (rebuilt when it changes)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -W / 2
	offset_right = W / 2
	offset_top = -H / 2 - 30
	offset_bottom = H / 2 - 30
	mouse_filter = Control.MOUSE_FILTER_STOP
	search = LineEdit.new()
	search.placeholder_text = "ค้นหา (ชื่อหรือ id)"
	search.position = Vector2(W - 220, 92)
	search.size = Vector2(200, 28)
	UiTheme.style_input(search)
	search.add_theme_font_size_override("font_size", UiTheme.SIZE_LABEL)
	for st in ["normal", "focus"]:
		var sb: StyleBoxFlat = search.get_theme_stylebox(st)
		sb.content_margin_top = 4
		sb.content_margin_bottom = 5
	search.text_changed.connect(func(_t): scroll = 0; queue_redraw())
	add_child(search)
	visibility_changed.connect(func():
		if not visible:
			search.release_focus())


## Typing in the search box (the game mustn't walk on W, A, S, D).
func searching() -> bool:
	return visible and search.has_focus()


func _items() -> Array:
	var q := search.text.strip_edges().to_lower()
	var ids := Items.DEFS.keys().filter(func(id):
		if q != "":
			return q in id.to_lower() or q in Items.display_name(id).to_lower()
		return cat == "all" or Items.category(id) == cat)
	ids.sort_custom(func(a, b): return Items.category(a) + a < Items.category(b) + b)
	return ids


func _cell(i: int) -> Rect2:
	var row := i / COLS - scroll
	return Rect2(20 + (i % COLS) * (CELL + 8), 132 + row * (CELL + 8), CELL, CELL)


func _tab_rect(i: int) -> Rect2:
	return Rect2(20 + i * 100, 50, 94, 30)


func _cat_rect(i: int) -> Rect2:
	return Rect2(20 + i * 74, 92, 70, 28)


func _visible(r: Rect2) -> bool:
	return r.position.y >= 128 and r.end.y <= H - 36


## The buttons of the tab that is open, laid out in rows under headings.
func _build() -> void:
	_buttons.clear()
	var y := 100.0
	match tab:
		"zombies":
			var opts: Array = [1, 5, 20].map(func(n): return ["×%d" % n, func(): count = n, count == n])
			opts.append(["ยืนนิ่ง (หุ่นซ้อม)", func(): still = not still, still])
			y = _row(y, "จำนวน", opts)
			var kinds := Zombie.KINDS.keys().map(func(k): return [ZOMBIE_NAMES.get(k, Bosses.DEFS.get(k, {}).get("name", k)), func(): zombie_requested.emit(k, count, false, still)])
			kinds.append(["ชุดพิเศษ (สุ่ม)", func(): zombie_requested.emit("", count, true, still)])
			y = _row(y, "เสกรอบตัว", kinds)
			var admin: Admin = _admin()
			y = _row(y, "ควบคุม", [
				["หยุดนิ่ง", func(): command_requested.emit(&"req_toggle", ["freeze"]), admin != null and admin.frozen],
				["ลบใกล้ๆ", func(): clear_requested.emit(400.0)],
				["ลบทั้งหมด", func(): clear_requested.emit(1e9)],
				["ฝูงบุกเดี๋ยวนี้", func(): command_requested.emit(&"req_horde", [])]])
		"self":
			var me := _me()
			y = _row(y, "ร่างกาย", [["รักษาเต็ม", func(): heal_requested.emit()],
				["อมตะ", func(): command_requested.emit(&"req_toggle", ["god"]), me != null and me.god],
				["หายทุกอาการ", func(): command_requested.emit(&"req_self", ["cure", ""])],
				["หิว", func(): command_requested.emit(&"req_self", ["hungry", ""])],
				["กระหาย", func(): command_requested.emit(&"req_self", ["thirsty", ""])],
				["หมดแรง", func(): command_requested.emit(&"req_self", ["tired", ""])],
				["ติดเชื้อ +50", func(): command_requested.emit(&"req_self", ["infect", ""])]])
			var wounds := Body.KINDS.keys().map(func(k): return [Body.KINDS[k].name, func(): command_requested.emit(&"req_self", ["wound", k])])
			wounds.append(["แผลอักเสบ", func(): command_requested.emit(&"req_self", ["fester", ""])])
			y = _row(y, "แผล", wounds)
			y = _row(y, "อาการ", Body.CONDITIONS.keys().map(func(k): return [Body.CONDITIONS[k].name,
					func(): command_requested.emit(&"req_self", ["condition", k])]))
		"world":
			y = _row(y, "เวลา", [["เช้า", func(): time_requested.emit(0.28)], ["เที่ยง", func(): time_requested.emit(0.5)],
				["เย็น", func(): time_requested.emit(0.7)], ["กลางคืน", func(): time_requested.emit(0.85)],
				["+1 ชม.", func(): command_requested.emit(&"req_skip", [1.0])], ["+6 ชม.", func(): command_requested.emit(&"req_skip", [6.0])],
				["+1 วัน", func(): command_requested.emit(&"req_skip", [24.0])]])
			var m := get_parent().get_parent() if get_parent() else null
			y = _row(y, "อากาศ", [["ฝนตก/หยุด", func(): command_requested.emit(&"req_toggle", ["rain"]), m is Main and m.raining]])
			y = _row(y, "วาร์ปไป", BigPlans.KINDS.keys().map(func(k): return [BIG_NAMES.get(k, k), func(): command_requested.emit(&"req_goto", [k])]))


## One row of buttons under a heading; returns where the next row goes.
func _row(y: float, heading: String, list: Array) -> float:
	var x := 130.0
	for e in list:
		var w := maxf(76.0, UiTheme.body().get_string_size(e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24.0)
		if x + w > W - 20:
			x = 130.0
			y += 40.0
		_buttons.append([Rect2(x, y, w, 32), e[0], e[1], e[2] if e.size() > 2 else false, heading if x == 130.0 and _buttons.all(func(b): return b[4] != heading) else ""])
		x += w + 8
	return y + 56.0


func _me() -> Player:
	var m := get_parent().get_parent() if get_parent() else null
	return m.players.get(m.multiplayer.get_unique_id()) if m is Main else null


func _admin() -> Admin:
	var m := get_parent().get_parent() if get_parent() else null
	return m.admin if m is Main else null


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		accept_event()
		if e.button_index == MOUSE_BUTTON_LEFT:
			search.release_focus()
		for i in TABS.size():
			if e.button_index == MOUSE_BUTTON_LEFT and _tab_rect(i).has_point(e.position):
				tab = TABS[i][0]
				scroll = 0
		search.visible = tab == "items"
		if tab == "items":
			if e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				scroll = mini(scroll + 1, maxi(0, ceili(_items().size() / float(COLS)) - 5))
			elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
				scroll = maxi(0, scroll - 1)
			elif e.button_index == MOUSE_BUTTON_LEFT:
				for i in CATS.size():
					if _cat_rect(i).has_point(e.position):
						cat = CATS[i][0]
						search.text = ""
						scroll = 0
				var ids := _items()
				for i in ids.size():
					var r := _cell(i)
					if _visible(r) and r.has_point(e.position):
						give_requested.emit(ids[i], 10 if e.shift_pressed else 1)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_build()
			for b in _buttons:
				if b[0].has_point(e.position):
					b[2].call()
			# (switches show their new state once the server has answered)
			get_tree().create_timer(0.2).timeout.connect(queue_redraw)
		queue_redraw()
	elif e is InputEventMouseMotion:
		queue_redraw()


func _draw() -> void:
	var head := UiTheme.heading()
	var body := UiTheme.body()
	var m := get_local_mouse_position()
	UiTheme.panel(self, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(UiTheme.RADIUS_LG, 0, size.x - UiTheme.RADIUS_LG * 2, 3), UiTheme.DANGER_DEEP)  # (red along the top: not part of the game)
	draw_string(head, Vector2(20, 36), "เมนูแอดมิน", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_TITLE, UiTheme.TEXT)
	var hw := head.get_string_size("เมนูแอดมิน", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_TITLE).x
	draw_string(UiTheme.medium(), Vector2(28 + hw, 35), "ทดสอบ · อ่านจากตารางของเกม ของใหม่มาเอง", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_CAPTION,
			UiTheme.TEXT_MUTED)
	var cw := UiTheme.draw_rich(self, Vector2.ZERO, "[F2] ปิด", body, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED, true, true)
	UiTheme.draw_rich(self, Vector2(size.x - 20 - cw, 35), "[F2] ปิด", body, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED, false, true)
	for i in TABS.size():
		_button(_tab_rect(i), TABS[i][1], tab == TABS[i][0], m, 14)
	if tab != "items":
		_build()
		for b in _buttons:
			if b[4] != "":
				draw_string(UiTheme.medium(), Vector2(20, b[0].position.y + 20), b[4], HORIZONTAL_ALIGNMENT_LEFT, 100, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED)
			_button(b[0], b[1], b[3], m, 13)
		return
	for i in CATS.size():
		_button(_cat_rect(i), CATS[i][1], cat == CATS[i][0] and search.text == "", m, 12)
	var ids := _items()
	var tip := "%d ชิ้น · คลิกเสก 1 · Shift+คลิก 10 · ล้อเมาส์เลื่อน" % ids.size()
	for i in ids.size():
		var r := _cell(i)
		if not _visible(r):
			continue
		var lit := r.has_point(m)
		var rarity := Items.rarity_of(ids[i])
		UiTheme.slot(self, r, true, false, lit, Items.RARITY_COLORS[rarity] if rarity != "common" else Color(0, 0, 0, 0))
		Items.draw_icon(self, r.grow(-11), ids[i])
		if lit:
			tip = "%s  ·  %s" % [Items.display_name(ids[i]), ids[i]]
	var rows := ceili(ids.size() / float(COLS))
	if rows > 5:  # where you are in the list
		var track := Rect2(W - 10, 132, 4, H - 170)
		draw_style_box(UiTheme.rbox(UiTheme.SURFACE_200, 2), track)
		var k := 5.0 / rows
		draw_style_box(UiTheme.rbox(UiTheme.BORDER_STRONG, 2), Rect2(track.position + Vector2(0, track.size.y * scroll / rows), Vector2(4, track.size.y * k)))
	draw_string(body, Vector2(20, H - 14), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED)


func _button(r: Rect2, text: String, on: bool, m: Vector2, fs: int) -> void:
	var hot := r.has_point(m)
	var bg := UiTheme.ACCENT if on else (UiTheme.SURFACE_300 if hot else UiTheme.SURFACE_200)
	draw_style_box(UiTheme.rbox(bg, UiTheme.RADIUS_SM, bg if on else (UiTheme.BORDER_STRONG if hot else UiTheme.BORDER)), r)
	fs = maxi(fs, UiTheme.SIZE_LABEL)
	draw_string(UiTheme.heading(), r.position + Vector2(0, r.size.y * 0.5 + fs * 0.4), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs,
			UiTheme.ON_ACCENT if on else UiTheme.TEXT)
