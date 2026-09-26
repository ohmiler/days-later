class_name BikeArt
## How motorbikes look: seven models from today's Bangkok streets, drawn in
## code at their real size (about 1.9 m long) from the side, the front and
## the back, like the characters. Parked bikes (StreetProp) and ridden ones
## (Player) both draw through here. A rider sits between a bike's far and near
## parts, so `part` draws only one of them: "far", "near" or "all".
##
## Everything is drawn on `ci` under `xf` (the caller's transform: a turning
## squash, a lean), from the bike's ground point.

## The bikes on Bangkok's streets today, how common each is (out of 100), and
## the colours each comes in. A parked bike's model comes from its seed.
const BIKE_MODELS := [["wave", 30], ["click", 28], ["scoopy", 16], ["pcx", 12], ["ev", 6], ["sport", 4], ["trail", 4]]
const BIKE_COLORS := {
	wave = [Color("b8262a"), Color("1e1e22"), Color("2a5aa8"), Color("a8acb0"), Color("3a7a4a")],
	click = [Color("1e1e22"), Color("e8e6e0"), Color("b8262a"), Color("5a6068"), Color("2a5aa8")],
	scoopy = [Color("e8c8b0"), Color("a8d0c0"), Color("e8a8b8"), Color("f0e6c8"), Color("b8c8e0")],
	pcx = [Color("2a2c30"), Color("e8e6e0"), Color("6a7078"), Color("7a2a2a")],
	ev = [Color("eef0ee"), Color("3aa8a0"), Color("2a2c30")],
	sport = [Color("c8202a"), Color("1a1a1e"), Color("e8e8e8")],
	trail = [Color("c8202a"), Color("e8e8e8"), Color("2a8a3a")],
}


## Where a rider's hips, hands and feet go on each model, facing +x from the
## bike's ground point (see Rig anchors). Sports bikes put the feet back and
## the bars low; trail bikes sit tall.
const BIKE_SEATS := {
	wave = {seat = Vector2(-7, -15.5), bars = Vector2(7.5, -20.5), pegs = Vector2(0, -9.5)},
	click = {seat = Vector2(-7, -16), bars = Vector2(8, -22), pegs = Vector2(0.5, -10.5)},
	ev = {seat = Vector2(-7, -16), bars = Vector2(8, -22), pegs = Vector2(0.5, -10.5)},
	scoopy = {seat = Vector2(-8, -15.5), bars = Vector2(7.5, -21), pegs = Vector2(0, -10.5)},
	pcx = {seat = Vector2(-6, -17), bars = Vector2(7, -22.5), pegs = Vector2(1, -10.5)},
	sport = {seat = Vector2(-6.5, -16), bars = Vector2(6, -18.5), pegs = Vector2(-3, -9)},
	trail = {seat = Vector2(-5, -19), bars = Vector2(5, -23), pegs = Vector2(-1, -10)},
}


static func bike_model(seed_val: int) -> String:
	var r := (seed_val >> 4) % 100
	for m in BIKE_MODELS:
		r -= m[1]
		if r < 0:
			return m[0]
	return "wave"



## How far down the screen a point moves for each pixel it is toward the
## camera, in the 3/4 view (matches the characters and the city).
const DEPTH := 0.35

## Front and back: how wide the bits are, and what the headlamp looks like.
const ENDS := {
	wave = {shield = 8.5, rear = 7.0, bars = 6.0, lamp = "small"},
	click = {shield = 9.0, rear = 8.5, bars = 6.0, lamp = "led"},
	ev = {shield = 9.0, rear = 8.5, bars = 6.0, lamp = "led"},
	scoopy = {shield = 9.5, rear = 9.0, bars = 5.5, lamp = "round"},
	pcx = {shield = 11.0, rear = 10.0, bars = 6.5, lamp = "led", screen = true},
	sport = {shield = 8.5, rear = 6.0, bars = 5.0, lamp = "sport", screen = true},
	trail = {shield = 5.5, rear = 5.0, bars = 7.0, lamp = "plate"},
}


static func color_of(seed_val: int) -> Color:
	var cols: Array = BIKE_COLORS[bike_model(seed_val)]
	return cols[(seed_val >> 8) % cols.size()]


## Extras by seed: 0-1 a delivery box, 2 a front basket, 3 a win rider's vest.
static func extra_of(seed_val: int) -> int:
	return (seed_val >> 12) % 10


## A rider's anchors on this model seen from `view` ("side", "front", "back";
## side-on faces +x), for Rig.build.
static func rider_anchors(model: String, view := "side") -> Dictionary:
	var b: Dictionary = BIKE_SEATS.get(model, BIKE_SEATS.wave)
	if view == "side":
		return {seat = b.seat, hands = [b.bars + Vector2(-0.8, 0.3), b.bars], feet = [b.pegs + Vector2(-0.6, 0), b.pegs]}
	var e: Dictionary = ENDS.get(model, ENDS.wave)
	var k := DEPTH if view == "front" else -DEPTH
	var at := func(p: Vector2, x: float) -> Vector2: return Vector2(x, p.y + p.x * k)
	return {seat = at.call(b.seat, 0.0), hands = [at.call(b.bars, -e.bars), at.call(b.bars, e.bars)],
			feet = [at.call(b.pegs, -3.2), at.call(b.pegs, 3.2)]}


## Draw a bike. `v`: {seed, model?}; view "side" (dir +1 faces right),
## "front" (coming toward the camera) or "back" (going away).
static var wheel_turn := 0.0  # set for one draw: how far round the wheels have rolled (a ridden bike)
static var braking := false  # set for one draw: the brake light is on


static func draw(ci, seed_val: int, view: String, dir: float, part: String, xf := Transform2D.IDENTITY) -> void:
	var model := bike_model(seed_val)
	var col := color_of(seed_val)
	var extra := extra_of(seed_val)
	if part != "near":
		ci.draw_set_transform_matrix(xf * Transform2D(0, Vector2(1, 0.3 if view == "side" else 0.45), 0, Vector2.ZERO))
		ci.draw_circle(Vector2.ZERO, 15.0 if view == "side" else 6.0, Color(0, 0, 0, 0.3))
	if view == "side":
		if part == "near":
			return
		ci.draw_set_transform_matrix(xf * Transform2D(0, Vector2(dir, 1), 0, Vector2.ZERO))
		match model:
			"wave":
				_bike_wave(ci, col)
			"click":
				_bike_click(ci, col, true)
			"ev":
				_bike_click(ci, col, false)
			"scoopy":
				_bike_scoopy(ci, col)
			"pcx":
				_bike_pcx(ci, col)
			"sport":
				_bike_sport(ci, col)
			"trail":
				_bike_trail(ci, col)
		_extras_side(ci, model, extra)
	else:
		ci.draw_set_transform_matrix(xf)
		if view == "front":
			if part != "near":
				_front_far(ci, model, col, extra)
			if part != "far":
				_front_near(ci, model, col, extra)
		else:
			if part != "near":
				_back_far(ci, model, col, extra)
			if part != "far":
				_back_near(ci, model, col, extra)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _extras_side(ci, model: String, extra: int) -> void:
	if extra < 2 and model in ["wave", "click", "pcx"]:  # a delivery rider's box
		var bc := Color("2e9a4a") if extra == 0 else Color("e0782a")
		ci.draw_rect(Rect2(-15, -25, 9, 8.5), bc)
		ci.draw_rect(Rect2(-15, -25, 9, 1.5), bc.lightened(0.25))
		ci.draw_rect(Rect2(-13.5, -22, 6, 2.5), Color(1, 1, 1, 0.8))
	elif extra == 2 and model in ["wave", "scoopy"]:  # a wire basket on the front
		ci.draw_rect(Rect2(9, -23, 6, 4), Color("3a3c40"), false, 0.7)
		ci.draw_line(Vector2(11, -23), Vector2(11, -19), Color("3a3c40"), 0.5)
		ci.draw_line(Vector2(13, -23), Vector2(13, -19), Color("3a3c40"), 0.5)
	elif extra == 3 and model in ["wave", "click"]:  # a win rider's orange vest left on the seat
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-11, -16.5), Vector2(-5, -17), Vector2(-4, -14), Vector2(-10, -13.5)]),
				Color("e8782a"))


# --- Front and back ------------------------------------------------------------
# Seen end-on the bike is narrow: wheels are upright slivers, one nearer the
# camera (lower on screen) than the other. Coordinates: x across the bike, y
# up the screen as usual, and `z(l)` shifts a point `l` pixels along the bike
# (+ toward its front) by how much nearer or further that puts it.

static func _tyre(ci, y: float, r: float) -> void:
	ci.draw_rect(Rect2(-1.3, y - 2.0 * r, 2.6, 2.0 * r), Color("141414"))
	ci.draw_rect(Rect2(-0.5, y - 1.4 * r, 1.0, 0.8 * r), Color("5a5e62"))


static func _radius(model: String) -> float:
	return {sport = 5.0, trail = 6.0, pcx = 4.8}.get(model, 4.4)


static func _seat_y(model: String) -> float:
	return BIKE_SEATS.get(model, BIKE_SEATS.wave).seat.y


static func _bar_y(model: String) -> float:
	return BIKE_SEATS.get(model, BIKE_SEATS.wave).bars.y


## Coming toward the camera. Far: the back wheel, the seat and anything on
## the back. Near: the front wheel, leg shield, lamp and bars.
static func _front_far(ci, model: String, col: Color, extra: int) -> void:
	var e: Dictionary = ENDS[model]
	var back := -10.0 * DEPTH
	_tyre(ci, back, _radius(model))
	var sy := _seat_y(model) - 7.0 * DEPTH
	ci.draw_rect(Rect2(-e.rear * 0.5, sy + 1.0, e.rear, -sy - 7.0), col.darkened(0.1))
	ci.draw_rect(Rect2(-2.6, sy - 1.0, 5.2, 2.6), Color("1c1c1e"))
	if extra < 2 and model in ["wave", "click", "pcx"]:
		var bc := Color("2e9a4a") if extra == 0 else Color("e0782a")
		ci.draw_rect(Rect2(-4.5, sy - 10.5, 9, 8.5), bc.darkened(0.15))
		ci.draw_rect(Rect2(-4.5, sy - 10.5, 9, 1.5), bc.lightened(0.2))


static func _front_near(ci, model: String, col: Color, extra: int) -> void:
	var e: Dictionary = ENDS[model]
	var front := 11.0 * DEPTH
	var r := _radius(model)
	_tyre(ci, front, r)
	ci.draw_rect(Rect2(-2.0, front - 2.0 * r - 1.2, 4.0, 2.2), col.darkened(0.3))  # fender
	var by := _bar_y(model) + 7.0 * DEPTH
	var w: float = e.shield
	if model == "trail" or model == "sport":
		ci.draw_line(Vector2(-1.6, front - r), Vector2(-1.4, by + 3.0), Color("b8bcc0") if model == "trail" else Color("c8a030"), 0.9)
		ci.draw_line(Vector2(1.6, front - r), Vector2(1.4, by + 3.0), Color("b8bcc0") if model == "trail" else Color("c8a030"), 0.9)
	if model not in ["sport", "trail"]:  # the floorboards stick out either side
		ci.draw_rect(Rect2(-w * 0.5 - 1.0, -10.5 + 1.0, w + 2.0, 2.0), Color("26282c"))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5 + 0.8, by + 1.5), Vector2(w * 0.5 - 0.8, by + 1.5),
			Vector2(w * 0.5, front - 2.0 * r - 0.5), Vector2(-w * 0.5, front - 2.0 * r - 0.5)]), col)
	ci.draw_line(Vector2(w * 0.5 - 0.8, by + 1.8), Vector2(w * 0.5, front - 2.0 * r), col.darkened(0.25), 0.8)  # shaded edge
	var ly := by + 3.4
	match e.lamp:
		"led":
			ci.draw_rect(Rect2(-2.4, ly, 4.8, 0.9), Color("eef4ff"))
		"round":
			ci.draw_circle(Vector2(0, ly + 0.5), 1.6, Color("d8d8d0"))
			ci.draw_circle(Vector2(0, ly + 0.5), 1.1, Color("fff6d8"))
		"sport":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-2.6, ly), Vector2(-0.4, ly + 0.6), Vector2(-0.6, ly + 1.4), Vector2(-2.4, ly + 1.0)]), Color("f4eed0"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(2.6, ly), Vector2(0.4, ly + 0.6), Vector2(0.6, ly + 1.4), Vector2(2.4, ly + 1.0)]), Color("f4eed0"))
		"plate":
			ci.draw_rect(Rect2(-1.8, ly - 1.0, 3.6, 3.2), Color("e8e8e8"))
			ci.draw_rect(Rect2(-0.7, ly + 0.2, 1.4, 1.0), Color("f4eed0"))
		_:
			ci.draw_rect(Rect2(-1.2, ly, 2.4, 1.6), Color("f4eed0"))
	if e.get("screen", false):
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-2.4, by + 0.5), Vector2(2.4, by + 0.5), Vector2(1.8, by - 3.0), Vector2(-1.8, by - 3.0)]),
				Color(0.55, 0.65, 0.75, 0.55))
	if extra == 2 and model in ["wave", "scoopy"]:
		ci.draw_rect(Rect2(-2.8, by + 0.2, 5.6, 3.2), Color("3a3c40"), false, 0.6)
	_bars(ci, by, e.bars)


static func _bars(ci, by: float, half: float) -> void:
	ci.draw_line(Vector2(-half, by), Vector2(half, by), Color("1a1a1a"), 1.1)
	for side in [-1.0, 1.0]:
		ci.draw_line(Vector2(half * 0.75 * side, by), Vector2((half * 0.75 + 0.4) * side, by - 3.2), Color("3a3a3a"), 0.5)
		ci.draw_circle(Vector2((half * 0.75 + 0.5) * side, by - 3.4), 0.8, Color("5a6068"))


## Going away from the camera. Far: the front wheel and the bars. Near: the
## seat end, tail light, plate, the back wheel and anything on the back.
static func _back_far(ci, model: String, col: Color, extra: int) -> void:
	var e: Dictionary = ENDS[model]
	var front := -11.0 * DEPTH
	_tyre(ci, front, _radius(model))
	var by := _bar_y(model) - 7.0 * DEPTH
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-e.shield * 0.5 + 0.8, by + 1.5), Vector2(e.shield * 0.5 - 0.8, by + 1.5),
			Vector2(e.shield * 0.5, front - 9.0), Vector2(-e.shield * 0.5, front - 9.0)]), col.darkened(0.25))
	_bars(ci, by, e.bars)
	var sy := _seat_y(model) + 7.0 * DEPTH
	ci.draw_rect(Rect2(-2.6, sy - 1.0, 5.2, 2.6), Color("1c1c1e"))


static func _back_near(ci, model: String, col: Color, extra: int) -> void:
	var e: Dictionary = ENDS[model]
	var back := 10.0 * DEPTH
	var r := _radius(model)
	_tyre(ci, back, r)
	var sy := _seat_y(model) + 7.0 * DEPTH
	var top := sy + 1.5
	if model not in ["sport", "trail"]:
		ci.draw_rect(Rect2(-e.shield * 0.5 - 1.0, -10.5 - 1.0, e.shield + 2.0, 2.0), Color("26282c"))  # floorboards
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-e.rear * 0.5, top), Vector2(e.rear * 0.5, top),
			Vector2(e.rear * 0.35, back - 2.0 * r + 1.0), Vector2(-e.rear * 0.35, back - 2.0 * r + 1.0)]), col)
	ci.draw_rect(Rect2(-1.2, top + 0.4, 2.4, 1.2), Color("ff5040") if braking else Color("d8302a"))  # tail light
	if braking:
		ci.draw_circle(Vector2(0, top + 1.0), 3.0, Color(1, 0.25, 0.15, 0.35))
	ci.draw_rect(Rect2(-1.6, back - 2.0 * r + 1.6, 3.2, 1.8), Color("ecebe4"))  # plate
	if model != "ev":
		ci.draw_rect(Rect2(e.rear * 0.5 - 0.4, back - r - 2.0, 1.8, 3.0), Color("6a6e72"))  # exhaust, on the right
	if extra < 2 and model in ["wave", "click", "pcx"]:
		var bc := Color("2e9a4a") if extra == 0 else Color("e0782a")
		ci.draw_rect(Rect2(-4.5, sy - 9.0, 9, 8.5), bc)
		ci.draw_rect(Rect2(-4.5, sy - 9.0, 9, 1.5), bc.lightened(0.25))
		ci.draw_rect(Rect2(-3, sy - 6.0, 6, 2.5), Color(1, 1, 1, 0.8))


# --- Side-on, one function a model ------------------------------------------------

static func _wheel(ci, x: float, r: float, spokes := false) -> void:
	ci.draw_circle(Vector2(x, -r), r, Color("141414"))
	ci.draw_circle(Vector2(x, -r), r * 0.45, Color("8a8e92"))
	if spokes:
		for i in 4:
			var a := i * PI / 4
			ci.draw_line(Vector2(x, -r) + Vector2.from_angle(a) * r * 0.75, Vector2(x, -r) - Vector2.from_angle(a) * r * 0.75,
					Color("6a6e72"), 0.4)
	ci.draw_circle(Vector2(x, -r), r * 0.18, Color("2a2a2a"))
	# A scuff on the tyre that goes round as it rolls (only on a ridden bike).
	if wheel_turn != 0.0:
		ci.draw_circle(Vector2(x, -r) + Vector2.from_angle(wheel_turn) * r * 0.78, r * 0.13, Color("4a4a4a"))
		ci.draw_circle(Vector2(x, -r) + Vector2.from_angle(wheel_turn + PI) * r * 0.78, r * 0.13, Color("4a4a4a"))


static func _poly(ci, pts: Array, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array(pts), col)


static func _tail(ci, x: float, y: float) -> void:
	ci.draw_rect(Rect2(x, y, 1.4, 2), Color("ff5040") if braking else Color("d8302a"))
	if braking:
		ci.draw_circle(Vector2(x + 0.7, y + 1.0), 2.6, Color(1, 0.25, 0.15, 0.35))
	ci.draw_rect(Rect2(x - 0.4, y + 2.6, 2.2, 1.8), Color("ecebe4"))  # plate


static func _mirror(ci, x: float, y: float) -> void:
	ci.draw_line(Vector2(x, y), Vector2(x - 1, y - 3), Color("3a3a3a"), 0.6)
	ci.draw_circle(Vector2(x - 1, y - 3.2), 0.9, Color("5a6068"))


## Honda Wave: the underbone everyone's family rides. Open floor between the wheels.
static func _bike_wave(ci, col: Color) -> void:
	_wheel(ci, -10, 4.5)
	_wheel(ci, 11, 4.5)
	ci.draw_rect(Rect2(-14, -6.5, 8, 1.6), Color("6a6e72"))  # exhaust
	ci.draw_rect(Rect2(-7, -9.5, 6, 4.5), Color("3a3c40"))  # engine
	ci.draw_rect(Rect2(-3, -9, 9, 2), Color("26282c"))  # floor
	_poly(ci, [Vector2(-15.5, -10), Vector2(-12.5, -14.5), Vector2(-2.5, -13.5), Vector2(-1.5, -8.5), Vector2(-8, -8), Vector2(-14.5, -7.5)], col)
	ci.draw_line(Vector2(-14.8, -10.2), Vector2(-3, -12.6), col.lightened(0.25), 0.7)
	_tail(ci, -16.2, -12)
	_poly(ci, [Vector2(-13.5, -14.2), Vector2(-12.5, -16.4), Vector2(-3, -15.8), Vector2(-2, -13.6)], Color("1c1c1e"))
	_poly(ci, [Vector2(3.5, -8.5), Vector2(6.5, -8.5), Vector2(9.5, -18.5), Vector2(6, -19.5), Vector2(3, -11)], col)
	ci.draw_line(Vector2(8, -17), Vector2(11, -5), Color("7a7e82"), 1.2)
	_poly(ci, [Vector2(7.5, -9.5), Vector2(14.5, -8.5), Vector2(13.5, -10.5), Vector2(9, -11)], col.darkened(0.35))
	ci.draw_line(Vector2(4.5, -21), Vector2(10, -20.2), Color("1a1a1a"), 1.1)
	ci.draw_rect(Rect2(8.6, -19.6, 2.6, 2.2), col.lightened(0.1))
	ci.draw_rect(Rect2(10.6, -19.2, 1.2, 1.6), Color("f4eed0"))
	_mirror(ci, 6, -21)


## Honda Click and the electric scooters: an automatic whose body covers
## everything, a flat floor, a slim LED face. The electric one has no exhaust
## and a fat hub motor in the back wheel.
static func _bike_click(ci, col: Color, petrol: bool) -> void:
	_wheel(ci, -10, 4.3)
	_wheel(ci, 11, 4.3)
	if petrol:
		ci.draw_rect(Rect2(-15, -7, 8, 2), Color("5a5e62"))
		ci.draw_rect(Rect2(-15.5, -7.2, 2, 2.4), Color("8a8e92"))
	else:
		ci.draw_circle(Vector2(-10, -4.3), 2.8, Color("4a4e52"))  # hub motor
	_poly(ci, [Vector2(-16, -10.5), Vector2(-13, -15), Vector2(-3, -14), Vector2(-1, -9), Vector2(-9, -6.5), Vector2(-15, -7.5)], col)
	_poly(ci, [Vector2(-15, -8), Vector2(-9, -6.5), Vector2(-1, -9), Vector2(-1, -8), Vector2(-9, -5.5)], col.darkened(0.3))
	ci.draw_rect(Rect2(-3, -10, 8, 2.5), col.darkened(0.12))  # flat floor
	_tail(ci, -16.6, -12.5)
	_poly(ci, [Vector2(-14, -14.6), Vector2(-12.5, -17), Vector2(-3, -16.2), Vector2(-2, -14)], Color("1c1c1e"))
	_poly(ci, [Vector2(4, -7.5), Vector2(7.5, -7.5), Vector2(10.5, -19), Vector2(6.5, -20.5), Vector2(3.5, -10)], col)
	_poly(ci, [Vector2(8, -9), Vector2(14.5, -8.2), Vector2(13.5, -10), Vector2(9, -10.5)], col.darkened(0.3))
	ci.draw_line(Vector2(8.5, -17), Vector2(11, -5), Color("5a5e62"), 1.1)
	ci.draw_rect(Rect2(5, -22.5, 6.5, 2.4), col)  # bar cover
	ci.draw_line(Vector2(7, -21.4), Vector2(11.5, -21.6), Color("eef4ff"), 0.6)  # LED strip
	ci.draw_line(Vector2(4.5, -22), Vector2(3, -22.3), Color("1a1a1a"), 1.0)
	_mirror(ci, 6, -22.5)
	if not petrol:
		ci.draw_line(Vector2(-10, -12), Vector2(-7, -12.8), Color("5ad0ff"), 0.8)  # the blue stripe EVs wear


## Honda Scoopy: round and retro, pastel with a cream panel and a round lamp.
static func _bike_scoopy(ci, col: Color) -> void:
	_wheel(ci, -10, 4.3)
	_wheel(ci, 11, 4.3)
	ci.draw_rect(Rect2(-14.5, -6.8, 7, 1.8), Color("8a8e92"))
	var body := []
	for i in 13:
		var a := PI + i * PI / 12
		body.append(Vector2(-9, -9) + Vector2(cos(a) * 7, sin(a) * 5.5))
	_poly(ci, body, col)
	ci.draw_rect(Rect2(-16, -9.5, 14, 2.5), col)
	ci.draw_rect(Rect2(-3, -10, 8, 2.5), Color("efe6d4"))  # cream floor panel
	_tail(ci, -16.4, -11.5)
	_poly(ci, [Vector2(-14.5, -14), Vector2(-13, -16.5), Vector2(-3.5, -16), Vector2(-2.5, -13.8)], Color("6a4a32"))  # brown seat
	var front := []
	for i in 9:
		var a := -PI / 2 + i * PI / 8 * 0.9
		front.append(Vector2(6, -13) + Vector2(cos(a) * 4, sin(a) * 7))
	front.append(Vector2(4, -7.5))
	front.append(Vector2(3.5, -12))
	_poly(ci, front, col)
	_poly(ci, [Vector2(8, -9), Vector2(14.5, -8.2), Vector2(13.5, -10.5), Vector2(9, -11)], col)
	ci.draw_line(Vector2(8.5, -17), Vector2(11, -5), Color("9a9ea2"), 1.1)
	ci.draw_line(Vector2(4.5, -21.5), Vector2(10, -21), Color("d8d8d0"), 1.0)  # chrome bars
	ci.draw_circle(Vector2(9.5, -19), 1.9, Color("d8d8d0"))
	ci.draw_circle(Vector2(9.7, -19), 1.3, Color("fff6d8"))  # round lamp
	_mirror(ci, 5.5, -21.5)


## Honda PCX / Yamaha NMAX: the big scooter. Longer, a stepped seat, a
## tunnel down the middle of the floor, a tall front with a small screen.
static func _bike_pcx(ci, col: Color) -> void:
	_wheel(ci, -12, 4.8)
	_wheel(ci, 12, 4.8)
	ci.draw_rect(Rect2(-17, -7.5, 9, 2.2), Color("4a4e52"))
	ci.draw_rect(Rect2(-17.5, -7.8, 2, 2.8), Color("8a8e92"))
	_poly(ci, [Vector2(-18, -11), Vector2(-15, -16), Vector2(-4, -15), Vector2(-1, -9.5), Vector2(-11, -6.5), Vector2(-17, -8)], col)
	_poly(ci, [Vector2(-17, -8.5), Vector2(-11, -6.5), Vector2(-1, -9.5), Vector2(-1, -8.5), Vector2(-11, -5.5)], col.darkened(0.4))
	_poly(ci, [Vector2(-2, -9.5), Vector2(4, -9.5), Vector2(3, -12.5), Vector2(-1, -12.5)], col.darkened(0.15))  # tunnel
	_tail(ci, -18.6, -13.5)
	_poly(ci, [Vector2(-16, -15.8), Vector2(-15, -18.2), Vector2(-9, -17.8), Vector2(-8, -16.2), Vector2(-3, -16), Vector2(-2.5, -14.5)],
			Color("1c1c1e"))  # stepped seat
	_poly(ci, [Vector2(3.5, -8), Vector2(8, -8), Vector2(12, -20), Vector2(8, -22), Vector2(3.5, -11)], col)
	_poly(ci, [Vector2(8, -22), Vector2(10.5, -26), Vector2(12, -25.5), Vector2(11.5, -21)], Color(0.55, 0.65, 0.75, 0.55))  # screen
	_poly(ci, [Vector2(9, -9.5), Vector2(16, -9), Vector2(15, -11), Vector2(10, -11.5)], col.darkened(0.35))
	ci.draw_line(Vector2(10, -18), Vector2(12, -5), Color("5a5e62"), 1.3)
	ci.draw_line(Vector2(5, -22.5), Vector2(9, -22.8), Color("1a1a1a"), 1.1)
	ci.draw_line(Vector2(10.5, -19.5), Vector2(12.8, -18.5), Color("eef4ff"), 0.9)  # LED face
	_mirror(ci, 6, -23)


## A sports bike (Honda CBR): sharp fairing, tank, a high pointed tail,
## low bars. Rare, and loud.
static func _bike_sport(ci, col: Color) -> void:
	_wheel(ci, -11, 5, true)
	_wheel(ci, 12, 5, true)
	ci.draw_line(Vector2(-11, -5), Vector2(-1, -9), Color("3a3c40"), 1.4)  # swingarm
	ci.draw_rect(Rect2(-6, -11, 8, 5), Color("3a3c40"))  # engine
	_poly(ci, [Vector2(-7, -12), Vector2(-3, -15), Vector2(2, -14), Vector2(3, -8), Vector2(-5, -6.5)], col.darkened(0.2))
	_poly(ci, [Vector2(-17, -18), Vector2(-7, -15), Vector2(-5, -13.5), Vector2(-12, -14.5)], col)  # tail up high
	_poly(ci, [Vector2(-10, -16.5), Vector2(-5, -16.8), Vector2(-4, -15.2), Vector2(-9, -15)], Color("1c1c1e"))
	_poly(ci, [Vector2(-5, -16.5), Vector2(1, -18.5), Vector2(4, -16.5), Vector2(1, -14), Vector2(-4, -14.5)], col)  # tank
	_poly(ci, [Vector2(2, -9), Vector2(3, -17), Vector2(9, -20), Vector2(14, -15), Vector2(11, -10), Vector2(6, -8)], col)  # fairing
	_poly(ci, [Vector2(8, -20), Vector2(10, -22), Vector2(12, -18.5)], Color(0.5, 0.6, 0.7, 0.6))
	ci.draw_rect(Rect2(12, -15.8, 2, 1.2), Color("f4eed0"))
	ci.draw_line(Vector2(9, -16), Vector2(12, -5), Color("c8a030"), 1.3)  # gold forks
	_poly(ci, [Vector2(-8, -8), Vector2(-15, -12), Vector2(-15.5, -10.5), Vector2(-9, -7)], Color("8a8e92"))  # exhaust under the tail
	ci.draw_rect(Rect2(-17.4, -18, 1.4, 1.6), Color("d8302a"))


## A trail bike (Honda CRF): big thin wheels, a long travel fork, a high
## front fender and a flat seat. Rare.
static func _bike_trail(ci, col: Color) -> void:
	_wheel(ci, -11, 5.8, true)
	_wheel(ci, 12, 6.2, true)
	ci.draw_line(Vector2(-11, -5.8), Vector2(-2, -11), Color("3a3c40"), 1.3)
	ci.draw_rect(Rect2(-5, -12.5, 6, 5), Color("3a3c40"))
	ci.draw_line(Vector2(-3, -16), Vector2(6, -18), Color("2a2c30"), 1.2)  # frame
	_poly(ci, [Vector2(-16, -18.5), Vector2(-3, -17.5), Vector2(-2, -16), Vector2(-14, -16.8)], col)
	_poly(ci, [Vector2(-13, -19.5), Vector2(0, -19), Vector2(1, -17.5), Vector2(-12, -18)], Color("1c1c1e"))  # flat seat
	_poly(ci, [Vector2(-1, -17), Vector2(4, -20), Vector2(7, -18), Vector2(3, -14)], col)  # tank shrouds
	ci.draw_line(Vector2(7, -21), Vector2(12, -6.2), Color("b8bcc0"), 1.4)  # long fork
	_poly(ci, [Vector2(9, -15), Vector2(16, -15.5), Vector2(15, -14), Vector2(10, -13.8)], col)  # high fender
	ci.draw_rect(Rect2(5, -21.5, 3.5, 3.5), Color("e8e8e8"))  # number plate
	ci.draw_line(Vector2(4, -23), Vector2(9, -23), Color("1a1a1a"), 1.1)
	ci.draw_rect(Rect2(8, -20.5, 1.2, 1.4), Color("f4eed0"))
	ci.draw_line(Vector2(-6, -9), Vector2(-15, -14.5), Color("8a8e92"), 1.2)  # high pipe
	ci.draw_rect(Rect2(-16.8, -18.5, 1.4, 1.4), Color("d8302a"))


