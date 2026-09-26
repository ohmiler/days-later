class_name Player
extends Node2D
## A connected player. The server simulates it; clients predict their own
## player and interpolate everyone else toward the server snapshot.

const SPEED := 55.0  # walking; zombies shamble at 25-38, runners at 64, so only sprinting outruns those
const RADIUS := 5.0
const MAX_HP := 100.0
const RESPAWN_TIME := 5.0

var world: World
var peer_id := 0
var is_local := false
var hp := MAX_HP
var kills := 0
var aim := Vector2.RIGHT
var move := Vector2.ZERO
var punching := false
var kicking := false
var anim := Look.NONE
var anim_t := 0.0
var punch_side := false
# Server only: a swing lands a moment after it starts, when the limb is extended.
var pending_kind := Look.NONE
var pending_t := 0.0
var pending_stats: Array = []
# Inventory: server-authoritative; the owning client gets a copy via main.inventory.inv_sync.
var inv: Array = []  # INV_SIZE entries of null or {id, n, hp}
var sel := 0
var weapon_id := ""  # what everyone sees in this player's right hand (the left is in wear_ids)
var next_hand := "r"  # server: the hand the next swing comes from (swings alternate)
var muzzle := Vector2(0, -15)  # tip of the gun as last drawn, in this node's space
var aiming := false  # right mouse held with a gun in hand: raised, slow, the left button fires
var swing_hand := "r"  # server: the hand of the swing under way
var search_id := -1  # server only: container being searched
var search_t := 0.0
var craft := {}  # server: the making/mending job under way ({kind, t, ...}; see Crafting)
var dropped := false  # server only: death bag already dropped this life
var death_t := 0.0  # seconds since dying (every peer, drives the fall)
var pname := ""  # shown above the head
# Survival needs, 0..100. Server-authoritative, sent to everyone in snapshots.
var hunger := 80.0  # 100 = full
var thirst := 80.0  # 100 = fully hydrated
var infection := 0.0  # 100 = you turn
var bleeding := false
var stamina := 100.0
var exhausted := false  # ran dry: no sprinting until stamina recovers
var sprint := false
var sneak := false  # Ctrl / C: slow, quiet, harder to spot
var on_roof := false  # up on the shophouse roofs: zombies can't follow
var up := false  # upstairs in a shophouse (World.upper): zombies can follow, by the stairs
var lift := 0.0  # current drawn height above the street (eases between roofs)
var _pose := {}  # what the body last showed, for easing between poses (Rig.build_eased)
var step_t := 0.0  # server: time to the next footstep noise
var bitten := false  # server: set by a zombie bite, handled by main
var turned := false  # died of the infection and got back up as a zombie
var warned := {}  # server: which low-need warnings were already sent
var fall_dir := 1.0
var last_death_pos := Vector2.ZERO
var last_death_up := false  # died upstairs: the body stays up there
var shoot_cd := 0.0
var punch_buf := 0.0  # a click that came while still busy: acted on when ready (see set_attack_input)
var kick_buf := 0.0
var sight_k := 1.0  # someone else, on your screen: 0 when out of your character's sight (see Sight)
var hitstop := 0.0  # the attack animation holds still this long when a blow lands
var local_cd := 0.0  # client, local player: its own guess at shoot_cd, to swing on the click
var predicted := 0  # client, local player: swings shown early, still to be confirmed by the server
var respawn := 0.0
var net_pos := Vector2.ZERO
var skin: Color
var shirt: Color
var hair: Color
var pants: Color
var app_code := -1  # appearance, packed (Look.pack); the player picks it in the menu
var look := {}  # colours and shapes to draw with, from app_code
# Clothes: server keeps the items (slot -> {id, n, hp}); every machine knows
# the ids (slot -> id, from snapshots), which is all drawing and speed need.
var worn := {}
var wear_ids := {}
var secret_hash := ""  # server: fingerprint of the secret that owns this name (never the secret itself)
var say := ""  # last thing said in chat, shown over their head for say_t seconds
var say_t := 0.0
var open_box := -1  # server: the container this player has open in the bag screen
var torn := ""  # server: name of something a bite just tore apart, for main to report
var wounds: Array = []  # see Body (server; the owner's machine gets a copy)
var body_dirty := false  # server: wounds changed, send them to the owner
var body_sync_t := 0.0  # server: time to the next refresh of the owner's copy
var last_window := -1  # server: the smashed window being climbed through (glass cuts)
var bite_where := ""  # server: where the last bite landed, and how much of it was stopped
var bite_guard := 0.0
var phase := 0.0
var sleeping := false  # lying on a bed: can't move, heals, the night goes faster
var bed := -1  # the bed (container id) this survivor calls home: where they wake after dying
var sleep_check := 0.0  # server: time to the next look around while asleep
var sleep_bed := -1  # the bed slept in now (-1: the floor)
var sitting := -1  # -1 on your feet; -2 sat on the floor; else the World.decor you sit on (a sofa, a stool...)
var rest_face := 0  # which way you lay down or sat: 0 right, 1 left, 2 down (towards us), 3 up (away)
var getup_t := 0.0  # server: still getting to your feet, not moving yet
var travel_to := ""  # server: the zone they're on their way to (saved, so the next zone's server knows where they come in)
var travel_exit := ""  # ...and by which way in
var on_car := -1  # standing on this vehicle's roof (World.street_props id): zombies can't reach, but gather
var car_t := 0.0  # server: how long you've been up there (a moment before a step jumps you down)
var rest_k := 0.0  # drawn, every machine: 0 standing .. 1 all the way down (lying or sat)
var _rest_lying := false  # (what the last rest was, to get up out of the right pose)
const LIE_TIME := 0.9  # seconds to lie down (and to get up again)
const SIT_TIME := 0.5

var riding := -1  # the bike (World.vehicles id) being ridden, or -1
var seat := 0  # on a bike: 0 riding it, 1 on the back (pillion: the rider steers, you can fight)
var ride_vel := Vector2.ZERO  # a rider's speed and heading (server, and the rider's own machine)
# How a rider looks turning (every machine, just for show): the view the bike
# is turning from, how far through the turn, and how far it leans.
var turn_from := ["side", 1.0]
var turn_t := 0.0
var lean := 0.0
var last_heading := 0.0
var dust_t := 0.0
var ride_seen := Vector2.ZERO  # the bike's velocity as drawn (every peer, smoothed): the camera looks ahead by it
var engine: AudioStreamPlayer2D  # the running engine, while riding (not on a headless server)
var headlight: PointLight2D  # the beam ahead, riding at night
var ride_spd := 0.0  # how fast the bike is going, as drawn (every peer), and its change
var ride_acc := 0.0
var wheel_turn := 0.0  # how far round the wheels have rolled
var ride_t := 0.0  # a clock for the engine's shake
var puff_t := 0.0
const TURN_TIME := 0.16
var sleep_safe := false  # server: that bed's building is shut tight (checked each second)
var view := [Look.FRONT, false]
var moving := false
var last_pos := Vector2.ZERO
var night_eyes: PointLight2D  # local player only: at night you make out a few metres around you


func _init() -> void:
	inv.resize(Items.INV_SIZE)


## The weapon in the selected slot, or "" for bare fists.
## The hand holding a gun ("r" first), or "".
func gun_hand() -> String:
	for h in ["r", "l"]:
		if Items.is_gun(hand_weapon(h)):
			return h
	return ""


## The weapon in the right hand (every machine knows, from wear_ids), or "".
func held_weapon() -> String:
	return wear_ids.get("hand_r", "")


func hand_weapon(hand: String) -> String:
	return wear_ids.get("hand_" + hand, "")


## Holding any of these, in either hand.
func holds(ids: Array) -> bool:
	return wear_ids.get("hand_r", "") in ids or wear_ids.get("hand_l", "") in ids


func alive() -> bool:
	return hp > 0


func take_damage(amount: float) -> void:
	if not alive():
		return
	hp -= amount
	if sleeping or sitting != -1:
		stand_up()  # pain wakes you (and gets you up)
	if hp <= 0:
		hp = 0
		respawn = RESPAWN_TIME


## Start an attack animation (runs on every peer via main.combat.fx_melee).
func play_attack(kind: int) -> void:
	anim = kind  # (the server says which hand: swings alternate between them)
	anim_t = 0.0
	hitstop = 0.0


const ATTACK_BUFFER := 0.25  # how early a click can come and still count


## The attack buttons as they are this frame. A new press while still busy is
## remembered for a moment, so clicking in rhythm never loses a blow.
func set_attack_input(punch: bool, kick: bool) -> void:
	if punch and not punching:
		punch_buf = ATTACK_BUFFER
	if kick and not kicking:
		kick_buf = ATTACK_BUFFER
	punching = punch
	kicking = kick


func wants_punch() -> bool:
	return punching or punch_buf > 0.0


func wants_kick() -> bool:
	return kicking or kick_buf > 0.0


## Server only.
func server_tick(delta: float) -> void:
	shoot_cd -= delta
	punch_buf -= delta
	kick_buf -= delta
	if not alive():
		respawn -= delta
		if respawn <= 0:
			hp = MAX_HP
			dropped = false
			hunger = 80.0
			thirst = 80.0
			infection = 0.0
			bleeding = false
			stamina = 100.0
			warned.clear()
			wounds.clear()  # a new survivor, unhurt
			body_dirty = true
			refresh_wear()  # the clothes stayed on the body; the new survivor starts in their own
			inv.resize(bag_size())
			position = home_spawn()
			up = bed >= 0 and bed < world.container_nodes.size() and world.container_nodes[bed].data.get("up", false)
			on_roof = false
			on_car = -1
		return
	if sleeping or sitting != -1:
		if move.length() > 0.1 or punching or kicking:
			stand_up()
		return
	if getup_t > 0.0:
		getup_t -= delta  # getting to your feet first
		return
	if on_car >= 0:
		car_t += delta
		if move.length() > 0.1 and car_t > 0.4:
			get_parent().actions.jump_off_car(self, move)  # a step off the roof is a jump
		return
	if riding >= 0:
		return  # the bike moves them (Vehicles.server_tick)
	position = world.slide(position, move.limit_length(1.0) * SPEED * speed_mult() * world.slow_at(position) * delta, RADIUS, on_roof, false, up)


## Sprinting is faster; a bad infection drags your feet.
func speed_mult() -> float:
	var m := 1.0
	if sneak:
		m = 0.5
	elif sprint and not exhausted and stamina > 0.0 and not Body.sprained(wounds):
		m = 1.75
	if infection > 60.0:
		m *= 0.85
	if Body.sprained(wounds):
		m *= 0.8  # limping
	m *= Body.leg_speed(wounds)  # a bitten leg
	if Body.fevered(wounds):
		m *= 0.92  # feverish
	if aiming:
		m = minf(m, 0.55)  # steady, careful steps
	for slot in wear_ids:
		m *= Items.def(wear_ids[slot]).get("speed", 1.0)
	return m * load_speed()


## Kilograms carried: the bag and what you're wearing.
func load_kg() -> float:
	var kg := 0.0
	for it in inv:
		kg += Items.weight_of(it)
	for slot in wear_ids:
		kg += float(Items.def(wear_ids[slot]).get("weight", 0.0))
	return kg


## Kilograms you carry before slowing down: your own strength plus a bag's.
func carry_limit() -> float:
	var kg := Items.CARRY
	for slot in wear_ids:
		kg += float(Items.def(wear_ids[slot]).get("carry", 0.0))
	return kg


## 1.0 up to the limit, then slower the more you're over it.
func load_speed() -> float:
	var over := load_kg() / carry_limit()
	if over <= 1.0:
		return 1.0
	return lerpf(1.0, Items.OVERLOAD_SPEED, clampf((over - 1.0) / (Items.OVERLOAD - 1.0), 0.0, 1.0))


## Share of a bite stopped at `part` by what you're wearing (see Items.PARTS).
func guard(part: String) -> float:
	return Items.guard_at(wear_ids.values(), part)


## How hot your clothes make you: 0 in a T-shirt, 1 and up in riot gear.
func heat() -> float:
	var h := 0.0
	for slot in wear_ids:
		h += float(Items.def(wear_ids[slot]).get("hot", 0.0))
	return h


## You hear the world through a full-face helmet.
func muffled() -> bool:
	return wear_ids.values().any(func(id): return Items.def(id).get("muffle", false))


## Where a bite from a zombie at `from` lands: on the ground it gets your
## legs; from behind, your neck and back; face to face, the arm you put up.
func bite_part(from: Vector2, crawling: bool) -> String:
	var table: Dictionary = Items.BITE_FRONT
	if crawling:
		table = Items.BITE_GROUND
	elif aim.normalized().dot((from - position).normalized()) < -0.3:
		table = Items.BITE_BEHIND
	var total := 0
	for k in table:
		total += table[k]
	var r := randi() % total
	for k in table:
		r -= table[k]
		if r < 0:
			return k
	return "torso"


func in_long_bed() -> bool:
	return sleep_bed >= 0 and sleep_bed < world.container_nodes.size() 			and world.container_nodes[sleep_bed].data.get("long", 0) == 2


## Astride a bike: the bike's far part, the rider sat on it (hands on the bars),
## then its near part. Mid-turn, both squash thin as the view changes over,
## so it reads as the bike swinging round; in a bend they lean in.
func _draw_riding(v: Dictionary) -> void:
	var view: String = v.view
	var dir: float = v.dir
	var squash := 1.0
	if turn_t > 0.0:
		var k := 1.0 - turn_t / TURN_TIME  # 0..1 through the turn
		squash = maxf(0.18, absf(cos(k * PI)))
		if k < 0.5:
			view = turn_from[0]
			dir = turn_from[1]
	# The engine shakes it a little standing, the road bobs it at speed.
	var running: bool = v.fuel > 0.0 and v.hp > 0
	var fast := clampf(ride_spd / 150.0, 0.0, 1.0)
	var bob := Vector2(0, (sin(ride_t * 55.0) * 0.18 if running and fast < 0.2 else 0.0) + sin(ride_t * 9.0) * 0.35 * fast)
	var xf := Transform2D(lean, Vector2(squash, 1.0), 0.0, bob)
	var rv := Look.SIDE if view == "side" else (Look.FRONT if view == "front" else Look.BACK)
	# The rider leans in on the throttle and back on the brakes.
	var tilt := clampf(ride_acc / 900.0, -0.07, 0.1) if view == "side" else 0.0
	var st := {view = [rv, dir < 0.0], anchors = BikeArt.rider_anchors(v.model, view), shadow = false, lean = tilt}
	BikeArt.wheel_turn = wheel_turn
	BikeArt.braking = ride_acc < -40.0 and ride_spd > 10.0
	BikeArt.draw(self, v.seed, view, dir, "far", xf)
	Look.body_xf = xf
	# Someone on the back sits behind the rider: drawn first, unless the bike is
	# going away from us (then they're nearer the camera).
	var q: Player = null
	if v.get("pillion", 0) != 0 and get_parent().get("players") != null:
		q = get_parent().players.get(v.pillion)
	if q and view != "back":
		_draw_pillion(q, v, view, rv, dir)
	Look.draw(self, st, look)
	if q and view == "back":
		_draw_pillion(q, v, view, rv, dir)
	Look.body_xf = Transform2D.IDENTITY
	BikeArt.draw(self, v.seed, view, dir, "near", xf)
	BikeArt.wheel_turn = 0.0
	BikeArt.braking = false


## Whoever rides on the back: sat on the pillion seat, holding on to the rider,
## or, fighting or holding a weapon, arms free to swing (see Rig free_arms).
func _draw_pillion(q: Player, v: Dictionary, view: String, rv: int, dir: float) -> void:
	var wdef := Items.def(q.hand_weapon("r"))
	var ldef := Items.def(q.hand_weapon("l"))
	var dur := 0.22
	if q.anim == Look.SWING:
		dur = wdef.get("dur", 0.34)
	elif q.anim == Look.SWING_L:
		dur = ldef.get("dur", 0.34)
	var ext := 0.0
	if q.anim in [Look.PUNCH_L, Look.PUNCH_R, Look.SWING, Look.SWING_L] and q.anim_t < dur:
		ext = sin(q.anim_t / dur * PI) if q.anim in [Look.PUNCH_L, Look.PUNCH_R] else q.anim_t / dur
	var fighting: bool = ext > 0.0 or q.aiming or not wdef.get("draw", {}).is_empty() or (q.anim != Look.NONE and q.anim_t < 1.2)
	var st := {view = [rv, dir < 0.0], anchors = BikeArt.pillion_anchors(v.model, view), shadow = false,
			angle = q.aim.angle(), attack = q.anim if ext > 0.0 else Look.NONE, ext = ext, guard = fighting,
			weapon = wdef.get("draw", {}), weapon_l = ldef.get("draw", {}), aiming = q.aiming, free_arms = fighting}
	Look.draw(self, st, q.look)


## Every machine, each frame: notice the bike turning, lean into bends, kick up dust.
## Every machine: the engine's note rising with speed, and at night the
## headlight's beam swinging round to where the bike points.
func _engine_and_lamp(delta: float) -> void:
	var v = null
	if riding >= 0 and riding < world.vehicles.size() and seat == 0 and alive():
		v = world.vehicles[riding]
	var lamp: bool = v != null and Vehicles.headlight_on(v, world)
	headlight.energy = move_toward(headlight.energy, 1.1 if lamp else 0.0, delta * 4.0)
	headlight.visible = headlight.energy > 0.01
	if v != null:
		var to := 0.0 if v.dir > 0.0 else PI
		if v.view != "side":
			to = PI * 0.5 if v.view == "front" else -PI * 0.5
		headlight.rotation = lerp_angle(headlight.rotation, to, minf(1.0, 10.0 * delta))
		headlight.position = Vector2.from_angle(headlight.rotation) * 8.0 + Vector2(0, -3)
	if DisplayServer.get_name() == "headless":
		return
	var run: bool = v != null and v.fuel > 0.0 and v.hp > 0
	if not run:
		if engine:
			engine.queue_free()
			engine = null
		return
	var m: Dictionary = Vehicles.MODELS[v.model]
	if engine == null:
		engine = AudioStreamPlayer2D.new()
		engine.stream = Sfx.loop("motor" if m.electric else "engine")
		engine.bus = "SFX"
		engine.max_distance = 700
		engine.attenuation = 1.5
		add_child(engine)
		engine.play()
	var k := clampf(ride_spd / m.speed, 0.0, 1.0)
	if m.electric:
		engine.pitch_scale = lerpf(0.6, 1.7, k)
		engine.volume_db = lerpf(-24.0, -15.0, k)
	else:
		engine.pitch_scale = lerpf(0.8, 2.3, k) * (1.0 + 0.1 * clampf(ride_acc / 150.0, 0.0, 1.0))  # it revs as it pulls away
		engine.volume_db = lerpf(-15.0, -7.0, k)


func _ride_look(delta: float) -> void:
	if turn_t > 0.0:
		turn_t = maxf(0.0, turn_t - delta)
	if riding < 0 or riding >= world.vehicles.size() or seat == 1:  # (on the back, the rider's bike does the looking)
		lean = 0.0
		ride_seen = Vector2.ZERO
		return
	var v: Dictionary = world.vehicles[riding]
	var now := [v.view, v.dir]
	if now != _shown_view:
		if not _shown_view.is_empty():
			turn_from = _shown_view
			turn_t = TURN_TIME
		_shown_view = now
	# Lean from how fast the heading is swinging round, and how fast we're going.
	var vel := (position - last_pos_ride) / maxf(delta, 0.001)
	last_pos_ride = position
	# Speed and its change (smoothed: positions come in steps over the network).
	var spd := vel.length() if vel.length() < 400.0 else ride_spd
	if vel.length() < 400.0:
		ride_seen = ride_seen.lerp(vel, minf(1.0, 8.0 * delta))
	ride_acc = lerpf(ride_acc, (spd - ride_spd) / maxf(delta, 0.001), minf(1.0, 6.0 * delta))
	ride_spd = lerpf(ride_spd, spd, minf(1.0, 10.0 * delta))
	wheel_turn += ride_spd * delta / 4.4
	ride_t += delta
	# Opening the throttle puffs smoke from the exhaust (not the electric one).
	puff_t -= delta
	var m: Dictionary = Vehicles.MODELS[v.model]
	if ride_acc > 60.0 and not m.electric and v.fuel > 0.0 and puff_t <= 0.0:
		puff_t = 0.12
		var main := get_parent()
		if main.get("dust") != null:
			var back := -vel.normalized() * 12.0 if vel.length() > 5.0 else Vector2(-12.0 * v.dir, 0)
			main.dust.append([position + back + Vector2(0, -3), 0.0])
	var target := 0.0
	if vel.length() > 20.0:
		var h := vel.angle()
		var turn := wrapf(h - last_heading, -PI, PI) / maxf(delta, 0.001)
		last_heading = h
		target = clampf(turn * 0.05 * minf(1.0, vel.length() / 150.0), -0.2, 0.2)
		if v.view != "side":
			target = -target if v.view == "back" else target
		# Hard turns at speed throw up dust from the back wheel.
		dust_t -= delta
		if absf(target) > 0.12 and vel.length() > 100.0 and dust_t <= 0.0:
			dust_t = 0.05
			var main := get_parent()
			if main.get("dust") != null:
				main.dust.append([position - vel.normalized() * 10.0, 0.0])
	lean = lerpf(lean, target, minf(1.0, 8.0 * delta))
	queue_redraw()


var _shown_view: Array = []
var last_pos_ride := Vector2.ZERO


## Where this survivor comes back: beside their bed if they have one, else anywhere.
## Which way a body lies or sits, from where it faces: see rest_face.
static func face_of(dir: Vector2) -> int:
	if absf(dir.x) >= absf(dir.y):
		return 0 if dir.x >= 0.0 else 1
	return 2 if dir.y > 0.0 else 3


## Server: off the floor, the bed or the chair, taking a moment about it.
func stand_up() -> void:
	if not sleeping and sitting == -1:
		return
	getup_t = LIE_TIME if sleeping else SIT_TIME
	sleeping = false
	sitting = -1


## Is `other` (a player or zombie) on the same floor as you: both upstairs or
## both down (the roof is its own place again: see on_roof)?
func same_floor(other) -> bool:
	return other.up == up


func home_spawn() -> Vector2:
	if bed >= 0 and bed < world.container_nodes.size():
		return world.container_nodes[bed].position
	return world.spawn_point()


## Hotbar slots: the base eight plus whatever the bag on your back holds.
func bag_size() -> int:
	var n := Items.INV_SIZE
	for slot in wear_ids:  # a backpack, a shoulder bag...
		n += int(Items.def(wear_ids[slot]).get("bag", 0))
	return n


## Server: after `worn` changes, update the ids everyone sees.
func refresh_wear() -> void:
	var ids := {}
	for slot in worn:
		if worn[slot] != null:
			ids[slot] = worn[slot].id
	set_wear(ids)


func set_wear(ids: Dictionary) -> void:
	wear_ids = ids
	look.wear = Items.wear_draw(ids)
	queue_redraw()


## Server: a zombie bite landing on `part`. What guards that part soaks up
## its share and wears down doing so: the most protective piece there first.
func bite(dmg: float, part := "torso") -> void:
	var g := guard(part)
	take_damage(dmg * (1.0 - g))
	bitten = true
	bite_where = part
	bite_guard = g
	var best := ""
	var best_g := 0.0
	for slot in worn:
		if worn[slot] == null:
			continue
		var s := float(Items.def(worn[slot].id).get("guard", {}).get(part, 0.0))
		if s > best_g:
			best_g = s
			best = slot
	if best == "":
		return
	worn[best].hp -= 1
	if worn[best].hp <= 0:
		torn = Items.display_name(worn[best].id)
		worn.erase(best)
		refresh_wear()


func _footstep() -> void:
	var t := world.get_tile(world.to_cell(position))
	var surface := "concrete"
	if on_roof:
		surface = "concrete"
	elif t in [World.GRASS, World.DIRT, World.TREE]:
		surface = "grass"
	elif t in [World.FLOOR, World.DOOR, World.IWALL]:
		surface = "wood"
	var vol := -20.0 if sneak else (-6.0 if sprint else -12.0)
	Sfx.play(get_parent(), "step_" + surface, position, vol, 1.1 if sprint else 1.0)


func set_appearance(code: int) -> void:
	app_code = code
	look = Look.look_of(Look.unpack(code))
	look.wear = Items.wear_draw(wear_ids)
	skin = look.skin
	shirt = look.shirt
	pants = look.pants
	hair = look.hair
	queue_redraw()


func _ready() -> void:
	if app_code < 0:
		# Until the player's chosen look arrives, pick one from the peer id.
		var rng := RandomNumberGenerator.new()
		rng.seed = peer_id
		set_appearance(Look.pack(Look.random_appearance(rng)))
	# No torch: in the dark you only make out what is right around you (eyes
	# get used to it), unless a street lamp or a lit window lights the way.
	night_eyes = PointLight2D.new()
	night_eyes.texture = StreetProp._lamp_texture()
	night_eyes.texture_scale = 0.75
	night_eyes.color = Color("9aa6c4")  # moonlight blue
	night_eyes.position = Look.CHEST
	night_eyes.energy = 0.0
	add_child(night_eyes)
	headlight = PointLight2D.new()
	headlight.texture = Vehicles.beam_texture()
	headlight.color = Color("fff0c8")
	headlight.energy = 0.0
	headlight.visible = false
	add_child(headlight)


func _process(delta: float) -> void:
	if seat == 1 and riding >= 0 and riding < world.vehicles.size():
		# On the back: exactly where the rider is, on every machine.
		var d = get_parent().players.get(world.vehicles[riding].rider) if get_parent().get("players") != null else null
		if d:
			position = d.position
			net_pos = d.position
	_ride_look(delta)
	_engine_and_lamp(delta)
	# Lying down, sitting, getting up: eased here, drawn in _draw_rest.
	var down := sleeping or sitting != -1
	if down:
		_rest_lying = sleeping
	rest_k = move_toward(rest_k, 1.0 if down else 0.0, delta / (LIE_TIME if _rest_lying else SIT_TIME))
	if not multiplayer.is_server():
		if is_local:
			# Trust local prediction, but drift toward the server and snap on big errors.
			if position.distance_to(net_pos) > (120.0 if riding >= 0 else 40.0):  # a bike outruns the snapshots
				position = net_pos
			else:
				position = position.lerp(net_pos, minf(1.0, 2.0 * delta))
		else:
			position = position.lerp(net_pos, minf(1.0, 15.0 * delta))
	var step := position.distance_to(last_pos)
	last_pos = position
	moving = step > 0.05
	var before := phase
	phase = phase + step * 0.3 if moving else 0.0  # longer strides
	if moving and floor(phase / PI) != floor(before / PI) and alive() and get_parent().get("in_game"):
		_footstep()
	var want_lift: float = world.roof_height(position) if on_roof else (BuildingProp.GROUND_H if up else 0.0)
	if on_car >= 0 and on_car < world.street_props.size():
		want_lift = StreetProp.roof_spot(world.street_props[on_car])[1]
	lift = lerpf(lift, want_lift, minf(1.0, 12.0 * delta))
	night_eyes.position = Look.CHEST + Vector2(0, -lift)
	z_index = 2 if on_roof or lift > 1.0 else 1  # above the buildings while up there
	view = Look.pick_view(aim.angle(), view)
	if hitstop > 0.0:
		hitstop -= delta  # the blow landed: hold the pose a beat
	else:
		anim_t += delta
	if alive():
		if death_t > 0.0:
			# Respawned: leave the old body where it fell (unless it got up and walked off).
			if not turned and get_parent().has_method("leave_corpse"):
				get_parent().leave_corpse(last_death_pos, fall_dir, look, false, death_t, "", 0, -1.0, last_death_up)
			death_t = 0.0
			turned = false  # cleared here, on every peer, once the old body is dealt with
	else:
		if death_t == 0.0:
			fall_dir = -1.0 if aim.x > 0 else 1.0  # topple backwards, away from where we faced
			last_death_pos = position
			last_death_up = up
		death_t += delta
	night_eyes.energy = move_toward(night_eyes.energy, 0.55 if world.is_night and alive() and is_local else 0.0, delta * 0.5)
	night_eyes.visible = night_eyes.energy > 0.01
	modulate.a = sight_k
	queue_redraw()


## Lying down, sat, or on the way down or back up (rest_k), facing rest_face.
## Side-on: the getting-up-off-the-ground motion (Rig rise) played backwards,
## stopping sat on the floor or going on down onto your back, head behind you.
## Towards us or away: squat, then down; sat, cross-legged; on a chair, sat on it.
func _draw_rest() -> void:
	var k := smoothstep(0.0, 1.0, rest_k)
	var lying := _rest_lying
	var shut := lying and sleeping and rest_k >= 0.99
	Look.lift = Vector2(0, -lift)
	var on_seat := sitting >= 0 and sitting < world.decor.size()
	if on_seat:
		var seat_h: float = SEAT_HEIGHT.get(world.decor[sitting].kind, 6.0)
		_draw_sat(lerpf(Rig.HIP_Y, -seat_h, k), k, 2, false)
	elif rest_face <= 1:
		var fd := -1.0 if rest_face == 0 else 1.0  # (legs out in front, head going down behind you)
		var u := 1.0 - k if lying else 1.0 - 0.6 * k
		Look.draw(self, {view = [Look.SIDE, rest_face == 1], rise = u, fall_dir = fd, eyes_shut = shut}, look)
	elif not lying or k < 0.5:
		# Down on your backside (and, lying down, on the way to your back).
		_draw_sat(lerpf(Rig.HIP_Y, -2.5, minf(1.0, k * (2.0 if lying else 1.0))), k, rest_face, true)
	else:
		# Flat on your back along the floor, head away from us (or towards us),
		# seen from above.
		_draw_lying_top(rest_face == 2)
		if in_long_bed():
			# Under the blanket, head on the pillow.
			draw_rect(Rect2(-7, -19 - lift, 14, 17), Color("6a7a94"))
			draw_rect(Rect2(-4.5, -18 - lift, 9, 15), Color("75869f"))
	Look.lift = Vector2.ZERO
	if shut:
		var t := fmod(Time.get_ticks_msec() / 1000.0, 3.0)
		draw_string(UiTheme.heading(), Vector2(4 + t * 3, -20 - t * 5 - lift), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(0.9, 0.9, 1.0, 0.8 * (1.0 - t / 3.0)))


## Someone on their back lying up the screen (head away) or down it, as seen
## from above: the top of the head, shoulders, arms along the sides, legs,
## the soles of the shoes. Feet at the origin.
func _draw_lying_top(head_up: bool) -> void:
	# Drawn head-up with the feet at the origin, then flipped for head-down
	# (towards us: the face upside down, as it would be).
	var dl := Look._dress(look, false)
	var top: Color = dl.shirt
	var legs: Color = dl.pants
	var shoe: Color = dl.shoes
	var gw: float = look.get("build", 1.0)  # (heavier builds lie wider)
	draw_set_transform(Vector2(0, -lift), 0, Vector2(gw, 1.0 if head_up else -1.0))
	var breath := sin(Time.get_ticks_msec() * 0.0022 + get_instance_id()) * 0.35 if sleeping else 0.0
	# The shadow all along it.
	draw_colored_polygon(PackedVector2Array([Vector2(-5, 1), Vector2(5, 1), Vector2(8, -14), Vector2(7, -24), Vector2(0, -30),
			Vector2(-7, -24), Vector2(-8, -14)]), Color(0, 0, 0, 0.22))
	# Legs, a little apart, knees shaded; shorts show the skin below.
	for sx in [-1.0, 1.0]:
		var x: float = sx * 2.2
		draw_colored_polygon(PackedVector2Array([Vector2(x - 1.7, -2.5), Vector2(x + 1.7, -2.5), Vector2(x + 2.0, -13.5), Vector2(x - 1.9, -13.5)]),
				legs)
		if dl.get("shorts", false):
			draw_rect(Rect2(x - 1.6, -8.5, 3.2, 6.0), skin)
		draw_rect(Rect2(x - 1.6, -8.2, 3.2, 0.8), legs.darkened(0.25))  # the knee
		# Shoes seen from their soles, the tread across them.
		draw_rect(Rect2(x - 1.9, -3.2, 3.8, 3.0), shoe)
		draw_rect(Rect2(x - 1.6, -2.7, 3.2, 0.6), shoe.lightened(0.25))
		draw_rect(Rect2(x - 1.6, -1.5, 3.2, 0.6), shoe.lightened(0.25))
	draw_rect(Rect2(-4.4, -14.6, 8.8, 1.6), legs.darkened(0.35))  # belt
	# The body: shoulders wider than the waist, a collar, a fold of the shirt.
	var chest := -22.5 - breath
	draw_colored_polygon(PackedVector2Array([Vector2(-4.4, -13.5), Vector2(4.4, -13.5), Vector2(5.8, chest + 1.0), Vector2(4.8, chest - 0.5),
			Vector2(-4.8, chest - 0.5), Vector2(-5.8, chest + 1.0)]), top)
	draw_line(Vector2(-2.0, -15.5), Vector2(-1.2, chest + 3.0), top.darkened(0.12), 0.6)
	draw_colored_polygon(PackedVector2Array([Vector2(-1.8, chest - 0.3), Vector2(1.8, chest - 0.3), Vector2(0, chest + 2.4)]), skin.darkened(0.08))
	# Arms by the sides, sleeves to the elbow (or all the way), hands open.
	for sx in [-1.0, 1.0]:
		var a := Vector2(sx * 5.9, chest + 1.2)
		var e := Vector2(sx * 6.7, -17.0)
		var h := Vector2(sx * 6.4, -12.2)
		draw_line(a, e, top.darkened(0.06), 2.6)
		draw_line(e, h, top.darkened(0.06) if dl.get("long_sleeves", false) else skin, 2.2)
		draw_circle(h + Vector2(0, 0.6), 1.3, skin)
	# The head, the face up to the sky, eyes shut; the hair spread under it.
	var hc := Vector2(0, chest - 3.6)
	draw_circle(hc + Vector2(0, -0.8), 3.9, hair)
	draw_circle(hc, 3.2, skin)
	draw_circle(hc + Vector2(-3.1, 0.2), 0.9, skin.darkened(0.08))  # ears
	draw_circle(hc + Vector2(3.1, 0.2), 0.9, skin.darkened(0.08))
	draw_rect(Rect2(hc.x - 3.0, hc.y - 3.4, 6.0, 1.4), hair)  # the fringe
	var shut := Color(0.12, 0.08, 0.06, 0.9)
	draw_line(hc + Vector2(-1.9, -0.4), hc + Vector2(-0.7, -0.2), shut, 0.5)
	draw_line(hc + Vector2(0.7, -0.2), hc + Vector2(1.9, -0.4), shut, 0.5)
	draw_rect(Rect2(hc.x - 0.3, hc.y + 0.2, 0.6, 0.9), skin.darkened(0.15))  # nose
	draw_line(hc + Vector2(-0.8, 1.7), hc + Vector2(0.8, 1.7), skin.darkened(0.3), 0.5)
	draw_set_transform(Vector2.ZERO)


## How high each kind of seat is (the hips sit this far up).
const SEAT_HEIGHT := {sofa = 8.0, bench = 7.5, chairs = 5.0, barberchair = 9.0, recliner = 8.0, examcot = 9.0}


## Sat: hips at `hip_y`, from the front (2) or back (3). On the floor the legs
## fold cross-legged and the hands rest on the knees; on a seat the feet stay
## on the floor.
func _draw_sat(hip_y: float, k: float, face: int, floor_sit: bool) -> void:
	var hip := Vector2(0, hip_y)
	var feet: Array
	var hands: Array
	if floor_sit:
		feet = [Vector2(-1.7, 0).lerp(Vector2(-4.2, -0.5), k), Vector2(1.7, 0).lerp(Vector2(4.2, -0.5), k)]
		hands = [Vector2(-3.5, -8).lerp(Vector2(-3.8, hip_y + 0.5), k), Vector2(3.5, -8).lerp(Vector2(3.8, hip_y + 0.5), k)]
	else:
		feet = [Vector2(-2.2, 0), Vector2(2.2, 0)]
		hands = [Vector2(-3.5, -8).lerp(Vector2(-2.5, hip_y - 1.0), k), Vector2(3.5, -8).lerp(Vector2(2.5, hip_y - 1.0), k)]
	Look.draw(self, {view = [Look.FRONT if face == 2 else Look.BACK, false],
			anchors = {seat = hip, hands = hands, feet = feet}}, look)


func _draw() -> void:
	if not alive():
		if turned:
			return  # the body got up and walked off as a zombie
		Look.draw_blood_pool(self, fall_dir, clampf((death_t - 0.5) / 3.0, 0.0, 1.0))
		Look.draw(self, {view = [Look.SIDE, fall_dir > 0], fall = clampf(death_t / 0.75, 0.001, 1.0), fall_dir = fall_dir}, look)
		return
	if rest_k > 0.001 and riding < 0:
		_draw_rest()
		queue_redraw()
		return
	if riding >= 0 and riding < world.vehicles.size():
		if seat == 0:
			_draw_riding(world.vehicles[riding])
		queue_redraw()
		return  # (on the back you're drawn by the rider, in the right order: see _draw_riding)
	var wdef := Items.def(hand_weapon("r"))
	var ldef := Items.def(hand_weapon("l"))
	var dur := 0.22
	if anim == Look.KICK:
		dur = 0.45
	elif anim == Look.SWING:
		dur = wdef.get("dur", 0.34)
	elif anim == Look.SWING_L:
		dur = ldef.get("dur", 0.34)
	var ext := 0.0
	if anim != Look.NONE and anim_t < dur:
		# Punches use a quick out-and-back curve; kicks and swings pass their raw timeline.
		ext = sin(anim_t / dur * PI) if anim in [Look.PUNCH_L, Look.PUNCH_R] else anim_t / dur
	# Sneaking: crouched low, a slow creep.
	Look.lift = Vector2(0, -lift)
	Look.muzzle = null
	if _winded() and ext == 0.0 and wdef.get("draw", {}).is_empty() and ldef.get("draw", {}).is_empty():
		# Out of breath and standing still: bent over, hands on the knees, panting.
		var side: bool = view[0] == Look.SIDE
		var pant := sin(Time.get_ticks_msec() * 0.012) * 0.5
		var hands := [Vector2(2.4, -7.6), Vector2(3.2, -7.6)] if side else [Vector2(-2.8, -6.8), Vector2(2.8, -6.8)]
		Look.draw(self, {view = view, anchors = {seat = Vector2(0, Rig.HIP_Y + 0.8 + pant), hands = hands},
				lean = 0.12 + pant * 0.05}, look)
	else:
		_draw_standing(ext, wdef, ldef)
	Look.lift = Vector2.ZERO
	if Look.muzzle != null:
		muzzle = Look.muzzle  # (the flash of a shot comes from here)
	draw_set_transform(Vector2(0, -lift))
	Look.draw_hp(self, hp / MAX_HP)
	draw_set_transform(Vector2.ZERO)


## Out of breath (nearly spent, or spent) and standing about.
func _winded() -> bool:
	return alive() and not moving and not aiming and riding < 0 and (exhausted or stamina < 22.0) 			and (anim == Look.NONE or anim_t > 1.2)


func _draw_standing(ext: float, wdef: Dictionary, ldef: Dictionary) -> void:
	Look.draw_eased(self, {view = view, angle = aim.angle(), phase = phase * (0.6 if sneak else 1.0), moving = moving and ext == 0.0,
			attack = anim if ext > 0.0 else Look.NONE, ext = ext, guard = anim != Look.NONE and anim_t < 1.2,
			crouch = 3.0 if sneak else 0.0, weapon = wdef.get("draw", {}), weapon_l = ldef.get("draw", {}), aiming = aiming,
			breath = Time.get_ticks_msec() * 0.0016 + get_instance_id() % 7}, look, _pose)
