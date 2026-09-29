class_name Things
extends Node
## Things in the world that have a state and can be used: taps, radios, vending
## machines, and in time stoves, beds, generators, light switches...
##
## To add one: put it in DEFS (its name, starting state, whether it blocks the
## way), give it actions in `actions_for`, write `_do_<kind>_<verb>` for what
## each action does, and draw it in ThingProp. Saving, sending the state to
## everyone, the E prompt and the wheel, reach and "same building" checks all
## come from here. The state is a plain dictionary; only what differs from
## the starting state is saved or sent.

var main: Main

const REACH := 18.0
const DEFS := {
	# A tap runs from its building's rooftop tank (Buildings.tank), not its own supply.
	"tap": {name = "ก๊อกน้ำ", state = {}, solid = true},
	"radio": {name = "วิทยุ", state = {on = false}, solid = false},
	"vending": {name = "ตู้กดน้ำ", state = {broken = false}, solid = true},
	# The gas stove in a shophouse's back kitchen (the decor draws the stove;
	# this is what it does). A pot goes on, and it cooks by the game clock -
	# `ready` is when it's done, nothing counts down - so you can leave it and
	# come back. Each go uses gas from the bottle under it.
	"stove": {name = "เตาแก๊ส", state = {gas = -1, pot = {}, ready = 0.0}, solid = false},
	# A big building's diesel generator, in the plant room downstairs. Running,
	# the building has power (Buildings.power: its lights, its fridges, the
	# pump that sends water up to the roof), and it is loud. `fuel` is hours
	# of running left as of `since` (-1: as it was left, worked out from the
	# seed); running, it burns down by the clock, nothing counts it.
	"generator": {name = "เครื่องปั่นไฟ", state = {fuel = -1.0, on = false, since = 0.0}, solid = true},
	# The water jar (โอ่ง) in a shophouse bathroom: what the family kept in
	# store for when the mains ran dry. `water` is sips left (-1: as it was
	# left, worked out from the seed). It doesn't fill again by itself: it is
	# a home's reserve once the rooftop tank is empty. (The decor draws it.)
	"jar": {name = "โอ่งน้ำ", state = {water = -1}, solid = false},
	# The refugee camp's (Camp): the volunteer at the table by the gate, who
	# gives newcomers what they need to start; the notice board with the
	# day's jobs.
	"volunteer": {name = "อาสาประจำค่าย", state = {}, solid = true},
	"board": {name = "บอร์ดประกาศของค่าย", state = {}, solid = true},
}
const JAR_LEFT := [4, 30]  # sips a jar was left with, the least and the most
const BOIL_HOURS := 0.5  # game hours to boil a pot of water
const COOK_HOURS := 0.75  # ...to cook rice
const COOK_SMELL := 110.0  # cooking smells: zombies this far come to see, every few seconds
const GAS := [2, 6]  # goes a gas bottle has left, the least and the most
const TAP_GULP := 2  # sips drunk straight from a tap
const RADIO_NOISE := 95.0  # a playing radio calls zombies this far, every few seconds
const GEN_NOISE := 190.0  # a running generator, further
const GEN_TANK := 8.0  # hours of running a generator's tank holds
const GEN_CAN := 4.0  # ...a jerrycan puts in
const GEN_LEFT := [0.0, 2.5]  # what was left in one, the least and the most

var _radio_t := 0.0


# --- What can be done ------------------------------------------------------------

## Everything `p` can do with thing `id` right now: the same {verb, label, ok, why}
## as the rest of Interact.
func actions_for(p: Player, id: int) -> Array:
	var th: Dictionary = main.world.things[id]
	var s: Dictionary = th.state
	match th.kind:
		"tap":
			var wet := _tap_water(th) >= 1.0
			return [_act("drink", "ดื่มน้ำจากก๊อก (ไม่ได้ต้ม)", wet and p.thirst < 98.0,
					"แท็งก์บนดาดฟ้าแห้ง · รอฝน" if not wet else "ยังไม่กระหาย"), _tap_extra(p, th)]
		"radio":
			return [_act("toggle", "ปิดวิทยุ" if s.on else "เปิดวิทยุ (ซอมบี้ได้ยิน)")]
		"vending":
			if not s.broken:
				return [_act("smash", "ทุบตู้เอาเครื่องดื่ม (เสียงดัง)")]
		"stove":
			return _stove_actions(p, th)
		"jar":
			var sips := jar_water(th)
			var room := _room_for(p, "jar")
			return [_act("drink", "ดื่มน้ำในโอ่ง (ไม่ได้ต้ม)", sips >= 1 and p.thirst < 98.0, "โอ่งแห้งแล้ว" if sips < 1 else "ยังไม่กระหาย"),
					_act("fill", "ตักน้ำในโอ่งใส่ขวด/หม้อ", sips >= 1 and room, "โอ่งแห้งแล้ว" if sips < 1 else "ไม่มีขวดหรือหม้อที่ว่าง")]
		"volunteer":
			return [_act("talk", "คุยกับอาสา")]
		"board":
			return [_act("jobs", "ดูงานประจำวัน")]
		"generator":
			var left := gen_fuel(th, main.now())
			var can := Crafting.count_in(p.inv, "fuelcan") > 0
			var fill := _act("refuel", "เติมน้ำมัน (แกลลอน 1 ใบ)", can and left < GEN_TANK - 1.0,
					"ต้องมีแกลลอนน้ำมัน" if not can else "ถังน้ำมันเต็มแล้ว")
			if gen_running(th, main.now()):
				return [_act("stop", "ดับเครื่องปั่นไฟ"), fill]
			return [_act("start", "ติดเครื่องปั่นไฟ (เสียงดังมาก)", left > 0.05, "น้ำมันหมด · เติมจากแกลลอน"), fill]
	return []


## Tap: drink, or fill what you carry.
func _tap_extra(p: Player, th: Dictionary) -> Dictionary:
	var room := _room_for(p, "tap")
	var wet := _tap_water(th) >= 1.0
	return _act("fill", "เติมน้ำใส่ขวด/หม้อ", wet and room, "แท็งก์บนดาดฟ้าแห้ง · รอฝน" if not wet else "ไม่มีขวดหรือหม้อที่ว่าง")


## Sips left for a tap: its building's rooftop tank.
func _tap_water(th: Dictionary) -> float:
	return Buildings.tank(main, Buildings.at(main.world, th.cell))


## Anything in `p`'s bag with room for `what` water?
func _room_for(p: Player, what: String) -> bool:
	for it in p.inv:
		if it != null and Items.holds(it.id) > 0:
			var f := Items.fill_of(it)
			if f.is_empty() or (f.what == what and f.n < Items.holds(it.id)):
				return true
	return false


## Stove: put a pot of water on to boil, or rice to cook; take it off.
func _stove_actions(p: Player, th: Dictionary) -> Array:
	var s: Dictionary = th.state
	if not s.pot.is_empty():
		var done: bool = main.now() >= s.ready
		return [_act("take", "ยกหม้อลง" + ("" if done else " (ยังไม่เสร็จ)"))]
	var gas: int = stove_gas(th)
	var pot := _pot_with_water(p, 1)
	var rice := p.inv.any(func(it): return it != null and Items.def(it.id).has("cooks"))
	var why := "แก๊สหมดแล้ว" if gas <= 0 else "ต้องมีหม้อที่มีน้ำ (เติมที่ก๊อก หรือตักน้ำคลอง)"
	var out := [_act("boil", "ต้มน้ำ (ฆ่าเชื้อ · มีกลิ่นล่อซอมบี้)", gas > 0 and pot >= 0, why)]
	var rpot := _pot_with_water(p, 2)
	out.append(_act("cook", "หุงข้าว (ข้าวสาร + น้ำ 2 ส่วน)", gas > 0 and rpot >= 0 and rice,
			why if gas <= 0 or rpot < 0 else "ต้องมีข้าวสาร"))
	return out


## A pot in `p`'s bag with at least `sips` of water, or -1.
func _pot_with_water(p: Player, sips: int) -> int:
	for i in p.inv.size():
		var it = p.inv[i]
		if it != null and Items.has_tag(it.id, "cookware") and Items.fill_of(it).get("n", 0) >= sips:
			return i
	return -1


## Hours of running left in a generator at game time `now`.
func gen_fuel(th: Dictionary, now: float) -> float:
	var s: Dictionary = th.state
	var fuel: float = s.fuel
	if fuel < 0.0:
		fuel = GEN_LEFT[0] + (GEN_LEFT[1] - GEN_LEFT[0]) * float((th.id * 13 + main.world_seed) % 11) / 10.0
	if s.on:
		fuel -= (now - float(s.since)) / Main.HOUR
	return maxf(0.0, fuel)


func gen_running(th: Dictionary, now: float) -> bool:
	return th.state.on and gen_fuel(th, now) > 0.0


## Gas left in a stove's bottle (worked out from the stove until first used).
func stove_gas(th: Dictionary) -> int:
	if th.state.gas >= 0:
		return th.state.gas
	return GAS[0] + (th.id * 7 + main.world_seed) % (GAS[1] - GAS[0] + 1)


## What E says it is, with how it is doing.
static func title_of(th: Dictionary) -> String:
	var name: String = DEFS[th.kind].name
	var s: Dictionary = th.state
	match th.kind:
		"tap":
			return name
		"radio":
			return name + (" · เปิดอยู่" if s.on else "")
		"vending":
			return name + (" · พังแล้ว" if s.broken else "")
		"stove":
			if not s.pot.is_empty():
				return name + " · มีหม้อตั้งอยู่"  # (done or not: the action says)
		"generator":
			var m = Engine.get_main_loop().current_scene if Engine.get_main_loop() else null
			if m is Main and m.things:
				var left: float = m.things.gen_fuel(th, m.now())
				if m.things.gen_running(th, m.now()):
					return name + " · เดินอยู่ · น้ำมันอีกราว %d ชม." % ceili(left)
				return name + (" · น้ำมันหมด" if left <= 0.05 else " · น้ำมันพอเดินได้ราว %d ชม." % ceili(left))
	return name


func _act(verb: String, label: String, ok := true, why := "") -> Dictionary:
	return {verb = verb, label = label, ok = ok, why = why if not ok else "", key = ""}


# --- Doing it (server) -------------------------------------------------------------

## Carry out `verb` on thing `id` for `p`, if it is on offer and possible.
func act(p: Player, id: int, verb: String) -> void:
	if id < 0 or id >= main.world.things.size():
		return
	var a := Interact.find_action(actions_for(p, id), verb)
	if a.is_empty():
		return
	if not a.ok:
		main._toast(p, a.why)
		return
	var th: Dictionary = main.world.things[id]
	var fn := "_do_%s_%s" % [th.kind, verb]
	if has_method(fn):
		call(fn, p, th)


func _do_volunteer_talk(p: Player, _th: Dictionary) -> void:
	main.camp.talk(p)


func _do_board_jobs(p: Player, _th: Dictionary) -> void:
	main.camp.jobs(p)


func _do_tap_drink(p: Player, th: Dictionary) -> void:
	var bid := Buildings.at(main.world, th.cell)
	var got := Buildings.draw_water(main, bid, TAP_GULP)
	if got <= 0:
		return
	p.thirst = minf(100.0, p.thirst + Items.LIQUIDS.tap.drink * got)
	main.fx_sound.rpc("eat", p.position)
	if randf() < Items.LIQUIDS.tap.sick:
		main._toast(p, Body.add_condition(p, "diarrhea", main.now()))
	else:
		main._toast(p, "ดื่มน้ำจากก๊อก" + (" · น้ำในแท็งก์ใกล้หมด" if Buildings.tank(main, bid) < 4.0 else ""))


## Sips left in a water jar.
func jar_water(th: Dictionary) -> int:
	var w: int = th.state.water
	if w < 0:
		w = JAR_LEFT[0] + (th.id * 31 + main.world_seed) % (JAR_LEFT[1] - JAR_LEFT[0] + 1)
	return w


func _jar_take(th: Dictionary, n: int) -> int:
	var got := mini(n, jar_water(th))
	if got > 0:
		set_state(th.id, {water = jar_water(th) - got})
	return got


func _do_jar_drink(p: Player, th: Dictionary) -> void:
	var got := _jar_take(th, TAP_GULP)
	if got <= 0:
		return
	p.thirst = minf(100.0, p.thirst + Items.LIQUIDS.jar.drink * got)
	main.fx_sound.rpc("eat", p.position)
	if randf() < Items.LIQUIDS.jar.sick:
		main._toast(p, Body.add_condition(p, "diarrhea", main.now()))
	else:
		main._toast(p, "ดื่มน้ำในโอ่ง · เหลืออีก %d ส่วน" % jar_water(th))


func _do_jar_fill(p: Player, th: Dictionary) -> void:
	var got: int = main.inventory.fill_containers(p, "jar", jar_water(th))
	if got <= 0:
		return
	_jar_take(th, got)
	main.fx_sound.rpc("eat", p.position)
	main._toast(p, "ตักน้ำในโอ่ง %d ส่วน · ควรต้มก่อนดื่ม" % got)


func _do_tap_fill(p: Player, th: Dictionary) -> void:
	var bid := Buildings.at(main.world, th.cell)
	var got: int = main.inventory.fill_containers(p, "tap", floori(Buildings.tank(main, bid)))
	if got <= 0:
		return
	Buildings.draw_water(main, bid, got)
	main.fx_sound.rpc("eat", p.position)
	main._toast(p, "เติมน้ำประปา %d ส่วน · ควรต้มก่อนดื่ม" % got)


func _do_stove_boil(p: Player, th: Dictionary) -> void:
	_stove_on(p, th, _pot_with_water(p, 1), "boil", BOIL_HOURS)


func _do_stove_cook(p: Player, th: Dictionary) -> void:
	var slot := -1
	for i in p.inv.size():
		if p.inv[i] != null and Items.def(p.inv[i].id).has("cooks"):
			slot = i
	var pot_slot := _pot_with_water(p, 2)
	if slot < 0 or pot_slot < 0:
		return
	var raw: Dictionary = p.inv[slot]
	var cooks: Dictionary = Items.def(raw.id).cooks
	var pot: Dictionary = p.inv[pot_slot]
	pot.cooking = {into = cooks.into, n = int(cooks.get("n", 1)), water = int(cooks.get("water", 1))}
	raw.n -= 1
	if raw.n <= 0:
		p.inv[slot] = null
	_stove_on(p, th, pot_slot, "cook", COOK_HOURS)


## The pot from `p`'s bag onto the stove, lit, done in `hours` of game time.
func _stove_on(p: Player, th: Dictionary, slot: int, what: String, hours: float) -> void:
	if slot < 0:
		return
	main.skills.gain(p, "cook", what)  # (only once it's really on the stove)
	main.quests.note(p, what)
	var pot: Dictionary = p.inv[slot]
	p.inv[slot] = null
	main.inventory._send_inv(p)
	set_state(th.id, {gas = stove_gas(th) - 1, pot = pot, ready = main.now() + hours * Main.HOUR})
	main.fx_sound.rpc("ui_click", main.world.to_pos(th.cell))
	main._toast(p, ("ต้มน้ำ" if what == "boil" else "หุงข้าว") + " · อีกราว %d นาทีในเกม · ไปทำอย่างอื่นได้ กลิ่นจะลอยไป" % roundi(hours * 60.0))


## Take the pot off: done, the water is boiled clean (and the rice cooked);
## not done, it comes off as it went on (the gas is spent all the same).
func _do_stove_take(p: Player, th: Dictionary) -> void:
	var pot: Dictionary = th.state.pot.duplicate(true)
	var done: bool = main.now() >= th.state.ready
	var made := []
	if done:
		var f := Items.fill_of(pot)
		if pot.has("cooking"):
			var c: Dictionary = pot.cooking
			f.n = maxi(0, f.get("n", 0) - c.water)
			for i in c.n:
				made.append({id = c.into, n = 1, hp = 0, made = main.now()})
		if f.get("n", 0) > 0:
			pot.fill = {what = "clean", n = f.n}
		else:
			pot.erase("fill")
	pot.erase("cooking")
	set_state(th.id, {gas = stove_gas(th), pot = {}, ready = 0.0})
	var at := main.world.to_pos(th.cell)
	for it in [pot] + made:
		var slot: int = main.inventory._inv_slot_for(p, it)
		if slot >= 0:
			p.inv[slot] = it
		else:
			main._spawn_pickup(at + Vector2(randf_range(-6, 6), 10), it)
	main.inventory._send_inv(p)
	main.fx_sound.rpc("pickup", p.position)
	if not done:
		main._toast(p, "ยกหม้อลงก่อนเสร็จ · ยังไม่ได้อะไร")
	elif not made.is_empty():
		main._toast(p, "หุงข้าวเสร็จ · ได้%s %d จาน · เก็บไม่ได้นาน" % [Items.display_name(made[0].id), made.size()])
	else:
		main._toast(p, "ต้มน้ำเสร็จ · น้ำสะอาดดื่มได้")


func _do_generator_start(p: Player, th: Dictionary) -> void:
	var now: float = main.now()
	var left := gen_fuel(th, now)
	set_state(th.id, {fuel = left, on = true, since = now})
	var bid := Buildings.at(main.world, th.cell)
	Buildings.power_run(main, bid, now, now + left * Main.HOUR)
	_pumped[bid] = now
	var at := main.world.to_pos(th.cell)
	main.fx_sound.rpc("door", at)
	main._make_noise(at, GEN_NOISE)
	main._toast(p, "เครื่องติดแล้ว · ไฟในตึกมา ปั๊มส่งน้ำขึ้นแท็งก์ · เสียงดังไปไกล ซอมบี้ได้ยิน")


func _do_generator_stop(p: Player, th: Dictionary) -> void:
	var now: float = main.now()
	set_state(th.id, {fuel = gen_fuel(th, now), on = false, since = now})
	Buildings.power_stop(main, Buildings.at(main.world, th.cell), now)
	main.fx_sound.rpc("ui_click", main.world.to_pos(th.cell))
	main._toast(p, "ดับเครื่องแล้ว · ไฟในตึกดับ")


func _do_generator_refuel(p: Player, th: Dictionary) -> void:
	var now: float = main.now()
	var running := gen_running(th, now)
	var left := minf(GEN_TANK, gen_fuel(th, now) + GEN_CAN)
	main.crafting._take(p, "fuelcan", 1)
	main.inventory._send_inv(p)
	set_state(th.id, {fuel = left, on = running, since = now})
	if running:
		Buildings.power_run(main, Buildings.at(main.world, th.cell), now, now + left * Main.HOUR)
	main.fx_sound.rpc("eat", main.world.to_pos(th.cell))
	main._toast(p, "เติมน้ำมันแล้ว · เดินได้อีกราว %d ชม." % ceili(left))


func _do_radio_toggle(p: Player, th: Dictionary) -> void:
	set_state(th.id, {on = not th.state.on})
	main.fx_sound.rpc("ui_click", main.world.to_pos(th.cell))


func _do_vending_smash(p: Player, th: Dictionary) -> void:
	set_state(th.id, {broken = true})
	var at := main.world.to_pos(th.cell)
	main.fx_sound.rpc("glass", at)
	main._make_noise(at, 200.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = th.id * 131 + main.world_seed
	for i in rng.randi_range(2, 4):
		var id: String = ["water", "water", "energy"][rng.randi() % 3]
		main._spawn_pickup(at + Vector2(rng.randf_range(-8, 8), rng.randf_range(8, 14)), {id = id, n = 1, hp = 0})
	main._toast(p, "ทุบตู้แตก · เสียงดังไปทั้งซอย")


var _pumped := {}  # building -> game time the pump last sent water up to

## A playing radio keeps drawing zombies to it; so does the smell of cooking,
## and a running generator's din. While it runs, the pump sends water up.
func server_tick(delta: float) -> void:
	_radio_t -= delta
	if _radio_t > 0.0:
		return
	_radio_t = 5.0
	var now: float = main.now()
	for th in main.world.things:
		if th.kind == "radio" and th.state.on:
			main._make_noise(main.world.to_pos(th.cell), RADIO_NOISE)
		elif th.kind == "stove" and not th.state.pot.is_empty() and now < th.state.ready:
			main.stimulus("smell", main.world.to_pos(th.cell), COOK_SMELL, th.get("storey", 0))
		elif th.kind == "generator" and th.state.on:
			var bid := Buildings.at(main.world, th.cell)
			var from: float = _pumped.get(bid, float(th.state.since))
			var until := minf(now, float(th.state.since) + gen_fuel(th, float(th.state.since)) * Main.HOUR)
			if until > from:
				Buildings.pump(main, bid, Buildings.PUMP * (until - from) / Main.HOUR)
			_pumped[bid] = now
			if gen_running(th, now):
				main._make_noise(main.world.to_pos(th.cell), GEN_NOISE)


var _power_t := 0.0


## On every machine: which buildings have power right now (their lights), a
## look every second (a generator runs out by the clock, with nothing sent).
func tick(delta: float) -> void:
	_power_t -= delta
	if _power_t > 0.0:
		return
	_power_t = 1.0
	update_power()


func update_power() -> void:
	var w: World = main.world
	if w == null:
		return
	var now := {}
	for th in w.things:
		if th.kind == "generator":
			var bid := Buildings.at(w, th.cell)
			if Buildings.powered(main, bid):
				now[bid] = true
	if now != w.powered:
		w.set_powered(now)


# --- State (kept by WorldState, kind "thing") ------------------------------------

## How thing `id` starts (WorldState asks).
static func start_state(w: World, id: int) -> Dictionary:
	return DEFS[w.things[id].kind].state.duplicate() if id >= 0 and id < w.things.size() else {}


## Change a thing's state for everyone (server).
func set_state(id: int, state: Dictionary) -> void:
	main.world_state.set_state("thing", id, state)


## Told by WorldState whenever one changes, on every machine.
func on_changed(id: int, state: Dictionary) -> void:
	var w: World = main.world
	if w == null or id < 0 or id >= w.things.size():
		return
	w.things[id].state = state
	if id < w.thing_nodes.size():
		w.thing_nodes[id].refresh()


## A building's state changed (its tank, its power): its taps and lights show it.
func on_building_changed(id: int, _state: Dictionary) -> void:
	var w: World = main.world
	if w == null:
		return
	for th in w.things:
		if th.kind in ["tap", "generator"] and Buildings.at(w, th.cell) == id and th.id < w.thing_nodes.size():
			w.thing_nodes[th.id].refresh()
	update_power()


## Old saves kept things on their own: put them back the new way.
func restore(states: Dictionary) -> void:
	main.world_state.restore({thing = states})


# --- Placing them in the city (generation) ---------------------------------------

## Put taps in back rooms, radios in some shops, vending machines outside
## mini-marts and a few shops. Runs last in city generation (its random numbers
## come after everything else, so older saved cities keep their layout).
static func place_all(w: World, rng: RandomNumberGenerator) -> void:
	for rec in w.buildings:
		# Taps and radios go where the building's plan says (see CityGen._build_plan).
		for c in rec.get("taps", []):
			if rng.randf() < 0.7 and not w.blocked.has(c):
				_add(w, "tap", c)
		for c in rec.get("radios", []):
			if rng.randf() < 0.22 and not w.blocked.has(c):
				_add(w, "radio", c)
		for e in rec.get("taps_up", []):
			if rng.randf() < (0.95 if rec.get("big", false) else 0.7) and not w.storey_blocked(e[1]).has(e[0]):
				_add(w, "tap", e[0], e[1])
		for c in rec.get("generators", []):
			_add(w, "generator", c)
		var r: Rect2i = rec.rect
		if rec.kind == "store" or rng.randf() < 0.06:
			for tries in 4:
				var c := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), r.end.y)
				if w.get_tile(c) in [World.SIDEWALK, World.SOI] and CityGen._fits(w, [c]):
					_add(w, "vending", c)
					break


## The stoves in back kitchens (the plans' `G`), on the ground floor. No random
## numbers, and after everything else: older saved cities keep their things.
static func place_stoves(w: World) -> void:
	for d in w.decor:
		if d.kind == "stove" and (d.get("storey", 0) == 0 or d.building.get("big", false)):
			_add(w, "stove", d.cell, d.get("storey", 0))


## The water jars, from the decor (after everything else, so the things
## before them keep their ids in old saves).
static func place_jars(w: World) -> void:
	for d in w.decor:
		if d.kind == "jar" and not d.get("outside", false):
			_add(w, "jar", d.cell, d.get("storey", 0))


## The camp's volunteer and notice board, just inside the gate facing the
## street (after everything else: new things go after the old ones).
static func place_camp(w: World) -> void:
	for camp in w.camps:
		var r: Rect2i = camp.rect
		var c := r.get_center()
		_add(w, "volunteer", Vector2i(c.x - 4, r.end.y - 14))
		_add(w, "board", Vector2i(c.x + 4, r.end.y - 14))


static func _add(w: World, kind: String, c: Vector2i, storey := 0) -> void:
	if DEFS[kind].solid:
		if storey > 0:
			w.storey_blocked(storey)[c] = true
		else:
			w.blocked[c] = true
	var th := {id = w.things.size(), kind = kind, cell = c, state = DEFS[kind].state.duplicate()}
	if storey > 0:
		th.storey = storey
	w.things.append(th)
