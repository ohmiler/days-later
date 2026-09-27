extends "res://tests/test_base.gd"
## The wardrobe: one item, many looks (colour, pattern, a printed slogan),
## kept by its key when worn and when taken off a body; the waist slot; what
## clothes do (rubber boots are loud, pale clothes and hi-vis show up in the
## dark, boxing gloves punch hard and hold nothing); the big buildings' own
## finds; zombies dressed for where they turned.


func run() -> void:
	# Looks: fixed by the number, varied across numbers.
	var a := Items.draw_of("tshirt#22")
	check(a == Items.draw_of("tshirt#22") and a.get("pattern", "") == "print" and a.get("print", "") != "",
			"a T-shirt's look comes from its number: #22 is printed (\"%s\")" % a.get("print", ""))
	var seen := {}
	for v in 300:
		var d := Items.draw_of("tshirt#%d" % v)
		seen["%s|%s" % [d.col, d.get("pattern", "")]] = true
	check(seen.size() > 30, "three hundred T-shirts come in many looks (%d)" % seen.size())
	check(Items.def("tshirt#5") == Items.def("tshirt") and Items.base_id("tshirt#5") == "tshirt", "a look's key reads as its item")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var made := Items.make("hawaii", rng)
	check(made.has("v") and Items.key(made) == "hawaii#%d" % made.v and not Items.plain(made), "one found gets a look of its own")
	check(not Items.make("water").has("v"), "things without looks don't")
	check(Items.from_key("hawaii#17", 5) == {id = "hawaii", n = 1, hp = 5, v = 17}, "taken off a body, it keeps its look")
	check(Items.state_text(Items.from_key("tshirt#22", 5), 0.0).contains("สกรีน"), "its card says what's printed on it")
	check("waist" in Items.SLOTS and Items.def("pakhaoma").slot == "waist", "a slot for the waist: a pha khao ma goes there")

	SaveGame.wipe()
	seed(31)
	await host(9534)
	main.spawn_timer = 1e9
	var w: World = main.world

	# Worn, everyone sees this one's look.
	me.worn.body = Items.from_key("tshirt#22", 10)
	me.refresh_wear()
	check(me.wear_ids.body == "tshirt#22" and me.look.wear.body.get("pattern", "") == "print", "worn, it's drawn with its own look")

	# Rubber boots are loud; flip-flops a bit; bare feet not.
	var quiet := me.wear_mult("noise")
	me.worn.feet = Items.make("rubberboots")
	me.refresh_wear()
	check(me.wear_mult("noise") > quiet * 1.3, "rubber boots make your steps louder")

	# In the dark: a white shirt shows further than black; hi-vis further still.
	me.worn.body = Items.from_key("tanktop#0", 6)  # (white)
	me.refresh_wear()
	var pale := me.seen_in_dark()
	me.worn.body = Items.from_key("tanktop#2", 6)  # (black)
	me.refresh_wear()
	var dark := me.seen_in_dark()
	me.worn.over = Items.make("hivis")
	me.refresh_wear()
	check(pale > dark and me.seen_in_dark() > dark * 1.3, "pale clothes show in the dark more than dark ones, hi-vis most (%.2f / %.2f / %.2f)" % [pale, dark, me.seen_in_dark()])
	me.worn.erase("over")

	# Boxing gloves: a harder punch, and no weapon in hand.
	var bare: float = Combat.next_swing(me).stats[1]
	me.worn.hands = Items.make("boxing")
	me.refresh_wear()
	check(Combat.next_swing(me).stats[1] > bare * 1.5, "boxing gloves punch harder")
	main.inventory._give(me, "bat")
	var slot := me.inv.find(me.inv.filter(func(it): return it != null and it.id == "bat")[0])
	main.inventory._move_as(me, ["inv", slot], ["worn", "hand_r"])
	check(me.worn.get("hand_r") == null, "with boxing gloves on you can't take up a bat")
	me.worn.erase("hands")
	me.refresh_wear()

	# The big buildings turn up their own things.
	check(Items.place_in("med", "hospital") == "hospital" and Items.LOOT.hospital.any(func(e): return e[0] == "scrubs") \
			and Items.LOOT.hospital.any(func(e): return e[0] == "bandage"), "a hospital's cupboards: what a pharmacy has, and scrubs")
	check(Items.place_in("home", "office") == "office" and Items.LOOT.office.any(func(e): return e[0] == "office_shirt"), "an office's: shirts and ties")

	# Zombies dress for where they turned.
	var hosp: Dictionary = w.buildings.filter(func(b): return b.kind == "hospital")[0]
	var at := w.to_pos(hosp.rect.get_center())
	var zid: int = main.new_zid(at)
	check(Items.ZOMBIE_PLACES[zid % 8] == "hospital", "a zombie that turned in a hospital is known as one (%d)" % zid)
	var scrubs := 0
	for i in 40:
		var wear := Items.zombie_wear(main.new_zid(at))
		if Items.base_id(wear.get("body", "")) == "scrubs" or wear.has("over"):
			scrubs += 1
	check(scrubs > 20, "most in a hospital wear scrubs or a white coat (%d/40)" % scrubs)
	check(Items.zombie_wear(zid) == Items.zombie_wear(zid), "and the same on every machine")

	# A pha khao ma tears into bandages.
	check(Crafting.RECIPES.has("bandage_pakhaoma"), "a pha khao ma tears into bandages")

	# --- Round 2 ---
	# A life jacket: the canal can be swum (slowly); without one, it can't; zombies never.
	var wc := Vector2i(-1, -1)
	for y in range(1, World.H - 1):
		if w.get_tile(Vector2i(60, y)) == World.WATER and w.get_tile(Vector2i(60, y - 1)) != World.WATER:
			wc = Vector2i(60, y)
			break
	check(wc.x >= 0, "a canal to swim")
	var bank := w.to_pos(wc + Vector2i.UP)
	me.worn = {}
	me.refresh_wear()
	me.position = bank
	for i in 60:
		me.position = w.slide(me.position, Vector2(0, 1.0), Player.RADIUS, false, false, 0, me.floats())
	check(not me.swimming(), "without a life jacket you can't go in the canal")
	me.worn.over = Items.make("lifejacket")
	me.refresh_wear()
	for i in 60:
		me.position = w.slide(me.position, Vector2(0, 1.0), Player.RADIUS, false, false, 0, me.floats())
	check(me.swimming() and me.speed_mult() < 0.5, "in a life jacket you swim out into it, slowly (%.2f)" % me.speed_mult())
	var zb := zombie_at(bank)
	for i in 60:
		zb.position = w.slide(zb.position, Vector2(0, 1.0), Zombie.RADIUS)
	check(w.get_tile(w.to_cell(zb.position)) != World.WATER, "a zombie can't follow you in")
	main.zombies.erase(zb.zid)
	zb.queue_free()
	main.survival._tick_wet(me)
	check(me.conditions.has("wet"), "in the canal you get soaked")
	var dry_kg := 0.0
	me.conditions.erase("wet")
	me.worn = {body = Items.make("jeans")}
	me.worn.body = Items.make("hoodie")
	me.worn.legs = Items.make("jeans")
	me.refresh_wear()
	me.position = w.to_pos(w.spawn_cell)
	dry_kg = me.load_kg()
	main.survival._set_rain(true)
	main.survival._tick_wet(me)
	check(me.conditions.has("wet") and me.load_kg() > dry_kg + 0.5, "out in the rain you're soaked: jeans and a hoodie get heavy (%.1f -> %.1f kg)" % [dry_kg, me.load_kg()])
	me.conditions.erase("wet")
	me.worn.over = Items.make("raincoat")
	me.refresh_wear()
	main.survival._tick_wet(me)
	check(not me.conditions.has("wet"), "a raincoat keeps it off")
	main.survival._set_rain(false)

	# A headlamp lights the night (zombies see you by it) and runs down.
	me.worn = {head = Items.make("headlamp")}
	me.refresh_wear()
	w.is_night = true
	check(me.lamp_lit(), "a headlamp on at night")
	me.worn.head.hp = 0.5
	main.survival._tick_lamp(me, 1.0)
	check(me.worn.head.id == "headlamp_off" and not me.lamp_lit(), "its batteries run flat: dark")
	check(Crafting.RECIPES.headlamp.needs.has("battery"), "new batteries in it: a recipe")
	w.is_night = false

	# A mirror on the helmet: a glimpse of what's behind.
	var sg := Sight.new()
	sg.world = w
	me.aim = Vector2(1, 0)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if w.sight_ray(me.position + Vector2(0, -2), -d, 90.0)[0] >= 90.0:
			me.aim = d  # (facing so that the way behind is open)
			break
	me.worn = {}
	me.refresh_wear()
	sg.update(me, 1.0, 400.0)
	sg.on = 1.0
	var behind := me.position - me.aim * 80.0
	var saw := sg.sees(behind)
	me.worn.head = Items.make("mirrorhelmet")
	me.refresh_wear()
	sg.update(me, 1.0, 400.0)
	sg.on = 1.0
	check(not saw and sg.sees(behind), "with the mirror you see a way behind you")

	# Heels: slower; a skirt: bare legs below it.
	me.worn = {feet = Items.make("heels"), legs = Items.make("skirt")}
	me.refresh_wear()
	check(me.speed_mult() < 0.95 and me.wear_mult("noise") > 1.2, "heels: slower, and loud")
	check(Look._dress(me.look, false).shorts, "a skirt: bare legs below it")

	# --- Round 3: the strange ones ---
	# A mascot costume: thick fur, hot, and you see out of it poorly.
	me.worn = {over = Items.make("mascot_durian")}
	me.refresh_wear()
	sg.update(me, 1.0, 400.0)
	check(me.guard("torso") >= 0.5 and me.heat() >= 0.8 and sg.cone < Sight.CONE * 0.7, "a mascot suit: bites don't get through, it's hot, you see less")
	# The blow-up dinosaur keeps off a bite or three, then it's gone.
	me.worn = {over = Items.make("dinosuit")}
	me.refresh_wear()
	for i in 4:
		me.hp = 100.0
		me.bite(10.0, "torso")
	check(not me.worn.has("over"), "the blow-up dinosaur pops after a few bites")
	# A pot on the head: bitten there, it rings.
	me.worn = {head = Items.make("pothelm")}
	me.refresh_wear()
	var zp := zombie_at(me.position + Vector2(160, 0))
	zp.target = null
	zp.investigate_t = 0.0
	me.bite(5.0, "head")
	check(zp.investigate_t > 0.0, "a bite on a pot helmet rings out: a zombie a way off comes to see")
	main.zombies.erase(zp.zid)
	zp.queue_free()
	check(Crafting.RECIPES.has("pothelm"), "a pot and tape make a pot helmet")
	# A mongkol: breath back quicker (you believe in it).
	me.worn = {head = Items.make("mongkol")}
	me.refresh_wear()
	check(me.wear_mult("stamina") > 1.05, "a mongkol: breath back quicker")
	# A duck ring floats you too.
	me.worn = {waist = Items.make("swimring")}
	me.refresh_wear()
	check(me.floats(), "a duck swim ring floats you")
	# Now and then a zombie in a costume, and it comes off whole.
	var specials := 0
	for mz in range(4, 8000, 8):  # (from the mall)
		var wr := Items.zombie_wear(mz)
		if wr.values().any(func(k): return Items.def(k).get("special", false)):
			specials += 1
	check(specials > 5 and specials < 60, "one mall zombie in a hundred or so is still in a costume (%d/1000)" % specials)
	var zc := zombie_at(me.position + Vector2(40, 0))
	zc._set_wear({over = "mascot_elephant"})
	main.combat._kill_zombie(zc, 1.0)
	check(main.pickups.values().any(func(pu): return pu.item.id == "mascot_elephant"), "killed, the costume always comes off")
	SaveGame.wipe()
	await close_game()
