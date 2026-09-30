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
const CAR_REACH := 34.0
const CAR_TURN := 80.0  # px: a car's tightest turn (its radius), about 5 m
const CAR_WIDEN := 2.0  # its turning circle is this much wider again at top speed
const CAR_BACK := 0.35  # a car backs up this much of its top speed
const KEY_CHANCE := 0.15  # bikes left with the key still in (few: a bike worth keeping is worth looking after)
## Steering: a moving bike swings round toward where you steer at so many
## radians a second (tight at a crawl, wide at full speed); below CRAWL it
## points anywhere, and steering right back the way you came brakes first.
const TURN_SLOW := 6.0
const TURN_FAST := 3.2
const CRAWL := 20.0
const U_TURN := 2.3  # radians: steering further round than this is braking
## Running into a wall: faster than BUMP it jolts and dents the bike, faster
## than CRASH it bruises whoever is on it too.
const BUMP := 80.0
const CRASH := 125.0

## model -> {name, speed, accel, fuel, use, noise, hp, offroad, electric}
static var MODELS: Dictionary = _load()
static var _beam: Texture2D

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
		m.merge({offroad = false, electric = false, car = false}, false)
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
				dir = rec.get("dir", 1.0 if rec.seed % 2 else -1.0), view = rec.get("view", "side"), fuel = m.fuel * h * 0.6, hp = m.hp,
				key = World.hash01(rec.seed, 5, 23) < KEY_CHANCE, upright = rec.seed % 7 != 3, rider = 0, pillion = 0, rec = rec})
		rec.vehicle = w.vehicles.size() - 1
	_park_cars(w)


## Cars parked in the city. The street's cars and taxis are real cars (CarArt,
## the same as the one the admin menu makes), standing along the kerb facing the
## way that side's traffic goes (on the left). About one in five runs (some with
## the key in, some needing a hotwire); the rest are dead shells: still solid,
## still climbable, never started. Cars left out in the lanes go, and so do
## wrecks that aren't at a junction: the road keeps a clear way through.
const RUNNING := 0.2
const PARK_SHIFT := 6.5  # (a car is wider than its lane of cells: pulled in off the kerb)


## The five cells a street vehicle takes (see CityGen._size_vehicles).
static func _strip(rec: Dictionary) -> Array:
	var base := Vector2i((rec.pos / World.TILE).floor())
	var out := []
	for i in 5:
		out.append(Vector2i(base.x + i, base.y - 1) if rec.get("horizontal", true) else Vector2i(base.x, base.y - 1 - i))
	return out


## How many cells from `c` to the nearest pavement or building across the street,
## and which way: [cells, -1 | +1 along the cross axis].
static func _kerb(w: World, c: Vector2i, horizontal: bool) -> Array:
	var back := Vector2i.UP if horizontal else Vector2i.LEFT
	for r in range(1, 12):
		for side in [-1, 1]:
			if w.get_tile(c + back * r * side) not in [World.ROAD, World.SOI]:
				return [r, side]
	return [99, 1]


static func _park_cars(w: World) -> void:
	var m: Dictionary = MODELS.get("sedan", {})
	if m.is_empty():
		return
	for rec in w.street_props:
		if rec.kind not in ["car", "taxi", "wreck"]:
			continue
		var strip := _strip(rec)
		var horizontal: bool = rec.get("horizontal", true)
		var kerb := _kerb(w, strip[0], horizontal)
		var owned := strip.filter(func(c): return w.blocked.has(c))
		if rec.kind == "wreck":
			# Kept where the road is wide open beside it or it's a junction pile-up; else cleared.
			var near_junction := strip.any(func(c): return _near_intersection(w, c, 4))
			if kerb[0] > 2 and not near_junction:
				rec.culled = true
				for c in owned:
					w.blocked.erase(c)
			continue
		if kerb[0] > 2:
			rec.culled = true  # (left out in the lane: gone)
			for c in owned:
				w.blocked.erase(c)
			continue
		# A car along the kerb: nose the way its side's traffic goes (on the left).
		var dir: float
		var centre: Vector2
		var inward := float(kerb[1]) * -1.0  # (+1: toward +y / +x: away from a kerb on the - side)
		if horizontal:
			dir = 0.0 if kerb[1] < 0 else PI
			centre = Vector2((strip[0].x + 2.5) * World.TILE, (strip[0].y + 0.5) * World.TILE + inward * PARK_SHIFT)
		else:
			dir = -PI * 0.5 if kerb[1] < 0 else PI * 0.5
			centre = Vector2((strip[0].x + 0.5) * World.TILE + inward * PARK_SHIFT, (strip[0].y - 2.0) * World.TILE)
		var h := World.hash01(rec.seed, 7, 31)
		var runs := h < RUNNING
		var v := {id = w.vehicles.size(), model = "sedan", seed = rec.seed, color = rec.get("color", Color.WHITE), pos = centre, dir = dir, view = "car",
				fuel = m.fuel * (0.25 + 0.5 * World.hash01(rec.seed, 9, 11)) if runs else 0.0, hp = m.hp if runs else 0,
				key = runs and World.hash01(rec.seed, 5, 23) < 0.35, upright = true, rider = 0, pillion = 0, rec = {}, spd = 0.0, prop = rec, cells = owned}
		rec.art_gone = true
		rec.car_vehicle = v.id
		w.vehicles.append(v)
		free_cells(w, v)
		block_parked(w, v)


static func _near_intersection(w: World, c: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if w.in_intersection(c + Vector2i(dx, dy)):
				return true
	return false


## A parked car's cells are solid to walkers and zombies; while it's driven they
## are not (it carries its own collision), and where it stops it blocks again.
static func free_cells(w: World, v: Dictionary) -> void:
	for c in v.get("cells", []):
		w.blocked.erase(c)
		if w.astar.region.has_point(c):
			w.astar.set_point_solid(c, w.is_solid(c))
	v.cells = []


static func block_parked(w: World, v: Dictionary) -> void:
	free_cells(w, v)
	var fwd := Vector2.from_angle(v.dir)
	var right := fwd.orthogonal()
	var spec := CarArt.SEDAN
	var cells := {}
	for ix in range(-int(spec.len * 0.5) + 2, int(spec.len * 0.5) - 1, 4):
		for iy in range(-int(spec.wid * 0.5) + 2, int(spec.wid * 0.5) - 1, 4):
			cells[w.to_cell(v.pos + fwd * ix + right * iy)] = true
	var taken := []
	for c: Vector2i in cells:
		if w.in_bounds(c) and not w.blocked.has(c) and w.get_tile(c) in [World.ROAD, World.SOI, World.SIDEWALK, World.PLAZA]:
			w.blocked[c] = true
			taken.append(c)
			if w.astar.region.has_point(c):
				w.astar.set_point_solid(c, true)
	v.cells = taken
	if v.has("prop"):
		v.prop.moved = v.get("touched", false)  # (a car that has been driven can't be climbed where it was)


static func is_car(v: Dictionary) -> bool:
	return MODELS.get(v.model, {}).get("car", false)


## How close you get in to a vehicle: a car from beside its doors.
static func reach_of(v: Dictionary) -> float:
	return CAR_REACH if is_car(v) else REACH


static func title_of(v: Dictionary) -> String:
	var m: Dictionary = MODELS[v.model]
	return "%s · %s %d%%" % [m.name, "แบต" if m.electric else "น้ำมัน", roundi(v.fuel / m.fuel * 100.0)]


## One step of riding, for the rider: speed up toward where they steer and
## swing round to it, slow on rough ground, stop against walls. Shared by the
## server and the rider's own machine so what they see matches what happens.
## Returns how fast it was going if it just ran into something (else 0).
static func step(p: Player, v: Dictionary, move: Vector2, delta: float, w: World) -> float:
	if is_car(v):
		return _car_step(p, v, move, delta, w)
	var m: Dictionary = MODELS[v.model]
	var top: float = m.speed
	if not m.offroad and w.get_tile(w.to_cell(p.position)) in [World.GRASS, World.DIRT]:
		top *= SLOW_GROUND
	if v.fuel <= 0.0 or v.hp <= 0 or p.grabbed_by >= 0:
		top = 0.0  # (dry, broken, or a zombie has hold of you: you pull up)
	var two: bool = v.get("pillion", 0) != 0  # two up: a little slower away and at the top
	if two:
		top *= 0.94
	var want := move.limit_length(1.0) * top
	var go: float = m.accel * (0.85 if two else 1.0)
	var brake: float = m.accel * 1.6  # brakes bite harder
	var spd := p.ride_vel.length()
	if want.length() < 0.01 or spd < CRAWL:
		# Letting go (it pulls up), or at a crawl (it points anywhere).
		p.ride_vel = p.ride_vel.move_toward(want, (go if want.length() > spd else brake) * delta)
	else:
		var head := p.ride_vel / spd
		var ang := head.angle_to(want)
		if absf(ang) > U_TURN:
			spd = move_toward(spd, 0.0, brake * delta)  # right back the way you came: stop first
		else:
			var turn := lerpf(TURN_SLOW, TURN_FAST, clampf(spd / m.speed, 0.0, 1.0)) * delta
			head = head.rotated(clampf(ang, -turn, turn))
			spd = move_toward(spd, want.length(), (go if want.length() > spd else brake) * delta)
		p.ride_vel = head * spd
	var before := p.position
	var hit := 0.0
	p.position = w.slide(p.position, p.ride_vel * delta, RADIUS, false, true)
	if (p.position - before).length() < (p.ride_vel * delta).length() * 0.5:
		hit = p.ride_vel.length()
		p.ride_vel *= 0.3  # ran into something
	turn_to(v, p.ride_vel)
	v.pos = p.position
	_place(v)
	return hit


## A car, driven the way cars are: W the accelerator, S the brake and then
## reverse, A and D the wheel (it turns round its back wheels as it rolls,
## never on the spot; backing up, the tail swings the way you steer the
## nose). Let go of the wheel and it runs straight on, easing onto the
## nearest of the eight compass ways, so a street is driven dead along it.
## It hits walls, trees and parked vehicles with its whole length (CarArt.SEDAN).
const CAR_SETTLE := 0.9  # radians a second it eases straight, at full speed
const CAR_WAYS := PI / 4.0  # (the eight ways it eases onto)

static func _car_step(p: Player, v: Dictionary, move: Vector2, delta: float, w: World) -> float:
	var m: Dictionary = MODELS[v.model]
	var spd: float = v.get("spd", 0.0)
	var heading: float = v.dir
	var top: float = m.speed
	if v.fuel <= 0.0 or v.hp <= 0 or p.grabbed_by >= 0:
		top = 0.0
	var pedal := clampf(-move.y * 1.5, -1.0, 1.0)
	var steer := clampf(move.x * 1.5, -1.0, 1.0)
	# A and D are the car's own left and right, whichever way it faces.
	var want := pedal * (top if pedal > 0.0 else top * CAR_BACK)
	if pedal < 0.0 and spd > 5.0:
		want = 0.0  # (braking first: it only backs up once stopped)
	var rate: float = m.accel if signf(want) == signf(spd) and absf(want) > absf(spd) else m.accel * 2.2
	if absf(pedal) < 0.1:
		rate = m.accel * 0.5  # (off the pedals: it rolls to a stop)
	spd = move_toward(spd, want, rate * delta)
	# The faster it goes the wider it has to turn (a tap at speed is a nudge).
	var radius := CAR_TURN * (1.0 + CAR_WIDEN * clampf(absf(spd) / maxf(m.speed, 1.0), 0.0, 1.0))
	heading += steer * spd / radius * delta
	if absf(steer) < 0.1 and absf(spd) > 5.0:
		var straight := roundf(heading / CAR_WAYS) * CAR_WAYS
		heading = move_toward(heading, straight, CAR_SETTLE * minf(1.0, absf(spd) / maxf(m.speed, 1.0)) * delta)
	var pos: Vector2 = v.pos + Vector2.from_angle(heading) * spd * delta
	var hit := 0.0
	if car_blocked(w, pos, heading, CarArt.SEDAN):
		# Grazing a wall: slide along it, losing a little speed, and only a
		# head-on hit stops it (with a bounce).
		var slid := false
		for turn in [0.0, 0.1, -0.1, 0.22, -0.22]:
			var hd: float = heading + turn
			var sp: Vector2 = v.pos + Vector2.from_angle(hd) * spd * delta * 0.6
			if not car_blocked(w, sp, hd, CarArt.SEDAN):
				v.pos = sp
				v.dir = hd
				spd *= 1.0 - 1.4 * delta
				hit = absf(spd) * 0.3
				slid = true
				break
		if not slid:
			hit = absf(spd)
			spd *= -0.25  # (a bump: it bounces back a little)
	else:
		v.pos = pos
		v.dir = heading
	v.spd = spd
	v.view = "car"
	p.position = v.pos
	p.ride_vel = Vector2.from_angle(v.dir) * spd
	_place(v)
	return hit


## Would a car `spec` at `pos` facing `heading` run into anything?
static func car_blocked(w: World, pos: Vector2, heading: float, spec: Dictionary) -> bool:
	var fwd := Vector2.from_angle(heading)
	var right := fwd.orthogonal()
	var h: float = spec.len * 0.5
	var hw: float = spec.wid * 0.5
	for c in [Vector2(h, hw), Vector2(h, -hw), Vector2(-h, hw), Vector2(-h, -hw), Vector2(h, 0), Vector2(-h, 0), Vector2(0, hw), Vector2(0, -hw),
			Vector2(h * 0.5, hw), Vector2(h * 0.5, -hw), Vector2(-h * 0.5, hw), Vector2(-h * 0.5, -hw)]:
		var q: Vector2 = pos + fwd * c.x + right * c.y
		var cell := w.to_cell(q)
		if not w.in_bounds(cell) or w.is_solid(cell) or w.get_tile(cell) in [World.FLOOR, World.DOOR] or w._in_vehicle(cell, q).has_area():
			return true
	return false


## Whether a bike's headlight is on: at night, with someone riding it and
## something in the tank. It lights the road, and shows the rider up to zombies.
static func headlight_on(v: Dictionary, w: World) -> bool:
	return w.is_night and v.rider != 0 and v.fuel > 0.0 and v.hp > 0


## A headlight's beam, pointing right from the middle (a PointLight2D turns it):
## a cone fading with distance, and a little pool of light around the bike.
static func beam_texture() -> Texture2D:
	if _beam == null:
		var n := 256
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := Vector2(n, n) * 0.5
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5, y + 0.5) - c
				var r := d.length() / (n * 0.5)
				var cone := 1.0 - smoothstep(0.32, 0.5, absf(d.angle())) if d.x > 0.0 else 0.0
				var a := maxf(cone * pow(maxf(0.0, 1.0 - r), 1.2), 0.6 * maxf(0.0, 1.0 - r / 0.16))
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_beam = ImageTexture.create_from_image(img)
	return _beam


## Face a bike the way it is going (only once it is really moving).
static func turn_to(v: Dictionary, vel: Vector2) -> void:
	if vel.length() < 12.0 or is_car(v):
		return
	var prev := [Look.SIDE, v.dir < 0.0] if v.view == "side" else [Look.FRONT if v.view == "front" else Look.BACK, false]
	var pv := Look.pick_view(vel.angle(), prev)
	v.view = "side" if pv[0] == Look.SIDE else ("front" if pv[0] == Look.FRONT else "back")
	if v.view == "side":
		v.dir = -1.0 if pv[1] else 1.0


## Move a bike's drawing to where the bike is.
static func _place(v: Dictionary) -> void:
	if v.rec.is_empty():  # (a car made after the city: it draws itself)
		var n: Node2D = v.get("node")
		if n:
			n.position = v.pos
			n.visible = v.rider == 0
			n.queue_redraw()
		return
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
	if p.seat == 1:
		# Riding pillion: wherever the bike goes (the rider steers).
		var d: Player = main.players.get(v.rider)
		if d:
			p.position = d.position
		return
	var m: Dictionary = MODELS[v.model]
	var hit := step(p, v, p.move, delta, main.world)
	var q: Player = main.players.get(v.pillion) if v.pillion != 0 else null
	if hit > BUMP:
		_crash(p, q, v, hit)
		if v.hp <= 0:
			main._toast(p, "รถพังแล้ว!")
			dismount(p)
			return
	if q:
		q.position = p.position
	var speed := p.ride_vel.length()
	v.fuel = maxf(0.0, v.fuel - m.use * (0.1 + 0.9 * speed / m.speed) * (1.15 if q else 1.0) * delta)
	if v.fuel <= 0.0 and speed < 1.0 and p.move.length() > 0.1:
		main._toast(p, "แบตหมด" if m.electric else "น้ำมันหมด!")
	# The engine carries.
	_noise_t[p.peer_id] = _noise_t.get(p.peer_id, 0.0) - delta
	if _noise_t[p.peer_id] <= 0.0 and v.fuel > 0.0:
		_noise_t[p.peer_id] = 0.5
		main._make_noise(p.position, m.noise * (0.5 + 0.5 * speed / m.speed))
	# Running into zombies knocks them down, and knocks the bike about.
	if speed > HIT_SPEED:
		var car := is_car(v)
		var nose: float = CarArt.SEDAN.len * 0.5 + 4.0 if car else 12.0
		var width: float = CarArt.SEDAN.wid * 0.5 if car else RADIUS
		for z: Zombie in main.zombies.values():
			# Anything the front of the bike (or car) is about to go through.
			var ahead := Geometry2D.get_closest_point_to_segment(z.position, p.position, p.position + p.ride_vel.normalized() * nose)
			if z.down_t > 0.0 or z.position.distance_to(ahead) > width + Zombie.RADIUS + 2.0:
				continue
			var dir := p.ride_vel.normalized()
			z.knock_down()
			z.hp -= speed * 0.15 * z.armour_k("body")
			main.combat.fx_hit.rpc(z.zid, z.position, dir, true, p.peer_id, "", z.hp)
			main.fx_sound.rpc("kick", z.position)
			if z.hp <= 0.0:
				main.combat._kill_zombie(z, signf(dir.x) if dir.x != 0.0 else 1.0, "stomp")
				p.kills += 1
			v.hp -= 1 if car else 3
			p.ride_vel *= 0.85 if car else 0.6
			if car:
				v.spd = v.get("spd", 0.0) * 0.85
			main._notify(p.peer_id, &"jolt", [2.0])
			if v.hp <= 0:
				main._toast(p, "รถพังแล้ว!")
				dismount(p)
				return


## Into a wall: a jolt and a dent, and hard enough, bruises all round.
func _crash(p: Player, q: Player, v: Dictionary, speed: float) -> void:
	var hard := speed > CRASH
	v.hp -= 6 if hard else 2
	main.fx_sound.rpc("crash", p.position)
	main._make_noise(p.position, 160.0)
	for who in [p, q]:
		if who == null:
			continue
		main._notify(who.peer_id, &"jolt", [5.0 if hard else 2.5])
		if hard:
			who.take_damage(4.0)
			Body.add(who, "bruise", ["legs", "arms"].pick_random())
			main._toast(who, "ชนแรง! ฟกช้ำ")
	_send(v)


## The one riding feels it: the screen shakes.
@rpc("authority", "call_remote", "reliable")
func jolt(amount: float) -> void:
	main.shake = maxf(main.shake, amount)


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
	if is_car(v):
		free_cells(main.world, v)
		if v.has("prop"):
			v.prop.moved = true
	_place(v)
	main.fx_sound.rpc("door", v.pos)
	if is_car(v):
		main._toast(p, "W เร่ง · S เบรก/ถอย · A D เลี้ยว")


## Get on the back of a bike someone is riding.
func mount_pillion(p: Player, id: int) -> void:
	var v: Dictionary = main.world.vehicles[id]
	if v.rider == 0 or v.pillion != 0 or p.riding >= 0 or v.rider == p.peer_id:
		return
	p.riding = id
	p.seat = 1
	p.ride_vel = Vector2.ZERO
	var d: Player = main.players.get(v.rider)
	p.position = d.position if d else v.pos
	v.pillion = p.peer_id
	main.fx_sound.rpc("rustle", v.pos)
	if d:
		main._toast(d, "%s ซ้อนท้ายแล้ว" % p.pname)


func dismount(p: Player) -> void:
	if p.riding < 0:
		return
	var v: Dictionary = main.world.vehicles[p.riding]
	if p.seat == 1:
		# Off the back: the rider rides on.
		v.pillion = 0
		p.riding = -1
		p.seat = 0
		_step_off(p, v)
		return
	v.rider = 0
	p.riding = -1
	# Whoever was on the back gets off too.
	var q: Player = main.players.get(v.pillion) if v.pillion != 0 else null
	v.pillion = 0
	if q:
		q.riding = -1
		q.seat = 0
		_step_off(q, v, Vector2(0, -9))
		main._toast(q, "คนขี่ลงแล้ว")
	_place(v)
	_step_off(p, v)
	if is_car(v):
		block_parked(main.world, v)
	_send(v)


## Stand someone beside the bike (first free spot, `first` tried before the rest).
func _step_off(p: Player, v: Dictionary, first := Vector2(0, 9)) -> void:
	p.ride_vel = Vector2.ZERO
	var offs := [first, Vector2(0, 9), Vector2(0, -9), Vector2(10, 0), Vector2(-10, 0)]
	if is_car(v):
		v.spd = 0.0
		var side := Vector2.from_angle(v.dir).orthogonal() * (CarArt.SEDAN.wid * 0.5 + 7.0)
		var along := Vector2.from_angle(v.dir) * (CarArt.SEDAN.len * 0.5 + 7.0)
		offs = [side, -side, along, -along]  # (out of a door, else by a bumper)
	for off in offs:
		if main.world.can_stand(v.pos + off, Player.RADIUS):
			p.position = v.pos + off
			return


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


## What E can do with a bike: ride it, or with someone on it, hop on the back.
func actions_for(p: Player, id: int) -> Array:
	var v: Dictionary = main.world.vehicles[id]
	var m: Dictionary = MODELS[v.model]
	var out := []
	if v.rider != 0:
		out.append(Interact._act("pillion", "นั่งข้างคนขับ" if is_car(v) else "ซ้อนท้าย", v.pillion == 0, "มีคนนั่งแล้ว" if is_car(v) else "มีคนซ้อนแล้ว"))
		return out
	var why := ""
	if v.hp <= 0:
		why = "รถพัง"
	elif not v.key:
		why = "ไม่มีกุญแจ · ต่อสายตรงก่อน"
	elif v.fuel <= 0.0:
		why = "แบตหมด" if m.electric else "น้ำมันหมด · เติมจากแกลลอน"
	out.append(Interact._act("ride", "ขับ" if is_car(v) else "ขี่", why == "", why))
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
	for v in main.world.vehicles:
		if v.get("spawned", false):
			vehicle_add.rpc_id(peer, v.id, v.model, v.pos, v.dir)
	vehicles_sync.rpc_id(peer, changed())


## Server (admin menu): a car here, facing `heading`, key in, tank full.
func spawn_car(pos: Vector2, heading: float) -> void:
	# Somewhere it stands clear (not in a wall): here, else a little round about, turned each way.
	var w: World = main.world
	var at := pos
	var head := heading
	var found := false
	for r in [0.0, 30.0, 60.0, 90.0]:
		for k in (1 if r == 0.0 else 8):
			var p: Vector2 = pos + Vector2.from_angle(k * TAU / 8.0) * r
			for hd in [heading, heading + PI * 0.5, heading + PI, heading - PI * 0.5]:
				if not car_blocked(w, p, hd, CarArt.SEDAN):
					at = p
					head = hd
					found = true
					break
			if found:
				break
		if found:
			break
	vehicle_add.rpc(main.world.vehicles.size(), "sedan", at, head)


## Every machine: a vehicle that wasn't in the city when it was built.
@rpc("authority", "call_local", "reliable")
func vehicle_add(id: int, model: String, pos: Vector2, heading: float) -> void:
	var w: World = main.world
	if id != w.vehicles.size():
		return  # (already have it)
	var m: Dictionary = MODELS[model]
	var v := {id = id, model = model, seed = id * 7919, pos = pos, dir = heading, view = "car", fuel = m.fuel, hp = m.hp, key = true,
			upright = true, rider = 0, pillion = 0, rec = {}, spd = 0.0, spawned = true}
	var node := CarProp.new()
	node.v = v
	node.z_index = 1
	main.add_child(node)
	v.node = node
	w.vehicles.append(v)
	_place(v)


@rpc("authority", "call_remote", "reliable")
func vehicles_sync(ch: Dictionary) -> void:
	restore(ch)


@rpc("authority", "call_local", "reliable")
func vehicle_state(id: int, pos: Vector2, dir: float, fuel: float, hp: int, key: bool, upright: bool, view: String) -> void:
	if id >= main.world.vehicles.size():
		return  # (one we haven't been told about yet)
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
	if is_car(v) and v.rider == 0:
		block_parked(main.world, v)  # (a car standing where it was left is solid there)
	_place(v)
