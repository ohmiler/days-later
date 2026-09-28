class_name InventoryBar
extends Control
## The 8-slot hotbar at the bottom of the screen: a tray of design-system
## Slots, the selected one edged in the accent. What you hold and how to use it shows above
## the bar for a moment when it changes (or while the mouse is over a slot),
## then fades: the screen stays clear the rest of the time. Empty slots are
## drawn small and faint.
## Slot contents come from the server as an array of null or {id, n, hp}.

const SLOT := 52.0
const GAP := 6.0
const TRAY := 6.0  # the tray's padding around the slots

var slots: Array = []
var selected := 0
var hover := -1  # slot under the mouse: highlighted, and its details shown instead
var hands := ""  # what's held, e.g. "มีดทำครัว + ค้อน" ("" empty-handed)
var has_gun := false
var label_t := 0.0  # seconds since what's held changed: its name shows for a moment
var quiet := false  # riding: no label at all (the bike's dashboard is there)
var _held := ""

const LABEL_FOR := 2.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit(Items.INV_SIZE)


func _fit(n: int) -> void:
	var w := n * (SLOT + GAP) - GAP + TRAY * 2
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -w / 2
	offset_right = w / 2
	offset_top = -SLOT - TRAY * 2 - 64
	offset_bottom = -24


## The slot at `p` (in this control's coordinates), or -1.
func slot_at(p: Vector2) -> int:
	for i in Items.INV_SIZE:
		if _rect(i).grow(GAP / 2).has_point(p):
			return i
	return -1


func _rect(i: int) -> Rect2:
	return Rect2(TRAY + i * (SLOT + GAP), size.y - TRAY - SLOT, SLOT, SLOT)


func _process(delta: float) -> void:
	var h := slot_at(get_local_mouse_position()) if is_visible_in_tree() else -1
	if h != hover:
		hover = h
		queue_redraw()
	# Show the label again whenever what's held (or selected) changes.
	var it = slots[selected] if selected < slots.size() else null
	var held := "%d|%s|%s" % [selected, hands, it.id if it != null else ""]
	if held != _held:
		_held = held
		label_t = 0.0
	if label_t < LABEL_FOR + 0.6:
		label_t += delta
		queue_redraw()


func show_inventory(inv: Array, sel: int) -> void:
	slots = inv
	selected = sel
	_fit(Items.INV_SIZE)
	queue_redraw()


func _draw() -> void:
	UiTheme.card(self, Rect2(0, size.y - SLOT - TRAY * 2, size.x, SLOT + TRAY * 2))
	for i in Items.INV_SIZE:
		var it = slots[i] if i < slots.size() else null
		var sel := i == selected
		var r := _rect(i)
		var rare := Color(0, 0, 0, 0)
		if it != null:
			rare = Items.RARITY_COLORS.get(Items.def(it.id).get("rarity", "common"), Color(0, 0, 0, 0))
		UiTheme.slot(self, r, it != null, sel, i == hover)
		draw_string(UiTheme.medium(), r.position + Vector2(5, 13), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				UiTheme.TEXT_MUTED if it != null or sel else UiTheme.TEXT_FAINT)
		if it == null:
			continue
		Items.draw_icon(self, r.grow(-11), Items.key(it))
		if it.n > 1:
			var q := "%d" % it.n
			UiTheme.over_world(self, Vector2(r.position.x, r.end.y - 5), q, UiTheme.heading(), UiTheme.SIZE_LABEL, UiTheme.TEXT,
					HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 5)
		var d := Items.def(it.id)
		if d.get("type") in ["weapon", "wear"]:
			# Wear stands in for rarity under things that wear out.
			var frac: float = float(it.hp) / d.hp
			UiTheme.meter(self, Rect2(r.position.x + 6, r.end.y - 5, SLOT - 12, 3), frac,
					UiTheme.OK if frac > 0.3 else UiTheme.DANGER, Color(0, 0, 0, 0.4))
		elif rare != Items.RARITY_COLORS.common:
			draw_rect(Rect2(r.position.x + 6, r.end.y - 4, r.size.x - 12, 2), rare)

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
		# What's in it and how fresh it is (a bottle of canal water, rice gone off).
		var m = get_tree().current_scene
		var state := Items.state_text(cur, m.now() if m != null and m.has_method("now") else 0.0)
		if Items.holds(cur.id) > 0:
			info = state + (" · คลิกขวาดื่ม" if hover >= 0 else " · กด F ดื่ม") + (" · ขว้างได้ [T]" if Items.has_tag(cur.id, "throw") else "")
		elif state != "":
			info = state + " · " + info
	var a := 1.0 if hover >= 0 else clampf((LABEL_FOR + 0.6 - label_t) / 0.6, 0.0, 1.0)
	if quiet:
		a = 0.0
	if a <= 0.0:
		return
	var ty := size.y - SLOT - TRAY * 2
	UiTheme.over_world(self, Vector2(-200, ty - 30), name, UiTheme.heading(), UiTheme.SIZE_HEADING, Color(UiTheme.TEXT, a),
			HORIZONTAL_ALIGNMENT_CENTER, size.x + 400)
	UiTheme.over_world(self, Vector2(-200, ty - 11), info, UiTheme.body_bold(), UiTheme.SIZE_LABEL, Color(UiTheme.TEXT, 0.9 * a),
			HORIZONTAL_ALIGNMENT_CENTER, size.x + 400)
