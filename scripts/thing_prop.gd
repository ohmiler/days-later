class_name ThingProp
extends Node2D
## Draws one of the Things (see things.gd) and shows its state. Origin is the
## bottom of its cell, so it y-sorts with characters like furniture does.

var thing: Dictionary  # {id, kind, cell, state}
var _sound: AudioStreamPlayer2D
var _t := 0.0


func refresh() -> void:
	queue_redraw()
	if thing.kind == "radio":
		_radio_sound(thing.state.on)


func _process(delta: float) -> void:
	if thing.kind == "radio" and thing.state.on:
		_t += delta
		queue_redraw()  # the dial glows and sound rings go out


func _radio_sound(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if on and _sound == null:
		_sound = AudioStreamPlayer2D.new()
		var st: AudioStream = load("res://audio/ambience/radio_news.mp3").duplicate()
		if st is AudioStreamMP3:
			st.loop = true
		_sound.stream = st
		_sound.max_distance = 420.0
		_sound.volume_db = -4.0
		_sound.bus = "SFX"
		add_child(_sound)
	if _sound:
		if on and not _sound.playing:
			_sound.play(randf() * 30.0)
		elif not on:
			_sound.stop()


func _draw() -> void:
	var s: Dictionary = thing.state
	match thing.kind:
		"tap":
			# A sink on the back wall with a tap over it.
			draw_rect(Rect2(-6, -12, 12, 2), Color("c8c8c0"))
			draw_rect(Rect2(-5, -10, 10, 5), Color("a8aca8"))
			draw_rect(Rect2(-4, -9, 8, 3), Color("5a6a70") if s.water > 0 else Color("7a6a5a"))
			draw_line(Vector2(0, -16), Vector2(0, -12), Color("8a8e92"), 1.2)
			draw_line(Vector2(0, -16), Vector2(2.5, -16), Color("8a8e92"), 1.2)
			if s.water <= 0:
				draw_circle(Vector2(-2, -8), 1.0, Color(0.45, 0.25, 0.1, 0.8))  # rust where water used to sit
		"radio":
			draw_set_transform(Vector2(0, -1), 0, Vector2(1, 0.35))
			draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.3))
			draw_set_transform(Vector2.ZERO)
			draw_rect(Rect2(-5, -7, 10, 6), Color("5a4a3a"))
			draw_rect(Rect2(-4, -6, 4, 4), Color("2a2622"))  # speaker
			draw_rect(Rect2(1, -6, 3, 2), Color("e8c060") if s.on else Color("6a6250"))  # dial
			draw_line(Vector2(3, -7), Vector2(7, -14), Color("9a9a9a"), 0.6)  # aerial
			if s.on:
				for i in 2:
					var k := fmod(_t * 0.8 + i * 0.5, 1.0)
					draw_arc(Vector2(-2, -4), 4.0 + k * 10.0, -PI * 0.9, -PI * 0.1, 10, Color(1, 1, 1, 0.35 * (1.0 - k)), 0.8)
		"vending":
			draw_set_transform(Vector2(0, -1), 0, Vector2(1, 0.35))
			draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.3))
			draw_set_transform(Vector2.ZERO)
			var body := Color("2a62a8") if thing.id % 2 == 0 else Color("b8302a")
			draw_rect(Rect2(-6, -24, 12, 24), body)
			draw_rect(Rect2(-6, -24, 12, 2), body.lightened(0.2))
			draw_rect(Rect2(-5, -21, 7, 14), Color(0.75, 0.88, 0.95, 0.8) if not s.broken else Color("1a1e22"))
			if not s.broken:
				for row in 3:
					for col in 2:
						draw_rect(Rect2(-4 + col * 3, -20 + row * 4.5, 2, 3), [Color("e8a030"), Color("c83a2e"), Color("3a8a4a")][(row + col) % 3])
			else:
				draw_line(Vector2(-5, -21), Vector2(1, -12), Color(0.8, 0.9, 0.95, 0.6), 0.5)  # what is left of the glass
				draw_line(Vector2(2, -20), Vector2(-3, -9), Color(0.8, 0.9, 0.95, 0.6), 0.5)
			draw_rect(Rect2(3, -18, 2, 5), Color("1a1a1a"))  # coin slot
			draw_rect(Rect2(-5, -5, 10, 3), Color("141414"))  # the tray
