class_name DoorProp
extends Node2D
## A shop door in its doorway: open, shut, boarded up or smashed in.
## Origin is the bottom-left of the doorway cell.

## Doors and windows are drawn 15 px tall and stretched to BuildingProp.GROUND_H.
const DOOR_STRETCH := 2.0
const WINDOW_STRETCH := 1.8

var door: Dictionary


func _draw() -> void:
	var kind: String = door.get("kind", "door")
	if kind == "window":
		_draw_window()
		return
	if kind == "shutter":
		_draw_shutter()
		return
	if World.BUILDS.has(kind):
		_draw_structure(kind)
		return
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


## One section of a rolling steel shutter (drawn 15 tall, stretched to the storey).
## Up: rolled into its box (the building draws that); down: ribbed steel with
## a padlocked bottom bar; prised: the bottom bent up into a hole to crawl under.
func _draw_shutter() -> void:
	var T := World.TILE
	var steel := Color("8e9092")
	if not door.closed and not door.broken:
		return
	var bottom := -6.0 if door.broken else 0.0
	draw_rect(Rect2(0, -15, T, 15 + bottom), steel)
	for y in range(-14, int(bottom), 1):
		draw_line(Vector2(0, y + 0.5), Vector2(T, y + 0.5), steel.darkened(0.18 if y % 2 else 0.05), 0.4)
	draw_line(Vector2(0, -15), Vector2(0, bottom), Color("5a5c5e"), 0.8)  # the guide rails
	if door.broken:
		# Bent up and out: a jagged lip over a dark gap.
		draw_rect(Rect2(0, -6, T, 6), Color("15120f"))
		draw_colored_polygon(PackedVector2Array([Vector2(1, -6), Vector2(T - 1, -6), Vector2(T - 3, -3.5), Vector2(3, -4)]), steel.darkened(0.3))
		return
	draw_rect(Rect2(0, -1.5, T, 1.5), Color("6a6c6e"))  # bottom bar
	var mid := int(door.cell.x) % 2 == 0
	if mid:
		draw_rect(Rect2(T * 0.5 - 1, -2.5, 2, 2), Color("c8a040"))  # padlock
	var dmg: float = 1.0 - door.hp / World.SHUTTER_HP
	if dmg > 0.3:
		draw_arc(Vector2(T * 0.5, -8), 3.0, 0.3, 2.8, 6, Color(0, 0, 0, 0.35), 0.6)  # dented
	if dmg > 0.65:
		draw_arc(Vector2(T * 0.3, -4), 2.5, -0.5, 2.0, 6, Color(0, 0, 0, 0.4), 0.6)


func _draw_window() -> void:
	var T := World.TILE
	var frame := Color("4a4640")
	var pane := Rect2(1.5, -13, T - 3, 9)
	draw_rect(Rect2(0.5, -14, T - 1, 11), frame)
	if door.broken or not door.closed:
		draw_rect(pane, Color("15120f"))  # dark hole
		for p in [[Vector2(1.5, -13), Vector2(5, -13), Vector2(1.5, -8)], [Vector2(T - 1.5, -13), Vector2(T - 6, -13), Vector2(T - 1.5, -9)],
				[Vector2(1.5, -4), Vector2(4, -4), Vector2(1.5, -7)], [Vector2(T - 1.5, -4), Vector2(T - 5, -4), Vector2(T - 1.5, -6)]]:
			draw_colored_polygon(PackedVector2Array(p), Color(0.7, 0.85, 0.9, 0.6))  # shards left in the frame
	else:
		draw_rect(pane, Color(0.55, 0.7, 0.78, 0.85))
		draw_line(pane.position + Vector2(2, 8), pane.position + Vector2(7, 1), Color(1, 1, 1, 0.35), 1.2)
		draw_line(Vector2(T / 2, -13), Vector2(T / 2, -4), frame, 0.8)
		var dmg: float = 1.0 - door.hp / (World.WINDOW_HP + door.boards * World.BOARD_HP)
		if dmg > 0.3 and door.boards == 0:
			draw_line(Vector2(4, -12), Vector2(9, -6), Color(1, 1, 1, 0.6), 0.5)  # cracked
	draw_rect(Rect2(-0.5, -4, T + 1, 1.5), frame.lightened(0.15))  # sill
	for i in door.boards:
		var y: float = -12.0 + i * 3.5
		draw_line(Vector2(-1, y), Vector2(T + 1, y + (1.2 if i % 2 else -1.2)), Color("a8885a"), 2.6)
		draw_line(Vector2(-1, y - 1), Vector2(T + 1, y - 1 + (1.2 if i % 2 else -1.2)), Color("c8a878"), 0.5)


func _draw_structure(kind: String) -> void:
	var T := World.TILE
	var wood := Color("9a7650")
	if door.broken and door.hp < 0.0:
		return  # someone picked it back up
	if door.broken:
		for i in 4:  # wreckage
			var x := 2.0 + i * 3.5
			draw_line(Vector2(x, -1), Vector2(x + 3, -3 - (i % 2) * 2), wood.darkened(0.3), 1.2)
		return
	match kind:
		"wire":
			for i in 3:
				var x := 3.0 + i * 5.0
				draw_set_transform(Vector2(x, -4), 0, Vector2(1, 0.8))
				draw_arc(Vector2.ZERO, 3.2, 0, TAU, 12, Color("8a8e90"), 0.6)
				draw_set_transform(Vector2.ZERO)
				for k in 4:  # barbs
					var a := k * TAU / 4 + i
					var p := Vector2(x, -4) + Vector2.from_angle(a) * Vector2(3.2, 2.6)
					draw_line(p, p + Vector2.from_angle(a + 0.8) * 1.2, Color("6a6e70"), 0.5)
			draw_line(Vector2(0, -1), Vector2(0, -8), wood.darkened(0.2), 1.2)
			draw_line(Vector2(T, -1), Vector2(T, -8), wood.darkened(0.2), 1.2)
		"spikes":
			draw_rect(Rect2(1, -6, T - 2, 5), wood.darkened(0.2))
			draw_rect(Rect2(1, -6, T - 2, 1), wood)
			for i in 6:
				var p := Vector2(3 + (i % 3) * 5, -5 + (i / 3) * 2.5)
				draw_line(p, p + Vector2(0.3, -2.5), Color("b8bcc0"), 0.5)
