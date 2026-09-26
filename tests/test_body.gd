extends "res://tests/test_base.gd"
## Wounds: a bite leaves one where it landed (a bruise if clothes stopped it),
## it bleeds until bandaged (or stops on its own after a while), an open bite
## can fester later (a fever, not the zombie infection; antibiotics clear it),
## bandages go on one wound at a time, things heal (faster asleep), a bitten
## arm swings slower and a bitten leg walks slower, a sprain stops you
## running, you mend slowly when fed, and wounds are saved.


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

	# An open bite can fester long after it happened: a fever, not the zombie infection.
	me.wounds.clear()
	me.infection = 0.0
	var sore := Body.add(me, "bite", "hands")
	seed(7)
	for i in 1200:
		Body.tick(me, 1.0)
		if sore.get("festering", false):
			break
	check(sore.get("festering", false), "an open bite left alone festers in the end")
	check(me.infection == 0.0, "that's a fever, not the zombie infection (you won't turn from it)")
	check(Body.statuses(me).any(func(st): return st.icon == "fever"), "and shows as a fever")
	var hp0 := me.hp
	simulate(5.0)
	check(me.hp < hp0, "a fever slowly costs health")
	me.inv.fill(null)
	main.inventory._give(me, "antibiotic")
	me.sel = 0
	main.inventory._use_selected(me)
	check(not Body.fevered(me.wounds), "antibiotics clear it")

	# A bleeding bite left alone stops in the end.
	me.wounds.clear()
	var gush := Body.add(me, "bite", "legs", true)
	for i in int(Body.CLOT) + 2:
		Body.tick(me, 1.0)
	check(not gush.bleeding and not me.bleeding and me.wounds.has(gush), "a bleeding bite stops on its own after a while (the wound stays open)")

	# Where a bite is matters: an arm swings slower, a leg walks slower.
	me.wounds.clear()
	var cd0: float = Combat.next_swing(me).stats[2]
	var walk0 := me.speed_mult()
	Body.add(me, "bite", "arms")
	Body.add(me, "bite", "legs")
	check(Combat.next_swing(me).stats[2] > cd0 * 1.1, "a bitten arm swings slower (%.2f -> %.2f)" % [cd0, Combat.next_swing(me).stats[2]])
	check(me.speed_mult() < walk0 * 0.95, "a bitten leg walks slower")
	for w in me.wounds:
		w.bandaged = true
	check(Combat.next_swing(me).stats[2] < cd0 * 1.15, "less so once bandaged")

	# Fed, watered and whole, you mend slowly while awake (up to a point).
	me.wounds.clear()
	me.bleeding = false
	me.infection = 0.0
	me.hunger = 90.0
	me.thirst = 90.0
	me.hp = 30.0
	simulate(20.0)
	check(me.hp > 30.5 and me.hp <= Survival.REST_HEAL_UP_TO, "you mend slowly when fed and whole (%.1f)" % me.hp)
	me.hp = 100.0

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
