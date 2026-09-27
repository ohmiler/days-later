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
	await round2()


# --- Round 2 ---------------------------------------------------------------------

func round2() -> void:
	SaveGame.wipe()
	await host(9545)
	main.spawn_timer = 1e9
	var home := me.position
	var side := Vector2.RIGHT
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if main.world.can_stand(home + d * 14.0, 5) and not main.combat._wall_between(home, home + d * 14.0, 0):
			side = d
			break

	# An axe to the legs can take one off: it crawls, slowly, at your ankles.
	me.worn.hand_r = Items.make("axe")
	me.refresh_wear()
	var z := zombie_at(home + side * 14.0)
	z.max_hp = 5000.0
	z.hp = 5000.0
	for i in 60:
		if z.crawler():
			break
		z.stun = 0.0
		z.down_t = 0.0
		z.flags = 0
		z.position = home + side * 14.0
		_aim_at(z.position + Vector2(0, -4))
		main.combat._resolve_melee(me, Look.SWING, main.combat.PUNCH)
	check(z.crawler(), "an axe to the legs takes one off")
	check(Combat.zone_at(-28.0, z) == "body", "a crawler is low: no head to aim at")
	z.down_t = 0.0
	z.stun = 0.0
	z.target = me
	z.position = home + side * 60.0
	var from := z.position
	z.repath = 0.0
	simulate(1.0)
	var moved := z.position.distance_to(from)
	check(moved > 1.0 and moved < Zombie.KINDS.normal.speed * 0.5, "it drags itself along, slowly (%.1f px in a second)" % moved)
	z.position = home + side * 9.0
	var hp := me.hp
	z.attack_cd = 0.0
	simulate(0.1)
	check(me.hp < hp and me.wounds.any(func(w): return w.part == "legs"), "it bites at your legs")
	me.hp = Player.MAX_HP
	me.wounds.clear()
	main.actions._do_action(me, {kind = "zombie", id = z.zid}, "stomp")
	check(not main.zombies.has(z.zid), "and it can be stamped on")

	# Sneaking up behind one with a knife: dead at once, not a sound.
	me.worn.hand_r = Items.make("knife")
	me.refresh_wear()
	me.sneak = true
	var b := zombie_at(home + side * 14.0)
	b.target = null
	b.state = 0
	b.facing = side.angle()  # (its back to you)
	var other := zombie_at(home - side * 120.0)
	other.target = null
	other.investigate_t = 0.0
	_aim_at(b.position + Vector2(0, -15))
	main.combat._resolve_melee(me, Look.SWING, main.combat.PUNCH)
	check(not main.zombies.has(b.zid), "a knife from behind, sneaking: a silent kill")
	check(me.stabbing(), "played out: you're held in it a moment")
	var at := me.position
	me.move = Vector2.RIGHT
	me.server_tick(0.1)
	check(me.position == at, "and can't walk off mid-kill")
	me.move = Vector2.ZERO
	simulate(Combat.STAB_TIME)
	check(not me.stabbing(), "then it's done")
	check(main.corpses.values()[-1].style == "held", "lowered face down")
	check(other.investigate_t <= 0.0, "nobody heard a thing")
	var f := zombie_at(home + side * 14.0)
	f.max_hp = 500.0
	f.hp = 500.0
	f.target = null
	f.state = 0
	f.facing = (-side).angle()  # (facing you)
	_aim_at(f.position + Vector2(0, -15))
	main.combat._resolve_melee(me, Look.SWING, main.combat.PUNCH)
	check(main.zombies.has(f.zid), "not from the front")
	# Sneaking up behind, it only knows you're there when you're almost touching.
	var s2 := zombie_at(home + side * 30.0)
	s2.target = null
	s2.state = 0
	s2.facing = side.angle()
	me.position = home + side * 30.0 - side * 14.0
	check(s2._nearest_player() == null, "sneaking up behind it, 14 px away: it hasn't noticed")
	me.sneak = false
	check(s2._nearest_player() == me, "walking up, it has")
	me.sneak = true
	me.worn.hand_r = Items.make("knife")
	check(Combat.can_backstab(me, s2, "knife"), "and the knife mark shows over it")
	check(Combat.can_backstab(me, s2, "machete") and not Combat.can_backstab(me, s2, "axe") and not Combat.can_backstab(me, s2, "bat"),
			"a machete will do too; not an axe or a bat")
	# The real thing: a click, through the swing (its sound would turn it round).
	me.stab_t = 99.0
	var c3 := zombie_at(home + side * 60.0)
	c3.target = null
	c3.state = 0
	c3.facing = side.angle()
	c3.wander_t = 100.0
	c3.wander = Vector2.ZERO
	me.position = c3.position - side * 18.0
	me.aim = side * 18.0 + Vector2(0, -14)
	me.shoot_cd = 0.0
	me.local_cd = 0.0
	me.punching = true
	simulate(0.1)
	me.punching = false
	check(not main.zombies.has(c3.zid) and me.stabbing(), "a click from behind, sneaking: the silent kill, not a swing")
	simulate(Combat.STAB_TIME)
	me.sneak = false
	me.position = home

	# Left alone it mostly stands still.
	var idle := zombie_at(home + side * 200.0)
	var still := 0
	for i in 40:
		idle.wander_t = 0.0
		idle.repath = 0.0
		idle.target = null
		idle.investigate_t = 0.0
		idle.server_tick(0.01)
		if idle.wander == Vector2.ZERO:
			still += 1
	check(still > 14 and still < 36, "left alone it mostly stands about (%d of 40)" % still)

	# Some twitch once they're down; face down after a kneel.
	var twitched := 0
	for seed_i in 30:
		var c := Corpse.new()
		c.style = "blunt"
		c.lk = {spurt_seed = seed_i}
		for t in range(10, 40):
			if c._twitch(t * 0.1) > 0.0:
				twitched += 1
				break
		c.free()
	check(twitched > 3 and twitched < 25, "some bodies twitch (%d of 30)" % twitched)
	var r := Rig.build({view = [Look.SIDE, false], fall = 1.0, fall_dir = 1.0, face_down = true}, {})
	var r2 := Rig.build({view = [Look.SIDE, false], fall = 1.0, fall_dir = 1.0}, {})
	check(r.sx != r2.sx, "face down: turned over from lying on its back")
	SaveGame.wipe()
	await close_game()
