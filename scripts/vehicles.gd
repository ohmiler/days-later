class_name Vehicles
extends Node
## Riding motorbikes. Every bike parked in the city (StreetProp "motorbike")
## is a vehicle with a state: where it is, which way it faces, fuel, damage,
## and whether its key is in it. Only what changed from the generated city is
## saved (like Things). A rider's movement is simulated the same way on the
## server and, to feel instant, on the rider's own machine (see step).
##
## World.vehicles: [{id, model, seed, pos, dir, view, fuel, hp, key, upright, rider, node}]
## `view` is how it is seen: "side" (facing `dir`), "front" or "back", picked
## from its heading the way a character's is (see BikeArt).

const DATA := "res://data/vehicles.cfg"  # (exports must include *.cfg)
const REACH := 22.0
const RADIUS := 5.0
const HOTWIRE_TIME := 8.0
const FUEL_CAN := 3.0  # litres in a jerrycan
const HIT_SPEED := 60.0  # faster than this, a zombie in the way is knocked flat
const SLOW_GROUND := 0.5  # grass and dirt, for bikes not built for it
const KEY_CHANCE := 0.35  # bikes left with the key still in

## model -> {name, speed, accel, fuel, use, noise, hp, offroad, electric}
static var MODELS: Dictionary = _load()

var main: Main
var _noise_t := {}  # peer -> time to the next engine noise


static func _load() -> Dictionary:
	var cf := ConfigFile.new()
	var err := cf.load(DATA)
	if err != OK:
		push_error("Could not read %s (error %d)" % [DATA, err])
		return {}
	var out := {}
	for id in cf.get_sections():
		var m := {}
		for key in cf.get_section_keys(id):
			m[key] = cf.get_value(id, key)
		m.merge({offroad = false, electric = false}, false)
		out[id] = m
	return out


## Make the vehicles for a freshly built world, from its parked bikes. How much
## fuel each has and whether its key is in come from its seed, so every
## machine agrees without being told.
static func setup(w: World) -> void:
	w.vehicles = []
	for rec in w.street_props:
		if rec.kind != "motorbike":
			continue
		var model := BikeArt.bike_model(rec.seed)
		var m: Dictionary = MODELS.get(model, MODELS.wave)
		var h := World.hash01(rec.seed, 3, 17)
		w.vehicles.append({id = w.vehicles.size(), model = model, seed = rec.seed, pos = rec.pos,
				dir = 1.0 if rec.seed % 2 else -1.0, view = "side", fuel = m.fuel * h * 0.6, hp = m.hp,
				key = World.hash01(rec.seed, 5, 23) < KEY_CHANCE, upright = rec.seed % 7 != 3, rider = 0, rec = rec})
		rec.vehicle = w.vehicles.size() - 1


static func title_of(v: Dictionary) -> String:
	var m: Dictionary = MODELS[v.model]
	return "%s · %s %d%%" % [m.name, "แบต" if m.electric else "น้ำมัน", roundi(v.fuel / m.fuel * 100.0)]


## One step of riding, for the rider: speed up toward where they steer, slow
## on rough ground, stop against walls. Shared by the server and the rider's
## own machine so what they see matches what happens.
static func step(p: Player, v: Dictionary, move: Vector2, delta: float, w: World) -> void:
	var m: Dictionary = MODELS[v.model]
	var top: float = m.speed
	if not m.offroad and w.get_tile(w.to_cell(p.position)) in [World.GRASS, World.DIRT]:
		top *= SLOW_GROUND
	if v.fuel <= 0.0 or v.hp <= 0:
		top = 0.0
	var want := move.limit_length(1.0) * top
	var rate: float = m.accel if want.length() > p.ride_vel.length() else m.accel * 1.6  # brakes bite harder
	p.ride_vel = p.ride_vel.move_toward(want, rate * delta)
	var before := p.position
	p.position = w.slide(p.position, p.ride_vel * delta, RADIUS, false, true)
	if (p.position - before).length() < (p.ride_vel * delta).length() * 0.5:
		p.ride_vel *= 0.3  # ran into something
	turn_to(v, p.ride_vel)
	v.pos = p.position
	_place(v)


## Face a bike the way it is going (only once it is really moving).
static func turn_to(v: Dictionary, vel: Vector2) -> void:
	if vel.length() < 12.0:
		return
	var prev := [Look.SIDE, v.dir < 0.0] if v.view == "side" else [Look.FRONT if v.view == "front" else Look.BACK, false]
	var pv := Look.pick_view(vel.angle(), prev)
	v.view = "side" if pv[0] == Look.SIDE else ("front" if pv[0] == Look.FRONT else "back")
	if v.view == "side":
		v.dir = -1.0 if pv[1] else 1.0


## Move a bike's drawing to where the bike is.
static func _place(v: Dictionary) -> void:
	v.rec.pos = v.pos
	v.rec.dir = v.dir
	v.rec.view = v.view
	v.rec.upright = v.upright
	var node: Node2D = v.get("node")
	if node:
		node.position = v.pos
		node.visible = v.rider == 0  # a ridden bike is drawn by its rider, around them (see Player)
		node.queue_redraw()


# --- Server --------------------------------------------------------------------

func server_tick(p: Player, delta: float) -> void:
	if p.riding < 0:
		return
	var v: Dictionary = main.world.vehicles[p.riding]
	if not p.alive() or p.sleeping:
		dismount(p)
		return
	var m: Dictionary = MODELS[v.model]
	step(p, v, p.move, delta, main.world)
	var speed := p.ride_vel.length()
	v.fuel = maxf(0.0, v.fuel - m.use * (0.1 + 0.9 * speed / m.speed) * delta)
	if v.fuel <= 0.0 and speed < 1.0 and p.move.length() > 0.1:
		main._toast(p, "แบตหมด" if m.electric else "น้ำมันหมด!")
	# The engine carries.
	_noise_t[p.peer_id] = _noise_t.get(p.peer_id, 0.0) - delta
	if _noise_t[p.peer_id] <= 0.0 and v.fuel > 0.0:
		_noise_t[p.peer_id] = 0.5
		main._make_noise(p.position, m.noise * (0.5 + 0.5 * speed / m.speed))
	# Running into zombies knocks them down, and knocks the bike about.
	if speed > HIT_SPEED:
		for z: Zombie in main.zombies.values():
			# Anything the front of the bike is about to go through.
			var ahead := Geometry2D.get_closest_point_to_segment(z.position, p.position, p.position + p.ride_vel.normalized() * 12.0)
			if z.down_t > 0.0 or z.position.distance_to(ahead) > RADIUS + Zombie.RADIUS + 2.0:
				continue
			var dir := p.ride_vel.normalized()
			z.knock_down()
			z.hp -= speed * 0.15
			main.combat.fx_hit.rpc(z.zid, z.position, dir, true, p.peer_id, "", z.hp)
			main.fx_sound.rpc("kick", z.position)
			if z.hp <= 0.0:
				main.combat._kill_zombie(z, signf(dir.x) if dir.x != 0.0 else 1.0, "stomp")
				p.kills += 1
			v.hp -= 3
			p.ride_vel *= 0.6
			if v.hp <= 0:
				main._toast(p, "รถพังแล้ว!")
				dismount(p)
				return


func mount(p: Player, id: int) -> void:
	var v: Dictionary = main.world.vehicles[id]
	if v.rider != 0 or p.riding >= 0:
		return
	p.riding = id
	p.ride_vel = Vector2.ZERO
	p.position = v.pos
	v.rider = p.peer_id
	v.upright = true
	v.touched = true
	_place(v)
	main.fx_sound.rpc("door", v.pos)
	main._toast(p, "ขึ้นขี่%s · [E] ลงจากรถ" % MODELS[v.model].name)


func dismount(p: Player) -> void:
	if p.riding < 0:
		return
	var v: Dictionary = main.world.vehicles[p.riding]
	v.rider = 0
	p.riding = -1
	_place(v)
	p.ride_vel = Vector2.ZERO
	for off in [Vector2(0, 9), Vector2(0, -9), Vector2(10, 0), Vector2(-10, 0)]:
		if main.world.can_stand(v.pos + off, Player.RADIUS):
			p.position = v.pos + off
			break
	_send(v)


func _send(v: Dictionary) -> void:
	vehicle_state.rpc(v.id, v.pos, v.dir, v.fuel, v.hp, v.key, v.upright, v.view)


func finish_hotwire(p: Player, id: int) -> void:
	var v: Dictionary = main.world.vehicles[id]
	v.key = true
	v.touched = true
	main._toast(p, "ต่อสายตรงสำเร็จ · ขี่ได้แล้ว")
	_send(v)


func refuel(p: Player, id: int) -> void:
	var v: Dictionary = main.world.vehicles[id]
	var m: Dictionary = MODELS[v.model]
	if m.electric or Crafting.count_in(p.inv, "fuelcan") < 1:
		return
	main.crafting._take(p, "fuelcan", 1)
	v.fuel = minf(m.fuel, v.fuel + FUEL_CAN)
	v.touched = true
	main.fx_sound.rpc("pickup", v.pos)
	main._toast(p, "เติมน้ำมัน · %s" % title_of(v))
	main.inventory._send_inv(p)
	_send(v)


## What E can do with a bike.
func actions_for(p: Player, id: int) -> Array:
	var v: Dictionary = main.world.vehicles[id]
	var m: Dictionary = MODELS[v.model]
	var out := []
	var why := ""
	if v.hp <= 0:
		why = "รถพัง"
	elif not v.key:
		why = "ไม่มีกุญแจ · ต่อสายตรงก่อน"
	elif v.fuel <= 0.0:
		why = "แบตหมด" if m.electric else "น้ำมันหมด · เติมจากแกลลอน"
	out.append(Interact._act("ride", "ขี่", why == "", why))
	if not v.key:
		var tool := p.holds(["screwdriver"])
		out.append(Interact._act("hotwire", "ต่อสายตรง (ถือไขควง)", tool, "ต้องถือไขควงไว้ในมือ"))
	if not m.electric and v.fuel < m.fuel:
		var has := Crafting.count_in(p.inv, "fuelcan") > 0
		out.append(Interact._act("refuel", "เติมน้ำมันจากแกลลอน", has, "ไม่มีแกลลอนน้ำมัน"))
	return out


# --- Saving and joining ------------------------------------------------------------

## Bikes that differ from the generated city: id -> [pos, dir, fuel, hp, key, upright, view].
func changed() -> Dictionary:
	var out := {}
	for v in main.world.vehicles:
		if v.get("touched", false):
			out[v.id] = [v.pos, v.dir, v.fuel, v.hp, v.key, v.upright, v.view]
	return out


func restore(ch: Dictionary) -> void:
	for id in ch:
		if id < main.world.vehicles.size():
			_apply(main.world.vehicles[id], ch[id])


func send_all(peer: int) -> void:
	vehicles_sync.rpc_id(peer, changed())


@rpc("authority", "call_remote", "reliable")
func vehicles_sync(ch: Dictionary) -> void:
	restore(ch)


@rpc("authority", "call_local", "reliable")
func vehicle_state(id: int, pos: Vector2, dir: float, fuel: float, hp: int, key: bool, upright: bool, view: String) -> void:
	var v: Dictionary = main.world.vehicles[id]
	_apply(v, [pos, dir, fuel, hp, key, upright, view])


func _apply(v: Dictionary, e: Array) -> void:
	v.pos = e[0]
	v.dir = e[1]
	v.fuel = e[2]
	v.hp = e[3]
	v.key = e[4]
	v.upright = e[5]
	v.view = e[6] if e.size() > 6 else "side"  # (saves from before bikes had front and back)
	v.touched = true
	_place(v)
