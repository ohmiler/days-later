extends "res://tests/test_base.gd"
## Floors counted, not flagged: which storey someone is on goes over the
## network and into the saves as a number, and the stairs work for any number
## of floors (a third floor made by hand here, as later buildings will have).


func _verbs(t: Dictionary) -> Dictionary:
	var out := {}
	for a in Interact.actions(main, me, t):
		out[a.verb] = a.label
	return out


## A shophouse with a floor upstairs and stairs.
func _upper_building(w: World) -> Dictionary:
	for rec in w.buildings:
		if rec.get("upper", false) and rec.has("stairs"):
			return rec
	return {}


func run() -> void:
	SaveGame.wipe()
	seed(8)
	await host(9612)
	main.spawn_timer = 1e9
	var w: World = main.world
	var b := _upper_building(w)
	check(not b.is_empty(), "there is a shophouse with a floor upstairs")
	var st: Vector2i = b.stairs
	var at := w.to_pos(st)

	# --- The network carries the storey as a number. ---
	var z := zombie_at(at + Vector2(0, 30))
	z.storey = 3
	z.missing = Look.LOST_ARM_R
	z.flags = 1 | 2 | 8
	var buf := StreamPeerBuffer.new()
	buf.data_array = NetCodec.zombie_bytes(z)
	var dz := NetCodec.get_zombie(buf)
	check(dz.storey == 3 and dz.missing == Look.LOST_ARM_R and dz.flags == 11,
			"a zombie on the fourth floor packs and unpacks (%s)" % dz)
	z.flags = 0
	buf.data_array = NetCodec.zombie_bytes(z)
	check(NetCodec.get_zombie(buf).flags & 4 == 0, "being upstairs is no longer flag 4")
	z.storey = 1
	z.server_tick(1.0 / 60.0)
	check(z.flags & 4 == 0, "and the server no longer sets it")
	var was := NetCodec.zombie_bytes(z)
	z.storey = 2
	check(NetCodec.nudge(was, NetCodec.zombie_bytes(z)).is_empty(), "a zombie that changed floor goes in full, not as a nudge")
	z.queue_free()
	main.zombies.erase(z.zid)
	me.storey = 3
	buf = StreamPeerBuffer.new()
	NetCodec.put_player(buf, me)
	buf.seek(0)
	var dp := NetCodec.get_player(buf)
	check(dp.storey == 3 and not dp.has("up"), "a player on the fourth floor packs and unpacks (%s)" % dp.get("storey"))
	me.storey = 0

	# --- Old saves (a flag for upstairs) come up to storeys. ---
	var oldp := SaveGame._player_12_to_13({up = true})
	check(oldp.get("storey") == 1 and not oldp.has("up"), "an old player save upstairs is on storey 1")
	var oldw := SaveGame._world_12_to_13({pickups = [[0, Vector2.ZERO, {}, true]], corpses = [[1, Vector2.ZERO, 0.0, {}, "", 0.0, -1.0, false]],
			zombies = [[2, Vector2.ZERO, 10.0, {}, 0]]})
	check(typeof(oldw.pickups[0][3]) == TYPE_INT and oldw.pickups[0][3] == 1 and typeof(oldw.corpses[0][7]) == TYPE_INT and oldw.corpses[0][7] == 0 \
			and oldw.zombies[0].size() == 6 and oldw.zombies[0][5] == 0, "an old world save's pickups, bodies and zombies get storeys")

	# --- Saves keep the storey: player, zombie, pickup, body. ---
	var up_cell := Vector2i(-9999, -9999)
	for c in w.storey_map(1):
		if c != st and b.rect.has_point(c) and not w.is_solid_on(c, 1):
			up_cell = c
			break
	check(up_cell.x != -9999, "a free cell upstairs")
	var zu := zombie_at(w.to_pos(up_cell))
	zu.storey = 1
	var zid := zu.zid
	main._spawn_pickup(w.to_pos(up_cell), {id = "rag", n = 1, hp = 0}, 1)
	main.add_corpse(w.to_pos(up_cell), 1.0, zu.body_look(), "", 1)
	var cid: int = main.corpses.keys().max()
	me.position = at
	me.storey = 1
	main._save_all()
	await close_game()
	await host(9613, true, false)
	main.spawn_timer = 1e9
	w = main.world
	check(me.storey == 1 and me.position.distance_to(at) < 1.0, "the player comes back upstairs (storey %d)" % me.storey)
	check(main.zombies.has(zid) and main.zombies[zid].storey == 1, "the zombie comes back upstairs")
	var rags: Array = main.pickups.values().filter(func(pu): return pu.item.id == "rag")
	check(rags.size() == 1 and rags[0].storey == 1, "the thing dropped upstairs comes back upstairs")
	check(main.corpses.has(cid) and main.corpses[cid].storey == 1, "the body upstairs comes back upstairs")
	var node: Corpse = main.corpse_nodes.get(cid)
	check(node != null and node.storey == 1, "and is drawn up there")
	for zz in main.zombies.values():
		zz.queue_free()
	main.zombies.clear()

	# --- A third floor: the stairs go on up to it, and the roof above that. ---
	var f2 := w.storey_map(2)
	for c in [st, st + Vector2i.LEFT, st + Vector2i.RIGHT]:
		f2[c] = World.FLOOR
	var t := {kind = "stairs", id = st, pos = at}
	me.position = at
	me.storey = 1
	me.on_roof = false
	var v := _verbs(t)
	check(v.get("up") == "ขึ้นชั้น 3" and v.get("down") == "ลงชั้นล่าง", "on the first floor: up to the third, down to the ground (%s)" % v)
	main.actions._do_action(me, t, "up")
	check(me.storey == 2 and not me.on_roof, "up the stairs to the third floor, not the roof (storey %d)" % me.storey)
	check(w.can_stand(at, Player.RADIUS * 0.5, false, false, 2) and w.is_solid_on(st + Vector2i(0, 2), 2), "up there, only its own floor is floor")
	v = _verbs(t)
	check(v.get("up") == "ขึ้นดาดฟ้า" and v.get("down") == "ลงชั้น 2", "on the third floor: up to the roof, down to the second (%s)" % v)
	main.actions._do_action(me, t, "up")
	check(me.on_roof and me.storey == 0, "on up to the roof")
	v = _verbs(t)
	check(v.get("down") == "ลงชั้น 3", "from the roof, down to the third floor (%s)" % v)
	main.actions._do_action(me, t, "down")
	check(me.storey == 2 and not me.on_roof, "down from the roof to the third floor")
	main.actions._do_action(me, t, "down")
	check(me.storey == 1 and not me.on_roof, "down to the second")
	main.actions._do_action(me, t, "down")
	check(me.storey == 0 and not me.on_roof, "and down to the ground")
	w.storeys.erase(2)
	SaveGame.wipe()
