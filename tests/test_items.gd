extends "res://tests/test_base.gd"
## The item table in data/items.cfg: it reads, nothing is mistyped, and the
## rules built on it (loot by rarity, tags, weight) work.


func run() -> void:
	check(Items.DEFS.size() >= 30, "the item table loads (%d items)" % Items.DEFS.size())
	var bad := Items.problems()
	check(bad.is_empty(), "every item is filled in correctly" + ("" if bad.is_empty() else ": " + "; ".join(bad)))
	check(Items.def("water").drink == 45.0 and Items.stack("water") == 6, "fields come through (water: drink 45, stacks of 6)")
	check(Items.def("knife").draw.col is Color, "colours are read as colours")

	# Every kind of place has something to find, and rare things turn up less.
	for place in Items.PLACES:
		check(not Items.LOOT[place].is_empty(), "%s has things to find" % place)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 3000:
		for id in Items.roll("tools", "crate", rng):
			seen[id] = seen.get(id, 0) + 1
	check(seen.get("hammer", 0) > seen.get("axe", 0) * 2, "common finds outnumber rare ones (hammer %d, axe %d)" % [seen.get("hammer", 0), seen.get("axe", 0)])

	# What a piece of furniture holds is what you'd expect of it.
	var cats := {}
	for i in 1000:
		for id in Items.roll("home", "fridge", rng):
			cats[Items.category(id)] = true
	check(cats.keys().all(func(c): return c in ["food", "drink"]), "a fridge holds food and drink (%s)" % [cats.keys()])
	var essential := 0
	for i in 1000:
		if Items.roll("home", "table", rng).any(func(id): return Items.category(id) in ["food", "drink", "medicine"]):
			essential += 1
	check(essential > 700, "a kitchen table in a home mostly has something to eat or drink (%d%%)" % (essential / 10))
	var meds := 0
	for i in 1000:
		if Items.roll("med", "shelf", rng).any(func(id): return Items.category(id) == "medicine"):
			meds += 1
	check(meds > 700, "a pharmacy shelf mostly has medicine (%d%%)" % (meds / 10))
	# Shops hold their own trade: a barber's station its blades, a phone shop's
	# glass case phones and batteries, a gold shop's gold.
	var trade := {"barber/mirror": ["scissors", "razor"], "phone/glass": ["phone", "battery", "powerbank"],
			"valuables/glass": ["gold"], "food/stall": ["mama", "snack", "water", "energy"]}
	for k in trade:
		var hits := 0
		for i in 500:
			if Items.roll(k.get_slice("/", 0), k.get_slice("/", 1), rng).any(func(id): return id in trade[k]):
				hits += 1
		check(hits > 150, "%s turns up its trade (%d%%)" % [k, hits / 5])

	# Rules go by tags, so a new blade works without code.
	check(Items.has_tag("axe", "sever") and not Items.has_tag("bat", "blade"), "tags say what cuts")
	check(Combat.death_style("knife") == "stab", "a weapon's death styles come from the table")

	# Weight slows you down past what you can carry, and a bag carries more.
	await host(9360)
	me.inv.fill(null)
	me.set_wear({})
	check(me.load_speed() == 1.0, "an empty bag does not slow you")
	var plain := me.speed_mult()
	me.inv[0] = {id = "wood", n = 10, hp = 0}
	me.inv[1] = {id = "wood", n = 10, hp = 0}
	check(me.load_kg() == 20.0 and me.speed_mult() < plain, "20 kg of wood slows you down (%.2f)" % me.load_speed())
	me.set_wear({back = "backpack"})
	check(me.load_speed() == 1.0, "until you wear a backpack")
