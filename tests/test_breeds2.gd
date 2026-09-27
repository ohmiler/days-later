extends "res://tests/test_base.gd"
## Four more kinds (ROADMAP "ซอมบี้รอบ 3"): the junkie (fast, shrugs off
## blows, burns out; its pills), the faker lying among the dead, the guard
## with the whistle, and the aerobics class that never stopped.


func run() -> void:
	var count := {}
	var guard_places := {}
	for id in 40000:
		var k := Zombie.kind_for(id)
		count[k] = count.get(k, 0) + 1
		if k == "guard":
			guard_places[Items.ZOMBIE_PLACES[id % Items.ZOMBIE_PLACES.size()]] = true
	check(["junkie", "faker", "guard", "aerobic"].all(func(k): return count.get(k, 0) > 200), "every new kind turns up (%s)" % count)
	check(count.normal > count.values().reduce(func(a, b): return a + b) * 0.45, "most are still ordinary")
	check(guard_places.keys().all(func(pl): return pl in ["office", "mall", "hospital"]), "guards only where there were guards (%s)" % str(guard_places.keys()))

	SaveGame.wipe()
	await host(9543)
	main.spawn_timer = 1e9
	var home := me.position

	# The faker: lying still, until you come close.
	var f := zombie_at(home + Vector2(80, 0), "faker")
	simulate(1.0)
	check(f.shamming and f.flags & 16 and f.flags & 2 and f.position.distance_to(home + Vector2(80, 0)) < 1.0, "a faker lies still among the dead")
	me.position = home + Vector2(80 - 24, 0)
	simulate(0.1)
	check(not f.shamming and f.target == me, "walk past and it's up, after you")
	simulate(1.2)
	check(f.down_t <= 0.0, "on its feet a moment later")
	f.queue_free()
	main.zombies.erase(f.zid)
	me.position = home
	me.hp = Player.MAX_HP

	# The junkie shrugs off blows, and burns out.
	var j := zombie_at(home + Vector2(200, 0), "junkie")
	check(j.max_hp > Zombie.KINDS.normal.hp and j.speed > Zombie.KINDS.normal.speed, "a junkie is fast and hard to kill")
	check(Zombie.KINDS.junkie.stun < 0.5, "and hardly staggers")
	j.target = me
	j.frenzy_t = Zombie.FRENZY
	simulate(0.1)
	check(j.down_t > Zombie.RISE_TIME and j.flags & 16, "chase too long and it drops, spent")
	simulate(Zombie.SPENT)
	check(j.down_t <= 0.0 and j.flags & 16 == 0, "and gets back up after a while")
	main.combat._kill_zombie(j, 1.0)
	# (60%: its pills are sometimes on it)

	# The pills: no tiredness, things that aren't there, then the crash.
	me.inv[0] = Items.make("pills")
	me.sel = 0
	me.stamina = 10.0
	main.inventory._use_selected(me)
	check(me.stamina >= 99.0 and me.conditions.has("high"), "the pills: tiredness gone, high")
	check(Body.mod(me, "stamina_regen") > 2.0, "your wind comes back fast")
	main.phantoms._t = 0.0
	for i in 60:
		main.phantoms.tick(me, 0.1)
	check(main.zombies.values().all(func(z): return z.zid < 2000000000), "none of them are real zombies")
	Body.tick_conditions(me, float(me.conditions.high) + 1.0, 0.1)
	check(not me.conditions.has("high") and me.conditions.has("crash"), "then it wears off: the crash")
	check(Body.mod(me, "speed") < 1.0, "slow and weak")
	me.conditions.clear()
	main.phantoms.tick(me, 5.0)
	main.phantoms.tick(me, 5.0)
	check(main.phantoms._live.is_empty(), "sober: the phantoms are gone")

	# The guard whistles for the others when it sees you.
	var g := zombie_at(home + Vector2(40, 0), "guard")
	check(g.wear.get("neck", "") == "whistle", "a guard has a whistle round its neck")
	var far := zombie_at(home + Vector2(-200, 0))
	far.target = null
	far.investigate_t = 0.0
	g.state = 0
	g.facing = PI
	simulate(1.2)
	check(g.state == 2 and far.investigate_t > 0.0, "it sees you and whistles: another comes to look")
	g.queue_free()
	main.zombies.erase(g.zid)

	# Your own whistle does the same.
	far.investigate_t = 0.0
	far.target = null
	me.inv[1] = Items.make("whistle")
	me.sel = 1
	main.inventory._use_selected(me)
	check(far.investigate_t > 0.0 and me.inv[1] != null, "blow a whistle: they come to look, and you keep the whistle")

	# The aerobics class dances while nobody's about.
	var a := zombie_at(home + Vector2(0, 120), "aerobic")
	a.state = 0
	a.moving = false
	check(a._dancing(), "an aerobics zombie dances on the spot")
	a.state = 2
	check(not a._dancing(), "and stops when it sees you")
	SaveGame.wipe()
	await close_game()
