class_name BagScreen
extends Control
## The bag screen (Tab): what you wear, what you carry, and what is within reach.
##
##   left    you, dressed as you are, with a slot for each place things are
##           worn around the body (an outline shows what goes there), and how
##           well each part of you is guarded against bites
##   middle  the bag, with a bar for how much you're carrying
##   right   tabs: the ground nearby, an open cupboard, or making things
##   bottom  a card for the item picked (or under the mouse), with buttons
##           for what can be done with it
##
## Drag between slots, shift-click to send across, right-click for the same
## actions as the buttons. Nothing moves here: every change is a request, and
## the server's answer comes back through inv_sync.
##
## Slots are named by refs, as on the server: ["inv", i], ["worn", slot],
## ["ground", pickup id] (-1 = drop here), ["box", container, i].

signal move_requested(from: Array, to: Array)
signal use_requested(ref: Array)
signal split_requested(ref: Array)
signal drop_requested(ref: Array)
signal craft_requested(id: String)
signal salvage_requested(idx: int)
signal repair_requested(ref: Array)
signal treat_requested(i: int)  # bandage wound i
signal box_closed

const SLOT := 52.0
const WSLOT := 50.0  # worn slots, round the doll
const GAP := 6.0
const W := 900.0
const H := 560.0
const COLS := 4
const X_BAG := 316.0
const X_FAR := 590.0
const CARD_Y := H - 100.0

## Where each worn slot sits round the doll: beside the part of the body it's for.
const WORN_AT := {
	head = Vector2(120, 44), face = Vector2(22, 62), neck = Vector2(218, 62),
	body = Vector2(22, 116), over = Vector2(218, 116), arms = Vector2(22, 170), hands = Vector2(218, 170),
	legs = Vector2(22, 224), knees = Vector2(218, 224), back = Vector2(22, 278), strap = Vector2(218, 278),
	feet = Vector2(120, 332),
	hand_r = Vector2(22, 332), hand_l = Vector2(218, 332),  # what you hold: right hand on the left, as the doll faces you
}
const DOLL_AT := Vector2(145, 310)  # the doll's feet
const DOLL_SCALE := 5.4

var inv: Array = []
var worn := {}
var ground: Array = []  # [pickup id, item] within reach
var box_id := -1  # a cupboard opened to take from or put in
var box_items: Array = []
var box_title := ""
var doll_look := {}  # how you look (set by main while this is open)
var me: Player  # you, for your wounds and how you are (set by main)
var hover: Array = []  # ref under the mouse
var drag: Array = []  # ref being dragged
var drag_from := Vector2.ZERO
var picked: Array = []  # ref clicked: its card stays while the mouse moves on
var menu_ref: Array = []
var menu_pos := Vector2.ZERO
var menu_items: Array = []  # [label, action]
var tab := "ground"  # the right-hand column: "ground", "box", "craft" or "body"
var crafting := false  # (tab == "craft", for anyone asking)
var doll_view := 0  # 0 front, 1 side, 2 back, 3 other side: click the doll to turn it
var _last_box := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -W / 2
	offset_right = W / 2
	offset_top = -H / 2 - 30
	offset_bottom = H / 2 - 30
	mouse_filter = Control.MOUSE_FILTER_STOP


# --- Layout ------------------------------------------------------------------

func _slots() -> Array:
	var out := []  # [ref, rect]
	for slot in Items.SLOTS + Items.HANDS:
		out.append([["worn", slot], Rect2(WORN_AT.get(slot, Vector2.ZERO), Vector2(WSLOT, WSLOT))])
	for i in inv.size():
		var row := i / COLS
		var y := 60.0 + row * (SLOT + GAP) + (12.0 if i >= Items.INV_SIZE else 0.0)
		out.append([["inv", i], Rect2(X_BAG + (i % COLS) * (SLOT + GAP), y, SLOT, SLOT)])
	match tab:
		"box":
			for i in box_items.size():
				out.append([["box", box_id, i], Rect2(X_FAR + (i % 5) * (SLOT + GAP), 60 + (i / 5) * (SLOT + GAP), SLOT, SLOT)])
		"ground":
			for i in 15:
				var ref := ["ground", ground[i][0]] if i < ground.size() else ["ground", -1]
				out.append([ref, Rect2(X_FAR + (i % 5) * (SLOT + GAP), 60 + (i / 5) * (SLOT + GAP), SLOT, SLOT)])
	return out


## The far column's target: the open cupboard, or the ground.
func _far(i := -1) -> Array:
	return ["box", box_id, i] if tab == "box" and box_id >= 0 else ["ground", i]


func _far_items() -> Array:
	var out := []
	match tab:
		"box":
			for i in box_items.size():
				if box_items[i] != null:
					out.append(["box", box_id, i])
		"ground":
			for g in ground:
				out.append(["ground", g[0]])
	return out


func _item(ref: Array) -> Variant:
	if ref.is_empty():
		return null
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
	if tab == "craft":
		for i in Crafting.RECIPES.size():
			if _recipe_rect(i).has_point(p):
				return ["recipe", Crafting.RECIPES.keys()[i]]
		return []
	if tab == "body":
		return []
	if Rect2(X_FAR - 10, 50, W - X_FAR, CARD_Y - 60).has_point(p):
		return _far()  # anywhere over the far column: into the cupboard, or onto the ground
	return []


func _tabs() -> Array:
	var out := [["ground", "พื้นใกล้ตัว"]]
	if box_id >= 0:
		out.append(["box", box_title])
	out.append(["craft", "ทำของ"])
	out.append(["body", "ร่างกาย"])
	return out


func _tab_rect(i: int) -> Rect2:
	return Rect2(X_FAR + i * 74, 18, 70, 28)


func _doll_rect() -> Rect2:
	return Rect2(78, 100, 134, 216)


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
			elif _doll_rect().has_point(e.position):
				doll_view = (doll_view + 1) % 4  # turn the doll round
		elif e.button_index == MOUSE_BUTTON_LEFT and not e.pressed and not drag.is_empty():
			var to := ref
			if to.is_empty() and not Rect2(Vector2.ZERO, size).has_point(e.position):
				to = ["ground", -1]  # dragged right out of the bag: drop it
			if e.position.distance_to(drag_from) <= 4.0:
				picked = drag  # a click, not a drag: show its card
			elif not to.is_empty() and to != drag and not (drag[0] == "ground" and to[0] == "ground"):
				move_requested.emit(drag, to)
			drag = []
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and it != null:
			menu_items = _actions(ref, it)
			menu_ref = ref
			menu_pos = e.position
		queue_redraw()


## Shift-click: from the bag or body to the other side, from the other side into the bag.
func _send_across(ref: Array) -> void:
	if ref[0] in ["ground", "box"]:
		move_requested.emit(ref, ["inv", -1])
	elif tab == "box" and box_id >= 0:
		move_requested.emit(ref, _far())
	else:
		drop_requested.emit(ref)


## What can be done with the item at `ref`: [label, action] (the card's buttons and the right-click menu).
func _actions(ref: Array, it: Dictionary) -> Array:
	var d := Items.def(it.id)
	var out := []
	match ref[0]:
		"inv":
			if d.get("type") == "weapon":
				out.append(["ถือสองมือ" if Items.two_handed(it.id) else "ถือขวา", "hold_r"])
				if not Items.two_handed(it.id):
					out.append(["ถือซ้าย", "hold_l"])
			match d.get("type"):
				"use":
					out.append(["ใช้", "use"])
				"wear":
					out.append(["สวม", "use"])
				"trap":
					out.append(["วางกับดัก", "use"])
			if not d.get("salvage", {}).is_empty():
				out.append(["แยก", "salvage"])
			if Crafting.repair_with(it) != "":
				out.append(["ซ่อม", "repair"])
			if it.get("n", 1) > 1:
				out.append(["แบ่งครึ่ง", "split"])
			if tab == "box" and box_id >= 0:
				out.append(["เก็บเข้าตู้", "stash"])
			out.append(["ทิ้ง", "drop"])
		"worn":
			out.append(["ปล่อย" if ref[1] in Items.HANDS else "ถอด", "use"])
			if Crafting.repair_with(it) != "":
				out.append(["ซ่อม", "repair"])
			out.append(["ทิ้ง", "drop"])
		"ground", "box":
			out.append(["เก็บ", "take"])
	return out


func _do(action: String, ref: Array) -> void:
	match action:
		"use":
			use_requested.emit(ref)
		"split":
			split_requested.emit(ref)
		"salvage":
			salvage_requested.emit(ref[1])
		"repair":
			repair_requested.emit(ref)
		"drop":
			drop_requested.emit(ref)
		"take":
			move_requested.emit(ref, ["inv", -1])
		"stash":
			move_requested.emit(ref, _far())
		"hold_r":
			move_requested.emit(ref, ["worn", "hand_r"])
		"hold_l":
			move_requested.emit(ref, ["worn", "hand_l"])


func _menu_rect(i: int) -> Rect2:
	return Rect2(menu_pos + Vector2(0, i * 26), Vector2(130, 26))


func _menu_click(p: Vector2) -> void:
	for i in menu_items.size():
		if _menu_rect(i).has_point(p):
			_do(menu_items[i][1], menu_ref)
	menu_items = []


func take_all() -> void:
	for ref in _far_items():
		move_requested.emit(ref, ["inv", -1])


func _process(_delta: float) -> void:
	if not visible:
		return
	# An opened cupboard shows itself; closing it goes back to the ground.
	if box_id != _last_box:
		if box_id >= 0:
			tab = "box"
		elif tab == "box":
			tab = "ground"
		_last_box = box_id
	crafting = tab == "craft"
	if not picked.is_empty() and _item(picked) == null:
		picked = []
	queue_redraw()


## Clicks on the tabs, the take-all button, recipes and the card's buttons.
func _input(e: InputEvent) -> void:
	if not (visible and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and menu_items.is_empty()):
		return
	var m := get_local_mouse_position()
	var tabs := _tabs()
	for i in tabs.size():
		if _tab_rect(i).has_point(m):
			tab = tabs[i][0]
			crafting = tab == "craft"
			get_viewport().set_input_as_handled()
			return
	if tab != "craft" and _take_all_rect().has_point(m) and not _far_items().is_empty():
		take_all()
		get_viewport().set_input_as_handled()
		return
	if tab == "craft":
		var h := _ref_at(m)
		if not h.is_empty() and h[0] == "recipe":
			if Crafting.can_make(inv, h[1]):
				craft_requested.emit(h[1])
			get_viewport().set_input_as_handled()
			return
	if tab == "body":
		for row in _body_rows():
			if row.button != "" and _body_button(row.i).has_point(m):
				if row.button == "treat":
					treat_requested.emit(row.wound)
				elif row.button == "cure":
					use_requested.emit(["inv", row.slot])
				get_viewport().set_input_as_handled()
				return
	var shown := _shown()
	var it = _item(shown)
	if it != null:
		var acts := _actions(shown, it)
		for i in acts.size():
			if _button_rect(i, acts.size()).has_point(m):
				_do(acts[i][1], shown)
				get_viewport().set_input_as_handled()
				return


## The item the card is about: the one under the mouse, else the one clicked.
func _shown() -> Array:
	if not hover.is_empty() and hover[0] not in ["recipe"] and _item(hover) != null:
		return hover
	return picked


# --- Drawing -------------------------------------------------------------------

const DIM := Color(0.91, 0.88, 0.81, 0.45)
const SLOT_BG := Color(0.11, 0.1, 0.08, 0.8)
const SLOT_EDGE := Color(0.23, 0.2, 0.17)
const CARD_BG := Color("ad9870")


func _draw() -> void:
	draw_style_box(UiTheme.box(Color(0.06, 0.055, 0.045, 0.98), 10, UiTheme.LINE, 1), Rect2(Vector2.ZERO, size))
	var head := UiTheme.heading()
	var body := UiTheme.body()
	_draw_worn_side(head, body)
	_draw_bag_side(head, body)
	_draw_far_side(head, body)
	# Slots.
	for s in _slots():
		var ref: Array = s[0]
		var r: Rect2 = s[1]
		var it = _item(ref)
		var lit: bool = ref == hover or ref == picked
		if it == null:
			draw_style_box(UiTheme.box(SLOT_BG if ref[0] != "ground" else Color(0.91, 0.88, 0.81, 0.03), 6,
					UiTheme.WARN if lit and not drag.is_empty() else SLOT_EDGE, 2 if ref[0] != "ground" else 1), r)
			if ref == ["worn", "hand_l"] and worn.get("hand_r") != null and Items.two_handed(worn.hand_r.id):
				# The left hand is on the other end of a two-handed weapon.
				Items.draw_icon(self, r.grow(-r.size.x * 0.19), worn.hand_r.id)
				draw_rect(r.grow(-2), Color(0.06, 0.055, 0.045, 0.55))
				_label(r, "สองมือ", Color(UiTheme.PAPER, 0.6), false)
			elif ref[0] == "worn":
				_slot_outline(r, ref[1])
				_label(r, Items.SLOT_NAMES.get(ref[1], Items.HAND_NAMES.get(ref[1], "")), Color(UiTheme.PAPER, 0.4), false)
		else:
			draw_style_box(UiTheme.box(CARD_BG if ref != drag else Color("6e5b3c"), 6, UiTheme.WARN if lit else Color("6e5b3c"), 2), r)
			if ref != drag:
				_draw_item(r, it)  # (just the icon: its name is on the card below)
		if ref[0] == "inv" and ref[1] < Items.INV_SIZE:
			draw_string(head, r.position + Vector2(5, 14), str(ref[1] + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(UiTheme.INK, 0.55) if it != null else Color(UiTheme.PAPER, 0.3))
	_draw_card(head, body)
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
		draw_rect(Rect2(menu_pos, Vector2(130, 26 * menu_items.size())), UiTheme.LINE, false, 1)


## You, dressed, turned by clicking; the slots round you; what guards each part.
func _draw_worn_side(head: Font, body: Font) -> void:
	draw_string(head, Vector2(24, 36), "ที่สวมอยู่", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.PAPER)
	draw_string(body, Vector2(120, 36), "คลิกตัวละครเพื่อหมุน", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UiTheme.PAPER, 0.35))
	draw_style_box(UiTheme.box(Color(0.91, 0.88, 0.81, 0.03), 60), _doll_rect())
	if not doll_look.is_empty():
		var views := [[Look.FRONT, false], [Look.SIDE, false], [Look.BACK, false], [Look.SIDE, true]]
		var angles := [PI / 2, 0.0, -PI / 2, PI]
		Look.body_xf = Transform2D(0.0, Vector2(DOLL_SCALE, DOLL_SCALE), 0.0, DOLL_AT)
		var held := {}
		for h in Items.HANDS:
			if worn.get(h) != null:
				held[h] = Items.def(worn[h].id).get("draw", {})
		Look.draw(self, {view = views[doll_view], angle = angles[doll_view], weapon = held.get("hand_r", {}),
				weapon_l = held.get("hand_l", {})}, doll_look)
		Look.body_xf = Transform2D.IDENTITY
		draw_set_transform(Vector2.ZERO)
		# Wounds where they are: red still open, pale once bandaged.
		if me:
			for w in me.wounds:
				var at: Vector2 = DOLL_AT + Body.marker(w, views[doll_view][0]) * DOLL_SCALE
				var col: Color = Color("e8e2d4") if w.bandaged else (Body.LEVEL_COLORS[1] if w.kind in ["sprain", "bruise"] else Body.LEVEL_COLORS[2])
				draw_circle(at, 7, Color(0, 0, 0, 0.5))
				draw_circle(at, 5, col)
	# How well each part is guarded, as a strip of coloured pips with the numbers.
	var ids := []
	for k in worn:
		if worn[k] != null:
			ids.append(worn[k].id)
	var y := 404.0
	draw_string(head, Vector2(24, y), "กันกัด", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.PAPER)
	var x := 70.0
	for part in Items.PARTS:
		var g := Items.guard_at(ids, part)
		var col := Color("5a3a30").lerp(Color("4f9a3a"), clampf(g / 0.7, 0.0, 1.0))
		var r := Rect2(x, y - 12, 30, 16)
		draw_style_box(UiTheme.box(col, 4), r)
		draw_string(body, r.position + Vector2(0, 12), "%d" % roundi(g * 100), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, UiTheme.PAPER)
		draw_string(body, r.position + Vector2(0, 28), Items.PART_NAMES[part], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Color(UiTheme.PAPER, 0.5))
		x += 31.0
	# How hot it all is.
	var heat := 0.0
	for id in ids:
		heat += float(Items.def(id).get("hot", 0.0))
	if heat > 0.0:
		draw_string(body, Vector2(24, y + 36), "ร้อน", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e8904a"))
		_bar(Rect2(70, y + 29, 216, 5), clampf(heat / 1.2, 0.0, 1.0), Color("e8904a"))


## The bag: slots, and a bar for the weight.
func _draw_bag_side(head: Font, body: Font) -> void:
	var used := inv.filter(func(x): return x != null).size()
	draw_string(head, Vector2(X_BAG, 36), "กระเป๋า", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.PAPER)
	draw_string(body, Vector2(X_BAG + 72, 36), "%d / %d ช่อง" % [used, inv.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	if inv.size() > Items.INV_SIZE:
		draw_string(body, Vector2(X_BAG, 60 + 2 * (SLOT + GAP) + 9), "จากเป้และกระเป๋า", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UiTheme.PAPER, 0.4))
	var kg := 0.0
	for it in inv + worn.values():
		kg += Items.weight_of(it)
	var limit := Items.CARRY
	for k in worn:
		if worn[k] != null:
			limit += float(Items.def(worn[k].id).get("carry", 0.0))
	var rows := ceili(inv.size() / float(COLS))
	var y := 60.0 + rows * (SLOT + GAP) + (12.0 if inv.size() > Items.INV_SIZE else 0.0) + 14.0
	var k2 := kg / maxf(limit, 0.1)
	var col := Color("4f9a3a") if k2 < 0.8 else (UiTheme.WARN if k2 <= 1.0 else Color("c8502a"))
	draw_string(body, Vector2(X_BAG, y), "น้ำหนัก %.1f / %.0f กก." % [kg, limit], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			col if k2 > 1.0 else DIM)
	_bar(Rect2(X_BAG, y + 6, COLS * (SLOT + GAP) - GAP, 8), clampf(k2, 0.0, 1.0), col)
	if k2 > 1.0:
		draw_string(body, Vector2(X_BAG, y + 30), "หนักเกิน · เดินช้าลง เหนื่อยเร็ว", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


## The right-hand column: tabs, then the ground, a cupboard or the recipes.
func _draw_far_side(head: Font, body: Font) -> void:
	var tabs := _tabs()
	for i in tabs.size():
		var r := _tab_rect(i)
		var on: bool = tab == tabs[i][0]
		var lit := r.has_point(get_local_mouse_position())
		draw_style_box(UiTheme.box(UiTheme.WARN if on else Color(0.91, 0.88, 0.81, 0.12 if lit else 0.05), 6), r)
		_tab_icon(Vector2(r.position.x + 14, r.position.y + 14), tabs[i][0], UiTheme.INK if on else UiTheme.PAPER)
		draw_string(head, r.position + Vector2(24, 19), _fit(tabs[i][1], head, 12, r.size.x - 28), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				UiTheme.INK if on else UiTheme.PAPER)
		if tabs[i][0] == "body" and me and not Body.statuses(me).filter(func(s): return s.level == 2).is_empty():
			draw_circle(r.position + Vector2(r.size.x - 6, 6), 4, Body.LEVEL_COLORS[2])  # something needs seeing to
	var hint := {ground = "ลากของมาวางที่นี่เพื่อทิ้ง", box = "ลากของมาเก็บไว้ในนี้ได้", craft = "ใช้ของในกระเป๋า · ต้องยืนนิ่ง"}
	if tab == "body":
		_draw_body(head, body)
		return
	if tab == "craft":
		_draw_recipes(head, body)
		return
	draw_string(body, Vector2(X_FAR, 58 + 3 * (SLOT + GAP) + 12), hint[tab], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UiTheme.PAPER, 0.4))
	if not _far_items().is_empty():
		var br := _take_all_rect()
		var lit := br.has_point(get_local_mouse_position())
		draw_style_box(UiTheme.box(UiTheme.WARN if lit else Color(0.91, 0.88, 0.81, 0.08), 6), br)
		draw_string(head, br.position + Vector2(0, 19), "เก็บทั้งหมด", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 14,
				UiTheme.INK if lit else UiTheme.PAPER)


func _take_all_rect() -> Rect2:
	return Rect2(X_FAR, 60 + 3 * (SLOT + GAP) + 22, 5 * SLOT + 4 * GAP, 28)


## The card for the item picked or under the mouse: what it is, its numbers, and buttons.
func _draw_card(head: Font, body: Font) -> void:
	draw_line(Vector2(20, CARD_Y - 10), Vector2(W - 20, CARD_Y - 10), UiTheme.LINE, 1)
	var shown := _shown()
	var it = _item(shown)
	if not hover.is_empty() and hover[0] == "recipe":
		var rc: Dictionary = Crafting.RECIPES[hover[1]]
		Items.draw_icon(self, Rect2(24, CARD_Y + 4, 56, 56), rc.makes)
		draw_string(head, Vector2(92, CARD_Y + 24), rc.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.PAPER)
		draw_string(body, Vector2(92, CARD_Y + 46), "ต้องใช้: " + _recipe_line(hover[1]), HORIZONTAL_ALIGNMENT_LEFT, W - 120, 12, DIM)
		return
	if it == null:
		draw_string(body, Vector2(24, CARD_Y + 30), "คลิกของเพื่อดูรายละเอียด · ลากเพื่อย้าย · Shift+คลิกส่งข้ามฝั่ง · คลิกขวาเปิดเมนู · [Tab] ปิด",
				HORIZONTAL_ALIGNMENT_LEFT, W - 48, 13, Color(UiTheme.PAPER, 0.55))
		return
	var d := Items.def(it.id)
	var ir := Rect2(24, CARD_Y + 2, 64, 64)
	draw_style_box(UiTheme.box(CARD_BG, 8, Color("6e5b3c"), 2), ir)
	_draw_item(ir, it)
	var rarity := Items.rarity_of(it.id)
	draw_string(head, Vector2(102, CARD_Y + 22), Items.display_name(it.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.PAPER)
	if rarity != "common":
		var nw := head.get_string_size(Items.display_name(it.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(body, Vector2(110 + nw, CARD_Y + 21), Items.RARITY_NAMES[rarity], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Items.RARITY_COLORS[rarity])
	# The numbers, each with a small mark for what it is.
	var stats := []  # [mark, text]
	match d.get("type"):
		"weapon":
			if shown == ["worn", "hand_l"]:
				stats.append(["hit", "ฟาด %d (มือซ้าย %d%%)" % [roundi(d.dmg * Items.OFF_HAND), roundi(Items.OFF_HAND * 100)]])
			else:
				stats.append(["hit", "ฟาด %d" % d.dmg])
			stats.append(["hit", "สองมือ" if Items.two_handed(it.id) else "มือเดียว · ถือคู่ได้"])
		"wear":
			var g: Dictionary = d.get("guard", {})
			for part in g:
				stats.append(["guard", "%s %d%%" % [Items.PART_NAMES[part], roundi(g[part] * 100)]])
			if d.get("bag", 0) > 0:
				stats.append(["bag", "+%d ช่อง" % d.bag])
			if d.get("hot", 0.0) >= 0.15:
				stats.append(["hot", "ร้อน"])
			if d.get("muffle", false):
				stats.append(["ear", "ได้ยินไม่ชัด"])
		"use":
			stats.append(["use", Items.effect_text(it.id)])
	if d.has("hp") and d.get("type") in ["weapon", "wear"]:
		stats.append(["hp", "ทนทาน %d/%d" % [it.hp, d.hp]])
	stats.append(["kg", "%.1f กก." % Items.weight_of(it)])
	if Items.stack(it.id) > 1:
		stats.append(["n", "%d/%d" % [it.get("n", 1), Items.stack(it.id)]])
	var x := 102.0
	var sy := CARD_Y + 48
	for s in stats:
		_mark(Vector2(x + 5, sy - 4), s[0])
		draw_string(body, Vector2(x + 14, sy), s[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		x += 22.0 + body.get_string_size(s[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		if x > W - 330:
			break
	# Buttons.
	var acts := _actions(shown, it)
	for i in acts.size():
		var br := _button_rect(i, acts.size())
		var lit := br.has_point(get_local_mouse_position())
		var danger: bool = acts[i][1] == "drop"
		draw_style_box(UiTheme.box(UiTheme.WARN if lit else Color(0.91, 0.88, 0.81, 0.08), 6,
				Color("8a3a2a") if danger else Color(0, 0, 0, 0), 1 if danger else 0), br)
		draw_string(head, br.position + Vector2(0, 21), acts[i][0], HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 13,
				UiTheme.INK if lit else UiTheme.PAPER)


func _button_rect(i: int, n: int) -> Rect2:
	var w := 70.0
	return Rect2(W - 24 - (n - i) * (w + 6) + 6, CARD_Y + 18, w, 32)


# --- Little drawings -------------------------------------------------------------

## A slot's name band: what's in it (or what goes in it), cut short to fit.
func _label(r: Rect2, text: String, col: Color, filled: bool) -> void:
	var f := UiTheme.body()
	var size := 9
	var band := Rect2(r.position.x + 2, r.end.y - 13, r.size.x - 4, 11)
	if filled:
		draw_rect(band, Color(0.1, 0.09, 0.07, 0.72))
	draw_string(f, Vector2(band.position.x, band.end.y - 2), _fit(text, f, size, band.size.x - 2), HORIZONTAL_ALIGNMENT_CENTER,
			band.size.x, size, col)


## `text`, shortened with "…" until it fits in `width`.
func _fit(text: String, f: Font, size: int, width: float) -> String:
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return text
	var t := text
	while t.length() > 1 and f.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		t = t.left(t.length() - 1)
	return t + "…"


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), col)


## A faint outline in an empty worn slot of what goes there.
func _slot_outline(r: Rect2, slot: String) -> void:
	var c := r.get_center() - Vector2(0, 5)  # (room below for the name)
	var col := Color(UiTheme.PAPER, 0.22)
	var w := 1.3
	match slot:
		"head":  # a cap
			draw_arc(c + Vector2(0, 3), 10, PI, TAU, 12, col, w)
			draw_line(c + Vector2(-10, 3), c + Vector2(14, 3), col, w)
		"face":  # a mask
			draw_rect(Rect2(c + Vector2(-9, -5), Vector2(18, 11)), col, false, w)
			draw_line(c + Vector2(-9, -3), c + Vector2(-13, -7), col, w)
			draw_line(c + Vector2(9, -3), c + Vector2(13, -7), col, w)
		"neck":  # a scarf
			draw_rect(Rect2(c + Vector2(-11, -5), Vector2(22, 7)), col, false, w)
			draw_line(c + Vector2(4, 2), c + Vector2(6, 12), col, w)
		"body":  # a T-shirt
			draw_polyline(PackedVector2Array([c + Vector2(-5, -11), c + Vector2(-13, -6), c + Vector2(-10, -1), c + Vector2(-7, -3),
					c + Vector2(-7, 11), c + Vector2(7, 11), c + Vector2(7, -3), c + Vector2(10, -1), c + Vector2(13, -6), c + Vector2(5, -11)]), col, w)
		"over":  # a vest
			draw_polyline(PackedVector2Array([c + Vector2(-4, -11), c + Vector2(-9, -11), c + Vector2(-9, 11), c + Vector2(9, 11),
					c + Vector2(9, -11), c + Vector2(4, -11), c + Vector2(0, -5), c + Vector2(-4, -11)]), col, w)
		"arms":  # a forearm with a guard
			draw_line(c + Vector2(-12, 8), c + Vector2(12, -8), col, 5.0)
			draw_line(c + Vector2(-4, 3), c + Vector2(4, -3), SLOT_BG, 2.0)
		"hands":  # a glove
			draw_rect(Rect2(c + Vector2(-7, -4), Vector2(14, 13)), col, false, w)
			for i in 4:
				draw_line(c + Vector2(-6 + i * 4, -4), c + Vector2(-6 + i * 4, -11), col, w)
		"legs":  # trousers
			draw_polyline(PackedVector2Array([c + Vector2(-8, 12), c + Vector2(-9, -11), c + Vector2(9, -11), c + Vector2(8, 12),
					c + Vector2(3, 12), c + Vector2(0, -2), c + Vector2(-3, 12), c + Vector2(-8, 12)]), col, w)
		"knees":  # a pad
			draw_rect(Rect2(c + Vector2(-6, -10), Vector2(12, 20)), col, false, w)
			draw_line(c + Vector2(-6, -2), c + Vector2(6, -2), col, w)
		"feet":  # a shoe
			draw_polyline(PackedVector2Array([c + Vector2(-10, -6), c + Vector2(-3, -6), c + Vector2(-2, 1), c + Vector2(11, 3),
					c + Vector2(11, 7), c + Vector2(-10, 7), c + Vector2(-10, -6)]), col, w)
		"back":  # a backpack
			draw_rect(Rect2(c + Vector2(-9, -9), Vector2(18, 20)), col, false, w)
			draw_arc(c + Vector2(0, -9), 4, PI, TAU, 8, col, w)
			draw_rect(Rect2(c + Vector2(-5, 3), Vector2(10, 5)), col, false, w)
		"hand_r", "hand_l":  # a hand, open
			draw_rect(Rect2(c + Vector2(-6, -2), Vector2(12, 10)), col, false, w)
			for i in 4:
				draw_line(c + Vector2(-5 + i * 3.3, -2), c + Vector2(-5 + i * 3.3, -9), col, w)
			draw_line(c + Vector2(6 if slot == "hand_l" else -6, 2), c + Vector2(10 if slot == "hand_l" else -10, -2), col, w)
		"strap":  # a shoulder bag
			draw_line(c + Vector2(-11, -12), c + Vector2(4, 0), col, w)
			draw_rect(Rect2(c + Vector2(-2, -1), Vector2(14, 11)), col, false, w)


## A small mark before a number on the card.
func _mark(c: Vector2, kind: String) -> void:
	var col := Color(UiTheme.PAPER, 0.6)
	match kind:
		"guard":  # a shield
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -4), c + Vector2(4, -4), c + Vector2(4, 1), c + Vector2(0, 5), c + Vector2(-4, 1)]), col)
		"hit":  # a blade
			draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), col, 2.0)
			draw_line(c + Vector2(-4, 1), c + Vector2(-1, 4), col, 1.5)
		"hp":  # a little wear bar
			draw_rect(Rect2(c + Vector2(-5, -1.5), Vector2(10, 3)), Color(0, 0, 0, 0.4))
			draw_rect(Rect2(c + Vector2(-5, -1.5), Vector2(7, 3)), Color("4f9a3a"))
		"kg":  # a weight
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3, -2), c + Vector2(3, -2), c + Vector2(5, 4), c + Vector2(-5, 4)]), col)
			draw_arc(c + Vector2(0, -3), 2, PI, TAU, 6, col, 1.0)
		"hot":
			draw_circle(c, 3.5, Color("e8904a"))
		"bag":
			draw_rect(Rect2(c + Vector2(-4, -3), Vector2(8, 7)), col)
		"ear":
			draw_arc(c, 3.5, -PI * 0.5, PI * 0.9, 8, col, 1.5)
		_:
			draw_circle(c, 2.5, col)


## The icon on each tab.
func _tab_icon(c: Vector2, kind: String, col: Color) -> void:
	match kind:
		"body":  # a cross
			draw_rect(Rect2(c + Vector2(-1.5, -5), Vector2(3, 10)), col)
			draw_rect(Rect2(c + Vector2(-5, -1.5), Vector2(10, 3)), col)
		"ground":  # a pin on the ground
			draw_circle(c + Vector2(0, -2), 4, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 0), c + Vector2(3, 0), c + Vector2(0, 6)]), col)
		"box":  # a cupboard
			draw_rect(Rect2(c + Vector2(-5, -6), Vector2(10, 12)), col, false, 1.5)
			draw_line(c + Vector2(0, -6), c + Vector2(0, 6), col, 1.0)
		"craft":  # a hammer
			draw_line(c + Vector2(-4, 5), c + Vector2(2, -1), col, 2.0)
			draw_rect(Rect2(c + Vector2(-1, -6), Vector2(8, 4)), col)


## What a recipe uses, with how many of each you have: "เศษผ้า 1/2 · ...".
func _recipe_line(id: String) -> String:
	var r: Dictionary = Crafting.RECIPES[id]
	var parts := []
	for need in r.needs:
		var nm: String = ("อะไรก็ได้ที่เป็น" + need.substr(1)) if need.begins_with("#") else Items.display_name(need)
		parts.append("%s %d/%d" % [nm, Crafting.count_in(inv, need), r.needs[need]])
	return " · ".join(parts)


# --- The body tab --------------------------------------------------------------------

## A row for each wound, and one for an infection: {i, wound, icon, level, title, sub, button, slot}.
func _body_rows() -> Array:
	var out := []
	if me == null:
		return out
	var has_bandage := inv.any(func(x): return x != null and x.id in ["bandage", "firstaid"])
	for k in me.wounds.size():
		var w: Dictionary = me.wounds[k]
		var sub := ""
		var button := ""
		var level := 1
		match w.kind:
			"bite", "scratch":
				if w.bandaged:
					sub = "พันแผลแล้ว · " + Body.heal_text(w)
					level = 0
				else:
					sub = ("เลือดออก · " if w.bleeding else "") + ("ยังไม่พันแผล · ไม่หายเองถ้าไม่พัน · เสี่ยงติดเชื้อ" if w.kind == "bite" 							else "ยังไม่พันแผล · " + Body.heal_text(w) + " (พันแล้วเร็วขึ้น)")
					level = 2 if w.kind == "bite" or w.bleeding else 1
					button = "treat" if has_bandage else ""
			"sprain":
				sub = "วิ่งไม่ได้ เดินช้าลง · " + Body.heal_text(w) + " · นอนจะเร็วขึ้น"
			"bruise":
				sub = "ของที่ใส่กันไว้ได้ · " + Body.heal_text(w)
				level = 0
		out.append({i = out.size(), wound = k, icon = "bandaged" if w.bandaged else w.kind, level = level, title = Body.title(w),
				sub = sub, button = button, slot = -1, healing = Body.progress(w)})
	if me.infection > 0.0:
		var stage := Body.infection_stage(me.infection)
		var slot := -1
		for k in inv.size():
			if inv[k] != null and inv[k].id == "antibiotic":
				slot = k
		out.append({i = out.size(), wound = -1, icon = "fever", level = 2 if stage >= 2 else 1,
				title = "ติดเชื้อ · ระยะ %d จาก 4: %s" % [stage + 1, Body.STAGES[stage][1]],
				sub = Body.STAGES[stage][2] + (" · มียาปฏิชีวนะในกระเป๋า" if slot >= 0 else " · ต้องใช้ยาปฏิชีวนะ หาได้ที่ร้านขายยา"),
				button = "cure" if slot >= 0 else "", slot = slot, infection = me.infection})
	return out


func _body_row_rect(i: int) -> Rect2:
	return Rect2(X_FAR, 58 + i * 48, W - X_FAR - 24, 44)


func _body_button(i: int) -> Rect2:
	var r := _body_row_rect(i)
	return Rect2(r.end.x - 74, r.position.y + 8, 66, 28)


func _draw_body(head: Font, body: Font) -> void:
	var rows := _body_rows()
	if rows.is_empty():
		draw_string(body, Vector2(X_FAR, 80), "ร่างกายปกติดี ไม่มีบาดแผล", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
		return
	for row in rows:
		var r := _body_row_rect(row.i)
		if r.end.y > CARD_Y - 14:
			break
		var col: Color = Body.LEVEL_COLORS[row.level]
		draw_style_box(UiTheme.box(Color(0.91, 0.88, 0.81, 0.05), 6, Color(col, 0.6) if row.level > 0 else SLOT_EDGE, 1), r)
		Body.draw_icon(self, r.position + Vector2(20, 22), row.icon, col, 1.1)
		var tw := r.size.x - 44 - (80 if row.button != "" else 0)
		draw_string(head, r.position + Vector2(40, 19), _fit(row.title, head, 13, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.PAPER)
		draw_string(body, r.position + Vector2(40, 36), _fit(row.sub, body, 11, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
		if row.has("infection"):
			_bar(Rect2(r.position.x + 40, r.end.y - 4, tw, 3), row.infection / 100.0, col)
		elif row.has("healing") and row.healing[1] >= 0.0:
			_bar(Rect2(r.position.x + 40, r.end.y - 4, tw, 3), row.healing[0], Color("6ab04a"))  # how far it's healed
		if row.button != "":
			var br := _body_button(row.i)
			var lit := br.has_point(get_local_mouse_position())
			draw_style_box(UiTheme.box(UiTheme.WARN if lit else Color(0.91, 0.88, 0.81, 0.1), 6), br)
			draw_string(head, br.position + Vector2(0, 19), "พันแผล" if row.button == "treat" else "ใช้ยา", HORIZONTAL_ALIGNMENT_CENTER,
					br.size.x, 12, UiTheme.INK if lit else UiTheme.PAPER)


func _recipe_rect(i: int) -> Rect2:
	return Rect2(X_FAR, 58 + i * 36, W - X_FAR - 24, 32)


func _draw_recipes(head: Font, body: Font) -> void:
	var ids := Crafting.RECIPES.keys()
	for i in ids.size():
		var r: Dictionary = Crafting.RECIPES[ids[i]]
		var rr := _recipe_rect(i)
		if rr.end.y > CARD_Y - 14:
			break
		var ok := Crafting.can_make(inv, ids[i])
		var lit: bool = hover == ["recipe", ids[i]]
		draw_style_box(UiTheme.box(Color(0.91, 0.88, 0.81, 0.12 if lit else 0.04), 6, UiTheme.WARN if lit and ok else SLOT_EDGE, 1), rr)
		Items.draw_icon(self, Rect2(rr.position + Vector2(4, 4), Vector2(24, 24)), r.makes)
		draw_string(head, rr.position + Vector2(34, 14), r.name, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 38, 13,
				UiTheme.PAPER if ok else Color(UiTheme.PAPER, 0.4))
		draw_string(body, rr.position + Vector2(34, 27), _recipe_line(ids[i]), HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 38, 10,
				Color("8fc870") if ok else Color(UiTheme.PAPER, 0.35))


## An item in a slot. `named`: room is left at the bottom for its name band.
func _draw_item(r: Rect2, it: Dictionary, named := false) -> void:
	if named:
		Items.draw_icon(self, Rect2(r.position + Vector2(r.size.x * 0.22, r.size.y * 0.1), Vector2(r.size.x * 0.56, r.size.x * 0.56)), it.id)
	else:
		Items.draw_icon(self, r.grow(-r.size.x * 0.19), it.id)
	var rarity := Items.rarity_of(it.id)
	if rarity != "common":  # a coloured corner marks the harder finds
		draw_colored_polygon(PackedVector2Array([r.position + Vector2(4, 4), r.position + Vector2(14, 4), r.position + Vector2(4, 14)]),
				Items.RARITY_COLORS[rarity])
	if it.get("n", 1) > 1:
		draw_string(UiTheme.heading(), r.end - Vector2(22, 5), "x%d" % it.n, HORIZONTAL_ALIGNMENT_RIGHT, 18, 12, UiTheme.INK)
	var d := Items.def(it.id)
	if d.get("type") in ["weapon", "wear"] and d.has("hp"):
		var frac: float = float(it.hp) / d.hp
		var bar := Rect2(r.position.x + 5, r.end.y - (16.0 if named else 7.0), r.size.x - 10, 2.5 if named else 3.0)
		draw_rect(bar, Color(0, 0, 0, 0.35))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color("4f9a3a") if frac > 0.3 else Color("c8502a"))
