class_name Soundscape
extends Node
## Everything you hear that is not a single action: the city's background
## (wind by day, crickets by night, rain), far-off sounds now and then (a dog,
## a scream, metal banging, moaning somewhere), and music that follows what is
## happening: exploring, night, danger. Runs on every client, from state it
## already has; the server sends nothing extra for it.

const AMB := "res://audio/ambience/"
const MUSIC := "res://audio/music/"
const FADE := 2.5  # seconds for music and loops to fade across

var main: Node
var loops := {}  # name -> AudioStreamPlayer
var tracks := {}  # name -> AudioStreamPlayer
var mood := ""
var far_t := 12.0
var danger_t := 0.0  # stays in "danger" a while after the last zombie sees you


func _ready() -> void:
	Sfx.setup_buses()
	if DisplayServer.get_name() == "headless":
		return
	for n in ["wind", "crickets", "rain"]:
		loops[n] = _player(AMB + n + ".ogg", "Ambience")
	for n in ["explore", "night", "danger"]:
		tracks[n] = _player(MUSIC + n + ".ogg", "Music")


func _player(path: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		var st: AudioStream = load(path).duplicate()
		if st is AudioStreamOggVorbis:
			st.loop = true
		p.stream = st
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p


## Ease a player toward a volume (silent = -80), starting or stopping it at the ends.
func _fade(p: AudioStreamPlayer, target_db: float, delta: float) -> void:
	if p.stream == null:
		return
	var step := 80.0 / FADE * delta
	p.volume_db = move_toward(p.volume_db, target_db, step)
	if target_db > -79.0 and not p.playing:
		p.play(randf() * maxf(0.0, p.stream.get_length() - 1.0))
	elif p.volume_db <= -79.0 and p.playing:
		p.stop()


## Sound effects not yet loaded; one is loaded per frame so the first time a
## sound plays it does not stall the game while every variant loads.
var _warm: Array = []


func _warm_list() -> Array:
	var names := {}
	for f in DirAccess.get_files_at(Sfx.DIR):
		var base := f.trim_suffix(".import").trim_suffix(".ogg")
		if f.ends_with(".ogg") or f.ends_with(".ogg.import"):
			var cut := base.rfind("_")
			if cut > 0 and base.substr(cut + 1).is_valid_int():
				base = base.substr(0, cut)
			names[base] = true
	return names.keys()


func _process(delta: float) -> void:
	if loops.is_empty():
		return
	if _warm.is_empty() and not get_meta("warmed", false):
		set_meta("warmed", true)
		_warm = _warm_list()
	if not _warm.is_empty():
		Sfx.stream(_warm.pop_back())
	var in_game: bool = main.in_game
	var night: bool = main.world != null and main.world.is_night
	var raining: bool = main.raining
	var me: Player = main.players.get(main.multiplayer.get_unique_id()) if in_game else null
	var indoors: bool = me != null and main.world.building_at.has(main.world.to_cell(me.position))
	# Background loops. Indoors the weather is muffled.
	var room := -8.0 if indoors else 0.0
	_fade(loops.wind, (-20.0 + room) if in_game and not night else -80.0, delta)
	_fade(loops.crickets, (-17.0 + room) if in_game and night and not raining else -80.0, delta)
	_fade(loops.rain, (-9.0 + room) if in_game and raining else -80.0, delta)
	# Music by mood: danger while something has spotted you nearby or the horde is out.
	if me:
		for z: Zombie in main.zombies.values():
			if z.state == 2 and z.position.distance_to(me.position) < 220.0:
				danger_t = 6.0
				break
	danger_t = maxf(0.0, danger_t - delta)
	var want := "explore"
	if not in_game:
		want = "night"
	elif danger_t > 0.0 or main.is_horde(main.day, main.time):
		want = "danger"
	elif night:
		want = "night"
	for n in tracks:
		var level := -14.0 if n == "danger" else -16.0
		_fade(tracks[n], level if n == want else -80.0, delta)
	# Now and then, something far away.
	if in_game and me:
		far_t -= delta
		if far_t <= 0.0:
			far_t = randf_range(14.0, 40.0)
			_far_sound(me.position, night)


func _far_sound(at: Vector2, night: bool) -> void:
	var picks := [["dog", AMB + "dog.ogg"], ["moans", AMB + "moans_far.ogg"], ["scream", ""], ["metal", ""], ["glass", ""]]
	if night:
		picks.append(["scream", ""])
		picks.append(["moans", AMB + "moans_far.ogg"])
	var pick: Array = picks.pick_random()
	var p := AudioStreamPlayer2D.new()
	if pick[1] != "":
		p.stream = load(pick[1])
	else:
		p.stream = Sfx.stream(pick[0])
	# Off to one side, well away: loud enough to hear, never close enough to see.
	p.position = at + Vector2.from_angle(randf() * TAU) * randf_range(260.0, 420.0)
	p.max_distance = 900.0
	p.attenuation = 0.8
	p.volume_db = -6.0 if pick[0] == "moans" else 0.0
	p.pitch_scale = randf_range(0.8, 1.0)
	p.bus = "Ambience"
	main.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
