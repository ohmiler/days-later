class_name Admin
extends Node
## Developer tools (F2, the host only): conjure items, heal, bring zombies or
## clear them, change the time. For testing without walking the city for
## hours. The server only obeys the host player, or anyone when started with
## `-- --admin` (a test server).

var main: Main


func _allowed(p: Player) -> bool:
	return p != null and (p.peer_id == 1 or "--admin" in OS.get_cmdline_user_args())


@rpc("any_peer", "call_remote", "reliable")
func req_give(id: String, n: int) -> void:
	var p := main._sender()
	if not _allowed(p) or not Items.DEFS.has(id):
		return
	var given := 0
	for i in clampi(n, 1, 99):
		if main.inventory._give(p, id):
			given += 1
		else:
			main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 6), {id = id, n = 1, hp = Items.def(id).get("hp", 0)})
			given += 1
	main.inventory._send_inv(p)
	main._toast(p, "เสก %s ×%d" % [Items.display_name(id), given])


## Everything back to full: health, food, water, stamina; no wounds or infection.
@rpc("any_peer", "call_remote", "reliable")
func req_heal() -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	p.hp = Player.MAX_HP
	p.hunger = 100.0
	p.thirst = 100.0
	p.stamina = 100.0
	p.infection = 0.0
	p.bleeding = false
	p.exhausted = false
	p.wounds.clear()
	p.body_dirty = true
	main._toast(p, "รักษาเต็ม")


@rpc("any_peer", "call_remote", "reliable")
func req_zombie(pos: Vector2, kind: String) -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	# A zombie's kind comes from its id (so every machine agrees): skip ids until one fits.
	if kind != "" and Zombie.KINDS.has(kind):
		while Zombie.kind_for(main.next_zid) != kind:
			main.next_zid += 1
	main._add_zombie(main.next_zid, pos)
	main.next_zid += 1


## Remove every zombie within `radius` of you.
@rpc("any_peer", "call_remote", "reliable")
func req_clear(radius: float) -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	var n := 0
	for z: Zombie in main.zombies.values():
		if z.position.distance_to(p.position) < radius:
			main.zombies.erase(z.zid)
			z.queue_free()
			n += 1
	main._toast(p, "ลบซอมบี้ %d ตัว" % n)


## Jump the clock to a time of day (0..1: 0.25 morning, 0.5 noon, 0.8 night).
@rpc("any_peer", "call_remote", "reliable")
func req_time(t: float) -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	main.time = fposmod(t, 1.0)
	main._toast(p, "เปลี่ยนเวลา")
