extends "res://tests/test_base.gd"
## Up on a car: E climbs (a moment, walking stops it); zombies can't bite you
## up there but gather and bang on it, which can set its alarm off; you get
## your breath back; a step jumps you down clear of it.


func run() -> void:
	SaveGame.wipe()
	seed(12)
	await host(9490)
	main.spawn_timer = 1e9
	for z in main.zombies.values():
		z.queue_free()
	main.zombies.clear()
	var w: World = main.world
	# The nearest car you can climb, standing somewhere free beside it.
	var car := {}
	var best := INF
	for rec in w.street_props:
		if rec.kind in ["car", "taxi"] and rec.get("horizontal", false):
			var d: float = StreetProp.middle(rec).distance_to(me.position)
			if d < best and w.can_stand(StreetProp.middle(rec) + Vector2(0, 26), Player.RADIUS):
				best = d
				car = rec
	check(not car.is_empty(), "there are cars to climb")
	me.position = StreetProp.middle(car) + Vector2(0, 26)
	var t := {kind = "car", id = car.id, pos = StreetProp.middle(car)}
	check(Interact.actions(main, me, t).any(func(a): return a.verb == "climb" and a.ok), "E at a car offers to climb it")
	main.actions._do_action(me, t, "climb")
	check(me.on_car < 0 and not me.craft.is_empty(), "climbing takes a moment")
	simulate(Actions.CLIMB_TIME + 0.2)
	check(me.on_car == car.id, "then you're up on the roof")
	check(me.position == StreetProp.roof_spot(car)[0], "standing on it")

	# Zombies can't get at you, but they gather and bang on it.
	var spot := me.position + Vector2(0, 30)
	for off in [Vector2(0, 30), Vector2(-30, 14), Vector2(30, 14), Vector2(-40, 4), Vector2(40, 4), Vector2(0, 44)]:
		if w.can_stand(me.position + off, Zombie.RADIUS + 1.0):
			spot = me.position + off
			break
	var z := zombie_at(spot)
	z.facing = (me.position - z.position).angle()
	var hp0 := me.hp
	simulate(4.0)
	check(me.hp == hp0, "a zombie can't bite you up on a car")
	check(z.target == me and z.position.distance_to(me.position) < 24.0, "but it comes and stands at the car")
	z.queue_free()
	main.zombies.erase(z.zid)

	# You get your breath back up there.
	me.stamina = 20.0
	simulate(1.0)
	var up_gain := me.stamina - 20.0

	# A zombie banging on a car can set its alarm off, and the whole street hears.
	var far := zombie_at(StreetProp.middle(car) + Vector2(0, 300))
	for i in 60:
		main.actions.bang_car(car.id, StreetProp.middle(car))
	check(main.actions.alarms.has(car.id), "banging on a car can set its alarm off")
	far.target = null
	far.investigate_t = 0.0
	simulate(1.2)
	check(far.investigate_t > 0.0, "and it draws zombies from down the street")
	main.actions.alarms.clear()
	far.queue_free()
	main.zombies.erase(far.zid)

	# A step off the roof jumps you down, clear of the car.
	me.move = Vector2.DOWN
	simulate(0.6)
	me.move = Vector2.ZERO
	check(me.on_car == -1 and w.can_stand(me.position, Player.RADIUS), "a step jumps you down, clear of it")
	me.stamina = 20.0
	simulate(1.0)
	check(up_gain > (me.stamina - 20.0) * 1.3, "you got your breath back faster up there (%.0f vs %.0f)" % [up_gain, me.stamina - 20.0])
