class_name Buildings
## What a building knows about itself (ROADMAP core 6), kept in WorldState as
## kind "building" by its index in World.buildings:
##   tank    sips of water in the tank on its roof: a shophouse's taps run
##           from it, as they do in Bangkok. The rain fills it.
##   power   a generator running (not yet: round 4)
##   owner   who claimed it (not yet: see ROADMAP "เจ้าของ")
## The tank isn't topped up as the rain falls (hundreds of buildings, every
## few seconds, sent to everyone): Main.rain_total adds up how long it has
## rained, and a tank remembers the rain_total when it was last drawn from.
## How full it is now is worked out from that, whenever someone asks.

const TANK := 60.0  # sips a rooftop tank holds
const TANK_RAIN := 12.0  # sips an hour of rain puts in
const START := 24  # a tank starts with up to this many sips (what was left in it)


static func start(w: World, id: int) -> Dictionary:
	var rec: Dictionary = w.buildings[id] if id >= 0 and id < w.buildings.size() else {}
	return {tank = float(int(rec.get("seed", 0)) % (START + 1)), tank_at = 0.0, power = false, owner = ""}


## The building a cell is in (its index), or -1.
static func at(w: World, c: Vector2i) -> int:
	var b = w.building_at.get(c)
	return int(b.data.get("id", -1)) if b != null else -1


## Sips in building `id`'s tank now.
static func tank(main: Node, id: int) -> float:
	if id < 0:
		return 0.0
	var s: Dictionary = main.world_state.state("building", id)
	return minf(TANK, float(s.tank) + (main.rain_total - float(s.tank_at)) * TANK_RAIN / Main.HOUR)


## Server: take `n` sips from the tank (as much as there is). Returns how many.
static func draw_water(main: Node, id: int, n: int) -> int:
	var have := floori(tank(main, id))
	var take := mini(n, have)
	if take > 0:
		main.world_state.set_state("building", id, {tank = tank(main, id) - take, tank_at = main.rain_total})
	return take
