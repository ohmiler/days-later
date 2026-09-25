class_name Doors
extends Node
## Doors, windows and traps: opening, shutting, boarding, repairing, breaking.
## Split out of main.gd; shared state (world, players, zombies, pickups) lives there.

var main: Main


## A zombie pounds on a door (server).
func damage_door(id: int, dmg: float) -> void:
	var d: Dictionary = main.world.doors[id]
	if not d.closed:
		return
	var hp: float = d.hp - dmg
	# Boards take the beating first; each one splinters off as its share runs out.
	var base_hp := World.WINDOW_HP if main.world.is_window(id) else World.DOOR_HP
	var boards: int = mini(d.boards, maxi(0, ceili((hp - base_hp) / World.BOARD_HP)))
	var pos := main.world.to_pos(d.cell)
	if hp <= 0.0 and main.world.is_window(id):
		door_state.rpc(id, false, 0.0, 0, true)  # glass and boards gone: now a hole to climb through
		main.fx_sound.rpc("break", pos)
		main._make_noise(pos, main.NOISE_BREAK)
	elif hp <= 0.0:
		door_state.rpc(id, false, 0.0, 0, true)
		main.fx_sound.rpc("break", pos)
		main._make_noise(pos, main.NOISE_BREAK)
	else:
		door_state.rpc(id, true, hp, boards, false)
		main.fx_sound.rpc("door", pos)
		main._make_noise(pos, main.NOISE_HIT)


@rpc("authority", "call_local", "reliable")
func door_state(id: int, closed: bool, hp: float, boards: int, broken: bool) -> void:
	main.world.set_door(id, closed, hp, boards, broken)
	var me: Player = main.players.get(multiplayer.get_unique_id())
	if closed and me and not multiplayer.is_server() and main.world.door_overlap(id, me.position) > 0:
		me.position = main.world.nudge_out_of_door(id, me.position)


@rpc("any_peer", "call_remote", "reliable")
func req_reinforce() -> void:
	var p := main._sender()
	if p == null or not p.alive():
		return
	var t := Interact.target(main, p)
	var list := Interact.actions(main, p, t)
	# R is also reload: with a gun in hand and no door to board, that's what it does.
	var board := Interact.find_action(list, "board")
	var fix := Interact.find_action(list, "repair")
	if p.gun_hand() != "" and not (not board.is_empty() and board.ok) and not (not fix.is_empty() and fix.ok):
		main.crafting._reload(p)
		return
	for verb in ["board", "repair"]:
		var a := Interact.find_action(list, verb)
		if not a.is_empty():
			if a.ok:
				main.actions._do_action(p, t, verb)
			else:
				main._toast(p, a.why)
			return


## Nail a board across a door or window, or repair a broken door (server).
func _reinforce(p: Player, id: int) -> void:
	var slot := -1
	for i in p.inv.size():
		if p.inv[i] != null and p.inv[i].id == "wood":
			slot = i
	if slot < 0:
		main._toast(p, "ต้องมีไม้กระดาน")
		return
	var d: Dictionary = main.world.doors[id]
	if main.world.is_window(id) and not d.closed:
		door_state.rpc(id, true, World.BOARD_HP, 1, false)
		main._toast(p, "ตอกไม้ปิดหน้าต่าง (1/%d)" % World.MAX_BOARDS)
	elif d.broken:
		door_state.rpc(id, false, World.DOOR_HP, 0, false)
		main._toast(p, "ซ่อมประตูแล้ว")
	elif d.boards >= World.MAX_BOARDS:
		main._toast(p, "ตอกไม้เต็มแล้ว")
		return
	else:
		var base_hp := World.WINDOW_HP if main.world.is_window(id) else World.DOOR_HP
		var nb: int = d.boards + 1  # read before door_state updates `d` in place
		door_state.rpc(id, d.closed, minf(d.hp + World.BOARD_HP, base_hp + nb * World.BOARD_HP), nb, false)
		main._toast(p, "ตอกไม้เสริม%s (%d/%d)" % ["หน้าต่าง" if main.world.is_window(id) else "ประตู", nb, World.MAX_BOARDS])
	p.inv[slot].n -= 1
	if p.inv[slot].n <= 0:
		p.inv[slot] = null
	main.fx_sound.rpc("door", p.position)
	main._make_noise(p.position, main.NOISE_SWING)  # hammering is loud
	main.inventory._send_inv(p)


func _toggle_door(p: Player, id: int) -> void:
	var d: Dictionary = main.world.doors[id]
	if main.world.is_built(id):
		return
	if main.world.is_window(id):
		if d.closed and d.boards == 0:
			door_state.rpc(id, false, 0.0, 0, true)
			main.fx_sound.rpc("glass", main.world.to_pos(d.cell))
			main._make_noise(main.world.to_pos(d.cell), main.NOISE_BREAK)
			main._toast(p, "ทุบกระจกแล้ว ปีนผ่านได้ (ช้า)")
		elif d.closed:
			main._toast(p, "หน้าต่างตอกไม้ปิดไว้")
		return
	if d.broken:
		main._toast(p, "ประตูพัง ต้องซ่อมด้วยไม้กระดาน [R]")
		return
	if not d.closed:
		# Never shut it on someone standing in the doorway; anyone just
		# brushing its edge gets eased out to their own side first.
		for q: Player in main.players.values():
			if q.alive() and not q.on_roof and main.world.door_overlap(id, q.position) == 2:
				main._toast(p, "ออกจากช่องประตูก่อนปิด" if q == p else "มีคนยืนขวางประตูอยู่")
				return
		for z: Zombie in main.zombies.values():
			if main.world.door_overlap(id, z.position) == 2:
				main._toast(p, "มีซอมบี้ขวางประตูอยู่!")
				return
		for q: Player in main.players.values():
			if q.alive() and not q.on_roof and main.world.door_overlap(id, q.position) == 1:
				q.position = main.world.nudge_out_of_door(id, q.position)
		for z: Zombie in main.zombies.values():
			if main.world.door_overlap(id, z.position) == 1:
				z.position = main.world.nudge_out_of_door(id, z.position)
	door_state.rpc(id, not d.closed, d.hp, d.boards, false)
	main.fx_sound.rpc("door_close" if d.closed else "door_open", main.world.to_pos(d.cell))


## Spikes stab and stagger whatever steps on them; barbed wire cuts while you're in it.
func _tick_traps(delta: float) -> void:
	for z: Zombie in main.zombies.values():
		z.trap_cd -= delta
		var id: int = main.world.door_at.get(main.world.to_cell(z.position), -1)
		if id < 0 or not main.world.is_built(id) or main.world.doors[id].broken:
			continue
		var d: Dictionary = main.world.doors[id]
		var hit := 0.0
		var wear := 0.0
		if d.kind == "spikes" and z.trap_cd <= 0.0:
			z.trap_cd = 1.0
			z.stun = 0.4
			hit = 25.0
			wear = 1.0
		elif d.kind == "wire":
			hit = 5.0 * delta
			wear = 3.0 * delta
		if hit <= 0.0:
			continue
		z.hp -= hit
		var hp: float = d.hp - wear
		if hp <= 0.0:
			door_state.rpc(id, false, 0.0, 0, true)
		elif d.kind == "spikes" or int(hp) != int(d.hp):
			door_state.rpc(id, d.closed, hp, 0, false)
		else:
			d.hp = hp  # small wire wear: sync on whole points only
		if d.kind == "spikes":
			main.combat.fx_hit.rpc(z.zid, z.position, Vector2.UP, false, 0, "knife", 25.0)
		if z.hp <= 0.0:
			main.combat._kill_zombie(z, 1.0, d.kind)


## Set the selected trap down on the ground just in front of you (server).
func _place_trap(p: Player, it: Dictionary) -> void:
	if p.on_roof:
		main._toast(p, "วางกับดักบนหลังคาไม่ได้")
		return
	var cell := main.world.to_cell(p.position + p.aim.normalized() * 14.0)
	if not main.world.can_build(cell):
		main._toast(p, "วางตรงนี้ไม่ได้")
		return
	var id: int = main.world.door_at.get(cell, main.world.doors.size())
	build_add.rpc(id, cell, it.id, World.BUILDS[it.id].hp)
	it.n -= 1
	if it.n <= 0:
		p.inv[p.sel] = null
	main.fx_sound.rpc("door", main.world.to_pos(cell))
	main._toast(p, "วาง%sแล้ว" % Items.display_name(it.id))
	main.inventory._send_inv(p)


@rpc("authority", "call_local", "reliable")
func build_add(id: int, cell: Vector2i, kind: String, hp: float) -> void:
	main.world.add_structure(id, cell, kind, hp)
