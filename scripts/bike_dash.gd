class_name BikeDash
extends Control
## The bike's dashboard while you ride, over the hotbar (which fades back):
## speed, a rev bar that climbs as you open the throttle, the tank (or
## battery) in bars, the model, and E to get off. Slides in when you get on.

const REV_BARS := 12
const FUEL_BARS := 8
const KMH := 0.4  # km/h a pixel a second: the city is drawn small, so this reads right (a Wave tops out ~60)

var k := 0.0  # 0 hidden .. 1 shown
var speed := 0.0  # pixels a second
var top := 150.0
var rev := 0.0  # 0..1
var fuel := 1.0  # 0..1 of a tank
var electric := false
var model_name := ""
var broken := false
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -170
	offset_right = 170
	offset_top = -178
	offset_bottom = -104


## Every frame from Ui.update_hud.
func update(me: Player, v: Dictionary, delta: float) -> void:
	t += delta
	var riding := not v.is_empty()
	k = move_toward(k, 1.0 if riding else 0.0, delta * 5.0)
	visible = k > 0.01
	if riding:
		var m: Dictionary = Vehicles.MODELS[v.model]
		top = m.speed
		speed = me.ride_vel.length()
		electric = m.electric
		fuel = clampf(v.fuel / m.fuel, 0.0, 1.0)
		model_name = m.name
		broken = v.hp <= 0
		# The revs follow speed, and jump when you open the throttle.
		var throttle := 0.3 if me.move.length() > 0.1 and fuel > 0.0 else 0.0
		rev = lerpf(rev, clampf(speed / top * 0.75 + throttle, 0.0, 1.0), minf(1.0, delta * 8.0))
	queue_redraw()


func _draw() -> void:
	if k <= 0.0:
		return
	var a := k
	var off := Vector2(0, (1.0 - k) * 30.0)  # (slides up into place)
	var r := Rect2(Vector2.ZERO + off, size)
	draw_style_box(UiTheme.box(Color(0.04, 0.045, 0.05, 0.8 * a), 12, Color(0.24, 0.25, 0.26, a), 1), r)
	var paper := Color(UiTheme.PAPER, a)
	var dim := Color(0.66, 0.64, 0.58, a)
	var off_col := Color(0.27, 0.28, 0.27, a)
	# Speed, big, with its unit.
	var sp := str(roundi(speed * KMH))
	var fh := UiTheme.heavy()
	draw_string(fh, r.position + Vector2(18, 44), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, paper)
	var sw := fh.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(UiTheme.body(), r.position + Vector2(22 + sw, 44), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)
	# Revs: green, amber, red.
	var lit := roundi(rev * REV_BARS)
	for i in REV_BARS:
		var c := off_col
		if i < lit:
			c = Color("e05a3a") if i >= 9 else (Color("e8b82a") if i >= 6 else Color("7fc36a"))
			c.a = a
		draw_rect(Rect2(r.position + Vector2(18 + i * 10, 54), Vector2(7, 10)), c)
	draw_line(r.position + Vector2(158, 12), r.position + Vector2(158, r.size.y - 12), Color(0.24, 0.25, 0.26, a), 1.0)
	# The model, the tank, getting off.
	var x := r.position.x + 172
	draw_string(UiTheme.body(), Vector2(x, r.position.y + 22), model_name, HORIZONTAL_ALIGNMENT_LEFT, 150, 13, dim)
	var bars := ceili(fuel * FUEL_BARS)
	var low := bars <= 2
	var blink := low and fmod(t, 0.8) < 0.4
	var ic := Color("e8a13a", a) if not low else Color("e05a3a", a)
	_tank_icon(Vector2(x, r.position.y + 33), ic)
	for i in FUEL_BARS:
		var c := off_col
		if i < bars and not blink:
			c = Color("e05a3a", a) if low else paper
		draw_rect(Rect2(x + 22 + i * 11, r.position.y + 34, 8, 10), c)
	if broken:
		draw_string(UiTheme.medium(), Vector2(x, r.position.y + 64), "รถพัง", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e05a3a", a))
	else:
		var kr := Rect2(x, r.position.y + 51, 20, 18)
		draw_style_box(UiTheme.box(Color(UiTheme.WARN, a), 4), kr)
		draw_string(UiTheme.medium(), Vector2(kr.position.x, kr.end.y - 4), "E", HORIZONTAL_ALIGNMENT_CENTER, kr.size.x, 13, UiTheme.INK)
		draw_string(UiTheme.body(), Vector2(x + 26, r.position.y + 65), "ลงรถ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)


## A petrol pump, or a battery for the electric one (drawn: the font has no such signs).
func _tank_icon(p: Vector2, c: Color) -> void:
	if electric:
		draw_rect(Rect2(p + Vector2(0, 2), Vector2(14, 9)), c, false, 1.5)
		draw_rect(Rect2(p + Vector2(14, 4.5), Vector2(2, 4)), c)
		draw_rect(Rect2(p + Vector2(2.5, 4.5), Vector2(6, 4)), c)
	else:
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(8, 11)), c)
		draw_rect(Rect2(p + Vector2(2.5, 2.5), Vector2(5, 3)), Color(0.04, 0.045, 0.05, c.a))
		draw_line(p + Vector2(9, 3), p + Vector2(12, 5), c, 1.2)
		draw_line(p + Vector2(12, 5), p + Vector2(12, 10), c, 1.2)
