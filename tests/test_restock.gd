extends "res://tests/test_base.gd"
## The city fills back up, slowly (Restock): each new game day some searched
## furniture can be searched again, fewer as the days go by; never near a
## survivor, never a cupboard with things kept in it, never furniture pulled
## apart; searched again, it has something in it.


func run() -> void:
	check(Restock.rate(1) > Restock.rate(10) and Restock.rate(10) > Restock.rate(30) and Restock.rate(500) == Restock.FLOOR,
			"fewer each day as the city runs dry (%.3f, %.3f, %.3f), never none" % [Restock.rate(1), Restock.rate(10), Restock.rate(30)])
	SaveGame.wipe()
	await host(9591, false, true, 11)
	main.spawn_timer = 1e9
	Restock.on = true
	var w: World = main.world
	var all: Array = w.container_nodes
	for f: FurnitureProp in all:
		f.searched = true
		f.items.resize(FurnitureProp.SIZE)
		f.items.fill(null)
	# Near you, kept things in, pulled apart: never.
	me.position = all[0].position
	var near := all.filter(func(f): return f.position.distance_to(me.position) < Restock.NEAR)
	var kept: FurnitureProp = all.filter(func(f): return f.position.distance_to(me.position) > Restock.NEAR * 2)[0]
	kept.items[0] = Items.make("bandage")
	var wreck: FurnitureProp = all.filter(func(f): return f.position.distance_to(me.position) > Restock.NEAR * 2)[1]
	wreck.stripped = true
	var refilled := {}
	for day in range(2, 40):
		for id in main.restock.new_day(day):
			refilled[id] = true
		if day == 2:
			var share := float(refilled.size()) / all.size()
			check(share > 0.05 and share < 0.15, "a new day: some of the searched furniture can be searched again (%.1f%%)" % (share * 100.0))
			check(not all[refilled.keys()[0]].searched, "...and shows it")
	check(near.all(func(f): return not refilled.has(f.data.id)), "never anything near a survivor (%d near)" % near.size())
	check(not refilled.has(kept.data.id), "never a cupboard with things kept in it")
	check(not refilled.has(wreck.data.id), "never furniture pulled apart")
	check(refilled.size() > all.size() * 0.5, "over weeks, most of it fills up again (%d of %d)" % [refilled.size(), all.size()])
	# Searched again, there is something in it (or now and then nothing, as ever).
	var found := 0
	var tried := 0
	for id in refilled.keys().slice(0, 40):
		var f: FurnitureProp = all[id]
		me.position = f.position + Vector2(0, 6)
		me.search_id = id
		me.search_t = 0.0
		me.move = Vector2.ZERO
		main.inventory._tick_search(me, 0.1)
		tried += 1
		if f.searched and f.items.any(func(it): return it != null):
			found += 1
	check(found > tried / 3, "searched again, there's something to find (%d of %d)" % [found, tried])
	# Off (a world setting in time): nothing.
	Restock.on = false
	check(main.restock.new_day(50).is_empty(), "switched off, nothing fills back up")
