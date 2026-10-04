extends "res://tests/test_base.gd"
## What you had stays with your body (Remains): a bundle where you fell for an
## hour, that only you can take back (E: everything at once, the clothes on
## again); it's saved with the world and gone when its hour is up. Turning,
## the clothes stay on the zombie and the bag with the body.
## Leaving mid-danger (Net): the body stays LINGER seconds, it can die there,
## coming back in time carries on in it; leaving when safe is at once; dead
## when saved, skills and quests are still yours.


func _act(p: Player, verb: String) -> bool:
	var t := Interact.target(main, p)
	if t.get("kind", "") != "remains":
		return false
	for a in Interact.actions(main, p, t):
		if a.verb == verb and a.ok:
			main.actions._do_action(p, t, verb)
			return true
	return false


func _clear_spot() -> Vector2:
	return main.world.to_pos(main.world.spawn_cell)


func run() -> void:
	SaveGame.wipe()
	await host(9561)
	main.spawn_timer = 1e9
	var w: World = main.world
	var spot := _clear_spot()
	me.position = spot
	me.pname = "Tester"
	main.inventory._give(me, "bandage")
	main.inventory._give(me, "water")
	me.worn["body"] = Items.make("jacket")
	me.refresh_wear()
	main.inventory._send_inv(me)
	var n_pickups: int = main.pickups.size()

	# Dying: everything into a bundle where you fell, nothing scattered.
	me.take_damage(9999)
	simulate(0.1)
	check(main.remains.seen.size() == 1, "a bundle where you fell (%d)" % main.remains.seen.size())
	check(main.pickups.size() == n_pickups, "nothing scattered on the ground")
	check(me.inv.all(func(it): return it == null) and me.worn.is_empty(), "nothing left on you")
	var rid: int = main.remains.seen.keys()[0]
	var r: Dictionary = main.remains.seen[rid]
	check(r.owner == "Tester" and r.pos.distance_to(spot) < 1.0, "yours, where you fell")
	check(main.remains.title(rid).contains("60 นาที"), "it keeps for an hour (%s)" % main.remains.title(rid))
	check(main.remains.map_marks("Tester").size() == 1 and main.remains.map_marks("Someone").is_empty(), "on your map, not on anyone else's")

	# Someone else can't take it.
	var other: Player = main._add_player(60)
	other.pname = "Other"
	other.position = spot + Vector2(4, 0)
	check(Interact.target(main, other).get("kind", "") == "remains", "someone else sees it in reach")
	check(not _act(other, "reclaim"), "but can't take it")
	main.remains.take(other, rid)
	check(main.remains.seen.has(rid) and other.inv.all(func(it): return it == null), "not even by asking the server")
	other.position = spot + Vector2(400, 0)

	# Back for it: everything at once, the jacket on again.
	simulate(Player.RESPAWN_TIME + 0.2)
	check(me.alive(), "back as a new survivor")
	me.position = spot + Vector2(3, 0)
	check(_act(me, "reclaim"), "E on your own bundle: take it all back")
	check(main.remains.seen.is_empty(), "the bundle is gone")
	check(count(me, "bandage") == 1 and count(me, "water") == 1, "the bag's things are back (%s)" % bag(me))
	check(me.worn.get("body", {}).get("id", "") == "jacket", "and the jacket is on again")

	# A full bag: what won't fit is left at your feet.
	me.take_damage(9999)
	simulate(0.1)
	simulate(Player.RESPAWN_TIME + 0.2)
	me.position = spot + Vector2(3, 0)
	me.worn["body"] = Items.make("tshirt")
	for i in me.inv.size():
		me.inv[i] = Items.make("rag")
	var before: int = main.pickups.size()
	check(_act(me, "reclaim"), "a full bag: still taken")
	check(main.pickups.size() == before + 3, "the jacket (a t-shirt on already) and the rest at your feet (%d)" % (main.pickups.size() - before))

	# Its hour up: gone, and what was in it.
	for i in me.inv.size():
		me.inv[i] = null
	main.inventory._give(me, "bandage")
	me.take_damage(9999)
	simulate(0.1)
	rid = main.remains.seen.keys()[0]
	main.remains.seen[rid].ends = Remains.now() - 1.0
	main.remains._t = 0.0
	main.remains.server_tick(0.1)
	check(main.remains.seen.is_empty() and main.remains.items.is_empty(), "an hour on, it's gone")
	simulate(Player.RESPAWN_TIME + 0.2)

	# Turning: the clothes stay on the zombie, the bag with the body.
	me.position = spot
	me.worn["body"] = Items.make("jacket")
	me.refresh_wear()
	main.inventory._give(me, "bandage")
	main.survival._turn(me)
	check(main.remains.seen.size() == 1, "turned: the bag's things in a bundle")
	rid = main.remains.seen.keys()[0]
	check(main.remains.items[rid].worn.is_empty() and main.remains.items[rid].inv.size() == 1, "the clothes went with the zombie")
	simulate(Player.RESPAWN_TIME + 0.2)

	# Saved with the world, still yours after a restart.
	main._save_all()
	await close_game()
	await host(9562, true, false)
	main.spawn_timer = 1e9
	check(main.remains.seen.size() == 1 and main.remains.seen.values()[0].owner == "Tester", "saved with the world: still there after a restart")
	check(main.remains.items.values()[0].inv.size() == 1, "with what was in it")

	# Leaving in the middle of a fight: the body stays.
	main.remains.clear()
	var spot2 := _clear_spot()
	var q: Player = main._add_player(61)
	q.pname = "Runner"
	q.secret_hash = "abc".sha256_text()
	q.position = spot2
	q.hp = 70.0
	var z := zombie_at(spot2 + Vector2(40, 0))
	z.target = q
	main.net._on_peer_disconnected(61)
	check(main.players.has(61) and q.linger > 0.0, "left with a zombie after them: the body stays")
	main.net.tick_lingering(Net.LINGER * 0.5)
	check(main.players.has(61), "...a while")
	# Back in time: the same body, not a new one.
	var back: Player = main._add_player(62)
	main.net._claim_name(back, "Runner", "abc")
	check(back.pname == "Runner" and not main.players.has(61), "back in time: the name is still theirs, the old body taken up")
	check(back.position.distance_to(spot2) < 1.0 and is_equal_approx(back.hp, 70.0), "carrying on where it stood, as hurt as it was")
	# Gone too long: saved and taken out.
	main.net._on_peer_disconnected(62)
	check(main.players.has(62), "left again, still in danger: stays")
	main.net.tick_lingering(Net.LINGER + 1.0)
	check(not main.players.has(62), "the time runs out: the body is gone")
	# Dying while it stands there: the bundle, then gone.
	z.queue_free()
	main.zombies.erase(z.zid)
	var d: Player = main._add_player(63)
	d.pname = "Unlucky"
	d.position = spot2
	main.inventory._give(d, "bandage")
	d.hurt_at = Time.get_ticks_msec() / 1000.0
	main.net._on_peer_disconnected(63)
	check(d.linger > 0.0, "just hurt counts as danger too")
	d.take_damage(9999)
	simulate(0.1)
	check(not main.players.has(63), "killed while standing there: gone")
	check(main.remains.map_marks("Unlucky").size() == 1, "with their things left at the body")
	# Leaving when it's quiet: at once.
	var calm: Player = main._add_player(64)
	calm.pname = "Calm"
	calm.position = spot2 + Vector2(3000, 0)
	main.net._on_peer_disconnected(64)
	check(not main.players.has(64), "leaving when nothing is near: gone at once")
	# Dead when saved: skills and quests still theirs.
	var vet: Player = main._add_player(65)
	vet.pname = "Veteran"
	vet.secret_hash = "vet".sha256_text()
	vet.skills = {combat = 900.0}
	vet.quests = {active = {}, done = {intro_camp = true}, day = -1}
	vet.take_damage(9999)
	SaveGame.save_player(vet)
	main.players.erase(65)
	vet.queue_free()
	var vet2: Player = main._add_player(66)
	main.net._claim_name(vet2, "Veteran", "vet")
	check(vet2.skills.get("combat", 0.0) == 900.0 and vet2.quests.get("done", {}).has("intro_camp"), "saved dead: a new survivor, but their skills and quests are kept")
