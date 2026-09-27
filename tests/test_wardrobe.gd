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
	SaveGame.wipe()
	await close_game()
