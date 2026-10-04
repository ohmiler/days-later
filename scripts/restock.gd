class_name Restock
extends Node
## The city fills back up, slowly: each new game day some of the cupboards,
## fridges and shelves already searched can be searched again (people pass
## through, things get moved about). Fewer as the days go by: Days Later, the
## city runs dry (ROADMAP "ของดรอป": a budget per zone).
##
## Never in front of anyone (nobody within NEAR), never a cupboard someone keeps
## things in (anything left in it), never furniture pulled apart.
## A world setting in time (the host's menu); for now `on`.

const NEAR := 600.0  # px: nothing refills this close to a survivor
const RATE := 0.12  # share of the searched ones that refill on the first days
const FADE := 0.96  # each day the share is this much of the day before's
const FLOOR := 0.02  # never below this share

static var on := true  # (tests turn it off: test_restock's)

var main: Main


## The share of searched furniture that refills on game day `day`.
static func rate(day: int) -> float:
	return maxf(FLOOR, RATE * pow(FADE, maxi(0, day - 1)))


## Server, at the start of game day `day`: some searched furniture can be searched again.
func new_day(day: int) -> Array:
	if not on or main.world == null:
		return []
	var can := []
	for f: FurnitureProp in main.world.container_nodes:
		if not f.searched or f.stripped or f.items.any(func(it): return it != null):
			continue
		if main.players.values().any(func(p): return p.alive() and p.position.distance_to(f.position) < NEAR):
			continue
		can.append(f.data.id)
	can.shuffle()
	var ids := can.slice(0, ceili(can.size() * rate(day)))
	if not ids.is_empty():
		restocked.rpc(ids)
	return ids


@rpc("authority", "call_local", "reliable")
func restocked(ids: Array) -> void:
	for id in ids:
		if id >= 0 and id < main.world.container_nodes.size():
			main.world.container_nodes[id].set_searched(false)
