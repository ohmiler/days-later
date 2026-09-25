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
var hud: Label
var menu: PanelContainer
var address: LineEdit
var status: Label
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
var corpses: Array = []  # [pos, angle, skin, shirt, ttl]
var sparks: Array = []  # [pos, ttl, strong]
var shake := 0.0


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
	grade.material = ShaderMaterial.new()
	grade.material.shader = load("res://shaders/post.gdshader")
	post.add_child(grade)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(10, 10)
	hud.add_theme_constant_override("outline_size", 4)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(hud)
	_build_menu(layer)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	for arg in OS.get_cmdline_user_args():
		if arg == "--server":
			_host(true)
		elif arg.begins_with("--join="):
			address.text = arg.trim_prefix("--join=")
			_join()


func _build_menu(layer: CanvasLayer) -> void:
	menu = PanelContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(menu)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(280, 0)
	menu.add_child(box)
	var title := Label.new()
	title.text = "DAYS LATER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var host_btn := Button.new()
	host_btn.text = "Host (play + be the server)"
	host_btn.pressed.connect(_host.bind(false))
	box.add_child(host_btn)
	address = LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "Server address"
	box.add_child(address)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_join)
	box.add_child(join_btn)
	status = Label.new()
	box.add_child(status)


# --- Connection -------------------------------------------------------------

func _host(dedicated: bool) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	if peer.create_server(port) != OK:
		status.text = "Could not open port %d" % port
		return
	multiplayer.multiplayer_peer = peer
	_connect_once(multiplayer.peer_connected, _on_peer_connected)
	_connect_once(multiplayer.peer_disconnected, _on_peer_disconnected)
	world_seed = randi()
	_make_world(world_seed)
	for i in 25:
		_spawn_zombie()
	if not dedicated:
		_add_player(1)
	menu.hide()
	print("Server listening on port %d" % port)


func _join() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d" % [address.text.strip_edges(), port]
	if peer.create_client(url) != OK:
		status.text = "Bad address"
		return
	multiplayer.multiplayer_peer = peer
	_connect_once(multiplayer.connected_to_server, _on_connected)
	_connect_once(multiplayer.connection_failed, _on_connection_failed)
	_connect_once(multiplayer.server_disconnected, _on_server_lost)
	status.text = "Connecting to %s..." % url


## Multiplayer signals live on the SceneTree and survive a scene reload,
## so only hook them up if this scene hasn't already.
func _connect_once(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


func _on_connected() -> void:
	status.text = "Connected, loading world..."


func _on_connection_failed() -> void:
	status.text = "Connection failed"
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
	_add_player(id)
	print("Player %d joined (%d online)" % [id, players.size()])


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
	print("Player %d left (%d online)" % [id, players.size()])


@rpc("authority", "call_remote", "reliable")
func init_world(seed_val: int) -> void:
	_make_world(seed_val)
	menu.hide()
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
	z.position = pos
	z.net_pos = pos
	z.z_index = 1
	add_child(z)
	zombies[id] = z
	return z


# --- Server simulation ------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func send_input(move: Vector2, aim: Vector2, punch: bool, kick: bool) -> void:
	var p: Player = players.get(multiplayer.get_remote_sender_id())
	if p:
		p.move = move.limit_length(1.0)
		p.aim = aim
		p.punching = punch
		p.kicking = kick


func _server_tick(delta: float) -> void:
	time = fmod(time + delta / DAY_LENGTH, 1.0)
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
				_melee(p, Look.PUNCH_L, PUNCH)
	for z: Zombie in zombies.values():
		z.server_tick(delta)
	_separate()

	spawn_timer -= delta
	if spawn_timer <= 0 and zombies.size() < MAX_ZOMBIES:
		_spawn_zombie()
		spawn_timer = 1.5 if world.is_night else 5.0

	snap_timer -= delta
	if snap_timer <= 0:
		snap_timer = SNAPSHOT_RATE
		var ps := []
		for p: Player in players.values():
			ps.append([p.peer_id, p.position, p.aim, p.hp, p.kills])
		var zs := []
		for z: Zombie in zombies.values():
			zs.append([z.zid, z.position, z.hp])
		snapshot.rpc(ps, zs, time)


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
func _melee(p: Player, kind: int, stats: Array) -> void:
	p.shoot_cd = stats[2]
	fx_melee.rpc(p.peer_id, kind)
	p.pending_kind = kind
	p.pending_stats = stats
	p.pending_t = KICK_WINDUP if kind == Look.KICK else PUNCH_WINDUP


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
	if kind != Look.KICK:
		hits.sort_custom(func(a, b): return (a.position - p.position).normalized().dot(dir) > (b.position - p.position).normalized().dot(dir))
		hits = [hits[0]]
	for z: Zombie in hits:
		z.hp -= stats[1]
		z.stun = stats[3]
		z.position = world.slide(z.position, dir * stats[4], Zombie.RADIUS)
		fx_hit.rpc(z.zid, z.position, dir, kind == Look.KICK, p.peer_id)
		if z.hp <= 0:
			fx_death.rpc(z.position, z.facing, z.skin, z.shirt)
			zombies.erase(z.zid)
			z.queue_free()
			p.kills += 1


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
			fx_death.rpc(hit.position, hit.facing, hit.skin, hit.shirt)
			zombies.erase(hit.zid)
			hit.queue_free()
			p.kills += 1
	fx_shot.rpc(from, from + dir * length, hit != null)


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
func snapshot(ps: Array, zs: Array, t: float) -> void:
	if world == null:
		return
	time = t
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


@rpc("authority", "call_local", "unreliable")
func fx_hit(zid: int, pos: Vector2, dir: Vector2, strong: bool, attacker: int) -> void:
	var z: Zombie = zombies.get(zid)
	if z:
		z.flinch(dir)
	sparks.append([pos + Look.CHEST - dir * 3.0, 0.14, strong])
	for i in 4 if strong else 2:
		blood.append([pos + dir * randf_range(2, 8) + Vector2(randf_range(-3, 3), randf_range(-2, 2)),
				randf_range(0.8, 2.2), Color(randf_range(0.35, 0.5), 0.02, 0.02, 0.85)])
	decals.queue_redraw()
	if attacker == multiplayer.get_unique_id():
		shake = maxf(shake, 2.2 if strong else 1.3)


@rpc("authority", "call_local", "reliable")
func fx_death(pos: Vector2, ang: float, skin: Color, shirt: Color) -> void:
	corpses.append([pos, ang, skin, shirt, 30.0])
	for i in 6:
		blood.append([pos + Vector2(randf_range(-5, 5), randf_range(-5, 5)), randf_range(1.5, 4.0),
				Color(0.32, 0.02, 0.02, 0.8)])


func _process(delta: float) -> void:
	if world == null:
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
		me.aim = aim
		if multiplayer.is_server():
			me.move = move
			me.punching = punch
			me.kicking = kick
		else:
			send_input.rpc_id(1, move, aim, punch, kick)
			if me.alive():
				me.position = world.slide(me.position, move * Player.SPEED * delta, Player.RADIUS)
		camera.position = me.position + Look.CHEST
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
		shake = move_toward(shake, 0.0, delta * 14.0)
		_fade_trees_near(me.position)

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
	if not corpses.is_empty():
		for c in corpses:
			c[4] -= delta
		corpses = corpses.filter(func(c): return c[4] > 0)
		decals.queue_redraw()

	hud.text = "%s   Players: %d   Zombies: %d" % [
		"NIGHT" if world.is_night else "Day", players.size(), zombies.size()]
	if me:
		hud.text = "HP %d   Kills %d   " % [me.hp, me.kills] + hud.text
		if not me.alive():
			hud.text += "\n\nYOU DIED - respawning in %d..." % ceili(me.respawn)
	hud.text += "\nWASD move | mouse aim | LMB punch | RMB kick | wheel zoom"


var faded: Array = []


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


func _draw_decals() -> void:
	for b in blood:
		decals.draw_circle(b[0], b[1], b[2])
	for c in corpses:
		Look.draw_corpse(decals, c[1], c[2], c[3], minf(1.0, c[4] / 5.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(1, 1), Vector2(6, 6))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.1).clamp(Vector2(1, 1), Vector2(6, 6))
