extends "res://tests/test_base.gd"
## Car trial (not a test, not in run_all): drive a car drawn at any heading
## (CarArt) round the real Victory Monument city, to see how it looks and
## feels before building cars into the game.
##
##   godot --path . -s res://tests/carlab.gd              drive: W/S, A/D, H lights, 1-4 colour
##   godot --path . -s res://tests/carlab.gd -- --shots=DIR   pictures at 8 headings into DIR

const TOP := 190.0  # px a second forward (~43 km/h)
const BACK := 60.0
const ACCEL := 110.0
const BRAKE := 260.0
const COLOURS := [Color("b8302a"), Color("e8e4dc"), Color("2a62a8"), Color("e0c030")]


class Car extends Node2D:
	var heading := 0.0
	var spec: Dictionary = CarArt.SEDAN.duplicate()
	var lights := false

	func _draw() -> void:
		CarArt.draw(self, heading, spec, Vector2.ZERO, lights)


var car: Car
var speed := 0.0


func _blocked(pos: Vector2, heading: float) -> bool:
	var w: World = main.world
	var fwd := Vector2.from_angle(heading)
	var right := fwd.orthogonal()
	var h: float = car.spec.len * 0.5
	var hw: float = car.spec.wid * 0.5
	for c in [Vector2(h, hw), Vector2(h, -hw), Vector2(-h, hw), Vector2(-h, -hw), Vector2(h, 0), Vector2(-h, 0), Vector2(0, hw), Vector2(0, -hw)]:
		var p: Vector2 = pos + fwd * c.x + right * c.y
		var cell := w.to_cell(p)
		if not w.in_bounds(cell) or w.is_solid(cell) or w._in_vehicle(cell, p).has_area():
			return true
	return false


func run() -> void:
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	await host(9431)
	main.spawn_timer = 1e9
	me.god = true
	var w: World = main.world
	car = Car.new()
	car.z_index = 1
	car.position = w.to_pos(Vector2i(120, 156))  # on Ratchawithi, west of the roundabout
	for sp in w.street_props:
		if sp.kind == "car" and sp.get("horizontal", true) and w.get_tile(w.to_cell(sp.pos)) == World.ROAD:
			car.position = sp.pos + Vector2(0, 40)  # (beside a parked one, to compare)
			break
	main.add_child(car)
	main.time = 0.42
	if shots != "":
		await _shots(shots)
		await _shots(shots + "/play", 2.0)
		quit(0)
		return
	while true:
		await process_frame
		_drive(main.get_process_delta_time())


func _drive(delta: float) -> void:
	var go := (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
	var steer := (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	if Input.is_key_pressed(KEY_H) and Engine.get_process_frames() % 20 == 0:
		car.lights = not car.lights
	for i in 4:
		if Input.is_key_pressed(KEY_1 + i):
			car.spec.col = COLOURS[i]
	var want := go * (TOP if go > 0.0 else BACK)
	var rate := ACCEL if signf(want) == signf(speed) and absf(want) > absf(speed) else BRAKE
	speed = move_toward(speed, want, rate * delta)
	# A car turns round its back wheels: tighter the slower it goes, never on the spot.
	var turn: float = steer * speed / (car.spec.len * 0.9) * delta
	var heading: float = car.heading + turn
	var pos := car.position + Vector2.from_angle(heading) * speed * delta
	if _blocked(pos, heading):
		if absf(speed) > 60.0:
			main.shake = maxf(main.shake, absf(speed) / 40.0)
		speed *= -0.25  # (a bump: it bounces back a little)
	else:
		car.heading = heading
		car.position = pos
	car.queue_redraw()
	me.position = car.position  # (the city streams in round you; you're in the car)
	me.visible = false


func _shots(dir: String, zoom := 4.0) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	me.visible = false
	main.play_zoom = Vector2(zoom, zoom)
	for i in 8:
		car.heading = i * TAU / 8.0
		car.queue_redraw()
		me.position = car.position
		for k in 40:
			await process_frame
		get_root().get_viewport().get_texture().get_image().save_png("%s/car_%d.png" % [dir, i * 45])
