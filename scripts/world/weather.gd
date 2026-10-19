class_name Weather
extends Node3D
## Clima de la isla: despejado, nublado, lluvia y tormenta. El cambio de estado
## sigue las probabilidades y duraciones de data/balance.json (sección
## "weather") con transiciones suaves. Afecta a la luz, la niebla, las nubes del
## cielo, el viento de la vegetación y el sonido (lluvia y truenos con
## relámpagos). Con lluvia la sed baja más despacio y los huertos crecen más
## rápido (lo aplican SurvivalStats y Economy a partir de GameState.weather).

signal changed(state: String)

const LABELS := {"despejado": "Despejado", "nublado": "Nublado", "lluvia": "Lluvia", "tormenta": "Tormenta"}
## [lluvia, nubosidad, viento] objetivo de cada estado.
const TARGETS := {
	"despejado": [0.0, 0.0, 1.0], "nublado": [0.0, 0.55, 1.3],
	"lluvia": [0.75, 0.85, 1.7], "tormenta": [1.0, 1.0, 2.4],
}

var world: Node3D
var rain := 0.0        # 0..1 lluvia visible (suavizada)
var overcast := 0.0    # 0..1 nubosidad (suavizada)
var wind := 1.0
var flash := 0.0       # 0..1 destello de relámpago
var _thunder_t := 0.0
var _flash_seq: Array = []
var _rain_fx: CPUParticles3D
var _splash_fx: CPUParticles3D
var _rain_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func setup(w: Node3D) -> void:
	world = w
	_rng.randomize()
	_build_rain()
	var st := state()
	if not TARGETS.has(st):
		GameState.weather.state = "despejado"
		st = "despejado"
	# Al cargar partida se aplica el clima guardado sin transición.
	var t: Array = TARGETS[st]
	rain = float(t[0])
	overcast = float(t[1])
	wind = float(t[2])
	_thunder_t = _rng.randf_range(4.0, 10.0)
	_apply()


func state() -> String:
	return str(GameState.weather.get("state", "despejado"))


func is_raining() -> bool:
	return state() in ["lluvia", "tormenta"]


func label() -> String:
	return LABELS.get(state(), "")


## Fuerza un estado (lo usan las pruebas y las capturas).
func force(st: String, instant: bool = false, duration: float = -1.0) -> void:
	if not TARGETS.has(st):
		return
	var prev := state()
	GameState.weather.state = st
	GameState.weather.left = duration if duration > 0.0 else _duration_for(st)
	if instant:
		var t: Array = TARGETS[st]
		rain = float(t[0])
		overcast = float(t[1])
		wind = float(t[2])
	if prev != st:
		_announce(prev, st)
		changed.emit(st)
		EventBus.weather_changed.emit(st)
	_apply()


func _duration_for(st: String) -> float:
	var cfg: Dictionary = GameData.balance.get("weather", {}).get("states", {}).get(st, {})
	return _rng.randf_range(float(cfg.get("min", 180.0)), float(cfg.get("max", 360.0)))


func _next_state(current: String) -> String:
	var cfg: Dictionary = GameData.balance.get("weather", {})
	if GameState.day < int(cfg.get("first_rain_day", 2)):
		return "despejado" if current != "despejado" or _rng.randf() < 0.7 else "nublado"
	var nexts: Dictionary = cfg.get("states", {}).get(current, {}).get("next", {"despejado": 1.0})
	var total := 0.0
	for k in nexts:
		total += float(nexts[k])
	var r := _rng.randf() * maxf(total, 0.0001)
	for k in nexts:
		r -= float(nexts[k])
		if r <= 0.0:
			return str(k)
	return "despejado"


func _announce(prev: String, st: String) -> void:
	match st:
		"lluvia":
			if prev != "tormenta":
				EventBus.notify("Empieza a llover: la lluvia riega los huertos y calma la sed.", "info")
		"tormenta":
			EventBus.notify("¡Se acerca una tormenta! Busca refugio.", "warn")
		"despejado", "nublado":
			if prev in ["lluvia", "tormenta"]:
				EventBus.notify("Deja de llover.", "info")


func _process(delta: float) -> void:
	if world == null:
		return
	if bool(GameData.balance.get("weather", {}).get("enabled", true)):
		GameState.weather.left = float(GameState.weather.get("left", 300.0)) - delta
		if float(GameState.weather.left) <= 0.0:
			force(_next_state(state()))
	var t: Array = TARGETS.get(state(), TARGETS.despejado)
	rain = move_toward(rain, float(t[0]), delta * 0.08)
	overcast = move_toward(overcast, float(t[1]), delta * 0.06)
	wind = move_toward(wind, float(t[2]), delta * 0.15)
	_update_storm(delta)
	_apply()
	_follow_camera()


func _update_storm(delta: float) -> void:
	if state() == "tormenta" and rain > 0.6:
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			var iv: Array = GameData.balance.get("weather", {}).get("thunder_interval", [9.0, 22.0])
			_thunder_t = _rng.randf_range(float(iv[0]), float(iv[1]))
			_lightning()
	# Secuencia de destellos (doble parpadeo).
	if not _flash_seq.is_empty():
		_flash_seq[0] = float(_flash_seq[0]) - delta
		if float(_flash_seq[0]) <= 0.0:
			_flash_seq.pop_front()
			flash = 1.0
	flash = move_toward(flash, 0.0, delta * 5.0)


func _lightning() -> void:
	_flash_seq = [0.0, 0.12 + _rng.randf() * 0.08]
	var delay := _rng.randf_range(0.3, 2.2)
	var vol := lerpf(0.0, -10.0, delay / 2.2)
	get_tree().create_timer(delay).timeout.connect(func(): AudioManager.play("ambient/thunder", vol, 0.1))


func _apply() -> void:
	AudioManager.set_ambient("rain", clampf(rain * 1.1, 0.0, 1.0) * 0.85)
	ModelLibrary.set_wind(wind, 1.0 + (wind - 1.0) * 0.35)
	if _rain_fx:
		var vis := rain > 0.03
		if _rain_fx.emitting != vis:
			_rain_fx.emitting = vis
			_splash_fx.emitting = vis
		_rain_mat.albedo_color.a = clampf(rain, 0.0, 1.0) * 0.5


func _build_rain() -> void:
	var low: bool = Settings.get_value("quality") == "baja"
	var cfg: Dictionary = GameData.balance.get("weather", {})
	var drops := QuadMesh.new()
	drops.size = Vector2(0.025, 0.55)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_mat.albedo_color = Color(0.78, 0.84, 0.95, 0.45)
	_rain_mat.disable_receive_shadows = true
	_rain_fx = CPUParticles3D.new()
	_rain_fx.name = "Lluvia"
	_rain_fx.amount = int(cfg.get("rain_particles_low", 110)) if low else int(cfg.get("rain_particles", 260))
	_rain_fx.lifetime = 0.8
	_rain_fx.mesh = drops
	_rain_fx.material_override = _rain_mat
	_rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain_fx.emission_box_extents = Vector3(13.0, 0.5, 13.0)
	_rain_fx.direction = Vector3(0.08, -1.0, 0.04)
	_rain_fx.spread = 3.0
	_rain_fx.initial_velocity_min = 15.0
	_rain_fx.initial_velocity_max = 18.0
	_rain_fx.gravity = Vector3.ZERO
	_rain_fx.emitting = false
	_rain_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_fx.visibility_aabb = AABB(Vector3(-16, -16, -16), Vector3(32, 20, 32))
	add_child(_rain_fx)
	# Salpicaduras en el suelo alrededor del jugador.
	var ring := QuadMesh.new()
	ring.size = Vector2(0.16, 0.16)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = WorldEffects.glow_texture()
	_splash_fx = CPUParticles3D.new()
	_splash_fx.name = "Salpicaduras"
	_splash_fx.amount = 18 if low else 40
	_splash_fx.lifetime = 0.3
	_splash_fx.mesh = ring
	_splash_fx.material_override = smat
	_splash_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_splash_fx.emission_box_extents = Vector3(7.0, 0.05, 7.0)
	_splash_fx.direction = Vector3.UP
	_splash_fx.spread = 30.0
	_splash_fx.initial_velocity_min = 0.6
	_splash_fx.initial_velocity_max = 1.2
	_splash_fx.gravity = Vector3(0, -6.0, 0)
	_splash_fx.scale_amount_min = 0.6
	_splash_fx.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.9, 1.0, 0.7))
	g.set_color(1, Color(0.85, 0.9, 1.0, 0.0))
	_splash_fx.color_ramp = g
	_splash_fx.emitting = false
	_splash_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash_fx)


## La lluvia sigue a la cámara (adelantada en la dirección de la vista).
func _follow_camera() -> void:
	if _rain_fx == null or not _rain_fx.emitting:
		return
	var cam := get_viewport().get_camera_3d()
	var player: Node3D = world.get("player")
	if cam == null or player == null:
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.01:
		fwd = fwd.normalized()
	_rain_fx.global_position = player.global_position + fwd * 6.0 + Vector3.UP * 11.0
	_splash_fx.global_position = player.global_position + fwd * 3.0 + Vector3.UP * 0.08
