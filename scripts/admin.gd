class_name Admin
extends Node
## Developer tools (F2, the host only): conjure items, heal, bring zombies or
## clear them, change the time. For testing without walking the city for
## hours. The server only obeys the host player, or anyone when started with
## `-- --admin` (a test server).

var main: Main
var frozen := false  # zombies stand still (no thinking at all) while the admin looks around


func _allowed(p: Player) -> bool:
	return p != null and (p.peer_id == 1 or "--admin" in OS.get_cmdline_user_args())


## Started as a test copy: `-- --admin`, or in the browser with ?admin in the
## address. (It only opens the panel here; the server still decides: see _allowed.)
static func asked_for() -> bool:
	if "--admin" in OS.get_cmdline_user_args():
		return true
	if OS.has_feature("web"):
		return "admin" in str(JavaScriptBridge.eval("window.location.search", true))
	return false


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
			main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 6), Items.make(id), p.storey)
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


## `n` zombies of `kind` around `pos`; `special`: in one of the rare costumes
## (Items.SPECIALS). Kind and costume both come from the id, so skip ids until one fits.
@rpc("any_peer", "call_remote", "reliable")
## `dummy`: stands still facing away from you, thinking nothing (for trying
## blows, silent kills and deaths on).
func req_zombie(pos: Vector2, kind: String, n := 1, special := false, dummy := false) -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	if Zombie.KINDS.get(kind, {}).get("boss", false):
		# A boss's id says which it is (Bosses): one not from any building.
		for i in clampi(n, 1, 5):
			var z := main._add_zombie(Bosses.zid_for(100000 + main.next_zid, kind), pos + Vector2(i * 14.0, 0))
			z.storey = p.storey
			main.next_zid += 1
		return
	for i in clampi(n, 1, 50):
		for tries in 200000:
			var ok := kind == "" or not Zombie.KINDS.has(kind) or Zombie.kind_for(main.next_zid) == kind
			if ok and special:
				ok = Items.zombie_wear(main.next_zid).values().any(func(k): return Items.def(Items.base_id(k)).get("special", false))
			if ok:
				break
			main.next_zid += 1
		var at := pos + (Vector2.from_angle(randf() * TAU) * randf_range(0, 14.0 * sqrt(n)) if n > 1 else Vector2.ZERO)
		if not main.world.can_stand(at, 5):
			at = pos
		var z := main._add_zombie(main.next_zid, at)
		z.storey = p.storey
		if dummy:
			z.dummy = true
			z.facing = (at - p.position).angle()  # (its back to you)
		main.next_zid += 1


## A car beside you (trial), facing the way you look.
@rpc("any_peer", "call_remote", "reliable")
func req_car() -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	var dir := p.aim.normalized() if p.aim.length() > 0.1 else Vector2.RIGHT
	main.vehicles.spawn_car(p.position + dir * 50.0, dir.angle())


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


## A switch on the admin's own character or the world: "god", "freeze", "rain".
@rpc("any_peer", "call_remote", "reliable")
func req_toggle(what: String) -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	match what:
		"god":
			p.god = not p.god
			main._toast(p, "อมตะ: " + ("เปิด" if p.god else "ปิด"))
		"freeze":
			frozen = not frozen
			main._toast(p, "ซอมบี้หยุดนิ่ง: " + ("เปิด" if frozen else "ปิด"))
		"rain":
			main.survival._set_rain(not main.raining)
			main.survival.rain_t = 600.0
			main._toast(p, "ฝนตก" if main.raining else "ฝนหยุด")


## Do something to yourself, to try a system out: a wound (Body.KINDS), a
## condition (Body.CONDITIONS), hungry, thirsty, worn out, infected.
@rpc("any_peer", "call_remote", "reliable")
func req_self(what: String, arg: String) -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	match what:
		"wound":
			if Body.KINDS.has(arg):
				var part: String = {bite = "arms", scratch = "arms", sprain = "legs", bruise = "torso"}.get(arg, "torso")
				Body.add(p, arg, part, arg == "bite")
				if arg == "bite":
					p.bleeding = true
		"fester":
			for w in p.wounds:
				if w.kind in ["bite", "scratch"]:
					w.festering = true
					p.body_dirty = true
					break
		"condition":
			if Body.CONDITIONS.has(arg):
				main._toast(p, Body.add_condition(p, arg, main.now()))
		"hungry":
			p.hunger = 5.0
		"thirsty":
			p.thirst = 5.0
		"tired":
			p.stamina = 0.0
		"infect":
			p.infection = minf(99.0, p.infection + 50.0)
		"cure":
			p.conditions.clear()
			p.wounds.clear()
			p.infection = 0.0
			p.bleeding = false
			p.body_dirty = true
	main._toast(p, "แอดมิน: " + what + (" " + arg if arg != "" else ""))


## Go to the nearest big building of a kind (hospital, mall...), or a zone exit.
@rpc("any_peer", "call_remote", "reliable")
func req_goto(kind: String) -> void:
	var p := main._sender()
	if not _allowed(p) or p.riding >= 0:
		return
	var w: World = main.world
	var best := Vector2.INF
	for rec: Dictionary in w.buildings:
		if rec.kind != kind:
			continue
		var r: Rect2i = rec.rect
		var door := Vector2(r.get_center().x, r.end.y + 1) * World.TILE + Vector2(World.TILE, World.TILE) * 0.5
		if best == Vector2.INF or door.distance_to(p.position) < best.distance_to(p.position):
			best = door
	if best == Vector2.INF:
		main._toast(p, "โซนนี้ไม่มี " + kind)
		return
	for i in 40:
		var at := best + Vector2(i % 7 - 3, i / 7) * 8.0
		if w.can_stand(at, 5):
			best = at
			break
	p.storey = 0
	p.on_roof = false
	p.position = best
	p.net_pos = best
	main._toast(p, "วาร์ปไป " + kind)


## Skip the clock forward (hours of game time): things that go by the clock
## (food going off, generators, conditions) all move on.
@rpc("any_peer", "call_remote", "reliable")
func req_skip(hours: float) -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	main.time += hours / 24.0
	while main.time >= 1.0:
		main.time -= 1.0
		main.day += 1
		main.restock.new_day(main.day)
	main._toast(p, "ข้ามเวลา %d ชม." % int(hours))


@rpc("any_peer", "call_remote", "reliable")
func req_horde() -> void:
	var p := main._sender()
	if not _allowed(p):
		return
	main.survival.horde_started = -99
	for i in 30:
		main.survival._spawn_horde_zombie()
	main.survival.fx_announce.rpc("ฝูงซอมบี้มาแล้ว! (แอดมิน)", true)
