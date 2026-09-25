class_name Corpse
extends Node2D
## A body left on the ground: plays the fall, bleeds out, then fades away.
## How it died (`style`) decides what it loses on the way down:
##   behead  head flies off, blood pumps from the neck    (axe, machete)
##   arm     an arm comes away                            (axe, machete)
##   crush   skull caved in                               (bat, pipe, hammer, plank)
##   burst   head blown apart into pieces                 (a shot to the head)
##   stab, cut, blunt, fall: an ordinary fall, some more blood

const LIFE := 40.0
const SPURT_TIME := 1.6

var lk := {}  # look of the body (Look.draw's look dictionary)
var zombie := true
var fall_dir := 1.0
var style := ""
var t := 0.0
var spurts := false


func _ready() -> void:
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


func _process(delta: float) -> void:
	t += delta
	if t > LIFE:
		queue_free()
		return
	modulate.a = clampf((LIFE - t) / 4.0, 0.0, 1.0)
	if t < 3.0 or t > LIFE - 4.0:
		queue_redraw()


func _draw() -> void:
	var gory := style in ["behead", "arm", "burst", "crush"]
	Look.draw_blood_pool(self, fall_dir, clampf((t - 0.5) / 3.0, 0.0, 1.0) * (1.4 if gory else 1.0))
	if spurts:
		lk.spurt = clampf(1.0 - t / SPURT_TIME, 0.0, 1.0)
	Look.draw(self, {view = [Look.SIDE, fall_dir > 0], zombie = zombie, fall = clampf(t / 0.75, 0.001, 1.0), fall_dir = fall_dir}, lk)
