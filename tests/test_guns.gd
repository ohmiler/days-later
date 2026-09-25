extends "res://tests/test_base.gd"
## Guns: reloading from the bag, firing only while aiming, a shot that hits,
## is heard far away and uses a round; an empty gun clicks; not aiming, the
## gun is a club; a shotgun takes both hands and throws pellets.


func _open_dir() -> Vector2:
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if main.world.ray_length(me.position + Look.CHEST, dir, 120.0) >= 120.0 \
				and main.world.can_stand(me.position + dir * 70.0, Zombie.RADIUS + 1.0):
			return dir
	return Vector2.RIGHT


func run() -> void:
	# Not in the city yet: guns and ammo wait for the police station (phase 3).
	var found := []
	for place in Items.LOOT:
		for entry in Items.LOOT[place]:
			if Items.def(entry[0]).get("type", "") in ["gun", "ammo"]:
				found.append("%s in %s" % [entry[0], place])
	check(found.is_empty(), "no guns or ammo to find in the city yet" + ("" if found.is_empty() else ": " + ", ".join(found)))
	await host(9430)
	main.spawn_timer = 1e9
	me.inv.fill(null)
	main.admin.req_give("pistol", 1)
	main.admin.req_give("ammo9", 30)
	main.inventory.req_select(0)
	check(me.hand_weapon("r") == "pistol", "a pistol in the right hand")

	# Reload from the bag.
	main.doors.req_reinforce()  # (R: no door here, so it reloads)
	simulate(Items.def("pistol").reload + 0.2)
	check(me.worn.hand_r.ammo == 12 and count(me, "ammo9") == 18, "T loads 12 from the bag (%d left)" % count(me, "ammo9"))

	# Fire while aiming: it hits, it's heard, it costs a round.
	var dir := _open_dir()
	me.aim = dir * 60.0
	var target := zombie_at(me.position + dir * 60.0)
	target.hp = 1000.0
	var far := zombie_at(me.position - dir * 400.0)
	me.aiming = true
	me.punching = true
	simulate(0.1)
	me.punching = false
	check(target.hp < 1000.0, "a shot hits the zombie in the sights (hp %.0f)" % target.hp)
	check(me.worn.hand_r.ammo == 11, "and uses a round")
	simulate(0.3)
	check(far.investigate_t > 0.0 or far.target != null, "the shot is heard 400 px away")

	# Not aiming: it's a club, and no round goes.
	me.aiming = false
	var hp0 := target.hp
	target.position = me.position + dir * 14.0
	me.punching = true
	simulate(0.8)
	me.punching = false
	check(me.worn.hand_r.ammo == 11, "without aiming the left button doesn't shoot")

	# Empty: a click, nothing else.
	me.worn.hand_r.ammo = 0
	target.position = me.position + dir * 60.0
	hp0 = target.hp
	me.aiming = true
	me.punching = true
	simulate(0.1)
	me.punching = false
	check(target.hp == hp0, "an empty gun just clicks")
	me.aiming = false

	# A shotgun: two hands, pellets.
	main.admin.req_give("shotgun", 1)
	main.inventory.req_move(["inv", me.inv.find(me.inv.filter(func(x): return x != null and x.id == "shotgun")[0])], ["worn", "hand_r"])
	check(me.hand_weapon("r") == "shotgun" and Items.two_handed("shotgun"), "a shotgun takes both hands")
	me.worn.hand_r.ammo = 5
	target.hp = 1000.0
	target.position = me.position + dir * 40.0
	me.aiming = true
	me.punching = true
	simulate(0.1)
	me.punching = false
	me.aiming = false
	check(1000.0 - target.hp > Items.def("shotgun").dmg * 2.0, "pellets hit hard up close (%.0f)" % (1000.0 - target.hp))


	# Up on a roof: aim and shots start where you're drawn, lifted; walls below don't stop them.
	var tz: Zombie = zombie_at(me.position + _open_dir() * 50.0)
	me.on_roof = true
	var lift: float = main.world.roof_height(me.position)
	if tz:
		tz.hp = 1000.0
		var gun_at := me.position + Look.CHEST + Vector2(0, -lift)
		me.aim = tz.position + Vector2(0, -12) - gun_at
		me.worn.hand_r = {id = "pistol", n = 1, hp = 100, ammo = 5}
		for i in 3:  # (shots spread at random: one of three is sure to land if the aim is right)
			me.shoot_cd = 0.0
			main.combat.fire(me, "r")
		check(tz.hp < 1000.0 or main.world.building_at.has(main.world.to_cell(tz.position)), "from a roof the shot lands where aimed (hp %.0f)" % tz.hp)
	me.on_roof = false

	# The whole figure counts: a shot at the head or the feet lands; beside it doesn't.
	var feet := Vector2(200, 100)
	check(Combat.body_hit(Vector2(100, 100 - 24), Vector2.RIGHT, feet) > 0, "a shot at the head hits")
	check(Combat.body_hit(Vector2(100, 100 - 3), Vector2.RIGHT, feet) > 0, "a shot at the legs hits")
	check(Combat.body_hit(Vector2(100, 100 - 45), Vector2.RIGHT, feet) < 0, "a shot over the head misses")
	var snapped := Combat.snap_aim(Vector2.ZERO, feet + Vector2(4, -26), [{position = feet}])
	check(snapped.is_equal_approx(feet + Vector2(0, -14)), "the cursor on a zombie aims at its middle")
