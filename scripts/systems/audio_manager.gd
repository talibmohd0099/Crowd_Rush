class_name AudioManager
extends Node
## Simple, local audio system: pooled one-shot SFX voices, a crossfading music
## pair, and looping ambience/footstep beds. Volumes are exported so they can
## be tuned in the inspector (or later from a settings menu).

@export_range(-40.0, 6.0) var master_volume_db := 0.0
@export_range(-40.0, 6.0) var music_volume_db := -9.0
@export_range(-40.0, 6.0) var sfx_volume_db := -1.0
@export_range(-40.0, 6.0) var ambience_volume_db := -12.0
@export var sfx_voices := 14

const DIR := "res://assets/sounds/"
const SOUNDS: Array[StringName] = [
	&"intro_rumble", &"city_ambience", &"whoosh", &"impact_distant", &"footstep",
	&"footsteps_loop", &"gate_positive", &"gate_negative", &"multiply", &"pop", &"sparkle",
	&"wood_impact", &"barrier_crash", &"thud", &"boss_roar", &"boss_step", &"weapon_swing",
	&"ground_slam", &"hit", &"boss_hit", &"victory_sting", &"crowd_cheer", &"ui_click",
	&"warning", &"music_main", &"music_boss",
]
const LOOPING: Array[StringName] = [&"city_ambience", &"footsteps_loop", &"music_main", &"music_boss"]

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_idx := 0
var _last_played: Dictionary = {}
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_offset_db := 0.0
var _ambience: AudioStreamPlayer
var _footsteps: AudioStreamPlayer
var _footsteps_level := 0.0
var _footsteps_target := 0.0


func _ready() -> void:
	_ensure_bus(&"Music", music_volume_db)
	_ensure_bus(&"SFX", sfx_volume_db)
	_ensure_bus(&"Ambience", ambience_volume_db)
	AudioServer.set_bus_volume_db(0, master_volume_db)
	for n in SOUNDS:
		var s: AudioStream = load(DIR + String(n) + ".wav")
		if s is AudioStreamWAV and LOOPING.has(n):
			var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
			s = w
		_streams[n] = s
	for i in sfx_voices:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_voices.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = &"Music"
		m.volume_db = -60.0
		add_child(m)
		_music.append(m)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"Ambience"
	add_child(_ambience)
	_footsteps = AudioStreamPlayer.new()
	_footsteps.bus = &"Ambience"
	_footsteps.stream = _streams[&"footsteps_loop"]
	_footsteps.volume_db = -60.0
	add_child(_footsteps)


func _ensure_bus(bus_name: StringName, vol: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	AudioServer.set_bus_volume_db(idx, vol)


# ------------------------------------------------------------------ SFX
func play(sound: StringName, volume_db := 0.0, pitch := 1.0, pitch_var := 0.04) -> AudioStreamPlayer:
	if not _streams.has(sound):
		push_warning("Unknown sound %s" % sound)
		return null
	var p := _voices[_voice_idx]
	_voice_idx = (_voice_idx + 1) % _voices.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_var, pitch_var))
	p.play()
	_last_played[sound] = Time.get_ticks_msec()
	return p


## Same as play() but ignored if the sound played less than `min_interval` ago
## (prevents machine-gun repetition when many runners spawn at once).
func play_limited(sound: StringName, min_interval: float, volume_db := 0.0, pitch := 1.0) -> void:
	var last: int = _last_played.get(sound, -100000)
	if Time.get_ticks_msec() - last < int(min_interval * 1000.0):
		return
	play(sound, volume_db, pitch)


# ------------------------------------------------------------------ music
func play_music(track: StringName, fade := 1.0, offset_db := 0.0) -> void:
	var cur := _music[_music_active]
	if cur.playing and cur.stream == _streams.get(track):
		set_music_offset(offset_db, fade)
		return
	_music_active = 1 - _music_active
	var nxt := _music[_music_active]
	nxt.stream = _streams[track]
	nxt.volume_db = -40.0
	nxt.play()
	_music_offset_db = offset_db
	var tw := create_tween().set_parallel(true)
	tw.tween_property(nxt, "volume_db", offset_db, fade)
	if cur.playing:
		tw.tween_property(cur, "volume_db", -60.0, fade)
		tw.chain().tween_callback(cur.stop)


func set_music_offset(offset_db: float, fade := 0.5) -> void:
	_music_offset_db = offset_db
	var cur := _music[_music_active]
	create_tween().tween_property(cur, "volume_db", offset_db, fade)


func stop_music(fade := 0.6) -> void:
	for m in _music:
		if m.playing:
			var tw := create_tween()
			tw.tween_property(m, "volume_db", -60.0, fade)
			tw.tween_callback(m.stop)


# ------------------------------------------------------------------ loops
func start_ambience(fade := 1.5) -> void:
	_ambience.stream = _streams[&"city_ambience"]
	_ambience.volume_db = -40.0
	_ambience.play()
	create_tween().tween_property(_ambience, "volume_db", 0.0, fade)


func fade_ambience(target_db: float, fade := 1.0) -> void:
	create_tween().tween_property(_ambience, "volume_db", target_db, fade)


## 0..1 loudness of the running-crowd footstep bed.
func set_footsteps_level(level: float) -> void:
	_footsteps_target = clampf(level, 0.0, 1.0)
	if _footsteps_target > 0.0 and not _footsteps.playing:
		_footsteps.play()


func _process(delta: float) -> void:
	_footsteps_level = move_toward(_footsteps_level, _footsteps_target, delta * 1.5)
	if _footsteps.playing:
		_footsteps.volume_db = linear_to_db(maxf(_footsteps_level, 0.0001)) + 2.0
		_footsteps.pitch_scale = 0.95 + _footsteps_level * 0.12
		if _footsteps_level <= 0.001 and _footsteps_target <= 0.0:
			_footsteps.stop()
