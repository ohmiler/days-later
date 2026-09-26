class_name Corpse
extends Node2D
## A body left on the ground: plays the fall and bleeds out, then rots: the
## skin darkens and the flies come (ROT), it goes to bones in a dark stain
## (BONES), and at last it's gone (GONE). Set alight (a zombie's, by the
## server: see Main.burn_corpse) it burns for BURN_TIME and leaves ash.
## How it died (`style`) decides what it loses on the way down:
##   behead  head flies off, blood pumps from the neck    (axe, machete)
##   arm     an arm comes away                            (axe, machete)
##   crush   skull caved in                               (bat, pipe, hammer, plank)
##   burst   head blown apart into pieces                 (a shot to the head)
##   stab, cut, blunt, fall: an ordinary fall, some more blood

const SPURT_TIME := 1.6
const ROT := 45.0  # seconds: fresh until then
const BONES := 150.0
const GONE := 300.0
const BURN_TIME := 14.0
const ASH_TIME := 60.0
const FADE := 10.0

var lk := {}  # look of the body (Look.draw's look dictionary)
var zombie := true
var fall_dir := 1.0
var style := ""
var t := 0.0
var spurts := false
var burn := -1.0  # seconds since it was set alight (-1: not burning)
var up := false  # on the floor upstairs (drawn a storey up)
var _redraw_t := 0.0
var _fx_t := 0.0
var _fx: Node2D  # the flies and flames, redrawn often; the body itself seldom
var _fx_on := false
var _light: PointLight2D


func _ready() -> void:
	_fx = Node2D.new()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	lk = lk.duplicate()
	lk.spurt_seed = randi() % 100
	if Look.low_gore and style in ["behead", "arm", "burst", "crush"]:
		style = "blunt"  # just falls
	if t > 0.0 or style == "":
		return
	var missing: int = lk.get("missing", 0)
	var up := Vector2(0, -20)
	match style:
		"behead":
			missing |= Look.LOST_HEAD
			_throw("head", up, 30.0, 70.0)
			spurts = true
		"arm":
			var bit := Look.LOST_ARM_R if not missing & Look.LOST_ARM_R else Look.LOST_ARM_L
			if missing & bit:
				style = "cut"  # nothing left to cut off
			else:
				missing |= bit
				_throw("arm", Vector2(0, -16), 40.0, 45.0)
				spurts = true
		"crush":
			lk.crushed = true
			_splat(6)
		"burst":
			missing |= Look.LOST_HEAD
			for i in 7:
				_throw("chunk", up, randf_range(25.0, 70.0), randf_range(40.0, 90.0), randf_range(-1.2, 1.2))
			_splat(10)
			spurts = true
		"stab", "cut":
			_splat(3)
	lk.missing = missing


## Throw a piece off the body: `speed` along the fall, `lift` up into the air.
func _throw(kind: String, from: Vector2, speed: float, lift: float, spread := 0.4) -> void:
	var g := Gib.new()
	g.kind = kind
	g.lk = lk
	g.position = position + Vector2(0, 1)
	g.h = -from.y
	var dir := Vector2(fall_dir, 0).rotated(randf_range(-spread, spread) * PI * 0.5)
	g.vel = Vector2(dir.x, dir.y * 0.6) * speed
	g.vh = lift
	g.spin = randf_range(6.0, 12.0) * (1 if randf() < 0.5 else -1)
	g.flip = fall_dir < 0
	g.z_index = z_index
	if get_parent().has_method("add_gib"):
		get_parent().add_gib.call_deferred(g)
	else:
		get_parent().add_child.call_deferred(g)


func _splat(n: int) -> void:
	if get_parent() and get_parent().has_method("splatter"):
		get_parent().splatter(position + Vector2(fall_dir * 8.0, 0), Vector2(fall_dir, 0), n)


func title() -> String:
	return "โครงกระดูก" if t > BONES else ("ศพเน่า" if t > ROT else "ศพ")


func _process(delta: float) -> void:
	t += delta
	# (A zombie's body goes when the server says: see Main.corpse_gone. Anyone
	# else's, left by a survivor who died, just goes in its own time.)
	var end := BURN_TIME + ASH_TIME if burn >= 0.0 else GONE
	var age := burn if burn >= 0.0 else t
	if burn >= 0.0:
		burn += delta
	if age > end:
		queue_free()
		return
	modulate.a = clampf((end - age) / FADE, 0.0, 1.0)
	if burn >= 0.0 and burn < BURN_TIME:
		_fire_light()
	elif _light:
		_light.queue_free()
		_light = null
	# The body is redrawn while it falls and bleeds (12 a second), then only as
	# it slowly rots or chars; the flies and flames on their own, 12 a second.
	_redraw_t -= delta
	var every := 1.0 / 12.0 if t < 3.0 else (0.5 if burn >= 0.0 and burn < BURN_TIME + 22.0 else 1.0)
	var busy := t < 3.0 or (t > ROT and t < BONES + 1.0) or (burn >= 0.0 and burn < BURN_TIME + 22.0)
	if busy and _redraw_t <= 0.0:
		_redraw_t = every
		queue_redraw()
	_fx_t -= delta
	var fx := (t > ROT and t < BONES and burn < 0.0) or (burn >= 0.0 and burn < BURN_TIME)
	if (fx or _fx_on) and _fx_t <= 0.0:
		_fx_t = 1.0 / 12.0
		_fx_on = fx
		_fx.queue_redraw()


func _fire_light() -> void:
	if _light == null:
		_light = PointLight2D.new()
		_light.texture = StreetProp._lamp_texture()
		_light.color = Color("ff9a40")
		_light.texture_scale = 0.8
		_light.position = Vector2(fall_dir * 12.0, -6)
		add_child(_light)
	_light.energy = 0.9 + sin(t * 17.0) * 0.15 + sin(t * 7.3) * 0.1


func _draw() -> void:
	# All of it in one batch: dozens of draw calls a body otherwise.
	var ci := MeshCanvas.new(self, Look.dot_tex())
	_draw_body(ci)
	ci.commit()


func _draw_body(ci: MeshCanvas) -> void:
	var lift := Vector2(0, -BuildingProp.GROUND_H if up else 0.0)
	ci.draw_set_transform(lift)
	var burnt := clampf(burn / BURN_TIME, 0.0, 1.0) if burn >= 0.0 else 0.0
	if burn >= BURN_TIME:
		_draw_ash(ci)
		return
	var gory := style in ["behead", "arm", "burst", "crush"]
	Look.draw_blood_pool(ci, fall_dir, clampf((t - 0.5) / 3.0, 0.0, 1.0) * (1.4 if gory else 1.0))
	if t > BONES and burn < 0.0:
		_draw_bones(ci)
		return
	if spurts:
		lk.spurt = clampf(1.0 - t / SPURT_TIME, 0.0, 1.0)
	# Rotting: the skin goes grey-green and dark, the clothes dull. Burning: charred.
	var rot := clampf((t - ROT) / (BONES - ROT), 0.0, 1.0)
	var body := lk
	if rot > 0.0 or burnt > 0.0:
		body = lk.duplicate()
		for key in ["skin", "shirt", "pants", "hair"]:
			if body.has(key):
				var col: Color = body[key]
				col = col.lerp(Color("4a5040") if key == "skin" else col.darkened(0.5), rot * (0.7 if key == "skin" else 0.5))
				body[key] = col.lerp(Color("1a1612"), burnt * 0.85)
	Look.lift = lift
	Look.draw(ci, {view = [Look.SIDE, fall_dir > 0], zombie = zombie, fall = clampf(t / 0.75, 0.001, 1.0), fall_dir = fall_dir}, body)
	Look.lift = Vector2.ZERO


func _draw_fx() -> void:
	var ci := MeshCanvas.new(_fx, Look.dot_tex())
	ci.draw_set_transform(Vector2(0, -BuildingProp.GROUND_H if up else 0.0))
	if t > ROT and t < BONES and burn < 0.0:
		_draw_flies(ci, clampf((t - ROT) / (BONES - ROT), 0.0, 1.0))
	elif burn >= 0.0 and burn < BURN_TIME:
		_draw_fire(ci)
	ci.commit()


## The flies over a rotting body.
func _draw_flies(ci: MeshCanvas, rot: float) -> void:
	var n := 2 + int(rot * 5)
	for i in n:
		var a := t * (3.0 + i * 0.7) + i * 2.1
		var p := Vector2(fall_dir * 12.0 + cos(a) * (6 + i % 3 * 3), -6 + sin(a * 1.3) * 3 - i % 2 * 3)
		ci.draw_circle(p, 0.6, Color(0.05, 0.05, 0.05, 0.9))


## Flames along the body, and the smoke going up from them.
func _draw_fire(ci: MeshCanvas) -> void:
	var k := 1.0 - absf(burn / BURN_TIME * 2.0 - 1.0) * 0.6  # (catching, roaring, dying down)
	for i in 7:
		var x := fall_dir * (2.0 + i * 3.6)
		var h := (6.0 + 5.0 * sin(t * 11.0 + i * 1.7) + 4.0 * sin(t * 5.3 + i)) * k + 4.0
		var wdt := 3.2
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - wdt, -1), Vector2(x + wdt, -1), Vector2(x + sin(t * 9.0 + i) * 1.5, -1 - h)]),
				Color(1.0, 0.45 + 0.2 * sin(t * 13.0 + i), 0.1, 0.9))
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - wdt * 0.5, -1), Vector2(x + wdt * 0.5, -1), Vector2(x, -1 - h * 0.6)]),
				Color(1.0, 0.9, 0.4, 0.95))
	for i in 5:
		var rise := fmod(t * 9.0 + i * 7.0, 34.0)
		ci.draw_circle(Vector2(fall_dir * (6.0 + i * 4.0) + sin(t + i) * 2.0, -10.0 - rise), 2.5 + rise * 0.12,
				Color(0.35, 0.33, 0.3, 0.35 * (1.0 - rise / 34.0)))


## What the fire leaves: ash and a few embers still glowing.
func _draw_ash(ci: MeshCanvas) -> void:
	ci.draw_set_transform(Vector2(fall_dir * 12.0, -1 - (BuildingProp.GROUND_H if up else 0.0)), 0, Vector2(1, 0.35))
	ci.draw_circle(Vector2.ZERO, 15.0, Color(0.08, 0.07, 0.06, 0.8))
	ci.draw_circle(Vector2(fall_dir * -3, 1), 10.0, Color(0.2, 0.19, 0.18, 0.8))
	ci.draw_set_transform(Vector2(0, -BuildingProp.GROUND_H if up else 0.0))
	var embers := clampf(1.0 - (burn - BURN_TIME) / 20.0, 0.0, 1.0)
	for i in 4:
		ci.draw_circle(Vector2(fall_dir * (4.0 + i * 5.0), -1.0 + (i % 2)), 0.9, Color(1.0, 0.45, 0.1, embers))


## Long rotted: bones lying in a dark stain.
func _draw_bones(ci: MeshCanvas) -> void:
	var bone := Color("d8d0bc")
	var f := fall_dir
	ci.draw_set_transform(Vector2(f * 12.0, -1 - (BuildingProp.GROUND_H if up else 0.0)), 0, Vector2(1, 0.35))
	ci.draw_circle(Vector2.ZERO, 16.0, Color(0.12, 0.08, 0.06, 0.55))
	ci.draw_set_transform(Vector2(0, -BuildingProp.GROUND_H if up else 0.0))
	ci.draw_line(Vector2(f * 4, -2), Vector2(f * 17, -2), bone, 1.2)  # spine
	for i in 4:
		var x := f * (9.0 + i * 2.2)
		ci.draw_line(Vector2(x, -4), Vector2(x, 0), bone, 0.8)  # ribs
	ci.draw_rect(Rect2(f * 2 - 2, -3.5, 4, 3), bone)  # pelvis
	ci.draw_line(Vector2(f * 2, -1), Vector2(f * -8, -1), bone, 1.0)  # legs
	ci.draw_line(Vector2(f * 2, -2), Vector2(f * -8, -3), bone, 1.0)
	if not lk.get("missing", 0) & Look.LOST_HEAD:
		ci.draw_circle(Vector2(f * 21, -2.5), 3.0, bone)  # skull
		ci.draw_circle(Vector2(f * 21.8, -2.8), 0.7, Color(0.1, 0.08, 0.06))
