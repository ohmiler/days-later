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

# One grid for the whole screen: every slot SLOT square with GAP between,
# PAD round the edge, COL_GAP between the three columns, and every column's
# slots starting on the same line (TOP), row for row.
const SLOT := 52.0
const WSLOT := SLOT  # worn slots, round the doll
const GAP := 8.0
const PAD := 24.0
const COL_GAP := 32.0
const TOP := 64.0  # where the slots start, under the headings
const ROW := SLOT + GAP
const COLS := 4
const FAR_COLS := 5
const DOLL_W := 140.0  # the doll's column, between the two columns of worn slots
const X_BAG := PAD + SLOT * 2 + GAP * 2 + DOLL_W + COL_GAP
const X_FAR := X_BAG + COLS * ROW - GAP + COL_GAP
const W := X_FAR + FAR_COLS * ROW - GAP + PAD
const CARD_H := 64.0  # the item card along the bottom
const H := TOP + 6 * ROW - GAP + 24 + 44 + 24 + 24 + CARD_H + PAD  # (the worn column, the guard strip, a line, the card)
const CARD_Y := H - PAD - CARD_H

## Where each worn slot sits round the doll: beside the part of the body it's
## for, on the rows of the grid (column 0 and 2, the doll between).
const _L := PAD
const _R := PAD + SLOT + GAP + DOLL_W + GAP
const _MID := PAD + SLOT + GAP + DOLL_W / 2
const WORN_AT := {
	head = Vector2(_MID - SLOT / 2, TOP), face = Vector2(_L, TOP), neck = Vector2(_R, TOP),
	body = Vector2(_L, TOP + ROW), over = Vector2(_R, TOP + ROW), arms = Vector2(_L, TOP + ROW * 2), hands = Vector2(_R, TOP + ROW * 2),
	legs = Vector2(_L, TOP + ROW * 3), knees = Vector2(_R, TOP + ROW * 3), back = Vector2(_L, TOP + ROW * 4), strap = Vector2(_R, TOP + ROW * 4),
	feet = Vector2(_MID - SLOT - GAP / 2, TOP + ROW * 5), waist = Vector2(_MID + GAP / 2, TOP + ROW * 5),
	hand_r = Vector2(_L, TOP + ROW * 5), hand_l = Vector2(_R, TOP + ROW * 5),  # what you hold: right hand on the left, as the doll faces you
}
const DOLL_AT := Vector2(_MID, TOP + ROW * 5 - GAP - 12)  # the doll's feet
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
var tab := "ground"  # the right-hand column: "ground", "box", "craft", "body" or "skills"
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
	visibility_changed.connect(_on_shown)


var _pop: Tween


## Opening, it grows into place and fades in (a tenth of a second); closing is at once.
func _on_shown() -> void:
	if not visible or not is_inside_tree():
		return
	if _pop:
		_pop.kill()
	pivot_offset = size * 0.5
	modulate.a = 0.0
	scale = Vector2.ONE * 0.97
	_pop = create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_pop.tween_property(self, "modulate:a", 1.0, 0.12)
	_pop.tween_property(self, "scale", Vector2.ONE, 0.12)


# --- Layout ------------------------------------------------------------------

func _slots() -> Array:
	var out := []  # [ref, rect]
	for slot in Items.SLOTS + Items.HANDS:
		out.append([["worn", slot], Rect2(WORN_AT.get(slot, Vector2.ZERO), Vector2(WSLOT, WSLOT))])
	for i in inv.size():
		var row := i / COLS
		var y := TOP + row * ROW + (16.0 if i >= Items.INV_SIZE else 0.0)
		out.append([["inv", i], Rect2(X_BAG + (i % COLS) * (SLOT + GAP), y, SLOT, SLOT)])
	match tab:
		"box":
			for i in box_items.size():
				out.append([["box", box_id, i], Rect2(X_FAR + (i % FAR_COLS) * ROW, TOP + (i / FAR_COLS) * ROW, SLOT, SLOT)])
		"ground":
			for i in 15:
				var ref := ["ground", ground[i][0]] if i < ground.size() else ["ground", -1]
				out.append([ref, Rect2(X_FAR + (i % FAR_COLS) * ROW, TOP + (i / FAR_COLS) * ROW, SLOT, SLOT)])
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
	if tab in ["body", "skills"]:
		return []
	if Rect2(X_FAR - 10, 50, W - X_FAR, CARD_Y - 60).has_point(p):
		return _far()  # anywhere over the far column: into the cupboard, or onto the ground
	return []


func _tabs() -> Array:
	var out := [["ground", "พื้น"]]
	if box_id >= 0:
		out.append(["box", box_title])
	out.append(["craft", "ทำของ"])
	out.append(["body", "ร่างกาย"])
	out.append(["skills", "ฝีมือ"])
	return out


## Tabs sit in a strip, each as wide as its word (a cupboard's name is cut to fit).
func _tab_rect(i: int) -> Rect2:
	var tabs := _tabs()
	var x := X_FAR + 4.0
	for k in tabs.size():
		var w := _tab_w(tabs[k][1], tabs.size())
		if k == i:
			return Rect2(x, 22, w, 28)
		x += w + 2.0
	return Rect2()


func _tab_fs(n: int) -> int:
	return UiTheme.SIZE_BODY if n <= 4 else UiTheme.SIZE_LABEL


func _tab_w(label: String, n: int) -> float:
	var w := UiTheme.medium().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _tab_fs(n)).x
	return minf(w, 60.0) + 36.0


func _doll_rect() -> Rect2:
	return Rect2(PAD + SLOT + GAP, TOP + ROW, DOLL_W, ROW * 4 - GAP)


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
			if Items.is_weapon(it.id):
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


const MENU_W := 140.0
const MENU_ROW := 30.0


func _menu_rect(i: int) -> Rect2:
	return Rect2(menu_pos + Vector2(0, i * MENU_ROW), Vector2(MENU_W, MENU_ROW))


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

const DIM := UiTheme.TEXT_MUTED


func _draw() -> void:
	# The world goes dark behind the bag (and the HUD with it: one thing at a time).
	draw_rect(Rect2(-4000, -4000, 8000 + size.x, 8000 + size.y), Color(UiTheme.SURFACE_000, 0.6))
	UiTheme.panel(self, Rect2(Vector2.ZERO, size))
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
		var rarity := Color(0, 0, 0, 0)
		if it != null and ref != drag and Items.rarity_of(it.id) != "common":
			rarity = Items.RARITY_COLORS[Items.rarity_of(it.id)]
		UiTheme.slot(self, r, it != null and ref != drag, ref == picked or (lit and not drag.is_empty()), lit, rarity)
		if it == null:
			if ref == ["worn", "hand_l"] and worn.get("hand_r") != null and Items.two_handed(worn.hand_r.id):
				# The left hand is on the other end of a two-handed weapon.
				Items.draw_icon(self, r.grow(-r.size.x * 0.22), worn.hand_r.id)
				draw_rect(r.grow(-1), Color(UiTheme.SURFACE_200, 0.6))
				_label(r, "สองมือ", UiTheme.TEXT_MUTED, false)
			elif ref[0] == "worn":
				_slot_outline(r, ref[1])
				_label(r, Items.SLOT_NAMES.get(ref[1], Items.HAND_NAMES.get(ref[1], "")), UiTheme.TEXT_FAINT, false)
		elif ref != drag:
			_draw_item(r, it)  # (just the icon: its name is on the card below)
		if ref[0] == "inv" and ref[1] < Items.INV_SIZE:
			draw_string(UiTheme.medium(), r.position + Vector2(5, 13), str(ref[1] + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					UiTheme.TEXT_MUTED if it != null else UiTheme.TEXT_FAINT)
	_draw_card(head, body)
	# Dragged item follows the mouse.
	if not drag.is_empty():
		var it = _item(drag)
		if it != null:
			var m := get_local_mouse_position()
			var dr := Rect2(m - Vector2(SLOT, SLOT) * 0.5, Vector2(SLOT, SLOT))
			UiTheme.slot(self, dr, true, true)
			_draw_item(dr, it)
	# Right-click menu.
	if not menu_items.is_empty():
		var mr := Rect2(menu_pos - Vector2(0, 4), Vector2(MENU_W, MENU_ROW * menu_items.size() + 8))
		draw_style_box(UiTheme.rbox(UiTheme.SURFACE_100, UiTheme.RADIUS_SM, UiTheme.BORDER_STRONG, 8), mr)
	for i in menu_items.size():
		var r := _menu_rect(i)
		if r.has_point(get_local_mouse_position()):
			draw_style_box(UiTheme.rbox(UiTheme.SURFACE_300, UiTheme.RADIUS_SM), r.grow_individual(-4, 0, -4, 0))
		draw_string(body, r.position + Vector2(12, 20), menu_items[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_BODY,
				UiTheme.DANGER if menu_items[i][1] == "drop" else UiTheme.TEXT)


## A button: `primary` in the accent (the one thing to press), else a quiet one;
## `danger` words in red (throwing away).
func _button(r: Rect2, text: String, primary := false, danger := false) -> void:
	var lit := r.has_point(get_local_mouse_position())
	var bg := UiTheme.ACCENT if primary else (UiTheme.SURFACE_300 if lit else UiTheme.SURFACE_200)
	if primary and lit:
		bg = bg.lightened(0.08)
	draw_style_box(UiTheme.rbox(bg, UiTheme.RADIUS_SM, bg if primary else (UiTheme.BORDER_STRONG if lit else UiTheme.BORDER)), r)
	var col := UiTheme.ON_ACCENT if primary else (UiTheme.DANGER if danger else UiTheme.TEXT)
	draw_string(UiTheme.heading(), Vector2(r.position.x, r.get_center().y + 6), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
			UiTheme.SIZE_BODY, col)


## A panel's heading with a small note beside it.
func _heading(x: float, title: String, note := "") -> void:
	draw_string(UiTheme.heading(), Vector2(x, 43), title, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_TITLE, UiTheme.TEXT)
	if note != "":
		var w := UiTheme.heading().get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_TITLE).x
		draw_string(UiTheme.medium(), Vector2(x + w + 8, 42), note, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_CAPTION, UiTheme.TEXT_MUTED)


## You, dressed, turned by clicking; the slots round you; what guards each part.
func _draw_worn_side(head: Font, body: Font) -> void:
	_heading(24, "ที่สวมอยู่", "คลิกตัวละครเพื่อหมุน")
	draw_style_box(UiTheme.rbox(UiTheme.SURFACE_200, UiTheme.RADIUS_LG), _doll_rect())
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
	var y := TOP + ROW * 6 - GAP + 24 + 16
	draw_string(UiTheme.medium(), Vector2(PAD, y + 6), "กันกัด", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED)
	var sw := _R + SLOT - (PAD + SLOT + GAP)
	var strip := Rect2(PAD + SLOT + GAP, y - 16, sw, 40)
	draw_style_box(UiTheme.rbox(UiTheme.SURFACE_200, UiTheme.RADIUS_SM), strip)
	var x := strip.position.x
	var cell := sw / Items.PARTS.size()
	for part in Items.PARTS:
		var g := Items.guard_at(ids, part)
		var col := UiTheme.TEXT_FAINT if g <= 0.0 else (UiTheme.OK if g >= 0.5 else UiTheme.TEXT)
		draw_string(UiTheme.heading(), Vector2(x, y + 1), "%d" % roundi(g * 100), HORIZONTAL_ALIGNMENT_CENTER, cell, UiTheme.SIZE_LABEL, col)
		draw_string(UiTheme.medium(), Vector2(x, y + 18), Items.PART_NAMES[part], HORIZONTAL_ALIGNMENT_CENTER, cell, 10, UiTheme.TEXT_MUTED)
		x += cell
	# How hot it all is.
	var heat := 0.0
	for id in ids:
		heat += float(Items.def(id).get("hot", 0.0))
	if heat > 0.0:
		UiTheme.meter(self, Rect2(strip.position.x + 4, strip.end.y - 4, sw - 8, 2), clampf(heat / 1.2, 0.0, 1.0), Color("e8904a"))  # (how hot)


## The bag: slots, and a bar for the weight.
func _draw_bag_side(head: Font, body: Font) -> void:
	var used := inv.filter(func(x): return x != null).size()
	_heading(X_BAG, "กระเป๋า", "%d/%d ช่อง" % [used, inv.size()])
	if inv.size() > Items.INV_SIZE:
		draw_string(UiTheme.medium(), Vector2(X_BAG, TOP + 2 * ROW + 10), "จากเป้และกระเป๋า", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				UiTheme.TEXT_MUTED)
	var kg := 0.0
	for it in inv + worn.values():
		kg += Items.weight_of(it)
	var limit := Items.CARRY
	for k in worn:
		if worn[k] != null:
			limit += float(Items.def(worn[k].id).get("carry", 0.0))
	var rows := ceili(inv.size() / float(COLS))
	var y := TOP + rows * ROW - GAP + (16.0 if inv.size() > Items.INV_SIZE else 0.0) + 24.0
	var k2 := kg / maxf(limit, 0.1)
	var col := UiTheme.ACCENT if k2 <= 1.0 else UiTheme.DANGER
	var bw := COLS * ROW - GAP
	draw_string(UiTheme.medium(), Vector2(X_BAG, y), "น้ำหนัก", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL,
			UiTheme.DANGER if k2 > 1.0 else UiTheme.TEXT_MUTED)
	draw_string(UiTheme.medium(), Vector2(X_BAG, y), "%.1f/%.0f กก." % [kg, limit], HORIZONTAL_ALIGNMENT_RIGHT, bw, UiTheme.SIZE_LABEL,
			UiTheme.DANGER if k2 > 1.0 else UiTheme.TEXT)
	UiTheme.meter(self, Rect2(X_BAG, y + 7, bw, 6), k2, col)
	if k2 > 1.0:
		draw_string(body, Vector2(X_BAG, y + 32), "หนักเกิน · เดินช้าลง เหนื่อยเร็ว", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL, col)


## The right-hand column: tabs, then the ground, a cupboard or the recipes.
func _draw_far_side(head: Font, body: Font) -> void:
	var tabs := _tabs()
	var last := _tab_rect(tabs.size() - 1)
	draw_style_box(UiTheme.rbox(UiTheme.SURFACE_200, UiTheme.RADIUS_SM), Rect2(X_FAR, 18, W - PAD - X_FAR, 36))
	var fs := _tab_fs(tabs.size())
	for i in tabs.size():
		var r := _tab_rect(i)
		var on: bool = tab == tabs[i][0]
		var lit := r.has_point(get_local_mouse_position())
		if on or lit:
			draw_style_box(UiTheme.rbox(UiTheme.ACCENT if on else UiTheme.SURFACE_300, UiTheme.RADIUS_SM), r)
		var col := UiTheme.ON_ACCENT if on else (UiTheme.TEXT if lit else UiTheme.TEXT_MUTED)
		_tab_icon(Vector2(r.position.x + 13, r.position.y + 14), tabs[i][0], col)
		draw_string(UiTheme.medium(), r.position + Vector2(24, 19), _fit(tabs[i][1], UiTheme.medium(), fs, r.size.x - 36), HORIZONTAL_ALIGNMENT_LEFT,
				-1, fs, col)
		if tabs[i][0] == "body" and me and not Body.statuses(me).filter(func(s): return s.level == 2).is_empty():
			draw_circle(Vector2(r.end.x - 7, r.get_center().y), 3.0, UiTheme.DANGER)  # something needs seeing to
	var hint := {ground = "ลากของมาวางที่นี่เพื่อทิ้ง", box = "ลากของมาเก็บไว้ในนี้ได้", craft = "ใช้ของในกระเป๋า · ต้องยืนนิ่ง"}
	if tab == "body":
		_draw_body(head, body)
		return
	if tab == "skills":
		_draw_skills(head, body)
		return
	if tab == "craft":
		_draw_recipes(head, body)
		return
	draw_string(body, Vector2(X_FAR, TOP + 3 * ROW - GAP + 20), hint[tab], HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_CAPTION, UiTheme.TEXT_MUTED)
	if not _far_items().is_empty():
		_button(_take_all_rect(), "เก็บทั้งหมด", true)


func _take_all_rect() -> Rect2:
	return Rect2(X_FAR, TOP + 3 * ROW - GAP + 32, FAR_COLS * ROW - GAP, 36)


## The card for the item picked or under the mouse: what it is, its numbers, and buttons.
func _draw_card(head: Font, body: Font) -> void:
	draw_line(Vector2(PAD, CARD_Y - 24), Vector2(W - PAD, CARD_Y - 24), UiTheme.BORDER, 1)
	var shown := _shown()
	var it = _item(shown)
	if not hover.is_empty() and hover[0] == "recipe":
		var rc: Dictionary = Crafting.RECIPES[hover[1]]
		UiTheme.slot(self, Rect2(24, CARD_Y + 2, 64, 64), true)
		Items.draw_icon(self, Rect2(34, CARD_Y + 12, 44, 44), rc.makes)
		draw_string(head, Vector2(102, CARD_Y + 24), Crafting.recipe_name(hover[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_HEADING, UiTheme.TEXT)
		draw_string(body, Vector2(102, CARD_Y + 46), "ต้องใช้: " + _recipe_line(hover[1]), HORIZONTAL_ALIGNMENT_LEFT, W - 130, UiTheme.SIZE_LABEL, DIM)
		return
	var work := GameUI.working()
	if it == null and not work.is_empty():
		_draw_work(work)
		return
	if it == null:
		UiTheme.draw_rich(self, Vector2(24, CARD_Y + 36), "คลิก ดูรายละเอียด · ลาก ย้าย · [Shift] + คลิก ส่งข้ามฝั่ง · คลิกขวา เมนู",
				body, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED, false, true)
		var cw := UiTheme.draw_rich(self, Vector2.ZERO, "[Tab] ปิด", body, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED, true, true)
		UiTheme.draw_rich(self, Vector2(W - 24 - cw, CARD_Y + 36), "[Tab] ปิด", body, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED, false, true)
		return
	var d := Items.def(it.id)
	var ir := Rect2(24, CARD_Y + 2, 64, 64)
	var rarity := Items.rarity_of(it.id)
	UiTheme.slot(self, ir, true, false, false, Items.RARITY_COLORS[rarity] if rarity != "common" else Color(0, 0, 0, 0))
	_draw_item(ir, it)
	draw_string(head, Vector2(102, CARD_Y + 22), Items.display_name(it.id), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_HEADING, UiTheme.TEXT)
	if rarity != "common":
		var nw := head.get_string_size(Items.display_name(it.id), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_HEADING).x
		var rtext: String = Items.RARITY_NAMES[rarity]
		if d.has("from"):
			rtext += " · ได้จาก" + d.from + "เท่านั้น"
		if d.has("repair_lv"):
			rtext += " · ซ่อม: ช่าง Lv %d" % int(d.repair_lv)
		elif Items.tier(it.id) >= Items.DANGER_TIER:
			rtext += " · เจอแค่ใน" + Items.TIER_NAMES[Items.tier(it.id)]
		draw_string(UiTheme.medium(), Vector2(110 + nw, CARD_Y + 21), rtext, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL,
				Items.RARITY_COLORS[rarity])
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
	if d.get("type") == "gun":
		stats.push_front(["hit", "กระสุน %d/%d · ใช้%s" % [it.get("ammo", 0), d.mag, Items.display_name(d.ammo)]])
	var m = get_tree().current_scene
	var state := Items.state_text(it, m.now() if m != null and m.has_method("now") else 0.0)
	if state != "":
		stats.push_front(["use", state])  # (what's in it, how fresh)
	stats.append(["kg", "%.1f กก." % Items.weight_of(it)])
	if Items.stack(it.id) > 1:
		stats.append(["n", "%d/%d" % [it.get("n", 1), Items.stack(it.id)]])
	var x := 102.0
	var sy := CARD_Y + 48
	for s in stats:
		_mark(Vector2(x + 5, sy - 4), s[0])
		draw_string(body, Vector2(x + 14, sy), s[1], HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL, DIM)
		x += 22.0 + body.get_string_size(s[1], HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_LABEL).x
		if x > W - 330:
			break
	# Buttons.
	var acts := _actions(shown, it)
	for i in acts.size():
		_button(_button_rect(i, acts.size()), acts[i][0], i == 0 and acts[i][1] != "drop", acts[i][1] == "drop")


## The work under way, in the card's place: what's being made, a bar, and to keep still.
func _draw_work(w: Dictionary) -> void:
	var ir := Rect2(24, CARD_Y + 2, 64, 64)
	UiTheme.slot(self, ir, true, true)
	if w.recipe != "" and Crafting.RECIPES.has(w.recipe):
		Items.draw_icon(self, ir.grow(-12), Crafting.RECIPES[w.recipe].makes)
	else:
		_tab_icon(ir.get_center(), "craft", UiTheme.ACCENT)
	var x := 102.0
	var bw := W - 24 - x
	draw_string(UiTheme.heading(), Vector2(x, CARD_Y + 22), "กำลัง" + w.what, HORIZONTAL_ALIGNMENT_LEFT, bw - 60, UiTheme.SIZE_HEADING, UiTheme.TEXT)
	draw_string(UiTheme.medium(), Vector2(x, CARD_Y + 22), "อีก %.1f วิ" % w.left, HORIZONTAL_ALIGNMENT_RIGHT, bw, UiTheme.SIZE_LABEL, UiTheme.TEXT_MUTED)
	UiTheme.meter(self, Rect2(x, CARD_Y + 32, bw, 8), w.k, UiTheme.ACCENT)
	draw_string(UiTheme.body(), Vector2(x, CARD_Y + 60), w.hint, HORIZONTAL_ALIGNMENT_LEFT, bw, UiTheme.SIZE_CAPTION, UiTheme.TEXT_MUTED)


func _button_rect(i: int, n: int) -> Rect2:
	var w := 72.0
	return Rect2(W - 24 - (n - i) * (w + 6) + 6, CARD_Y + 16, w, 36)


# --- Little drawings -------------------------------------------------------------

## A slot's name band: what's in it (or what goes in it), cut short to fit.
func _label(r: Rect2, text: String, col: Color, filled: bool) -> void:
	var f := UiTheme.medium()
	var size := 10
	var band := Rect2(r.position.x + 2, r.end.y - 14, r.size.x - 4, 12)
	if filled:
		draw_rect(band, Color(UiTheme.SURFACE_100, 0.72))
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
	UiTheme.meter(self, r, frac, col, UiTheme.SURFACE_000)


## A faint outline in an empty worn slot of what goes there.
func _slot_outline(r: Rect2, slot: String) -> void:
	var c := r.get_center() - Vector2(0, 5)  # (room below for the name)
	var col := Color(UiTheme.TEXT_FAINT, 0.7)
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
			draw_line(c + Vector2(-4, 3), c + Vector2(4, -3), UiTheme.SURFACE_200, 2.0)
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
		"waist":  # a belt and its buckle
			draw_rect(Rect2(c + Vector2(-13, -3), Vector2(26, 7)), col, false, w)
			draw_rect(Rect2(c + Vector2(-3, -5), Vector2(6, 11)), col, false, w)


## A small mark before a number on the card.
func _mark(c: Vector2, kind: String) -> void:
	var col := UiTheme.TEXT_MUTED
	match kind:
		"guard":  # a shield
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -4), c + Vector2(4, -4), c + Vector2(4, 1), c + Vector2(0, 5), c + Vector2(-4, 1)]), col)
		"hit":  # a blade
			draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), col, 2.0)
			draw_line(c + Vector2(-4, 1), c + Vector2(-1, 4), col, 1.5)
		"hp":  # a little wear bar
			draw_rect(Rect2(c + Vector2(-5, -1.5), Vector2(10, 3)), Color(0, 0, 0, 0.4))
			draw_rect(Rect2(c + Vector2(-5, -1.5), Vector2(7, 3)), UiTheme.OK)
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
		"skills":  # a star
			var pts := PackedVector2Array()
			for k in 10:
				pts.append(c + Vector2.from_angle(-PI / 2 + k * PI / 5) * (6.0 if k % 2 == 0 else 2.6))
			draw_colored_polygon(pts, col)


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
					sub = ("เลือดออก · " if w.bleeding else "") + ("อักเสบ มีไข้ · " if w.get("festering", false) else "") + ("ยังไม่พันแผล · ไม่หายเองถ้าไม่พัน · เสี่ยงอักเสบ" if w.kind == "bite" 							else "ยังไม่พันแผล · " + Body.heal_text(w) + " (พันแล้วเร็วขึ้น)")
					level = 2 if w.kind == "bite" or w.bleeding else 1
					button = "treat" if has_bandage else ""
			"sprain":
				sub = "วิ่งไม่ได้ เดินช้าลง · " + Body.heal_text(w) + " · นอนจะเร็วขึ้น"
			"bruise":
				sub = "ของที่ใส่กันไว้ได้ · " + Body.heal_text(w)
				level = 0
		out.append({i = out.size(), wound = k, icon = "bandaged" if w.bandaged else w.kind, level = level, title = Body.title(w),
				sub = sub, button = button, slot = -1, healing = Body.progress(w)})
	var slot := -1
	for k in inv.size():
		if inv[k] != null and inv[k].id == "antibiotic":
			slot = k
	if Body.fevered(me.wounds):
		out.append({i = out.size(), wound = -1, icon = "fever", level = 1, title = "แผลอักเสบ มีไข้",
				sub = "อ่อนแรง เลือดลดช้า ๆ" + (" · มียาปฏิชีวนะในกระเป๋า" if slot >= 0 else " · ต้องใช้ยาปฏิชีวนะ หาได้ที่ร้านขายยา"),
				button = "cure" if slot >= 0 else "", slot = slot})
	if me.infection > 0.0:
		var stage := Body.infection_stage(me.infection)
		out.append({i = out.size(), wound = -1, icon = "fever", level = 2 if stage >= 2 else 1,
				title = "ติดเชื้อซอมบี้ · ระยะ %d จาก 4: %s" % [stage + 1, Body.STAGES[stage][1]],
				sub = Body.STAGES[stage][2] + (" · มียาปฏิชีวนะในกระเป๋า" if slot >= 0 else " · ต้องใช้ยาปฏิชีวนะ หาได้ที่ร้านขายยา"),
				button = "cure" if slot >= 0 else "", slot = slot, infection = me.infection})
	return out


func _body_row_rect(i: int) -> Rect2:
	return Rect2(X_FAR, TOP + i * 68, W - X_FAR - PAD, 60)


func _body_button(i: int) -> Rect2:
	var r := _body_row_rect(i)
	return Rect2(r.end.x - 74, r.position.y + 12, 66, 34)


## Skills: the survivor level, then each skill's level, how far to the next,
## what it does and what the next level opens (Skills, data/skills.cfg).
func _draw_skills(head: Font, body: Font) -> void:
	if me == null:
		return
	draw_string(head, Vector2(X_FAR, TOP + 14), "ระดับผู้รอด %d" % Skills.total(me.skills), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_HEADING,
			UiTheme.ACCENT)
	draw_string(UiTheme.medium(), Vector2(X_FAR, TOP + 14), "เก่งขึ้นจากการทำจริง", HORIZONTAL_ALIGNMENT_RIGHT, W - X_FAR - 24, UiTheme.SIZE_CAPTION, DIM)
	var i := 0
	for id in Skills.DEFS:
		var d: Dictionary = Skills.DEFS[id]
		var xp: float = me.skills.get(id, 0.0)
		var lvl := Skills.level_of(xp)
		var r := Rect2(X_FAR, TOP + 28 + i * 58, W - X_FAR - PAD, 52)
		if r.end.y > CARD_Y - 32:
			break
		draw_style_box(UiTheme.rbox(UiTheme.SURFACE_200, UiTheme.RADIUS_SM, UiTheme.BORDER), r)
		draw_string(head, r.position + Vector2(12, 21), d.name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_BODY, UiTheme.TEXT)
		draw_string(head, r.position + Vector2(r.size.x - 72, 21), "Lv %d" % lvl, HORIZONTAL_ALIGNMENT_RIGHT, 60, UiTheme.SIZE_BODY, UiTheme.ACCENT)
		UiTheme.meter(self, Rect2(r.position + Vector2(12, 27), Vector2(r.size.x - 24, 4)), Skills.progress(xp), UiTheme.ACCENT, UiTheme.SURFACE_000)
		# The next thing it opens, if any is still ahead.
		var next := ""
		var unlocks: Dictionary = d.get("unlocks", {})
		for k in unlocks:
			if int(k) > lvl and (next == "" or int(k) < int(next.get_slice(":", 0))):
				next = "%s:%s" % [k, unlocks[k][1]]
		var sub := "เลเวลสูงสุดแล้ว" if lvl >= Skills.MAX_LEVEL else ("อีก %d EXP" % ceili(Skills.xp_for(lvl + 1) - xp))
		if next != "":
			sub += " · Lv %s: %s" % [next.get_slice(":", 0), next.get_slice(":", 1)]
		draw_string(body, r.position + Vector2(12, 45), _fit(sub, body, UiTheme.SIZE_CAPTION, r.size.x - 24), HORIZONTAL_ALIGNMENT_LEFT, -1,
				UiTheme.SIZE_CAPTION, DIM)
		i += 1


func _draw_body(head: Font, body: Font) -> void:
	var rows := _body_rows()
	if rows.is_empty():
		draw_string(body, Vector2(X_FAR, TOP + 14), "ร่างกายปกติดี ไม่มีบาดแผล", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_BODY, DIM)
		return
	for row in rows:
		var r := _body_row_rect(row.i)
		if r.end.y > CARD_Y - 32:
			break
		var col: Color = Body.LEVEL_COLORS[row.level]
		draw_style_box(UiTheme.rbox(UiTheme.SURFACE_200, UiTheme.RADIUS_SM, Color(col, 0.6) if row.level > 0 else UiTheme.BORDER), r)
		Body.draw_icon(self, r.position + Vector2(20, 24), row.icon, col, 1.1)
		var tw := r.size.x - 44 - (80 if row.button != "" else 0)
		draw_string(head, r.position + Vector2(40, 19), _fit(row.title, head, UiTheme.SIZE_BODY, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_BODY,
				UiTheme.TEXT)
		draw_multiline_string(body, r.position + Vector2(40, 36), row.sub, HORIZONTAL_ALIGNMENT_LEFT, tw, UiTheme.SIZE_CAPTION, 2, DIM)  # (wrapped: it says what to do)
		if row.has("infection"):
			_bar(Rect2(r.position.x + 40, r.end.y - 4, tw, 3), row.infection / 100.0, col)
		elif row.has("healing") and row.healing[1] >= 0.0:
			_bar(Rect2(r.position.x + 40, r.end.y - 4, tw, 3), row.healing[0], UiTheme.OK)  # how far it's healed
		if row.button != "":
			_button(_body_button(row.i), "พันแผล" if row.button == "treat" else "ใช้ยา", true)


func _recipe_rect(i: int) -> Rect2:
	return Rect2(X_FAR, TOP + i * 40, W - X_FAR - PAD, 36)


func _draw_recipes(head: Font, body: Font) -> void:
	var ids := Crafting.RECIPES.keys()
	var work := GameUI.working()
	for i in ids.size():
		var r: Dictionary = Crafting.RECIPES[ids[i]]
		var rr := _recipe_rect(i)
		if rr.end.y > CARD_Y - 32:
			break
		var locked := Crafting.locked_why(me, ids[i]) if me else ""
		var ok := Crafting.can_make(inv, ids[i]) and locked == ""
		var lit: bool = hover == ["recipe", ids[i]]
		draw_style_box(UiTheme.rbox(UiTheme.SURFACE_300 if lit else UiTheme.SURFACE_200, UiTheme.RADIUS_SM,
				UiTheme.ACCENT if lit and ok else (UiTheme.BORDER_STRONG if lit else UiTheme.BORDER)), rr)
		if work.get("recipe", "") == ids[i]:  # being made now: the row fills up
			draw_style_box(UiTheme.rbox(UiTheme.SURFACE_300, UiTheme.RADIUS_SM, UiTheme.ACCENT), rr)
			UiTheme.meter(self, Rect2(rr.position.x + 1, rr.end.y - 3, rr.size.x - 2, 2), work.k, UiTheme.ACCENT, UiTheme.SURFACE_000)
		Items.draw_icon(self, Rect2(rr.position + Vector2(6, 6), Vector2(23, 23)), r.makes)
		var fit := rr.size.x - 44
		draw_string(head, rr.position + Vector2(38, 15), _fit(Crafting.recipe_name(ids[i]), head, UiTheme.SIZE_BODY - 1, fit), HORIZONTAL_ALIGNMENT_LEFT,
				-1, UiTheme.SIZE_BODY - 1, UiTheme.TEXT if ok else UiTheme.TEXT_MUTED)
		draw_string(body, rr.position + Vector2(38, 30), _fit(locked if locked != "" else _recipe_line(ids[i]), body, UiTheme.SIZE_CAPTION, fit), HORIZONTAL_ALIGNMENT_LEFT, -1,
				UiTheme.SIZE_CAPTION, UiTheme.OK if ok else UiTheme.TEXT_FAINT)


## An item in a slot. `named`: room is left at the bottom for its name band.
func _draw_item(r: Rect2, it: Dictionary, named := false) -> void:
	if named:
		Items.draw_icon(self, Rect2(r.position + Vector2(r.size.x * 0.22, r.size.y * 0.1), Vector2(r.size.x * 0.56, r.size.x * 0.56)), Items.key(it))
	else:
		Items.draw_icon(self, r.grow(-r.size.x * 0.19), Items.key(it))
	if it.get("n", 1) > 1:  # (the whole slot's width: "100" fits)
		UiTheme.over_world(self, Vector2(r.position.x + 2, r.end.y - 6), "%d" % it.n, UiTheme.heading(), UiTheme.SIZE_LABEL, UiTheme.TEXT,
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6)
	var d := Items.def(it.id)
	if d.get("type") in ["weapon", "wear"] and d.has("hp"):
		var frac: float = float(it.hp) / d.hp
		var bar := Rect2(r.position.x + 5, r.end.y - (16.0 if named else 7.0), r.size.x - 10, 2.5 if named else 3.0)
		UiTheme.meter(self, bar, frac, UiTheme.OK if frac > 0.3 else UiTheme.DANGER, Color(0, 0, 0, 0.4))
