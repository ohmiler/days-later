class_name StreetProp
extends Node2D
## Small street objects in 3/4 view: power poles with lamps, cars, taxis,
## tuk-tuks, motorbikes, food carts, rubbish and skytrain pillars.
## Origin is where the object meets the ground, for y-sorting.

static var _glow_tex: Texture2D

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


func _shadow(size: Vector2, offset := Vector2.ZERO) -> void:
	draw_set_transform(offset, 0, Vector2(1, size.y / size.x))
	draw_circle(Vector2.ZERO, size.x, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)


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


func _car_side() -> void:
	var col: Color = data.color
	var taxi: bool = data.kind == "taxi"
	_shadow(Vector2(17, 3), Vector2(16, -1))
	var body := PackedVector2Array([Vector2(1, -3), Vector2(31, -3), Vector2(31, -8), Vector2(26, -10), Vector2(3, -10), Vector2(1, -8)])
	draw_polygon(body, PackedColorArray([col.darkened(0.3), col.darkened(0.3), col, col.lightened(0.1), col.lightened(0.1), col]))
	var cabin := PackedVector2Array([Vector2(7, -10), Vector2(24, -10), Vector2(21, -16), Vector2(10, -16)])
	draw_colored_polygon(cabin, col.lightened(0.05))
	draw_colored_polygon(PackedVector2Array([Vector2(8.5, -10.5), Vector2(15, -10.5), Vector2(15, -15.2), Vector2(10.7, -15.2)]), Color("2a323a"))
	draw_colored_polygon(PackedVector2Array([Vector2(16, -10.5), Vector2(22.5, -10.5), Vector2(20.4, -15.2), Vector2(16, -15.2)]), Color("2a323a"))
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
