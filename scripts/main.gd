extends Node2D
## Networking + game loop. The server is authoritative: clients send input,
## the server simulates everything and broadcasts snapshots.
##
## Run a dedicated server:  godot --headless -- --server
## Auto-join from the command line:  godot -- --join=127.0.0.1

const PORT := 9080
const DAY_LENGTH := 240.0
const MAX_ZOMBIES := 80
const SNAPSHOT_RATE := 0.05
const GUN_RANGE := 250.0
const GUN_DAMAGE := 34.0
const GUN_COOLDOWN := 0.25
# Melee: [range, damage, cooldown, stun, knockback]
const PUNCH := [18.0, 12.0, 0.35, 0.35, 2.5]
const KICK := [20.0, 22.0, 0.8, 0.7, 16.0]
const PUNCH_WINDUP := 0.08  # the hit lands when the fist is out, not on the click
const KICK_WINDUP := 0.18  # matches the foot snapping out in Look.kick_pose

var port := PORT  # override with -- --port=N
var world: World
var camera: Camera2D
var shade: CanvasModulate
var fx: Node2D
var ui: GameUI
var in_game := false  # false while the title menu shows a backdrop city
var backdrop_nodes: Array = []
var player_name := ""
var day := 1
var last_kills := 0
var dmg_numbers: Array = []  # [pos, text, crit, age]
var outfits := {}  # zid -> [shirt, pants, hair] for zombies that were players
var drip_t := 0.0
# Survival tuning, per second. A full stomach lasts about two in-game days.
const HUNGER_RATE := 100.0 / 480.0
const THIRST_RATE := 100.0 / 330.0  # Bangkok heat: water runs out faster
const INFECTION_RATE := 0.35
const STARVE_DAMAGE := 0.6
const BLEED_DAMAGE := 0.8
const BITE_INFECT_CHANCE := 0.2
const BITE_BLEED_CHANCE := 0.3
# How far each kind of noise carries, in pixels (a tile is 16).
const NOISE_WALK := 45.0
const NOISE_RUN := 115.0
const NOISE_SWING := 90.0
const NOISE_HIT := 130.0
const NOISE_SEARCH := 60.0
const NOISE_BREAK := 170.0
var sneak_toggle := false
# Horde nights: every HORDE_EVERY days the whole city comes for you.
const HORDE_EVERY := 3
const HORDE_MAX_ZOMBIES := 160
var horde_announced := -1  # day we last announced / started / ended, so each fires once
var horde_started := -1
var horde_ended := -1
var players := {}  # peer_id -> Player
var zombies := {}  # zid -> Zombie
var next_zid := 1
var world_seed := 0
var time := 0.3
var spawn_timer := 0.0
var snap_timer := 0.0
var tracers: Array = []  # [from, to, ttl]
var decals: Node2D
var blood: Array = []  # [pos, radius, colour] - stays on the ground
var sparks: Array = []  # [pos, ttl, strong]
var shake := 0.0
const INTERACT_RANGE := 20.0
const SEARCH_TIME := 1.6
var pickups := {}  # id -> {pos, item: {id, n, hp}} items lying on the ground
var next_pickup := 1
var search_until := 0.0  # client: progress bar for our own search
var search_total := 1.0
var hidden_building: BuildingProp  # the roof we lifted off because we are inside
var prompt := ""  # "press E" hint drawn above whatever is in reach
var prompt_pos := Vector2.ZERO
var grade_mat: ShaderMaterial
var play_zoom := Vector2(4, 4)  # zoom to go back to after the death close-up


func _ready() -> void:
	randomize()
	y_sort_enabled = true  # characters and trees are drawn back-to-front by their feet
	shade = CanvasModulate.new()
	add_child(shade)
	camera = Camera2D.new()
	camera.zoom = Vector2(4, 4)
	add_child(camera)
	fx = Node2D.new()
	fx.z_index = 3
	fx.draw.connect(_draw_fx)
	add_child(fx)
	var post := CanvasLayer.new()
	add_child(post)
	var grade := ColorRect.new()
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_mat = ShaderMaterial.new()
	grade_mat.shader = load("res://shaders/post.gdshader")
	grade.material = grade_mat
	post.add_child(grade)
	ui = GameUI.new()
	add_child(ui)
	ui.host_requested.connect(func(n: String):
		player_name = n
		_host(false))
	ui.join_requested.connect(func(addr: String, n: String):
		player_name = n
		_join(addr))

	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--name="):
			player_name = arg.trim_prefix("--name=")
	for arg in args:
		if arg == "--server":
			_host(true)
			return
		elif arg.begins_with("--join="):
			_join(arg.trim_prefix("--join="))
			return
	_make_backdrop()


## A real city at dusk behind the title menu, slowly drifting past.
func _make_backdrop() -> void:
	var before := get_children()
	_make_world(20260924)
	for c in get_children():
		if not before.has(c):
			backdrop_nodes.append(c)
	camera.position = world.to_pos(Vector2i(70, 50))
	camera.zoom = Vector2(2.4, 2.4)
	time = 0.8


func _clear_backdrop() -> void:
	for n in backdrop_nodes:
		n.queue_free()
	backdrop_nodes.clear()
	world = null
	camera.zoom = play_zoom


# --- Connection -------------------------------------------------------------

func _host(dedicated: bool) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	if peer.create_server(port) != OK:
		ui.set_status("เปิดพอร์ต %d ไม่ได้ (มีเกมอื่นเปิดอยู่หรือเปล่า?)" % port)
		return
	multiplayer.multiplayer_peer = peer
	_connect_once(multiplayer.peer_connected, _on_peer_connected)
	_connect_once(multiplayer.peer_disconnected, _on_peer_disconnected)
	world_seed = randi()
	_loot_rng.randomize()
	_clear_backdrop()
	_make_world(world_seed)
	in_game = true
	time = 0.3
	for i in 25:
		_spawn_zombie()
	if not dedicated:
		var p := _add_player(1)
		p.pname = player_name if player_name != "" else ui.player_name()
		_send_inv(p)
	ui.show_menu(false)
	print("Server listening on port %d" % port)


func _join(address: String) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d" % [address, port]
	if peer.create_client(url) != OK:
		ui.set_status("ที่อยู่ไม่ถูกต้อง")
		return
	multiplayer.multiplayer_peer = peer
	_connect_once(multiplayer.connected_to_server, _on_connected)
	_connect_once(multiplayer.connection_failed, _on_connection_failed)
	_connect_once(multiplayer.server_disconnected, _on_server_lost)
	ui.set_status("กำลังเชื่อมต่อ %s ..." % url)


## Multiplayer signals live on the SceneTree and survive a scene reload,
## so only hook them up if this scene hasn't already.
func _connect_once(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


func _on_connected() -> void:
	ui.set_status("เชื่อมต่อแล้ว กำลังโหลดเมือง...")


func _on_connection_failed() -> void:
	ui.set_status("เชื่อมต่อไม่สำเร็จ")
	multiplayer.multiplayer_peer = null


func _on_server_lost() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()


func _exit_tree() -> void:
	# Drop our hooks so a reloaded scene starts clean.
	for pair in [[multiplayer.peer_connected, _on_peer_connected], [multiplayer.peer_disconnected, _on_peer_disconnected],
			[multiplayer.connected_to_server, _on_connected], [multiplayer.connection_failed, _on_connection_failed],
			[multiplayer.server_disconnected, _on_server_lost]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _on_peer_connected(id: int) -> void:
	init_world.rpc_id(id, world_seed)
	var searched := []
	for f: FurnitureProp in world.container_nodes:
		if f.searched:
			searched.append(f.data.id)
	var items := []
	for pid in pickups:
		items.append([pid, pickups[pid].pos, pickups[pid].item])
	var doors := []
	for d in world.doors:
		doors.append([d.id, d.closed, d.hp, d.boards, d.broken])
	sync_state.rpc_id(id, searched, items, doors)
	var p := _add_player(id)
	_send_inv(p)
	print("Player %d joined (%d online)" % [id, players.size()])


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
	print("Player %d left (%d online)" % [id, players.size()])


@rpc("authority", "call_remote", "reliable")
func sync_state(searched: Array, items: Array, doors: Array) -> void:
	for e in doors:
		world.set_door(e[0], e[1], e[2], e[3], e[4])
	for id in searched:
		world.container_nodes[id].set_searched(true)
	for e in items:
		pickup_add(e[0], e[1], e[2])


@rpc("authority", "call_remote", "reliable")
func init_world(seed_val: int) -> void:
	_clear_backdrop()
	_make_world(seed_val)
	in_game = true
	ui.show_menu(false)
	req_set_name.rpc_id(1, player_name if player_name != "" else ui.player_name())
	print("Joined world, seed %d" % seed_val)


func _make_world(seed_val: int) -> void:
	world = World.new()
	world.prop_parent = self
	add_child(world)
	move_child(world, 0)
	world.generate(seed_val)
	decals = Node2D.new()
	decals.draw.connect(_draw_decals)
	add_child(decals)
	move_child(decals, 1)


func _add_player(id: int) -> Player:
	var p := Player.new()
	p.world = world
	p.peer_id = id
	p.is_local = id == multiplayer.get_unique_id()
	p.position = world.spawn_point()
	p.net_pos = p.position
	p.z_index = 1
	add_child(p)
	players[id] = p
	return p


func _add_zombie(id: int, pos: Vector2) -> Zombie:
	var z := Zombie.new()
	z.world = world
	z.players = players
	z.zid = id
	z.outfit = outfits.get(id, [])
	z.position = pos
	z.net_pos = pos
	z.z_index = 1
	add_child(z)
	zombies[id] = z
	return z


# --- Server simulation ------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func req_set_name(n: String) -> void:
	var p := _sender()
	if p:
		p.pname = n.strip_edges().left(16)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func send_input(move: Vector2, aim: Vector2, punch: bool, kick: bool, sprint: bool, sneak: bool) -> void:
	var p: Player = players.get(multiplayer.get_remote_sender_id())
	if p:
		p.sprint = sprint
		p.sneak = sneak
		p.move = move.limit_length(1.0)
		p.aim = aim
		p.punching = punch
		p.kicking = kick


func _server_tick(delta: float) -> void:
	time += delta / DAY_LENGTH
	if time >= 1.0:
		time -= 1.0
		day += 1
	for p: Player in players.values():
		p.server_tick(delta)
		if p.pending_kind != Look.NONE:
			p.pending_t -= delta
			if p.pending_t <= 0:
				_resolve_melee(p, p.pending_kind, p.pending_stats)
				p.pending_kind = Look.NONE
		if p.alive() and p.shoot_cd <= 0:
			if p.kicking:
				_melee(p, Look.KICK, KICK)
			elif p.punching:
				var wid := p.held_weapon()
				if wid == "":
					_melee(p, Look.PUNCH_L, PUNCH)
				else:
					var w := Items.def(wid)
					_melee(p, Look.SWING, [w.range, w.dmg, w.cd, w.stun, w.knock], w.dur * 0.45)
		_tick_search(p, delta)
		_tick_needs(p, delta)
		if not p.alive() and not p.dropped:
			p.dropped = true
			_drop_everything(p)
	for z: Zombie in zombies.values():
		z.server_tick(delta)
	_separate()

	_tick_horde()
	var horde := is_horde(day, time)
	spawn_timer -= delta
	if spawn_timer <= 0 and zombies.size() < (HORDE_MAX_ZOMBIES if horde else MAX_ZOMBIES):
		if horde and not players.is_empty():
			_spawn_horde_zombie()
			spawn_timer = 0.35
		else:
			_spawn_zombie()
			spawn_timer = 1.5 if world.is_night else 5.0

	snap_timer -= delta
	if snap_timer <= 0:
		snap_timer = SNAPSHOT_RATE
		var ps := []
		for p: Player in players.values():
			ps.append([p.peer_id, p.position, p.aim, p.hp, p.kills, p.weapon_id, p.pname,
					[int(p.hunger), int(p.thirst), int(p.infection), p.bleeding, int(p.stamina), p.exhausted, p.sprint, p.sneak]])
		var zs := []
		for z: Zombie in zombies.values():
			zs.append([z.zid, z.position, z.hp, z.state])
		snapshot.rpc(ps, zs, time, day)


## Keep bodies from stacking: zombies push each other and get pushed off players.
func _separate() -> void:
	var zs: Array = zombies.values()
	for i in zs.size():
		var a: Zombie = zs[i]
		for j in range(i + 1, zs.size()):
			var b: Zombie = zs[j]
			var v := b.position - a.position
			var dist := v.length()
			if dist < 9.0 and dist > 0.01:
				var push := v / dist * (9.0 - dist) * 0.5
				a.position = world.slide(a.position, -push, Zombie.RADIUS)
				b.position = world.slide(b.position, push, Zombie.RADIUS)
		for p: Player in players.values():
			var v := a.position - p.position
			var dist := v.length()
			if p.alive() and dist < 10.0 and dist > 0.01:
				a.position = world.slide(a.position, v / dist * (10.0 - dist), Zombie.RADIUS)


## Punch hits the closest zombie in front; a kick hits everything in front.
func _melee(p: Player, kind: int, stats: Array, windup := -1.0) -> void:
	p.shoot_cd = stats[2]
	p.search_id = -1  # swinging interrupts a search
	fx_melee.rpc(p.peer_id, kind)
	_make_noise(p.position, NOISE_SWING * (0.6 if p.sneak else 1.0))
	p.pending_kind = kind
	p.pending_stats = stats
	if windup < 0:
		windup = KICK_WINDUP if kind == Look.KICK else PUNCH_WINDUP
	p.pending_t = windup


## Punch hits the zombie in front that is closest to the aim; a kick hits
## everything in front. Generous cone so a blow that looks like it lands, lands.
func _resolve_melee(p: Player, kind: int, stats: Array) -> void:
	if not p.alive():
		return
	var dir := p.aim.normalized()
	var hits: Array = []
	for z: Zombie in zombies.values():
		var v := z.position - p.position
		if v.length() < stats[0] and v.normalized().dot(dir) > 0.3:
			hits.append(z)
	if hits.is_empty():
		return
	var wid := p.held_weapon() if kind == Look.SWING else ""
	var cleave: bool = kind == Look.KICK or Items.def(wid).get("cleave", false)
	if not cleave:
		hits.sort_custom(func(a, b): return (a.position - p.position).normalized().dot(dir) > (b.position - p.position).normalized().dot(dir))
		hits = [hits[0]]
	for z: Zombie in hits:
		z.hp -= stats[1]
		z.stun = stats[3]
		z.position = world.slide(z.position, dir * stats[4], Zombie.RADIUS)
		fx_hit.rpc(z.zid, z.position, dir, kind == Look.KICK, p.peer_id, Items.def(wid).get("draw", {}).get("kind", ""), stats[1])
		_make_noise(z.position, NOISE_HIT)
		if z.hp <= 0:
			fx_death.rpc(z.position, 1.0 if dir.x >= 0 else -1.0, z.skin, z.shirt, z.pants, z.hair)
			zombies.erase(z.zid)
			z.queue_free()
			p.kills += 1
	if wid != "":
		_wear_weapon(p)


## Hunger, thirst, infection, bleeding and stamina (server).
func _tick_needs(p: Player, delta: float) -> void:
	if not p.alive():
		return
	var running := p.sprint and not p.sneak and p.move.length() > 0.1 and not p.exhausted and p.stamina > 0.0
	# Footsteps: quiet walking, loud running, silent sneaking.
	p.step_t -= delta
	if p.move.length() > 0.1 and not p.sneak and p.step_t <= 0.0:
		p.step_t = 0.5
		_make_noise(p.position, NOISE_RUN if running else NOISE_WALK)
	p.hunger = maxf(0.0, p.hunger - HUNGER_RATE * delta * (1.6 if running else 1.0))
	p.thirst = maxf(0.0, p.thirst - THIRST_RATE * delta * (1.8 if running else 1.0))
	if running:
		p.stamina = maxf(0.0, p.stamina - 22.0 * delta)
		if p.stamina <= 0.0:
			p.exhausted = true
			_toast(p, "หมดแรง! ต้องพักก่อนวิ่งต่อ")
	else:
		var regen := 16.0 if p.hunger > 20.0 and p.thirst > 20.0 else 6.0
		p.stamina = minf(100.0, p.stamina + regen * delta)
		if p.exhausted and p.stamina > 35.0:
			p.exhausted = false
	if p.bitten:
		p.bitten = false
		if p.infection <= 0.0 and randf() < BITE_INFECT_CHANCE:
			p.infection = 12.0
			_toast(p, "โดนกัด! ติดเชื้อแล้ว หายาปฏิชีวนะ")
		if not p.bleeding and randf() < BITE_BLEED_CHANCE:
			p.bleeding = true
			_toast(p, "เลือดออก! ใช้ผ้าพันแผลห้ามเลือด")
	var dmg := 0.0
	if p.hunger <= 0.0:
		dmg += STARVE_DAMAGE
	if p.thirst <= 0.0:
		dmg += STARVE_DAMAGE
	if p.bleeding:
		dmg += BLEED_DAMAGE
	if dmg > 0:
		p.take_damage(dmg * delta)
	_warn(p, "hungry", p.hunger < 25.0, "หิวแล้ว หาอะไรกิน")
	_warn(p, "starving", p.hunger <= 0.0, "หิวจนเลือดลด!")
	_warn(p, "thirsty", p.thirst < 25.0, "กระหายน้ำ หาน้ำดื่ม")
	_warn(p, "dry", p.thirst <= 0.0, "ขาดน้ำจนเลือดลด!")
	if p.infection > 0.0:
		p.infection = minf(100.0, p.infection + INFECTION_RATE * delta)
		_warn(p, "fever", p.infection > 60.0, "เชื้อลุกลาม ตัวเริ่มร้อนและเดินช้าลง...")
		if p.infection >= 100.0:
			_turn(p)


## A zombie pounds on a door (server).
func damage_door(id: int, dmg: float) -> void:
	var d: Dictionary = world.doors[id]
	if not d.closed:
		return
	var hp: float = d.hp - dmg
	# Boards take the beating first; each one splinters off as its share runs out.
	var boards: int = mini(d.boards, maxi(0, ceili((hp - World.DOOR_HP) / World.BOARD_HP)))
	var pos := world.to_pos(d.cell)
	if hp <= 0.0:
		door_state.rpc(id, false, 0.0, 0, true)
		fx_sound.rpc("break", pos)
		_make_noise(pos, NOISE_BREAK)
	else:
		door_state.rpc(id, true, hp, boards, false)
		fx_sound.rpc("door", pos)
		_make_noise(pos, NOISE_HIT)


@rpc("authority", "call_local", "reliable")
func door_state(id: int, closed: bool, hp: float, boards: int, broken: bool) -> void:
	world.set_door(id, closed, hp, boards, broken)


## A screamer that spots you shrieks: every zombie for a long way comes running.
func zombie_scream(z: Zombie) -> void:
	fx_sound.rpc("scream", z.position)
	_make_noise(z.position, 260.0)


@rpc("any_peer", "call_remote", "reliable")
func req_reinforce() -> void:
	var p := _sender()
	if p == null or not p.alive():
		return
	var id := world.door_near(p.position, 18.0)
	if id < 0:
		return
	var slot := -1
	for i in Items.INV_SIZE:
		if p.inv[i] != null and p.inv[i].id == "wood":
			slot = i
	if slot < 0:
		_toast(p, "ต้องมีไม้กระดาน")
		return
	var d: Dictionary = world.doors[id]
	if d.broken:
		door_state.rpc(id, false, World.DOOR_HP, 0, false)
		_toast(p, "ซ่อมประตูแล้ว")
	elif d.boards >= World.MAX_BOARDS:
		_toast(p, "ตอกไม้เต็มแล้ว")
		return
	else:
		door_state.rpc(id, d.closed, minf(d.hp + World.BOARD_HP, World.DOOR_HP + (d.boards + 1) * World.BOARD_HP), d.boards + 1, false)
		_toast(p, "ตอกไม้เสริมประตู (%d/%d)" % [d.boards + 1, World.MAX_BOARDS])
	p.inv[slot].n -= 1
	if p.inv[slot].n <= 0:
		p.inv[slot] = null
	fx_sound.rpc("door", p.position)
	_make_noise(p.position, NOISE_SWING)  # hammering is loud
	_send_inv(p)


func _toggle_door(p: Player, id: int) -> void:
	var d: Dictionary = world.doors[id]
	if d.broken:
		_toast(p, "ประตูพัง ต้องซ่อมด้วยไม้กระดาน [R]")
		return
	if not d.closed:
		# Don't shut it on someone standing in the doorway.
		var c := world.to_pos(d.cell)
		for q: Player in players.values():
			if q.alive() and q.position.distance_to(c) < 9.0:
				return
		for z: Zombie in zombies.values():
			if z.position.distance_to(c) < 9.0:
				return
	door_state.rpc(id, not d.closed, d.hp, d.boards, false)
	fx_sound.rpc("door", world.to_pos(d.cell))


## Every zombie within `radius` goes to look.
func _make_noise(pos: Vector2, radius: float) -> void:
	for z: Zombie in zombies.values():
		if z.position.distance_to(pos) < radius:
			z.hear(pos)


## Send a warning once when a condition becomes true; re-arm when it clears.
func _warn(p: Player, key: String, cond: bool, text: String) -> void:
	if cond and not p.warned.has(key):
		p.warned[key] = true
		_toast(p, text)
	elif not cond:
		p.warned.erase(key)


## The infection wins: the player dies and gets back up as a zombie in their clothes.
func _turn(p: Player) -> void:
	p.infection = 100.0
	p.take_damage(9999)
	p.dropped = true
	_drop_everything(p)
	fx_turned.rpc(p.peer_id)
	var z := _add_zombie(next_zid, p.position)
	next_zid += 1
	var o := [p.shirt, p.pants, p.hair]
	z.apply_outfit(o)
	outfits[z.zid] = o
	zombie_outfit.rpc(z.zid, o)


@rpc("authority", "call_remote", "reliable")
func zombie_outfit(zid: int, o: Array) -> void:
	outfits[zid] = o
	var z: Zombie = zombies.get(zid)
	if z:
		z.apply_outfit(o)


@rpc("authority", "call_local", "reliable")
func fx_turned(peer_id: int) -> void:
	var p: Player = players.get(peer_id)
	if p:
		p.turned = true
		Sfx.play(self, "groan", p.position, 0.0, 0.8)


## Each hit wears the weapon down; at zero it breaks.
func _wear_weapon(p: Player) -> void:
	var it = p.inv[p.sel]
	if it == null:
		return
	it.hp -= 1
	if it.hp <= 0:
		p.inv[p.sel] = null
		fx_sound.rpc("break", p.position)
		_make_noise(p.position, NOISE_BREAK)
		_toast(p, "%s หัก!" % Items.display_name(it.id))
	_send_inv(p)


# --- Inventory, searching and pickups (server) ------------------------------

## Sender of the current RPC; for the host calling its own handler directly, itself.
func _sender() -> Player:
	var id := multiplayer.get_remote_sender_id()
	return players.get(id if id != 0 else multiplayer.get_unique_id())


## Call an owner-only RPC, or run it directly when the owner is this machine.
func _notify(peer_id: int, method: StringName, args: Array) -> void:
	if peer_id == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer_id, method] + args)


func _send_inv(p: Player) -> void:
	p.weapon_id = p.held_weapon()
	_notify(p.peer_id, &"inv_sync", [p.inv, p.sel])


func _toast(p: Player, text: String) -> void:
	_notify(p.peer_id, &"show_toast", [text])


## Put an item in the first slot that takes it. Returns false if full.
func _give(p: Player, id: String) -> bool:
	var d := Items.def(id)
	if d.get("type") != "weapon":
		for it in p.inv:
			if it != null and it.id == id and it.n < Items.STACK:
				it.n += 1
				return true
	for i in Items.INV_SIZE:
		if p.inv[i] == null:
			p.inv[i] = {id = id, n = 1, hp = d.get("hp", 0)}
			return true
	return false


func _spawn_pickup(pos: Vector2, item: Dictionary) -> void:
	pickup_add.rpc(next_pickup, pos, item)
	next_pickup += 1


func _drop_everything(p: Player) -> void:
	for i in Items.INV_SIZE:
		if p.inv[i] != null:
			_spawn_pickup(p.position + Vector2.from_angle(i * TAU / 8) * 6, p.inv[i])
			p.inv[i] = null
	_send_inv(p)


@rpc("any_peer", "call_remote", "reliable")
func req_select(slot: int) -> void:
	var p := _sender()
	if p and slot >= 0 and slot < Items.INV_SIZE:
		p.sel = slot
		_send_inv(p)


@rpc("any_peer", "call_remote", "reliable")
func req_use() -> void:
	var p := _sender()
	if p == null or not p.alive():
		return
	var it = p.inv[p.sel]
	if it == null or Items.def(it.id).get("type") != "use":
		return
	var d := Items.def(it.id)
	p.hp = minf(Player.MAX_HP, p.hp + d.get("heal", 0.0))
	p.hunger = clampf(p.hunger + d.get("food", 0.0), 0.0, 100.0)
	p.thirst = clampf(p.thirst + d.get("drink", 0.0), 0.0, 100.0)
	p.stamina = minf(100.0, p.stamina + d.get("stamina", 0.0))
	if d.get("cure", 0.0) > 0.0 and p.infection > 0.0:
		p.infection = maxf(0.0, p.infection - d.cure)
		if p.infection <= 0.0:
			_toast(p, "หายจากการติดเชื้อแล้ว")
	if d.get("stop_bleed", false) and p.bleeding:
		p.bleeding = false
		_toast(p, "ห้ามเลือดแล้ว")
	it.n -= 1
	if it.n <= 0:
		p.inv[p.sel] = null
	fx_sound.rpc("eat", p.position)
	_toast(p, "ใช้ %s" % Items.display_name(it.id))
	_send_inv(p)


@rpc("any_peer", "call_remote", "reliable")
func req_drop() -> void:
	var p := _sender()
	if p == null or p.inv[p.sel] == null:
		return
	_spawn_pickup(p.position + p.aim.normalized() * 8, p.inv[p.sel])
	p.inv[p.sel] = null
	_send_inv(p)


## E: pick up the nearest item on the ground, else start searching furniture.
@rpc("any_peer", "call_remote", "reliable")
func req_interact() -> void:
	var p := _sender()
	if p == null or not p.alive():
		return
	var best := -1
	var best_d := 14.0
	for pid in pickups:
		var d: float = p.position.distance_to(pickups[pid].pos)
		if d < best_d:
			best_d = d
			best = pid
	if best >= 0:
		var item: Dictionary = pickups[best].item
		var took := false
		if item.get("n", 1) > 1 or Items.is_weapon(item.id):
			for i in Items.INV_SIZE:
				if p.inv[i] == null:
					p.inv[i] = item.duplicate()
					took = true
					break
		else:
			took = _give(p, item.id)
		if not took:
			_toast(p, "กระเป๋าเต็ม")
			return
		pickup_del.rpc(best)
		fx_sound.rpc("pickup", p.position)
		_toast(p, "เก็บ %s" % Items.display_name(item.id))
		_send_inv(p)
		return
	var door := _door_for_e(p.position)
	if door >= 0:
		_toggle_door(p, door)
		return
	var f := _container_near(p.position)
	if f and not f.searched:
		p.search_id = f.data.id
		p.search_t = SEARCH_TIME
		fx_sound.rpc("rustle", f.position)
		_make_noise(f.position, NOISE_SEARCH)
		_notify(p.peer_id, &"search_started", [SEARCH_TIME])


## The door E would use: one you're standing in, or any close one when
## there's no unsearched furniture in reach.
func _door_for_e(pos: Vector2) -> int:
	var door := world.door_near(pos, 15.0)
	if door >= 0:
		return door
	var f := _container_near(pos)
	if f == null or f.searched:
		return world.door_near(pos, 16.0)
	return -1


func _container_near(pos: Vector2) -> FurnitureProp:
	var best: FurnitureProp = null
	var best_d := INTERACT_RANGE
	for f: FurnitureProp in world.container_nodes:
		var d := pos.distance_to(f.position)
		if d < best_d:
			best_d = d
			best = f
	return best


func _tick_search(p: Player, delta: float) -> void:
	if p.search_id < 0:
		return
	var f: FurnitureProp = world.container_nodes[p.search_id]
	if not p.alive() or p.move.length() > 0.1 or f.searched or p.position.distance_to(f.position) > INTERACT_RANGE + 4:
		p.search_id = -1
		_notify(p.peer_id, &"search_started", [0.0])
		return
	p.search_t -= delta
	if p.search_t > 0:
		return
	p.search_id = -1
	container_searched.rpc(f.data.id)
	var found := Items.roll(f.data.table, _loot_rng)
	var names := []
	for id in found:
		if not _give(p, id):
			_spawn_pickup(p.position + Vector2(randf_range(-6, 6), 4), {id = id, n = 1, hp = Items.def(id).get("hp", 0)})
		names.append(Items.display_name(id))
	_toast(p, "เจอ: " + ", ".join(names) if not names.is_empty() else "ไม่มีอะไรเหลือแล้ว")
	if not names.is_empty():
		fx_sound.rpc("pickup", p.position)
	_send_inv(p)


var _loot_rng := RandomNumberGenerator.new()


## Guns come back later as loot; kept here for that milestone.
func _fire(p: Player) -> void:
	if p.aim == Vector2.ZERO:
		return
	p.shoot_cd = GUN_COOLDOWN
	var dir := p.aim.normalized()
	var from := p.position
	var length := world.ray_length(from, dir, GUN_RANGE)
	var hit: Zombie = null
	for z: Zombie in zombies.values():
		var t := (z.position - from).dot(dir)
		if t > 0 and t < length and (from + dir * t).distance_to(z.position) < Zombie.RADIUS + 2:
			length = t
			hit = z
	if hit:
		hit.hp -= GUN_DAMAGE
		if hit.hp <= 0:
			fx_death.rpc(hit.position, 1.0 if dir.x >= 0 else -1.0, hit.skin, hit.shirt, hit.pants, hit.hair)
			zombies.erase(hit.zid)
			hit.queue_free()
			p.kills += 1
	fx_shot.rpc(from, from + dir * length, hit != null)


static func is_horde(d: int, t: float) -> bool:
	# The horde night starts at dusk on every third day and runs past midnight.
	return (d % HORDE_EVERY == 0 and t > 0.764) or (d % HORDE_EVERY == 1 and d > 1 and t < 0.036)


func _tick_horde() -> void:
	if day % HORDE_EVERY == 0 and time > 0.62 and horde_announced != day:
		horde_announced = day
		fx_announce.rpc("คืนนี้ฝูงซอมบี้จะบุกเมือง! หาที่หลบ ปิดประตู ตอกไม้ให้แน่น", true)
	if is_horde(day, time) and horde_started != day - (0 if day % HORDE_EVERY == 0 else 1):
		horde_started = day - (0 if day % HORDE_EVERY == 0 else 1)
		spawn_timer = 0.0
		fx_announce.rpc("ฝูงซอมบี้มาแล้ว!", true)
	if day % HORDE_EVERY == 1 and day > 1 and time > 0.036 and time < 0.2 and horde_ended != day:
		horde_ended = day
		fx_announce.rpc("รอดคืนฝูงมาได้ · ฟ้าใกล้สางแล้ว", false)


## Horde zombies come in from just off-screen of a random player and head straight for them.
func _spawn_horde_zombie() -> void:
	var targets: Array = players.values().filter(func(q): return q.alive())
	if targets.is_empty():
		return
	var p: Player = targets[randi() % targets.size()]
	for attempt in 20:
		var pos: Vector2 = p.position + Vector2.from_angle(randf() * TAU) * randf_range(280, 420)
		if world.can_stand(pos, 5):
			var z := _add_zombie(next_zid, pos)
			next_zid += 1
			z.hear(p.position)
			return


@rpc("authority", "call_local", "reliable")
func fx_announce(text: String, siren: bool) -> void:
	ui.announce(text)
	if siren:
		Sfx.play(self, "siren", camera.position, -6.0, 1.0)


func _spawn_zombie() -> void:
	for attempt in 30:
		var c := Vector2i(randi_range(0, World.W - 1), randi_range(0, World.H - 1))
		var pos := world.to_pos(c)
		if world.is_solid(c):
			continue
		var too_close := false
		for p: Player in players.values():
			if p.position.distance_to(pos) < 300:
				too_close = true
		if not too_close:
			_add_zombie(next_zid, pos)
			next_zid += 1
			return


# --- Client side ------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(ps: Array, zs: Array, t: float, d: int) -> void:
	if world == null or not in_game:
		return
	time = t
	day = d
	var seen := {}
	for e in ps:
		var id: int = e[0]
		seen[id] = true
		var p: Player = players.get(id)
		if p == null:
			p = _add_player(id)
			p.position = e[1]
		p.net_pos = e[1]
		if not p.is_local:
			p.aim = e[2]
		p.hp = e[3]
		p.kills = e[4]
		p.weapon_id = e[5]
		p.pname = e[6]
		var n: Array = e[7]
		p.hunger = n[0]
		p.thirst = n[1]
		p.infection = n[2]
		p.bleeding = n[3]
		p.stamina = n[4]
		p.exhausted = n[5]
		if not p.is_local:
			p.sprint = n[6]
			p.sneak = n[7]
	for id in players.keys():
		if not seen.has(id):
			players[id].queue_free()
			players.erase(id)
	seen.clear()
	for e in zs:
		var id: int = e[0]
		seen[id] = true
		var z: Zombie = zombies.get(id)
		if z == null:
			z = _add_zombie(id, e[1])
		z.net_pos = e[1]
		z.hp = e[2]
		z.state = e[3]
	for id in zombies.keys():
		if not seen.has(id):
			zombies[id].queue_free()
			zombies.erase(id)


@rpc("authority", "call_local", "unreliable")
func fx_shot(from: Vector2, to: Vector2, hit: bool) -> void:
	tracers.append([from, to, 0.08])
	if hit:
		var dir := (to - from).normalized()
		for i in 3:
			var p := to + dir * randf_range(0, 9) + Vector2(randf_range(-3, 3), randf_range(-3, 3))
			blood.append([p, randf_range(0.8, 2.6), Color(randf_range(0.35, 0.5), 0.02, 0.02, 0.85)])
		if blood.size() > 600:
			blood = blood.slice(blood.size() - 600)
	decals.queue_redraw()


@rpc("authority", "call_local", "unreliable")
func fx_melee(peer_id: int, kind: int) -> void:
	var p: Player = players.get(peer_id)
	if p:
		p.play_attack(kind)
		if p.is_local:
			ui.tutorial("kick" if kind == Look.KICK else "attack")
		Sfx.play(self, "swing" if kind in [Look.SWING, Look.KICK] else "punch", p.position, -4.0)


@rpc("authority", "call_local", "unreliable")
func fx_sound(name: String, pos: Vector2) -> void:
	Sfx.play(self, name, pos)


@rpc("authority", "call_remote", "reliable")
func inv_sync(inv: Array, sel: int) -> void:
	var me: Player = players.get(multiplayer.get_unique_id())
	if me:
		me.inv = inv
		me.sel = sel
		me.weapon_id = me.held_weapon()
		if me.weapon_id != "":
			ui.tutorial("equip")
	ui.set_inventory(inv, sel)


@rpc("authority", "call_remote", "reliable")
func show_toast(text: String) -> void:
	ui.push_feed(text)


@rpc("authority", "call_remote", "reliable")
func search_started(duration: float) -> void:
	search_total = maxf(duration, 0.01)
	search_until = Time.get_ticks_msec() / 1000.0 + duration


@rpc("authority", "call_local", "reliable")
func container_searched(id: int) -> void:
	world.container_nodes[id].set_searched(true)
	var me: Player = players.get(multiplayer.get_unique_id())
	if me and me.position.distance_to(world.container_nodes[id].position) < 30:
		ui.tutorial("search")


@rpc("authority", "call_local", "reliable")
func pickup_add(id: int, pos: Vector2, item: Dictionary) -> void:
	pickups[id] = {pos = pos, item = item}
	decals.queue_redraw()


@rpc("authority", "call_local", "reliable")
func pickup_del(id: int) -> void:
	pickups.erase(id)
	decals.queue_redraw()


@rpc("authority", "call_local", "unreliable")
func fx_hit(zid: int, pos: Vector2, dir: Vector2, strong: bool, attacker: int, weapon_kind := "", dmg := 0.0) -> void:
	if dmg > 0:
		dmg_numbers.append([pos + Vector2(randf_range(-4, 4), -30), str(int(dmg)), dmg >= 30, 0.0])
	var z: Zombie = zombies.get(zid)
	if z:
		z.flinch(dir)
	sparks.append([pos + Look.CHEST - dir * 3.0, 0.14, strong])
	for i in 4 if strong else 2:
		blood.append([pos + dir * randf_range(2, 8) + Vector2(randf_range(-3, 3), randf_range(-2, 2)),
				randf_range(0.8, 2.2), Color(randf_range(0.35, 0.5), 0.02, 0.02, 0.85)])
	decals.queue_redraw()
	var blade := weapon_kind in ["knife", "machete", "axe"]
	Sfx.play(self, "blade" if blade else ("kick" if strong else "hit"), pos)
	if attacker == multiplayer.get_unique_id():
		shake = maxf(shake, 2.2 if strong or weapon_kind != "" else 1.3)


@rpc("authority", "call_local", "reliable")
func fx_death(pos: Vector2, fall_dir: float, skin: Color, shirt: Color, pants: Color, hair: Color) -> void:
	leave_corpse(pos, fall_dir, skin, shirt, pants, hair, true, 0.0)


## A fallen body on the ground; `age` lets a respawned player's body carry on where it was.
func leave_corpse(pos: Vector2, fall_dir: float, skin: Color, shirt: Color, pants: Color, hair: Color,
		zombie: bool, age: float) -> void:
	var c := Corpse.new()
	c.position = pos
	c.skin = skin
	c.shirt = shirt
	c.pants = pants
	c.hair = hair
	c.zombie = zombie
	c.fall_dir = fall_dir
	c.t = age
	add_child(c)


func _process(delta: float) -> void:
	if world == null:
		return
	if not in_game:
		camera.position += Vector2(9, 2) * delta  # drift over the rooftops
		shade.color = Color(0.3, 0.3, 0.42)
		if not world.is_night:
			world.is_night = true
			get_tree().call_group("night_glow", "set_visible", true)
			get_tree().call_group("street_lights", "set_visible", true)
		return
	var me: Player = players.get(multiplayer.get_unique_id())
	if me:
		var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		move += Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
				float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		move = move.limit_length(1.0)
		var aim := get_global_mouse_position() - (me.position + Look.CHEST)
		var punch := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var kick := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		me.sneak = sneak_toggle or Input.is_key_pressed(KEY_CTRL)
		me.sprint = Input.is_key_pressed(KEY_SHIFT) and not me.sneak
		me.aim = aim
		if multiplayer.is_server():
			me.move = move
			me.punching = punch
			me.kicking = kick
		else:
			send_input.rpc_id(1, move, aim, punch, kick, me.sprint, me.sneak)
			if me.alive():
				me.position = world.slide(me.position, move * Player.SPEED * me.speed_mult() * delta, Player.RADIUS)
		camera.position = me.position + Look.CHEST
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
		shake = move_toward(shake, 0.0, delta * 14.0)
		_fade_trees_near(me.position)
		_update_inside(me)
		_update_prompt(me)
		if me.moving:
			ui.tutorial("move")
		if hidden_building:
			ui.tutorial("enter")
		if me.kills > last_kills:
			ui.push_feed("ฆ่าซอมบี้ · รวม %d ตัว" % me.kills, "kill")
		last_kills = me.kills

	if multiplayer.is_server():
		_server_tick(delta)

	var light := lerpf(0.12, 1.0, clampf((0.5 - absf(time - 0.4)) * 4.0, 0.0, 1.0))
	shade.color = Color(light * 0.85, light * 0.92, minf(1.0, light * 1.4))
	var night := light < 0.6
	if night != world.is_night:
		get_tree().call_group("night_glow", "set_visible", night)
		get_tree().call_group("street_lights", "set_visible", night)
	world.is_night = night

	for tr in tracers:
		tr[2] -= delta
	tracers = tracers.filter(func(tr): return tr[2] > 0)
	for sp in sparks:
		sp[1] -= delta
	sparks = sparks.filter(func(sp): return sp[1] > 0)
	fx.queue_redraw()


	drip_t -= delta
	if drip_t <= 0.0:
		drip_t = 0.35
		for p: Player in players.values():
			if p.alive() and p.bleeding:
				blood.append([p.position + Vector2(randf_range(-3, 3), randf_range(-1, 2)), randf_range(0.6, 1.4),
						Color(0.4, 0.03, 0.03, 0.8)])
				decals.queue_redraw()
	for dn in dmg_numbers:
		dn[3] += delta
	dmg_numbers = dmg_numbers.filter(func(dn): return dn[3] < 0.9)
	ui.update_hud(delta, me, day, time, players.size())
	var hurt := 0.0
	if me and me.alive() and me.hp < 35:
		hurt = (35.0 - me.hp) / 35.0
	grade_mat.set_shader_parameter("hurt", hurt)
	var sick := 0.0
	if me and me.alive():
		sick = clampf((me.infection - 10.0) / 90.0, 0.0, 1.0)
	grade_mat.set_shader_parameter("sick", sick)
	_update_death_screen(me, delta)


var faded: Array = []


## Colour drains to red, the camera leans in on the body, and a message fades up.
func _update_death_screen(me: Player, delta: float) -> void:
	var dead := me != null and not me.alive()
	var k := clampf((me.death_t - 0.6) / 1.2, 0.0, 1.0) if dead else 0.0
	var cur: float = grade_mat.get_shader_parameter("death") if grade_mat.get_shader_parameter("death") != null else 0.0
	grade_mat.set_shader_parameter("death", move_toward(cur, k, delta * (1.0 if dead else 2.5)))
	if dead:
		camera.zoom = camera.zoom.lerp(play_zoom * 1.35, delta * 0.8)
	elif me:
		camera.zoom = camera.zoom.lerp(play_zoom, delta * 3.0) if camera.zoom.distance_to(play_zoom) > 0.01 else play_zoom


## Walking into a building lifts its roof and front wall off so you can see inside.
func _update_inside(me: Player) -> void:
	var b: BuildingProp = world.building_at.get(world.to_cell(me.position))
	if b and not b.data.get("enter", false):
		b = null
	if b != hidden_building:
		if hidden_building:
			hidden_building.visible = true
		hidden_building = b
		if b:
			b.visible = false


func _update_prompt(me: Player) -> void:
	prompt = ""
	for f: FurnitureProp in world.container_nodes:
		f.set_highlight(false)
	if not me.alive():
		return
	for pid in pickups:
		if me.position.distance_to(pickups[pid].pos) < 14.0:
			prompt = "[E] เก็บ %s" % Items.display_name(pickups[pid].item.id)
			prompt_pos = pickups[pid].pos + Vector2(0, -10)
			return
	var door := _door_for_e(me.position)
	if door >= 0:
		var d: Dictionary = world.doors[door]
		var has_wood := me.inv.any(func(it): return it != null and it.id == "wood")
		if d.broken:
			prompt = "ประตูพัง" + ("  [R] ซ่อม" if has_wood else "  (ต้องมีไม้กระดาน)")
		else:
			prompt = ("[E] เปิดประตู" if d.closed else "[E] ปิดประตู") + ("  [R] ตอกไม้" if has_wood and d.boards < World.MAX_BOARDS else "")
		prompt_pos = world.to_pos(d.cell) + Vector2(0, -22)
		return
	var f := _container_near(me.position)
	if f and not f.searched and (hidden_building != null or not world.building_at.has(world.to_cell(f.position))):
		f.set_highlight(true)
		prompt = "[E] ค้นหา"
		prompt_pos = f.position + Vector2(0, -26)


## Anything standing in front of the local player turns see-through so you
## never lose your character behind a tree, a building or the skytrain.
func _fade_trees_near(pos: Vector2) -> void:
	for t in faded:
		if is_instance_valid(t):
			t.modulate.a = 1.0
	faded.clear()
	var c := world.to_cell(pos)
	for dy in range(0, 3):
		for dx in range(-1, 2):
			var t: TreeProp = world.props.get(c + Vector2i(dx, dy))
			if t:
				t.modulate.a = 0.45
				faded.append(t)
	var body := Rect2(pos + Vector2(-6, -28), Vector2(12, 28))
	for b: BuildingProp in world.building_nodes:
		if pos.y < b.position.y and b.visual_rect().intersects(body):
			b.modulate.a = 0.3
			faded.append(b)
	if world.bts_row >= 0:
		var deck_bottom := (world.bts_row + 3) * World.TILE - World.BTS_H + 9
		var deck_top := (world.bts_row - 1) * World.TILE - World.BTS_H
		if pos.y - 28 < deck_bottom and pos.y > deck_top:
			world.overhead.modulate.a = 0.45
			faded.append(world.overhead)


func _draw_fx() -> void:
	var font := UiTheme.world("Kanit-Medium")
	for p: Player in players.values():
		if p.alive() and p.pname != "":
			var w := font.get_string_size(p.pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 5).x + 6
			var r := Rect2(p.position + Vector2(-w / 2, -41), Vector2(w, 7))
			fx.draw_rect(r, Color(0, 0, 0, 0.45))
			fx.draw_string(font, r.position + Vector2(0, 5.6), p.pname, HORIZONTAL_ALIGNMENT_CENTER, w, 5, UiTheme.PAPER)
	for dn in dmg_numbers:
		var k: float = dn[3] / 0.9
		var pos: Vector2 = dn[0] + Vector2(0, -12 * ease(k, 0.4))
		var size := 9 if dn[2] else 7
		var col := Color(UiTheme.WARN, 1.0 - k * k) if dn[2] else Color(1, 1, 1, 1.0 - k * k)
		fx.draw_string_outline(font, pos - Vector2(20, 0), "-" + dn[1], HORIZONTAL_ALIGNMENT_CENTER, 40, size, 3, Color(0.45, 0.06, 0.04, 1.0 - k * k))
		fx.draw_string(font, pos - Vector2(20, 0), "-" + dn[1], HORIZONTAL_ALIGNMENT_CENTER, 40, size, col)
	if prompt != "":
		var sz := 5
		var tw := UiTheme.draw_rich(fx, Vector2.ZERO, prompt, font, sz, UiTheme.PAPER, true)
		var origin := prompt_pos + Vector2(-tw / 2 - 3, 0)
		fx.draw_style_box(UiTheme.box(UiTheme.CARD, 4, UiTheme.LINE, 0), Rect2(origin + Vector2(-3, -7.5), Vector2(tw + 12, 10)))
		UiTheme.draw_rich(fx, origin + Vector2(3, 0), prompt, font, sz, UiTheme.PAPER)
	var now := Time.get_ticks_msec() / 1000.0
	var me: Player = players.get(multiplayer.get_unique_id())
	if me and now < search_until:
		var k := 1.0 - (search_until - now) / search_total
		var r := Rect2(me.position + Vector2(-9, -38), Vector2(18, 3))
		fx.draw_rect(r.grow(0.6), Color(0, 0, 0, 0.7))
		fx.draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), Color(1, 0.85, 0.4))
	# Impact burst: a bright flash with streaks flying out.
	for sp in sparks:
		var k: float = sp[1] / 0.14
		var p: Vector2 = sp[0]
		var r := (4.0 if sp[2] else 3.0) * (1.6 - k)
		fx.draw_circle(p, r * 0.7 * k + 0.4, Color(1, 0.95, 0.8, k))
		for i in 6:
			var a := i * TAU / 6 + 0.4
			fx.draw_line(p + Vector2.from_angle(a) * r * 0.5, p + Vector2.from_angle(a) * r * 1.4, Color(1, 0.85, 0.5, k), 0.7)
	for tr in tracers:
		var dir: Vector2 = (tr[1] - tr[0]).normalized()
		var muzzle: Vector2 = tr[0] + Look.CHEST + Vector2(dir.x, dir.y * 0.85) * 13.5
		fx.draw_line(muzzle, tr[1] + Look.CHEST, Color(1, 0.9, 0.5, 0.8), 1.0)
		if tr[2] > 0.05:
			fx.draw_circle(muzzle, 3.0, Color(1, 0.8, 0.3, 0.9))
			fx.draw_circle(muzzle, 1.6, Color(1, 1, 0.8))


## Ask the server to do something; the host just does it.
func _request(method: StringName, args: Array) -> void:
	if multiplayer.is_server():
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


func _draw_decals() -> void:
	for b in blood:
		decals.draw_circle(b[0], b[1], b[2])
	for pid in pickups:
		var pu: Dictionary = pickups[pid]
		decals.draw_set_transform(pu.pos + Vector2(0, 1), 0, Vector2(1, 0.4))
		decals.draw_circle(Vector2.ZERO, 5, Color(0, 0, 0, 0.35))
		decals.draw_set_transform(Vector2.ZERO)
		Items.draw_icon(decals, Rect2(pu.pos + Vector2(-6, -9), Vector2(12, 12)), pu.item.id)



func _unhandled_input(event: InputEvent) -> void:
	if world and in_game and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k == KEY_H:
			ui.toggle_help()
		elif k == KEY_ESCAPE and ui.help.visible:
			ui.toggle_help()
		elif k == KEY_C:
			sneak_toggle = not sneak_toggle
			ui.push_feed("ย่อง: เงียบ ช้า มองเห็นยาก" if sneak_toggle else "เลิกย่อง")
		elif k == KEY_E:
			_request(&"req_interact", [])
		elif k == KEY_R:
			_request(&"req_reinforce", [])
		elif k == KEY_F:
			_request(&"req_use", [])
		elif k == KEY_G:
			_request(&"req_drop", [])
		elif k >= KEY_1 and k <= KEY_8:
			_request(&"req_select", [k - KEY_1])
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			play_zoom = (play_zoom * 1.1).clamp(Vector2(1, 1), Vector2(6, 6))
			camera.zoom = play_zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			play_zoom = (play_zoom / 1.1).clamp(Vector2(1, 1), Vector2(6, 6))
			camera.zoom = play_zoom
