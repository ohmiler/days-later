class_name BagScreen
extends Control
## The bag screen (Tab): what you wear, what you carry, and what is within reach.
## Drag things between slots, right-click for a menu, shift-click to send
## something across, hover for details. Nothing moves here: every change is a
## request, and the server's answer comes back through inv_sync.
##
## Slots are named by refs, as on the server: ["inv", i], ["worn", slot],
## ["ground", pickup id] (-1 = drop here).

signal move_requested(from: Array, to: Array)
signal use_requested(ref: Array)
signal split_requested(ref: Array)
signal drop_requested(ref: Array)
signal box_closed

const SLOT := 52.0
const GAP := 6.0
const W := 740.0
const H := 430.0
const COLS := 4

var inv: Array = []
var worn := {}
var ground: Array = []  # [pickup id, item] within reach
var box_id := -1  # an open container shows in place of the ground
var box_items: Array = []
var box_title := ""
var hover: Array = []  # ref under the mouse
var drag: Array = []  # ref being dragged
var drag_from := Vector2.ZERO
var menu_ref: Array = []
var menu_pos := Vector2.ZERO
var menu_items: Array = []  # [label, action]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -W / 2
	offset_right = W / 2
	offset_top = -H / 2 - 40
	offset_bottom = H / 2 - 40
	mouse_filter = Control.MOUSE_FILTER_STOP


# --- Layout ------------------------------------------------------------------

func _slots() -> Array:
	var out := []  # [ref, rect, title]
	var step := minf(SLOT + GAP, (H - 118.0) / Items.SLOTS.size())  # all the layers fit above the info line
	for i in Items.SLOTS.size():
		out.append([["worn", Items.SLOTS[i]], Rect2(24, 64 + i * step, step - 4, step - 4)])
	var x0 := 200.0
	for i in inv.size():
		var row := i / COLS
		var col := i % COLS
		var y := 64.0 + row * (SLOT + GAP) + (14.0 if i >= Items.INV_SIZE else 0.0)
		out.append([["inv", i], Rect2(x0 + col * (SLOT + GAP), y, SLOT, SLOT)])
	var x1 := 480.0
	if box_id >= 0:
		for i in box_items.size():
			out.append([["box", box_id, i], Rect2(x1 + (i % 4) * (SLOT + GAP), 64 + (i / 4) * (SLOT + GAP), SLOT, SLOT)])
		return out
	for i in 12:
		var ref := ["ground", ground[i][0]] if i < ground.size() else ["ground", -1]
		out.append([ref, Rect2(x1 + (i % 4) * (SLOT + GAP), 64 + (i / 4) * (SLOT + GAP), SLOT, SLOT)])
	return out


## The far column: an open container, or the ground.
func _far(i := -1) -> Array:
	return ["box", box_id, i] if box_id >= 0 else ["ground", i]


func _far_items() -> Array:
	var out := []
	if box_id >= 0:
		for i in box_items.size():
			if box_items[i] != null:
				out.append(["box", box_id, i])
	else:
		for g in ground:
			out.append(["ground", g[0]])
	return out


func _item(ref: Array) -> Variant:
	match ref[0]:
		"inv":
			return inv[ref[1]] if ref[1] >= 0 and ref[1] < inv.size() else null
		"worn":
			return worn.get(ref[1])
		"ground":
			for g in ground:
				if g[0] == ref[1]:
					return g[1]
		"box":
			return box_items[ref[2]] if ref[2] >= 0 and ref[2] < box_items.size() else null
	return null


func _ref_at(p: Vector2) -> Array:
	for s in _slots():
		if (s[1] as Rect2).has_point(p):
			return s[0]
	if Rect2(470, 40, 260, 250).has_point(p):
		return _far()  # anywhere over the far column: into the container, or onto the ground
	return []


# --- Input ---------------------------------------------------------------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _ref_at(e.position)
		if h != hover:
			hover = h
		queue_redraw()
	elif e is InputEventMouseButton:
		accept_event()
		if not menu_items.is_empty():
			if e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_menu_click(e.position)
			elif e.pressed:
				menu_items = []
			queue_redraw()
			return
		var ref := _ref_at(e.position)
		var it = _item(ref) if not ref.is_empty() else null
		if e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			if it != null and e.shift_pressed:
				_send_across(ref)
			elif it != null:
				drag = ref
				drag_from = e.position
		elif e.button_index == MOUSE_BUTTON_LEFT and not e.pressed and not drag.is_empty():
			var to := ref
			if to.is_empty() and not Rect2(Vector2.ZERO, size).has_point(e.position):
				to = ["ground", -1]  # dragged right out of the bag: drop it
			if not to.is_empty() and to != drag and e.position.distance_to(drag_from) > 4.0:
				if not (drag[0] == "ground" and to[0] == "ground"):
					move_requested.emit(drag, to)
			drag = []
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and it != null:
			_open_menu(ref, it, e.position)
		queue_redraw()


## Shift-click: from the bag or body to the ground, from the ground into the bag.
func _send_across(ref: Array) -> void:
	if ref[0] in ["ground", "box"]:
		move_requested.emit(ref, ["inv", -1])
	elif box_id >= 0:
		move_requested.emit(ref, _far())
	else:
		drop_requested.emit(ref)


func _open_menu(ref: Array, it: Dictionary, at: Vector2) -> void:
	var d := Items.def(it.id)
	menu_items = []
	match ref[0]:
		"inv":
			match d.get("type"):
				"use":
					menu_items.append(["ใช้", "use"])
				"wear":
					menu_items.append(["สวม", "use"])
				"trap":
					menu_items.append(["วางกับดัก", "use"])
			if it.get("n", 1) > 1:
				menu_items.append(["แบ่งครึ่ง", "split"])
			menu_items.append(["ทิ้งลงพื้น", "drop"])
		"worn":
			menu_items.append(["ถอด", "use"])
			menu_items.append(["ทิ้งลงพื้น", "drop"])
		"ground", "box":
			menu_items.append(["เก็บ", "take"])
	if ref[0] in ["inv", "worn"] and box_id >= 0:
		menu_items.insert(menu_items.size() - 1, ["ใส่ใน" + box_title, "stash"])
	menu_ref = ref
	menu_pos = at


func _menu_rect(i: int) -> Rect2:
	return Rect2(menu_pos + Vector2(0, i * 26), Vector2(120, 26))


func _menu_click(p: Vector2) -> void:
	for i in menu_items.size():
		if _menu_rect(i).has_point(p):
			match menu_items[i][1]:
				"use":
					use_requested.emit(menu_ref)
				"split":
					split_requested.emit(menu_ref)
				"drop":
					drop_requested.emit(menu_ref)
				"take":
					move_requested.emit(menu_ref, ["inv", -1])
				"stash":
					move_requested.emit(menu_ref, _far())
	menu_items = []


func take_all() -> void:
	for ref in _far_items():
		move_requested.emit(ref, ["inv", -1])


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	draw_style_box(UiTheme.box(Color(0.06, 0.055, 0.045, 0.98), 10, UiTheme.LINE, 1), Rect2(Vector2.ZERO, size))
	var head := UiTheme.heading()
	var body := UiTheme.body()
	# Column titles.
	var armor := 0.0
	for k in worn:
		if worn[k] != null:
			armor += Items.def(worn[k].id).get("armor", 0.0)
	draw_string(head, Vector2(24, 40), "ที่สวมอยู่", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.PAPER)
	draw_string(body, Vector2(24, 56), "กันกัด %d%%" % roundi(minf(armor, Items.MAX_ARMOR) * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			UiTheme.WARN if armor > 0 else Color(UiTheme.PAPER, 0.5))
	var used := inv.filter(func(x): return x != null).size()
	draw_string(head, Vector2(200, 40), "กระเป๋า", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.PAPER)
	var kg := 0.0
	for it in inv + worn.values():
		kg += Items.weight_of(it)
	var limit := Items.CARRY + float(Items.def(worn.back.id if worn.get("back") != null else "").get("carry", 0.0))
	var load_line := "%d / %d ช่อง · หนัก %.1f / %.0f กก." % [used, inv.size(), kg, limit]
	if kg > limit:
		load_line += " · หนักเกิน เดินช้าลง"
	draw_string(body, Vector2(200, 56), load_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			UiTheme.WARN if kg > limit else Color(UiTheme.PAPER, 0.5))
	draw_string(head, Vector2(480, 40), box_title if box_id >= 0 else "พื้นใกล้ตัว", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.PAPER)
	draw_string(body, Vector2(480, 56), "ลากของมาเก็บไว้ในนี้ได้" if box_id >= 0 else "ลากของมาวางที่นี่เพื่อทิ้ง",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UiTheme.PAPER, 0.5))
	if inv.size() > Items.INV_SIZE:
		var y := 64.0 + 2 * (SLOT + GAP) + 2
		draw_string(body, Vector2(200, y + 9), "ในเป้", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UiTheme.PAPER, 0.45))
	# Slots.
	for s in _slots():
		var ref: Array = s[0]
		var r: Rect2 = s[1]
		var it = _item(ref)
		var lit: bool = ref == hover
		if ref[0] == "ground" and it == null and box_id < 0:
			draw_style_box(UiTheme.box(Color(0.91, 0.88, 0.81, 0.03), 6, Color(0.23, 0.2, 0.17, 0.6), 1), r)
			continue
		if it == null:
			draw_style_box(UiTheme.box(Color(0.11, 0.1, 0.08, 0.8), 6, UiTheme.WARN if lit and not drag.is_empty() else Color(0.23, 0.2, 0.17), 2), r)
		else:
			var card := UiTheme.box(Color("ad9870") if ref != drag else Color("6e5b3c"), 6, UiTheme.WARN if lit else Color("6e5b3c"), 2)
			draw_style_box(card, r)
			if ref != drag:
				_draw_item(r, it)
		if ref[0] == "worn":
			draw_string(body, r.position + Vector2(SLOT + 8, 32), Items.SLOT_NAMES[ref[1]] if it == null else Items.display_name(it.id),
					HORIZONTAL_ALIGNMENT_LEFT, 110, 13, Color(UiTheme.PAPER, 0.4 if it == null else 0.85))
		elif ref[0] == "inv" and ref[1] < Items.INV_SIZE:
			draw_string(head, r.position + Vector2(5, 14), str(ref[1] + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(UiTheme.INK, 0.55) if it != null else Color(UiTheme.PAPER, 0.3))
	# Take-all button under "nearby".
	if not _far_items().is_empty():
		var br := _take_all_rect()
		draw_style_box(UiTheme.box(UiTheme.WARN if hover == ["take_all"] else Color(0.91, 0.88, 0.81, 0.08), 6), br)
		draw_string(head, br.position + Vector2(0, 19), "เก็บทั้งหมด", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 14,
				UiTheme.INK if hover == ["take_all"] else UiTheme.PAPER)
	# What the mouse is over.
	var info := "ลากเพื่อย้าย · คลิกขวาเพื่อใช้ / ทิ้ง · Shift+คลิกส่งข้ามฝั่ง · [Tab] ปิด"
	var hit = _item(hover) if not hover.is_empty() and hover[0] != "take_all" else null
	if hit != null:
		var d := Items.def(hit.id)
		var line := Items.display_name(hit.id)
		match d.get("type"):
			"weapon":
				line += " · ฟาด %d · ทนทาน %d/%d" % [d.dmg, hit.hp, d.hp]
			"wear":
				line += " · " + Items.wear_text(hit.id) + " · ทนทาน %d/%d" % [hit.hp, d.hp]
			"use":
				line += " · " + Items.effect_text(hit.id)
		if Items.stack(hit.id) > 1:
			line += " · %d/%d" % [hit.n, Items.stack(hit.id)]
		line += " · %.1f กก." % Items.weight_of(hit)
		if Items.rarity_of(hit.id) != "common":
			line += " · " + Items.RARITY_NAMES[Items.rarity_of(hit.id)]
		info = line
	draw_line(Vector2(20, H - 44), Vector2(W - 20, H - 44), UiTheme.LINE, 1)
	draw_string(body, Vector2(24, H - 18), info, HORIZONTAL_ALIGNMENT_LEFT, W - 48, 14, Color(UiTheme.PAPER, 0.8))
	# Dragged item follows the mouse.
	if not drag.is_empty():
		var it = _item(drag)
		if it != null:
			var m := get_local_mouse_position()
			_draw_item(Rect2(m - Vector2(SLOT, SLOT) * 0.5, Vector2(SLOT, SLOT)), it)
	# Right-click menu.
	for i in menu_items.size():
		var r := _menu_rect(i)
		var over := r.has_point(get_local_mouse_position())
		draw_rect(r, Color("2a2622") if not over else Color("4a4238"))
		draw_string(body, r.position + Vector2(10, 18), menu_items[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.PAPER)
	if not menu_items.is_empty():
		draw_rect(Rect2(menu_pos, Vector2(120, 26 * menu_items.size())), UiTheme.LINE, false, 1)


func _take_all_rect() -> Rect2:
	return Rect2(480, 64 + 3 * (SLOT + GAP) + 4, 4 * SLOT + 3 * GAP, 28)


func _draw_item(r: Rect2, it: Dictionary) -> void:
	Items.draw_icon(self, r.grow(-10), it.id)
	var rarity := Items.rarity_of(it.id)
	if rarity != "common":  # a coloured corner marks the harder finds
		draw_colored_polygon(PackedVector2Array([r.position + Vector2(4, 4), r.position + Vector2(14, 4), r.position + Vector2(4, 14)]),
				Items.RARITY_COLORS[rarity])
	if it.get("n", 1) > 1:
		draw_string(UiTheme.heading(), r.end - Vector2(22, 5), "x%d" % it.n, HORIZONTAL_ALIGNMENT_RIGHT, 18, 12, UiTheme.INK)
	var d := Items.def(it.id)
	if d.get("type") in ["weapon", "wear"] and d.has("hp"):
		var frac: float = float(it.hp) / d.hp
		var bar := Rect2(r.position.x + 6, r.end.y - 7, r.size.x - 12, 3)
		draw_rect(bar, Color(0, 0, 0, 0.35))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color("4f9a3a") if frac > 0.3 else Color("c8502a"))


func _process(_delta: float) -> void:
	if not visible:
		return
	var m := get_local_mouse_position()
	if _take_all_rect().has_point(m) and not _far_items().is_empty():
		hover = ["take_all"]
	queue_redraw()


func _input(e: InputEvent) -> void:
	# The take-all button, handled here so it works whatever _gui_input decided.
	if visible and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT \
			and _take_all_rect().has_point(get_local_mouse_position()) and not _far_items().is_empty() and menu_items.is_empty():
		take_all()
		get_viewport().set_input_as_handled()
