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
		main.inventory._give(me, id)
		me.sel = me.inv.find(me.inv.filter(func(x): return x != null and x.id == id)[0])
		main.inventory._use_selected(me)
	check(me.guard("torso") > 0.5 and me.guard("head") > 0.5, "vest and helmet guard body and head (%.2f, %.2f)" % [me.guard("torso"), me.guard("head")])
	me.hp = 100.0
	me.bite(20.0, "torso")
	check(me.hp > 80.0 and me.hp < 100.0, "a 20 bite on the body does less through the vest (hp %.1f)" % me.hp)
	me.hp = 100.0
	me.bite(20.0, "arms")
	check(me.hp == 80.0, "but a bite on a bare arm does it all (hp %.1f)" % me.hp)
	me.hp = 100.0

	# Where bites land: from behind, the neck and back; flat on the ground, the legs.
	me.aim = Vector2.RIGHT
	var spots := {}
	for i in 200:
		var at: String = me.bite_part(me.position + Vector2(-10, 0), false)
		spots[at] = spots.get(at, 0) + 1
	check(spots.get("neck", 0) > 50 and not spots.has("hands"), "from behind it goes for the neck (%s)" % [spots])
	check(me.bite_part(me.position + Vector2(10, 0), true) == "legs", "on the ground it goes for the legs")
	main.inventory._give(me, "scarf")
	me.sel = me.inv.find(me.inv.filter(func(x): return x != null and x.id == "scarf")[0])
	main.inventory._use_selected(me)
	check(me.guard("neck") > 0.4, "a thick scarf guards the neck (%.2f)" % me.guard("neck"))
	var flat := zombie_at(me.position + Vector2(6, 0))
	flat.knock_down()
	flat.attack_cd = 0.0
	me.hp = 100.0
	simulate(0.3)
	check(me.hp < 100.0 and me.bite_where == "legs", "a zombie knocked flat still bites the legs of anyone standing over it")
	flat.queue_free()
	main.zombies.erase(flat.zid)
	me.hp = 100.0

	# It comes for you from across the street.
	z.queue_free()
	main.zombies.erase(z.zid)
	# (Along whichever direction is open: the spawn point is random, and a
	# building in the way would make this a test of path finding instead.)
	var open_dir := Vector2.RIGHT
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if main.world.ray_length(me.position + Vector2(0, -4), dir, 100.0) >= 100.0:
			open_dir = dir
			break
	var far := zombie_at(me.position + open_dir * 90.0)
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
