extends "res://tests/test_base.gd"
## Things with a state: taps run dry, radios draw zombies, vending machines
## break open. And the system under them: E finds them, states are saved and
## sent to players who join later.


func _first(kind: String) -> Dictionary:
	for th in main.world.things:
		if th.kind == kind:
			return th
	return {}


func _stand_by(th: Dictionary) -> void:
	# Beside it, on the same side (inside the same building for indoor things).
	var w: World = main.world
	for d in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		var c: Vector2i = th.cell + d
		if not w.is_solid(c) and w.building_at.get(c) == w.building_at.get(th.cell):
			me.position = w.to_pos(c)
			me.aim = w.to_pos(th.cell) - me.position
			var tt := Interact.target(main, me)
			if tt.get("kind") == "thing" and tt.id == th.id:
				return  # (not a side where stairs or a cupboard are nearer)


## A free cell a few steps from a thing, in the same building, away from me.
func _near(th: Dictionary) -> Vector2:
	var w: World = main.world
	for r in range(3, 0, -1):
		for d in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
			var c: Vector2i = th.cell + d
			if not w.is_solid(c) and w.building_at.get(c) == w.building_at.get(th.cell) and w.to_pos(c) != me.position:
				return w.to_pos(c)
	return w.to_pos(th.cell) + Vector2(70, 0)


func run() -> void:
	SaveGame.wipe()
	seed(6649746)  # always the same city, one with every kind of thing (some cities have no radio)
	await host(9350)
	var w: World = main.world
	var counts := {}
	for th in w.things:
		counts[th.kind] = counts.get(th.kind, 0) + 1
	for k in ["tap", "radio", "vending"]:
		check(counts.get(k, 0) > 0, "the city has %ss (%d)" % [k, counts.get(k, 0)])
	check(w.thing_nodes.size() == w.things.size(), "each thing is drawn")

	# A tap: E finds it, it slakes thirst, it runs dry.
	var tap := _first("tap")
	_stand_by(tap)
	var t := Interact.target(main, me)
	check(t.get("kind") == "thing" and t.get("id") == tap.id, "E points at the tap (%s)" % t.get("title", "nothing"))
	me.thirst = 20.0
	main.actions.req_interact()
	check(me.thirst > 50.0, "drinking from it helps (%.0f)" % me.thirst)
	check(tap.state.water == Things.DEFS.tap.state.water - 1, "and uses up some of the city water")
	for i in 20:
		me.thirst = 20.0
		main.things.act(me, tap.id, "drink")
	check(tap.state.water == 0, "until it runs dry")
	me.thirst = 20.0
	main.things.act(me, tap.id, "drink")
	check(me.thirst == 20.0, "a dry tap gives nothing")
	check(Things.title_of(tap).contains("แห้ง"), "and says it is dry")

	# A radio: on, and it calls zombies to it.
	var radio := _first("radio")
	_stand_by(radio)
	main.things.act(me, radio.id, "toggle")
	check(radio.state.on, "the radio switches on")
	var z := zombie_at(_near(radio))
	simulate(6.0)
	check(z.investigate_t > 0.0 or z.target != null, "a playing radio draws a zombie to look")

	# A vending machine: smash it, drinks fall out, it stays broken.
	var vend := _first("vending")
	_stand_by(vend)
	var before: int = main.pickups.size()
	main.things.act(me, vend.id, "smash")
	check(vend.state.broken and main.pickups.size() > before, "smashing a vending machine drops drinks (%d)" % (main.pickups.size() - before))
	var again: int = main.pickups.size()
	main.things.act(me, vend.id, "smash")
	check(main.pickups.size() == again, "a broken one cannot be smashed again")

	# Only what changed is kept, and it survives a save.
	var ch: Dictionary = main.things.changed()
	check(ch.size() == 3 and ch.has(tap.id) and ch.has(radio.id) and ch.has(vend.id), "only the three changed things are saved (%d)" % ch.size())
	var ids := [tap.id, radio.id, vend.id]
	main._save_all()
	await close_game()
	await host(9351, true, false)
	var back: Array = main.world.things
	check(back[ids[0]].state.water == 0, "the dry tap is still dry after loading")
	check(back[ids[1]].state.on, "the radio is still on")
	check(back[ids[2]].state.broken, "the vending machine is still broken")

	# Someone joining later is sent the same states.
	var fresh: Dictionary = back[ids[1]].duplicate(true)
	fresh.state = Things.DEFS.radio.state.duplicate()
	main.world.things[ids[1]].state = fresh.state
	main.things.things_sync(main.things.changed().merged({ids[1]: {on = true}}))
	check(main.world.things[ids[1]].state.on, "a sync puts the states back on a client")
	SaveGame.wipe()
