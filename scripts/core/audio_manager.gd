extends Node
## Gestor de audio: efectos 2D/3D con variaciones aleatorias, música por
## estados (día, noche, peligro) con fundidos y capas de ambiente.

const SFX_ROOT := "res://assets/sounds/%s"
const MUSIC := {
	"menu": ["day_connecting_rainbows"],
	"day": ["day_connecting_rainbows", "day_flowing_rocks", "day_mischief_stroll", "day_farm_frolics"],
	"night": ["night_midnight_green_house", "night_at_the_beach"],
	"danger": ["danger_infinite_descent"],
}
const SHORT_LOOP_SECONDS := 70.0
const AMBIENT_LAYERS := {
	"birds": "ambient/day_birds.ogg",
	"crickets": "ambient/night_crickets.ogg",
	"waves": "ambient/beach_waves.ogg",
	"river": "ambient/river_stream.ogg",
	"wind": "ambient/wind.ogg",
}

var _variants: Dictionary = {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool_ui: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _next2d := 0
var _next_ui := 0
var _next3d := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _mood := ""
var _last_track := ""
var _gap_timer := 0.0
var _track_timer := 0.0
var _ambient: Dictionary = {}
var _ambient_target: Dictionary = {}
var _last_play_time: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2d.append(p)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_pool_ui.append(p)
	for i in 14:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 38.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for p in [_music_a, _music_b]:
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		p.finished.connect(_on_music_finished.bind(p))
	_music_active = _music_a
	for layer in AMBIENT_LAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambient"
		p.volume_db = -80.0
		var path: String = SFX_ROOT % AMBIENT_LAYERS[layer]
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
			p.stream = s
		add_child(p)
		_ambient[layer] = p
		_ambient_target[layer] = 0.0


## Devuelve las variantes de un efecto: "gather/wood_hit" -> wood_hit_0..n.ogg
func _resolve(key: String) -> Array:
	if _variants.has(key):
		return _variants[key]
	var list: Array = []
	var single := SFX_ROOT % (key + ".ogg")
	if ResourceLoader.exists(single):
		list.append(load(single))
	else:
		for i in 24:
			var path := SFX_ROOT % ("%s_%d.ogg" % [key, i])
			if not ResourceLoader.exists(path):
				break
			list.append(load(path))
	_variants[key] = list
	return list


func has_sound(key: String) -> bool:
	return not _resolve(key).is_empty()


func _pick(key: String) -> AudioStream:
	var list := _resolve(key)
	if list.is_empty():
		return null
	return list[randi() % list.size()]


## Evita que el mismo efecto suene decenas de veces en el mismo instante.
func _throttled(key: String, min_gap: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play_time.get(key, -10.0)) < min_gap:
		return true
	_last_play_time[key] = now
	return false


func play(key: String, volume_db: float = 0.0, pitch_var: float = 0.08) -> void:
	if _throttled(key, 0.03):
		return
	var s := _pick(key)
	if s == null:
		return
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % _pool2d.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_ui(key: String, volume_db: float = -4.0) -> void:
	if _throttled("ui:" + key, 0.05):
		return
	var s := _pick(key)
	if s == null:
		return
	var p := _pool_ui[_next_ui]
	_next_ui = (_next_ui + 1) % _pool_ui.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0
	p.play()


func play_at(key: String, pos: Vector3, volume_db: float = 0.0, pitch_var: float = 0.1) -> void:
	if _throttled(key + str(Vector3i(pos)), 0.03):
		return
	var s := _pick(key)
	if s == null:
		return
	var p := _pool3d[_next3d]
	_next3d = (_next3d + 1) % _pool3d.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


# ------------------------------------------------------------------ música
func set_mood(mood: String) -> void:
	if mood == _mood:
		return
	_mood = mood
	_gap_timer = 0.0
	if mood == "":
		_fade_out_all()
		return
	_start_track(true)


func get_mood() -> String:
	return _mood


func _start_track(crossfade: bool) -> void:
	var list: Array = MUSIC.get(_mood, [])
	if list.is_empty():
		return
	var choices := list.filter(func(t): return t != _last_track)
	if choices.is_empty():
		choices = list
	var track: String = choices[randi() % choices.size()]
	var path := "res://assets/music/%s.ogg" % track
	if not ResourceLoader.exists(path):
		return
	_last_track = track
	var stream: AudioStream = load(path)
	var is_short := stream.get_length() < 40.0
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = is_short or _mood == "danger"
	_track_timer = SHORT_LOOP_SECONDS if is_short and _mood != "danger" else -1.0
	var old := _music_active
	var nxt := _music_b if _music_active == _music_a else _music_a
	nxt.stream = stream
	nxt.volume_db = -40.0
	nxt.play()
	_music_active = nxt
	var tw := create_tween().set_parallel(true)
	tw.tween_property(nxt, "volume_db", _mood_volume(), 2.5 if crossfade else 0.5)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, 2.5)
		tw.chain().tween_callback(old.stop)


func _mood_volume() -> float:
	return -9.0 if _mood == "danger" else -6.0


func _fade_out_all() -> void:
	var tw := create_tween().set_parallel(true)
	for p in [_music_a, _music_b]:
		if p.playing:
			tw.tween_property(p, "volume_db", -60.0, 2.0)
	tw.chain().tween_callback(func(): _music_a.stop(); _music_b.stop())


func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player != _music_active:
		return
	# Silencio entre pistas para que la música no canse.
	_gap_timer = randf_range(25.0, 60.0) if _mood in ["day", "night"] else 2.0


func _process(delta: float) -> void:
	if _track_timer > 0.0:
		_track_timer -= delta
		if _track_timer <= 0.0 and _music_active.playing:
			var tw := create_tween()
			tw.tween_property(_music_active, "volume_db", -60.0, 3.0)
			tw.tween_callback(_music_active.stop)
			tw.tween_callback(func(): _gap_timer = randf_range(25.0, 55.0))
	if _gap_timer > 0.0:
		_gap_timer -= delta
		if _gap_timer <= 0.0 and _mood != "":
			_start_track(false)
	for layer in _ambient:
		var p: AudioStreamPlayer = _ambient[layer]
		var target: float = _ambient_target[layer]
		var cur_lin := db_to_linear(p.volume_db) if p.playing else 0.0
		var new_lin := move_toward(cur_lin, target, delta * 0.35)
		if new_lin <= 0.001:
			if p.playing:
				p.stop()
			p.volume_db = -80.0
		else:
			if not p.playing and p.stream:
				p.play(randf() * maxf(p.stream.get_length() - 1.0, 0.0))
			p.volume_db = linear_to_db(new_lin)


## Ajusta el volumen objetivo (0..1) de una capa de ambiente.
func set_ambient(layer: String, volume: float) -> void:
	if _ambient_target.has(layer):
		_ambient_target[layer] = clampf(volume, 0.0, 1.0)


func stop_ambient() -> void:
	for layer in _ambient_target:
		_ambient_target[layer] = 0.0
