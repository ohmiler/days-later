extends "res://tests/test_base.gd"
## The police station (BigPlans "police"): a walled compound in Victory
## Monument with an armoury, cells, lockers and dorms; the only place guns and
## ammo turn up (tier 4); the chief is its boss and carries the riot gun.


func run() -> void:
	await host(9383, false, true, 11)
	var w: World = main.world
	var stations := w.buildings.filter(func(b): return b.kind == "police")
	check(not stations.is_empty(), "the zone has a police station (%d)" % stations.size())
	if stations.is_empty():
		return
	var rec: Dictionary = stations[0]
	check(rec.floors >= 2 and rec.sign.begins_with("สถานีตำรวจ"), "two or more floors and its sign (%s)" % rec.sign)
	var tables := {}
	var mine := 0
	for ct in w.containers:
		if rec.rect.has_point(ct.cell):
			mine += 1
			tables[ct.get("table", "")] = tables.get(ct.get("table", ""), 0) + 1
	check(mine >= 15, "it is full of cupboards (%d)" % mine)
	check(tables.get("police", 0) >= 5, "an armoury and lockers hold police things (%s)" % [tables])
	check(Items.tier_of("police", "police") == 4 and Items.tier_of("home", "police") == 4, "all of it is the most dangerous ground")
	# Guns and ammo come from here and nowhere else.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var guns := 0
	var elsewhere := 0
	for i in 400:
		for f in Items.roll("police", "shelf", rng, 4):
			if Items.DEFS[f].type in ["gun", "ammo"]:
				guns += 1
		for f in Items.roll("home", "shelf", rng, 1):
			if Items.DEFS[f].type in ["gun", "ammo"]:
				elsewhere += 1
	check(guns > 20 and guns < 400, "now and then a gun or a magazine (%d in 400 searches)" % guns)
	check(elsewhere == 0, "never in a home")
	# Its boss lives here.
	check(Bosses.lair(w, "chief") >= 0 and w.buildings[Bosses.lair(w, "chief")].kind == "police", "the chief's lair is the police station")
	var chief: Dictionary = Bosses.DEFS["chief"]
	check(chief.drops.has("riotgun") and Items.DEFS.has("riotgun") and Items.DEFS.riotgun.type == "gun", "it carries the riot gun")
	check(Items.DEFS.riotgun.noise > Items.DEFS.shotgun.noise and Items.DEFS.riotgun.weight > Items.DEFS.shotgun.weight,
			"which is louder and heavier than the shotgun (its price)")
	# Zombies there dress for it.
	check(Items.ZOMBIE_PLACES.has("police") and Items.DRESS.has("police"), "the dead there are in uniform")
