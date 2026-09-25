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
# Inventory: server-authoritative; the owning client gets a copy via main.inv_sync.
var inv: Array = []  # INV_SIZE entries of null or {id, n, hp}
var sel := 0
var weapon_id := ""  # what everyone sees in this player's hand
var search_id := -1  # server only: container being searched
var search_t := 0.0
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
var lift := 0.0  # current drawn height above the street (eases between roofs)
var step_t := 0.0  # server: time to the next footstep noise
var bitten := false  # server: set by a zombie bite, handled by main
var turned := false  # died of the infection and got back up as a zombie
var warned := {}  # server: which low-need warnings were already sent
var fall_dir := 1.0
var last_death_pos := Vector2.ZERO
var shoot_cd := 0.0
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
var say := ""  # last thing said in chat, shown over their head for say_t seconds
var say_t := 0.0
var open_box := -1  # server: the container this player has open in the bag screen
var torn := ""  # server: name of something a bite just tore apart, for main to report
var phase := 0.0
var view := [Look.FRONT, false]
var moving := false
var last_pos := Vector2.ZERO
var flashlight: PointLight2D


func _init() -> void:
	inv.resize(Items.INV_SIZE)


## The weapon in the selected slot, or "" for bare fists.
func held_weapon() -> String:
	var it = inv[sel]
	return it.id if it != null and Items.is_weapon(it.id) else ""


func alive() -> bool:
	return hp > 0


func take_damage(amount: float) -> void:
	if not alive():
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		respawn = RESPAWN_TIME


## Start an attack animation (runs on every peer via main.fx_melee).
func play_attack(kind: int) -> void:
	if kind in [Look.PUNCH_L, Look.PUNCH_R]:
		punch_side = not punch_side
		kind = Look.PUNCH_L if punch_side else Look.PUNCH_R
	anim = kind
	anim_t = 0.0


## Server only.
func server_tick(delta: float) -> void:
	shoot_cd -= delta
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
			turned = false
			warned.clear()
			refresh_wear()  # the clothes stayed on the body; the new survivor starts in their own
			inv.resize(bag_size())
			position = world.spawn_point()
		return
	position = world.slide(position, move.limit_length(1.0) * SPEED * speed_mult() * world.slow_at(position) * delta, RADIUS, on_roof)


## Sprinting is faster; a bad infection drags your feet.
func speed_mult() -> float:
	var m := 1.0
	if sneak:
		m = 0.5
	elif sprint and not exhausted and stamina > 0.0:
		m = 1.75
	if infection > 60.0:
		m *= 0.85
	for slot in wear_ids:
		m *= Items.def(wear_ids[slot]).get("speed", 1.0)
	return m


## Share of a bite stopped by what you're wearing.
func armor() -> float:
	var a := 0.0
	for slot in wear_ids:
		a += Items.def(wear_ids[slot]).get("armor", 0.0)
	return minf(a, Items.MAX_ARMOR)


## Hotbar slots: the base eight plus whatever the bag on your back holds.
func bag_size() -> int:
	return Items.INV_SIZE + Items.def(wear_ids.get("back", "")).get("bag", 0)


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


## Server: a zombie bite. Clothing soaks up part of it and wears down doing so.
func bite(dmg: float) -> void:
	var a := armor()
	take_damage(dmg * (1.0 - a))
	bitten = true
	var armored := worn.keys().filter(func(k): return worn[k] != null and Items.def(worn[k].id).get("armor", 0.0) > 0.0)
	if armored.is_empty():
		return
	var slot: String = armored.pick_random()
	worn[slot].hp -= 1
	if worn[slot].hp <= 0:
		torn = Items.display_name(worn[slot].id)
		worn.erase(slot)
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
	flashlight = PointLight2D.new()
	flashlight.texture = Look.cone_texture()
	flashlight.texture_scale = 1.6
	flashlight.color = Color("fff1c8")
	flashlight.position = Look.CHEST
	flashlight.energy = 0.0
	add_child(flashlight)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		if is_local:
			# Trust local prediction, but drift toward the server and snap on big errors.
			if position.distance_to(net_pos) > 40:
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
	flashlight.rotation = aim.angle()
	lift = lerpf(lift, world.roof_height(position) if on_roof else 0.0, minf(1.0, 12.0 * delta))
	flashlight.position = Look.CHEST + Vector2(0, -lift)
	z_index = 2 if on_roof or lift > 1.0 else 1  # above the buildings while up there
	view = Look.pick_view(aim.angle(), view)
	anim_t += delta
	if alive():
		if death_t > 0.0:
			# Respawned: leave the old body where it fell.
			if not turned and get_parent().has_method("leave_corpse"):
				get_parent().leave_corpse(last_death_pos, fall_dir, look, false, death_t)
			death_t = 0.0
	else:
		if death_t == 0.0:
			fall_dir = -1.0 if aim.x > 0 else 1.0  # topple backwards, away from where we faced
			last_death_pos = position
		death_t += delta
	flashlight.energy = move_toward(flashlight.energy, 1.1 if world.is_night and alive() else 0.0, delta)
	flashlight.visible = flashlight.energy > 0.01
	queue_redraw()


func _draw() -> void:
	if not alive():
		if turned:
			return  # the body got up and walked off as a zombie
		Look.draw_blood_pool(self, fall_dir, clampf((death_t - 0.5) / 3.0, 0.0, 1.0))
		Look.draw(self, {view = [Look.SIDE, fall_dir > 0], fall = clampf(death_t / 0.75, 0.001, 1.0), fall_dir = fall_dir}, look)
		return
	var wdef := Items.def(weapon_id)
	var dur := 0.22
	if anim == Look.KICK:
		dur = 0.45
	elif anim == Look.SWING:
		dur = wdef.get("dur", 0.34)
	var ext := 0.0
	if anim != Look.NONE and anim_t < dur:
		# Punches use a quick out-and-back curve; kicks and swings pass their raw timeline.
		ext = sin(anim_t / dur * PI) if anim in [Look.PUNCH_L, Look.PUNCH_R] else anim_t / dur
	# Sneaking: crouched low, a slow creep.
	Look.lift = Vector2(0, -lift)
	Look.draw(self, {view = view, angle = aim.angle(), phase = phase * (0.6 if sneak else 1.0), moving = moving and ext == 0.0,
			attack = anim if ext > 0.0 else Look.NONE, ext = ext, guard = anim != Look.NONE and anim_t < 1.2,
			crouch = 3.0 if sneak else 0.0, weapon = wdef.get("draw", {})}, look)
	Look.lift = Vector2.ZERO
	draw_set_transform(Vector2(0, -lift))
	Look.draw_hp(self, hp / MAX_HP)
	draw_set_transform(Vector2.ZERO)
