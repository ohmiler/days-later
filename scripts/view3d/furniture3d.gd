class_name Furniture3D
extends RefCounted
## Furniture and the small things of Thai homes and shops, in 3D from code:
## what the city generator puts in each room (World.containers, World.decor,
## World.things). Each is made in a one-metre cell's space: the floor at y 0,
## its back against a wall at -Z (City3D turns it to the nearest wall), the
## front at +Z, across along X.

const WOOD := Color("8a6444")
const DARK_WOOD := Color("5a3e2c")
const STEEL := Color("9aa0a6")
const WHITE := Color("e8e4dc")
const PLASTIC_RED := Color("c83a30")
const PLASTIC_BLUE := Color("2a62a8")


static func _b(st: SurfaceTool, xf: Transform3D, c: Vector3, s: Vector3, col: Color) -> void:
	Props3D.xbox(st, xf, c, s, col)


static func _c(st: SurfaceTool, xf: Transform3D, c: Vector3, r: float, len: float, axis: int, col: Color, sides := 10, r2 := -1.0) -> void:
	Props3D.xcyl(st, xf, c, r, len, axis, col, sides, r2)


## Four legs under a top w x d at height h.
static func _legs(st: SurfaceTool, xf: Transform3D, w: float, d: float, h: float, col: Color, t := 0.04, z0 := 0.0) -> void:
	for x in [w * 0.5 - t, -w * 0.5 + t]:
		for z in [d * 0.5 - t, -d * 0.5 + t]:
			_b(st, xf, Vector3(x, h * 0.5, z + z0), Vector3(t, h, t), col)


static func _goods(st: SurfaceTool, xf: Transform3D, y: float, w: float, z: float, seed: int, n := 6) -> void:
	for i in n:
		var k := fmod(seed * 0.618 + i * 0.37, 1.0)
		var h := 0.12 + k * 0.16
		_b(st, xf, Vector3(-w * 0.5 + (i + 0.5) * w / n, y + h * 0.5, z), Vector3(w / n * 0.8, h, 0.22), Color.from_hsv(k, 0.55, 0.85))


## Build `kind` at `xf`. `shop`: the kind of place it's in (a building's kind),
## `seed`: for its colours. `long`: a bed two cells long runs 2 m along +Z.
static func build(st: SurfaceTool, xf: Transform3D, kind: String, seed: int, shop: String, long := false) -> void:
	match kind:
		# --- Containers (you search them) ---
		"crate":
			_b(st, xf, Vector3(0, 0.3, -0.1), Vector3(0.7, 0.6, 0.6), Color("a07a4a"))
			for y in [0.15, 0.45]:
				_b(st, xf, Vector3(0, y, 0.205), Vector3(0.72, 0.06, 0.02), Color("7a5a36"))
		"shelf":
			for x in [0.46, -0.46]:
				_b(st, xf, Vector3(x, 0.9, -0.28), Vector3(0.04, 1.8, 0.4), STEEL)
			for i in 4:
				var y := 0.1 + i * 0.52
				_b(st, xf, Vector3(0, y, -0.28), Vector3(0.95, 0.03, 0.4), STEEL.lightened(0.1))
				_goods(st, xf, y + 0.015, 0.88, -0.28, seed + i)
		"cabinet", "pantry":
			var col := WOOD if kind == "cabinet" else DARK_WOOD
			_b(st, xf, Vector3(0, 0.92, -0.25), Vector3(0.9, 1.84, 0.48), col)
			_b(st, xf, Vector3(0, 0.92, 0.0), Vector3(0.012, 1.76, 0.01), col.darkened(0.4))
			for x in [0.06, -0.06]:
				_b(st, xf, Vector3(x, 1.0, 0.01), Vector3(0.02, 0.14, 0.02), STEEL)
		"table":
			_b(st, xf, Vector3(0, 0.74, 0), Vector3(0.95, 0.03, 0.75), WOOD.lightened(0.1) if seed % 2 else Color("d8d0c0"))
			_legs(st, xf, 0.95, 0.75, 0.73, DARK_WOOD if seed % 2 else STEEL)
			# Plastic stools round it, red or blue.
			for i in 2:
				var sc := PLASTIC_RED if (seed + i) % 2 else PLASTIC_BLUE
				_c(st, xf, Vector3(-0.3 + i * 0.6, 0.22, 0.55), 0.14, 0.44, 1, sc, 8, 0.12)
		"sink":
			_b(st, xf, Vector3(0, 0.42, -0.2), Vector3(0.9, 0.84, 0.58), Color("c8c2b8"))
			_b(st, xf, Vector3(0.12, 0.84, -0.2), Vector3(0.5, 0.03, 0.4), STEEL.darkened(0.2))
			_c(st, xf, Vector3(0.12, 0.98, -0.44), 0.015, 0.26, 1, STEEL)
		"counter", "stall":
			_b(st, xf, Vector3(0, 0.5, -0.18), Vector3(0.95, 1.0, 0.6), Color("b8a888") if kind == "counter" else WOOD)
			_goods(st, xf, 1.0, 0.8, -0.18, seed, 4)
		"glass":
			_b(st, xf, Vector3(0, 0.35, -0.2), Vector3(0.95, 0.7, 0.55), Color("7a2a2a") if shop == "goldshop" else WHITE)
			_b(st, xf, Vector3(0, 0.88, -0.2), Vector3(0.95, 0.36, 0.55), Color(0.72, 0.82, 0.86))
			for i in 5:
				_b(st, xf, Vector3(-0.36 + i * 0.18, 0.76, -0.2), Vector3(0.1, 0.03, 0.2), Color("e8c050") if shop == "goldshop" else Color.from_hsv(i * 0.2, 0.5, 0.9))
		"bed":
			var len_ := 2.0 if long else 1.0
			var z0 := (len_ - 1.0) * 0.5
			_b(st, xf, Vector3(0, 0.2, z0), Vector3(0.95, 0.3, len_ * 0.98), DARK_WOOD)
			_b(st, xf, Vector3(0, 0.42, z0), Vector3(0.9, 0.16, len_ * 0.95), Color("ece6da"))
			_b(st, xf, Vector3(0, 0.55, -0.38), Vector3(0.6, 0.1, 0.28), WHITE)  # the pillow, at the head
			_b(st, xf, Vector3(0, 0.51, z0 + len_ * 0.2), Vector3(0.92, 0.04, len_ * 0.55), Color.from_hsv(fmod(seed * 0.31, 1.0), 0.35, 0.7))
			_b(st, xf, Vector3(0, 0.55, -0.48), Vector3(0.95, 0.7, 0.05), DARK_WOOD)  # the headboard
		"fridge":
			if shop in ["minimart", "eatery", "pharmacy", "market", "mall"]:
				# A shop's drinks cooler: a glass door, bottles lined up behind.
				_b(st, xf, Vector3(0, 0.95, -0.25), Vector3(0.75, 1.9, 0.5), Color("d8dcdc"))
				_b(st, xf, Vector3(0, 1.0, 0.01), Vector3(0.62, 1.6, 0.02), Color(0.6, 0.72, 0.8))
				for i in 4:
					_goods(st, xf, 0.3 + i * 0.38, 0.6, -0.1, seed + i * 3, 5)
				_b(st, xf, Vector3(0, 1.84, 0.02), Vector3(0.7, 0.12, 0.02), Color("c83a30"))
			else:
				_b(st, xf, Vector3(0, 0.82, -0.2), Vector3(0.62, 1.64, 0.6), WHITE)
				_b(st, xf, Vector3(0, 1.2, 0.105), Vector3(0.6, 0.01, 0.01), Color("a8a49c"))
				_b(st, xf, Vector3(0.24, 1.0, 0.11), Vector3(0.03, 0.3, 0.03), STEEL)
		"toolchest":
			_b(st, xf, Vector3(0, 0.5, -0.22), Vector3(0.7, 1.0, 0.5), Color("b8302a"))
			for i in 5:
				_b(st, xf, Vector3(0, 0.15 + i * 0.18, 0.035), Vector3(0.5, 0.02, 0.02), STEEL)
		"mirror":
			_b(st, xf, Vector3(0, 1.4, -0.44), Vector3(0.8, 1.0, 0.03), Color(0.75, 0.82, 0.86))
			_b(st, xf, Vector3(0, 0.85, -0.36), Vector3(0.9, 0.04, 0.2), WHITE)
			_goods(st, xf, 0.87, 0.7, -0.36, seed, 4)
		"safe":
			_b(st, xf, Vector3(0, 0.4, -0.2), Vector3(0.6, 0.8, 0.6), Color("3a3c40"))
			_c(st, xf, Vector3(0.1, 0.5, 0.11), 0.06, 0.03, 2, STEEL)
		# --- Decor ---
		"boxes":
			for i in 3:
				_b(st, xf, Vector3(-0.15 + 0.2 * (i % 2), 0.2 + i * 0.36, -0.1), Vector3(0.5, 0.36, 0.45), Color("b89060").darkened(0.06 * i))
		"toilet":
			_b(st, xf, Vector3(0, 0.2, 0.0), Vector3(0.38, 0.4, 0.5), WHITE)
			_b(st, xf, Vector3(0, 0.6, -0.3), Vector3(0.4, 0.4, 0.18), WHITE)
		"tv":
			_b(st, xf, Vector3(0, 0.25, -0.25), Vector3(0.95, 0.5, 0.45), WOOD)
			_b(st, xf, Vector3(0, 0.78, -0.3), Vector3(0.8, 0.5, 0.06), Color("1a1c20"))
		"examcot", "mattress":
			var hgt := 0.7 if kind == "examcot" else 0.12
			_b(st, xf, Vector3(0, hgt - 0.05, 0), Vector3(0.8, 0.1, 0.95), Color("6a9ab0") if kind == "examcot" else Color("d8d0c0"))
			if kind == "examcot":
				_legs(st, xf, 0.8, 0.95, hgt - 0.1, STEEL)
		"curtain":
			_b(st, xf, Vector3(0, 1.1, 0), Vector3(0.95, 1.9, 0.03), Color.from_hsv(fmod(seed * 0.17, 1.0), 0.45, 0.65))
		"tires":
			for i in 3:
				_c(st, xf, Vector3(0, 0.1 + i * 0.2, 0), 0.32, 0.2, 1, Color("1e1e20"), 12)
		"stairs":
			for i in 10:
				_b(st, xf, Vector3(0, 0.18 + i * 0.36, 0.45 - i * 0.1), Vector3(0.9, 0.08, 0.28), Color("b0a490"))
			_b(st, xf, Vector3(0.46, 1.9, 0), Vector3(0.04, 0.04, 1.0), STEEL)
		"hiphra", "altar", "shrine":
			# A shelf for the Buddha high on the wall (hiphra), or a red Chinese altar table.
			var red := kind != "hiphra"
			var y := 0.0 if red else 1.8
			if red:
				_b(st, xf, Vector3(0, 0.45, -0.2), Vector3(0.9, 0.9, 0.5), Color("a82a20"))
			_b(st, xf, Vector3(0, y + (0.9 if red else 0.0), -0.3), Vector3(0.8, 0.05, 0.35), Color("c8a050"))
			_c(st, xf, Vector3(0, y + (1.05 if red else 0.15), -0.35), 0.07, 0.25, 1, Color("e0b848"), 8, 0.02)
			_b(st, xf, Vector3(-0.25, y + (0.97 if red else 0.07), -0.25), Vector3(0.08, 0.12, 0.08), Color("e8d8b0"))
		"wheelchair":
			_b(st, xf, Vector3(0, 0.48, 0), Vector3(0.45, 0.05, 0.45), Color("2a2a2c"))
			_b(st, xf, Vector3(0, 0.75, -0.22), Vector3(0.45, 0.5, 0.04), Color("2a2a2c"))
			for x in [0.26, -0.26]:
				_c(st, xf, Vector3(x, 0.3, -0.05), 0.3, 0.03, 0, STEEL, 12)
		"bench":
			_b(st, xf, Vector3(0, 0.44, 0), Vector3(0.95, 0.05, 0.38), WOOD)
			_legs(st, xf, 0.95, 0.38, 0.42, DARK_WOOD)
		"plants":
			for i in 3:
				var p := Vector3(-0.28 + i * 0.28, 0, 0.05 * (i % 2))
				_c(st, xf, p + Vector3(0, 0.15, 0), 0.13, 0.3, 1, Color("a0583a"), 8, 0.16)
				_b(st, xf, p + Vector3(0, 0.45, 0), Vector3(0.3, 0.35, 0.3), Color("4a7a3a").lightened(0.1 * i))
		"lift":
			_b(st, xf, Vector3(0, 1.1, -0.42), Vector3(1.0, 2.2, 0.08), STEEL)
			_b(st, xf, Vector3(0, 1.1, -0.37), Vector3(0.01, 2.1, 0.02), Color("5a5e62"))
		"fan":
			# A standing fan, the kind every Thai home has.
			_c(st, xf, Vector3(0, 0.02, 0), 0.18, 0.04, 1, Color("3a6aa8"), 10)
			_c(st, xf, Vector3(0, 0.55, 0), 0.02, 1.05, 1, WHITE)
			_c(st, xf, Vector3(0, 1.12, 0.05), 0.24, 0.12, 2, Color("3a6aa8"), 12)
		"sofa":
			_b(st, xf, Vector3(0, 0.22, 0), Vector3(0.95, 0.44, 0.8), Color("6a4a3a"))
			_b(st, xf, Vector3(0, 0.6, -0.32), Vector3(0.95, 0.5, 0.18), Color("6a4a3a"))
		"jar":
			# A glazed water jar (โอ่ง), dragon-brown.
			_c(st, xf, Vector3(0, 0.3, 0), 0.25, 0.6, 1, Color("6a3a24"), 12, 0.36)
			_c(st, xf, Vector3(0, 0.75, 0), 0.36, 0.3, 1, Color("6a3a24"), 12, 0.22)
			_c(st, xf, Vector3(0, 0.92, 0), 0.23, 0.05, 1, Color("4a6a70"), 12)  # the water
		"stove":
			_b(st, xf, Vector3(0, 0.42, -0.2), Vector3(0.9, 0.84, 0.55), Color("c8c2b8"))
			_b(st, xf, Vector3(0, 0.9, -0.2), Vector3(0.6, 0.1, 0.4), Color("2a2a2c"))
			_c(st, xf, Vector3(0.36, 0.28, 0.12), 0.14, 0.5, 1, Color("c83a30"), 10)  # the gas tank
		"chairs":
			# Plastic stools stacked up (red, blue).
			for i in 2:
				var col := PLASTIC_RED if (seed + i) % 2 else PLASTIC_BLUE
				for s in 4:
					_c(st, xf, Vector3(-0.2 + i * 0.4, 0.22 + s * 0.08, 0), 0.15, 0.44, 1, col.darkened(0.03 * s), 8, 0.13)
		"bike":
			for z in [0.32, -0.32]:
				_c(st, xf, Vector3(0, 0.32, z), 0.32, 0.03, 0, Color("1e1e20"), 12)
			_b(st, xf, Vector3(0, 0.55, 0), Vector3(0.03, 0.04, 0.64), Color.from_hsv(fmod(seed * 0.21, 1.0), 0.6, 0.7))
			_b(st, xf, Vector3(0, 0.82, -0.2), Vector3(0.1, 0.04, 0.2), Color("2a2a2c"))
		"shoes":
			for i in 4:
				_b(st, xf, Vector3(-0.3 + i * 0.2, 0.04, 0.2 + 0.05 * (i % 2)), Vector3(0.1, 0.08, 0.26), Color.from_hsv(fmod(i * 0.29 + seed * 0.1, 1.0), 0.4, 0.5))
		"oil":
			for x in [0.22, -0.22]:
				_c(st, xf, Vector3(x, 0.45, 0), 0.22, 0.9, 1, Color("2a5a8a") if x > 0 else Color("b8302a"), 12)
		"barberchair":
			_c(st, xf, Vector3(0, 0.2, 0), 0.2, 0.4, 1, STEEL, 10)
			_b(st, xf, Vector3(0, 0.5, 0), Vector3(0.55, 0.14, 0.55), Color("a82a28"))
			_b(st, xf, Vector3(0, 0.85, -0.24), Vector3(0.55, 0.6, 0.1), Color("a82a28"))
		"washbasin":
			_c(st, xf, Vector3(0, 0.4, -0.3), 0.08, 0.8, 1, WHITE, 8)
			_b(st, xf, Vector3(0, 0.82, -0.28), Vector3(0.5, 0.14, 0.38), WHITE)
		"recliner":
			_b(st, xf, Vector3(0, 0.35, 0.1), Vector3(0.7, 0.2, 0.9), Color("3a5a4a"))
			_b(st, xf, Vector3(0, 0.6, -0.35), Vector3(0.7, 0.5, 0.2), Color("3a5a4a"))
		"sacks":
			for i in 3:
				_b(st, xf, Vector3(-0.25 + i * 0.25, 0.18 + (i % 2) * 0.3, 0), Vector3(0.4, 0.3, 0.6), Color("d8ceb0"))
		"mannequin":
			_c(st, xf, Vector3(0, 0.6, 0), 0.03, 1.2, 1, STEEL)
			_c(st, xf, Vector3(0, 1.35, 0), 0.16, 0.6, 1, Color.from_hsv(fmod(seed * 0.23, 1.0), 0.5, 0.75), 10, 0.13)
			_c(st, xf, Vector3(0, 1.75, 0), 0.1, 0.2, 1, Color("e8dcc8"), 10)
		"pot":
			_c(st, xf, Vector3(0, 0.3, 0), 0.25, 0.6, 1, Color("5a5a5a"), 10)
			_c(st, xf, Vector3(0, 0.78, 0), 0.34, 0.36, 1, STEEL, 12)
		"menu", "lightbox":
			_b(st, xf, Vector3(0, 1.6, -0.45), Vector3(0.8, 0.6, 0.06), Color("f0e8d0") if kind == "menu" else Color("e8c040"))
		"flag":
			_c(st, xf, Vector3(0, 1.5, 0), 0.02, 3.0, 1, WHITE)
			for i in 5:
				var col: Color = [Color("c8202c"), WHITE, Color("24305a"), WHITE, Color("c8202c")][i]
				_b(st, xf, Vector3(0.45, 2.8 - i * 0.12 - (0.06 if i >= 2 else 0.0), 0), Vector3(0.9, 0.12 if i != 2 else 0.24, 0.01), col)
		"pipes":
			for i in 4:
				_c(st, xf, Vector3(0, 0.08 + (i / 2) * 0.14, -0.1 + (i % 2) * 0.16), 0.07, 0.95, 0, Color("8a8e94"), 8)
		"grill":
			_b(st, xf, Vector3(0, 0.45, 0), Vector3(0.7, 0.2, 0.4), Color("3a3a3c"))
			_legs(st, xf, 0.7, 0.4, 0.35, STEEL)
			for i in 4:
				_b(st, xf, Vector3(-0.24 + i * 0.16, 0.57, 0), Vector3(0.04, 0.03, 0.32), Color("8a4a2a"))  # skewers of pork
		# --- Things (you use them) ---
		"tap":
			_c(st, xf, Vector3(0, 0.55, -0.44), 0.02, 0.2, 2, STEEL)
			_c(st, xf, Vector3(0, 0.25, -0.35), 0.18, 0.3, 1, Color("2a62a8"), 10)  # a bucket under it
		"generator":
			_b(st, xf, Vector3(0, 0.3, 0), Vector3(0.7, 0.55, 0.5), Color("e0b020"))
			_b(st, xf, Vector3(0, 0.62, 0), Vector3(0.74, 0.06, 0.54), Color("2a2a2c"))
		"vending":
			_b(st, xf, Vector3(0, 0.9, -0.2), Vector3(0.9, 1.8, 0.6), Color("c8302a"))
			_b(st, xf, Vector3(-0.12, 1.1, 0.11), Vector3(0.55, 1.1, 0.02), Color(0.8, 0.86, 0.9))
		"radio":
			_b(st, xf, Vector3(0, 0.78, -0.3), Vector3(0.3, 0.16, 0.12), Color("3a3a3c"))
		"board":
			for x in [0.5, -0.5]:
				_b(st, xf, Vector3(x, 0.9, 0), Vector3(0.06, 1.8, 0.06), WOOD)
			_b(st, xf, Vector3(0, 1.3, 0), Vector3(1.1, 0.8, 0.04), Color("b89060"))
			for i in 4:
				_b(st, xf, Vector3(-0.35 + i * 0.23, 1.35 + 0.1 * (i % 2), 0.025), Vector3(0.18, 0.24, 0.01), WHITE)
		_:
			pass  # (bulbs and the like: nothing to stand on the floor)
