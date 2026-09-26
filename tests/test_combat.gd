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

	# Two hands: a weapon in each, swings alternating; a two-handed one takes both.
	me.inv.fill(null)
	main.inventory._give(me, "knife")
	main.inventory._give(me, "hammer")
	main.inventory.req_move(["inv", 0], ["worn", "hand_r"])
	main.inventory.req_move(["inv", 1], ["worn", "hand_l"])
	check(me.hand_weapon("r") == "knife" and me.hand_weapon("l") == "hammer", "a knife in the right hand and a hammer in the left")
	var hands_seen := {}
	me.punching = true
	for i in 90:
		simulate(1.0 / 30.0)
		if me.anim in [Look.SWING, Look.SWING_L]:
			hands_seen[me.anim] = true
	me.punching = false
	check(hands_seen.size() == 2, "holding the button swings one hand, then the other")
	main.inventory._give(me, "axe")
	main.inventory.req_move(["inv", me.inv.find(me.inv.filter(func(x): return x != null and x.id == "axe")[0])], ["worn", "hand_l"])
	check(me.hand_weapon("r") == "axe" and me.hand_weapon("l") == "", "an axe takes both hands (the left lets go)")
	main.inventory.req_move(["inv", me.inv.find(me.inv.filter(func(x): return x != null and x.id == "hammer")[0])], ["worn", "hand_l"])
	check(me.hand_weapon("l") == "", "nothing else goes in the left hand while holding it")
	for h in ["hand_r", "hand_l"]:
		if me.worn.get(h) != null:
			main.inventory.req_move(["worn", h], ["inv", -1])

	# A blade takes arms off; weapons wear down.
	main.inventory._give(me, "machete")
	main.inventory.req_select(me.inv.find(me.inv.filter(func(x): return x != null and x.id == "machete")[0]))  # into the right hand
	var w := zombie_at(home + Vector2(14, 0))
	w.hp = 9999
	var dur0: int = me.worn.hand_r.hp
	me.swing_hand = "r"  # (these swings are the right hand's)
	for i in 30:
		w.position = home + Vector2(14, 0)
		main.combat._resolve_melee(me, Look.SWING, [26.0, 1.0, 0.5, 0.1, 0.0])
	check(w.missing & (Look.LOST_ARM_L | Look.LOST_ARM_R) != 0, "machete hits cut arms off (bits %d)" % w.missing)
	check(me.worn.get("hand_r") == null or me.worn.hand_r.hp < dur0, "the machete wore down")
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

	# Feel: a click while still busy isn't lost, the 1-2 starts again after a pause,
	# a blow that lands holds the pose a beat, and your own swing shows on the click.
	for h in ["hand_r", "hand_l"]:
		if me.worn.get(h) != null:
			main.inventory.req_move(["worn", h], ["inv", -1])
	simulate(1.0)
	me.set_attack_input(false, false)
	me.shoot_cd = 0.2  # still recovering from the last punch
	me.anim = Look.NONE
	me.set_attack_input(true, false)  # a quick click...
	simulate(0.05)
	me.set_attack_input(false, false)  # ...let go before the punch was ready
	simulate(0.3)
	check(me.anim in [Look.PUNCH_L, Look.PUNCH_R], "a click while still busy punches as soon as it can")
	me.next_hand = "l"
	me.anim_t = 0.3
	check(Combat.next_swing(me).hand == "l", "punching on, the hands alternate")
	me.anim_t = Combat.COMBO_RESET + 0.5
	check(Combat.next_swing(me).hand == "r", "after a pause the 1-2 starts again from the first punch")
	me.anim_t = 0.1
	me.hitstop = 0.0
	main.combat.fx_hit(-1, me.position, Vector2.RIGHT, false, me.peer_id)
	check(me.hitstop > 0.0, "a blow that lands holds the swing a beat")
	var zf := zombie_at(me.position + Vector2(40, 0))
	zf.flinch(Vector2.RIGHT)
	check(zf.freeze > 0.0 and zf.hit_t > 0.0, "and the zombie's flinch with it")
	# (What the client does for its own player, run here on the host's.)
	me.predicted = 0
	me.local_cd = 0.0
	me.anim = Look.NONE
	me.anim_t = 2.0
	me.set_attack_input(true, false)
	main.combat.predict(me, 0.016)
	me.set_attack_input(false, false)
	check(me.anim == Look.PUNCH_R and me.predicted == 1, "your own punch shows the moment you click")
	me.anim_t = 0.05
	main.combat.fx_melee(me.peer_id, Look.PUNCH_R)
	check(me.predicted == 0 and is_equal_approx(me.anim_t, 0.05), "and isn't played again when the server confirms it")

	# Fighting tires you: every blow costs breath, none comes back for a moment
	# after, and worn out the blows come slower and softer.
	me.stamina = 100.0
	me.exhausted = false
	me.swing_hand = "r"
	main.combat._melee(me, Look.PUNCH_R, Combat.PUNCH.duplicate())
	var after_punch := me.stamina
	check(is_equal_approx(after_punch, 100.0 - Combat.PUNCH_COST), "a punch costs stamina (%.0f left)" % after_punch)
	main.combat._melee(me, Look.KICK, Combat.kick_stats(me))
	check(me.stamina < after_punch - Combat.PUNCH_COST, "a kick costs more (%.0f left)" % me.stamina)
	var before_rest := me.stamina
	main.survival._tick_needs(me, 0.5)
	check(is_equal_approx(me.stamina, before_rest), "no breath back straight after a blow")
	main.survival._tick_needs(me, 0.6)
	main.survival._tick_needs(me, 0.5)
	check(me.stamina > before_rest, "then it comes back")
	check(Combat.blow_cost(Look.SWING, "axe") > Combat.blow_cost(Look.SWING, "knife"), "a heavy axe tires you more than a knife")
	var fresh := Combat.kick_stats(me)
	me.stamina = Combat.TIRED - 1.0
	var worn := Combat.kick_stats(me)
	check(worn[2] > fresh[2] and worn[1] < fresh[1], "worn out, blows come slower and land softer")
	me.stamina = 2.0
	main.combat._melee(me, Look.KICK, Combat.kick_stats(me))
	check(me.stamina == 0.0 and me.exhausted, "fought to a standstill: spent")
