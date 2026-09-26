extends "res://tests/test_base.gd"
## Beds: sleeping heals (faster in a building shut tight), the night passes
## faster when everyone sleeps, zombies wake you, and the bed you claim is
## where you wake after dying, even after a reload.


func _bed() -> FurnitureProp:
	for f: FurnitureProp in main.world.container_nodes:
		if f.data.kind == "bed":
			return f
	return null


## Stand beside the bed, inside, where E points at it.
func _stand_by(f: FurnitureProp) -> void:
	var w: World = main.world
	var up: bool = f.data.get("up", false)  # (bedrooms are upstairs)
	me.up = up
	var cells := [f.data.cell, w.to_cell(f.position - Vector2(0, 4))]  # (a long bed covers two)
	for i in 8:
		var c: Vector2i = cells[i / 4] + [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP][i % 4]
		if not (w.is_solid_up(c) if up else w.is_solid(c)) and w.building_at.get(c) == w.building_at.get(f.data.cell):
			me.position = w.to_pos(c)
			me.aim = f.position - me.position
			var tt := Interact.target(main, me)
			if tt.get("kind") == "container" and tt.id == f.data.id:
				return


func _clear_zombies() -> void:
	for z in main.zombies.values():
		z.queue_free()
	main.zombies.clear()
	main.spawn_timer = 1e9


func _shut(f: FurnitureProp, closed: bool) -> void:
	var w: World = main.world
	var b = w.building_at.get(f.data.cell)
	for d in w.doors:
		if not w.is_built(d.id) and w.building_at.get(d.cell) == b:
			w.set_door(d.id, closed, d.hp, d.boards, false)


func run() -> void:
	SaveGame.wipe()
	seed(5)  # always the same city
	await host(9370)
	_clear_zombies()
	var bed := _bed()
	check(bed != null, "the city has beds")
	_stand_by(bed)
	var t := Interact.target(main, me)
	check(t.get("kind") == "container" and t.id == bed.data.id, "E points at the bed")
	var verbs := Interact.actions(main, me, t).map(func(a): return a.verb)
	check("sleep" in verbs and "claim" in verbs, "a bed can be slept in and claimed (%s)" % [verbs])

	# Asleep in an open house: heals slowly. Shut tight: faster.
	_shut(bed, false)
	me.hp = 40.0
	main.actions.req_act("container", bed.data.id, "sleep")
	check(me.sleeping, "E > sleep lies you down")
	simulate(5.0)
	var open_gain := me.hp - 40.0
	_shut(bed, true)
	check(main.survival.spot_safe(bed.position), "shutting every door and window makes the building safe")
	me.hp = 40.0
	simulate(5.0)
	var shut_gain := me.hp - 40.0
	check(open_gain > 0.0 and shut_gain > open_gain * 2.0, "sleep heals, much faster shut in (%.0f vs %.0f)" % [open_gain, shut_gain])
	check(main.survival.time_speed() > 1.0, "the night runs faster while everyone sleeps")
	var before: float = main.time
	simulate(2.0)
	check(main.time - before > 2.0 * 4.0 / main.DAY_LENGTH, "and the clock shows it")

	# Moving gets you up; a zombie close by wakes you.
	me.move = Vector2.RIGHT
	simulate(0.2)
	check(not me.sleeping and main.survival.time_speed() == 1.0, "moving gets you up, time back to normal")
	me.move = Vector2.ZERO
	_stand_by(bed)
	main.actions.req_act("container", bed.data.id, "sleep")
	var z := zombie_at(me.position + Vector2(50, 0))
	simulate(1.2)
	check(not me.sleeping, "a zombie close by wakes you")
	z.queue_free()
	main.zombies.erase(z.zid)

	# Anywhere: Z lies you down on the spot; a bed is better.
	_stand_by(bed)
	var spot := me.position
	me.hp = 40.0
	main.actions.req_sleep()
	check(me.sleeping and me.position == spot, "Z sleeps right where you stand")
	simulate(5.0)
	var floor_gain := me.hp - 40.0
	check(floor_gain > 0.0 and floor_gain < shut_gain, "the floor heals too, less than a bed (%.0f vs %.0f)" % [floor_gain, shut_gain])
	main.actions.req_sleep()
	check(not me.sleeping, "Z again gets you up")
	# Getting up takes a moment; you lie the way you faced.
	var at := me.position
	me.move = Vector2.RIGHT
	simulate(0.3)
	check(me.position == at and me.getup_t > 0.0, "getting up off the floor takes a moment")
	simulate(1.0)
	check(me.position != at, "then you're off")
	me.move = Vector2.ZERO
	simulate(0.2)
	me.aim = Vector2.LEFT * 30.0
	main.actions.req_sleep()
	check(me.sleeping and me.rest_face == 1, "you lie down the way you face (left)")
	main.actions.req_sleep()
	simulate(1.0)

	# X sits you down on the spot: you get your breath back faster.
	me.stamina = 20.0
	simulate(1.0)
	var standing_gain := me.stamina - 20.0
	main.actions.req_sit()
	check(me.sitting == -2, "X sits you down on the floor")
	me.stamina = 20.0
	simulate(1.0)
	check(me.stamina - 20.0 > standing_gain * 1.5, "sat, you get your breath back faster (%.0f vs %.0f)" % [me.stamina - 20.0, standing_gain])
	main.actions.req_sit()
	check(me.sitting == -1, "X again gets you up")
	simulate(1.0)

	# A sofa, a bench, a stool: E sits you on it.
	var seat := {}
	for d in main.world.decor:
		if d.kind in Interact.SEATS and not d.get("up", false):
			seat = d
			break
	check(not seat.is_empty(), "the city has things to sit on")
	me.up = false
	me.position = main.world.to_pos(seat.cell) + Vector2(0, 12)
	var st := {kind = "seat", id = seat.id, pos = me.position}
	check(Interact.actions(main, me, st).any(func(x): return x.verb == "sit"), "E on a %s offers a seat" % seat.kind)
	main.actions._do_action(me, st, "sit")
	check(me.sitting == seat.id, "and sits you on it")
	me.move = Vector2.DOWN
	simulate(1.2)
	check(me.sitting == -1, "walking gets you up off it")
	me.move = Vector2.ZERO

	# Claimed: dying brings the next survivor back to it, even after a reload.
	_stand_by(bed)
	main.actions.req_act("container", bed.data.id, "claim")
	check(me.bed == bed.data.id, "claiming the bed makes it yours")
	me.take_damage(1000.0)
	simulate(Player.RESPAWN_TIME + 0.5)
	check(me.alive() and me.position.distance_to(bed.position) < 1.0, "after dying you wake at your bed")
	var bed_id: int = bed.data.id
	main._save_all()
	await close_game()
	await host(9371, true, false)
	check(me.bed == bed_id, "the bed is still yours after a reload")
	SaveGame.wipe()
