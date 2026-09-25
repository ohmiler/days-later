class_name InventoryBar
extends Control
## The 8-slot hotbar at the bottom of the screen, styled like cardboard.
## The selected slot lifts up and its name shows above the bar.
## Slot contents come from the server as an array of null or {id, n, hp}.

const SLOT := 64.0
const GAP := 8.0
const LIFT := 10.0

var slots: Array = []
var selected := 0
var hover := -1  # slot under the mouse: highlighted, and its details shown instead
var hands := ""  # what's held, e.g. "มีดทำครัว + ค้อน" ("" empty-handed)
var has_gun := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit(Items.INV_SIZE)


func _fit(n: int) -> void:
	var w := n * (SLOT + GAP) - GAP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -w / 2
	offset_right = w / 2
	offset_top = -SLOT - 84
	offset_bottom = -20


## The slot at `p` (in this control's coordinates), or -1.
func slot_at(p: Vector2) -> int:
	var top := size.y - SLOT
	for i in Items.INV_SIZE:
		if Rect2(i * (SLOT + GAP), top - LIFT, SLOT, SLOT + LIFT).has_point(p):
			return i
	return -1


func _process(_delta: float) -> void:
	var h := slot_at(get_local_mouse_position()) if is_visible_in_tree() else -1
	if h != hover:
		hover = h
		queue_redraw()


func show_inventory(inv: Array, sel: int) -> void:
	slots = inv
	selected = sel
	_fit(Items.INV_SIZE)
	queue_redraw()


func _draw() -> void:
	var top := size.y - SLOT
	for i in Items.INV_SIZE:
		var it = slots[i] if i < slots.size() else null
		var sel := i == selected
		var r := Rect2(i * (SLOT + GAP), top - (LIFT if sel else 0.0), SLOT, SLOT)
		if i == hover and not sel:
			r.position.y -= 3.0
		if it == null:
			draw_style_box(UiTheme.box(Color(0.11, 0.1, 0.08, 0.65), 6, UiTheme.WARN if sel else Color(0.23, 0.2, 0.17), 2), r)
			draw_string(UiTheme.heading(), r.position + Vector2(6, 16), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(UiTheme.PAPER, 0.35))
			continue
		# Cardboard slot with a drop shadow; a glow ring when selected.
		draw_style_box(UiTheme.box(Color(0, 0, 0, 0.35), 6), Rect2(r.position + Vector2(0, 3), r.size))
		var card := UiTheme.box(Color("ad9870"), 6, UiTheme.WARN if sel else Color("6e5b3c"), 2)
		if sel:
			card.shadow_color = Color(0.95, 0.76, 0.19, 0.35)
			card.shadow_size = 6
		draw_style_box(card, r)
		draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 3)), Color(1, 1, 1, 0.1))
		draw_string(UiTheme.heading(), r.position + Vector2(6, 16), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(UiTheme.INK, 0.6))
		Items.draw_icon(self, r.grow(-12), it.id)
		if it.n > 1:
			draw_string(UiTheme.heading(), Vector2(r.position.x + 2, r.end.y - 6), "x%d" % it.n, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6, 14, UiTheme.INK)  # (the whole slot's width: "x100" fits)
		var d := Items.def(it.id)
		if d.get("type") in ["weapon", "wear"]:
			var frac: float = float(it.hp) / d.hp
			var bar := Rect2(r.position.x + 7, r.end.y - 9, SLOT - 14, 4)
			draw_rect(bar, Color(0, 0, 0, 0.35))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color("4f9a3a") if frac > 0.3 else Color("c8502a"))

	# Name of the held item (or the one under the mouse), with what it does.
	var shown := hover if hover >= 0 else selected
	var cur = slots[shown] if shown < slots.size() else null
	var name := (hands if hands != "" else "มือเปล่า") if hover < 0 else "ช่องว่าง"
	var info := ("คลิกซ้ายฟาด สลับมือ · คลิกขวาเตะ" if hands != "" else "คลิกซ้ายต่อย · คลิกขวาเตะ") if hover < 0 else "คลิกเพื่อเลือก"
	if hover < 0 and has_gun:
		info = "คลิกขวาค้างเล็ง · คลิกซ้ายยิง · [R] บรรจุ · [Space] เตะ"
	if hover < 0 and cur != null and Items.is_weapon(cur.id):
		cur = null  # (weapons are in your hands now: the label says what they hold)
	if cur != null:
		var d := Items.def(cur.id)
		name = Items.display_name(cur.id)
		match d.get("type"):
			"weapon":
				info = "ทนทาน %d / %d · คลิกซ้ายฟาด" % [cur.hp, d.hp]
			"use":
				info = ("คลิกขวาใช้ · " if hover >= 0 else "กด F ใช้ · ") + Items.effect_text(cur.id)
			"wear":
				info = ("คลิกขวาสวม · " if hover >= 0 else "กด F สวมใส่ · ") + Items.wear_text(cur.id)
			"trap":
				info = "กด F วางลงพื้นข้างหน้า · ซอมบี้ที่เหยียบจะโดน"
			"material":
				info = "ยืนที่ประตูแล้วกด R เพื่อตอกเสริม · หรือใช้ทำของ (Tab)" if cur.id == "wood" else "ใช้ทำของและซ่อม (Tab > ทำของ)"
			_:
				info = "ใช้ทำของ (Tab > ทำของ)" if cur.id == "magazine" else "เก็บไว้แลกของ"
	var cx := size.x / 2
	draw_string_outline(UiTheme.medium(), Vector2(0, 26), name, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 8, Color(0, 0, 0, 0.6))
	draw_string(UiTheme.medium(), Vector2(0, 26), name, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, UiTheme.PAPER)
	draw_string_outline(UiTheme.body(), Vector2(0, 46), info, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, 6, Color(0, 0, 0, 0.6))
	draw_string(UiTheme.body(), Vector2(0, 46), info, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(UiTheme.PAPER, 0.75))
