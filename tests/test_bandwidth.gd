extends "res://tests/test_base.gd"
## What each player is sent a second (Net.build_snapshot, the packed snapshot
## they'd get): in a quiet street, and on a horde night with a full server,
## within BUDGET. Also that a snapshot reads back as it was written.

const BUDGET := 15.0  # KB a second to each player, the worst case (ROADMAP: network groundwork)


func _rate(seconds: float) -> float:
	var bytes := 0
	var t := 0.0
	while t < seconds:
		simulate(Main.SNAPSHOT_RATE)
		main.net.clock += Main.SNAPSHOT_RATE
		bytes += main.net.build_snapshot(me.peer_id).size() + 28  # (+ the rpc and websocket framing, roughly)
		t += Main.SNAPSHOT_RATE
	return bytes / seconds / 1024.0


func run() -> void:
	SaveGame.wipe()
	seed(2)
	await host(9526)
	main.spawn_timer = 1e9
	me.hp = 1e9

	# A snapshot reads back as it was written.
	var z := zombie_at(me.position + Vector2(30, 5))
	z.hp = 47.0
	z.missing = Look.LOST_ARM_L
	var b := StreamPeerBuffer.new()
	NetCodec.put_player(b, me)
	b.data_array = NetCodec.zombie_bytes(z)
	b.seek(0)
	var dz := NetCodec.get_zombie(b)
	check(dz.id == z.zid and dz.pos.distance_to(z.position) <= 0.5 and dz.hp == 47.0 and dz.missing == Look.LOST_ARM_L,
			"a zombie packs into %d bytes and back (%s)" % [NetCodec.ZOMBIE_BYTES, dz])
	me.prone = true
	me.aim = Vector2(0, -30)
	b = StreamPeerBuffer.new()
	NetCodec.put_player(b, me)
	var size := b.get_size()
	b.seek(0)
	var dp := NetCodec.get_player(b)
	check(dp.id == me.peer_id and dp.pos.distance_to(me.position) <= 0.5 and dp.prone and (dp.aim as Vector2).angle_to(me.aim) < 0.03,
			"a player packs into %d bytes and back" % size)
	me.prone = false

	# Played back smoothly: between two snapshots, in between; past the newest,
	# carried on a little; a zombie that only moved goes as a 7-byte nudge.
	var smp := []
	NetCodec.push(smp, 1.0, Vector2(0, 0))
	NetCodec.push(smp, 1.1, Vector2(10, 0))
	check(NetCodec.sample_at(smp, 1.05).is_equal_approx(Vector2(5, 0)), "half way between two snapshots, half way there")
	var ahead := NetCodec.sample_at(smp, 1.5)
	check(ahead.x > 10.0 and ahead.x <= 10.0 + 100.0 * NetCodec.EXTRAPOLATE + 0.01, "past the newest, carried on only a little (%.1f)" % ahead.x)
	var was := NetCodec.zombie_bytes(z)
	z.position += Vector2(3.5, -2.0)
	var nd := NetCodec.nudge(was, NetCodec.zombie_bytes(z))
	b = StreamPeerBuffer.new()
	b.data_array = nd
	var dn := NetCodec.get_nudge(b)
	check(nd.size() == 7 and dn.id == z.zid and dn.move.is_equal_approx(Vector2(3.5, -2.0)), "a step goes as a 7-byte nudge")
	z.hp -= 5.0
	check(NetCodec.nudge(was, NetCodec.zombie_bytes(z)).is_empty(), "hurt, it goes in full")
	z.queue_free()
	main.zombies.erase(z.zid)

	# A quiet street: forty zombies milling about.
	for i in 40:
		zombie_at(me.position + Vector2(randf_range(-400, 400), randf_range(-300, 300)))
	main.net.reset_peer(me.peer_id)
	simulate(0.5)
	var quiet := _rate(3.0)
	print("  quiet street, 40 zombies: %.1f KB/s" % quiet)
	check(quiet <= BUDGET * 0.5, "a quiet street is cheap (%.1f KB/s)" % quiet)

	# A horde night on a full server: eight players, 160 zombies all coming.
	for i in 7:
		var q: Player = main._add_player(100 + i)
		q.position = me.position + Vector2(2000 + i * 40, 0)  # (in the snapshots, out of the zombies' way)
		q.hp = 1e9
	for i in 120:
		zombie_at(me.position + Vector2(randf_range(-500, 500), randf_range(-400, 400)))
	for zz: Zombie in main.zombies.values():
		zz.target = me
	simulate(0.5)
	var horde := _rate(3.0)
	print("  horde night, 8 players, %d zombies: %.1f KB/s" % [main.zombies.size(), horde])
	check(horde <= BUDGET, "a horde night with a full server within %.0f KB/s (%.1f)" % [BUDGET, horde])
