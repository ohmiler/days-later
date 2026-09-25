class_name Sfx
## Sound effects synthesised in code (no audio files), cached on first use.
## Sfx.play(parent, "hit", position) plays one positioned in the world.

const RATE := 22050

static var _cache := {}


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
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


static func stream(name: String) -> AudioStreamWAV:
	if not _cache.has(name):
		_cache[name] = _build(name)
	return _cache[name]


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
		"groan":
			samples = _groan(rng, 0.9)
		"rustle":  # rummaging through a shelf
			samples = _rustle(rng, 0.7)
		"pickup":
			samples = _tone(0.07, 660.0, 0.35)
			samples.append_array(_tone(0.09, 990.0, 0.35))
		"eat":
			samples = _rustle(rng, 0.35)
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


static func _tone(length: float, f: float, gain: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		out[i] = sin(TAU * f * i / RATE) * gain * (1.0 - t)
	return out
