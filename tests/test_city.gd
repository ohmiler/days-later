extends "res://tests/test_base.gd"
## The city from a seed must come out exactly the same every time, and the same
## as it always has: saved cities are stored as a seed plus changes, so if the
## generator drifts, every saved city breaks. If you change generation on
## purpose, update the fingerprints below (and think about old saves).

const SEED := 777
## (Generator 7: zones, each its own map, the first one here. Changing these means old
## cities can no longer be rebuilt: bump CityGen.GEN so their saves move to a
## new city instead of loading wrong.)
const FINGERPRINT := {tiles = 3622999061, doors = 1372506714, containers = 502539381, buildings = 3617317347}


func _fingerprint(w: World) -> Dictionary:
	var doors := []
	for d in w.doors:
		doors.append([d.cell, d.kind, d.closed])
	var cont := []
	for c in w.containers:
		cont.append([c.cell, c.kind, c.table])
	var b := []
	for r in w.buildings:
		b.append([r.rect, r.kind, r.seed])
	return {tiles = hash(w.tiles), doors = hash(doors), containers = hash(cont), buildings = hash(b)}


func _make() -> World:
	var w := World.new()
	w.prop_parent = Node2D.new()
	root.add_child(w.prop_parent)
	root.add_child(w)
	w.generate(SEED)
	return w


func run() -> void:
	var bad := CityGen.prefab_problems()
	check(CityGen.PREFABS.size() >= 4, "the building plans load (%d)" % CityGen.PREFABS.size())
	check(bad.is_empty(), "every plan is drawn correctly" + ("" if bad.is_empty() else ": " + "; ".join(bad)))
	var a := _make()
	var fa := _fingerprint(a)
	for k in FINGERPRINT:
		check(fa[k] == FINGERPRINT[k], "seed %d %s unchanged (%d)" % [SEED, k, fa[k]])
	var b := _make()
	check(_fingerprint(b) == fa, "generating twice gives the same city")
	var kinds_a := a.street_props.map(func(p): return p.kind)
	var kinds_b := b.street_props.map(func(p): return p.kind)
	check(kinds_a == kinds_b, "street props come out the same too (%d)" % kinds_a.size())
	check(a.can_stand(a.to_pos(a.spawn_cell), 5), "the spawn corner is free to stand on")
	# Every door and furniture cell is reachable from spawn (nothing walled in by props).
	# (A closed door is solid to the path finder, so aim for the cells beside it.)
	var start := a.to_pos(a.spawn_cell)
	var unreachable := []
	for d in a.doors:
		if d.kind != "door":
			continue
		var ok := false
		for dir in World.DIRS:
			var c: Vector2i = d.cell + dir
			if not a.is_solid(c) and not a.path_between(start, a.to_pos(c)).is_empty():
				ok = true
				break
		if not ok:
			unreachable.append(d.cell)
	for f in a.containers:
		if f.get("up", false):
			# Upstairs: from the top of the stairs.
			var st: Vector2i = a.building_at[f.cell].data.stairs
			if not World.DIRS.any(func(dir): return not a.is_solid_up(f.cell + dir) and (f.cell + dir == st or not a.path_up(a.to_pos(st), a.to_pos(f.cell + dir)).is_empty())):
				unreachable.append(f.cell)
		elif not World.DIRS.any(func(dir): return not a.is_solid(f.cell + dir) and not a.path_between(start, a.to_pos(f.cell + dir)).is_empty()):
			unreachable.append(f.cell)
	check(unreachable.is_empty(), "every door and cupboard can be walked up to from spawn (%d cannot: %s)" % [unreachable.size(), unreachable.slice(0, 5)])
	var kinds := {}
	for p in a.street_props:
		kinds[p.kind] = true
	for k in ["wreck", "motorbike", "spirit", "boat", "stall"]:
		check(kinds.has(k), "city has some %s" % k)
