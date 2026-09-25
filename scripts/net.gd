class_name Net
extends Node
## Joining: the hello handshake, names, the first sync, snapshots, input and chat.
## Split out of main.gd; shared state (world, players, zombies, pickups) lives there.

var main: Main


# Melee: [range, damage, cooldown, stun, knockback]
## Bump when the messages between game and server change in a way an older
## copy would misread; a client on another number is turned away with a
## message instead of breaking in strange ways.
const PROTOCOL := 8
const HELLO_TIMEOUT := 10.0  # seconds a new connection has to say who it is
var protocol := PROTOCOL  # what this copy says it speaks (tests set it wrong on purpose)
var pending := {}  # server: peer id -> seconds since it connected, until it says hello
func _on_connected() -> void:
	main.ui.set_status("เชื่อมต่อแล้ว กำลังโหลดเมือง...")
	req_hello.rpc_id(1, protocol, main.player_name if main.player_name != "" else main.ui.player_name(), main.ui.secret(), main.ui.appearance_code())


func _on_connection_failed() -> void:
	main.ui.set_status("เชื่อมต่อไม่สำเร็จ")
	multiplayer.multiplayer_peer = null


func _on_server_lost() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()


## Someone connected. Nothing is sent until they say hello with the right version.
func _on_peer_connected(id: int) -> void:
	pending[id] = 0.0


## Client -> server, first thing after connecting: who they are and what they speak.
@rpc("any_peer", "call_remote", "reliable")
func req_hello(proto: int, name_wanted: String, secret: String, app_code: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not pending.has(id):
		return
	pending.erase(id)
	if proto != PROTOCOL:
		turned_away.rpc_id(id, "เวอร์ชันเกมไม่ตรงกับเซิร์ฟเวอร์ (เกม %d · เซิร์ฟเวอร์ %d) · กรุณาอัปเดตเกม" % [proto, PROTOCOL])
		_drop_peer.call_deferred(id)
		print("Turned away peer %d: protocol %d, server %d" % [id, proto, PROTOCOL])
		return
	_welcome(id)
	var p: Player = main.players[id]
	p.set_appearance(posmod(app_code, Look.appearance_count()))
	_claim_name(p, name_wanted, secret)
	main.inventory._send_inv(p)


## Client: the server would not let us in.
@rpc("authority", "call_remote", "reliable")
func turned_away(reason: String) -> void:
	main.ui.set_status(reason)
	main.ui.show_menu(true)


func _drop_peer(id: int) -> void:
	await get_tree().create_timer(0.5).timeout  # let the reason reach them first
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		multiplayer.multiplayer_peer.disconnect_peer(id)


## Take a survivor's name. A name with a save belongs to whoever made it, as
## proven by the secret their copy of the game keeps; someone else asking for
## it gets a variation instead. An old save with no owner goes to the first
## to use it.
func _claim_name(p: Player, wanted: String, secret: String) -> void:
	wanted = wanted.strip_edges().left(16)
	if wanted == "":
		wanted = "ผู้รอดชีวิต"
	var mine := secret.sha256_text()
	var asked := wanted
	for attempt in 50:
		var online := main.players.values().any(func(q): return q != p and q.pname == wanted)
		var owner := SaveGame.owner_of(wanted)
		if not online and (owner == "" or owner == mine):
			break
		wanted = "%s %d" % [asked.left(13), randi_range(2, 99)]
	p.pname = wanted
	p.secret_hash = mine
	if wanted != asked:
		main._toast(p, "ชื่อ %s มีเจ้าของแล้ว · ใช้ชื่อ %s แทน" % [asked, wanted])
	elif SaveGame.load_player_into(p, wanted):
		main._toast(p, "ยินดีต้อนรับกลับ %s" % wanted)
	elif p.bed >= 0:
		p.position = p.home_spawn()  # died last time: the new survivor starts at the old bed
		main._toast(p, "ตื่นขึ้นที่เตียงประจำ")


## Send a newly accepted player the city as it is now and give them a body.
func _welcome(id: int) -> void:
	init_world.rpc_id(id, main.world_seed)
	var searched := []
	var stripped := []
	for f: FurnitureProp in main.world.container_nodes:
		if f.searched:
			searched.append(f.data.id)
		if f.stripped:
			stripped.append(f.data.id)
	var items := []
	for pid in main.pickups:
		items.append([pid, main.pickups[pid].pos, main.pickups[pid].item])
	var doors := []
	for d in main.world.doors:
		doors.append([d.id, d.closed, d.hp, d.boards, d.broken, d.kind if main.world.is_built(d.id) else "", d.cell])
	sync_state.rpc_id(id, searched, items, doors, stripped)
	main.things.send_all(id)
	main.vehicles.send_all(id)
	main._add_player(id)
	print("Player %d joined (%d online)" % [id, main.players.size()])


func _on_peer_disconnected(id: int) -> void:
	pending.erase(id)
	if main.players.has(id):
		main.vehicles.dismount(main.players[id])
		SaveGame.save_player(main.players[id])
		main.players[id].queue_free()
		main.players.erase(id)
	print("Player %d left (%d online)" % [id, main.players.size()])


@rpc("authority", "call_remote", "reliable")
func sync_state(searched: Array, items: Array, doors: Array, stripped: Array) -> void:
	for e in doors:
		if e[5] != "":
			main.world.add_structure(e[0], e[6], e[5], e[2])
		main.world.set_door(e[0], e[1], e[2], e[3], e[4])
	for id in searched:
		main.world.container_nodes[id].set_searched(true)
	for id in stripped:
		main.world.container_nodes[id].set_stripped(true)
	for e in items:
		main.pickup_add(e[0], e[1], e[2])


@rpc("authority", "call_remote", "reliable")
func init_world(seed_val: int) -> void:
	main._clear_backdrop()
	main._make_world(seed_val)
	main.in_game = true
	main.ui.show_menu(false)
	print("Joined world, seed %d" % seed_val)


# --- Server simulation ------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func send_input(move: Vector2, aim: Vector2, punch: bool, kick: bool, sprint: bool, sneak: bool) -> void:
	var p: Player = main.players.get(multiplayer.get_remote_sender_id())
	if p:
		p.sprint = sprint
		p.sneak = sneak
		p.move = move.limit_length(1.0)
		p.aim = aim
		p.punching = punch
		p.kicking = kick


# --- Chat and leaving --------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func req_chat(text: String) -> void:
	var p := main._sender()
	if p == null:
		return
	var msg := text.strip_edges().left(120)
	if msg != "":
		chat_msg.rpc(p.peer_id, p.pname, msg)


@rpc("authority", "call_local", "reliable")
func chat_msg(peer_id: int, who: String, text: String) -> void:
	main.ui.show_chat(who, text)
	var p: Player = main.players.get(peer_id)
	if p:
		p.say = text
		p.say_t = 5.0 + text.length() * 0.05


# --- Client side ------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(ps: Array, zs: Array, t: float, d: int, rain := false) -> void:
	if main.world == null or not main.in_game:
		return
	main.time = t
	main.day = d
	main.survival._set_rain(rain)
	var seen := {}
	for e in ps:
		var id: int = e[0]
		seen[id] = true
		var p: Player = main.players.get(id)
		if p == null:
			p = main._add_player(id)
			p.position = e[1]
		p.net_pos = e[1]
		if not p.is_local:
			p.aim = e[2]
		p.hp = e[3]
		p.kills = e[4]
		p.weapon_id = e[5]
		p.pname = e[6]
		if e[8] != p.app_code:
			p.set_appearance(e[8])
		if e[9] != p.wear_ids:
			p.set_wear(e[9])
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
		p.on_roof = n[8]
		p.sleeping = n[9]
		p.bed = n[10]
		p.sleep_bed = n[11]
		if n[12] != p.riding and not (p.is_local and n[12] >= 0 and p.riding >= 0):
			if p.riding >= 0:  # got off: the bike is drawn where it stands again
				main.world.vehicles[p.riding].rider = 0
				Vehicles._place(main.world.vehicles[p.riding])
			p.riding = n[12]
			p.ride_vel = Vector2.ZERO
			if p.riding >= 0:
				main.world.vehicles[p.riding].rider = p.peer_id
				Vehicles._place(main.world.vehicles[p.riding])
		if p.riding >= 0:
			var v: Dictionary = main.world.vehicles[p.riding]
			v.fuel = n[13]
			if not p.is_local:  # someone else riding by: the bike goes with them
				Vehicles.turn_to(v, (e[1] - v.pos) / main.SNAPSHOT_RATE)
				v.pos = e[1]
				v.upright = true
				Vehicles._place(v)
	for id in main.players.keys():
		if not seen.has(id):
			main.players[id].queue_free()
			main.players.erase(id)
	seen.clear()
	for e in zs:
		var id: int = e[0]
		seen[id] = true
		var z: Zombie = main.zombies.get(id)
		if z == null:
			z = main._add_zombie(id, e[1])
		z.net_pos = e[1]
		z.hp = e[2]
		z.state = e[3]
		z.flags = e[4]
		z.missing = e[5]
	for id in main.zombies.keys():
		if not seen.has(id):
			main.zombies[id].queue_free()
			main.zombies.erase(id)
