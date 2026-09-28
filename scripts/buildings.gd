class_name Buildings
## What a building knows about itself (ROADMAP core 6), kept in WorldState as
## kind "building" by its index in World.buildings:
##   tank     sips of water in the tank on its roof: the taps on every floor
##            run from it, as they do in Bangkok. The rain fills it.
##   cistern  a big building's tank under the ground (what the mains left in
##            it): the pump sends it up to the roof, but only with power.
##   power    when it has had power: the runs of its generator, [[from, to],
##            ...] in game time (`to` is when the fuel runs out, or when it
##            was switched off), the last few kept. Lights and fridges ask.
##   trapped  the zombies still shut inside a big building since the outbreak
##            (Survival._tick_trapped lets them out when someone comes near)
##   owner    who claimed it (not yet: see ROADMAP "เจ้าของ")
## The tank isn't topped up as the rain falls (hundreds of buildings, every
## few seconds, sent to everyone): Main.rain_total adds up how long it has
## rained, and a tank remembers the rain_total when it was last drawn from.
## How full it is now is worked out from that, whenever someone asks. Power
## is the same: nothing ticks while a generator runs, the run says until when.

const TANK := 60.0  # sips a shophouse's rooftop tank holds (a big building's, more: see size_k)
const TANK_RAIN := 4.0  # sips an hour of rain puts in it (a shower tops a tank up; only a long rain fills one)
const START := 24  # a tank starts with up to this many sips (what was left in it)
const CISTERN := 30.0  # sips under a big building, for each 100 cells of it
const PUMP := 40.0  # sips an hour the pump sends up to the roof (with power)
const POWER_LOG := 6  # runs of the generator remembered


static func start(w: World, id: int) -> Dictionary:
	var rec: Dictionary = w.buildings[id] if id >= 0 and id < w.buildings.size() else {}
	var k := size_k(rec)
	var sd := int(rec.get("seed", 0))
	return {tank = float(sd % (int(START * k) + 1)), tank_at = 0.0,
			cistern = floorf(CISTERN * k * (0.4 + float(sd % 7) / 10.0)) if rec.get("big", false) else 0.0,
			power = [], owner = "", trapped = trapped_start(rec)}


const TRAPPED := 1.6  # zombies shut in a big building, for each 100 cells of it (and floor)
const TRAPPED_MAX := 14


## How many were shut inside when it all began: wards, shop floors, offices.
static func trapped_start(rec: Dictionary) -> int:
	if not rec.get("big", false):
		return 0
	var n := size_k(rec) * TRAPPED * (0.6 + 0.2 * int(rec.get("floors", 1)))
	return clampi(int(n) + int(rec.get("seed", 0)) % 3, 2, TRAPPED_MAX)


## How much bigger than a shophouse its roof (and its tank) is: 1 for a
## shophouse, a hospital's many times that.
static func size_k(rec: Dictionary) -> float:
	if not rec.get("big", false):
		return 1.0
	var r: Rect2i = rec.rect
	return maxf(1.0, r.get_area() / 100.0)


## The building a cell is in (its index), or -1.
static func at(w: World, c: Vector2i) -> int:
	var b = w.building_at.get(c)
	return int(b.data.get("id", -1)) if b != null else -1


static func capacity(w: World, id: int) -> float:
	return TANK * size_k(w.buildings[id]) if id >= 0 and id < w.buildings.size() else 0.0


## Sips in building `id`'s tank now.
static func tank(main: Node, id: int) -> float:
	if id < 0:
		return 0.0
	var s: Dictionary = main.world_state.state("building", id)
	var k := size_k(main.world.buildings[id])
	return minf(TANK * k, float(s.tank) + (main.rain_total - float(s.tank_at)) * TANK_RAIN * k / Main.HOUR)


## Server: take `n` sips from the tank (as much as there is). Returns how many.
static func draw_water(main: Node, id: int, n: int) -> int:
	var have := floori(tank(main, id))
	var take := mini(n, have)
	if take > 0:
		main.world_state.set_state("building", id, {tank = tank(main, id) - take, tank_at = main.rain_total})
	return take


## Server: the pump sends up to `n` sips from the cistern to the roof (as
## much as there is and there's room for). Returns how many.
static func pump(main: Node, id: int, n: float) -> float:
	var s: Dictionary = main.world_state.state("building", id)
	var now_tank := tank(main, id)
	var moved := minf(n, minf(float(s.cistern), capacity(main.world, id) - now_tank))
	if moved > 0.0:
		main.world_state.set_state("building", id, {tank = now_tank + moved, tank_at = main.rain_total, cistern = float(s.cistern) - moved})
	return maxf(moved, 0.0)


# --- Power ------------------------------------------------------------------------

## Has building `id` got power at game time `t` (now if left out)?
static func powered(main: Node, id: int, t := -1.0) -> bool:
	if id < 0:
		return false
	if t < 0.0:
		t = main.now()
	for run in main.world_state.state("building", id).power:
		if t >= float(run[0]) and t < float(run[1]):
			return true
	return false


## How many seconds of game time building `id` had power between `a` and `b`.
static func power_between(main: Node, id: int, a: float, b: float) -> float:
	var out := 0.0
	if id < 0 or b <= a:
		return out
	for run in main.world_state.state("building", id).power:
		out += maxf(0.0, minf(b, float(run[1])) - maxf(a, float(run[0])))
	return out


## Server: the generator runs from `from` until `to` (when its fuel runs out).
## Refuelled while it runs, the same run goes on longer.
static func power_run(main: Node, id: int, from: float, to: float) -> void:
	var runs: Array = main.world_state.state("building", id).power.duplicate(true)
	if not runs.is_empty() and float(runs[-1][1]) > from:
		runs[-1][1] = to
	else:
		runs.append([from, to])
	main.world_state.set_state("building", id, {power = runs.slice(maxi(0, runs.size() - POWER_LOG))})


## Server: the generator stopped at `at`.
static func power_stop(main: Node, id: int, at: float) -> void:
	var runs: Array = main.world_state.state("building", id).power.duplicate(true)
	if not runs.is_empty() and float(runs[-1][1]) > at:
		runs[-1][1] = at
		main.world_state.set_state("building", id, {power = runs})
