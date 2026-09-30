extends "res://tests/test_base.gd"
## Loot by how dangerous a place is (Items tiers): homes and corner shops were
## picked over first, the big buildings nobody dared hold the good things.


func _finds(table: String, kind: String, t: int, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var seen := {}
	for i in n:
		for id in Items.roll(table, kind, rng, t):
			seen[id] = seen.get(id, 0) + 1
	return seen


func run() -> void:
	# Where a cupboard is decides its tier: the shop, or the building around it.
	check(Items.tier_of("home", "") == 1 and Items.tier_of("store", "") == 1, "a home and a minimart are everyday places")
	check(Items.tier_of("tools", "") == 2 and Items.tier_of("med", "") == 2, "a hardware shop and a pharmacy are worth breaking into")
	check(Items.tier_of("med", "hospital") == 3 and Items.tier_of("tools", "mall") == 3 and Items.tier_of("home", "hospital") == 3,
			"anything inside a hospital or the mall is dangerous ground")
	check(Items.tier_of("home", "flats") == 1, "a flat is still a home")

	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var kinds: Array = Items.FURN_LOOT.keys()

	# What only the dangerous places hold never turns up anywhere safer.
	var leaked := {}
	for t in [1, 2]:
		for table in Items.PLACES:
			for kind in kinds:
				for id in _finds(table, kind, t, 15, rng):
					if Items.tier(id) > t:
						leaked[id] = t
	check(leaked.is_empty(), "nothing turns up below its tier %s" % [leaked])

	# ...and every one of them can be found somewhere dangerous.
	var top := {}
	for tt in [3, 4]:
		for table in Items.PLACES:
			for kind in kinds:
				top.merge(_finds(table, kind, tt, 60, rng))
	var missing := Items.DEFS.keys().filter(func(id): return Items.tier(id) >= 3 and not Items.DEFS[id].get("places", []).is_empty() and not top.has(id))
	check(missing.is_empty(), "every dangerous-place item can be found in one (missing %s)" % [missing])
	check(Items.def("fireaxe").dmg > Items.def("axe").dmg and Items.tier("fireaxe") == 3, "the fire axe is the best axe, and only in the big buildings")

	# The same hardware shelves hold more, and better, deeper in.
	var shop := _finds("tools", "crate", 2, 1500, rng)
	var mall := _finds("tools", "crate", 3, 1500, rng)
	var count := func(seen: Dictionary) -> int:
		return seen.values().reduce(func(a, b): return a + b, 0)
	var rare := func(seen: Dictionary) -> float:
		var r := 0
		for id in seen:
			if Items.rarity_of(id) == "rare":
				r += seen[id]
		return float(r) / maxf(1.0, count.call(seen))
	check(count.call(mall) > count.call(shop) * 1.3, "a mall's hardware shelves hold more than a shophouse's (%d vs %d)" % [count.call(mall), count.call(shop)])
	check(rare.call(mall) > rare.call(shop) * 2.0, "and rare things far more often (%.0f%% vs %.0f%%)" % [rare.call(mall) * 100, rare.call(shop) * 100])
	var home := _finds("home", "crate", 1, 1500, rng)
	check(rare.call(home) < rare.call(shop), "a home's rare finds are rarer still (%.1f%%)" % (rare.call(home) * 100))
	# Homes still feed you: the essentials didn't get rarer.
	var fed := 0
	for i in 1000:
		if Items.roll("home", "table", rng, 1).any(func(id): return Items.category(id) in ["food", "drink", "medicine"]):
			fed += 1
	check(fed > 700, "a home's kitchen table still mostly has something to eat or drink (%d%%)" % (fed / 10))

	# In the game: searching in a hospital goes by its tier, and walking in says so.
	await host(9372)
	var w: World = main.world
	var big := -1
	for i in w.buildings.size():
		if w.buildings[i].kind in ["hospital", "mall"]:
			big = i
			break
	check(big >= 0, "the city has a hospital or a mall")
	if big < 0:
		return
	var boxes := w.container_nodes.filter(func(f): return f.data.get("storey", 0) == 0 and Buildings.at(w, f.data.cell) == big)
	var searched := 0
	var total := 0
	var nonempty := 0
	for f: FurnitureProp in boxes.slice(0, 12):
		me.position = f.position + Vector2(0, 8)
		me.search_id = f.data.id
		me.search_t = 0.0
		simulate(0.05)
		main.inventory.req_close_box()
		if not f.searched:
			continue
		searched += 1
		var n := 0
		for it in f.items:
			if it != null:
				n += it.n
		total += n
		if n > 0:
			nonempty += 1
			if nonempty <= 3:
				check(n >= 2, "a %s in the %s held %d things (2 or more deeper in)" % [f.data.kind, w.buildings[big].kind, n])
	check(searched > 0, "searched %d cupboards in the %s (%d things)" % [searched, w.buildings[big].kind, total])
	me.position = w.container_nodes[boxes[0].data.id].position + Vector2(0, 8)
	main._danger_bid = -1
	main._note_danger(me)
	check(main._danger_bid == big, "walking into the %s warns it's dangerous" % w.buildings[big].kind)
