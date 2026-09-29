class_name BossBar
extends Control
## A boss's name and health across the top of the screen while it's close and
## in sight (Bosses sets `boss` and `frac`; "" hides it).

const W := 420.0

var boss := ""
var frac := 1.0
var _shown := 0.0  # fades in and out
var _ghost := 1.0  # the chunk just lost, shown a moment in a lighter red


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_shown = move_toward(_shown, 1.0 if boss != "" else 0.0, delta * 4.0)
	_ghost = move_toward(_ghost, frac, delta * 0.5) if _ghost > frac else frac
	if _shown > 0.0:
		queue_redraw()


func _draw() -> void:
	if _shown <= 0.0:
		return
	modulate.a = _shown
	var x := (size.x - W) * 0.5
	var head := UiTheme.heading()
	draw_string(head, Vector2(x, 18), boss, HORIZONTAL_ALIGNMENT_CENTER, W, UiTheme.SIZE_HEADING, UiTheme.TEXT)
	var r := Rect2(x, 28, W, 10)
	UiTheme.meter(self, r, _ghost, UiTheme.DANGER)
	UiTheme.meter(self, r, frac, UiTheme.DANGER_DEEP, Color(0, 0, 0, 0))
