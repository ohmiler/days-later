class_name Gib
extends Node2D
## A piece knocked off a body (a head, an arm, a lump of flesh): flies off in an
## arc, bounces, leaves blood where it lands, and fades away like a corpse.
## Purely visual; every peer throws its own.

const LIFE := 40.0
const GRAVITY := 260.0

var kind := "chunk"  # "head", "arm" or "chunk"
var lk := {}  # look of the body it came from (skin, shirt, hair, hair_style, wear)
var vel := Vector2.ZERO  # along the ground
var h := 0.0  # height above the ground
var vh := 0.0
var spin := 0.0
var rot := 0.0
var flip := false
var t := 0.0
var landed := false
var pool := 0.0


func _process(delta: float) -> void:
	t += delta
	if t > LIFE:
		queue_free()
		return
	if not landed:
		position += vel * delta
		h += vh * delta
		vh -= GRAVITY * delta
		rot += spin * delta
		if h <= 0.0:
			h = 0.0
			if vh < -50.0:
				vh = -vh * 0.3  # one bounce
				vel *= 0.45
				spin *= 0.4
				_splat(2)
			else:
				landed = true
				vh = 0.0
				_splat(3)
	else:
		pool = minf(1.0, pool + delta * 0.4)
	modulate.a = clampf((LIFE - t) / 4.0, 0.0, 1.0)
	queue_redraw()


func _splat(n: int) -> void:
	if get_parent().has_method("splatter"):
		get_parent().splatter(position, vel.normalized(), n)


func _draw() -> void:
	if kind != "chunk":
		draw_set_transform(Vector2(0, -0.5), 0, Vector2(1.2, 0.45))
		draw_circle(Vector2.ZERO, 1.5 + 3.5 * pool, Color(0.28, 0.02, 0.02, 0.7))  # it keeps bleeding where it lies
	draw_set_transform(Vector2(0, 0.5), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 3.0 if kind != "chunk" else 1.4, Color(0, 0, 0, 0.3 * clampf(1.0 - h / 40.0, 0.2, 1.0)))
	draw_set_transform(Vector2(0, -h - 2.0), rot, Vector2(-1 if flip else 1, 1))
	var skin: Color = lk.get("skin", Look.ZOMBIE_SKINS[0])
	match kind:
		"head":
			# Drawn around its own centre, with the torn neck underneath.
			Look._head(self, Look.SIDE, Vector2.ZERO, skin, lk.get("hair", Look.HAIRS[0]), lk.get("hair_style", "short"),
					true, true, lk.get("wear", {}).get("head", {}), 0.6, false)
			draw_rect(Rect2(-1.2, 3.4, 2.4, 1.2), skin.darkened(0.25))
			draw_circle(Vector2(0, 4.6), 1.3, Look.BLOOD)
		"arm":
			var sleeve: Color = (lk.get("shirt", Look.SHIRTS[0]) as Color).darkened(0.1)
			Look._arm(self, Vector2(0, -4.0), Vector2(0.3, 0.2), Vector2(0.4, 4.2), sleeve, skin.darkened(0.1), false,
					lk.get("long_sleeves", false))
			draw_circle(Vector2(0, -4.0), 1.5, Look.BLOOD)
			draw_circle(Vector2(0, -4.0), 0.6, Color("d8d0c0"))
		_:
			var c := Look.BLOOD if int(spin) % 2 == 0 else skin.darkened(0.3)
			draw_colored_polygon(PackedVector2Array([Vector2(-1.4, -0.6), Vector2(0.2, -1.4), Vector2(1.5, -0.2),
					Vector2(0.6, 1.2), Vector2(-1.0, 1.0)]), c)
			draw_circle(Vector2(0.2, 0), 0.6, Look.BLOOD_DARK)
