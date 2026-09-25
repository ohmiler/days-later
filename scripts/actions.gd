class_name Actions
extends Node
## What E does: the server side of the interaction system (see Interact for what is possible).
## Split out of main.gd; shared state (world, players, zombies, pickups) lives there.

var main: Main


## E tapped: do the main action on whatever is in reach.
@rpc("any_peer", "call_remote", "reliable")
func req_interact() -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.sleeping:
		return
	var t := Interact.target(main, p)
	var a := Interact.primary(Interact.actions(main, p, t))
	if a.is_empty():
		return
	if a.ok:
		_do_action(p, t, a.verb)
	else:
		main._toast(p, a.why)


## A specific action chosen from the hold-E wheel. The server checks the target
## is still in reach and the action still possible before doing it.
@rpc("any_peer", "call_remote", "reliable")
func req_act(kind: String, id: Variant, verb: String) -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.sleeping:
		return
	var t := Interact.resolve(main, p, kind, id)
	var a := Interact.find_action(Interact.actions(main, p, t), verb)
	if a.is_empty():
		return
	if a.ok:
		_do_action(p, t, verb)
	else:
		main._toast(p, a.why)


## Z: lie down where you are (or get up again).
@rpc("any_peer", "call_remote", "reliable")
func req_sleep() -> void:
	var p := main._sender()
	if p == null or not p.alive():
		return
	if p.sleeping:
		p.sleeping = false
		return
	var why: String = main.survival.can_sleep(p)
	if why != "":
		main._toast(p, why)
		return
	main.survival.start_sleep(p, -1)


func _do_action(p: Player, t: Dictionary, verb: String) -> void:
	if t.get("kind") == "thing":
		main.things.act(p, t.id, verb)
		return
	match verb:
		"up", "down":
			p.on_roof = verb == "up"
			p.position = main.world.to_pos(t.id)
			main.fx_sound.rpc("door", p.position)
			main._toast(p, "ขึ้นมาบนดาดฟ้า · ซอมบี้ตามขึ้นมาไม่ได้" if p.on_roof else "ลงมาข้างล่าง")
		"jump":
			var drop := Interact.jump_spot(main.world, p.position)
			if drop == Vector2.INF:
				return
			p.on_roof = false
			p.position = drop
			p.take_damage(10)
			main.fx_sound.rpc("kick", drop)
			main._make_noise(drop, main.NOISE_RUN)
			main._toast(p, "กระโดดลงมา! เจ็บขา")
		"take":
			var item: Dictionary = main.pickups[t.id].item
			var took := false
			if item.get("n", 1) > 1 or Items.is_weapon(item.id):
				for i in p.inv.size():
					if p.inv[i] == null:
						p.inv[i] = item.duplicate()
						took = true
						break
			else:
				took = main.inventory._give(p, item.id)
			if not took:
				main._toast(p, "กระเป๋าเต็ม")
				return
			main.pickup_del.rpc(t.id)
			main.fx_sound.rpc("pickup", p.position)
			main._toast(p, "เก็บ %s" % Items.display_name(item.id))
			main.inventory._send_inv(p)
		"take_trap":
			var kind: String = main.world.doors[t.id].kind
			if not main.inventory._give(p, kind):
				main._toast(p, "กระเป๋าเต็ม")
				return
			main.doors.door_state.rpc(t.id, false, -1.0, 0, true)  # hp -1: picked up, draw nothing
			main.fx_sound.rpc("pickup", p.position)
			main._toast(p, "เก็บ%sคืน" % World.BUILDS[kind].name)
			main.inventory._send_inv(p)
		"open", "close", "smash":
			main.doors._toggle_door(p, t.id)
		"board", "repair":
			main.doors._reinforce(p, t.id)
		"stomp":
			var z: Zombie = main.zombies.get(t.id)
			if z == null or z.down_t <= 0.0:
				return
			main.combat.fx_melee.rpc(p.peer_id, Look.KICK)
			main._make_noise(z.position, main.NOISE_HIT)
			main.combat.fx_hit.rpc(z.zid, z.position, Vector2.DOWN, true, p.peer_id, "", z.hp)
			main.combat._kill_zombie(z, 1.0 if z.position.x >= p.position.x else -1.0, "stomp")
			p.kills += 1
		"sleep":
			main.survival.start_sleep(p, t.id)
		"claim":
			p.bed = t.id
			main.fx_sound.rpc("rustle", p.position)
			main._toast(p, "เตียงนี้เป็นของคุณแล้ว · ถ้าตาย คนใหม่จะตื่นที่นี่")
		"look":
			main.fx_sound.rpc("rustle", main.world.container_nodes[t.id].position)
			main.inventory._open_box(p, t.id)
		"search":
			var f: FurnitureProp = main.world.container_nodes[t.id]
			p.search_id = t.id
			p.search_t = main.inventory.SEARCH_TIME
			main.fx_sound.rpc("rustle", f.position)
			main._make_noise(f.position, main.NOISE_SEARCH)
			main._notify(p.peer_id, &"search_started", [main.inventory.SEARCH_TIME])
