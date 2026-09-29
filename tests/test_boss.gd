extends "res://tests/test_base.gd"
## The first boss (data/bosses.cfg): the sergeant waits in a hospital, comes
## out with its shut-in dead, shrugs off blows below the head, can't be kicked
## down or killed silently, goes wild past half its health, hands everyone who
## hurt it its drops, and stays dead a while before another takes its place.


func _aim_at(pos: Vector2) -> void:
	me.aim = pos - (me.position + Look.CHEST)


func _hit(z: Zombie, dy: float, kind := Look.PUNCH_L, stats := []) -> float:
	var hp0 := z.hp
	z.stun = 0.0
	_aim_at(z.position + Vector2(0, dy))
	main.combat._resolve_melee(me, kind, main.combat.PUNCH if stats.is_empty() else stats)
	return hp0 - z.hp


func _bosses() -> Array:
	return main.zombies.values().filter(func(z): return z.kind == "sergeant")


func run() -> void:
	var bad := Bosses.problems()
	check(bad.is_empty(), "the boss table is filled in correctly" + ("" if bad.is_empty() else ": " + "; ".join(bad)))
	check(Items.problems().is_empty(), "and its drops are real items")
	var zid := Bosses.zid_for(12, "sergeant")
	check(Zombie.kind_for(zid) == "sergeant" and Bosses.is_zid(zid), "a boss's id says which boss it is, on every screen")
	check(range(0, 5000).all(func(i): return not Zombie.KINDS[Zombie.kind_for(i)].get("boss", false)), "no ordinary zombie turns out a boss")

	SaveGame.wipe()
	await host(9376)
	main.spawn_timer = 1e9
	var w: World = main.world
	var hosp := Bosses.lair(w, "sergeant")
	check(hosp >= 0 and w.buildings[hosp].kind == "hospital", "the zone's biggest hospital is its lair")
	if hosp < 0:
		return
	var rec: Dictionary = w.buildings[hosp]
	var marks: Array = main.bosses.map_marks()
	check(marks.size() == 1 and marks[0][0] == rec.rect.get_center() and marks[0][2] == 0.0, "the map marks its lair, boss at home (%s)" % [marks])

	# It comes out with the hospital's shut-in dead when someone comes near.
	Survival.trapped_on = true
	me.position = w.to_pos(rec.rect.get_center())
	main.survival._tick_trapped(1.1)
	var found := _bosses()
	check(found.size() == 1 and found[0].home == rec.id, "walking up to the hospital lets out its boss (%d)" % found.size())
	Survival.trapped_on = false
	if found.is_empty():
		return
	var z: Zombie = found[0]
	check(z.max_hp >= 200 and z.wear.get("over", "") == "vest" and z.wear.get("face", "") == "gasmask", "a big one in its gear: vest and gas mask (%s)" % [z.wear])

	# Somewhere clear to fight it: you, it a step away.
	for other in main.zombies.values():
		if other != z:
			other.queue_free()
	main.zombies = {z.zid: z}
	var spot := w.to_pos(w.spawn_cell)
	me.position = spot
	me.storey = 0
	var side := Vector2.RIGHT
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if w.can_stand(spot + d * 14.0, 5) and not main.combat._wall_between(spot, spot + d * 14.0, 0):
			side = d
			break
	z.position = spot + side * 14.0
	z.storey = 0
	z.lift = 0.0

	var head_dy := Proportions.head_line() * z.height - 3.0
	var body := _hit(z, -15.0)
	var head := _hit(z, head_dy)
	check(head > body * 4.0, "its gear stops blows to the body; the head is the way (%.1f vs %.1f)" % [head, body])
	for i in 20:
		_hit(z, -15.0, Look.KICK, main.combat.KICK)
	check(z.down_t <= 0.0 and z.missing == 0, "kicks don't put it down")
	me.sneak = true
	check(not Combat.can_backstab(me, z, "knife"), "no silent kill on a boss")
	me.sneak = false

	# Past half its health it goes wild.
	var calm := z.speed
	z.hp = z.max_hp * 0.4
	simulate(0.3)
	z.position = spot + side * 14.0
	check(z.enraged and z.speed > calm, "past half its health it comes on faster (%.0f -> %.0f)" % [calm, z.speed])

	# Killing it: everyone who hurt it gets its knife and the experience.
	var xp0: float = me.skills.get("combat", 0.0)
	me.inv.fill(null)
	z.hp = 1.0
	_hit(z, head_dy)
	check(not main.zombies.has(z.zid), "it dies")
	check(count(me, "armyknife") == 1, "and you get its army knife, your own (%s)" % bag(me))
	check(me.skills.get("combat", 0.0) >= xp0 + 400.0, "and the experience")
	# Its price: only a skilled hand can mend it.
	var knife: Dictionary = me.inv[me.inv.find(me.inv.filter(func(it): return it != null and it.id == "armyknife")[0])]
	knife.hp = 10
	me.inv[1] = Items.make("scrap")
	me.skills.craft = 0.0
	main.crafting.req_repair(["inv", me.inv.find(knife)])
	check(me.craft.is_empty(), "a new hand can't mend the army knife")
	me.skills.craft = Skills.xp_for(20)
	main.crafting.req_repair(["inv", me.inv.find(knife)])
	check(not me.craft.is_empty(), "craft level 20 can (with scrap)")
	me.craft = {}
	check(main.world_state.state("building", rec.id).has("boss_sergeant"), "the hospital remembers when its boss died")
	marks = main.bosses.map_marks()
	check(marks[0][2] > 47.0, "the map says it's dead, back in %.0f game hours" % marks[0][2])

	# It stays dead a while, then another takes its place.
	main.survival.clear_trapped()
	Survival.trapped_on = true
	me.position = w.to_pos(rec.rect.get_center())
	main.survival._tick_trapped(1.1)
	check(_bosses().is_empty(), "coming back soon after: no boss")
	main.survival.clear_trapped()
	main.day += 3
	main.survival._tick_trapped(1.1)
	check(_bosses().size() == 1, "two game days on, another has taken its place")
	Survival.trapped_on = false
