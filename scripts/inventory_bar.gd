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


func show_inventory(inv: Array, sel: int) -> void:
	slots = inv
	selected = sel
	_fit(maxi(Items.INV_SIZE, inv.size()))
	queue_redraw()


func _draw() -> void:
	var top := size.y - SLOT
	for i in maxi(Items.INV_SIZE, slots.size()):
		var it = slots[i] if i < slots.size() else null
		var sel := i == selected
		var r := Rect2(i * (SLOT + GAP), top - (LIFT if sel else 0.0), SLOT, SLOT)
		if it == null:
			draw_style_box(UiTheme.box(Color(0.11, 0.1, 0.08, 0.65), 6, UiTheme.WARN if sel else Color(0.23, 0.2, 0.17), 2), r)
			draw_string(UiTheme.heading(), r.position + Vector2(6, 16), str((i + 1) % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
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
		draw_string(UiTheme.heading(), r.position + Vector2(6, 16), str((i + 1) % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(UiTheme.INK, 0.6))
		Items.draw_icon(self, r.grow(-12), it.id)
		if it.n > 1:
			draw_string(UiTheme.heading(), r.end - Vector2(24, 6), "x%d" % it.n, HORIZONTAL_ALIGNMENT_RIGHT, 20, 14, UiTheme.INK)
		var d := Items.def(it.id)
		if d.get("type") in ["weapon", "wear"]:
			var frac: float = float(it.hp) / d.hp
			var bar := Rect2(r.position.x + 7, r.end.y - 9, SLOT - 14, 4)
			draw_rect(bar, Color(0, 0, 0, 0.35))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color("4f9a3a") if frac > 0.3 else Color("c8502a"))

	# Name of the held item, with what it does.
	var cur = slots[selected] if selected < slots.size() else null
	var name := "มือเปล่า"
	var info := "คลิกซ้ายต่อย · คลิกขวาเตะ"
	if cur != null:
		var d := Items.def(cur.id)
		name = Items.display_name(cur.id)
		match d.get("type"):
			"weapon":
				info = "ทนทาน %d / %d · คลิกซ้ายฟาด" % [cur.hp, d.hp]
			"use":
				info = "กด F ใช้ · " + Items.effect_text(cur.id)
			"wear":
				info = "กด F สวมใส่ · " + Items.wear_text(cur.id)
			"trap":
				info = "กด F วางลงพื้นข้างหน้า · ซอมบี้ที่เหยียบจะโดน"
			"material":
				info = "ยืนที่ประตูแล้วกด R เพื่อตอกเสริม / ซ่อม"
			_:
				info = "เก็บไว้แลกของ"
	var cx := size.x / 2
	draw_string_outline(UiTheme.medium(), Vector2(0, 26), name, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 8, Color(0, 0, 0, 0.6))
	draw_string(UiTheme.medium(), Vector2(0, 26), name, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, UiTheme.PAPER)
	draw_string_outline(UiTheme.body(), Vector2(0, 46), info, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, 6, Color(0, 0, 0, 0.6))
	draw_string(UiTheme.body(), Vector2(0, 46), info, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(UiTheme.PAPER, 0.75))
