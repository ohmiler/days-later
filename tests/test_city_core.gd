extends "res://tests/test_base.gd"
## The city core: one way for the dead to sense things (sounds and smells,
## covered by the rain, carrying less through a floor); one way the world's
## changeable state is kept (WorldState); buildings that know their rooftop
## tank, filled by the rain as it falls.


func run() -> void:
	SaveGame.wipe()
	seed(19)
	await host(9531)
	main.spawn_timer = 1e9
	main.survival._set_rain(false)
	main.survival.rain_t = 1e9
	var w: World = main.world

	# A smell: a zombie close enough goes to look, and keeps looking longer than for a bang.
	var z := zombie_at(me.position + Vector2(200, 0))
	z.target = null
	var at := me.position + Vector2(260, 0)
	main.stimulus("smell", at, 100.0)
	check(z.investigate_t >= 17.0 and z.investigate.distance_to(at) < 20.0, "a smell brings it to look, a good while (%.0f s)" % z.investigate_t)
	z.investigate_t = 0.0
	main.stimulus("sound", at, 100.0)
	check(z.investigate_t > 0.0 and z.investigate_t < 17.0, "a sound, a shorter look")
	z.investigate_t = 0.0

	# The rain washes a smell away sooner than it covers a sound.
	main.survival._set_rain(true)
	main.stimulus("smell", at, 120.0)  # (60 px away: 120 * 0.4 = 48 doesn't reach)
	check(z.investigate_t == 0.0, "in the rain a smell doesn't carry as far")
	main.stimulus("sound", at, 120.0)  # (120 * 0.65 = 78: it does)
	check(z.investigate_t > 0.0, "but a sound still does")
	main.survival._set_rain(false)
	z.investigate_t = 0.0

	# Through a floor it carries half as far.
	main.stimulus("sound", at, 100.0, 1)
	check(z.investigate_t == 0.0, "a sound upstairs, 60 px off, doesn't reach one on the ground at 100 px (it carries 50)")
	main.stimulus("sound", at, 150.0, 1)
	check(z.investigate_t > 0.0, "a louder one does")
	z.investigate_t = 0.0

	# Bleeding, you leave a smell of blood.
	z.position = me.position + Vector2(60, 0)
	z.target = null
	me.bleeding = true
	me.scent_t = 0.0
	main.survival._tick_needs(me, 0.1)
	check(z.investigate_t > 0.0 and z.investigate.distance_to(me.position) < 20.0, "a bleeding survivor is smelt")
	me.bleeding = false

	# WorldState: only what differs from the start is kept; back to the start, it's forgotten.
	var bid: int = w.buildings.filter(func(b): return b.kind == "shop")[0].id  # (a shophouse's tank)
	var start: float = Buildings.start(w, bid).tank
	main.world_state.set_state("building", bid, {tank = start + 5.0, tank_at = main.rain_total})
	check(main.world_state.changed().get("building", {}).has(bid), "a changed building is kept")
	main.world_state.set_state("building", bid, {tank = start, tank_at = 0.0})
	check(not main.world_state.changed().get("building", {}).has(bid), "put back as it started, it's forgotten")

	# The rain fills the tanks as it falls (rain_total), on the server's clock.
	main.world_state.set_state("building", bid, {tank = 0.0, tank_at = main.rain_total})
	main.survival._set_rain(true)
	var before: float = main.rain_total
	simulate(Main.HOUR)
	check(main.rain_total - before >= Main.HOUR - 0.01, "the rain is added up as it falls (%.1f s)" % (main.rain_total - before))
	check(absf(Buildings.tank(main, bid) - Buildings.TANK_RAIN) < 0.5, "an hour of rain puts water in a tank (%.1f)" % Buildings.tank(main, bid))
	main.rain_total += 100.0 * Main.HOUR
	check(Buildings.tank(main, bid) == Buildings.TANK, "never more than it holds")
	main.survival._set_rain(false)

	# And it all survives a save.
	main.world_state.set_state("building", bid, {tank = 7.0, tank_at = main.rain_total})
	var rain: float = main.rain_total
	main._save_all()
	await close_game()
	await host(9531, true)
	check(absf(main.rain_total - rain) < 0.01, "how long it has rained is saved")
	check(absf(Buildings.tank(main, bid) - 7.0) < 0.01, "and so is a building's tank")
	SaveGame.wipe()
	await close_game()
