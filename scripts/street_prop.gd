class_name StreetProp
extends Node2D
## Small street objects in 3/4 view: power poles with lamps, cars, taxis,
## tuk-tuks, motorbikes, food carts, rubbish and skytrain pillars.
## Origin is where the object meets the ground, for y-sorting.

static var _glow_tex: Texture2D
## Vehicles are drawn this much bigger than their shapes below, so a car is
## longer than a person is tall (see CityGen._size_vehicles for what they block).
const VEHICLE_SCALE := 1.6
const VEHICLES := ["car", "taxi", "tuktuk", "motorbike", "wreck", "army"]

var data: Dictionary


func _ready() -> void:
	if data.kind == "pole" and data.lamp != Vector2.ZERO:
		var light := PointLight2D.new()
		light.texture = _lamp_texture()
		light.texture_scale = 1.4
		light.color = Color("ffb35c")  # sodium orange
		light.energy = 0.9
		light.position = data.lamp
		light.visible = false
		light.add_to_group("street_lights")
		add_child(light)


static func _lamp_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_glow_tex = t
	return _glow_tex


func _draw() -> void:
	match data.kind:
		"pole":
			_pole()
		"car", "taxi":
			if data.horizontal:
				_car_side()
			else:
				_car_end()
		"tuktuk":
			_tuktuk()
		"motorbike":
			_motorbike()
		"cart":
			_cart()
		"trash":
			_trash()
		"pillar":
			_pillar()
		"wreck":
			_wreck()
		"glass":
			_glass()
		"papers":
			_papers()
		"luggage":
			_luggage()
		"drag":
			_drag()
		"debris":
			_debris()
		"spirit":
			_spirit()
		"stall":
			_stall()
		"bin":
			_bin()
		"boat":
			_boat()
		"sandbags":
			_sandbags()
		"barrier":
			_barrier()
		"army":
			_army()


var _xf := Transform2D.IDENTITY  # the transform a whole prop is drawn under (a wreck turned askew)


func _shadow(size: Vector2, offset := Vector2.ZERO) -> void:
	if _xf.determinant() < 0.0:
		return  # an upside-down wreck: its own scorch mark is shadow enough
	draw_set_transform_matrix(_xf * Transform2D(0, Vector2(1, size.y / size.x), 0, offset))
	draw_circle(Vector2.ZERO, size.x, Color(0, 0, 0, 0.3))
	draw_set_transform_matrix(_xf)


func _pole() -> void:
	var concrete := Color("9a968e")
	_shadow(Vector2(4, 1.5))
	draw_polygon(PackedVector2Array([Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(1.0, -47), Vector2(-1.0, -47)]),
			PackedColorArray([concrete.darkened(0.3), concrete.darkened(0.1), concrete, concrete.lightened(0.1)]))
	draw_rect(Rect2(-6, -44, 12, 1.4), Color("5a5850"))  # cross-arm
	for x in [-5.0, -1.5, 2.0, 5.0]:
		draw_circle(Vector2(x, -45), 0.7, Color("c8c8c0"))  # insulators
	draw_set_transform(Vector2(0.5, -38), 0, Vector2(1, 0.6))
	draw_circle(Vector2.ZERO, 3.2, Color("1c1c1c"))  # tangle of cables
	draw_set_transform(Vector2.ZERO)
	if data.seed % 5 == 0:
		draw_rect(Rect2(1.5, -34, 5, 7), Color("6e7470"))  # transformer
		draw_rect(Rect2(1.5, -34, 5, 7), Color("4a504c"), false, 0.5)
	var lamp: Vector2 = data.lamp
	if lamp != Vector2.ZERO:
		var head := lamp + Vector2(0, -40)
		draw_line(Vector2(0, -40), head, Color("5a5850"), 1.0)
		draw_rect(Rect2(head + Vector2(-2.5, -0.5), Vector2(5, 2)), Color("3a3a36"))
		draw_rect(Rect2(head + Vector2(-2, 1.2), Vector2(4, 0.8)), Color("e8d8b0"))


func _car_side(burnt := false) -> void:
	var col: Color = data.color
	if burnt:
		col = Color("3a302a")
	var taxi: bool = data.kind == "taxi"
	_shadow(Vector2(17, 3), Vector2(16, -1))
	var body := PackedVector2Array([Vector2(1, -3), Vector2(31, -3), Vector2(31, -8), Vector2(26, -10), Vector2(3, -10), Vector2(1, -8)])
	draw_polygon(body, PackedColorArray([col.darkened(0.3), col.darkened(0.3), col, col.lightened(0.1), col.lightened(0.1), col]))
	var cabin := PackedVector2Array([Vector2(7, -10), Vector2(24, -10), Vector2(21, -16), Vector2(10, -16)])
	draw_colored_polygon(cabin, col.lightened(0.05))
	var glass := Color("121010") if burnt else Color("2a323a")
	draw_colored_polygon(PackedVector2Array([Vector2(8.5, -10.5), Vector2(15, -10.5), Vector2(15, -15.2), Vector2(10.7, -15.2)]), glass)
	draw_colored_polygon(PackedVector2Array([Vector2(16, -10.5), Vector2(22.5, -10.5), Vector2(20.4, -15.2), Vector2(16, -15.2)]), glass)
	draw_rect(Rect2(10, -17, 11, 1.2), col.lightened(0.2))  # roof catching the light
	if taxi:
		draw_rect(Rect2(13, -19, 5, 2), Color("e8d040"))
		if col == Color("3a8a4a"):
			draw_rect(Rect2(3, -10, 24, 3), Color("e8d040"))  # green-and-yellow cab
	draw_circle(Vector2(7, -3), 2.8, Color("161616"))
	draw_circle(Vector2(25, -3), 2.8, Color("161616"))
	draw_circle(Vector2(7, -3), 1.1, Color("6a6a6a"))
	draw_circle(Vector2(25, -3), 1.1, Color("6a6a6a"))
	draw_rect(Rect2(30, -8, 1.5, 2), Color("e8e0c0"))  # headlight
	draw_rect(Rect2(0.5, -8, 1.5, 2), Color("a82a20"))  # tail light
	if data.seed % 4 == 0:
		draw_line(Vector2(17, -14), Vector2(20, -11), Color("c8ccd0"), 0.5)  # smashed window


func _car_end() -> void:
	var col: Color = data.color
	_shadow(Vector2(9, 5), Vector2(8, -3))
	draw_rect(Rect2(1, -30, 14, 26), col)  # bonnet + roof seen from above
	draw_rect(Rect2(2.5, -24, 11, 11), col.lightened(0.12))
	draw_rect(Rect2(2.5, -13, 11, 3), Color("2a323a"))  # windscreen
	draw_rect(Rect2(2.5, -27, 11, 2.5), Color("2a323a"))
	draw_rect(Rect2(1, -6, 14, 5), col.darkened(0.3))  # front face
	draw_rect(Rect2(2, -5, 2.5, 1.5), Color("e8e0c0"))
	draw_rect(Rect2(11.5, -5, 2.5, 1.5), Color("e8e0c0"))
	draw_rect(Rect2(0, -9, 1, 4), Color("161616"))
	draw_rect(Rect2(15, -9, 1, 4), Color("161616"))
	if data.kind == "taxi":
		draw_rect(Rect2(6, -20, 4, 2), Color("e8d040"))


func _tuktuk() -> void:
	var col: Color = data.color
	_shadow(Vector2(9, 2.5), Vector2(8, -1))
	draw_rect(Rect2(1, -8, 14, 5), col)
	draw_rect(Rect2(1, -8, 14, 1), col.lightened(0.2))
	draw_rect(Rect2(8, -12, 6, 4), Color("8a2a24"))  # passenger bench
	draw_line(Vector2(2, -8), Vector2(2, -18), Color("2a2a2a"), 0.8)
	draw_line(Vector2(14.5, -8), Vector2(14.5, -18), Color("2a2a2a"), 0.8)
	draw_rect(Rect2(0, -20, 16, 3), col.darkened(0.25))  # canopy
	for i in 8:
		draw_line(Vector2(0.5 + i * 2, -17), Vector2(0.5 + i * 2, -16), Color("d8c040"), 0.6)  # fringe
	for x in [3.5, 13.0]:
		draw_circle(Vector2(x, -2.5), 2.2, Color("161616"))


func _motorbike() -> void:
	var col := Color.from_hsv(float(data.seed % 97) / 97.0, 0.5, 0.45)
	var s := 1.0 if data.seed % 2 else -1.0
	_shadow(Vector2(7, 1.5))
	draw_set_transform(Vector2.ZERO, 0, Vector2(s, 1))
	draw_circle(Vector2(-5, -2), 2.0, Color("161616"))
	draw_circle(Vector2(5, -2), 2.0, Color("161616"))
	draw_colored_polygon(PackedVector2Array([Vector2(-5, -3), Vector2(3, -3), Vector2(5, -7), Vector2(-3, -7)]), col)
	draw_rect(Rect2(-4.5, -8, 5, 1.5), Color("1e1e1e"))  # seat
	draw_line(Vector2(4, -6), Vector2(5, -10), Color("2a2a2a"), 0.8)
	draw_line(Vector2(3.5, -10), Vector2(6.5, -10), Color("2a2a2a"), 0.8)  # handlebars
	draw_set_transform(Vector2.ZERO)


func _cart() -> void:
	_shadow(Vector2(8, 2.5))
	draw_rect(Rect2(-7, -9, 14, 7), Color("b8bcc0"))
	draw_rect(Rect2(-7, -9, 14, 1), Color("dcdfe2"))
	draw_rect(Rect2(-5, -14, 10, 5), Color(0.8, 0.9, 0.95, 0.6))  # glass case
	draw_rect(Rect2(-4, -12, 3, 2), Color("d89a3a"))
	draw_rect(Rect2(0, -12, 3, 2), Color("c85a3a"))
	draw_circle(Vector2(-5, -2), 1.6, Color("222222"))
	draw_circle(Vector2(5, -2), 1.6, Color("222222"))
	draw_line(Vector2(0, -14), Vector2(0, -26), Color("6a6a6a"), 0.8)
	var col: Color = [Color("c83a2e"), Color("2a6ab8"), Color("e8a030")][data.seed % 3]
	for i in 8:
		var a0 := PI + i * PI / 8
		var a1 := PI + (i + 1) * PI / 8
		draw_colored_polygon(PackedVector2Array([Vector2(0, -29), Vector2(cos(a0) * 11, -26 + sin(a0) * -2 + 2),
				Vector2(cos(a1) * 11, -26 + sin(a1) * -2 + 2)]), col if i % 2 == 0 else Color("ece8e0"))


func _trash() -> void:
	_shadow(Vector2(5, 1.5))
	for i in 3:
		var p := Vector2(-3 + i * 3, -2.5 - (i % 2) * 1.5)
		draw_circle(p, 2.6, Color("1a1a1c"))
		draw_circle(p + Vector2(-0.8, -1), 0.8, Color("4a4a50"))


func _pillar() -> void:
	var concrete := Color("a19d94")
	var top := World.TILE - World.BTS_H + 9.0  # up to the deck underside
	draw_rect(Rect2(3, -World.TILE * 2.0 + 2, 10, 4), Color(0, 0, 0, 0.25))
	draw_polygon(PackedVector2Array([Vector2(3, 0), Vector2(13, 0), Vector2(12, top), Vector2(4, top)]),
			PackedColorArray([concrete.darkened(0.3), concrete.darkened(0.15), concrete, concrete.lightened(0.05)]))
	draw_rect(Rect2(-3, top - 4, 22, 5), concrete.darkened(0.1))


# --- Aftermath ---------------------------------------------------------------

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = data.seed
	return r


## A car that crashed: slewed across the lane, burnt out, or upside down.
func _wreck() -> void:
	var r := _rng()
	var ang: float = data.angle
	var burnt: bool = data.pose == "burnt"
	var flip: bool = data.pose == "flipped"
	var side: bool = data.horizontal
	var mid := Vector2(16, -8) if side else Vector2(8, -15)
	# Scorch or oil under it.
	draw_set_transform(Vector2(mid.x, -3), 0, Vector2(1, 0.45))
	draw_circle(Vector2.ZERO, 17.0 if side else 12.0, Color(0.04, 0.03, 0.02, 0.5 if burnt else 0.22))
	# Turned about its middle; a flipped one mirrored top to bottom as well.
	var xf := Transform2D(ang, mid) * Transform2D(0, Vector2(1, -1 if flip else 1), 0, Vector2.ZERO) * Transform2D(0, -mid)
	_xf = xf
	draw_set_transform_matrix(xf)
	var keep: Color = data.color
	if burnt:
		data.color = Color("3a302a")
	if side:
		_car_side(burnt)
	else:
		_car_end()
	data.color = keep
	if flip:
		draw_rect(Rect2(3, -3, 26, 2), Color("2a2622") if side else Color("2a2622"))  # the underside
	elif side and data.seed % 3 == 0:
		draw_colored_polygon(PackedVector2Array([Vector2(16, -10.5), Vector2(19, -10.5), Vector2(23, -17), Vector2(20, -17)]),
				(data.color as Color).darkened(0.25))  # door hanging open
	if burnt:
		for i in 6:
			var p := Vector2(r.randf_range(4, 28 if side else 14), r.randf_range(-16, -5) if side else r.randf_range(-28, -6))
			draw_circle(p, r.randf_range(0.8, 1.8), Color(0.42, 0.2, 0.08, 0.7))  # rust
			draw_circle(p + Vector2(1.5, 1), r.randf_range(0.8, 1.6), Color(0.05, 0.04, 0.03, 0.6))  # soot
	_xf = Transform2D.IDENTITY
	draw_set_transform(Vector2.ZERO)


func _glass() -> void:
	var r := _rng()
	for i in 9:
		var p := Vector2(r.randf_range(-6, 6), r.randf_range(-2, 2))
		draw_rect(Rect2(p, Vector2(1, 0.6)), Color(0.8, 0.9, 0.95, 0.55))


func _papers() -> void:
	var r := _rng()
	for i in r.randi_range(2, 4):
		var p := Vector2(r.randf_range(-6, 6), r.randf_range(-3, 1))
		draw_set_transform(p, r.randf_range(-0.8, 0.8), Vector2.ONE)
		draw_rect(Rect2(-1.5, -1, 3, 2), Color("d8d4c8") if i % 2 else Color("c8b890"))
	draw_set_transform(Vector2.ZERO)


## A suitcase dropped by someone running, clothes spilling out.
func _luggage() -> void:
	var r := _rng()
	var col := Color.from_hsv(r.randf(), 0.4, 0.45)
	draw_set_transform(Vector2.ZERO, r.randf_range(-0.6, 0.6), Vector2.ONE)
	draw_rect(Rect2(-4, -3, 8, 5), col)
	draw_rect(Rect2(-4, -3, 8, 5), col.darkened(0.35), false, 0.5)
	draw_rect(Rect2(-1, -3.8, 2, 0.8), Color("2a2a2a"))
	for i in 3:
		draw_rect(Rect2(3 + i * 2, -1 + i * 0.6, 2.5, 1.5), Color.from_hsv(r.randf(), 0.4, 0.7))
	draw_set_transform(Vector2.ZERO)


## Dried blood where something was dragged away.
func _drag() -> void:
	if Look.low_gore:
		return
	var r := _rng()
	var dir := Vector2.from_angle(r.randf() * TAU) * Vector2(1, 0.6)
	for i in 7:
		var p := dir * i * 2.2 + Vector2(r.randf_range(-0.6, 0.6), r.randf_range(-0.4, 0.4))
		draw_circle(p, 1.4 - i * 0.12, Color(0.3, 0.03, 0.02, 0.55 - i * 0.05))


## Rubbish heaped against a wall: bags, a broken chair, planks.
func _debris() -> void:
	var r := _rng()
	_shadow(Vector2(8, 2))
	draw_line(Vector2(-7, -2), Vector2(6, -8), Color("7a5a3a"), 1.6)
	for i in 5:
		var p := Vector2(r.randf_range(-6, 6), r.randf_range(-7, -2))
		draw_circle(p, r.randf_range(2, 3.4), Color("1a1a1c") if i % 2 else Color("2a3a5a"))
	draw_rect(Rect2(2, -6, 4, 1), Color("c83a2e"))  # a plastic stool, legs up
	draw_rect(Rect2(2, -9, 1, 3), Color("a82e24"))
	draw_rect(Rect2(5, -9, 1, 3), Color("a82e24"))


## San phra phum: the little house for the spirit of the land, on its pillar.
func _spirit() -> void:
	var gold := Color("d0a83c")
	_shadow(Vector2(4, 1.5))
	draw_rect(Rect2(-1, -14, 2, 14), Color("e8e2d4"))  # pillar
	draw_rect(Rect2(-5, -16, 10, 2), Color("c8c0b0"))
	draw_rect(Rect2(-3.5, -22, 7, 6), Color("e8dcc0"))
	draw_rect(Rect2(-1.2, -21, 2.4, 4), Color("8a2a1a"))  # doorway
	draw_colored_polygon(PackedVector2Array([Vector2(-5, -22), Vector2(5, -22), Vector2(0, -28)]), Color("b8452a"))
	draw_line(Vector2(-5, -22), Vector2(0, -28), gold, 0.6)
	draw_line(Vector2(5, -22), Vector2(0, -28), gold, 0.6)
	draw_line(Vector2(0, -28), Vector2(0.8, -30), gold, 0.6)
	# Offerings: garlands, a red soda with a straw, little figures.
	draw_circle(Vector2(-3.5, -16.5), 0.9, Color("e8c040"))
	draw_circle(Vector2(3.5, -16.5), 0.9, Color("e87a3a"))
	draw_rect(Rect2(1.5, -18, 1, 2), Color("c8283a"))
	if data.seed % 2 == 0:
		draw_line(Vector2(-4, -16), Vector2(4, -16), Color("e8e0a0"), 0.5)


## Plastic table, stools and a big umbrella: a noodle stall nobody came back to.
func _stall() -> void:
	var r := _rng()
	var tone: Color = [Color("c83a2e"), Color("2a6ab8"), Color("e8a030"), Color("3a8a4a")][data.seed % 4]
	_shadow(Vector2(9, 2.5))
	draw_rect(Rect2(-5, -6, 10, 1.5), Color("e8e2d4"))
	draw_rect(Rect2(-4, -4.5, 1, 4.5), Color("9a9a9a"))
	draw_rect(Rect2(3, -4.5, 1, 4.5), Color("9a9a9a"))
	for i in 3:
		var x := -8.0 + i * 7.0
		if r.randf() < 0.3:
			draw_rect(Rect2(x, -1.5, 3, 1.5), tone.darkened(0.2))  # knocked over
		else:
			draw_rect(Rect2(x, -3.5, 3, 1.2), tone)
			draw_rect(Rect2(x + 0.3, -2.3, 2.4, 2.3), tone.darkened(0.2))
	draw_line(Vector2(0, -6), Vector2(0, -22), Color("7a7a7a"), 0.7)
	for i in 8:
		var a0 := PI + i * PI / 8
		var a1 := PI + (i + 1) * PI / 8
		draw_colored_polygon(PackedVector2Array([Vector2(0, -25), Vector2(cos(a0) * 12, -21 + sin(a0) * -1.5 + 1.5),
				Vector2(cos(a1) * 12, -21 + sin(a1) * -1.5 + 1.5)]), tone if i % 2 == 0 else Color("ece8e0"))


## The green bins every soi has.
func _bin() -> void:
	_shadow(Vector2(4, 1.5))
	draw_rect(Rect2(-3, -8, 6, 8), Color("2e6a3a"))
	draw_rect(Rect2(-3.4, -9, 6.8, 1.5), Color("245630"))
	draw_rect(Rect2(-3, -8, 1.2, 8), Color(1, 1, 1, 0.08))
	if data.seed % 3 == 0:
		draw_circle(Vector2(4, -1.5), 2, Color("1a1a1c"))  # a bag that did not fit


## A long-tail boat left in the canal; some have sunk to the gunwales.
func _boat() -> void:
	var sunk: bool = data.seed % 3 == 0
	var wood := Color("6a4a2a")
	var s := 1.0 if data.seed % 2 else -1.0
	draw_set_transform(Vector2.ZERO, 0, Vector2(s, 1))
	var hull := PackedVector2Array([Vector2(-22, -4), Vector2(18, -4), Vector2(24, -8), Vector2(14, -1), Vector2(-20, -1)])
	draw_colored_polygon(hull, wood.darkened(0.35) if sunk else wood)
	draw_line(Vector2(-21, -4), Vector2(23, -8), wood.lightened(0.2), 0.8)
	if not sunk:
		draw_rect(Rect2(-6, -5, 12, 1.5), Color("3a2a1a"))  # thwart
		for i in 3:
			draw_circle(Vector2(20 + i * 0.5, -8 - i), 0.8, [Color("e84a6a"), Color("e8c040"), Color("4a9ae8")][i])  # ribbons on the bow
	draw_rect(Rect2(-24, -7, 4, 3), Color("5a5a5a"))  # engine on its pole
	draw_line(Vector2(-22, -5), Vector2(-32, 1), Color("6a6a6a"), 1.0)
	draw_set_transform(Vector2.ZERO)
	draw_line(Vector2(-22, 0), Vector2(22, 0), Color(1, 1, 1, 0.15), 0.8)  # waterline


func _sandbags() -> void:
	var r := _rng()
	var khaki := Color("9a8a5a")
	for row in 2:
		for i in 3:
			var p := Vector2(-6 + i * 6 + (3 if row else 0) - 3, -2 - row * 3.2)
			draw_set_transform(p, r.randf_range(-0.1, 0.1), Vector2(1, 0.55))
			draw_circle(Vector2.ZERO, 3.4, khaki.darkened(r.randf() * 0.15))
			draw_set_transform(Vector2.ZERO)


func _barrier() -> void:
	_shadow(Vector2(8, 1.5))
	for x in [-6.0, 6.0]:
		draw_line(Vector2(x, 0), Vector2(x, -7), Color("5a5a5a"), 0.8)
	for i in 6:
		draw_rect(Rect2(-7 + i * 2.33, -7, 2.33, 2.5), Color("c83a2e") if i % 2 == 0 else Color("ece8e0"))


## An army truck left at the checkpoint.
func _army() -> void:
	var green := Color("4a5a3a")
	_shadow(Vector2(25, 3.5), Vector2(24, -1))
	draw_rect(Rect2(2, -12, 32, 9), green)  # canvas back
	draw_rect(Rect2(2, -12, 32, 2), green.lightened(0.12))
	for x in [10.0, 18.0, 26.0]:
		draw_line(Vector2(x, -12), Vector2(x, -3), green.darkened(0.25), 0.6)
	draw_rect(Rect2(34, -10, 12, 7), green.darkened(0.08))  # cab
	draw_rect(Rect2(38, -9, 6, 3), Color("2a323a"))
	draw_rect(Rect2(1, -4, 46, 2), Color("2a2a26"))
	for x in [8.0, 16.0, 40.0]:
		draw_circle(Vector2(x, -2.5), 3.0, Color("161616"))
		draw_circle(Vector2(x, -2.5), 1.1, Color("5a5a52"))
	draw_rect(Rect2(20, -9, 6, 3), Color("e8e4d0"))  # a sign taped on: "evacuation"
	draw_line(Vector2(21, -7.5), Vector2(25, -7.5), Color("c83a2e"), 0.6)
