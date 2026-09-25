extends "res://tests/test_base.gd"
## Hitting things: fists, kicks, weapons, what you click on, and how zombies die.


func _aim_at(pos: Vector2) -> void:
	me.aim = pos - (me.position + Look.CHEST)


func run() -> void:
	await host(9301)
	var home := me.position

	# A punch lands on the zombie in front.
	var z := zombie_at(home + Vector2(14, 0))
	_aim_at(z.position + Look.CHEST)
	var hp0 := z.hp
	main.combat._resolve_melee(me, Look.PUNCH_L, main.combat.PUNCH)
	check(z.hp < hp0, "punch hits a zombie in front (%.0f -> %.0f)" % [hp0, z.hp])

	# Clicking its feet from below still hits (the aim comes from your chest).
	z.position = home + Vector2(0, -14)
	_aim_at(z.position)
	hp0 = z.hp
	main.combat._resolve_melee(me, Look.PUNCH_L, main.combat.PUNCH)
	check(z.hp < hp0, "clicking a zombie's feet above you hits it")

	# Nothing behind you gets hit.
	z.position = home + Vector2(-16, 0)
	_aim_at(home + Vector2(40, 0))
	hp0 = z.hp
	main.combat._resolve_melee(me, Look.PUNCH_L, main.combat.PUNCH)
	check(z.hp == hp0, "a zombie behind you is not hit")

	# Kicks knock some down, never a fat one.
	z.position = home + Vector2(14, 0)
	z.hp = 9999
	_aim_at(z.position + Look.CHEST)
	var downs := 0
	for i in 60:
		z.down_t = 0.0
		z.position = home + Vector2(14, 0)
		main.combat._resolve_melee(me, Look.KICK, [26.0, 1.0, 0.5, 0.1, 0.0])
		downs += int(z.down_t > 0.0)
	check(downs > 5 and downs < 55, "kicks knock a normal zombie down sometimes (%d/60)" % downs)
	var fat := zombie_at(home + Vector2(14, 4), "fat")
	fat.hp = 9999
	z.queue_free()
	main.zombies.erase(z.zid)
	var fat_downs := 0
	for i in 30:
		fat.position = home + Vector2(14, 0)
		main.combat._resolve_melee(me, Look.KICK, [26.0, 1.0, 0.5, 0.1, 0.0])
		fat_downs += int(fat.down_t > 0.0)
	check(fat_downs == 0, "fat zombies are never kicked over")
	fat.queue_free()
	main.zombies.erase(fat.zid)

	# A blade takes arms off; weapons wear down.
	main.inventory._give(me, "machete")
	me.sel = me.inv.find(me.inv.filter(func(x): return x != null and x.id == "machete")[0])
	main.inventory._send_inv(me)
	var w := zombie_at(home + Vector2(14, 0))
	w.hp = 9999
	var dur0: int = me.inv[me.sel].hp
	for i in 30:
		w.position = home + Vector2(14, 0)
		main.combat._resolve_melee(me, Look.SWING, [26.0, 1.0, 0.5, 0.1, 0.0])
	check(w.missing & (Look.LOST_ARM_L | Look.LOST_ARM_R) != 0, "machete hits cut arms off (bits %d)" % w.missing)
	check(me.inv[me.sel] == null or me.inv[me.sel].hp < dur0, "the machete wore down")
	check(w.bite_damage() < Zombie.KINDS.normal.dmg, "fewer arms, weaker bite (%.1f)" % w.bite_damage())

	# Kills: how it dies depends on the weapon.
	var styles := {}
	for i in 400:
		styles[main.combat.death_style("axe")] = true
	check(styles.has("behead") and styles.has("arm"), "axes behead and take arms")
	check(main.combat.death_style("knife") == "stab", "knives stab")
	check(main.combat.death_style("gun") == "burst", "a shot to the head bursts it")
	var n0: int = main.zombies.size()
	w.hp = 1
	w.position = home + Vector2(14, 0)
	main.combat._resolve_melee(me, Look.SWING, [26.0, 5.0, 0.5, 0.1, 0.0])
	check(main.zombies.size() == n0 - 1, "a killing blow removes the zombie")
	check(me.kills >= 1, "and counts as a kill")
