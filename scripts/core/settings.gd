extends Node
## Ajustes del jugador (persistidos en user://settings.cfg) y mapa de entradas.

const PATH := "user://settings.cfg"
const QUALITY_PRESETS := {
	# Sin sombras en tiempo real: en el renderizador de Compatibilidad la luz con sombras se suma en
	# espacio sRGB (escena lavada al mediodía) y duplica las llamadas de dibujo. Se usan sombras
	# suaves bajo personajes, árboles y edificios («blob_shadows»: 1 = solo personajes, 2 = todo).
	"baja": {"shadows": false, "shadow_size": 1024, "view_distance": 75.0, "vegetation": 0.45, "render_scale": 0.75, "msaa": 0, "fog": true, "blob_shadows": 1},
	"media": {"shadows": false, "shadow_size": 1024, "view_distance": 105.0, "vegetation": 0.75, "render_scale": 1.0, "msaa": 0, "fog": true, "blob_shadows": 2},
	"alta": {"shadows": false, "shadow_size": 2048, "view_distance": 150.0, "vegetation": 1.0, "render_scale": 1.0, "msaa": 2, "fog": true, "blob_shadows": 2},
}
const DEFAULTS := {
	"sensitivity": 1.0,
	"invert_y": false,
	"volume_master": 0.9,
	"volume_music": 0.6,
	"volume_sfx": 0.85,
	"volume_ambient": 0.7,
	"quality": "media",
	"fps_limit": 60,
	"show_fps": false,
	"ui_scale": 1.0,
	"auto_deposit": true,
	"camera_distance": 6.5,
	"weather": true,
	"camera_shake": true,
}

var values: Dictionary = DEFAULTS.duplicate(true)


func _ready() -> void:
	_register_input_actions()
	load_settings()
	if OS.has_feature("mobile") and not FileAccess.file_exists(PATH):
		values.quality = "baja" if _is_low_end() else "media"
		values.fps_limit = 30 if _is_low_end() else 60
	apply()


func _is_low_end() -> bool:
	return OS.get_processor_count() <= 4


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in DEFAULTS:
		values[k] = cfg.get_value("ajustes", k, DEFAULTS[k])
	if not QUALITY_PRESETS.has(values.quality):
		values.quality = "media"


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("ajustes", k, values[k])
	cfg.save(PATH)


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	save_settings()
	apply()


func quality() -> Dictionary:
	return QUALITY_PRESETS.get(values.quality, QUALITY_PRESETS.media)


func apply() -> void:
	Engine.max_fps = int(values.fps_limit)
	_set_bus("Master", values.volume_master)
	_set_bus("Music", values.volume_music)
	_set_bus("SFX", values.volume_sfx)
	_set_bus("UI", values.volume_sfx)
	_set_bus("Ambient", values.volume_ambient)
	var tree := get_tree()
	if tree and tree.root:
		var q := quality()
		tree.root.scaling_3d_scale = float(q.render_scale)
		tree.root.msaa_3d = Viewport.MSAA_DISABLED if int(q.msaa) == 0 else Viewport.MSAA_2X
		tree.root.content_scale_factor = float(values.ui_scale)
	EventBus.settings_changed.emit()


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(linear), 0.0001)))
	AudioServer.set_bus_mute(idx, float(linear) <= 0.001)


func _register_input_actions() -> void:
	var map := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"interact": [KEY_E],
		"attack": [KEY_F, KEY_J],
		"dodge": [KEY_Q, KEY_CTRL],
		"inventory": [KEY_I, KEY_TAB],
		"crafting": [KEY_C],
		"build": [KEY_B],
		"tech": [KEY_T],
		"map": [KEY_M],
		"stats": [KEY_P],
		"pause": [KEY_ESCAPE],
		"rotate_building": [KEY_R],
		"confirm": [KEY_ENTER],
		"eat_quick": [KEY_H],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
