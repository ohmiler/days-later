extends "res://tests/test_base.gd"
## Wounds: a bite leaves one where it landed (a bruise if clothes stopped it),
## it bleeds until bandaged, an open bite can turn bad later, bandages go on one
## wound at a time, things heal (faster asleep), a sprain stops you running,
## and wounds are saved.


func _bandage_slot() -> void:
	me.inv.fill(null)
	main.inventory._give(me, "bandage")
	main.inventory._give(me, "bandage")
	me.sel = 0


func run() -> void:
	SaveGame.wipe()
	await host(9410)
	me.wounds.clear()

	# A bite on a bare arm leaves a bite there; the vest turns most body bites into bruises.
	me.bite(10.0, "arms")
	simulate(0.1)
	check(me.wounds.size() == 1 and me.wounds[0].kind == "bite" and me.wounds[0].part == "arms", "a bite on the arm leaves a bite wound there")
	main.inventory._give(me, "stabvest")
	me.sel = me.inv.find(me.inv.filter(func(x): return x != null and x.id == "stabvest")[0])
	main.inventory._use_selected(me)
	seed(4)
	for i in 12:
		me.bite(1.0, "torso")
		simulate(0.05)
	var bruises := me.wounds.filter(func(w): return w.kind == "bruise").size()
	check(bruises >= 5, "a stab vest turns most bites on the body into bruises (%d of 12)" % bruises)
	me.hp = 100.0

	# Bleeding lasts until the wound is bandaged, and a bandage goes on one wound.
	me.wounds.clear()
	var w1 := Body.add(me, "bite", "arms", true)
	var w2 := Body.add(me, "bite", "legs")
	simulate(0.1)
	check(me.bleeding, "a bleeding bite bleeds")
	_bandage_slot()
	main.inventory._use_selected(me)
	check(w1.bandaged and not w2.bandaged and not me.bleeding, "a bandage goes on the bleeding one first, and stops it")
	main.inventory.req_treat(me.wounds.find(w2))
	check(w2.bandaged and count(me, "bandage") == 0, "the body screen can bandage a chosen wound")

	# An open bite can turn bad long after it happened.
	me.wounds.clear()
	me.infection = 0.0
	Body.add(me, "bite", "hands")
	seed(7)
	for i in 1200:
		Body.tick(me, 1.0)
		if me.infection > 0.0:
			break
	check(me.infection > 0.0, "an open bite left alone gets infected in the end")

	# Healing: bandaged heals, open bites don't close, sleep speeds it up.
	me.infection = 0.0
	me.wounds.clear()
	var open := Body.add(me, "bite", "arms")
	var dressed := Body.add(me, "bite", "arms")
	dressed.bandaged = true
	for i in 130:
		Body.tick(me, 1.0)
	me.sleeping = true
	for i in 90:
		Body.tick(me, 1.0)
	me.sleeping = false
	check(not me.wounds.has(dressed) and me.wounds.has(open), "a bandaged bite heals (sooner asleep); an open one doesn't close")

	# A sprain: no running until it heals.
	me.wounds.clear()
	me.sprint = true
	me.stamina = 100.0
	var fast := me.speed_mult()
	Body.add(me, "sprain", "legs")
	check(me.speed_mult() < fast * 0.6, "a sprained ankle stops you running (%.2f -> %.2f)" % [fast, me.speed_mult()])
	check(Body.statuses(me).any(func(s): return s.icon == "sprain"), "and shows as a status")
	me.sprint = false

	# Where you are: hunted, or safe up top.
	var hunter := zombie_at(me.position + Vector2(60, 0))
	hunter.state = 2
	check(Body.statuses(me)[0].icon == "chased", "a zombie that has seen you shows first")
	hunter.queue_free()
	main.zombies.erase(hunter.zid)
	me.on_roof = true
	check(Body.statuses(me).any(func(st): return st.icon == "safe"), "up on a roof shows as safe")
	me.on_roof = false

	# Saved with you.
	main._save_all()
	await close_game()
	await host(9411, true, false)
	check(me.wounds.size() == 1 and me.wounds[0].kind == "sprain", "wounds come back after a reload")
	SaveGame.wipe()
