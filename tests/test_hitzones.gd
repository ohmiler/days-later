extends "res://tests/test_base.gd"
## Where a blow or a shot lands: head, body or legs (Combat.zone_at, from how
## high on the drawn body you clicked), what that does to the damage, and how
## the zombie dies of it (Combat.death_style).


func _aim_at(pos: Vector2) -> void:
	me.aim = pos - (me.position + Look.CHEST)


func _hit(z: Zombie, dy: float) -> float:
	var hp0 := z.hp
	_aim_at(z.position + Vector2(0, dy))
	main.combat._resolve_melee(me, Look.PUNCH_L, main.combat.PUNCH)
	return hp0 - z.hp


func run() -> void:
	check(Combat.zone_at(-28.0) == "head" and Combat.zone_at(-15.0) == "body" and Combat.zone_at(-4.0) == "legs", "head, body, legs by height")
	# Deaths by where and with what.
	var styles := func(how: String, zone: String, close := false) -> Dictionary:
		var seen := {}
		for i in 200:
			seen[Combat.death_style(how, zone, close)] = true
		return seen
	check(styles.call("axe", "head").has("behead"), "an axe to the head takes it off")
	check(styles.call("bat", "head").has("crush") and styles.call("bat", "head").has("slump"), "a bat to the head: skull caved, or down where it stood")
	check(styles.call("knife", "head").keys() == ["slump"], "a knife to the head: it drops")
	check(styles.call("knife", "body").has("kneel"), "a blade in the body: to its knees, then over")
	check(styles.call("gun", "head").keys() == ["burst"], "shot in the head: it bursts")
	check(not styles.call("gun", "body").has("burst"), "shot in the body: no burst head")
	check(styles.call("gun", "body", true).keys() == ["flung"], "a shotgun up close throws it back")
	check(styles.call("kick", "body").keys() == ["flung"], "a finishing kick throws it back")

	SaveGame.wipe()
	await host(9544)
	main.spawn_timer = 1e9
	var home := me.position
	var side := Vector2.RIGHT  # (somewhere clear beside you: no wall between)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if main.world.can_stand(home + d * 14.0, 5) and not main.combat._wall_between(home, home + d * 14.0, 0):
			side = d
			break
	var z := zombie_at(home + side * 14.0)
	z.hp = 1000.0
	z.max_hp = 1000.0
	var body := _hit(z, -15.0)
	z.stun = 0.0
	var head := _hit(z, -28.0)
	z.stun = 0.0
	z.down_t = 0.0
	var legs := _hit(z, -4.0)
	check(head > body * 1.6 and legs < body, "the head hurts most, the legs least (%.0f / %.0f / %.0f)" % [head, body, legs])
	# A zombie on the ground is all body.
	z.down_t = 1.0
	z.flags = 2
	check(Combat.zone_at(-28.0, z) == "body", "one on the ground has no head to aim for")
	z.down_t = 0.0
	z.flags = 0

	# Aiming a gun at the head aims at the head.
	var aim := Combat.snap_aim(me.position + Look.CHEST, z.position + Vector2(0, -28), [z])
	check(Combat.zone_at((me.position + Look.CHEST + aim).y - z.position.y) == "head", "the cursor on its head: the gun aims at the head")
	# The killing blow lands a little heavier.
	check(Combat.KILL_STOP > Combat.HITSTOP, "the killing blow holds longer")
	# A body from a kneel falls toward whoever killed it.
	z.hp = 1.0
	var before: int = main.corpses.size()
	main.combat._kill_zombie(z, 1.0, "knife", "head")
	var c: Dictionary = main.corpses.values()[-1]
	check(main.corpses.size() == before + 1 and c.style == "slump" and c.fall_dir == -1.0, "a knife to the head: it drops toward you")
	SaveGame.wipe()
	await close_game()
