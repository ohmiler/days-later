class_name Survival
extends Node
## Staying alive, and the world pushing back: needs, infection, turning, weather, zombie spawns and hordes.
## Split out of main.gd; shared state (world, players, zombies, pickups) lives there.

var main: Main


var rain_t := 120.0  # server: time until the weather next changes
# Survival tuning, per second. A full stomach lasts about two in-game days.
const HUNGER_RATE := 100.0 / 480.0
const THIRST_RATE := 100.0 / 330.0  # Bangkok heat: water runs out faster
const INFECTION_RATE := 0.35
const STARVE_DAMAGE := 0.6
const BLEED_DAMAGE := 0.8
const BITE_INFECT_CHANCE := 0.2
const BITE_BLEED_CHANCE := 0.3
# Horde nights: every HORDE_EVERY days the whole city comes for you.
const HORDE_EVERY := 3
const HORDE_MAX_ZOMBIES := 160
var horde_announced := -1  # day we last announced / started / ended, so each fires once
var horde_started := -1
var horde_ended := -1
## Weather: dry spells and downpours of a few minutes, more often at night.
func _tick_weather(delta: float) -> void:
	rain_t -= delta
	if rain_t > 0.0:
		return
	var start := not main.raining and randf() < (0.45 if main.world.is_night else 0.3)
	_set_rain(start)
	rain_t = randf_range(90.0, 200.0) if start else randf_range(150.0, 400.0)


func _set_rain(on: bool) -> void:
	if on == main.raining:
		return
	main.raining = on
	main.rain_fx.visible = on
	if main.in_game:
		main.ui.push_feed("ฝนตก · เสียงฝนกลบเสียงฝีเท้าคุณ" if on else "ฝนหยุดแล้ว")


func _draw_rain() -> void:
	var sz := main.rain_fx.size
	var t := Time.get_ticks_msec() / 1000.0
	for i in 170:
		var x := fmod(World.hash01(i, 1, 60) * sz.x + t * 90.0, sz.x + 40.0) - 20.0
		var y := fmod(World.hash01(i, 2, 61) * sz.y + t * (600.0 + World.hash01(i, 3, 62) * 250.0), sz.y + 40.0) - 20.0
		main.rain_fx.draw_line(Vector2(x, y), Vector2(x - 3, y + 14), Color(0.75, 0.8, 0.9, 0.22), 1.0)
	main.rain_fx.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.1, 0.12, 0.16, 0.12))


# --- Sleeping ---------------------------------------------------------------

const SLEEP_HEAL := 0.6  # health a second asleep, anywhere
const SAFE_BONUS := 3.0  # ...times this in a building shut tight with no zombie inside
const BED_BONUS := 1.5  # ...and times this in a bed
const SLEEP_NEEDS := 0.5  # hunger and thirst go down this much slower
const SLEEP_WAKE := 70.0  # a zombie this close wakes you
const SLEEP_TOO_CLOSE := 120.0  # ...and this close you can't get to sleep
const NIGHT_SPEED := 6.0  # how much faster time runs when everyone is asleep


## Time runs faster when every living survivor is asleep, so a night can be
## slept through. One person awake keeps it normal for everyone.
func time_speed() -> float:
	var any := false
	for p: Player in main.players.values():
		if p.alive() and p.pname != "":
			if not p.sleeping:
				return 1.0
			any = true
	return NIGHT_SPEED if any else 1.0


## Nearest zombie to a spot, in pixels (INF with none about).
func _nearest_zombie(at: Vector2) -> float:
	var best := INF
	for z: Zombie in main.zombies.values():
		best = minf(best, z.position.distance_to(at))
	return best


## A spot is safe inside a building whose every door and window is shut (and
## not smashed), with no zombie inside. Out in the street it never is.
func spot_safe(pos: Vector2) -> bool:
	var w: World = main.world
	var b = w.building_at.get(w.to_cell(pos))
	if b == null:
		return false
	for d in w.doors:
		if w.is_built(d.id) or w.building_at.get(d.cell) != b:
			continue
		if not d.closed or d.broken:
			return false
	for z: Zombie in main.zombies.values():
		if w.building_at.get(w.to_cell(z.position)) == b:
			return false
	return true


func can_sleep(p: Player) -> String:
	if _nearest_zombie(p.position) < SLEEP_TOO_CLOSE:
		return "มีซอมบี้อยู่ใกล้ นอนไม่ลง"
	return ""


## Lie down: on a bed (container id) or, with bed -1, right where you stand.
func start_sleep(p: Player, bed: int) -> void:
	p.sleeping = true
	if bed >= 0:
		var f: FurnitureProp = main.world.container_nodes[bed]
		p.position = f.position + (Vector2(0, 0.1) if f.data.get("long", 0) == 2 else Vector2(f.bed_left() + 8.0, 0))  # head on the pillow
	p.sleep_check = 0.0
	p.sleep_bed = bed
	var where := "บนเตียง" if bed >= 0 else "บนพื้น"
	if spot_safe(p.position):
		main._toast(p, "นอน%s · ที่นี่ปิดแน่น หลับสนิท" % where)
	elif main.world.building_at.has(main.world.to_cell(p.position)):
		main._toast(p, "นอน%s · ประตูหน้าต่างยังเปิดอยู่ หลับไม่สนิท" % where)
	else:
		main._toast(p, "นอนกลางแจ้ง · อันตราย หลับไม่สนิท")


func _tick_sleep(p: Player, delta: float) -> void:
	p.sleep_check -= delta
	if p.sleep_check <= 0.0:
		p.sleep_check = 1.0
		if _nearest_zombie(p.position) < SLEEP_WAKE:
			p.sleeping = false
			main._toast(p, "สะดุ้งตื่น! มีอะไรอยู่ใกล้ๆ")
			return
		p.sleep_safe = spot_safe(p.position)
	if p.hunger > 20.0 and p.thirst > 20.0:
		p.hp = minf(Player.MAX_HP, p.hp + SLEEP_HEAL * (SAFE_BONUS if p.sleep_safe else 1.0) * (BED_BONUS if p.sleep_bed >= 0 else 1.0) * delta)
	p.stamina = minf(100.0, p.stamina + 40.0 * delta)
	p.exhausted = false


## Hunger, thirst, infection, bleeding and stamina (server).
func _tick_needs(p: Player, delta: float) -> void:
	if not p.alive():
		p.sleeping = false
		return
	if p.sleeping:
		_tick_sleep(p, delta)
	var running := p.sprint and not p.sneak and p.move.length() > 0.1 and not p.exhausted and p.stamina > 0.0
	# Footsteps: quiet walking, loud running, silent sneaking.
	p.step_t -= delta
	if p.move.length() > 0.1 and not p.sneak and p.step_t <= 0.0:
		p.step_t = 0.5
		main._make_noise(p.position, main.NOISE_RUN if running else main.NOISE_WALK)
	var slow := SLEEP_NEEDS if p.sleeping else 1.0
	p.hunger = maxf(0.0, p.hunger - HUNGER_RATE * delta * slow * (1.6 if running else 1.0))
	p.thirst = maxf(0.0, p.thirst - THIRST_RATE * delta * slow * (1.8 if running else 1.0))
	if p.sleeping:
		pass  # (rested in _tick_sleep)
	elif running:
		p.stamina = maxf(0.0, p.stamina - 22.0 * delta / p.load_speed())  # heavier tires you faster
		if p.stamina <= 0.0:
			p.exhausted = true
			main._toast(p, "หมดแรง! ต้องพักก่อนวิ่งต่อ")
	else:
		var regen := 16.0 if p.hunger > 20.0 and p.thirst > 20.0 else 6.0
		p.stamina = minf(100.0, p.stamina + regen * delta)
		if p.exhausted and p.stamina > 35.0:
			p.exhausted = false
	if p.bitten:
		p.bitten = false
		var guard := 1.0 - p.armor()
		if p.torn != "":
			main._toast(p, "%sขาดแล้ว!" % p.torn)
			p.torn = ""
			main.inventory._send_inv(p)
		elif not p.worn.is_empty():
			main.inventory._send_inv(p)  # clothes wore down
		if p.infection <= 0.0 and randf() < BITE_INFECT_CHANCE * guard:
			p.infection = 12.0
			main._toast(p, "โดนกัด! ติดเชื้อแล้ว หายาปฏิชีวนะ")
		if not p.bleeding and randf() < BITE_BLEED_CHANCE * guard:
			p.bleeding = true
			main._toast(p, "เลือดออก! ใช้ผ้าพันแผลห้ามเลือด")
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


## A screamer that spots you shrieks: every zombie for a long way comes running.
func zombie_scream(z: Zombie) -> void:
	main.fx_sound.rpc("scream", z.position)
	main._make_noise(z.position, 260.0)


## Send a warning once when a condition becomes true; re-arm when it clears.
func _warn(p: Player, key: String, cond: bool, text: String) -> void:
	if cond and not p.warned.has(key):
		p.warned[key] = true
		main._toast(p, text)
	elif not cond:
		p.warned.erase(key)


## The infection wins: the player dies and gets back up as a zombie in their clothes.
func _turn(p: Player) -> void:
	p.infection = 100.0
	p.take_damage(9999)
	p.dropped = true
	main.inventory._drop_everything(p, true)
	fx_turned.rpc(p.peer_id)
	var z := main._add_zombie(main.next_zid, p.position)
	main.next_zid += 1
	var o := [p.shirt, p.pants, p.hair, p.wear_ids.duplicate()]
	z.apply_outfit(o)
	main.outfits[z.zid] = o
	zombie_outfit.rpc(z.zid, o)


@rpc("authority", "call_remote", "reliable")
func zombie_outfit(zid: int, o: Array) -> void:
	main.outfits[zid] = o
	var z: Zombie = main.zombies.get(zid)
	if z:
		z.apply_outfit(o)


@rpc("authority", "call_local", "reliable")
func fx_turned(peer_id: int) -> void:
	var p: Player = main.players.get(peer_id)
	if p:
		p.turned = true
		Sfx.play(main, "groan", p.position, 0.0, 0.8)


static func is_horde(d: int, t: float) -> bool:
	# The horde night starts at dusk on every third day and runs past midnight.
	return (d % HORDE_EVERY == 0 and t > 0.764) or (d % HORDE_EVERY == 1 and d > 1 and t < 0.036)


func _tick_horde() -> void:
	if main.day % HORDE_EVERY == 0 and main.time > 0.62 and horde_announced != main.day:
		horde_announced = main.day
		fx_announce.rpc("คืนนี้ฝูงซอมบี้จะบุกเมือง! หาที่หลบ ปิดประตู ตอกไม้ให้แน่น", true)
	if is_horde(main.day, main.time) and horde_started != main.day - (0 if main.day % HORDE_EVERY == 0 else 1):
		horde_started = main.day - (0 if main.day % HORDE_EVERY == 0 else 1)
		main.spawn_timer = 0.0
		fx_announce.rpc("ฝูงซอมบี้มาแล้ว!", true)
	if main.day % HORDE_EVERY == 1 and main.day > 1 and main.time > 0.036 and main.time < 0.2 and horde_ended != main.day:
		horde_ended = main.day
		fx_announce.rpc("รอดคืนฝูงมาได้ · ฟ้าใกล้สางแล้ว", false)


## Horde zombies come in from just off-screen of a random player and head straight for them.
func _spawn_horde_zombie() -> void:
	var targets: Array = main.players.values().filter(func(q): return q.alive())
	if targets.is_empty():
		return
	var p: Player = targets[randi() % targets.size()]
	for attempt in 20:
		var pos: Vector2 = p.position + Vector2.from_angle(randf() * TAU) * randf_range(280, 420)
		if main.world.can_stand(pos, 5):
			var z := main._add_zombie(main.next_zid, pos)
			main.next_zid += 1
			z.hear(p.position)
			return


@rpc("authority", "call_local", "reliable")
func fx_announce(text: String, siren: bool) -> void:
	main.ui.announce(text)
	if siren:
		Sfx.play(main, "siren", main.camera.position, -6.0, 1.0)


func _spawn_zombie() -> void:
	for attempt in 30:
		var c := Vector2i(randi_range(0, World.W - 1), randi_range(0, World.H - 1))
		var pos := main.world.to_pos(c)
		if main.world.is_solid(c):
			continue
		var too_close := false
		for p: Player in main.players.values():
			if p.position.distance_to(pos) < 300:
				too_close = true
		if not too_close:
			main._add_zombie(main.next_zid, pos)
			main.next_zid += 1
			return
