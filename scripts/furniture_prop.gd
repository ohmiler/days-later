class_name FurnitureProp
extends Node2D
## A searchable piece of furniture inside a building. Origin is the bottom of
## its cell so it y-sorts with characters. Looks emptier once searched.

const SIZE := 8  # slots in every cupboard, fridge and shelf

## Tall furniture is drawn this much taller than its sketch, so wardrobes,
## fridges and shelves stand about as high as a person.
const TALL := {shelf = 1.4, fridge = 1.35, cabinet = 2.0, pantry = 1.4, toolchest = 1.2}

var data: Dictionary  # {id, kind, cell, table, long (a bed two cells long: 2 = down into the room, 1 = to the right, -1 left)}
## What taking each piece apart gives (see Crafting "strip").
const STRIP := {
	shelf = {scrap = 1, nails = 1}, fridge = {scrap = 2}, counter = {wood = 2, nails = 2},
	cabinet = {wood = 2, nails = 1}, table = {wood = 1, nails = 2}, crate = {wood = 2, nails = 2},
	bed = {wood = 2, rag = 2},
	glass = {scrap = 1}, mirror = {wood = 1, scrap = 1}, toolchest = {scrap = 2}, stall = {scrap = 2},
	safe = {scrap = 3}, pantry = {wood = 2, nails = 1}, sink = {scrap = 1},
}

var stripped := false  # taken apart for its wood and nails: only a wreck is left
var searched := false  # its loot has been rolled; after that it just holds what people leave in it
var items: Array = []  # server: SIZE entries of null or {id, n, hp}
var highlight := false


func set_searched(v: bool) -> void:
	searched = v
	queue_redraw()


func set_stripped(v: bool) -> void:
	stripped = v
	queue_redraw()


func set_highlight(v: bool) -> void:
	if highlight != v:
		highlight = v
		queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = data.id * 7919
	draw_set_transform(Vector2(0, -1), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 8, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0, Vector2(1, TALL.get(data.kind, 1.0)))
	match data.kind:
		"shelf":
			_box(Rect2(-7, -20, 14, 20), Color("8a8e92") if data.table != "clothes" else Color("8a6a48"))
			for row in 3:
				var y := -18.0 + row * 6.0
				draw_rect(Rect2(-6, y + 4, 12, 1), Color("5a5e62"))
				var n := 1 if searched else 4
				for i in n:
					if rng.randf() < 0.8:
						_goods(Vector2(-5.5 + i * 2.8 + rng.randf(), y + 1), rng)
		"glass":
			# A glass display counter: aluminium frame, what's for sale laid out inside.
			_box(Rect2(-8, -6, 16, 6), Color("6a5a4a"))
			var bed := Color("7a1a1a") if data.table == "valuables" else Color("e8e4dc")
			draw_rect(Rect2(-7.5, -12, 15, 6), bed)
			if not searched:
				for i in 4:
					var p := Vector2(-6.5 + i * 3.5, -10.5)
					match data.table:
						"valuables":
							draw_arc(p + Vector2(1, 1), 1.2, 0, PI, 5, Color("f0c840"), 0.7)
							draw_circle(p + Vector2(1, 2.4), 0.5, Color("f0c840"))
						"phone":
							draw_rect(Rect2(p, Vector2(1.8, 3)), Color("2a2c30"))
							draw_rect(Rect2(p + Vector2(0.3, 0.3), Vector2(1.2, 2)), Color("5a8ab8"))
						_:
							_goods(p, rng)
			draw_rect(Rect2(-7.5, -12, 15, 6), Color(0.75, 0.9, 0.95, 0.3))
			draw_line(Vector2(-6, -7), Vector2(-3, -11.5), Color(1, 1, 1, 0.4), 0.8)
			draw_rect(Rect2(-8, -12.5, 16, 1), Color("c8ccd0"))
			draw_rect(Rect2(-8, -12.5, 0.8, 12.5), Color("c8ccd0"))
			draw_rect(Rect2(7.2, -12.5, 0.8, 12.5), Color("a8acb0"))
			if searched:
				draw_line(Vector2(-2, -12), Vector2(3, -7), Color(1, 1, 1, 0.6), 0.5)  # smashed in
		"mirror":
			# A barber's station: a wide mirror on the wall, a counter of tools under it.
			draw_rect(Rect2(-8, -28, 16, 14), Color("4a4a4c"))
			draw_rect(Rect2(-7, -27, 14, 12), Color("9ab8c4") if not searched else Color("7a8a90"))
			draw_line(Vector2(-5, -17), Vector2(0, -26), Color(1, 1, 1, 0.35), 1.2)
			if searched:
				draw_line(Vector2(-2, -26), Vector2(3, -18), Color(0.2, 0.2, 0.2, 0.6), 0.5)
			_box(Rect2(-8, -10, 16, 10), Color("e8e4dc"))
			draw_rect(Rect2(-8, -11, 16, 1.5), Color("c8c4bc"))
			if not searched:
				for i in 4:
					draw_rect(Rect2(-6 + i * 3.2, -14, 1.6, 3), Color.from_hsv(rng.randf(), 0.5, 0.75))  # tonic, powder, spray
				draw_line(Vector2(3, -11.5), Vector2(6, -12.5), Color("c8ccd0"), 0.6)  # scissors
		"toolchest":
			# A red roll cabinet under a pegboard of spanners.
			draw_rect(Rect2(-8, -24, 16, 10), Color("8a7a5a"))
			if not searched:
				for i in 5:
					draw_line(Vector2(-6 + i * 3, -22), Vector2(-6 + i * 3 + rng.randf_range(-0.5, 0.5), -16 - rng.randf() * 2), Color("b8bcc0"), 0.7)
			_box(Rect2(-7, -13, 14, 13), Color("c83a2e"))
			for i in 4:
				draw_rect(Rect2(-6, -12 + i * 3, 12, 0.6), Color("8a2018"))
				draw_rect(Rect2(-1.5, -11 + i * 3, 3, 0.6), Color("d8d8d8"))
			if searched:
				draw_rect(Rect2(-6, -9, 12, 2.5), Color("2a1a18"))
		"stall":
			_draw_stall(rng)
		"safe":
			_box(Rect2(-6, -13, 12, 13), Color("3a4a40"))
			draw_rect(Rect2(-5, -12, 10, 11), Color("34443a"), false, 0.6)
			draw_circle(Vector2(0, -7), 2.2, Color("c8c4b8"))
			draw_circle(Vector2(0, -7), 1.2, Color("2a2a2a"))
			draw_rect(Rect2(3, -8, 1, 3), Color("c8c4b8"))
			if searched:
				draw_rect(Rect2(-5, -12, 3, 11), Color("1a1a1a"))  # door hanging open
		"pantry":
			# Tu kap khao: a wooden food cupboard on legs, fly-screen doors.
			_box(Rect2(-7, -16, 14, 13), Color("8a6a48"))
			for i in 2:
				var r := Rect2(-6 + i * 6.5, -15, 5.5, 10)
				draw_rect(r, Color("5a6a62") if not searched else Color("2a2622"))
				for gy in range(1, 10, 2):
					draw_line(r.position + Vector2(0, gy), r.position + Vector2(5.5, gy), Color(0, 0, 0, 0.2), 0.3)
			for x in [-6.5, 5.5]:
				draw_rect(Rect2(x, -3, 1, 3), Color("6a4a30"))
		"sink":
			_box(Rect2(-8, -10, 16, 10), Color("c8c4bc"))
			draw_rect(Rect2(-8, -11, 16, 2), Color("d8dcdc"))
			draw_rect(Rect2(-6, -11, 8, 2), Color("8a8e92"))  # the basin
			draw_line(Vector2(-2, -11), Vector2(-2, -15), Color("b8bcc0"), 0.8)  # tap
			draw_line(Vector2(-2, -15), Vector2(-4, -14), Color("b8bcc0"), 0.8)
			if not searched:
				draw_circle(Vector2(5, -12), 1.5, Color("e8e2d4"))  # a stack of plates
				draw_circle(Vector2(5, -13), 1.5, Color("f0ece4"))
		"fridge":
			_box(Rect2(-7, -21, 14, 21), Color("d8dcdc"))
			draw_rect(Rect2(-5.5, -19, 11, 15), Color(0.6, 0.8, 0.85, 0.8) if not searched else Color("5a6a6e"))
			if not searched:
				for i in 4:
					draw_rect(Rect2(-4.5 + i * 2.6, -12, 1.6, 5), Color.from_hsv(rng.randf(), 0.6, 0.8))
			draw_rect(Rect2(-7, -4, 14, 4), Color("3a6ac8"))
		"counter":
			_box(Rect2(-8, -10, 16, 10), Color("7a5a3e"))
			draw_rect(Rect2(-8, -11, 16, 2), Color("b8a888"))
			draw_rect(Rect2(1, -15, 5, 4), Color("2e2e30"))  # cash register
			draw_rect(Rect2(1.5, -14.5, 4, 1.5), Color("6ac86a"))
			if searched:
				draw_rect(Rect2(-7, -7, 7, 3), Color("3a2a1e"))  # drawer pulled out
		"cabinet":
			_box(Rect2(-7, -13, 14, 13), Color("8a6a48"))
			for i in 2:
				var y := -12.0 + i * 6.0
				draw_rect(Rect2(-6, y, 12, 5), Color("7a5a3a"))
				draw_rect(Rect2(-1, y + 2, 2, 1), Color("c8b070"))
			if searched:
				draw_rect(Rect2(-6, -8, 12, 3), Color("3a2a1a"))
		"table":
			draw_rect(Rect2(-7, -8, 14, 2), Color("9a7a5a"))
			draw_rect(Rect2(-6, -6, 1.5, 6), Color("6a4a30"))
			draw_rect(Rect2(4.5, -6, 1.5, 6), Color("6a4a30"))
			if not searched:
				draw_circle(Vector2(-2, -9), 1.6, Color("e8e2d4"))
				draw_rect(Rect2(1, -10.5, 3, 2.5), Color.from_hsv(rng.randf(), 0.5, 0.7))
		"crate":
			_box(Rect2(-7, -9, 14, 9), Color("a8885a"))
			draw_line(Vector2(-7, -9), Vector2(7, 0), Color("7a603c"), 1.0)
			draw_line(Vector2(7, -9), Vector2(-7, 0), Color("7a603c"), 1.0)
			if searched:
				draw_rect(Rect2(-7, -11, 14, 2), Color("7a603c"))  # lid knocked off
		"bed":
			# Seen from above at an angle: the mattress top, then the frame's front.
			var long: int = data.get("long", 0)
			if long == 2:  # down the room, headboard on the back wall; origin at the foot
				draw_rect(Rect2(-7, -29, 14, 26), Color("d8d0c0") if not searched else Color("b8a890"))
				draw_rect(Rect2(-7, -3, 14, 3), Color("6a4a30"))
				draw_rect(Rect2(-7, -31, 14, 3), Color("5a3a24"))  # headboard
				draw_rect(Rect2(-5, -28, 10, 5), Color("f0ece4"))  # pillow
				draw_rect(Rect2(-7, -19, 14, 16), Color.from_hsv(rng.randf(), 0.35, 0.6))  # blanket
				draw_rect(Rect2(-7, -19, 14, 1.5), Color(0, 0, 0, 0.15))
				draw_set_transform(Vector2.ZERO)
				if stripped:
					draw_rect(Rect2(-7, -31, 14, 31), Color(0.1, 0.08, 0.06, 0.55))
				if highlight and not searched:
					draw_rect(Rect2(-9, -32, 18, 33), Color(1, 0.9, 0.5, 0.8), false, 0.8)
				return
			var x0 := bed_left()
			var w := 32.0 if long != 0 else 16.0
			draw_rect(Rect2(x0, -13, w, 10), Color("d8d0c0") if not searched else Color("b8a890"))
			draw_rect(Rect2(x0, -3, w, 3), Color("6a4a30"))
			draw_rect(Rect2(x0, -15, 2, 15), Color("5a3a24"))  # headboard
			draw_rect(Rect2(x0 + 2.5, -12, 6, 8), Color("f0ece4"))  # pillow
			if long != 0:
				draw_rect(Rect2(x0 + 12, -13, w - 12, 10), Color.from_hsv(rng.randf(), 0.35, 0.6))  # blanket
				draw_rect(Rect2(x0 + 12, -13, 1.5, 10), Color(0, 0, 0, 0.15))
	draw_set_transform(Vector2.ZERO)
	if stripped:  # pulled apart: dark, with the boards gone
		var h2: float = 18.0 * TALL.get(data.kind, 1.0)
		draw_rect(Rect2(-8, -h2, 16, h2), Color(0.1, 0.08, 0.06, 0.55))
		draw_line(Vector2(-6, -h2 + 2), Vector2(5, -3), Color(0, 0, 0, 0.5), 1.0)
		draw_line(Vector2(5, -h2 + 4), Vector2(-4, -6), Color(0, 0, 0, 0.4), 1.0)
	if highlight and not searched:
		var h: float = 23.0 * TALL.get(data.kind, 1.0)
		var r := Rect2(bed_left() - 1 if data.kind == "bed" else -9, -h, 34 if data.get("long", 0) != 0 else 18, h + 1)
		draw_rect(r, Color(1, 0.9, 0.5, 0.8), false, 0.8)


## Something for sale on a shelf, looking like what the shop sells.
func _goods(p: Vector2, rng: RandomNumberGenerator) -> void:
	match data.table:
		"med":  # medicine boxes: white with a coloured band
			draw_rect(Rect2(p, Vector2(2.2, 3)), Color("f0ece4"))
			draw_rect(Rect2(p + Vector2(0, 1), Vector2(2.2, 0.8)), Color.from_hsv(rng.randf(), 0.6, 0.8))
		"clothes":  # bolts of cloth, silk bright
			draw_rect(Rect2(p + Vector2(0, 0.5), Vector2(2.4, 2.5)), Color.from_hsv(rng.randf(), 0.65, 0.75))
			draw_circle(p + Vector2(1.2, 1.7), 0.5, Color(0, 0, 0, 0.25))
		"tools":  # paint tins and boxes of screws
			draw_rect(Rect2(p + Vector2(0, 0.5), Vector2(2.2, 2.5)), Color.from_hsv(rng.randf(), 0.3, 0.6))
			draw_rect(Rect2(p + Vector2(0, 0.5), Vector2(2.2, 0.6)), Color("b8bcc0"))
		"phone":  # phone cases hanging on hooks
			draw_rect(Rect2(p + Vector2(0.3, 0), Vector2(1.6, 3)), Color.from_hsv(rng.randf(), 0.7, 0.85))
		"barber":  # bottles of hair tonic
			draw_rect(Rect2(p + Vector2(0.4, 0.8), Vector2(1.4, 2.2)), Color.from_hsv(rng.randf(), 0.5, 0.7))
			draw_rect(Rect2(p + Vector2(0.7, 0), Vector2(0.8, 0.8)), Color("e8e4dc"))
		_:
			draw_rect(Rect2(p, Vector2(2.2, 3)), Color.from_hsv(rng.randf(), 0.5, 0.75))


## The cart at the front of an eatery, dressed for what it cooks: chickens
## hanging in the glass for khao man gai, the noodle pot for kuay tiew, a clay
## mortar for som tam, a coffee sock for old-style coffee.
func _draw_stall(rng: RandomNumberGenerator) -> void:
	_box(Rect2(-8, -10, 16, 10), Color("b8bcc0"))
	draw_rect(Rect2(-8, -10, 16, 1.2), Color("d8dcdc"))
	var glass := Rect2(-7, -18, 11, 8)
	draw_rect(glass, Color("f0ece0"))
	var full := not searched
	match data.get("sign", ""):
		"ข้าวมันไก่":
			if full:
				for i in 3:
					draw_set_transform(Vector2(-5 + i * 3.5, -14.5), 0, Vector2(0.8, 1.2))
					draw_circle(Vector2.ZERO, 1.5, Color("e8b85a"))
					draw_set_transform(Vector2.ZERO, 0, Vector2(1, TALL.get(data.kind, 1.0)))
					draw_line(Vector2(-5 + i * 3.5, -18), Vector2(-5 + i * 3.5, -16.5), Color("6a6a6a"), 0.4)
			draw_rect(Rect2(4.5, -14, 3.5, 4), Color("c8ccd0"))  # the rice pot
		"ก๋วยเตี๋ยวเรือ", "โจ๊ก ข้าวต้ม":
			draw_rect(Rect2(3.5, -16, 5, 6), Color("b8bcc0"))  # the big broth pot
			draw_rect(Rect2(3.5, -16, 5, 1), Color("d8dcdc"))
			if full:
				for i in 3:
					draw_rect(Rect2(-6 + i * 3, -13, 2.4, 2.5), Color("f0e6c8"))  # bundles of noodles
		"ส้มตำ ไก่ย่าง":
			draw_rect(Rect2(3.5, -13, 4.5, 3), Color("8a5a3a"))  # clay mortar
			draw_line(Vector2(6, -13), Vector2(7.5, -17), Color("b89a6a"), 0.9)
			if full:
				for i in 3:
					draw_line(Vector2(-6 + i * 3, -11), Vector2(-4 + i * 3, -16), Color("b89a6a"), 0.4)  # chicken on sticks
					draw_circle(Vector2(-5 + i * 3, -14), 1.1, Color("a8502a"))
		"กาแฟโบราณ":
			draw_line(Vector2(5, -17), Vector2(5, -13), Color("6a6a6a"), 0.5)  # the coffee sock on its hoop
			draw_circle(Vector2(5, -12.5), 1.5, Color("6a4a30"))
			draw_rect(Rect2(3, -12, 5, 2), Color("c8ccd0"))  # the kettle
			if full:
				for i in 4:
					draw_rect(Rect2(-6 + i * 2.4, -12.5, 1.6, 2), Color("e8e4dc"))  # glasses
		_:  # a wok on a gas ring
			draw_circle(Vector2(5.5, -12), 2.2, Color("2a2a2a"))
			if full:
				for i in 3:
					draw_rect(Rect2(-6 + i * 3, -12.5, 2.4, 2), Color.from_hsv(rng.randf(), 0.5, 0.7))  # trays of ingredients
	draw_rect(glass, Color(0.75, 0.9, 0.95, 0.25))
	draw_rect(glass, Color("c8ccd0"), false, 0.6)


## A bed's left edge (the headboard end), from the origin: a long bed that
## took the cell to its left starts a cell further over.
func bed_left() -> float:
	return -24.0 if data.get("long", 0) == -1 else -8.0


## Box with a lit top edge and a darker right side.
func _box(r: Rect2, col: Color) -> void:
	draw_rect(r, col)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1.5)), col.lightened(0.2))
	draw_rect(Rect2(r.end.x - 2, r.position.y, 2, r.size.y), col.darkened(0.2))
	if searched:
		draw_rect(r, Color(0, 0, 0, 0.12))
