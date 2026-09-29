extends "res://tests/test_base.gd"
## What the skills open (data/skills.cfg `unlocks`, Skills.has): each one
## really does something, through the same paths play takes.


func _at(skill: String, lvl: int) -> void:
	me.skills[skill] = Skills.xp_for(lvl)


func _aim_at(pos: Vector2) -> void:
	me.aim = pos - (me.position + Look.CHEST)


func run() -> void:
	for bad in [Skills.problems(), Crafting.problems(), Items.problems()]:
		check(bad.is_empty(), "the tables agree" + ("" if bad.is_empty() else ": " + "; ".join(bad)))
	var asked := ["head_aim", "kick_down", "side_stab", "blunt_silent", "treat_other", "stitch", "craft_5", "fast_hotwire", "mend_rare",
			"cook_5", "more_carry"]
	var idle: Array = Skills.UNLOCKS.keys().filter(func(u): return u not in asked)
	check(idle.is_empty(), "every unlock in the table is one the code asks about (%s)" % [idle])

	SaveGame.wipe()
	await host(9377)
	main.spawn_timer = 1e9
	var w: World = main.world
	var spot := w.to_pos(w.spawn_cell)
	me.position = spot
	var side := Vector2.RIGHT
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if w.can_stand(spot + d * 14.0, 5) and not main.combat._wall_between(spot, spot + d * 14.0, 0):
			side = d
			break
	me.skills = {}
	check(not Skills.has(me, "head_aim"), "a new survivor has none open")
	_at("combat", 5)
	check(Skills.has(me, "head_aim") and not Skills.has(me, "kick_down"), "combat 5 opens the first, not the next")

	# combat 5: the head reaches a little lower.
	var z := zombie_at(spot + side * 14.0)
	z.hp = 1000.0
	var dy := Proportions.head_line() * z.height + 1.5  # (just under the head: a body blow for most)
	me.skills = {}
	var hp0 := z.hp
	_aim_at(z.position + Vector2(0, dy))
	main.combat._resolve_melee(me, Look.PUNCH_L, main.combat.PUNCH)
	var plain := hp0 - z.hp
	_at("combat", 5)
	z.stun = 0.0
	hp0 = z.hp
	main.combat._resolve_melee(me, Look.PUNCH_L, main.combat.PUNCH)
	check(hp0 - z.hp > plain * 1.5, "combat 5: a blow just under the head counts as the head (%.0f vs %.0f)" % [hp0 - z.hp, plain])

	# combat 10: kicks put them down more often.
	var downs := func() -> int:
		var n := 0
		for i in 400:
			z.down_t = 0.0
			z.stun = 0.0
			z.hp = 1000.0
			z.position = spot + side * 14.0
			_aim_at(z.position + Vector2(0, -15))
			main.combat._resolve_melee(me, Look.KICK, main.combat.KICK)
			if z.down_t > 0.0:
				n += 1
		return n
	me.skills = {}
	var d0: int = downs.call()
	_at("combat", 10)
	var d1: int = downs.call()
	check(d1 > d0 + 20, "combat 10: kicks put them down more (%d vs %d of 400)" % [d1, d0])
	z.down_t = 0.0

	# stealth 5: from the side; stealth 10: with something blunt.
	me.sneak = true
	z.state = 0
	z.target = null
	z.facing = (side.orthogonal()).angle()  # (you're at its side)
	me.skills = {}
	check(not Combat.can_backstab(me, z, "knife"), "from the side, a silent kill needs stealth 5")
	_at("stealth", 5)
	check(Combat.can_backstab(me, z, "knife"), "stealth 5: from the side will do")
	z.facing = (spot - z.position).angle() + PI  # (its back to you)
	check(not Combat.can_backstab(me, z, "pipe"), "a pipe can't kill silently")
	_at("stealth", 10)
	check(Combat.can_backstab(me, z, "pipe"), "stealth 10: a pipe can")
	me.sneak = false
	z.queue_free()
	main.zombies.erase(z.zid)

	# first aid 5: bandage a friend (E on them); first aid 10: sewn, heals faster.
	me.skills = {}
	var q: Player = main._add_player(77)
	q.pname = "Noi"
	q.position = spot + side * 8.0
	q.hp = 70.0
	Body.add(q, "bite", "arms", true)
	me.inv.fill(null)
	me.inv[0] = Items.make("bandage")
	me.inv[0].n = 3
	me.aim = side * 20.0
	check(Interact.target(main, me).get("kind") != "player", "without first aid 5, a hurt friend isn't something E does")
	_at("medic", 5)
	var t := Interact.target(main, me)
	check(t.get("kind") == "player" and t.id == 77, "first aid 5: E points at the hurt friend")
	main.actions.req_act("player", 77, "treat_other")
	check(q.wounds[0].bandaged and not q.bleeding and count(me, "bandage") == 2, "and bandages their bite with one of yours")
	check(not q.wounds[0].get("stitched", false), "(not sewn: that's first aid 10)")
	Body.add(q, "bite", "legs", true)
	_at("medic", 10)
	main.inventory.treat_other(me, q)
	check(q.wounds[1].get("stitched", false), "first aid 10: sewn up too")
	var t0: float = q.wounds[0].t
	var t1: float = q.wounds[1].t
	Body.tick(q, 10.0)
	check(q.wounds[1].t - t1 > (q.wounds[0].t - t0) * 1.9, "and a sewn wound heals twice as fast")

	# craft 5 and cook 5: recipes you know only then.
	me.skills = {}
	me.inv.fill(null)
	me.inv[0] = Items.make("plank")
	me.inv[1] = Items.make("nails")
	me.inv[1].n = 3
	me.craft = {}
	main.crafting.req_craft("nailbat_plank")
	check(me.craft.is_empty(), "a nail bat needs craft 5")
	_at("craft", 5)
	main.crafting.req_craft("nailbat_plank")
	check(me.craft.get("id", "") == "nailbat_plank", "craft 5: now you know how")
	me.craft = {}
	me.inv[2] = Items.make("rice")
	me.inv[3] = Items.make("fishcan")
	main.crafting.req_craft("fishrice")
	check(me.craft.is_empty(), "rice and fish need cook 5")
	_at("cook", 5)
	main.crafting.req_craft("fishrice")
	check(me.craft.get("id", "") == "fishrice", "cook 5: rice mixed with canned fish")
	simulate(3.0)
	check(count(me, "fishrice") == 1 and Items.def("fishrice").food > Items.def("rice").food + Items.def("fishcan").food,
			"and it fills you more than the two apart")

	# endurance 10: 3 kg more before you slow down.
	me.set_wear({})
	me.skills = {}
	var kg := me.carry_limit()
	_at("endurance", 10)
	check(me.carry_limit() >= kg + Player.MORE_CARRY, "endurance 10: carry 3 kg more (%.1f -> %.1f)" % [kg, me.carry_limit()])
