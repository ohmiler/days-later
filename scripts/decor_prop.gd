class_name DecorProp
extends Node2D
## Non-interactive dressing inside a shop or home: plastic chairs, a noodle
## pot, tyres, a fan, a spirit house, litter, a hanging bulb... Origin is the
## bottom of its cell so upright things y-sort with characters.

var data: Dictionary  # {kind, cell, seed}


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed
	match data.kind:
		"chairs":
			_shadow(8)
			draw_rect(Rect2(-6, -8, 12, 2), Color("d84a3a"))  # folding table top
			draw_rect(Rect2(-5, -6, 1, 6), Color("8a8a8a"))
			draw_rect(Rect2(4, -6, 1, 6), Color("8a8a8a"))
			for x in [-9.0, 7.0]:  # red plastic stools
				draw_rect(Rect2(x, -5, 3, 1.5), Color("c83a2e"))
				draw_rect(Rect2(x + 0.5, -3.5, 2, 3.5), Color("a82e24"))
			draw_circle(Vector2(-2, -9), 1.2, Color("e8e2d4"))  # bowls
			draw_circle(Vector2(2, -9), 1.2, Color("e8e2d4"))
		"pot":
			_shadow(6)
			draw_rect(Rect2(-4, -5, 8, 5), Color("5a5a5a"))  # gas ring stand
			draw_rect(Rect2(-5, -11, 10, 6), Color("b8bcc0"))
			draw_rect(Rect2(-5, -11, 10, 1.5), Color("d8dce0"))
			draw_rect(Rect2(-6, -12, 12, 1), Color("8a8e92"))
		"tires":
			_shadow(7)
			for i in 3:
				var y := -2.0 - i * 2.6
				draw_set_transform(Vector2(0, y), 0, Vector2(1, 0.45))
				draw_circle(Vector2.ZERO, 6, Color("1e1e1e"))
				draw_circle(Vector2.ZERO, 3, Color("3a3a3a"))
			draw_set_transform(Vector2.ZERO)
		"bike":
			_shadow(8)
			draw_circle(Vector2(-5, -2.5), 2.5, Color("1a1a1a"))
			draw_line(Vector2(-5, -3), Vector2(3, -7), Color("6a2a24"), 2.0)  # frame on a stand, back wheel off
			draw_rect(Rect2(-3, -9, 6, 1.5), Color("1e1e1e"))
			draw_rect(Rect2(3, -3, 4, 3), Color("7a7a7a"))  # engine block
		"oil":
			draw_set_transform(Vector2(0, -3), 0, Vector2(1.4, 0.5))
			draw_circle(Vector2.ZERO, 5, Color(0.05, 0.05, 0.08, 0.5))
			draw_set_transform(Vector2.ZERO)
		"boxes":
			_shadow(7)
			draw_rect(Rect2(-6, -6, 7, 6), Color("b89a6a"))
			draw_rect(Rect2(0, -5, 6, 5), Color("a88a5a"))
			draw_rect(Rect2(-4, -11, 7, 5), Color("c8aa7a"))
			draw_line(Vector2(-4, -8.5), Vector2(3, -8.5), Color("8a7040"), 0.6)  # tape
		"mattress":
			# A thin floor mattress, a person's length (it lies over the next cell).
			draw_rect(Rect2(-13, -9, 27, 7), Color("8a9ab0"))
			draw_rect(Rect2(-13, -2, 27, 2), Color("6a7a90"))
			draw_rect(Rect2(-12, -8, 5, 5), Color("e8e4dc"))  # pillow
		"fan":
			_shadow(4)
			draw_line(Vector2(0, 0), Vector2(0, -9), Color("dcdcd4"), 1.2)
			draw_circle(Vector2(0, -12), 3.8, Color("7ab0d0"))
			draw_circle(Vector2(0, -12), 1.2, Color("e8e8e0"))
			draw_rect(Rect2(-3, -1, 6, 1.5), Color("dcdcd4"))
		"tv":
			_shadow(6)
			draw_rect(Rect2(-6, -5, 12, 5), Color("6a4a30"))  # low cabinet
			draw_rect(Rect2(-4.5, -12, 9, 7), Color("2a2a2c"))  # old tube TV
			draw_rect(Rect2(-3.5, -11, 6, 5), Color("3a4450"))
		"shrine":
			# A small spirit house on a post, garlands and a red strawberry soda offering.
			_shadow(4)
			draw_rect(Rect2(-0.8, -8, 1.6, 8), Color("c8a878"))
			draw_rect(Rect2(-4, -13, 8, 5), Color("d8b04a"))
			draw_colored_polygon(PackedVector2Array([Vector2(-5, -13), Vector2(5, -13), Vector2(0, -18)]), Color("c83a2e"))
			draw_circle(Vector2(-2.5, -8), 0.9, Color("f0d060"))
			draw_rect(Rect2(1.5, -9.5, 1.2, 2), Color("e03a4a"))
		"litter":
			for i in 5:
				var p := Vector2(rng.randf_range(-7, 7), rng.randf_range(-6, 0))
				draw_rect(Rect2(p, Vector2(rng.randf_range(1.5, 3), 1.2)), Color.from_hsv(rng.randf(), 0.3, rng.randf_range(0.5, 0.9)))
		"stairs":
			# Concrete steps climbing to a hatch in the ceiling.
			_shadow(7)
			for i in 5:
				var y := -2.0 - i * 3.0
				draw_rect(Rect2(-6 + i * 1.5, y - 2.5, 11 - i * 1.5, 3), Color("9a968e").darkened(i * 0.06))
				draw_rect(Rect2(-6 + i * 1.5, y - 2.5, 11 - i * 1.5, 0.8), Color("b8b4ac"))
			draw_line(Vector2(6, -1), Vector2(6, -17), Color("5a5a5a"), 0.8)  # handrail
			draw_rect(Rect2(-2, -21, 8, 3), Color("2a2622"))  # the hatch above
		"bulb":
			draw_line(Vector2(0, -40), Vector2(0, -24), Color("1e1e1e"), 0.5)  # hanging from the ceiling
			draw_circle(Vector2(0, -23), 1.6, Color("f0e0a0"))
		"barberchair":
			# A barber's chair: chrome pedestal, red leather, a headrest.
			_shadow(6)
			var red := Color("a82a24")
			var chrome := Color("c8ccd0")
			draw_rect(Rect2(-3, -1.5, 6, 1.5), chrome)
			draw_rect(Rect2(-0.8, -5, 1.6, 4), chrome)
			draw_rect(Rect2(-5, -9, 10, 4), red)
			draw_rect(Rect2(-4.5, -18, 9, 9), red.darkened(0.15))
			draw_rect(Rect2(-2.5, -21, 5, 3), red.darkened(0.25))
			draw_rect(Rect2(-6, -10, 1.5, 4), chrome)
			draw_rect(Rect2(4.5, -10, 1.5, 4), chrome)
			draw_rect(Rect2(-3, -4, 6, 1), chrome)  # foot plate
			var sign: String = data.building.get("sign", "") if data.get("building") else ""
			if sign == "ร้านเสริมสวย":  # a salon: the hood dryer over it
				draw_arc(Vector2(0, -21), 5.0, PI, TAU, 8, Color("e8e4dc"), 2.5)
				draw_line(Vector2(5, -21), Vector2(6, -10), chrome, 0.8)
		"stove":
			# A two-ring gas stove on a low stand, the red LPG tank beside it.
			_shadow(7)
			draw_rect(Rect2(-7, -8, 10, 8), Color("7a7a76"))
			draw_rect(Rect2(-7, -9.5, 10, 2), Color("2a2a2a"))
			draw_circle(Vector2(-4.5, -9), 1.4, Color("4a4a4a"))
			draw_circle(Vector2(0.5, -9), 1.4, Color("4a4a4a"))
			draw_circle(Vector2(0.5, -11), 2.4, Color("3a3a3c"))  # a wok on it
			draw_rect(Rect2(4, -9, 4.5, 9), Color("c83a2e"))
			draw_rect(Rect2(4, -9, 4.5, 1), Color("e05a4a"))
			draw_rect(Rect2(5.5, -11, 1.5, 2), Color("8a8a8a"))
			draw_line(Vector2(6, -11), Vector2(2, -8), Color("e0a040"), 0.5)  # the hose
		"jar":
			# A glazed dragon jar of water with a plastic dipper on the lid.
			_shadow(6)
			draw_set_transform(Vector2(0, -6), 0, Vector2(1, 1.05))
			draw_circle(Vector2.ZERO, 6, Color("6a3a22"))
			draw_set_transform(Vector2.ZERO)
			draw_rect(Rect2(-4.5, -13, 9, 2), Color("4a2816"))
			draw_arc(Vector2(0, -6), 4.0, 2.4, 4.4, 6, Color("d8b040"), 0.8)  # the dragon
			draw_arc(Vector2(1, -5), 3.0, -0.6, 1.2, 6, Color("d8b040"), 0.8)
			draw_circle(Vector2(1.5, -14), 1.8, Color("e070a0"))
			draw_line(Vector2(3, -14), Vector2(5.5, -15), Color("e070a0"), 0.6)
		"toilet":
			# A squat toilet in a tiled floor, a bucket and dipper beside it.
			draw_rect(Rect2(-6, -8, 12, 8), Color("a8c0c8"))
			draw_set_transform(Vector2(-1, -4), 0, Vector2(1, 0.6))
			draw_circle(Vector2.ZERO, 3.5, Color("f0f0ec"))
			draw_circle(Vector2(0, -0.5), 2.0, Color("c8d8dc"))
			draw_set_transform(Vector2.ZERO)
			draw_rect(Rect2(3, -5, 3, 4), Color("3a7ac8"))
		"sofa":
			# A carved wooden living-room bench with cushions.
			_shadow(8)
			var wood := Color("7a4a2a")
			draw_rect(Rect2(-8, -15, 16, 8), wood.darkened(0.1))
			draw_rect(Rect2(-8, -8, 16, 3), wood)
			draw_rect(Rect2(-8, -5, 1.5, 5), wood.darkened(0.2))
			draw_rect(Rect2(6.5, -5, 1.5, 5), wood.darkened(0.2))
			draw_rect(Rect2(-6.5, -10, 5.5, 2.5), Color("c8a040"))
			draw_rect(Rect2(1, -10, 5.5, 2.5), Color("b83a2e"))
		"altar":
			# A Chinese family altar: red cabinet, gods behind glass, candles, incense.
			_shadow(7)
			draw_rect(Rect2(-7, -9, 14, 9), Color("8a1a14"))
			draw_rect(Rect2(-7, -10, 14, 1.5), Color("c83a2e"))
			draw_rect(Rect2(-5, -19, 10, 9), Color("a81e18"))
			draw_rect(Rect2(-3.5, -17.5, 7, 6), Color("f0c840"))
			draw_circle(Vector2(0, -15), 1.5, Color("e8d8a0"))
			for x in [-6.0, 5.5]:
				draw_rect(Rect2(x, -13, 1, 3), Color("e82a2a"))
				draw_circle(Vector2(x + 0.5, -13.5), 0.5, Color("f0d060"))
			draw_line(Vector2(0, -10), Vector2(0.5, -13), Color("6a4a30"), 0.3)
		"sacks":
			# Sacks of rice and cement stacked on a pallet.
			_shadow(8)
			draw_rect(Rect2(-8, -2, 16, 2), Color("9a7a52"))
			for i in 3:
				var r := Rect2(-7 + (i % 2) * 3.0, -6.5 - i * 4, 11, 4.5)
				draw_rect(r, Color("e8e4dc") if i != 1 else Color("b8b4ac"))
				draw_rect(Rect2(r.position + Vector2(3, 1.2), Vector2(4, 1.5)), Color("2a6ab8") if i != 1 else Color("5a5a5a"))
		"mannequin":
			_shadow(4)
			draw_line(Vector2(0, 0), Vector2(0, -8), Color("5a5a5a"), 0.8)
			draw_rect(Rect2(-2.5, -1, 5, 1), Color("5a5a5a"))
			draw_colored_polygon(PackedVector2Array([Vector2(-3.5, -20), Vector2(3.5, -20), Vector2(2.5, -9), Vector2(-2.5, -9)]),
					Color.from_hsv(rng.randf(), 0.6, 0.7))  # a silk dress on it
			draw_rect(Rect2(-1, -22, 2, 2), Color("e8dcc8"))
		"recliner":
			# A foot-massage armchair with its stool.
			_shadow(7)
			var lea := Color("6a3a22")
			draw_rect(Rect2(-5, -9, 9, 4), lea)
			draw_colored_polygon(PackedVector2Array([Vector2(-5, -9), Vector2(-7, -18), Vector2(-3, -18), Vector2(-1, -9)]), lea.darkened(0.15))
			draw_rect(Rect2(-6, -5, 11, 5), lea.darkened(0.25))
			draw_rect(Rect2(5, -5, 3.5, 4), lea.lightened(0.1))
			draw_rect(Rect2(-4, -9.5, 7, 1.5), Color("e8e4dc"))  # a towel
		"examcot":
			# A clinic's examination couch: steel frame, vinyl, a strip of paper.
			_shadow(8)
			draw_rect(Rect2(-8, -9, 16, 3), Color("3a8a8a"))
			draw_rect(Rect2(-8, -11, 5, 2), Color("3a8a8a").darkened(0.15))
			draw_rect(Rect2(-3, -9.5, 8, 1), Color("f0ece4"))
			for x in [-7.0, 6.0]:
				draw_rect(Rect2(x, -6, 1, 6), Color("c8ccd0"))
		"washbasin":
			# A salon's backwash basin: a reclining chair tipped back to the sink.
			_shadow(7)
			draw_rect(Rect2(-7, -8, 9, 3.5), Color("2a2a2c"))
			draw_colored_polygon(PackedVector2Array([Vector2(-7, -8), Vector2(-3, -8), Vector2(0, -13), Vector2(-3, -14)]), Color("3a3a3c"))
			draw_rect(Rect2(0, -14, 7, 5), Color("f0f0ec"))
			draw_rect(Rect2(1, -13.5, 5, 2), Color("c8d8dc"))
			draw_line(Vector2(5, -14), Vector2(5, -17), Color("c8ccd0"), 0.7)
			draw_rect(Rect2(-6, -4.5, 7, 4.5), Color("1a1a1c"))
		"bench":
			# A waiting bench and a stack of old newspapers.
			_shadow(8)
			draw_rect(Rect2(-8, -7, 16, 2.5), Color("3a6ac8"))
			draw_rect(Rect2(-8, -13, 16, 5), Color("3a6ac8").darkened(0.15))
			for x in [-7.0, 6.0]:
				draw_rect(Rect2(x, -4.5, 1, 4.5), Color("8a8a8a"))
			draw_rect(Rect2(2, -9, 4, 2), Color("d8d4c8"))
		"curtain":
			# A curtain hung on a rail, half drawn (between massage mattresses).
			draw_line(Vector2(-8, -28), Vector2(8, -28), Color("8a8a8a"), 0.6)
			var col := Color.from_hsv(rng.randf_range(0.0, 0.12), 0.55, 0.6)
			for i in 4:
				draw_rect(Rect2(-8 + i * 2.2, -28, 2.0, 26), col.darkened(0.08 * (i % 2)))
		"shoes":
			# Shoes and slippers left at the door, as everyone does.
			for i in 5:
				var p := Vector2(rng.randf_range(-6, 5), rng.randf_range(-6, -1))
				draw_rect(Rect2(p, Vector2(2.5, 1.2)), Color.from_hsv(rng.randf(), 0.4, rng.randf_range(0.3, 0.8)))
		"lightbox":
			# A lit sign box standing on the pavement, in the colours of its trade.
			var sign: String = data.building.get("sign", "") if data.get("building") else ""
			var col: Color = {"ร้านขายยา": Color("1a9a4a"), "คลินิก": Color("2a6ab8"), "ร้านโทรศัพท์": Color("e0402a"),
					"นวดแผนไทย": Color("c8508a"), "ร้านเสริมสวย": Color("d86aa8"), "ร้านตัดผม": Color("2a4ab8")}.get(sign, Color("d8a030"))
			_shadow(4)
			draw_rect(Rect2(-0.6, -5, 1.2, 5), Color("5a5a5a"))
			draw_rect(Rect2(-4, -15, 8, 10), Color("f0ece4"))
			draw_rect(Rect2(-4, -15, 8, 2.5), col)
			draw_rect(Rect2(-4, -15, 8, 10), col.darkened(0.3), false, 0.5)
			match sign:
				"ร้านขายยา", "คลินิก":
					draw_rect(Rect2(-2.5, -10.5, 5, 1.6), col)
					draw_rect(Rect2(-0.8, -12.2, 1.6, 5), col)
				"ร้านโทรศัพท์":
					draw_rect(Rect2(-1.5, -11.5, 3, 5.5), Color("2a2c30"))
					draw_rect(Rect2(-1, -11, 2, 4), Color("5a8ab8"))
				"นวดแผนไทย":  # a foot
					draw_set_transform(Vector2(0, -9), 0.3, Vector2(0.7, 1.2))
					draw_circle(Vector2.ZERO, 2.0, col)
					draw_set_transform(Vector2.ZERO)
				_:  # scissors
					draw_line(Vector2(-2, -11), Vector2(2, -7), col, 0.6)
					draw_line(Vector2(2, -11), Vector2(-2, -7), col, 0.6)
					draw_circle(Vector2(-2, -6.5), 0.8, col)
					draw_circle(Vector2(2, -6.5), 0.8, col)
		"flag":
			# A tall feather flag on a pole, the kind every shop opening puts out.
			var fc := Color.from_hsv(rng.randf(), 0.8, 0.85)
			draw_rect(Rect2(-2, -1, 4, 1), Color("3a3a3a"))
			draw_line(Vector2(-1, 0), Vector2(-1, -30), Color("c8ccd0"), 0.6)
			draw_colored_polygon(PackedVector2Array([Vector2(-1, -30), Vector2(3, -29), Vector2(4, -14), Vector2(-1, -10)]), fc)
			for i in 3:
				draw_rect(Rect2(0.3, -26 + i * 4, 2.2, 1.2), Color(1, 1, 1, 0.8))
		"menu":
			# A sandwich board with the day's dishes chalked up.
			_shadow(4)
			draw_colored_polygon(PackedVector2Array([Vector2(-3.5, 0), Vector2(-2.5, -11), Vector2(2.5, -11), Vector2(3.5, 0)]), Color("6a4a30"))
			draw_rect(Rect2(-2.2, -10, 4.4, 8), Color("2a3a2e"))
			for i in 4:
				draw_line(Vector2(-1.6, -8.5 + i * 2), Vector2(rng.randf_range(0, 1.6), -8.5 + i * 2), Color(1, 1, 1, 0.7), 0.5)
		"grill":
			# A charcoal grill with chicken on bamboo sticks.
			_shadow(6)
			draw_rect(Rect2(-6, -6, 12, 4), Color("3a3a3a"))
			draw_rect(Rect2(-5, -2, 1, 2), Color("3a3a3a"))
			draw_rect(Rect2(4, -2, 1, 2), Color("3a3a3a"))
			draw_rect(Rect2(-5.5, -6.5, 11, 1), Color("e05a2a"))  # the coals glowing
			for i in 4:
				draw_line(Vector2(-4.5 + i * 3, -7), Vector2(-3 + i * 3, -11), Color("c8a878"), 0.4)
				draw_circle(Vector2(-3.8 + i * 3, -8.8), 1.0, Color("a8502a"))
			draw_line(Vector2(0, -12), Vector2(1, -18), Color(0.8, 0.8, 0.8, 0.35), 1.5)  # smoke
		"pipes":
			# Lengths of PVC pipe leaning on the wall.
			for i in 4:
				var x := -5.0 + i * 2.5
				draw_line(Vector2(x, 0), Vector2(x + 2, -20), Color("4a7ac8") if i % 2 else Color("e8e4dc"), 1.3)
		"plants":
			# Pots of plants by the door: a bougainvillea, a mother-in-law's tongue.
			_shadow(5)
			for i in 2:
				var x := -3.0 + i * 6.0
				draw_rect(Rect2(x - 2.5, -4, 5, 4), Color("a8583a"))
				for k in 4:
					draw_circle(Vector2(x + rng.randf_range(-2.5, 2.5), -5.5 - rng.randf() * 4), 1.6, Color("4a8a3a").darkened(rng.randf() * 0.3))
				if i == 0:
					for k in 3:
						draw_circle(Vector2(x + rng.randf_range(-2, 2), -7 - rng.randf() * 3), 0.9, Color("e04a9a"))
		"hiphra":
			# A Buddha shelf high on the wall: gold images, a garland, a flower vase.
			draw_rect(Rect2(-7, -33, 14, 1.5), Color("8a5a2a"))
			draw_line(Vector2(-6, -31.5), Vector2(-4, -29), Color("6a4a2a"), 0.6)
			draw_line(Vector2(6, -31.5), Vector2(4, -29), Color("6a4a2a"), 0.6)
			for x in [-3.5, 0.0, 3.5]:
				draw_rect(Rect2(x - 0.8, -37, 1.6, 4), Color("d8b040"))
				draw_circle(Vector2(x, -37.5), 0.8, Color("d8b040"))
			draw_arc(Vector2(0, -34), 5.5, 0.2, PI - 0.2, 8, Color("f0ece0"), 0.8)  # jasmine garland
			draw_rect(Rect2(5.5, -35.5, 1, 2.5), Color("e05a8a"))


func _shadow(r: float) -> void:
	draw_set_transform(Vector2(0, -0.5), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO)
