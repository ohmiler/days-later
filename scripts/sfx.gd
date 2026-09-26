class_name Sfx
## Sound effects. Real recordings live in res://audio/sfx as <name>_<n>.ogg and
## one variant is picked at random each time; names with no files fall back to
## a sound synthesised here in code. See audio/CREDITS.md for where they came from.
## Sfx.play(parent, "hit", position) plays one positioned in the world.

const RATE := 22050
const DIR := "res://audio/sfx/"
## Names that share another name's recordings.
const ALIASES := {"break": "crunch"}

static var _cache := {}  # name -> Array of streams


## Mixer buses, so the pause menu can turn music, ambience and effects up or down on their own.
static func setup_buses() -> void:
	for bus in ["SFX", "Ambience", "Music"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


## Hear the world through a helmet: effects and ambience dulled and quieter.
static func set_muffled(on: bool) -> void:
	for bus in ["SFX", "Ambience"]:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		if AudioServer.get_bus_effect_count(i) == 0:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 900.0
			AudioServer.add_bus_effect(i, lp)
		AudioServer.set_bus_effect_enabled(i, 0, on)


static func play(parent: Node, name: String, pos: Vector2, volume_db := 0.0, pitch := 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = stream(name)
	p.position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	p.max_distance = 700
	p.attenuation = 1.5
	p.bus = "SFX"
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## A sound with no place in the world (menu clicks).
static func play_ui(parent: Node, name: String, volume_db := -6.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream(name)
	p.volume_db = volume_db
	p.bus = "SFX"
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


static func stream(name: String) -> AudioStream:
	if not _cache.has(name):
		var files := []
		var base: String = ALIASES.get(name, name)
		for i in 40:
			for ext in [".ogg", ".wav"]:  # (.wav: sounds made in code, like the gunshots)
				var path := DIR + "%s_%d%s" % [base, i, ext]
				if ResourceLoader.exists(path):
					files.append(load(path))
		if ResourceLoader.exists(DIR + base + ".ogg"):
			files.append(load(DIR + base + ".ogg"))
		if files.is_empty():
			files.append(_build(name))
		_cache[name] = files
	return _cache[name].pick_random()


## A sound that goes round and round (an engine), made in code; play it with
## pitch_scale for how fast it's running.
static func loop(name: String) -> AudioStreamWAV:
	var key := "loop:" + name
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(name)
		var samples := _engine(rng, 30.0) if name == "engine" else _motor(rng, 180.0)
		var w := _to_wav(samples)
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
		_cache[key] = [w]
	return _cache[key][0]


## One second of a small single-cylinder engine: a thud of noise and body
## each time it fires (`f` times a second, a whole number so it loops cleanly).
static func _engine(rng: RandomNumberGenerator, f: float) -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var amp := 1.0
	var last := -1
	for i in n:
		var t := float(i) / RATE * f
		var cyc := int(t)
		if cyc != last:
			last = cyc
			amp = rng.randf_range(0.8, 1.0)
		var ph := t - cyc
		y += (rng.randf_range(-1, 1) - y) * 0.25
		var kick := exp(-ph * 7.0)
		out[i] = (sin(TAU * ph * 2.0) * 0.55 + sin(TAU * ph * 5.0) * 0.15 + y * 0.6) * kick * amp * 0.55
	return out


## One second of an electric motor's whine (`f` a whole number, to loop).
static func _motor(rng: RandomNumberGenerator, f: float) -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1, 1) - y) * 0.05
		out[i] = sin(TAU * f * t) * 0.3 + sin(TAU * f * 2.0 * t) * 0.12 + y * 0.2
	return out


static func _build(name: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var samples := PackedFloat32Array()
	match name:
		"swing":  # whoosh: filtered noise swelling and fading
			samples = _noise_sweep(rng, 0.18, 0.08, 0.35, 0.5)
		"punch":
			samples = _noise_sweep(rng, 0.12, 0.12, 0.4, 0.35)
		"hit":  # body blow: low thump plus a slap of noise
			samples = _thump(rng, 0.2, 95.0, 55.0, 0.7)
		"kick":
			samples = _thump(rng, 0.26, 75.0, 40.0, 0.9)
		"blade":
			samples = _thump(rng, 0.16, 140.0, 90.0, 0.5)
			_mix(samples, _noise_sweep(rng, 0.16, 0.6, 0.9, 0.35))
		"gore":  # something coming off: a wet, heavy chop
			samples = _thump(rng, 0.3, 60.0, 35.0, 1.0)
			_mix(samples, _noise_sweep(rng, 0.28, 0.25, 0.05, 0.55))
		"crunch":  # a skull giving way
			samples = _thump(rng, 0.2, 180.0, 55.0, 0.8)
			_mix(samples, _noise_sweep(rng, 0.12, 0.9, 0.4, 0.55))
		"groan":
			samples = _groan(rng, 0.9)
		"rustle":  # rummaging through a shelf
			samples = _rustle(rng, 0.7)
		"pickup":
			samples = _tone(0.07, 660.0, 0.35)
			samples.append_array(_tone(0.09, 990.0, 0.35))
		"eat":
			samples = _rustle(rng, 0.35)
		"scream":  # a screamer calling the others
			samples = _sweep_tone(rng, 1.1, 700.0, 1300.0, 0.45)
		"siren":  # horde warning drifting over the city
			samples = _siren(2.6)
		"crash":  # a bike into a wall: a heavy thud and bent metal ringing
			samples = _thump(rng, 0.5, 90.0, 45.0, 0.9)
			_mix(samples, _noise_sweep(rng, 0.35, 0.9, 0.2, 0.5))
			for f in [410.0, 623.0, 947.0]:
				var ring := _tone(0.5, f, 0.12)
				for i in ring.size():
					ring[i] *= exp(-float(i) / RATE * 7.0)
				_mix(samples, ring)
		"shutter":  # a steel shutter rattling up or down its rails
			var n := int(0.9 * RATE)
			samples.resize(n)
			var y := 0.0
			for i in n:
				var t := float(i) / n
				var slat := fmod(t * 0.9 * 34.0, 1.0)  # a clack per slat going round the roll
				y += (rng.randf_range(-1, 1) - y) * 0.6
				var ring := sin(TAU * 820.0 * i / RATE) * 0.25 + sin(TAU * 1230.0 * i / RATE) * 0.15
				var env := clampf(t / 0.05, 0, 1) * clampf((1.0 - t) / 0.15, 0, 1)
				samples[i] = (y * 0.7 + ring) * exp(-slat * 9.0) * env * 0.6
			for i in int(0.15 * RATE):  # and it hits the ground (or the top of the box)
				samples[n - int(0.15 * RATE) + i] += sin(TAU * 60.0 * i / RATE) * exp(-float(i) / RATE * 25.0) * 0.8
		"alarm":  # a car alarm: two tones, back and forth
			var n := int(0.95 * RATE)
			samples.resize(n)
			var phase := 0.0
			for i in n:
				var t := float(i) / RATE
				var f := 1250.0 if int(t * 8.0) % 2 == 0 else 880.0
				phase += TAU * f / RATE
				samples[i] = (1.0 if sin(phase) > 0.0 else -1.0) * 0.22 * clampf((0.95 - t) / 0.05, 0.0, 1.0)
		"door":  # fist and shoulder against wood
			samples = _thump(rng, 0.22, 120.0, 70.0, 0.8)
		"break":
			samples = _thump(rng, 0.12, 300.0, 150.0, 0.4)
			_mix(samples, _noise_sweep(rng, 0.12, 0.8, 1.0, 0.6))
	return _to_wav(samples)


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> void:
	for i in mini(a.size(), b.size()):
		a[i] += b[i]


## Noise through a one-pole filter whose brightness moves from c0 to c1.
static func _noise_sweep(rng: RandomNumberGenerator, length: float, c0: float, c1: float, gain: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		var cut := lerpf(c0, c1, t)
		y += (rng.randf_range(-1, 1) - y) * cut
		out[i] = y * sin(t * PI) * gain * 2.0
	return out


static func _thump(rng: RandomNumberGenerator, length: float, f0: float, f1: float, gain: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var y := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(f0, f1, t) / RATE
		y += (rng.randf_range(-1, 1) - y) * 0.3
		var body := sin(phase) * exp(-t * 6.0)
		var slap := y * exp(-t * 30.0) * 1.6
		out[i] = (body + slap) * gain
	return out


static func _groan(rng: RandomNumberGenerator, length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var y := 0.0
	var base := rng.randf_range(70, 95)
	for i in n:
		var t := float(i) / n
		var f := base * (1.0 + 0.06 * sin(t * TAU * 5.0) - 0.15 * t)
		phase = fmod(phase + f / RATE, 1.0)
		var saw := phase * 2.0 - 1.0 + rng.randf_range(-0.3, 0.3)  # breathy sawtooth
		y += (saw - y) * 0.12
		var env := clampf(t / 0.15, 0, 1) * clampf((1.0 - t) / 0.4, 0, 1)
		out[i] = y * env * 0.9
	return out


static func _rustle(rng: RandomNumberGenerator, length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var gate := 0.0
	for i in n:
		if i % 800 == 0:
			gate = rng.randf_range(0.0, 1.0) if rng.randf() < 0.7 else 0.0
		y += (rng.randf_range(-1, 1) - y) * 0.5
		out[i] = y * gate * 0.35
	return out


static func _sweep_tone(rng: RandomNumberGenerator, length: float, f0: float, f1: float, gain: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var y := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, sin(t * PI * 0.5)) * (1.0 + 0.04 * sin(t * 90.0))
		phase += TAU * f / RATE
		y += (rng.randf_range(-1, 1) - y) * 0.6
		var env := clampf(t / 0.05, 0, 1) * clampf((1.0 - t) / 0.35, 0, 1)
		out[i] = (sin(phase) * 0.6 + sin(phase * 2.01) * 0.25 + y * 0.35) * env * gain
	return out


static func _siren(length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := 520.0 + 280.0 * (0.5 - 0.5 * cos(t * TAU * 1.5))
		phase += TAU * f / RATE
		var env := clampf(t / 0.1, 0, 1) * clampf((1.0 - t) / 0.3, 0, 1)
		out[i] = (sin(phase) + 0.3 * sin(phase * 3.0)) * 0.3 * env
	return out


static func _tone(length: float, f: float, gain: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		out[i] = sin(TAU * f * i / RATE) * gain * (1.0 - t)
	return out
