class_name BoxCard
extends Control
## What a cupboard, shelf or fridge holds, as a small card by the side of the
## screen instead of the whole bag: click a thing to take it, E takes the lot
## (the rare things first), Tab opens the bag beside it. It never stops you
## walking: walk off and it closes (see Main's check on open_box).

signal take_requested(ref: Array)
signal closed

const W := 300.0
const ROW := 44.0
const TOP := 44.0
const FOOT := 34.0

var box_id := -1
var items: Array = []
var title := ""
var hover := -1
var empty_t := 0.0  # an empty one shows for a moment, then goes


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


## Show (or refresh) the card with what's inside now.
func show_box(cid: int, list: Array, name: String) -> void:
	box_id = cid
	items = list
	title = name
	var n := _rows().size()
	size = Vector2(W, TOP + maxf(n, 1.0) * ROW + FOOT)
	var view := get_viewport_rect().size
	position = Vector2(view.x - W - 28.0, maxf(90.0, view.y * 0.5 - size.y * 0.5 - 40.0))
	visible = true
	empty_t = 1.4 if n == 0 else 0.0
	set_process(n == 0)
	queue_redraw()


func hide_card() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if visible and _rows().is_empty():
		empty_t -= delta
		if empty_t <= 0.0:
			hide_card()
			closed.emit()


## The indexes of what's in there, the best first.
func _rows() -> Array:
	var out := []
	for i in items.size():
		if items[i] != null:
			out.append(i)
	out.sort_custom(func(a, b): return _rank(items[a]) > _rank(items[b]))
	return out


func _rank(it: Dictionary) -> int:
	return {"rare": 2, "uncommon": 1}.get(Items.rarity_of(it.id), 0)


## E: take everything, the rare first, as far as the bag has room.
func take_all() -> void:
	for i in _rows():
		take_requested.emit(["box", box_id, i])


func _row_at(pos: Vector2) -> int:
	var rows := _rows()
	var k := int((pos.y - TOP) / ROW)
	if pos.y < TOP or k < 0 or k >= rows.size():
		return -1
	return rows[k]


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _row_at(e.position)
		if h != hover:
			hover = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := _row_at(e.position)
		if i >= 0:
			take_requested.emit(["box", box_id, i])
		accept_event()


func _draw() -> void:
	UiTheme.card(self, Rect2(Vector2.ZERO, size))
	draw_string(UiTheme.heading(), Vector2(16, 28), title, HORIZONTAL_ALIGNMENT_LEFT, W - 32, UiTheme.SIZE_HEADING, UiTheme.TEXT)
	var rows := _rows()
	if rows.is_empty():
		draw_string(UiTheme.body(), Vector2(16, TOP + 26), "ว่างเปล่า", HORIZONTAL_ALIGNMENT_LEFT, W - 32, UiTheme.SIZE_BODY, UiTheme.TEXT_MUTED)
	for k in rows.size():
		var it: Dictionary = items[rows[k]]
		var r := Rect2(10, TOP + k * ROW, W - 20, ROW - 4)
		var rc: String = Items.rarity_of(it.id)
		UiTheme.slot(self, r, true, false, rows[k] == hover, Items.RARITY_COLORS[rc] if rc != "common" else Color(0, 0, 0, 0))
		Items.draw_icon(self, Rect2(r.position + Vector2(6, 5), Vector2(28, 28)), Items.key(it))
		var label := Items.display_name(it.id) + (" ×%d" % it.n if it.get("n", 1) > 1 else "")
		draw_string(UiTheme.body(), Vector2(r.position.x + 44, r.position.y + 25), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 52, UiTheme.SIZE_BODY, UiTheme.TEXT)
	var fy := size.y - 12.0
	var x := 16.0
	if not rows.is_empty():
		x += UiTheme.keycap(self, Vector2(x, fy), "E", UiTheme.SIZE_LABEL, true) + 6.0
		draw_string(UiTheme.body(), Vector2(x, fy), "เก็บทั้งหมด", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_CAPTION, UiTheme.TEXT_MUTED)
		x += 86.0
	x += UiTheme.keycap(self, Vector2(x, fy), "Tab", UiTheme.SIZE_LABEL) + 6.0
	draw_string(UiTheme.body(), Vector2(x, fy), "กระเป๋า", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_CAPTION, UiTheme.TEXT_MUTED)
