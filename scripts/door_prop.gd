class_name DoorProp
extends Node2D
## A shop door in its doorway: open, shut, boarded up or smashed in.
## Origin is the bottom-left of the doorway cell.

var door: Dictionary


func _draw() -> void:
	var T := World.TILE
	var wood := Color("7a5634")
	if door.broken:
		# Splintered frame and a few boards hanging off.
		for i in 3:
			var x := 1.0 + i * 5.0
			draw_colored_polygon(PackedVector2Array([Vector2(x, -2), Vector2(x + 3, -2), Vector2(x + 1.5, -6 - i * 2)]), wood.darkened(0.2))
		draw_line(Vector2(1, -14), Vector2(6, -11), wood, 1.5)
		return
	if not door.closed:
		# Swung inward: just its edge against the side of the frame.
		draw_rect(Rect2(1, -15, 2.5, 15), wood.darkened(0.35))
		draw_rect(Rect2(1, -15, 2.5, 1), wood.lightened(0.1))
	else:
		var r := Rect2(1, -15, T - 2, 15)
		draw_rect(r, wood)
		draw_rect(Rect2(2.5, -13.5, T - 5, 5.5), wood.darkened(0.12))  # panels
		draw_rect(Rect2(2.5, -7, T - 5, 5.5), wood.darkened(0.12))
		draw_circle(Vector2(T - 4, -7.5), 0.8, Color("c8b070"))  # handle
		var dmg: float = 1.0 - door.hp / (World.DOOR_HP + door.boards * World.BOARD_HP)
		if dmg > 0.35:
			draw_line(Vector2(4, -13), Vector2(8, -8), Color(0, 0, 0, 0.5), 0.6)
		if dmg > 0.65:
			draw_line(Vector2(11, -3), Vector2(7, -9), Color(0, 0, 0, 0.5), 0.6)
	for i in door.boards:
		# Boards nailed across the doorway.
		var y: float = -12.0 + i * 4.5
		var tilt := 1.5 if i % 2 == 0 else -1.5
		draw_line(Vector2(-1, y - tilt), Vector2(T + 1, y + tilt), Color("a8885a"), 3.0)
		draw_line(Vector2(-1, y - tilt - 1), Vector2(T + 1, y + tilt - 1), Color("c8a878"), 0.6)
		draw_circle(Vector2(0.5, y - tilt), 0.5, Color("6a6a6a"))
		draw_circle(Vector2(T - 0.5, y + tilt), 0.5, Color("6a6a6a"))
