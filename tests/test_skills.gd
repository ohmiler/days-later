extends "res://tests/test_base.gd"
## Skills (data/skills.cfg): experience from doing, levels 1-50 quick at first
## and slow later, small effects, a ring and the news on a level up, a little
## lost on dying (never a level), kept in the save; the survivor level by the name.


func run() -> void:
	# The numbers.
	check(Skills.DEFS.size() == 6 and Skills.DEFS.has("combat") and Skills.DEFS.has("stealth"), "six skills from the table")
	check(Skills.level_of(0.0) == 1 and Skills.level_of(Skills.xp_for(10)) == 10 and Skills.level_of(Skills.xp_for(10) - 1.0) == 9, "levels by experience")
	check(Skills.level_of(1e12) == Skills.MAX_LEVEL, "fifty at most")
	check(Skills.xp_for(10) < 2000.0 and Skills.xp_for(50) > 40.0 * Skills.xp_for(10), "quick at first (%.0f to Lv10), slow later (%.0f to Lv50)" % [Skills.xp_for(10), Skills.xp_for(50)])
	check(Skills.total({}) == 1, "a new survivor is level 1")

	SaveGame.wipe()
	await host(9546)
	main.spawn_timer = 1e9
	var home := me.position
	var side := Vector2.RIGHT
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if main.world.can_stand(home + d * 14.0, 5) and not main.combat._wall_between(home, home + d * 14.0, 0):
			side = d
			break

	# Hitting and killing teaches fighting.
	var z := zombie_at(home + side * 14.0)
	z.hp = 1.0
	me.aim = side * 14.0 + Vector2(0, -15)
	main.combat._resolve_melee(me, Look.PUNCH_L, main.combat.PUNCH)
	var xp: float = me.skills.get("combat", 0.0)
	check(not main.zombies.has(z.zid) and xp >= 12.0, "a kill: fighting experience (%.0f)" % xp)

	# Going up a level: the ring, and everyone knows the survivor level.
	me.skills.combat = Skills.xp_for(2) - 1.0
	main.skills.gain(me, "combat", "hit")
	check(Skills.level(me, "combat") == 2 and me.levelup_t > 0.0, "a level up: the ring of light")
	check(me.level_total == 2, "and the survivor level goes up (%d)" % me.level_total)

	# What levels do: small, never huge.
	me.skills.combat = Skills.xp_for(50)
	check(absf(Skills.mult(me, "swing_cd") - (1.0 - 0.004 * 49)) < 0.001, "combat 50: swings %.0f%% sooner" % ((1.0 - Skills.mult(me, "swing_cd")) * 100))
	check(Skills.mult(me, "heal") == 1.0, "and nothing else changes")
	me.skills.endurance = Skills.xp_for(50)
	check(me.carry_limit() > Items.CARRY * 1.15 and me.carry_limit() < Items.CARRY * 1.3 + Player.MORE_CARRY, "endurance 50: carry a little more (%.1f kg)" % me.carry_limit())

	# Creeping past one that hasn't seen you teaches sneaking.
	me.skills.stealth = 0.0
	var idle := zombie_at(home + side * 50.0)
	idle.target = null
	idle.state = 0
	idle.dummy = true
	me.sneak = true
	me.move = -side
	for i in 30:
		main.survival._tick_needs(me, 0.1)
	me.move = Vector2.ZERO
	me.sneak = false
	check(float(me.skills.get("stealth", 0.0)) > 1.0, "creeping past unseen: sneaking experience (%.1f)" % float(me.skills.get("stealth", 0.0)))

	# Dying costs part of the way into the level, never the level.
	me.skills.medic = (Skills.xp_for(7) + Skills.xp_for(8)) * 0.5
	var before: float = me.skills.medic
	main.skills.on_death(me)
	check(Skills.level(me, "medic") == 7 and me.skills.medic < before, "dying: a little lost, the level kept")

	# Kept in the save.
	me.skills.cook = Skills.xp_for(5) + 3.0
	main._save_all()
	await close_game()
	await host(9546, true, false)
	check(Skills.level(me, "cook") == 5 and Skills.level(me, "endurance") == 50, "skills come back after a reload")
	SaveGame.wipe()
	await close_game()
