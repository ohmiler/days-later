extends "res://tests/test_base.gd"
## Throwing (T): a bottle or a can flies toward the cursor, stops at a wall,
## and where it lands a zombie that hasn't seen you goes to look. Glass
## smashes and is gone; a can lies there to be picked up again. Drinking an
## energy drink leaves its empty bottle.


func run() -> void:
	SaveGame.wipe()
	seed(12)
	await host(9506)
	main.spawn_timer = 1e9
	var w: World = main.world

	# Somewhere with open ground to the right.
	var start := me.position
	for y in range(20, W_H()):
		for x in range(20, W_W() - 60):
			var c := Vector2i(x, y)
			var open := true
			for dx in 45:
				if not w.can_stand(w.to_pos(c + Vector2i(dx, 0)), Player.RADIUS):
					open = false
					break
			if open:
				start = w.to_pos(c)
				break
		if start != me.position:
			break
	me.position = start

	check(Combat.throw_slot(me) < 0, "with nothing to throw, T finds nothing")
	main.inventory._give(me, "bottle")
	main.inventory._give(me, "can")
	check(Combat.throw_slot(me) >= 0, "a bottle or a can can be thrown")

	# A zombie off to the side, not after anyone.
	var z := zombie_at(start + Vector2(120, 60))
	z.target = null
	me.aim = Vector2(120, 0)
	var sta := me.stamina
	main.combat.req_throw()
	check(count(me, "bottle") == 0, "the bottle leaves your hand")
	check(me.stamina < sta, "throwing takes a little breath")
	check(main.combat.throws.size() == 1, "it's in the air")
	var pickups_before: int = main.pickups.size()
	simulate(1.0)
	check(main.combat.throws.is_empty(), "and comes down")
	check(z.investigate.distance_to(start + Vector2(120, 0)) < 20.0 and z.investigate_t > 0.0,
			"a zombie nearby goes to see what smashed (%s)" % z.investigate)
	check(main.pickups.size() == pickups_before, "a bottle smashes: nothing left to pick up")

	# A can clatters and stays; it can be picked up again.
	me.shoot_cd = 0.0
	me.aim = Vector2(80, 0)
	main.combat.req_throw()
	simulate(1.0)
	await frames(1)
	var landed := false
	for pid in main.pickups:
		if main.pickups[pid].item.id == "can" and main.pickups[pid].pos.distance_to(start + Vector2(80, 0)) < 6.0:
			landed = true
	check(landed, "a can lands where it was thrown, to pick up again")

	# Not through walls, and no farther than an arm can throw.
	main.inventory._give(me, "can")
	me.shoot_cd = 0.0
	me.aim = Vector2(1000, 0)
	main.combat.req_throw()
	var th: Dictionary = main.combat.throws[-1]
	check(th.at.distance_to(start) <= Combat.THROW_RANGE + 0.5, "it goes %d px at most (%.0f)" % [Combat.THROW_RANGE, th.at.distance_to(start)])
	var wall_dir := Vector2.ZERO
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		if w.ray_length(start, d, Combat.THROW_RANGE) < Combat.THROW_RANGE - 20.0:
			wall_dir = d
	if wall_dir != Vector2.ZERO:
		main.inventory._give(me, "can")
		me.shoot_cd = 0.0
		me.aim = wall_dir * 400.0
		main.combat.req_throw()
		th = main.combat.throws[-1]
		check(th.at.distance_to(start) < w.ray_length(start, wall_dir, Combat.THROW_RANGE), "a wall stops it")

	# An energy drink leaves its empty bottle.
	main.inventory._give(me, "energy")
	for i in me.inv.size():
		if me.inv[i] != null and me.inv[i].id == "energy":
			me.sel = i
	main.inventory._use_selected(me)
	check(count(me, "bottle") == 1, "drink the energy drink, keep the bottle")

	await close_game()


func W_W() -> int:
	return World.W


func W_H() -> int:
	return World.H
