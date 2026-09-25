class_name GameUI
extends CanvasLayer
## Everything on screen that isn't the world: title menu, HUD (vitals, clock,
## hotbar, message feed), the step-by-step tutorial, help sheet and death screen.

signal host_requested(player_name: String)
signal join_requested(address: String, player_name: String)

const TUTORIAL := [
	["move", "เดินด้วย [W][A][S][D]"],
	["attack", "คลิกซ้ายเพื่อต่อย"],
	["kick", "คลิกขวาเตะ ผลักซอมบี้ออกไป"],
	["enter", "เดินเข้าไปในร้านที่มีประตู"],
	["search", "กด [E] ค้นหาของในร้าน"],
	["equip", "กดเลข [1]–[8] เพื่อถืออาวุธที่เจอ"],
]
const SETTINGS := "user://settings.cfg"

var menu: Control
var name_edit: LineEdit
var address_edit: LineEdit
var status: Label
var hud: Control
var vitals: Vitals
var clock: Clock
var tut: TutorialCard
var feed: VBoxContainer
var hotbar: InventoryBar
var build_bar: BuildBar
var help: Control
var banner: Label
var banner_t := 0.0
var death_label: Label
var death_sub: Label
var done_steps := {}
var cfg := ConfigFile.new()


func _ready() -> void:
	layer = 2
	cfg.load(SETTINGS)
	for id in cfg.get_value("tutorial", "done", []):
		done_steps[id] = true
	_build_hud()
	_build_help()
	_build_death()
	_build_menu()
	show_menu(true)


func player_name() -> String:
	var n := name_edit.text.strip_edges().left(16)
	return n if n != "" else "ผู้รอดชีวิต"


func show_menu(v: bool) -> void:
	menu.visible = v
	hud.visible = not v


func set_status(text: String) -> void:
	status.text = text


func set_inventory(inv: Array, sel: int) -> void:
	hotbar.show_inventory(inv, sel)


## A big message across the top of the screen for a few seconds.
func announce(text: String) -> void:
	banner.text = text
	banner_t = 5.0
	push_feed(text, "kill")


func toggle_help() -> void:
	help.visible = not help.visible and not menu.visible


# --- Message feed ------------------------------------------------------------

func push_feed(text: String, kind := "info") -> void:
	var p := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.CARD, 4)
	sb.border_width_left = 3
	sb.border_color = UiTheme.BLOOD if kind == "kill" else UiTheme.WARN
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 12
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.set_meta("age", 0.0)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.body_bold())
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UiTheme.PAPER)
	p.add_child(l)
	feed.add_child(p)
	while feed.get_child_count() > 5:
		var old := feed.get_child(0)
		feed.remove_child(old)
		old.queue_free()


# --- Tutorial ----------------------------------------------------------------

## Mark a tutorial step as done (called by the game when the player does it).
func tutorial(id: String) -> void:
	if done_steps.has(id):
		return
	done_steps[id] = true
	tut.flash = 1.0
	cfg.set_value("tutorial", "done", done_steps.keys())
	cfg.set_value("player", "name", player_name())
	cfg.save(SETTINGS)


# --- Per frame ---------------------------------------------------------------

func update_hud(delta: float, me: Player, day: int, time: float, online: int, building := false, build_kind := "") -> void:
	if me == null:
		return
	build_bar.visible = building
	hotbar.visible = not building
	if building:
		var wood := 0
		for it in me.inv:
			if it != null and it.id == "wood":
				wood += it.n
		build_bar.wood = wood
		build_bar.kind = build_kind
		build_bar.queue_redraw()
	vitals.t += delta
	vitals.pname = me.pname if me.pname != "" else player_name()
	vitals.hp = me.hp
	vitals.ghost = move_toward(vitals.ghost, me.hp, delta * 18.0) if vitals.ghost > me.hp else me.hp
	vitals.hunger = me.hunger
	vitals.thirst = me.thirst
	vitals.infection = me.infection
	vitals.bleeding = me.bleeding
	vitals.stamina = me.stamina
	vitals.exhausted = me.exhausted
	# How loud you are right now: 0 silent, 1 walking, 2 running, 3 just fought.
	var noise := 0
	if me.alive():
		if me.anim != Look.NONE and me.anim_t < 0.6:
			noise = 3
		elif me.moving and not me.sneak:
			noise = 2 if me.sprint and not me.exhausted else 1
	vitals.noise = noise
	vitals.sneak = me.sneak
	vitals.hint = _hint(me) if me.alive() else ""
	vitals.offset_top = vitals.offset_bottom - (150 if vitals.hint != "" else 126)
	vitals.queue_redraw()

	banner_t = maxf(0.0, banner_t - delta)
	banner.modulate.a = clampf(banner_t, 0.0, 1.0)
	clock.day = day
	clock.time = time
	clock.online = online
	clock.queue_redraw()

	var step := -1
	for i in TUTORIAL.size():
		if not done_steps.has(TUTORIAL[i][0]):
			step = i
			break
	tut.flash = maxf(0.0, tut.flash - delta * 1.5)
	tut.visible = (step >= 0 or tut.flash > 0) and me.alive()
	if step >= 0:
		tut.text = TUTORIAL[step][1]
		tut.index = step
	tut.done_flags = TUTORIAL.map(func(st): return done_steps.has(st[0]))
	tut.queue_redraw()

	for p in feed.get_children():
		var age: float = p.get_meta("age") + delta
		p.set_meta("age", age)
		p.modulate.a = clampf((6.0 - age) / 1.5, 0.0, 1.0) * (0.55 if p.get_index() < feed.get_child_count() - 2 else 1.0)
		if age > 6.0:
			feed.remove_child(p)
			p.queue_free()

	var k := clampf((me.death_t - 0.6) / 1.2, 0.0, 1.0) if not me.alive() else 0.0
	death_label.modulate.a = k
	death_sub.modulate.a = k
	death_label.text = "คุณกลายเป็นซอมบี้" if me.turned else "คุณตายแล้ว"
	if not me.alive():
		death_sub.text = "ของที่ถืออยู่ร่วงอยู่ข้างศพ  ·  เกิดใหม่ใน %d วินาที" % ceili(maxf(0.0, Player.RESPAWN_TIME - me.death_t))


## The most urgent thing in the bag that would help right now.
func _hint(me: Player) -> String:
	var wants := []  # [urgency, stat key, reason]
	if me.bleeding:
		wants.append([90, "stop_bleed", "ห้ามเลือด"])
	if me.infection > 25.0:
		wants.append([60 + me.infection * 0.3, "cure", "ลดเชื้อ"])
	if me.hp < 35.0:
		wants.append([80 - me.hp, "heal", "รักษา"])
	if me.thirst < 20.0:
		wants.append([70 - me.thirst, "drink", "ดื่ม"])
	if me.hunger < 20.0:
		wants.append([65 - me.hunger, "food", "กิน"])
	wants.sort_custom(func(a, b): return a[0] > b[0])
	for w in wants:
		var best := -1
		var best_v := 0.0
		for i in me.inv.size():
			var it = me.inv[i]
			if it == null:
				continue
			var v = Items.def(it.id).get(w[1], 0.0)
			v = 1.0 if typeof(v) == TYPE_BOOL and v else float(v) if typeof(v) != TYPE_BOOL else 0.0
			if v > best_v:
				best_v = v
				best = i
		if best >= 0:
			return "กด [%d] แล้ว [F] %s ด้วย %s" % [best + 1, w[2], Items.display_name(me.inv[best].id)]
	return ""


# --- Building ----------------------------------------------------------------

func _label(text: String, f: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	vitals = Vitals.new()
	vitals.anchor_top = 1.0
	vitals.anchor_bottom = 1.0
	vitals.offset_left = 24
	vitals.offset_right = 24 + 270
	vitals.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vitals.offset_bottom = -24
	vitals.offset_top = -24 - 126
	hud.add_child(vitals)

	clock = Clock.new()
	clock.anchor_left = 1.0
	clock.anchor_right = 1.0
	clock.offset_left = -440
	clock.offset_right = -24
	clock.offset_top = 18
	clock.offset_bottom = 120
	hud.add_child(clock)

	tut = TutorialCard.new()
	tut.anchor_left = 0.5
	tut.anchor_right = 0.5
	tut.offset_left = -230
	tut.offset_right = 230
	tut.offset_top = 24
	tut.offset_bottom = 24 + 96
	tut.pivot_offset = Vector2(230, 48)
	tut.rotation = -0.017
	hud.add_child(tut)

	feed = VBoxContainer.new()
	feed.anchor_left = 1.0
	feed.anchor_right = 1.0
	feed.anchor_top = 1.0
	feed.anchor_bottom = 1.0
	feed.offset_left = -420
	feed.offset_right = -24
	feed.offset_top = -330
	feed.offset_bottom = -130
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.add_theme_constant_override("separation", 6)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(feed)

	hotbar = InventoryBar.new()
	hud.add_child(hotbar)
	build_bar = BuildBar.new()
	build_bar.visible = false
	build_bar.anchor_left = 0.5
	build_bar.anchor_right = 0.5
	build_bar.anchor_top = 1.0
	build_bar.anchor_bottom = 1.0
	build_bar.offset_left = -300
	build_bar.offset_right = 300
	build_bar.offset_top = -150
	build_bar.offset_bottom = -20
	hud.add_child(build_bar)

	banner = _label("", UiTheme.heavy(), 34, Color("ff6a5a"))
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.offset_left = -520
	banner.offset_right = 520
	banner.offset_top = 140
	banner.offset_bottom = 190
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 12)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	banner.modulate.a = 0.0
	hud.add_child(banner)


func _build_death() -> void:
	death_label = _label("คุณตายแล้ว", UiTheme.heavy(), 72, Color("d8342a"))
	death_sub = _label("", UiTheme.body_bold(), 22, Color(1, 1, 1, 0.9))
	for l in [death_label, death_sub]:
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		l.offset_left = -500
		l.offset_right = 500
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 12)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.modulate.a = 0.0
		add_child(l)
	death_label.offset_top = -140
	death_label.offset_bottom = -40
	death_sub.offset_top = -10
	death_sub.offset_bottom = 30


func _build_help() -> void:
	help = Control.new()
	help.set_anchors_preset(Control.PRESET_FULL_RECT)
	help.visible = false
	add_child(help)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.02, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	help.add_child(dim)
	var sheet := HelpSheet.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sheet.offset_left = -370
	sheet.offset_right = 370
	sheet.offset_top = -320
	sheet.offset_bottom = 320
	sheet.pivot_offset = Vector2(370, 320)
	sheet.rotation = 0.01
	help.add_child(sheet)


func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.38, 0.72])
	grad.colors = PackedColorArray([Color(0.03, 0.03, 0.02, 0.95), Color(0.03, 0.03, 0.02, 0.78), Color(0.03, 0.03, 0.02, 0.08)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	var dim := TextureRect.new()
	dim.texture = gt
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dim.stretch_mode = TextureRect.STRETCH_SCALE
	menu.add_child(dim)

	var days := _label("DAYS", UiTheme.heavy(), 104, UiTheme.PAPER)
	var later := _label("LATER", UiTheme.heavy(), 104, UiTheme.BLOOD)
	days.add_theme_color_override("font_shadow_color", Color("7a1510"))
	later.add_theme_color_override("font_shadow_color", Color("3a0806"))
	for l in [days, later]:
		l.add_theme_constant_override("shadow_offset_x", 4)
		l.add_theme_constant_override("shadow_offset_y", 4)
		menu.add_child(l)
	days.position = Vector2(86, 60)
	later.position = Vector2(86, 150)
	var sub := _label("กรุงเทพฯ · หลังวันสิ้นโลก", UiTheme.medium(), 24, Color(UiTheme.PAPER, 0.75))
	sub.position = Vector2(92, 282)
	menu.add_child(sub)

	var form := VBoxContainer.new()
	form.position = Vector2(90, 350)
	form.custom_minimum_size = Vector2(400, 0)
	form.add_theme_constant_override("separation", 12)
	menu.add_child(form)
	form.add_child(_label("ชื่อผู้รอดชีวิต", UiTheme.body(), 15, Color(UiTheme.PAPER, 0.7)))
	name_edit = _line_edit(cfg.get_value("player", "name", ""), "ใส่ชื่อของคุณ")
	form.add_child(name_edit)
	var host := _button("เล่นคนเดียว / เปิดห้อง", true)
	host.pressed.connect(func():
		cfg.set_value("player", "name", player_name())
		cfg.save(SETTINGS)
		host_requested.emit(player_name()))
	form.add_child(host)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	address_edit = _line_edit("127.0.0.1", "ที่อยู่เซิร์ฟเวอร์")
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(address_edit)
	var join := _button("เข้าร่วม", false)
	join.pressed.connect(func():
		cfg.set_value("player", "name", player_name())
		cfg.save(SETTINGS)
		join_requested.emit(address_edit.text.strip_edges(), player_name()))
	row.add_child(join)
	form.add_child(row)
	status = _label("", UiTheme.body(), 15, UiTheme.WARN)
	form.add_child(status)
	var ver := _label("v0.3 · ต้นแบบ · กด H ในเกมเพื่อดูวิธีเล่น", UiTheme.body(), 14, Color(UiTheme.PAPER, 0.4))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 90
	ver.offset_top = -50
	menu.add_child(ver)


func _line_edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", UiTheme.body())
	e.add_theme_font_size_override("font_size", 18)
	e.add_theme_color_override("font_color", UiTheme.PAPER)
	e.add_theme_stylebox_override("normal", UiTheme.box(Color(0.91, 0.88, 0.81, 0.08), 6, UiTheme.LINE, 1))
	e.add_theme_stylebox_override("focus", UiTheme.box(Color(0.91, 0.88, 0.81, 0.12), 6, UiTheme.WARN, 1))
	return e


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", UiTheme.heading())
	b.add_theme_font_size_override("font_size", 21)
	var bg := UiTheme.WARN if primary else Color(0.91, 0.88, 0.81, 0.06)
	var fg := UiTheme.INK if primary else UiTheme.PAPER
	for state in ["normal", "hover", "pressed", "focus"]:
		var c := bg
		if state == "hover":
			c = bg.lightened(0.12)
		elif state == "pressed":
			c = bg.darkened(0.15)
		var sb := UiTheme.box(c, 6, UiTheme.LINE if not primary else Color(0, 0, 0, 0), 0 if primary else 1)
		if primary:
			sb.shadow_color = Color("9a7a18")
			sb.shadow_offset = Vector2(0, 4)
			sb.shadow_size = 1
		b.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, fg)
	return b


# --- Custom-drawn pieces -------------------------------------------------------

class Vitals extends Control:
	var pname := ""
	var hp := 100.0
	var ghost := 100.0
	var hint := ""
	var t := 0.0
	var hunger := 80.0
	var thirst := 80.0
	var infection := 0.0
	var bleeding := false
	var stamina := 100.0
	var exhausted := false
	var noise := 0
	var sneak := false

	## Speaker with 0-3 bars and a word, right-aligned at `right`.
	func _draw_noise(right: Vector2) -> void:
		var words := ["เงียบ", "เบา", "ดัง", "ดังมาก"]
		var cols := [Color(UiTheme.PAPER, 0.4), Color(UiTheme.PAPER, 0.8), UiTheme.WARN, Color("ff5a4a")]
		var col: Color = cols[noise]
		var word: String = ("ย่อง · " if sneak else "") + words[noise]
		var f := UiTheme.body_bold()
		var tw := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(f, right - Vector2(tw, 0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		var x := right.x - tw - 8
		for i in 3:
			var h := 4.0 + i * 3.0
			var bx := x - (2 - i) * 4.0 - 3.0
			draw_rect(Rect2(bx, right.y - 1 - h, 2.5, h), col if i < noise else Color(UiTheme.PAPER, 0.15))
		var sp := x - 12 - 11.0
		draw_rect(Rect2(sp, right.y - 8, 3, 5), col)
		draw_colored_polygon(PackedVector2Array([Vector2(sp + 3, right.y - 8), Vector2(sp + 7, right.y - 11),
				Vector2(sp + 7, right.y), Vector2(sp + 3, right.y - 3)]), col)

	func _draw() -> void:
		var low := hp > 0 and hp < 30
		var pulse := 0.5 + 0.5 * sin(t * 7.0)
		draw_style_box(UiTheme.box(UiTheme.CARD, 8, UiTheme.BLOOD if low else UiTheme.LINE, 2 if low else 1), Rect2(Vector2.ZERO, size))
		draw_string(UiTheme.heading(), Vector2(16, 32), pname, HORIZONTAL_ALIGNMENT_LEFT, size.x - 150, 20, UiTheme.PAPER)
		# Next to the name: an urgent warning, if any.
		var alert := "ใกล้ตาย!" if low else ("เลือดออก!" if bleeding else "")
		low = low or bleeding
		if alert != "":
			var nw := UiTheme.heading().get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(UiTheme.body_bold(), Vector2(16 + nw + 10, 31), alert, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					Color(1, 0.42, 0.35, 0.55 + 0.45 * pulse))
		_draw_noise(Vector2(size.x - 16, 31))
		var hc := Color("ff3a2a") if low else UiTheme.BLOOD
		UiTheme.heart(self, Vector2(27, 60), 12.0 + (1.8 * pulse if low else 0.0), hc)
		var bar := Rect2(48, 54, size.x - 104, 12)
		draw_rect(bar, Color(1, 1, 1, 0.08))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(ghost / 100.0, 0, 1), bar.size.y)), Color(1, 0.86, 0.78, 0.35))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp / 100.0, 0, 1), bar.size.y)), hc)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp / 100.0, 0, 1), 3)), Color(1, 1, 1, 0.18))
		draw_string(UiTheme.medium(), Vector2(bar.end.x + 10, 66), str(ceili(hp)), HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				Color("ff6a5a") if low else UiTheme.PAPER)
		# Stamina: a thin bar under health.
		var st := Rect2(48, 70, bar.size.x, 3)
		draw_rect(st, Color(1, 1, 1, 0.06))
		draw_rect(Rect2(st.position, Vector2(st.size.x * stamina / 100.0, 3)),
				Color(1, 0.45, 0.3, 0.5 + 0.5 * pulse) if exhausted else Color(0.95, 0.85, 0.4, 0.8))
		# Needs row.
		var needs := [["อิ่ม", hunger, Color("c9a24a"), hunger < 25], ["น้ำ", thirst, Color("4a8ac9"), thirst < 25],
				["เชื้อ", infection, Color("7ab04a"), infection > 0]]
		for i in needs.size():
			var n: Array = needs[i]
			var x := 16.0 + i * (size.x - 16) / 3.0
			var cw := (size.x - 16) / 3.0 - 12
			var warn: bool = n[3] and (i < 2 or infection > 40)
			var lc := Color(1, 0.55, 0.45, 0.6 + 0.4 * pulse) if warn else Color(UiTheme.PAPER, 0.75)
			draw_string(UiTheme.body_bold(), Vector2(x, 100), n[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, lc)
			var b := Rect2(x, 106, cw, 5)
			draw_rect(b, Color(1, 1, 1, 0.08))
			draw_rect(Rect2(b.position, Vector2(b.size.x * n[1] / 100.0, b.size.y)), n[2])
			draw_string(UiTheme.body(), Vector2(x, 100), "%d" % n[1], HORIZONTAL_ALIGNMENT_RIGHT, cw, 12, Color(UiTheme.PAPER, 0.55))
		if hint != "":
			UiTheme.draw_rich(self, Vector2(16, 138), hint, UiTheme.body_bold(), 14, Color(1, 0.8, 0.75))


class Clock extends Control:
	var day := 1
	var time := 0.3
	var online := 1

	func _horde_now() -> bool:
		return (day % 3 == 0 and time > 0.764) or (day % 3 == 1 and day > 1 and time < 0.036)

	func _draw() -> void:
		var w := size.x
		var title := "วันที่ %d" % day
		draw_string_outline(UiTheme.heavy(), Vector2(0, 36), title, HORIZONTAL_ALIGNMENT_RIGHT, w, 34, 8, Color(0, 0, 0, 0.55))
		draw_string(UiTheme.heavy(), Vector2(0, 36), title, HORIZONTAL_ALIGNMENT_RIGHT, w, 34, UiTheme.PAPER)
		var hour := fmod(time * 24.0 + 2.4, 24.0)
		var night := time > 0.764 or time < 0.036
		var phase := "กลางคืน"
		if not night:
			if hour < 11.0:
				phase = "เช้า"
			elif hour < 16.0:
				phase = "กลางวัน"
			elif hour < 19.0:
				phase = "เย็น"
			else:
				phase = "พลบค่ำ"
		var line := "%02d:%02d · %s" % [int(hour), int(fmod(hour, 1.0) * 60), phase]
		var f := UiTheme.medium()
		var tw := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string_outline(f, Vector2(0, 64), line, HORIZONTAL_ALIGNMENT_RIGHT, w, 18, 6, Color(0, 0, 0, 0.5))
		draw_string(f, Vector2(0, 64), line, HORIZONTAL_ALIGNMENT_RIGHT, w, 18, Color(UiTheme.PAPER, 0.9))
		var ic := Vector2(w - tw - 16, 58)
		if night:
			draw_circle(ic, 7, Color("d8dce8"))
			draw_circle(ic + Vector2(3, -2), 6, Color(0.1, 0.1, 0.12))
		else:
			draw_circle(ic, 6, Color("ffb35c"))
		var warn := ""
		var wc := Color("ffb35c")
		if _horde_now():
			warn = "ฝูงซอมบี้กำลังบุก! อยู่ในที่ปลอดภัย"
			wc = Color("ff5a4a")
		elif day % 3 == 0 and time < 0.764:
			warn = "คืนนี้: ฝูงซอมบี้จะบุก"
			wc = Color("ff7a5a")
		elif time >= 0.70 and time < 0.764:
			warn = "อีก %d นาทีจะมืด ซอมบี้จะออกมามากขึ้น" % ceili((0.764 - time) * 24.0 * 60.0)
		elif night:
			warn = "ซอมบี้มองเห็นไกลขึ้นในความมืด"
			wc = Color("ff8a7a")
		if warn != "":
			draw_string_outline(UiTheme.body_bold(), Vector2(0, 88), warn, HORIZONTAL_ALIGNMENT_RIGHT, w, 15, 5, Color(0, 0, 0, 0.55))
			draw_string(UiTheme.body_bold(), Vector2(0, 88), warn, HORIZONTAL_ALIGNMENT_RIGHT, w, 15, wc)
		if online > 1:
			draw_string(UiTheme.body(), Vector2(0, 108), "ผู้เล่นออนไลน์ %d คน" % online, HORIZONTAL_ALIGNMENT_RIGHT, w, 13, Color(UiTheme.PAPER, 0.55))


class TutorialCard extends Control:
	var text := ""
	var index := 0
	var done_flags: Array = []
	var flash := 0.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.35))
		draw_rect(r, UiTheme.PAPER)
		for tape in [[Vector2(4, 4), -0.5], [Vector2(size.x - 4, 4), 0.42]]:
			draw_set_transform(tape[0], tape[1])
			draw_rect(Rect2(-30, -9, 60, 18), Color(0.9, 0.84, 0.63, 0.78))
		draw_set_transform(Vector2.ZERO)
		draw_string(UiTheme.heading(), Vector2(20, 28), "วิธีเอาชีวิตรอด", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("8a2a22"))
		draw_string(UiTheme.heading(), Vector2(0, 28), "%d / %d" % [index + 1, GameUI.TUTORIAL.size()],
				HORIZONTAL_ALIGNMENT_RIGHT, size.x - 20, 14, Color("8a2a22"))
		UiTheme.draw_rich(self, Vector2(20, 64), text, UiTheme.medium(), 22, UiTheme.INK)
		for i in GameUI.TUTORIAL.size():
			var done: bool = i < done_flags.size() and done_flags[i]
			draw_rect(Rect2(20 + i * 28, 80, 22, 4), Color("8a2a22") if done else UiTheme.PAPER_DARK)
		if flash > 0.0:
			draw_rect(r, Color(0.3, 0.6, 0.25, flash * 0.35))
			draw_string(UiTheme.heavy(), Vector2(0, 68), "✓", HORIZONTAL_ALIGNMENT_RIGHT, size.x - 24, 40, Color(0.2, 0.45, 0.15, flash))


class HelpSheet extends Control:
	const ROWS := [
		["[W][A][S][D]", "เดิน"], ["[E]", "ค้นของ / เก็บของ"],
		["[คลิกซ้าย]", "ต่อย / ฟาดอาวุธ"], ["[1]–[8]", "เลือกช่องของ"],
		["[คลิกขวา]", "เตะ ผลักซอมบี้ออก"], ["[F]", "ใช้ของ (กิน / รักษา)"],
		["[ลูกกลิ้ง]", "ซูมกล้อง"], ["[G]", "ทิ้งของ"],
		["[Shift]", "วิ่ง (เร็ว แต่เสียงดัง)"], ["[Ctrl]/[C]", "ย่อง (เงียบ ซอมบี้เห็นยาก)"],
		["[R]", "ตอกไม้เสริม / ซ่อมประตู"], ["[E] ที่บันได", "ขึ้น / ลงดาดฟ้า"],
		["[B]", "โหมดสร้าง: รั้ว กำแพง ลวดหนาม กับดัก"], ["[H]", "เปิด / ปิดหน้านี้"],
	]

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position + Vector2(0, 12), r.size), Color(0, 0, 0, 0.4))
		draw_rect(r, UiTheme.PAPER)
		draw_string(UiTheme.heavy(), Vector2(36, 62), "วิธีเล่น", HORIZONTAL_ALIGNMENT_LEFT, -1, 38, UiTheme.INK)
		draw_string(UiTheme.body(), Vector2(36, 92), "กด H อีกครั้งเพื่อปิด", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiTheme.INK, 0.6))
		for i in ROWS.size():
			var col := i % 2
			var row := i / 2
			var p := Vector2(36 + col * 350, 140 + row * 50)
			var kw := UiTheme.draw_rich(self, p, ROWS[i][0], UiTheme.heading(), 16, UiTheme.INK)
			draw_string(UiTheme.body_bold(), p + Vector2(maxf(kw, 60) + 14, 0), ROWS[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.INK)
			draw_dashed_line(p + Vector2(0, 16), p + Vector2(320, 16), UiTheme.PAPER_DARK, 1.0, 4.0)
		draw_string(UiTheme.body(), Vector2(36, size.y - 30), "ทุก 3 วันจะมีคืนฝูง: ยึดร้านสักหลัง กด E ปิดประตู แล้วกด R ตอกไม้ให้แน่น",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiTheme.INK, 0.65))


class BuildBar extends Control:
	var wood := 0
	var kind := "fence"

	func _draw() -> void:
		var title := "โหมดสร้าง · ไม้กระดาน %d แผ่น" % wood
		draw_string_outline(UiTheme.medium(), Vector2(0, 24), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 8, Color(0, 0, 0, 0.6))
		draw_string(UiTheme.medium(), Vector2(0, 24), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, UiTheme.PAPER)
		var hint := "[คลิกซ้าย] วาง  ·  [R] ซ่อม  ·  [B] ออก"
		var hw := UiTheme.draw_rich(self, Vector2.ZERO, hint, UiTheme.body(), 14, UiTheme.PAPER, true)
		UiTheme.draw_rich(self, Vector2((size.x - hw) / 2, 46), hint, UiTheme.body(), 14, Color(UiTheme.PAPER, 0.8))
		var n := World.BUILD_ORDER.size()
		var cw := 136.0
		var x0 := (size.x - n * cw - (n - 1) * 8) / 2
		for i in n:
			var k: String = World.BUILD_ORDER[i]
			var b: Dictionary = World.BUILDS[k]
			var r := Rect2(x0 + i * (cw + 8), 62, cw, 56)
			var sel := k == kind
			var afford: bool = wood >= b.cost
			draw_style_box(UiTheme.box(Color("ad9870") if afford else Color(0.11, 0.1, 0.08, 0.75), 6, UiTheme.WARN if sel else Color("6e5b3c"), 3 if sel else 2), r)
			var ink: Color = UiTheme.INK if afford else Color(UiTheme.PAPER, 0.5)
			draw_string(UiTheme.heading(), r.position + Vector2(10, 22), "%d  %s" % [i + 1, b.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)
			draw_string(UiTheme.body_bold(), r.position + Vector2(10, 44), "ใช้ไม้ %d" % b.cost + (" · กั้นทาง" if b.solid else " · กับดัก"),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(ink, 0.75))
