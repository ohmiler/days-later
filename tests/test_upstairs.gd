extends "res://tests/test_base.gd"
## Upstairs in a shophouse: the stairs go up to the floor with the bedrooms
## and on up to the roof; up there you walk on its floor, not the one below;
## a zombie below can't reach you, but one that saw you go up follows you up
## the stairs; what you drop up there stays up there.


func _clear_zombies() -> void:
	for z in main.zombies.values():
		z.queue_free()
	main.zombies.clear()
	main.spawn_timer = 1e9


func _verbs(t: Dictionary) -> Array:
	return Interact.actions(main, me, t).map(func(a): return a.verb)


func run() -> void:
	SaveGame.wipe()
	seed(8)
	await host(9460)
	_clear_zombies()
	var w: World = main.world
	var b: Dictionary = {}
	for rec in w.buildings:
		if rec.get("upper", false) and rec.has("stairs"):
			b = rec
			break
	check(not b.is_empty(), "shophouses have a floor upstairs")
	var st: Vector2i = b.stairs
	var at := w.to_pos(st)
	check(w.upper.get(st) == World.FLOOR, "the stairs come up onto its floor")
	var beds := w.containers.filter(func(f): return f.get("up", false) and f.kind == "bed" and b.rect.has_point(f.cell))
	check(not beds.is_empty(), "the bedrooms are up there (%d beds)" % beds.size())

	# Up the stairs.
	for d in w.doors:
		if w.building_at.get(d.cell) and w.building_at[d.cell].data == b:
			w.set_door(d.id, true, d.hp, d.boards, false)  # (shut in, so nothing wanders in)
	me.position = at
	var t := {kind = "stairs", id = st, pos = at}
	check("up" in _verbs(t), "at the stairs, E goes up")
	main.actions._do_action(me, t, "up")
	check(me.up and not me.on_roof, "to the floor upstairs, not the roof")
	await frames(30)
	check(me.lift > BuildingProp.GROUND_H * 0.8, "drawn a storey up (%.0f)" % me.lift)

	# Walking up there goes by its walls, not the ones below.
	var start := me.position
	me.move = Vector2.UP
	simulate(1.5)
	me.move = Vector2.ZERO
	var c := w.to_cell(me.position)
	check(me.position != start and w.upper.get(c) == World.FLOOR, "you walk on the floor up there")
	me.move = Vector2.UP
	simulate(2.0)
	me.move = Vector2.ZERO
	check(b.rect.has_point(w.to_cell(me.position)), "and its walls keep you in (%s)" % w.to_cell(me.position))

	# A zombie right below you can't get at you.
	me.position = at
	var below := zombie_at(at + Vector2(6, 0))
	below.up = false
	var hp0 := me.hp
	simulate(1.5)
	check(me.hp == hp0, "a zombie on the floor below can't bite you")
	below.queue_free()
	main.zombies.erase(below.zid)

	# What you drop up here stays up here.
	me.inv.fill(null)
	main.inventory._give(me, "rag")
	me.sel = 0
	main.inventory.req_drop()
	var dropped: Array = main.pickups.values().filter(func(pu): return pu.item.id == "rag")
	check(dropped.size() == 1 and dropped[0].up, "a thing dropped upstairs lies upstairs")

	# Up to the roof and back down to the floor upstairs.
	main.actions._do_action(me, t, "up")
	check(me.on_roof and not me.up, "on up the stairs to the roof")
	main.actions._do_action(me, t, "down")
	check(me.up and not me.on_roof, "down from the roof to the floor upstairs")
	main.actions._do_action(me, t, "down")
	check(not me.up and not me.on_roof, "and down again to the ground floor")

	# A zombie that sees you go up comes up the stairs after you.
	for d in w.doors:
		if w.building_at.get(d.cell) and w.building_at[d.cell].data == b:
			w.set_door(d.id, false, d.hp, d.boards, false)
	var z := zombie_at(at + Vector2(0, 40))
	if not w.can_stand(z.position, Zombie.RADIUS):
		z.position = at + Vector2(0, 24)
	z.facing = (at - z.position).angle()
	me.position = at
	simulate(0.8)
	check(z.target == me, "the zombie has seen you")
	main.actions._do_action(me, t, "up")
	me.position = at + Vector2(0, -20) if not w.is_solid_up(st + Vector2i.UP) else at
	simulate(5.0)
	check(z.up, "it comes up the stairs after you")
	check(z.position.distance_to(me.position) < 24.0 or me.hp < Player.MAX_HP, "and finds you up there")
