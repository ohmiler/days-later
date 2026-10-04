class_name Net
extends Node
## Joining: the hello handshake, names, the first sync, snapshots, input and chat.
## Split out of main.gd; shared state (world, players, zombies, pickups) lives there.

var main: Main


# Melee: [range, damage, cooldown, stun, knockback]
## Bump when the messages between game and server change in a way an older
## copy would misread; a client on another number is turned away with a
## message instead of breaking in strange ways.
const PROTOCOL := 44  # 44: remains (Remains rpcs add, gone: what you had stays with your body), lingering on leaving mid-danger; 43: city events (Events: an ice-cream truck, a door chime, a ringing phone, karaoke, the lottery seller; item lotto; four new sounds); 42: the police station (tier 4 loot, the chief boss, riotgun, police zombies); 41: parked cars are real (Vehicles._park_cars: the city has cars, ids after the bikes); 40: cars driven W/S pedals A/D wheel (the move means pedals and wheel in a car); 39: trial car (Vehicles.vehicle_add, sedan model, car steering); 38: the refugee camp (Camp rpcs none new; things volunteer, board; GEN 10; dailies from the board); 37: skill unlocks do things (Skills.has; treat_other, stitched wounds, recipe unlocks, fishrice); 36: army knife 80 hp, mended with scrap at craft Lv 20 (repair_lv); 35: bosses (Bosses rpcs fx_enrage, boss_down; boss zids; army_shirt, armyknife); 34: loot by how dangerous a place is (Items tier, 3 new items); 33: body proportions V5 and a height in the appearance code (Look.HEIGHTS first); 32: round 0 (shutter 300 hp + scrap repair, safe = the shell, no spawns indoors); 31: search_started says what the work is (what, recipe); 30: quests (Quests rpcs: quests_sync, quest_done); 29: skills (Skills rpcs: skills_sync, survivor_level, fx_level_up); 28: no crawling (P_PRONE gone, req_prone gone); 27: silent kill played out (fx_stealth); 26: crawlers (missing 4 bits, storey 4 bits), silent kills; 25: hit zones (fx_hit zone, kill), new death styles; 24: four new zombie kinds, flag 16, pills/whistle; 23: place items (round B), shut-in zombies; 22: big buildings (CityGen.GEN 9), generators, power; 21: WorldState (things, buildings), rain in every snapshot; 20: storeys
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
	# Back while their body is still standing where they left it: they take it up again.
	for q: Player in main.players.values():
		if q != p and q.linger >= 0.0 and q.pname == wanted and q.secret_hash == mine:
			_remove(q)  # (saved: loaded straight back below)
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
		p.body_dirty = true  # (their wounds came back with them)
	elif p.bed >= 0:
		p.position = p.home_spawn()  # died last time: the new survivor starts at the old bed
		main._toast(p, "ตื่นขึ้นที่เตียงประจำ")


## Send a newly accepted player the city as it is now and give them a body.
func _welcome(id: int) -> void:
	send_world(id)
	main._add_player(id)
	print("Player %d joined (%d online)" % [id, main.players.size()])


## The zone as it is now, to a player: its seed (they build it themselves)
## and everything that has changed since.
func send_world(id: int) -> void:
	reset_peer(id)  # (everything it knows is sent again)
	init_world.rpc_id(id, main.world_seed, main.zone)
	var searched := []
	var stripped := []
	for f: FurnitureProp in main.world.container_nodes:
		if f.searched:
			searched.append(f.data.id)
		if f.stripped:
			stripped.append(f.data.id)
	var items := []
	for pid in main.pickups:
		items.append([pid, main.pickups[pid].pos, main.pickups[pid].item, main.pickups[pid].get("storey", 0)])
	var doors := []
	for d in main.world.doors:
		doors.append([d.id, d.closed, d.hp, d.boards, d.broken, d.kind if main.world.is_built(d.id) else "", d.cell])
	sync_state.rpc_id(id, searched, items, doors, stripped)
	main.world_state.send_all(id)
	main.vehicles.send_all(id)
	main.corpses_sync.rpc_id(id, main.corpse_list())
	main.remains.send_all(id)


func _on_peer_disconnected(id: int) -> void:
	pending.erase(id)
	reset_peer(id)
	if main.players.has(id):
		var p: Player = main.players[id]
		main.vehicles.dismount(p)
		if p.travel_to == "" and in_danger(p):
			# Left in the middle of it: the body stays a while (no escaping a
			# fight by closing the game). Back in time, they carry on in it.
			p.linger = LINGER
			p.move = Vector2.ZERO
			p.sprint = false
			p.sneak = false
			p.aiming = false
			p.set_attack_input(false, false)
			print("Player %d left mid-danger: stays %.0f s" % [id, LINGER])
			return
		_remove(p)
	print("Player %d left (%d online)" % [id, main.players.size()])


const LINGER := 30.0  # seconds a survivor who left mid-danger stays in the world
const DANGER_NEAR := 160.0  # a zombie this close (or after them) is danger
const DANGER_HURT := 10.0  # hurt this recently is danger


## Whether leaving now would be running out of a fight: something after them
## or close by, or just hurt. (Not in the camp: it's safe there.)
func in_danger(p: Player) -> bool:
	if not p.alive() or main.world == null or main.world.in_camp(p.position):
		return false
	if Time.get_ticks_msec() / 1000.0 - p.hurt_at < DANGER_HURT:
		return true
	for z: Zombie in main.zombies.values():
		if z.target == p or (z.storey == p.storey and z.position.distance_to(p.position) < DANGER_NEAR and z.hp > 0.0):
			return true
	return false


## Gone from this world: saved as they are, and taken out.
func _remove(p: Player) -> void:
	if p.travel_to == "":  # (on their way to another zone's server: saved already)
		SaveGame.save_player(p)
	main.players.erase(p.peer_id)
	p.queue_free()


## Server, every tick: those staying on after leaving. Their time runs out, or
## they die (what they had stays with the body: Remains), and they're gone.
func tick_lingering(delta: float) -> void:
	for p: Player in main.players.values():
		if p.linger < 0.0:
			continue
		p.linger -= delta
		if p.linger <= 0.0 or (not p.alive() and p.dropped):
			print("Player %d's body is gone from the world" % p.peer_id)
			_remove(p)


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
		main.pickup_add(e[0], e[1], e[2], int(e[3]) if e.size() > 3 else 0)


@rpc("authority", "call_remote", "reliable")
func init_world(seed_val: int, zone_id := "") -> void:
	main._clear_backdrop()
	main._drop_world()  # (arriving in a new zone with the group)
	main.zone = zone_id if zone_id != "" else Zones.first()
	main._make_world(seed_val)
	for p: Player in main.players.values():
		p.world = main.world
	main.in_game = true
	main.ui.show_menu(false)
	main.ui.announce(Zones.name_of(main.zone))
	print("Joined %s, seed %d" % [main.zone, seed_val])


## Zones run as separate servers: this one hands you over to the next.
@rpc("authority", "call_remote", "reliable")
func go_zone(zone_id: String, port_: int) -> void:
	main.travel_to_server(zone_id, port_)


# --- Server simulation ------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func send_input(move: Vector2, aim: Vector2, punch: bool, kick: bool, sprint: bool, sneak: bool, aiming := false) -> void:
	var p: Player = main.players.get(multiplayer.get_remote_sender_id())
	if p:
		p.aiming = aiming and p.gun_hand() != ""
		p.sprint = sprint
		p.sneak = sneak
		p.move = move.limit_length(1.0)
		p.aim = aim
		p.set_attack_input(punch, kick)


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


# --- Snapshots (server) --------------------------------------------------------
# Every SNAPSHOT_RATE each player is sent one packed snapshot (NetCodec): the
# players as everyone sees them; what only they should know, when it changed;
# and the zombies around them - those close by ten times a second while they
# move, those further off less often, those standing still once a second to
# say they're still there, and the ones gone out of reach, to forget. Names,
# looks and clothes go on their own, reliably, when they change (player_info).
# A zombie that has only moved (or changed what it's doing) goes as a nudge
# from where it was last sent (7 bytes, not 11); in full once a second, so
# a lost snapshot's nudge is put right. Other players go every other
# snapshot (ten a second: played back smoothly), yourself every one.

const ZOMBIE_NEAR := 320.0  # px: zombies this close (the screen and a margin, at the usual zoom) are kept up to date quickly...
const ZOMBIE_RATE := 0.1  # ...every this many seconds while they move
const ZOMBIE_FAR_RATE := 0.3  # (further off)
const KEEPALIVE := 1.0  # an unchanged zombie is still sent this often, to say it's there
const FORGET := 2.5  # client: a zombie not heard of for this long has gone
const GONE_REPEATS := 3  # (snapshots can be lost: a zombie to forget is named this many times)
var clock := 0.0  # seconds, the server's: snapshots are stamped with it (the client keeps its own copy)
var _snap_t := 0.0
var _snap_n := 0  # snapshots sent (every other one carries everyone, not just you)
var _sent := {}  # server: peer -> what it has been sent (see _record)


func _record(peer: int) -> Dictionary:
	if not _sent.has(peer):
		_sent[peer] = {z = {}, gone = {}, info = {}, own = PackedByteArray()}
	return _sent[peer]


## Forget what `peer` was sent (they left, or moved to another zone: start afresh).
func reset_peer(peer: int) -> void:
	_sent.erase(peer)


## Server, every tick.
func send_snapshots(delta: float) -> void:
	clock += delta
	_snap_t -= delta
	if _snap_t > 0.0:
		return
	_snap_t = main.SNAPSHOT_RATE
	_snap_n += 1
	for peer in multiplayer.get_peers():
		if not main.players.has(peer):
			continue  # (still saying hello)
		_send_info(peer)
		snapshot.rpc_id(peer, build_snapshot(peer))


## Names, looks and clothes: sent to `peer` for each player when they change.
func _send_info(peer: int) -> void:
	var rec := _record(peer)
	for p: Player in main.players.values():
		var key := "%s|%d|%s" % [p.pname, p.app_code, p.wear_ids]
		if rec.info.get(p.peer_id, "") != key:
			rec.info[p.peer_id] = key
			player_info.rpc_id(peer, p.peer_id, p.pname, p.app_code, p.wear_ids)
	main.skills.send_all(peer)


## One snapshot for `peer`, packed (see NetCodec). Updates what they've been sent.
func build_snapshot(peer: int) -> PackedByteArray:
	var rec := _record(peer)
	var b := StreamPeerBuffer.new()
	b.put_float(clock)
	b.put_float(main.time)
	b.put_float(main.rain_total)
	b.put_u16(main.day)
	var everyone := _snap_n % 2 == 0
	b.put_u8((1 if main.raining else 0) | (2 if everyone else 0))
	var me: Player = main.players.get(peer)
	var ps: Array = main.players.values() if everyone or me == null else [me]
	b.put_u8(ps.size())
	for p: Player in ps:
		NetCodec.put_player(b, p)
	var own := NetCodec.own_bytes(me, main.world) if me else PackedByteArray()
	if own != rec.own:
		rec.own = own
		b.put_u8(own.size())
		b.put_data(own)
	else:
		b.put_u8(0)
	var full := PackedByteArray()
	var nudges := PackedByteArray()
	var n_full := 0
	var n_nudge := 0
	var near := {}
	for z: Zombie in main.zombies_for(me):
		near[z.zid] = true
		var bytes := NetCodec.zombie_bytes(z)
		# rec.z[zid] = [bytes last sent, when, when last sent in full]
		var last: Array = rec.z.get(z.zid, [])
		var since: float = clock - last[1] if not last.is_empty() else INF
		var rate := ZOMBIE_RATE if me.position.distance_to(z.position) < ZOMBIE_NEAR else ZOMBIE_FAR_RATE
		if not (last.is_empty() or since >= KEEPALIVE or (bytes != last[0] and since >= rate - 0.001)):
			continue
		var nudge := PackedByteArray() if last.is_empty() or clock - last[2] >= KEEPALIVE else NetCodec.nudge(last[0], bytes)
		if nudge.is_empty():
			full.append_array(bytes)
			n_full += 1
			rec.z[z.zid] = [bytes, clock, clock]
		else:
			nudges.append_array(nudge)
			n_nudge += 1
			rec.z[z.zid] = [bytes, clock, last[2]]
	for zid in rec.z.keys():
		if not near.has(zid):
			rec.z.erase(zid)
			rec.gone[zid] = GONE_REPEATS
	b.put_u16(n_full)
	b.put_data(full)
	b.put_u16(n_nudge)
	b.put_data(nudges)
	b.put_u16(rec.gone.size())
	for zid in rec.gone.keys():
		b.put_u32(zid)
		rec.gone[zid] -= 1
		if rec.gone[zid] <= 0:
			rec.gone.erase(zid)
	return b.data_array


# --- Client side ------------------------------------------------------------

## Client: a player's name, look and clothes (sent when they change).
@rpc("authority", "call_remote", "reliable")
func player_info(id: int, pname: String, app_code: int, wear_ids: Dictionary) -> void:
	if main.world == null:
		return
	var p: Player = main.players.get(id)
	if p == null:
		p = main._add_player(id)
	p.pname = pname
	if app_code != p.app_code:
		p.set_appearance(app_code)
	if wear_ids != p.wear_ids:
		p.set_wear(wear_ids)


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server() or main.world == null:
		return
	clock += delta  # (kept near the server's by each snapshot)
	# Zombies not heard of for a while have gone (out of reach, or a lost "gone").
	for id in main.zombies.keys():
		var z: Zombie = main.zombies[id]
		if clock - z.heard > FORGET:
			z.queue_free()
			main.zombies.erase(id)


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(data: PackedByteArray) -> void:
	if main.world == null or not main.in_game:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var at := b.get_float()  # the server's clock when it was sent
	if absf(clock - at) > 0.5:
		clock = at
	else:
		clock = lerpf(clock, at, 0.1)
	main.time = b.get_float()
	main.rain_total = b.get_float()
	main.day = b.get_u16()
	var bits := b.get_u8()
	main.survival._set_rain(bits & 1 != 0)
	var everyone := bits & 2 != 0  # (else only us: the others come every other snapshot)
	var seen := {}
	for k in b.get_u8():
		var d := NetCodec.get_player(b)
		var id: int = d.id
		seen[id] = true
		var p: Player = main.players.get(id)
		if p == null:
			p = main._add_player(id)
			p.position = d.pos
		p.net_pos = d.pos
		if not p.is_local:
			p.aim = d.aim
			p.sprint = d.sprint
			p.sneak = d.sneak
			p.aiming = d.aiming
			p.push_sample(at, d.pos)
		p.hp = d.hp
		p.weapon_id = d.weapon
		p.stamina = d.stamina
		p.exhausted = d.exhausted
		p.bleeding = d.bleeding
		p.on_roof = d.on_roof
		p.sleeping = d.sleeping
		p.storey = d.storey
		p.sitting = d.sitting
		p.rest_face = d.rest_face
		p.on_car = d.on_car
		p.grabbed_by = d.grabbed_by
		p.struggle = d.struggle
		var seat: int = d.seat
		if (d.riding != p.riding or seat != p.seat) and not (p.is_local and d.riding >= 0 and p.riding >= 0 and seat == p.seat):
			if p.riding >= 0:  # got off: the bike is drawn where it stands again
				var old: Dictionary = main.world.vehicles[p.riding]
				if p.seat == 1:
					old.pillion = 0
				else:
					old.rider = 0
					if Vehicles.is_car(old):
						Vehicles.block_parked(main.world, old)  # (left where it stands: solid again)
				Vehicles._place(old)
			p.riding = d.riding
			p.seat = seat if p.riding >= 0 else 0
			p.ride_vel = Vector2.ZERO
			if p.riding >= 0:
				if p.seat == 1:
					main.world.vehicles[p.riding].pillion = p.peer_id
				else:
					main.world.vehicles[p.riding].rider = p.peer_id
					if Vehicles.is_car(main.world.vehicles[p.riding]):
						Vehicles.free_cells(main.world, main.world.vehicles[p.riding])  # (driven: it carries its own collision)
				Vehicles._place(main.world.vehicles[p.riding])
		if p.riding >= 0 and p.seat == 0 and not p.is_local:
			# Someone else riding by: the bike goes with them.
			var v: Dictionary = main.world.vehicles[p.riding]
			Vehicles.turn_to(v, (d.pos - v.pos) / main.SNAPSHOT_RATE)
			v.pos = d.pos
			v.upright = true
			Vehicles._place(v)
	var own_size := b.get_u8()
	if own_size > 0:
		var own := NetCodec.read_own(b.get_data(own_size)[1])
		var me: Player = main.players.get(multiplayer.get_unique_id())
		if me:
			me.hunger = own.hunger
			me.thirst = own.thirst
			me.infection = own.infection
			me.kills = own.kills
			me.bed = own.bed
			me.sleep_bed = own.sleep_bed
			if me.riding >= 0 and me.seat == 0:
				main.world.vehicles[me.riding].fuel = own.fuel
	for id in main.players.keys():
		if everyone and not seen.has(id):
			var gone: Player = main.players[id]
			if gone.riding >= 0 and gone.riding < main.world.vehicles.size():  # left mid-ride: the bike stays, empty
				var v: Dictionary = main.world.vehicles[gone.riding]
				if v.rider == id:
					v.rider = 0
				if v.pillion == id:
					v.pillion = 0
				Vehicles._place(v)
			gone.queue_free()
			main.players.erase(id)
	for k in b.get_u16():
		var d := NetCodec.get_zombie(b)
		var z: Zombie = main.zombies.get(d.id)
		if z == null:
			z = main._add_zombie(d.id, d.pos)
		z.push_sample(at, d.pos)
		z.heard = clock
		z.hp = d.hp
		z.state = d.state
		z.flags = d.flags
		z.missing = d.missing
		z.storey = d.storey
	for k in b.get_u16():
		var d := NetCodec.get_nudge(b)
		var z: Zombie = main.zombies.get(d.id)
		if z == null:
			continue  # (its full description was lost: it comes again within a second)
		z.push_sample(at, z.net_pos + d.move)
		z.heard = clock
		z.state = d.state
		z.flags = d.flags
	for k in b.get_u16():
		var id := b.get_u32()
		if main.zombies.has(id):
			main.zombies[id].queue_free()
			main.zombies.erase(id)
