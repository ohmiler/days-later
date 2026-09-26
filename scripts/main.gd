class_name Main
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
# Feature modules, split out of this file. Each is a child node with a fixed
# name, so its network calls line up between server and clients.
var combat: Combat
var inventory: Inventory
var doors: Doors
var survival: Survival
var net: Net
var actions: Actions
var things: Things
var crafting: Crafting
var admin: Admin
var vehicles: Vehicles
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
const MAX_GIBS := 40  # loose heads and arms; the oldest fade out first
var gibs: Array = []
var map_t := 0.0
var raining := false  # the server rolls the weather; clients get it in every snapshot
var rain_fx: Control
var bar_click := false  # a mouse button went down on the hotbar: do not punch until it is let go
var outfits := {}  # zid -> [shirt, pants, hair] for zombies that were players
const AUTOSAVE_EVERY := 60.0
var autosave_t := AUTOSAVE_EVERY
var drip_t := 0.0
# How far each kind of noise carries, in pixels (a tile is 16).
const NOISE_WALK := 45.0
const NOISE_RUN := 115.0
const NOISE_SWING := 90.0
const NOISE_HIT := 130.0
const NOISE_SEARCH := 60.0
const NOISE_BREAK := 170.0
var sneak_toggle := false
var roof_k := 0.0  # 0 on the street .. 1 up on the roofs (eases, drives the rooftop view)
const ROOF_DIM := 0.4  # how much the street below darkens while you're up top
var players := {}  # peer_id -> Player
var zombies := {}  # zid -> Zombie
var next_zid := 1
var world_seed := 0
var time := 0.3
var spawn_timer := 0.0
var snap_timer := 0.0
var tracers: Array = []  # [from, to, ttl]
var decals: Node2D
var sight: Sight  # what your character can see; the rest is shaded (local only)
var blood: Array = []  # [pos, radius, colour] - stays on the ground
var sparks: Array = []  # [pos, ttl, strong]
var _muffled := false  # the local player's helmet dulls the sound
var dust: Array = []  # [pos, age]: kicked up by bikes turning hard
var shake := 0.0
const INTERACT_RANGE := 20.0
var pickups := {}  # id -> {pos, item: {id, n, hp}} items lying on the ground
var next_pickup := 1
var search_until := 0.0  # client: progress bar for our own search
var search_total := 1.0
var hidden_building: BuildingProp  # the roof we lifted off because we are inside
var prompt := ""  # "press E" hint drawn above whatever is in reach
var prompt_pos := Vector2.ZERO
var last_target := {}  # what E points at right now (client), for the hold-E wheel
var last_actions: Array = []
var e_down_at := -1.0  # when E went down; held long enough opens the wheel
const WHEEL_HOLD := 0.25
var grade_mat: ShaderMaterial
var play_zoom := Vector2(4, 4)  # zoom to go back to after the death close-up


func _ready() -> void:
	randomize()
	combat = _module(Combat.new(), "Combat")
	inventory = _module(Inventory.new(), "Inventory")
	doors = _module(Doors.new(), "Doors")
	survival = _module(Survival.new(), "Survival")
	net = _module(Net.new(), "Net")
	actions = _module(Actions.new(), "Actions")
	things = _module(Things.new(), "Things")
	crafting = _module(Crafting.new(), "Crafting")
	admin = _module(Admin.new(), "Admin")
	vehicles = _module(Vehicles.new(), "Vehicles")
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
	_warm_glyphs()
	var sounds := Soundscape.new()
	sounds.main = self
	add_child(sounds)
	# Rain streaks over the world, under the HUD.
	var rain_layer := CanvasLayer.new()
	rain_layer.layer = 1
	add_child(rain_layer)
	rain_fx = Control.new()
	rain_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	rain_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rain_fx.visible = false
	rain_fx.draw.connect(survival._draw_rain)
	rain_layer.add_child(rain_fx)
	ui.host_requested.connect(func(n: String, resume: bool):
		player_name = n
		_host(false, resume))
	ui.gear.move_requested.connect(func(a: Array, b: Array): _request(&"req_move", [a, b]))
	ui.gear.use_requested.connect(func(ref: Array): _request(&"req_use_ref", [ref]))
	ui.gear.split_requested.connect(func(ref: Array): _request(&"req_split", [ref]))
	ui.gear.craft_requested.connect(func(id: String): _request(&"req_craft", [id]))
	ui.gear.salvage_requested.connect(func(idx: int): _request(&"req_salvage", [idx]))
	ui.gear.repair_requested.connect(func(ref: Array): _request(&"req_repair", [ref]))
	ui.gear.treat_requested.connect(func(i: int): _request(&"req_treat", [i]))
	ui.admin.give_requested.connect(func(id: String, n: int): _request(&"req_give", [id, n]))
	ui.admin.heal_requested.connect(func(): _request(&"req_heal", []))
	ui.admin.clear_requested.connect(func(r: float): _request(&"req_clear", [r]))
	ui.admin.time_requested.connect(func(t: float): _request(&"req_time", [t]))
	ui.admin.zombie_requested.connect(func(kind: String):
		var me: Player = players.get(multiplayer.get_unique_id())
		if me:
			_request(&"req_zombie", [me.position + Vector2(60, 0).rotated(randf() * TAU), kind]))
	ui.gear.drop_requested.connect(func(ref: Array): _request(&"req_move", [ref, ["ground", -1]]))
	ui.gear.box_closed.connect(func(): _request(&"req_close_box", []))
	ui.chat_sent.connect(func(t: String): _request(&"req_chat", [t]))
	ui.leave_requested.connect(func(): _leave(false))
	ui.quit_requested.connect(func(): _leave(true))
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
			_host(true, SaveGame.has_world() and not args.has("--new"))
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

## Start a server. `resume` loads the saved city; otherwise a new one replaces it.
func _host(dedicated: bool, resume := false) -> void:
	var saved := {}
	if resume:
		# Never start a fresh city over a save we could not read: it would be
		# written over within the minute.
		var r := SaveGame.load_world()
		if r.state == "oldcity":
			# Built by an older generator: the survivors move to a new city.
			SaveGame.move_to_new_city()
			r = {state = "none", data = {}}
		if r.state in ["newer", "corrupt"]:
			var msg: String = SaveGame.world_info().get("problem", "")
			ui.set_status(msg)
			print("Not starting: world save is %s (%s)" % [r.state, ProjectSettings.globalize_path(SaveGame.dir())])
			if dedicated:
				get_tree().quit(1)
			return
		saved = r.data
	var peer := WebSocketMultiplayerPeer.new()
	if peer.create_server(port) != OK:
		ui.set_status("เปิดพอร์ต %d ไม่ได้ (มีเกมอื่นเปิดอยู่หรือเปล่า?)" % port)
		return
	multiplayer.multiplayer_peer = peer
	_connect_once(multiplayer.peer_connected, net._on_peer_connected)
	_connect_once(multiplayer.peer_disconnected, net._on_peer_disconnected)
	if not resume:
		SaveGame.wipe()
	world_seed = saved.get("seed", randi())
	inventory._loot_rng.randomize()
	_clear_backdrop()
	_make_world(world_seed)
	in_game = true
	time = 0.3
	if not saved.is_empty() and SaveGame.load_world_into(self, saved):
		decals.queue_redraw()
		print("Loaded saved city: day %d" % day)
	else:
		for i in 25:
			survival._spawn_zombie()
	if not dedicated:
		var p := _add_player(1)
		p.set_appearance(ui.appearance_code())
		net._claim_name(p, player_name if player_name != "" else ui.player_name(), ui.secret())
		inventory._send_inv(p)
	ui.show_menu(false)
	print("Server listening on port %d" % port)


func _join(address: String) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d" % [address, port]
	if peer.create_client(url) != OK:
		ui.set_status("ที่อยู่ไม่ถูกต้อง")
		return
	multiplayer.multiplayer_peer = peer
	_connect_once(multiplayer.connected_to_server, net._on_connected)
	_connect_once(multiplayer.connection_failed, net._on_connection_failed)
	_connect_once(multiplayer.server_disconnected, net._on_server_lost)
	ui.set_status("กำลังเชื่อมต่อ %s ..." % url)


## Multiplayer signals live on the SceneTree and survive a scene reload,
## so only hook them up if this scene hasn't already.
func _connect_once(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


func _exit_tree() -> void:
	# Drop our hooks so a reloaded scene starts clean.
	for pair in [[multiplayer.peer_connected, net._on_peer_connected], [multiplayer.peer_disconnected, net._on_peer_disconnected],
			[multiplayer.connected_to_server, net._on_connected], [multiplayer.connection_failed, net._on_connection_failed],
			[multiplayer.server_disconnected, net._on_server_lost]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _make_world(seed_val: int) -> void:
	world = World.new()
	world.prop_parent = self
	add_child(world)
	move_child(world, 0)
	world.generate(seed_val)
	ui.city_map.setup(world, ui.cfg, seed_val)
	decals = Node2D.new()
	decals.draw.connect(_draw_decals)
	add_child(decals)
	move_child(decals, 1)
	if sight:
		sight.queue_free()
	sight = Sight.new()
	sight.world = world
	sight.z_index = 8  # over the city and everyone in it, under the HUD
	add_child(sight)


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


func _save_all() -> void:
	SaveGame.save_world(self)
	for p: Player in players.values():
		SaveGame.save_player(p)


func _notification(what: int) -> void:
	# Closing the window saves before the game quits.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and in_game and multiplayer.is_server():
		_save_all()


## Draw every letter the city's signs and graffiti use once, while the title
## screen is up. The first time a letter is drawn its sharp (MSDF) image is
## generated, 2-7 ms per sign; done on the fly, walking into a street full of
## new signs stalled the game for a tenth of a second.
func _warm_glyphs() -> void:
	var texts: Array = CityGen.SIGNS + BuildingProp.GRAFFITI + ["มินิมาร์ท 24 ชม.", "0123456789 SOS X"]
	var warm := Node2D.new()
	warm.position = Vector2(-99999, -99999)
	warm.draw.connect(func():
		var font := Look.thai_font()
		for i in texts.size():
			warm.draw_string(font, Vector2(0, i * 20), texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE))
	add_child(warm)
	get_tree().create_timer(1.0).timeout.connect(warm.queue_free)


func _server_tick(delta: float) -> void:
	things.server_tick(delta)
	survival._tick_weather(delta)
	for id in net.pending.keys():
		net.pending[id] += delta
		if net.pending[id] > net.HELLO_TIMEOUT:
			net.pending.erase(id)
			print("Dropped peer %d: never said hello" % id)
			net._drop_peer(id)
	autosave_t -= delta
	if autosave_t <= 0.0:
		autosave_t = AUTOSAVE_EVERY
		_save_all()
	time += delta * survival.time_speed() / DAY_LENGTH
	if time >= 1.0:
		time -= 1.0
		day += 1
	for p: Player in players.values():
		p.server_tick(delta)
		vehicles.server_tick(p, delta)
		if p.pending_kind != Look.NONE:
			p.pending_t -= delta
			if p.pending_t <= 0:
				combat._resolve_melee(p, p.pending_kind, p.pending_stats)
				p.pending_kind = Look.NONE
		if p.alive() and p.shoot_cd <= 0 and p.riding < 0:
			if p.wants_kick():
				p.kick_buf = 0.0
				combat._melee(p, Look.KICK, combat.KICK)
			elif p.punching and p.aiming and p.gun_hand() != "":
				combat.fire(p, p.gun_hand())
			elif p.wants_punch():
				p.punch_buf = 0.0
				var sw := Combat.next_swing(p)
				p.next_hand = "l" if sw.hand == "r" else "r"
				p.swing_hand = sw.hand
				combat._melee(p, sw.kind, sw.stats, sw.windup)
		inventory._tick_search(p, delta)
		crafting.server_tick(p, delta)
		survival._tick_needs(p, delta)
		if p.open_box >= 0 and (not p.alive() or p.position.distance_to(world.container_nodes[p.open_box].position) > Interact.CONTAINER_REACH + 8.0):
			p.open_box = -1
			_notify(p.peer_id, &"box_open", [-1, []])
		if not p.alive() and not p.dropped:
			p.dropped = true
			inventory._drop_everything(p)
	for z: Zombie in zombies.values():
		z.server_tick(delta)
	_separate()
	doors._tick_traps(delta)

	survival._tick_horde()
	var horde := survival.is_horde(day, time)
	spawn_timer -= delta
	if spawn_timer <= 0 and zombies.size() < (survival.HORDE_MAX_ZOMBIES if horde else MAX_ZOMBIES):
		if horde and not players.is_empty():
			survival._spawn_horde_zombie()
			spawn_timer = 0.35
		else:
			survival._spawn_zombie()
			spawn_timer = 1.5 if world.is_night else 5.0

	snap_timer -= delta
	if snap_timer <= 0:
		snap_timer = SNAPSHOT_RATE
		var ps := []
		for p: Player in players.values():
			ps.append([p.peer_id, p.position, p.aim, p.hp, p.kills, p.weapon_id, p.pname,
					[int(p.hunger), int(p.thirst), int(p.infection), p.bleeding, int(p.stamina), p.exhausted, p.sprint, p.sneak, p.on_roof, p.sleeping, p.bed, p.sleep_bed, p.riding, world.vehicles[p.riding].fuel if p.riding >= 0 else 0.0, p.aiming],
					p.app_code, p.wear_ids])
		var zs := []
		for z: Zombie in zombies.values():
			zs.append([z.zid, z.position, z.hp, z.state, z.flags, z.missing])
		net.snapshot.rpc(ps, zs, time, day, raining)


## Keep bodies from stacking: zombies push each other and get pushed off players.
## Keep bodies from overlapping. Zombies are bucketed into 16 px cells so each
## only checks the ones around it, not every other zombie in the city.
func _separate() -> void:
	var grid := {}
	for z: Zombie in zombies.values():
		var k := Vector2i(z.position / 16.0)
		if grid.has(k):
			grid[k].append(z)
		else:
			grid[k] = [z]
	for a: Zombie in zombies.values():
		var k := Vector2i(a.position / 16.0)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for b: Zombie in grid.get(k + Vector2i(dx, dy), []):
					if b.zid <= a.zid:
						continue  # each pair once
					var v := b.position - a.position
					var dist := v.length()
					if dist < 9.0 and dist > 0.01:
						var push := v / dist * (9.0 - dist) * 0.5
						a.position = world.slide(a.position, -push, Zombie.RADIUS)
						b.position = world.slide(b.position, push, Zombie.RADIUS)
		for p: Player in players.values():
			var v := a.position - p.position
			var dist := v.length()
			if p.alive() and not p.on_roof and dist < 10.0 and dist > 0.01:
				a.position = world.slide(a.position, v / dist * (10.0 - dist), Zombie.RADIUS)


## Every zombie within `radius` goes to look.
func _make_noise(pos: Vector2, radius: float) -> void:
	if raining:
		radius *= 0.65  # the rain covers a lot
	for z: Zombie in zombies.values():
		if z.position.distance_to(pos) < radius:
			z.hear(pos)


# --- Inventory, searching and pickups (server) ------------------------------

## Sender of the current RPC; for the host calling its own handler directly, itself.
var _acting: Player = null  # set while one handler runs another on a player's behalf


func _sender() -> Player:
	if _acting:
		return _acting
	var id := multiplayer.get_remote_sender_id()
	return players.get(id if id != 0 else multiplayer.get_unique_id())


## Call an owner-only RPC, or run it directly when the owner is this machine.
func _module(m: Node, node_name: String) -> Node:
	m.name = node_name
	m.main = self
	add_child(m)
	return m


## The node that has `method`: this one or one of the modules.
func _handler(method: StringName) -> Node:
	if has_method(method):
		return self
	for m in [combat, inventory, doors, survival, net, actions, things, crafting, vehicles, admin]:
		if m.has_method(method):
			return m
	push_error("No handler for %s" % method)
	return self


func _notify(peer_id: int, method: StringName, args: Array) -> void:
	var h := _handler(method)
	if peer_id == multiplayer.get_unique_id():
		h.callv(method, args)
	else:
		h.callv("rpc_id", [peer_id, method] + args)


## Back to the title screen, or out of the game. Saves first when this is the server.
func _leave(quit: bool) -> void:
	if in_game and multiplayer.is_server() and multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
		_save_all()
	in_game = false
	set_process(false)  # nothing may touch the network once it is gone
	set_physics_process(false)
	set_process_unhandled_input(false)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()  # so anything still asking gets an answer
	if quit:
		get_tree().quit()
	else:
		get_tree().reload_current_scene()


func _toast(p: Player, text: String) -> void:
	_notify(p.peer_id, &"show_toast", [text])


func _spawn_pickup(pos: Vector2, item: Dictionary) -> void:
	pickup_add.rpc(next_pickup, pos, item)
	next_pickup += 1


@rpc("authority", "call_local", "unreliable")
func fx_sound(name: String, pos: Vector2) -> void:
	Sfx.play(self, name, pos)


@rpc("authority", "call_remote", "reliable")
func show_toast(text: String) -> void:
	ui.push_feed(text)


@rpc("authority", "call_local", "reliable")
func pickup_add(id: int, pos: Vector2, item: Dictionary) -> void:
	pickups[id] = {pos = pos, item = item}
	decals.queue_redraw()


@rpc("authority", "call_local", "reliable")
func pickup_del(id: int) -> void:
	pickups.erase(id)
	decals.queue_redraw()


## Add a loose body part, fading out the oldest when there are too many.
func add_gib(g: Gib) -> void:
	gibs = gibs.filter(func(x): return is_instance_valid(x))
	if gibs.size() >= MAX_GIBS:
		var old: Gib = gibs.pop_front()
		old.t = maxf(old.t, Gib.LIFE - 2.0)
	gibs.append(g)
	add_child(g)


## Blood thrown across the ground (it stays, like the rest of the decals).
func splatter(pos: Vector2, dir: Vector2, n: int) -> void:
	if Look.low_gore:
		n = n / 3
	for i in n:
		blood.append([pos + dir * randf_range(0, 12) + Vector2(randf_range(-5, 5), randf_range(-3, 3)),
				randf_range(0.8, 2.8), Color(randf_range(0.3, 0.5), 0.02, 0.02, 0.85)])
	if decals:
		decals.queue_redraw()


## A fallen body on the ground; `age` lets a respawned player's body carry on where it was.
func leave_corpse(pos: Vector2, fall_dir: float, body: Dictionary, zombie: bool, age: float, style := "") -> void:
	var c := Corpse.new()
	c.position = pos
	c.lk = body
	c.style = style
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
	map_t -= delta
	if me and map_t <= 0.0:
		map_t = 0.3
		if me.alive():
			ui.city_map.reveal(me.position)
		ui.city_map.me = me
		var others := []
		for p: Player in players.values():
			if p != me and p.alive():
				others.append([p.position, p.pname])
		ui.city_map.others = others
	for p: Player in players.values():
		p.say_t = maxf(0.0, p.say_t - delta)
	if me:
		var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		move += Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
				float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		move = move.limit_length(1.0)
		# From where you're drawn: up on a roof that's lifted above your feet.
		var aim := get_global_mouse_position() - (me.position + Look.CHEST + Vector2(0, -me.lift))
		if me.aiming:  # the cursor on a zombie aims at its middle
			aim = Combat.snap_aim(me.position + Look.CHEST + Vector2(0, -me.lift), get_global_mouse_position(), zombies.values())
		if e_down_at >= 0.0 and not ui.wheel.visible and Time.get_ticks_msec() / 1000.0 - e_down_at > WHEEL_HOLD \
				and not last_actions.is_empty():
			var centre: Vector2 = get_viewport().get_canvas_transform() * (last_target.pos + Vector2(0, -12 - me.lift))
			ui.wheel.open(last_target.title, last_actions, centre)
		if ui.wheel.visible:
			ui.wheel.point(get_viewport().get_mouse_position())
		var over_gear := ui.gear.visible and (ui.gear.get_global_rect().has_point(ui.gear.get_global_mouse_position()) 				or not ui.gear.drag.is_empty())
		if ui.gear.visible:
			# What lies on the ground within reach, for the bag screen's "nearby" column.
			var near := []
			for pid in pickups:
				if me.position.distance_to(pickups[pid].pos) < inventory.GROUND_REACH - 4.0:
					near.append([pid, pickups[pid].item])
			ui.gear.ground = near
			ui.gear.doll_look = me.look  # the bag screen shows you as you are
			ui.gear.me = me
		# Clicks on the hotbar are for the hotbar, not for punching.
		var over_bar := ui.hotbar.hover >= 0 or bar_click
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			bar_click = false
		var blocked := ui.typing() or ui.pause.visible or ui.city_map.visible
		if blocked:
			move = Vector2.ZERO
		var punch := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not ui.wheel.visible and not over_gear and not over_bar and not blocked
		# With a gun in hand the right button raises it to aim; without, it kicks. Space always kicks.
		var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not over_bar and not over_gear and not blocked
		var aiming := rmb and me.gun_hand() != ""
		var kick := (rmb and not aiming) or (Input.is_key_pressed(KEY_SPACE) and not blocked)
		me.aiming = aiming
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if aiming else Input.CURSOR_ARROW)
		me.sneak = sneak_toggle or Input.is_key_pressed(KEY_CTRL)
		me.sprint = Input.is_key_pressed(KEY_SHIFT) and not me.sneak
		me.aim = aim
		if multiplayer.is_server():
			me.move = move
			me.set_attack_input(punch, kick)
		else:
			net.send_input.rpc_id(1, move, aim, punch, kick, me.sprint, me.sneak, aiming)
			me.set_attack_input(punch, kick)
			combat.predict(me, delta)
			if me.riding >= 0 and me.alive():
				Vehicles.step(me, world.vehicles[me.riding], move, delta, world)
			elif me.alive() and not me.sleeping:
				me.position = world.slide(me.position, move * Player.SPEED * me.speed_mult() * world.slow_at(me.position) * delta, Player.RADIUS, me.on_roof)
		camera.position = me.position + Look.CHEST + Vector2(0, -me.lift)
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
		shake = move_toward(shake, 0.0, delta * 14.0)
		if not me.on_roof:
			_fade_trees_near(me.position)
		if me.muffled() != _muffled:
			_muffled = me.muffled()
			Sfx.set_muffled(_muffled)
		_update_inside(me)
		_update_sight(me, delta)
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

	var light := lerpf(0.12, 1.0, clampf((0.5 - absf(time - 0.4)) * 4.0, 0.0, 1.0)) * (0.8 if raining else 1.0)
	if raining:
		rain_fx.queue_redraw()
	shade.color = Color(light * 0.85, light * 0.92, minf(1.0, light * 1.4))
	_update_roof_view(me, delta)
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
	for d in dust:
		d[1] += delta
	dust = dust.filter(func(d): return d[1] < 0.6)
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


## Up on the roofs the street drops into shadow while the roofs you can walk on
## (and anyone standing on them) stay bright, and the camera pulls back a little.
func _update_roof_view(me: Player, delta: float) -> void:
	var target := 1.0 if me and me.on_roof and me.alive() else 0.0
	var before := roof_k
	roof_k = move_toward(roof_k, target, delta * 3.0)
	if roof_k <= 0.0 and before <= 0.0:
		return
	var dim := 1.0 - ROOF_DIM * roof_k
	shade.color = Color(shade.color.r * dim, shade.color.g * dim, shade.color.b * dim)
	var lift_col := 1.0 / dim
	for b: BuildingProp in world.building_nodes:
		var up: float = lift_col if b.data.kind in ["shop", "store"] else 1.0
		b.modulate = Color(up, up, up, b.modulate.a)
	for p: Player in players.values():
		var up := lift_col if p.on_roof else 1.0
		p.modulate = Color(up, up, up, p.modulate.a)


## Shade what your character can't see, and don't show who is there.
func _update_sight(me: Player, delta: float) -> void:
	var r := get_viewport().get_visible_rect().size.length() * 0.5 / camera.zoom.x + 32.0
	sight.update(me, delta, r)
	var k := delta * 6.0
	for z: Zombie in zombies.values():
		z.sight_k = move_toward(z.sight_k, 1.0 if sight.sees(z.position + Vector2(0, -8)) else 0.0, k)
	for p: Player in players.values():
		if p != me:
			p.sight_k = move_toward(p.sight_k, 1.0 if sight.sees(p.position + Vector2(0, -8)) else 0.0, k)


## Colour drains to red, the camera leans in on the body, and a message fades up.
func _update_death_screen(me: Player, delta: float) -> void:
	var dead := me != null and not me.alive()
	var k := clampf((me.death_t - 0.6) / 1.2, 0.0, 1.0) if dead else 0.0
	var cur: float = grade_mat.get_shader_parameter("death") if grade_mat.get_shader_parameter("death") != null else 0.0
	grade_mat.set_shader_parameter("death", move_toward(cur, k, delta * (1.0 if dead else 2.5)))
	if dead:
		camera.zoom = camera.zoom.lerp(play_zoom * 1.35, delta * 0.8)
	elif me:
		var want := play_zoom * lerpf(1.0, 0.78, roof_k)
		camera.zoom = camera.zoom.lerp(want, delta * 3.0) if camera.zoom.distance_to(want) > 0.01 else want


## Walking into a building lifts its roof and front wall off so you can see inside.
func _update_inside(me: Player) -> void:
	var b: BuildingProp = world.building_at.get(world.to_cell(me.position))
	if b and (not b.data.get("enter", false) or me.on_roof or me.lift > 1.0):
		b = null
	if b != hidden_building:
		if hidden_building:
			hidden_building.visible = true
		hidden_building = b
		if b:
			b.visible = false


func _update_prompt(me: Player) -> void:
	prompt = ""
	last_target = {}
	last_actions = []
	for f: FurnitureProp in world.container_nodes:
		f.set_highlight(false)
	if not me.alive():
		return
	if me.sleeping:
		prompt = "หลับอยู่ · เดินเพื่อลุกขึ้น"
		return
	if me.riding >= 0:
		prompt = "[E] ลงจากรถ · " + Vehicles.title_of(world.vehicles[me.riding])
		prompt_pos = me.position + Vector2(0, -34)  # over the rider's head
		return
	var t := Interact.target(self, me)
	var list := Interact.actions(self, me, t)
	if list.is_empty():
		return
	var a := Interact.primary(list)
	prompt = ("[E] " + a.label) if a.ok else "%s · %s" % [t.title, a.why]
	if a.verb != "board":
		var board := Interact.find_action(list, "board")
		if not board.is_empty() and board.ok:
			prompt += "  [R] ตอกไม้"
	if list.size() > 1:
		prompt += "  · ค้าง [E]"
	var up := {stairs = -26.0, edge = -40.0, pickup = -10.0, trap = -14.0, door = -22.0, window = -22.0, container = -26.0}
	prompt_pos = t.pos + Vector2(0, up.get(t.kind, -22.0) - me.lift)
	if t.kind == "container":
		world.container_nodes[t.id].set_highlight(true)
	last_target = t
	last_actions = list


## Anything standing in front of the local player turns see-through so you
## never lose your character behind a tree, a building or the skytrain.
func _fade_trees_near(pos: Vector2) -> void:
	for t in faded:
		if is_instance_valid(t):
			t.modulate.a = 1.0
	faded.clear()
	var c := world.to_cell(pos)
	for dy in range(0, 4):  # (trees are big: see TreeProp.SCALE)
		for dx in range(-2, 3):
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
	var local: Player = players.get(multiplayer.get_unique_id())
	for p: Player in players.values():
		if p.alive() and p.pname != "":
			var w := font.get_string_size(p.pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 5).x + 6
			var r := Rect2(p.position + Vector2(-w / 2, -41 - p.lift), Vector2(w, 7))
			fx.draw_rect(r, Color(0, 0, 0, 0.45))
			fx.draw_string(font, r.position + Vector2(0, 5.6), p.pname, HORIZONTAL_ALIGNMENT_CENTER, w, 5, UiTheme.PAPER)
			if p.say_t > 0.0:
				# What they just said, in a bubble that fades at the end.
				var a := clampf(p.say_t / 0.6, 0.0, 1.0)
				var bw := minf(font.get_string_size(p.say, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 8, 110.0)
				var br := Rect2(p.position + Vector2(-bw / 2, -53 - p.lift), Vector2(bw, 10))
				fx.draw_rect(br, Color(0.95, 0.93, 0.88, 0.92 * a))
				fx.draw_colored_polygon(PackedVector2Array([br.get_center() + Vector2(-2, 5), br.get_center() + Vector2(2, 5),
						br.get_center() + Vector2(0, 8)]), Color(0.95, 0.93, 0.88, 0.92 * a))
				fx.draw_string(font, br.position + Vector2(4, 7.6), p.say, HORIZONTAL_ALIGNMENT_LEFT, bw - 8, 6, Color(0.1, 0.1, 0.1, a))
	for dn in dmg_numbers:
		var k: float = dn[3] / 0.9
		var pos: Vector2 = dn[0] + Vector2(0, -12 * ease(k, 0.4))
		var size := 9 if dn[2] else 7
		var col := Color(UiTheme.WARN, 1.0 - k * k) if dn[2] else Color(1, 1, 1, 1.0 - k * k)
		fx.draw_string_outline(font, pos - Vector2(20, 0), "-" + dn[1], HORIZONTAL_ALIGNMENT_CENTER, 40, size, 3, Color(0.45, 0.06, 0.04, 1.0 - k * k))
		fx.draw_string(font, pos - Vector2(20, 0), "-" + dn[1], HORIZONTAL_ALIGNMENT_CENTER, 40, size, col)
	if local:
		_draw_roof_guides(local, font)
	if prompt != "" and not ui.wheel.visible:
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
	for d in dust:  # puffs that swell and fade
		var k: float = d[1] / 0.6
		fx.draw_circle(d[0] + Vector2(0, -2.0 * k), 2.0 + 4.0 * k, Color(0.72, 0.68, 0.6, 0.35 * (1.0 - k)))
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
		var muzzle: Vector2 = tr[0] + dir * 10.0
		var shooter: Player = players.get(tr[3]) if tr.size() > 3 else null
		if shooter:  # the tip of the gun as drawn
			muzzle = fx.to_local(shooter.to_global(shooter.muzzle))
		muzzle += dir * 1.5
		# No bullet line: just a flash at the muzzle.
		var k: float = tr[2] / 0.07
		fx.draw_circle(muzzle, 7.0 * k, Color(1, 0.7, 0.2, 0.35 * k))
		fx.draw_colored_polygon(PackedVector2Array([muzzle + dir.orthogonal() * 2.5 * k, muzzle + dir * 9.0 * k, muzzle - dir.orthogonal() * 2.5 * k]), Color(1, 0.85, 0.4, k))
		fx.draw_circle(muzzle, 3.0 * k, Color(1, 1, 0.85, k))


## Ask the server to do something; the host just does it.
func _request(method: StringName, args: Array) -> void:
	var h := _handler(method)
	if multiplayer.is_server():
		h.callv(method, args)
	else:
		h.callv("rpc_id", [1, method] + args)


## Outline the walkable roofs around you and mark every stairwell hatch; inside
## a building, label its stairs.
func _draw_roof_guides(me: Player, font: Font) -> void:
	var c0 := world.to_cell(me.position)
	var T := World.TILE
	if roof_k > 0.01:
		var edge := Color(1.0, 0.9, 0.6, 0.6 * roof_k)
		for dy in range(-13, 14):
			for dx in range(-18, 19):
				var c := c0 + Vector2i(dx, dy)
				if not world.is_roof(c):
					continue
				var o := Vector2(c) * T + Vector2(0, -world.roof_height(world.to_pos(c)))
				for d in World.DIRS:
					if not world.is_roof(c + d):
						var a := o + Vector2(maxi(d.x, 0), maxi(d.y, 0)) * T
						var b := a + (Vector2(0, T) if d.x != 0 else Vector2(T, 0))
						fx.draw_line(a, b, edge, 1.0)
		for st in world.stairs:
			if Vector2(st - c0).length() < 20:
				var p := world.to_pos(st) + Vector2(0, -world.roof_height(world.to_pos(st)))
				var r := Rect2(p - Vector2(5, 5), Vector2(10, 10))
				fx.draw_rect(r, Color(0.1, 0.09, 0.08, 0.9 * roof_k))
				fx.draw_rect(r, Color(1, 0.85, 0.4, 0.8 * roof_k), false, 0.8)
				for i in 3:
					fx.draw_line(r.position + Vector2(2, 2.5 + i * 2.5), r.position + Vector2(8, 2.5 + i * 2.5), Color(1, 0.85, 0.4, 0.7 * roof_k), 0.6)
				fx.draw_string(font, p + Vector2(-20, -7), "↓ บันได", HORIZONTAL_ALIGNMENT_CENTER, 40, 5, Color(1, 0.9, 0.6, roof_k))
	elif hidden_building and hidden_building.data.has("stairs"):
		var p := world.to_pos(hidden_building.data.stairs) + Vector2(0, -26)
		fx.draw_string_outline(font, p + Vector2(-20, 0), "↑ ดาดฟ้า", HORIZONTAL_ALIGNMENT_CENTER, 40, 5, 2, Color(0, 0, 0, 0.7))
		fx.draw_string(font, p + Vector2(-20, 0), "↑ ดาดฟ้า", HORIZONTAL_ALIGNMENT_CENTER, 40, 5, UiTheme.WARN)


func _draw_decals() -> void:
	if blood.size() > 600:
		blood = blood.slice(blood.size() - 600)  # oldest stains fade from memory
	for b in blood:
		Look._dot(decals, b[0], b[1], b[2])  # fast circles: this redraws on every hit
	for pid in pickups:
		var pu: Dictionary = pickups[pid]
		# Things on the ground at their real size, with a glint so they are still seen.
		decals.draw_set_transform(pu.pos + Vector2(0, 1), 0, Vector2(1, 0.4))
		Look._dot(decals, Vector2.ZERO, 3.5, Color(0, 0, 0, 0.35))
		decals.draw_set_transform(Vector2.ZERO)
		Items.draw_icon(decals, Rect2(pu.pos + Vector2(-3.5, -6), Vector2(7, 7)), pu.item.id)
		Look._dot(decals, pu.pos + Vector2(2.5, -5.5), 0.9, Color(1, 1, 0.9, 0.9))



func _unhandled_input(event: InputEvent) -> void:
	if world and in_game and event is InputEventKey and not event.pressed and event.keycode == KEY_E and e_down_at >= 0.0:
		e_down_at = -1.0
		var rider: Player = players.get(multiplayer.get_unique_id())
		if rider and rider.riding >= 0:
			_request(&"req_interact", [])  # on a bike, E gets you off
			return
		if ui.wheel.visible:
			var a: Dictionary = ui.wheel.chosen()
			ui.wheel.close()
			if not a.is_empty():
				_request(&"req_act", [last_target.kind, last_target.id, a.verb])
		elif not last_actions.is_empty():
			# A tap does exactly what the prompt says, on exactly what it points at.
			var a := Interact.primary(last_actions)
			_request(&"req_act", [last_target.kind, last_target.id, a.verb])
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		ui.set_fullscreen(not ui.is_fullscreen())
		return
	if world and in_game and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k == KEY_ESCAPE:
			ui.escape()
			return
		if ui.pause.visible:
			return  # the pause menu takes the keys
		if k == KEY_H:
			ui.toggle_help()
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			ui.open_chat()
			get_viewport().set_input_as_handled()
		elif k == KEY_M:
			ui.toggle_map()
		elif k == KEY_Z:
			_request(&"req_sleep", [])
		elif k == KEY_F2 and (multiplayer.is_server() or "--admin" in OS.get_cmdline_user_args()):
			ui.admin.visible = not ui.admin.visible  # developer tools (see Admin)
		elif k == KEY_C:
			sneak_toggle = not sneak_toggle
			ui.push_feed("ย่อง: เงียบ ช้า มองเห็นยาก" if sneak_toggle else "เลิกย่อง")
		elif k == KEY_E:
			e_down_at = Time.get_ticks_msec() / 1000.0
		elif k == KEY_R:
			_request(&"req_reinforce", [])  # (boards up a door you face; otherwise reloads the gun in hand)
		elif k == KEY_F:
			_request(&"req_use", [])
		elif k == KEY_G:
			_request(&"req_drop", [])
		elif k >= KEY_1 and k <= KEY_8:
			_request(&"req_select", [k - KEY_1])
		elif k == KEY_TAB:
			ui.toggle_gear()
		elif k == KEY_Q:
			_request(&"req_quick_heal", [])
	if event is InputEventMouseButton and event.pressed:
		var slot := ui.hotbar.hover
		var me: Player = players.get(multiplayer.get_unique_id())
		if slot >= 0 and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			bar_click = true
			if me and slot < me.inv.size():
				if event.button_index == MOUSE_BUTTON_LEFT:
					_request(&"req_select", [slot])
				else:
					_request(&"req_use_slot", [slot])
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var up: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
			if event.ctrl_pressed:
				# Ctrl + wheel zooms; the wheel on its own flicks through the hotbar.
				play_zoom = (play_zoom * (1.1 if up else 1 / 1.1)).clamp(Vector2(1, 1), Vector2(6, 6))
				camera.zoom = play_zoom
			elif me and not me.inv.is_empty():
				_request(&"req_select", [posmod(me.sel + (-1 if up else 1), Items.INV_SIZE)])
