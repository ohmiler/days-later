class_name InventoryBar
extends Control
## The 8-slot bar at the bottom of the screen. Slot contents come from the
## server as an array of null or {id, n, hp}.

const SLOT := 58.0
const GAP := 6.0

var slots: Array = []
var selected := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := Items.INV_SIZE * (SLOT + GAP) - GAP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -w / 2
	offset_right = w / 2
	offset_top = -SLOT - 34
	offset_bottom = -8


func show_inventory(inv: Array, sel: int) -> void:
	slots = inv
	selected = sel
	queue_redraw()


func _draw() -> void:
	var font := Look.thai_font()
	for i in Items.INV_SIZE:
		var r := Rect2(i * (SLOT + GAP), 22, SLOT, SLOT)
		var sel := i == selected
		draw_rect(r, Color(0.05, 0.05, 0.05, 0.65))
		draw_rect(r, Color(1, 0.85, 0.4) if sel else Color(1, 1, 1, 0.25), false, 3.0 if sel else 1.0)
		draw_string(font, r.position + Vector2(5, 15), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
		var it = slots[i] if i < slots.size() else null
		if it == null:
			continue
		Items.draw_icon(self, r.grow(-10), it.id)
		if it.n > 1:
			draw_string(font, r.end - Vector2(16, 5), "x%d" % it.n, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		var d := Items.def(it.id)
		if d.get("type") == "weapon":
			var frac: float = float(it.hp) / d.hp
			draw_rect(Rect2(r.position.x + 4, r.end.y - 6, (SLOT - 8), 3), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(r.position.x + 4, r.end.y - 6, (SLOT - 8) * frac, 3),
					Color("7ad15a") if frac > 0.3 else Color("e0603a"))
		if sel:
			draw_string(font, Vector2(r.get_center().x - 80, 14), Items.display_name(it.id),
					HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color.WHITE)
