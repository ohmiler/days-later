extends "res://tests/test_base.gd"
## Zombie behaviour: telegraphed bites, interrupting them, armour, chasing.


func run() -> void:
	await host(9302)
	var home := me.position
	me.hp = 100.0

	# The lunge: nothing for the wind-up, then one bite.
	var z := zombie_at(home + Vector2(10, 0))
	simulate(0.2)
	check(z.lunge_t > 0.0 and me.hp == 100.0, "winding up, not bitten yet")
	simulate(0.4)
	check(me.hp < 100.0, "bitten after the wind-up (hp %.0f)" % me.hp)

	# A hit during the wind-up cancels the bite. (Clear any bleeding from the
	# first bite, or it would keep taking health on its own.)
	me.bleeding = false
	me.infection = 0.0
	me.hp = 100.0
	z.attack_cd = 0.0
	z.lunge_t = 0.0
	simulate(0.1)
	check(z.lunge_t > 0.0, "a new lunge starts")
	z.stun = 0.4
	simulate(0.6)
	check(me.hp == 100.0, "hitting it mid wind-up stops the bite")

	# Armour soaks up bites.
	for id in ["vest", "helmet"]:
		main._give(me, id)
		me.sel = me.inv.find(me.inv.filter(func(x): return x != null and x.id == id)[0])
		main._use_selected(me)
	check(me.armor() > 0.3, "wearing vest and helmet (armor %.2f)" % me.armor())
	me.hp = 100.0
	me.bite(20.0)
	check(me.hp > 80.0 and me.hp < 100.0, "a 20 bite does less through armour (hp %.1f)" % me.hp)

	# It comes for you from across the street.
	z.queue_free()
	main.zombies.erase(z.zid)
	var far := zombie_at(home + Vector2(90, 0))
	var d0 := far.position.distance_to(me.position)
	simulate(2.0)
	check(far.position.distance_to(me.position) < d0 - 20.0, "a zombie that sees you closes in (%.0f -> %.0f)" % [d0,
			far.position.distance_to(me.position)])

	# Knocked down: stays put, then gets up.
	far.knock_down()
	var at := far.position
	simulate(0.8)
	check(far.position.distance_to(at) < 0.5, "a downed zombie does not move")
	simulate(1.2)
	check(far.down_t <= 0.0, "it gets back up")

	# Breeds and looks come from the id, the same on every machine.
	check(Zombie.kind_for(12345) == Zombie.kind_for(12345), "breed is fixed by id")
	check(Items.zombie_wear(77) == Items.zombie_wear(77), "clothes are fixed by id")
