class_name GameUI
extends CanvasLayer
## Everything on screen that isn't the world: title menu, HUD (vitals, clock,
## hotbar, message feed), the step-by-step tutorial, help sheet and death screen.

signal host_requested(player_name: String, resume: bool)
signal join_requested(address: String, player_name: String)
signal leave_requested  # back to the title screen (saves first)
signal quit_requested
signal chat_sent(text: String)

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
var admin: AdminPanel  # F2, host only (see Admin)
var statuses: StatusRow
var weapons: WeaponPanel
var vitals: Vitals
var clock: Clock
var tut: TutorialCard
var feed: VBoxContainer
var hotbar: InventoryBar
var prompt_tag: PromptTag  # "E  open" over whatever is in reach
var dash: BikeDash  # the bike's dashboard while riding
var help: Control
var gear: BagScreen
var fs_button: Button
var pause: Control
var pause_fs: Button
var pause_gore: Button
var city_map: CityMap
var chat: LineEdit
var wheel: ActionWheel
var banner: Label
var banner_t := 0.0
var death_label: Label
var death_sub: Label
var done_steps := {}
var cfg := ConfigFile.new()
var appearance := {}
var preview: Preview


func _ready() -> void:
	layer = 2
	cfg.load(SETTINGS)
	Look.low_gore = cfg.get_value("video", "low_gore", false)
	set_volume(cfg.get_value("video", "volume", 0.8), false)
	for bus in ["Music", "Ambience"]:
		set_bus_volume(bus, cfg.get_value("video", "vol_" + bus, 1.0), false)
	# Full screen unless turned off; left alone for test runs, servers and the browser.
	if Engine.get_main_loop().get_script() == null and DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		set_fullscreen(cfg.get_value("video", "fullscreen", true), false)
	for id in cfg.get_value("tutorial", "done", []):
		done_steps[id] = true
	_build_hud()
	_build_help()
	gear = BagScreen.new()
	gear.visible = false
	add_child(gear)
	admin = AdminPanel.new()
	admin.visible = false
	add_child(admin)
	city_map = CityMap.new()
	city_map.visible = false
	add_child(city_map)
	_build_chat()
	_build_pause()
	_build_death()
	_build_menu()
	show_menu(true)


## This copy of the game's secret: made once and kept in the settings file. It
## is what proves a returning survivor is the same person, with no password.
func secret() -> String:
	if secret_override != "":
		return secret_override
	var s: String = cfg.get_value("player", "secret", "")
	if s.length() < 32:
		s = Crypto.new().generate_random_bytes(16).hex_encode()
		cfg.set_value("player", "secret", s)
		cfg.save(SETTINGS)
	return s


var secret_override := ""  # tests pose as someone else


func player_name() -> String:
	var n := name_edit.text.strip_edges().left(16)
	return n if n != "" else "ผู้รอดชีวิต"


## The look picked in the character creator, packed (see Look.pack).
func appearance_code() -> int:
	return Look.pack(appearance)


func show_menu(v: bool) -> void:
	menu.visible = v
	hud.visible = not v


func set_status(text: String) -> void:
	status.text = text


func set_inventory(inv: Array, sel: int) -> void:
	hotbar.show_inventory(inv, sel)
	gear.inv = inv
	gear.queue_redraw()


func set_worn(worn: Dictionary) -> void:
	var held := []
	for h in Items.HANDS:
		if worn.get(h) != null:
			var it: Dictionary = worn[h]
			if Items.is_gun(it.id):
				held.append("%s %d/%d" % [Items.display_name(it.id), it.get("ammo", 0), Items.def(it.id).mag])
			else:
				held.append(Items.display_name(it.id))
	hotbar.hands = " + ".join(held)
	hotbar.has_gun = Items.HANDS.any(func(h): return worn.get(h) != null and Items.is_gun(worn[h].id))
	hotbar.queue_redraw()
	gear.worn = worn
	gear.queue_redraw()


func toggle_gore() -> void:
	Look.low_gore = not Look.low_gore
	cfg.set_value("video", "low_gore", Look.low_gore)
	cfg.save(SETTINGS)
	if pause_gore:
		pause_gore.text = "เลือดและชิ้นส่วน: " + ("น้อย" if Look.low_gore else "เต็ม")


func set_bus_volume(bus: String, v: float, remember := true) -> void:
	Sfx.setup_buses()
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.01)
	if remember:
		cfg.set_value("video", "vol_" + bus, v)
		cfg.save(SETTINGS)


func set_volume(v: float, remember := true) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.01)
	if remember:
		cfg.set_value("video", "volume", v)
		cfg.save(SETTINGS)


## Something that takes the keyboard or the whole screen is open.
func typing() -> bool:
	return chat.visible


func overlay_open() -> bool:
	return pause.visible or city_map.visible or gear.visible or help.visible or admin.visible


func toggle_map() -> void:
	city_map.visible = not city_map.visible and not menu.visible and city_map.world != null


func toggle_pause() -> void:
	pause.visible = not pause.visible and not menu.visible
	if pause.visible:
		pause_fs.text = "เต็มจอ: " + ("เปิด" if is_fullscreen() else "ปิด") + "  (F11)"


## The Esc key: close whatever is open, or bring up the pause menu.
func escape() -> void:
	if admin.visible:
		admin.visible = false
	elif chat.visible:
		close_chat()
	elif city_map.visible:
		city_map.visible = false
	elif gear.visible:
		toggle_gear()
	elif help.visible:
		toggle_help()
	else:
		toggle_pause()


func open_chat() -> void:
	chat.visible = true
	chat.text = ""
	chat.grab_focus()


func close_chat() -> void:
	chat.release_focus()
	chat.visible = false


func show_chat(who: String, text: String) -> void:
	push_feed("%s: %s" % [who, text], "chat")


func _build_chat() -> void:
	chat = _line_edit("", "พิมพ์ข้อความ แล้วกด Enter · Esc ยกเลิก")
	chat.anchor_top = 1.0
	chat.anchor_bottom = 1.0
	chat.offset_left = 24
	chat.offset_right = 24 + 420
	chat.offset_top = -210
	chat.offset_bottom = -174
	chat.max_length = 120
	chat.visible = false
	chat.text_submitted.connect(func(t: String):
		var msg := t.strip_edges()
		if msg != "":
			chat_sent.emit(msg)
		close_chat())
	chat.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			close_chat()
			chat.accept_event())
	add_child(chat)


## Esc menu. The world keeps going while it is open: this is an online game.
func _build_pause() -> void:
	pause = Control.new()
	pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause.visible = false
	add_child(pause)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.02, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -200
	box.offset_right = 200
	box.offset_top = -270
	box.offset_bottom = 270
	box.add_theme_constant_override("separation", 12)
	pause.add_child(box)
	var title := _label("หยุดพัก", UiTheme.heavy(), 44, UiTheme.PAPER)
	title.custom_minimum_size = Vector2(0, 64)
	box.add_child(title)
	box.add_child(_label("โลกยังเดินต่อระหว่างเปิดเมนูนี้ ระวังตัวด้วย", UiTheme.body(), 15, Color(UiTheme.WARN, 0.9)))
	var resume := _button("เล่นต่อ", true)
	resume.pressed.connect(toggle_pause)
	box.add_child(resume)
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 12)
	var vl := _label("ระดับเสียง", UiTheme.body(), 16, UiTheme.PAPER)
	vl.custom_minimum_size = Vector2(90, 0)
	vol_row.add_child(vl)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = cfg.get_value("video", "volume", 0.8)
	vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol.value_changed.connect(func(v: float): set_volume(v))
	vol_row.add_child(vol)
	box.add_child(vol_row)
	for pair in [["Music", "เพลง"], ["Ambience", "บรรยากาศ"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := _label(pair[1], UiTheme.body(), 16, UiTheme.PAPER)
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = cfg.get_value("video", "vol_" + pair[0], 1.0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bus: String = pair[0]
		sl.value_changed.connect(func(v: float): set_bus_volume(bus, v))
		row.add_child(sl)
		box.add_child(row)
	pause_fs = _button("", false)
	pause_fs.pressed.connect(func():
		set_fullscreen(not is_fullscreen())
		pause_fs.text = "เต็มจอ: " + ("เปิด" if is_fullscreen() else "ปิด") + "  (F11)")
	box.add_child(pause_fs)
	pause_gore = _button("เลือดและชิ้นส่วน: " + ("น้อย" if Look.low_gore else "เต็ม"), false)
	pause_gore.pressed.connect(toggle_gore)
	box.add_child(pause_gore)
	var keys := _button("วิธีเล่น (H)", false)
	keys.pressed.connect(func():
		toggle_pause()
		toggle_help())
	box.add_child(keys)
	var leave := _button("กลับเมนูหลัก (บันทึกให้)", false)
	leave.pressed.connect(func(): leave_requested.emit())
	box.add_child(leave)
	var quit := _button("ออกจากเกม (บันทึกให้)", false)
	quit.pressed.connect(func(): quit_requested.emit())
	box.add_child(quit)


func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]


func set_fullscreen(on: bool, remember := true) -> void:
	if Engine.is_embedded_in_editor():
		# Played inside the editor's Game tab, which can only be a window.
		if remember:
			set_status("เล่นในแท็บ Game ของ Godot เต็มจอไม่ได้ · ปิด Embed ในแท็บ Game หรือเปิดไฟล์เกมตรงๆ")
			push_feed("เล่นในตัวแก้ไข Godot อยู่ · เต็มจอใช้ได้ตอนเปิดเกมในหน้าต่างของตัวเอง")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if remember:
		cfg.set_value("video", "fullscreen", on)
		cfg.save(SETTINGS)
	if fs_button:
		fs_button.text = "เต็มจอ: " + ("เปิด" if on else "ปิด") + "  (F11)"


func open_box(cid: int, items: Array, title: String) -> void:
	gear.box_id = cid
	gear.box_items = items
	gear.box_title = title
	gear.visible = true
	gear.queue_redraw()


func close_box() -> void:
	gear.box_id = -1
	gear.box_items = []
	gear.queue_redraw()


func toggle_gear() -> void:
	gear.visible = not gear.visible and not menu.visible
	if not gear.visible and gear.box_id >= 0:
		close_box()
		gear.box_closed.emit()
	if gear.visible:
		tutorial("gear")


## A big message across the top of the screen for a few seconds.
func announce(text: String) -> void:
	banner.text = text
	banner_t = 5.0
	push_feed(text, "kill")


func toggle_help() -> void:
	help.visible = not help.visible and not menu.visible


# --- Message feed ------------------------------------------------------------

func push_feed(text: String, kind := "info") -> void:
	if feed.get_child_count() > 0:
		var last := feed.get_child(feed.get_child_count() - 1)
		if last.get_meta("text", "") == text:
			var n: int = last.get_meta("n", 1) + 1
			last.set_meta("n", n)
			last.set_meta("age", 0.0)
			last.modulate.a = 1.0
			(last.get_child(0) as Label).text = "%s  ×%d" % [text, n]
			return
	var p := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.CARD, 4)
	sb.border_width_left = 3
	sb.border_color = UiTheme.BLOOD if kind == "kill" else (Color("5a9ad8") if kind == "chat" else UiTheme.WARN)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 12
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.set_meta("age", 0.0)
	p.set_meta("text", text)
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

func update_hud(delta: float, me: Player, day: int, time: float, online: int) -> void:
	if me == null:
		return
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
	vitals.on_roof = me.on_roof
	vitals.hint = _hint(me) if me.alive() else ""
	vitals.offset_top = vitals.offset_bottom - (150 if vitals.hint != "" else 126)
	vitals.queue_redraw()
	statuses.items = Body.statuses(me) if me.alive() else []
	# Riding: the dashboard comes up, and the hotbar and weapons (no use on a bike) fade back.
	var v: Dictionary = {}
	var w: World = me.world
	if me.alive() and me.riding >= 0 and me.seat == 0 and me.riding < w.vehicles.size():  # (the rider's; not on the back)
		v = w.vehicles[me.riding]
	dash.update(me, v, delta)
	hotbar.modulate.a = lerpf(1.0, 0.18, dash.k)
	if hotbar.quiet != (dash.k > 0.0):
		hotbar.quiet = dash.k > 0.0
		hotbar.queue_redraw()
	weapons.modulate.a = lerpf(1.0, 0.0, dash.k)
	weapons.me = me
	weapons.t = vitals.t
	weapons.queue_redraw()
	statuses.t = vitals.t
	statuses.offset_bottom = vitals.offset_bottom - (vitals.offset_bottom - vitals.offset_top) - 6
	statuses.offset_top = statuses.offset_bottom - 30
	statuses.queue_redraw()

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
	prompt_tag = PromptTag.new()
	hud.add_child(prompt_tag)
	dash = BikeDash.new()
	hud.add_child(dash)

	vitals = Vitals.new()
	vitals.anchor_top = 1.0
	vitals.anchor_bottom = 1.0
	vitals.offset_left = 24
	vitals.offset_right = 24 + 270
	vitals.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vitals.offset_bottom = -24
	vitals.offset_top = -24 - 126
	hud.add_child(vitals)

	weapons = WeaponPanel.new()
	weapons.anchor_left = 1.0
	weapons.anchor_right = 1.0
	weapons.anchor_top = 1.0
	weapons.anchor_bottom = 1.0
	weapons.offset_left = -24 - 250
	weapons.offset_right = -24
	weapons.offset_top = -24 - 64
	weapons.offset_bottom = -24
	weapons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(weapons)

	statuses = StatusRow.new()
	statuses.anchor_top = 1.0
	statuses.anchor_bottom = 1.0
	statuses.offset_left = 24
	statuses.offset_right = 24 + 600
	statuses.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(statuses)

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
	feed.offset_top = -360
	feed.offset_bottom = -160  # (above the weapon cards)
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.add_theme_constant_override("separation", 6)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(feed)

	hotbar = InventoryBar.new()
	hud.add_child(hotbar)
	wheel = ActionWheel.new()
	wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.visible = false
	add_child(wheel)

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
	# Carry on in the saved city, or start a new one (which replaces it).
	var info := SaveGame.world_info()
	if info.has("problem"):
		form.add_child(_label(info.problem, UiTheme.body_bold(), 15, UiTheme.WARN))
	elif info.get("oldcity", false):
		form.add_child(_label("เมืองนี้สร้างด้วยเกมรุ่นเก่า · ไปเมืองใหม่ได้ ตัวละครและของยังอยู่ครบ", UiTheme.body(), 14, UiTheme.WARN))
		var move := _button("ย้ายไปเมืองใหม่", true)
		move.pressed.connect(func():
			_remember_name()
			host_requested.emit(player_name(), true))
		form.add_child(move)
	elif not info.is_empty():
		var cont := _button("เล่นต่อ · วันที่ %d" % info.day, true)
		cont.pressed.connect(func():
			_remember_name()
			host_requested.emit(player_name(), true))
		form.add_child(cont)
	var fresh := _button("เริ่มเมืองใหม่", info.is_empty())
	fresh.pressed.connect(func():
		if not info.is_empty() and not fresh.has_meta("confirm"):
			fresh.set_meta("confirm", true)
			fresh.text = "กดอีกครั้งเพื่อยืนยัน · เมืองเดิมจะถูกย้ายไปเก็บสำรอง"
			return
		_remember_name()
		host_requested.emit(player_name(), false))
	form.add_child(fresh)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	address_edit = _line_edit("127.0.0.1", "ที่อยู่เซิร์ฟเวอร์")
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(address_edit)
	var join := _button("เข้าร่วม", false)
	join.pressed.connect(func():
		_remember_name()
		join_requested.emit(address_edit.text.strip_edges(), player_name()))
	row.add_child(join)
	form.add_child(row)
	var gore := _button("", false)
	var show_gore := func():
		gore.text = "เลือด: " + ("น้อย" if Look.low_gore else "เต็ม")
	show_gore.call()
	gore.add_theme_font_size_override("font_size", 16)
	gore.pressed.connect(func():
		toggle_gore()
		show_gore.call())
	fs_button = _button("", false)
	fs_button.add_theme_font_size_override("font_size", 16)
	fs_button.pressed.connect(func(): set_fullscreen(not is_fullscreen()))
	fs_button.text = "เต็มจอ: " + ("เปิด" if cfg.get_value("video", "fullscreen", true) else "ปิด") + "  (F11)"
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 8)
	for b: Button in [gore, fs_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opts.add_child(b)
	form.add_child(opts)
	status = _label("", UiTheme.body(), 15, UiTheme.WARN)
	form.add_child(status)
	_build_creator()
	var ver := _label("v0.3 · ต้นแบบ · กด H ในเกมเพื่อดูวิธีเล่น", UiTheme.body(), 14, Color(UiTheme.PAPER, 0.4))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 90
	ver.offset_top = -30
	menu.add_child(ver)


## Character creator: a turning preview with a picker for each part of the look.
func _build_creator() -> void:
	if cfg.has_section_key("player", "look"):
		appearance = Look.unpack(posmod(int(cfg.get_value("player", "look")), Look.appearance_count()))
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		appearance = Look.random_appearance(rng)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.03, 0.02, 0.72), 10, UiTheme.LINE, 1))
	panel.position = Vector2(740, 150)
	panel.custom_minimum_size = Vector2(430, 0)
	menu.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(130, 260)
	stage.clip_contents = true
	row.add_child(stage)
	preview = Preview.new()
	preview.position = Vector2(65, 225)
	preview.scale = Vector2(6.5, 6.5)
	stage.add_child(preview)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label("หน้าตาผู้รอดชีวิต", UiTheme.heading(), 18, UiTheme.PAPER))
	var names := {skin = "สีผิว", style = "ทรงผม", hair = "สีผม", shirt = "เสื้อ", pants = "กางเกง", build = "รูปร่าง"}
	var sizes := {skin = Look.SKINS.size(), style = Look.HAIR_STYLES.size(), hair = Look.HAIRS.size(),
			shirt = Look.SHIRTS.size(), pants = Look.PANTS.size(), build = Look.BUILDS.size()}
	var values := {}
	for key in ["skin", "style", "hair", "shirt", "pants", "build"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		col.add_child(line)
		var l := _label(names[key], UiTheme.body(), 15, Color(UiTheme.PAPER, 0.7))
		l.custom_minimum_size = Vector2(70, 0)
		line.add_child(l)
		var prev := _small_button("‹")
		var val := _label("", UiTheme.medium(), 15, UiTheme.PAPER)
		val.custom_minimum_size = Vector2(90, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var next := _small_button("›")
		values[key] = val
		for b: Button in [prev, next]:
			var step := -1 if b == prev else 1
			b.pressed.connect(func():
				appearance[key] = posmod(appearance[key] + step, sizes[key])
				_refresh_creator(values))
		line.add_child(prev)
		line.add_child(val)
		line.add_child(next)
	var dice := _button("สุ่มหน้าตา", false)
	dice.pressed.connect(func():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		appearance = Look.random_appearance(rng)
		_refresh_creator(values))
	col.add_child(dice)
	_refresh_creator(values, false)


func _refresh_creator(values: Dictionary, save := true) -> void:
	for key in values:
		var v: int = appearance[key]
		var text := "%d / %d" % [v + 1, {skin = Look.SKINS.size(), hair = Look.HAIRS.size(),
				shirt = Look.SHIRTS.size(), pants = Look.PANTS.size()}.get(key, 1)]
		if key == "style":
			text = Look.HAIR_STYLE_NAMES[v]
		elif key == "build":
			text = Look.BUILD_NAMES[v]
		values[key].text = text
	preview.look = Look.look_of(appearance)
	preview.queue_redraw()
	if save:
		cfg.set_value("player", "look", appearance_code())
		cfg.save(SETTINGS)


func _small_button(text: String) -> Button:
	var b := _button(text, false)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(32, 28)
	return b


func _remember_name() -> void:
	cfg.set_value("player", "name", player_name())
	cfg.set_value("player", "look", appearance_code())
	cfg.save(SETTINGS)


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
	b.pressed.connect(func(): Sfx.play_ui(self, "ui_click"))
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

## The character creator's model: stands and slowly turns, walking now and then.
class Preview extends Node2D:
	var look := {}
	var t := 0.0
	var view := [Look.FRONT, false]

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		t += delta
		queue_redraw()

	func _draw() -> void:
		if look.is_empty():
			return
		var angle := PI / 2 - t * 0.6
		view = Look.pick_view(angle, view)
		var walking := fmod(t, 8.0) > 5.0
		Look.draw(self, {view = view, angle = angle, phase = t * 9.0, moving = walking}, look)


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
	var on_roof := false

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
		var nw := UiTheme.heading().get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if alert != "":
			draw_string(UiTheme.body_bold(), Vector2(16 + nw + 10, 31), alert, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					Color(1, 0.42, 0.35, 0.55 + 0.45 * pulse))
		elif on_roof:
			draw_string(UiTheme.body_bold(), Vector2(16 + nw + 10, 31), "บนดาดฟ้า", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("8ad07a"))
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


## Icons for what's wrong with you (see Body.statuses): red means deal with it
## now, yellow means watch out. Point at one for what it is.
## Bottom right: a card for each hand that holds something: its icon, name and
## wear, and for a gun the rounds in it and in the bag (flashing when empty).
class WeaponPanel extends Control:
	var me: Player
	var t := 0.0

	func _draw() -> void:
		if me == null or not me.alive():
			return
		var cards := []
		for h in ["hand_r", "hand_l"]:
			var it = me.worn.get(h) if me.worn.has(h) else null
			if it == null and me.wear_ids.has(h):
				it = {id = me.wear_ids[h], n = 1, hp = 0}  # (someone else's copy: no numbers)
			if it != null:
				cards.append([h, it])
		var y := size.y
		for c in cards:
			y -= 64
			var it: Dictionary = c[1]
			var d := Items.def(it.id)
			var r := Rect2(0, y, size.x, 58)
			var gun := Items.is_gun(it.id)
			var empty: bool = gun and it.get("ammo", 0) <= 0
			var pulse := 0.5 + 0.5 * sin(t * 6.0)
			draw_style_box(UiTheme.box(UiTheme.CARD, 8, Color(1, 0.4, 0.3, pulse) if empty else UiTheme.LINE, 2 if empty else 1), r)
			Items.draw_icon(self, Rect2(r.position + Vector2(8, 8), Vector2(42, 42)), it.id)
			var f := UiTheme.heading()
			var hand: String = Items.HAND_NAMES[c[0]] + (" · สองมือ" if Items.two_handed(it.id) else "")
			draw_string(UiTheme.body(), r.position + Vector2(58, 18), hand, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UiTheme.PAPER, 0.5))
			draw_string(f, r.position + Vector2(58, 36), Items.display_name(it.id), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 130, 14, UiTheme.PAPER)
			if d.has("hp") and it.get("hp", 0) > 0:
				var frac: float = float(it.hp) / d.hp
				draw_rect(Rect2(r.position + Vector2(58, 44), Vector2(r.size.x - 130, 3)), Color(1, 1, 1, 0.1))
				draw_rect(Rect2(r.position + Vector2(58, 44), Vector2((r.size.x - 130) * frac, 3)), Color("4f9a3a") if frac > 0.3 else Color("c8502a"))
			if gun:
				var loaded: int = it.get("ammo", 0)
				var carried := Crafting.count_in(me.inv, d.ammo)
				draw_string(UiTheme.medium(), Vector2(r.end.x - 66, r.position.y + 34), "%d" % loaded, HORIZONTAL_ALIGNMENT_RIGHT, 30, 22,
						Color(1, 0.45, 0.35, 0.5 + 0.5 * pulse) if empty else UiTheme.PAPER)
				draw_string(UiTheme.body(), Vector2(r.end.x - 34, r.position.y + 34), "/%d" % carried, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
						Color(UiTheme.PAPER, 0.55))
				draw_string(UiTheme.body(), Vector2(r.end.x - 70, r.position.y + 50), "กด R บรรจุ" if empty and carried > 0 else
						("หมดกระสุน" if empty else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.55, 0.45))


class StatusRow extends Control:
	var items: Array = []
	var t := 0.0

	func _draw() -> void:
		var m := get_local_mouse_position()
		var tip := ""
		for i in items.size():
			var it: Dictionary = items[i]
			var r := Rect2(i * 34, 0, 30, 30)
			var col: Color = Body.LEVEL_COLORS[it.level]
			var pulse := 0.5 + 0.5 * sin(t * 6.0) if it.level == 2 else 1.0
			draw_style_box(UiTheme.box(Color(0.08, 0.07, 0.06, 0.85), 7, Color(col, 0.5 + 0.5 * pulse), 2), r)
			Body.draw_icon(self, r.get_center(), it.icon, col, 1.1)
			if it.get("n", 1) > 1:
				draw_string_outline(UiTheme.heavy(), r.position + Vector2(0, 30), "%d" % it.n, HORIZONTAL_ALIGNMENT_RIGHT, 28, 12, 4, Color.BLACK)
				draw_string(UiTheme.heavy(), r.position + Vector2(0, 30), "%d" % it.n, HORIZONTAL_ALIGNMENT_RIGHT, 28, 12, UiTheme.PAPER)
			if r.has_point(m):
				tip = it.text
		if tip != "":
			var f := UiTheme.body()
			var w := f.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16
			var tr := Rect2(0, -30, w, 24)
			draw_style_box(UiTheme.box(Color(0.08, 0.07, 0.06, 0.95), 6, UiTheme.LINE, 1), tr)
			draw_string(f, Vector2(8, -13), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.PAPER)


class Clock extends Control:
	var day := 1
	var time := 0.3
	var online := 1
	var _warn_kind := ""  # which warning is up; its full sentence shows for a while, then a short form
	var _warn_since := 0.0

	const WARN_FULL := 8.0  # seconds a warning is spelled out before it shrinks

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
		# [kind, the full sentence, the short form it shrinks to ("" to go)]
		var warn := ""
		var wc := Color("ffb35c")
		var kind := ""
		var short := ""
		if _horde_now():
			kind = "horde"
			warn = "ฝูงซอมบี้กำลังบุก! อยู่ในที่ปลอดภัย"
			short = "ฝูงซอมบี้บุก!"
			wc = Color("ff5a4a")
		elif day % 3 == 0 and time < 0.764:
			kind = "tonight"
			warn = "คืนนี้: ฝูงซอมบี้จะบุก"
			short = "คืนนี้ฝูงบุก"
			wc = Color("ff7a5a")
		elif time >= 0.70 and time < 0.764:
			kind = "dusk"
			var mins := ceili((0.764 - time) * 24.0 * 60.0)
			warn = "อีก %d นาทีจะมืด ซอมบี้จะออกมามากขึ้น" % mins
			short = "มืดใน %d นาที" % mins
		elif night:
			kind = "night"
			warn = "มืดแล้ว · ซอมบี้เห็นเราแค่ใกล้ ๆ เว้นแต่ยืนใต้ไฟ"
			wc = Color("ff8a7a")
		var now := Time.get_ticks_msec() / 1000.0
		if kind != _warn_kind:
			_warn_kind = kind
			_warn_since = now
		if now - _warn_since > WARN_FULL:
			warn = short
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
		["[คลิกซ้าย]", "ต่อย / ฟาดอาวุธ"], ["[1]–[0] / ลูกกลิ้ง", "เลือกช่องของ (คลิกได้)"],
		["[คลิกขวา]", "เตะ ผลักซอมบี้ออก"], ["[F]", "ใช้ของ / สวมเสื้อผ้า"],
		["[Ctrl]+ลูกกลิ้ง", "ซูมกล้อง"], ["[G]", "ทิ้งของ"],
		["[Shift]", "วิ่ง (เร็ว แต่เสียงดัง)"], ["[Ctrl]/[C]", "ย่อง (เงียบ ซอมบี้เห็นยาก)"],
		["[R]", "ตอกไม้เสริม / ซ่อมประตู"], ["[E] ที่บันได", "ขึ้น / ลงดาดฟ้า"],
		["[E] ค้าง", "เลือกสิ่งที่จะทำกับของตรงหน้า"], ["[H]", "เปิด / ปิดหน้านี้"],
		["[Tab]", "กระเป๋า · ลากของ / เก็บในตู้"], ["[Q]", "รักษาด่วน (ห้ามเลือดก่อน)"],
		["[M]", "แผนที่ · คลิกขวาปักหมุด"], ["[Z]", "นอนพัก ที่ไหนก็ได้ · บนเตียงหลับดีกว่า"], ["[X]", "นั่งพัก · เหนื่อยหายเร็ว · E ที่โซฟา/ม้านั่งเพื่อนั่ง"], ["[Enter]", "แชท · [Esc] เมนู"], ["เสื้อผ้า", "กันกัด ลดโอกาสติดเชื้อ แต่ขาดได้"],
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


## Hold E: every action for the thing in front of you, around a ring. Point the
## mouse at one and let go of E. Things you can't do are greyed out with why.
class ActionWheel extends Control:
	var title := ""
	var items: Array = []
	var centre := Vector2.ZERO
	var selected := -1
	const R := 92.0

	func open(t: String, list: Array, at: Vector2) -> void:
		title = t
		items = list
		centre = at
		selected = -1
		visible = true
		queue_redraw()

	func close() -> void:
		visible = false

	func chosen() -> Dictionary:
		return items[selected] if selected >= 0 and items[selected].ok else {}

	func point(mouse: Vector2) -> void:
		var v := mouse - centre
		var was := selected
		selected = -1
		if v.length() > 24.0 and not items.is_empty():
			var step := TAU / items.size()
			var a := fposmod(v.angle() + PI / 2 + step / 2, TAU)
			selected = int(a / step) % items.size()
		if selected != was:
			queue_redraw()

	func _slot_pos(i: int) -> Vector2:
		var a := -PI / 2 + i * TAU / items.size()
		return centre + Vector2.from_angle(a) * (R if items.size() > 1 else 0.0) + (Vector2(0, -R) if items.size() == 1 else Vector2.ZERO)

	func _draw() -> void:
		draw_circle(centre, R + 46, Color(0, 0, 0, 0.35))
		draw_circle(centre, 22, UiTheme.CARD)
		draw_string(UiTheme.heading(), centre + Vector2(-120, 6), title, HORIZONTAL_ALIGNMENT_CENTER, 240, 15, UiTheme.PAPER)
		for i in items.size():
			var a: Dictionary = items[i]
			var p := _slot_pos(i)
			var f := UiTheme.medium()
			var w := maxf(f.get_string_size(a.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 28, 110)
			var h := 34.0 if a.ok else 50.0
			var r := Rect2(p - Vector2(w / 2, h / 2), Vector2(w, h))
			var sel := i == selected
			var bg := UiTheme.WARN if sel and a.ok else (Color(0.2, 0.18, 0.15, 0.95) if a.ok else Color(0.12, 0.11, 0.1, 0.9))
			draw_style_box(UiTheme.box(bg, 8, UiTheme.WARN if sel else UiTheme.LINE, 2 if sel else 1), r)
			var col := UiTheme.INK if sel and a.ok else (UiTheme.PAPER if a.ok else Color(UiTheme.PAPER, 0.4))
			draw_string(f, Vector2(r.position.x, r.position.y + 23), a.label, HORIZONTAL_ALIGNMENT_CENTER, w, 16, col)
			if not a.ok:
				draw_string(UiTheme.body(), Vector2(r.position.x, r.position.y + 42), a.why, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(1, 0.55, 0.45, 0.8))
		draw_string(UiTheme.body(), centre + Vector2(-160, R + 70), "ชี้เมาส์แล้วปล่อย E", HORIZONTAL_ALIGNMENT_CENTER, 320, 13, Color(UiTheme.PAPER, 0.6))
