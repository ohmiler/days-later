extends "res://tests/test_base.gd"
## The trial car (Vehicles, CarArt): the admin menu makes one, E gets you in,
## it drives round toward where you steer, backs up, stops at walls, and you
## get out beside a door.


func run() -> void:
	SaveGame.wipe()
	await host(9379)
	main.spawn_timer = 1e9
	var w: World = main.world
	# Somewhere on a wide street with a clear run east.
	var at := Vector2.ZERO
	for y in range(154, 166):
		for x in range(20, 140, 4):
			var p := w.to_pos(Vector2i(x, y))
			if range(0, 300, 12).all(func(dx): return not Vehicles.car_blocked(w, p + Vector2(dx, 0), 0.0, CarArt.SEDAN)):
				at = p
				break
		if at != Vector2.ZERO:
			break
	check(at != Vector2.ZERO, "found a clear run of street")
	me.position = at + Vector2(0, 24)
	me.aim = Vector2(0, -30)
	var n0 := w.vehicles.size()
	main.admin.req_car()
	check(w.vehicles.size() == n0 + 1 and Vehicles.is_car(w.vehicles[-1]), "the admin menu makes a car")
	var v: Dictionary = w.vehicles[-1]
	v.pos = at
	v.dir = 0.0
	Vehicles._place(v)
	check(not Vehicles.car_blocked(w, v.pos, v.dir, CarArt.SEDAN), "it stands clear on the street")
	me.position = at + Vector2(0, 24)
	var acts: Array = main.vehicles.actions_for(me, v.id)
	check(acts[0].verb == "ride" and acts[0].ok and acts[0].label == "ขับ", "E by it: drive (%s)" % acts[0].label)
	main.actions.req_act("vehicle", v.id, "ride")
	check(me.riding == v.id and v.rider == me.peer_id, "and you're in")

	# Drive east: it goes, the way it faces.
	me.move = Vector2.RIGHT
	simulate(1.5)
	check(v.pos.x > at.x + 60.0 and absf(wrapf(v.dir, -PI, PI)) < 0.1, "holding right, it drives east (%.0f px)" % (v.pos.x - at.x))
	# Steer down: it swings round, never on the spot.
	var d0: float = v.dir
	me.move = Vector2.DOWN
	simulate(0.1)
	check(v.dir > d0 and v.dir - d0 < PI * 0.5, "steering down, it starts to turn (%.2f rad)" % (v.dir - d0))
	# Stopped, holding the way behind: it backs up.
	me.move = Vector2.ZERO
	simulate(3.0)
	v.dir = 0.0
	var x0: float = v.pos.x
	me.move = Vector2.LEFT
	simulate(1.0)
	check(v.pos.x < x0 - 5.0 and absf(wrapf(v.dir, -PI, PI)) < 0.3, "holding the way behind, it backs up (%.0f px)" % (v.pos.x - x0))
	# Into a wall: it stops there.
	me.move = Vector2.ZERO
	simulate(2.0)
	v.dir = -PI * 0.5
	me.move = Vector2.UP
	simulate(8.0)
	check(not Vehicles.car_blocked(w, v.pos, v.dir, CarArt.SEDAN), "driving north it stops at whatever is in the way, not through it")
	# Out beside a door.
	me.move = Vector2.ZERO
	simulate(2.0)
	main.vehicles.dismount(me)
	check(me.riding == -1 and me.position.distance_to(v.pos) < 40.0 and w.can_stand(me.position, Player.RADIUS), "out again, beside it")
