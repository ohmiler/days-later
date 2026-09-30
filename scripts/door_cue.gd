class_name DoorCue
extends Node2D
## The way in of a shop whose front is turned away from us (north) or edge on
## (east, west), where the camera shows no door: a frame at the roof's edge
## where the doorway is, and a hanging เปิด / ปิด board that says what state
## it is in (the way Thai shops hang one). Origin: the doorway's middle on the
## roof's edge; `facing` is which way the front looks.

var door: Dictionary
var facing := "n"
var show_board := false  # (one board on a front, not one per shutter section)
var _sig := -1

const OPEN := Color("3f9a4a")
const SHUT := Color("b8342c")
const BROKEN := Color("d8842a")


func _ready() -> void:
	z_index = 3
	set_process(true)


func _process(_delta: float) -> void:
	var s := (1 if door.get("closed", false) else 0) + (2 if door.get("broken", false) else 0) + 4 * int(door.get("boards", 0))
	if s != _sig:
		_sig = s
		queue_redraw()


func _draw() -> void:
	var T := World.TILE
	var broken: bool = door.get("broken", false)
	var closed: bool = door.get("closed", false)
	var col := BROKEN if broken else (SHUT if closed else OPEN)
	var word := "พัง" if broken else ("ปิด" if closed else "เปิด")
	var dark := Color("2a2622")
	var board: Rect2
	match facing:
		"n":
			# A doorframe notched into the roof's near edge, the board hung in it.
			draw_rect(Rect2(-T * 0.5, -1, T, 4), dark)
			draw_rect(Rect2(-T * 0.5, 3, T, 1.2), col)
			board = Rect2(-7, 5, 14, 7)
			draw_line(Vector2(-4, 3), Vector2(-4, 5), Color("5a5c5e"), 0.6)
			draw_line(Vector2(4, 3), Vector2(4, 5), Color("5a5c5e"), 0.6)
		"e", "w":
			var out := 1.0 if facing == "e" else -1.0
			# A frame standing out of the side wall, the board hung from it.
			draw_rect(Rect2(out * 0.5 - (3.0 if out < 0 else 0.0), -T * 0.5, 3, T), dark)
			draw_rect(Rect2(out * 3.5 - (1.2 if out < 0 else 0.0), -T * 0.5, 1.2, T), col)
			var bx := 6.0 * out
			board = Rect2(bx - (14.0 if out < 0 else 0.0), -3.5, 14, 7)
	if not show_board:
		return
	draw_rect(board, col)
	draw_rect(board, dark, false, 0.6)
	if int(door.get("boards", 0)) > 0:
		draw_line(board.position, board.end, Color("a8885a"), 1.2)
		draw_line(Vector2(board.position.x, board.end.y), Vector2(board.end.x, board.position.y), Color("a8885a"), 1.2)
	draw_string(Look.thai_font(), Vector2(board.position.x, board.position.y + 5.6), word, HORIZONTAL_ALIGNMENT_CENTER, board.size.x, 5, Color.WHITE)
