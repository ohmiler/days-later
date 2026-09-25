class_name BuildingProp
extends Node2D
## One building in 3/4 view. The origin is the bottom-left of its footprint,
## so it y-sorts against characters by its front wall. The front wall (facade)
## rises `h` pixels above the footprint's bottom edge and the roof sits on top.

const FLOOR_H := 13.0
const GROUND_H := 15.0

var data: Dictionary
var w := 0.0  # footprint width in px
var d := 0.0  # footprint depth in px
var h := 0.0  # facade height in px
var glow: Node2D  # unshaded layer for lit windows and signs at night
var rng := RandomNumberGenerator.new()


func setup(rec: Dictionary) -> void:
	data = rec
	var r: Rect2i = rec.rect
	w = r.size.x * World.TILE
	d = r.size.y * World.TILE
	match rec.kind:
		"condo":
			h = rec.floors * 11.0 + 8.0
		"temple":
			h = 34.0
		"chedi":
			h = 0.0
		"sala":
			h = 16.0
		"store":
			h = GROUND_H + 6.0
		_:
			h = GROUND_H + (rec.floors - 1) * FLOOR_H + 4.0
	position = Vector2(r.position.x, r.end.y) * World.TILE
	glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = mat
	glow.visible = false
	glow.draw.connect(_draw_glow)
	glow.add_to_group("night_glow")
	add_child(glow)


## Screen-space box covering everything this building draws.
func visual_rect() -> Rect2:
	var top := -h - d - (40.0 if data.kind in ["temple", "chedi"] else 0.0)
	return Rect2(position + Vector2(0, top), Vector2(w, -top))


func _draw() -> void:
	rng.seed = data.seed
	match data.kind:
		"shop":
			_draw_shop()
		"store":
			_draw_store()
		"condo":
			_draw_condo()
		"temple":
			_draw_temple()
		"chedi":
			_draw_chedi()
		"sala":
			_draw_sala()


# --- Shared pieces ----------------------------------------------------------

func _wall(col: Color) -> void:
	draw_polygon(PackedVector2Array([Vector2(0, -h), Vector2(w, -h), Vector2(w, 0), Vector2(0, 0)]),
			PackedColorArray([col, col.darkened(0.05), col.darkened(0.28), col.darkened(0.24)]))
	# Rain streaks under the roof line.
	for i in int(w / 9):
		var x := 4.0 + i * 9.0 + rng.randf() * 4.0
		draw_line(Vector2(x, -h + 3), Vector2(x, -h + 6 + rng.randf() * h * 0.4), Color(0, 0, 0, 0.07), 2.0)


func _flat_roof(col: Color) -> void:
	var roof := Rect2(0, -h - d, w, d)
	if rng.randf() < 0.35:
		# Corrugated metal roof, often rusty.
		var metal := Color("8a8e90") if rng.randf() < 0.5 else Color("8a5a3e")
		draw_rect(roof, metal)
		for x in range(0, int(w), 3):
			draw_line(Vector2(x, -h - d), Vector2(x, -h), metal.darkened(0.18), 1.0)
		for i in 3:
			draw_circle(Vector2(rng.randf() * w, -h - rng.randf() * d), rng.randf_range(3, 7), Color(0.45, 0.22, 0.1, 0.3))
	else:
		draw_rect(roof, Color("6e6a63"))
		for i in 4:  # water stains and patch repairs
			draw_circle(Vector2(rng.randf() * w, -h - rng.randf() * d), rng.randf_range(3, 9), Color(0, 0, 0, 0.1))
		draw_rect(Rect2(rng.randf() * (w - 12), -h - d + rng.randf() * (d - 8), 12, 8), Color("7c786f"))
		for i in rng.randi_range(1, 3):  # air-con compressors
			var p := Vector2(rng.randf_range(3, w - 9), -h - rng.randf_range(6, d - 4))
			draw_rect(Rect2(p, Vector2(7, 5)), Color("cfcfc8"))
			draw_circle(p + Vector2(3.5, 2.5), 1.8, Color("7a7a74"))
		if rng.randf() < 0.4:  # laundry line
			var y := -h - d * rng.randf_range(0.3, 0.7)
			draw_line(Vector2(3, y), Vector2(w - 3, y), Color("2a2a2a"), 0.4)
			for i in int((w - 8) / 5):
				draw_rect(Rect2(4 + i * 5, y, 3, 3), Color.from_hsv(rng.randf(), 0.4, 0.8))
		if rng.randf() < 0.3:  # potted plants
			for i in 3:
				draw_circle(Vector2(5 + i * 5, -h - d + 5), 2.2, Color("4a6a38"))
	draw_rect(roof, Color(0, 0, 0, 0.2), false, 1.5)
	draw_rect(Rect2(0, -h - d, w, 2), col.darkened(0.15))  # back parapet
	draw_rect(Rect2(0, -h - 3, w, 3), col.lightened(0.05))  # front parapet
	if rng.randf() < 0.7:
		# Rooftop water tank.
		var p := Vector2(rng.randf_range(8, maxf(9.0, w - 14)), -h - d + rng.randf_range(10, maxf(11.0, d - 10)))
		var tank := Color("3f6f9e") if rng.randf() < 0.6 else Color("a8acb0")
		draw_rect(Rect2(p + Vector2(-4, -7), Vector2(8, 7)), tank.darkened(0.2))
		draw_set_transform(p + Vector2(0, -7), 0, Vector2(1, 0.45))
		draw_circle(Vector2.ZERO, 4, tank)
		draw_set_transform(Vector2.ZERO)
	if rng.randf() < 0.4:
		var a := Vector2(rng.randf_range(4, w - 4), -h - d + 6)
		draw_line(a, a + Vector2(0, -12), Color("333333"), 0.6)  # antenna
		draw_line(a + Vector2(-3, -10), a + Vector2(3, -10), Color("333333"), 0.6)


## Upper-floor window rects, shared by the day drawing and the night glow.
func _windows() -> Array:
	var out := []
	var count := maxi(1, int(w / 22))
	var span := w / count
	for f in range(1, data.floors):
		var y := -GROUND_H - f * FLOOR_H + 3.0
		for i in count:
			out.append(Rect2(i * span + span * 0.5 - 6, y, 12, 7))
	return out


func _sign_rect() -> Rect2:
	return Rect2(2, -GROUND_H - 7, w - 4, 6)


func _text(rect: Rect2, text: String, col: Color, size: int) -> void:
	var font := Look.thai_font()
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + size * 0.36), text,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, col)


# --- Kinds ------------------------------------------------------------------

func _draw_shop() -> void:
	var col: Color = data.color
	_flat_roof(col)
	_wall(col)
	draw_rect(Rect2(0, -h, 1.5, h), col.darkened(0.3))  # party wall between units
	for wr: Rect2 in _windows():
		draw_rect(wr.grow(1), col.darkened(0.35))
		draw_rect(wr, Color("262b30"))
		draw_line(wr.position + Vector2(2, 6), wr.position + Vector2(6, 1), Color(1, 1, 1, 0.12), 1.5)
		for gx in range(2, 12, 3):
			draw_line(wr.position + Vector2(gx, 0), wr.position + Vector2(gx, 7), Color("8a8a82"), 0.4)  # grille
		if rng.randf() < 0.45:
			var ac := Rect2(wr.position + Vector2(rng.randf_range(-2, 7), 7.5), Vector2(6, 4))  # air-con unit
			draw_rect(ac, Color("c8c8c0"))
			draw_circle(ac.get_center() + Vector2(0.8, 0), 1.3, Color("6a6a66"))
	# Ground floor: open shop front with an awning, or a pulled-down shutter.
	if data.open:
		draw_rect(Rect2(2, -GROUND_H + 1, w - 4, GROUND_H - 1), Color("231f1a"))
		for i in int((w - 8) / 5):
			draw_rect(Rect2(4 + i * 5, -8 - rng.randf() * 4, 3, 3), Color.from_hsv(rng.randf(), 0.45, 0.6))
		var aw := Color.from_hsv(rng.randf(), 0.5, 0.65)
		for i in int(w / 6) + 1:
			var x0 := i * 6.0
			draw_colored_polygon(PackedVector2Array([Vector2(x0, -GROUND_H), Vector2(minf(x0 + 6, w), -GROUND_H),
					Vector2(minf(x0 + 7, w + 1), -GROUND_H + 5), Vector2(x0 + 1, -GROUND_H + 5)]),
					aw if i % 2 == 0 else Color("e8e2d4"))
	else:
		draw_rect(Rect2(2, -GROUND_H + 1, w - 4, GROUND_H - 1), Color("8a8c8e"))
		for y in range(-int(GROUND_H) + 2, 0, 2):
			draw_line(Vector2(2, y), Vector2(w - 2, y), Color("6e7072"), 0.5)
		if rng.randf() < 0.4:
			draw_line(Vector2(w * 0.3, -9), Vector2(w * 0.6, -5), Color("b8482e", 0.6), 1.2)  # graffiti
	if data.sign != "":
		var sr := _sign_rect()
		var sc := Color.from_hsv(rng.randf(), 0.7, 0.75)
		draw_rect(sr, sc)
		draw_rect(sr, sc.darkened(0.4), false, 0.5)
		_text(sr, data.sign, Color.WHITE if sc.get_luminance() < 0.55 else Color("1a1a1a"), 5)


func _draw_store() -> void:
	var col := Color("e8e6e0")
	_flat_roof(col)
	_wall(col)
	draw_rect(Rect2(0, -h + 1, w, 5), Color("2a62a8"))  # brand stripe
	_text(Rect2(0, -h + 1, w, 5), data.sign, Color.WHITE, 4)
	draw_rect(Rect2(3, -GROUND_H + 1, w - 6, GROUND_H - 2), Color("a8c8d4"))
	for i in int((w - 10) / 6):
		draw_rect(Rect2(6 + i * 6, -10, 4, 7), Color("6a8a9a"))  # shelves behind glass
	draw_rect(Rect2(w * 0.5 - 4, -GROUND_H + 1, 8, GROUND_H - 2), Color("c8e0e8"))  # door


func _draw_condo() -> void:
	var col: Color = [Color("d8d4cc"), Color("c4c8cc"), Color("d8ccb8")][data.seed % 3]
	_flat_roof(col)
	draw_rect(Rect2(w * 0.3, -h - d * 0.7, w * 0.4, d * 0.4), Color("8a867e"))  # lift housing
	_wall(col)
	for f in data.floors:
		var y := -h + 6 + float(f) * 11.0
		draw_rect(Rect2(3, y, w - 6, 6), Color("2e343a"))
		draw_line(Vector2(3, y + 6.5), Vector2(w - 3, y + 6.5), col.lightened(0.1), 1.2)  # balcony rail
		for x in range(8, int(w) - 4, 14):
			draw_line(Vector2(x, y), Vector2(x, y + 6), col.darkened(0.2), 1.0)
	draw_rect(Rect2(w * 0.35, -GROUND_H + 2, w * 0.3, GROUND_H - 2), Color("3a4a56"))  # lobby


func _draw_temple() -> void:
	var red := Color("b8452a")
	var green := Color("2e6048")
	var gold := Color("c9a03a")
	var white := Color("ece6da")
	# Tiered roof seen from above: nested layers, gold ridge down the middle.
	draw_rect(Rect2(-4, -h - d, w + 8, d), green)
	draw_rect(Rect2(0, -h - d + 3, w, d - 4), red)
	draw_rect(Rect2(10, -h - d + 8, w - 20, d - 14), red.lightened(0.1))
	draw_rect(Rect2(10, -h - d + 8, w - 20, d - 14), green, false, 1.5)
	draw_line(Vector2(w / 2, -h - d + 3), Vector2(w / 2, -h), gold, 2.0)
	# White walls with red columns, gilded doors and windows.
	draw_polygon(PackedVector2Array([Vector2(0, -h), Vector2(w, -h), Vector2(w, 0), Vector2(0, 0)]),
			PackedColorArray([white, white, white.darkened(0.15), white.darkened(0.15)]))
	for i in 7:
		var x := 6.0 + i * (w - 12) / 6.0
		draw_rect(Rect2(x - 2, -h + 4, 4, h - 4), Color("a83a26"))
		draw_rect(Rect2(x - 2.5, -h + 3, 5, 2), gold)
	draw_rect(Rect2(w / 2 - 7, -22, 14, 22), Color("6a2a1a"))
	draw_rect(Rect2(w / 2 - 7, -22, 14, 22), gold, false, 1.5)
	for x in [w * 0.22, w * 0.78]:
		draw_rect(Rect2(x - 4, -24, 8, 11), Color("4a2418"))
		draw_rect(Rect2(x - 4, -24, 8, 11), gold, false, 1.0)
	draw_rect(Rect2(-2, -3, w + 4, 3), white.darkened(0.3))  # plinth
	# Stacked front gables with gold bargeboards and chofa finials.
	for tier in 3:
		var inset := tier * w * 0.09
		var base_y := -h - tier * 7.0
		var peak := Vector2(w / 2, base_y - 24 + tier * 2)
		var l := Vector2(w * 0.18 + inset, base_y)
		var r := Vector2(w * 0.82 - inset, base_y)
		draw_colored_polygon(PackedVector2Array([l, r, peak]), red.darkened(tier * 0.08))
		draw_colored_polygon(PackedVector2Array([l.lerp(peak, 0.2) + Vector2(3, 0), r.lerp(peak, 0.2) - Vector2(3, 0), peak.lerp(Vector2(w / 2, base_y), 0.25)]), gold.darkened(0.2))
		draw_line(l, peak, gold, 1.5)
		draw_line(r, peak, gold, 1.5)
		draw_line(l, l + Vector2(-3, -3), gold, 1.2)  # hang hong (upturned ends)
		draw_line(r, r + Vector2(3, -3), gold, 1.2)
		if tier == 2:
			draw_line(peak, peak + Vector2(2, -5), gold, 1.5)  # chofa
			draw_line(peak + Vector2(2, -5), peak + Vector2(4, -4), gold, 1.2)


func _draw_chedi() -> void:
	var white := Color("eae4d6")
	var gold := Color("d0a83c")
	var cx := w / 2
	draw_rect(Rect2(4, -8, w - 8, 8), white.darkened(0.2))
	draw_rect(Rect2(10, -14, w - 20, 6), white.darkened(0.1))
	var bell := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 17:
		var a := PI + i * PI / 16.0
		bell.append(Vector2(cx + cos(a) * 20, -14 + sin(a) * 26))
		cols.append(white.lightened(0.05) if i < 8 else white.darkened(0.15))
	draw_polygon(bell, cols)
	draw_rect(Rect2(cx - 7, -44, 14, 5), white)  # harmika
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, -44), Vector2(cx + 5, -44), Vector2(cx, -82)]), gold)
	for i in 6:
		var y := -48.0 - i * 5.0
		var half := 4.5 - i * 0.65
		draw_line(Vector2(cx - half, y), Vector2(cx + half, y), gold.darkened(0.25), 0.8)


func _draw_sala() -> void:
	var red := Color("b8452a")
	draw_rect(Rect2(0, -h - d, w, d), red)
	draw_rect(Rect2(0, -h - d, w, d), Color("2e6048"), false, 1.5)
	draw_rect(Rect2(0, -h - 2, w, 2), Color("c9a03a"))
	for x in [2.0, w - 4]:
		draw_rect(Rect2(x, -h, 2, h), Color("ece6da"))
	draw_rect(Rect2(4, -5, w - 8, 2), Color("6a4a30"))  # bench


# --- Night ------------------------------------------------------------------

func _draw_glow() -> void:
	match data.kind:
		"shop":
			var lit := RandomNumberGenerator.new()
			lit.seed = data.seed + 7
			for wr: Rect2 in _windows():
				if lit.randf() < 0.3:
					glow.draw_rect(wr, Color(1.0, 0.82, 0.5, 0.75))
			if data.sign != "":
				glow.draw_rect(_sign_rect(), Color(1, 1, 1, 0.12))
		"store":
			glow.draw_rect(Rect2(3, -GROUND_H + 1, w - 6, GROUND_H - 2), Color(0.8, 0.95, 1.0, 0.7))
		"condo":
			var lit := RandomNumberGenerator.new()
			lit.seed = data.seed + 7
			for f in data.floors:
				for x in range(3, int(w) - 8, 7):
					if lit.randf() < 0.18:
						glow.draw_rect(Rect2(x, -h + 6 + f * 11.0, 6, 6), Color(1.0, 0.85, 0.55, 0.7))
