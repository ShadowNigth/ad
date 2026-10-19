class_name DayNight
extends Node
## Ciclo de día y noche: mueve el sol, cambia el cielo, la niebla y la luz
## ambiental, y emite los eventos de amanecer y anochecer.

var world: Node3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: Material          # ShaderMaterial (cielo propio) o ProceduralSkyMaterial
var base_fog := 0.0035          # densidad de niebla según la calidad (la ajusta World)
var sun_scale := 1.0            # multiplicadores globales de luz (calibración)
var ambient_scale := 1.0
var _was_night := false
var _last_hour := -1
var paused := false

# Paleta por hora: [hora, cielo_arriba, horizonte, sol_color, sol_energía, ambiente]
const KEYS := [
	[0.0, Color(0.03, 0.05, 0.13), Color(0.08, 0.12, 0.22), Color(0.55, 0.62, 0.95), 0.18, 0.32],
	[5.0, Color(0.05, 0.07, 0.17), Color(0.14, 0.15, 0.26), Color(0.55, 0.62, 0.95), 0.2, 0.34],
	[6.3, Color(0.32, 0.42, 0.62), Color(0.96, 0.62, 0.42), Color(1.0, 0.68, 0.45), 0.55, 0.55],
	[8.0, Color(0.30, 0.55, 0.85), Color(0.72, 0.84, 0.92), Color(1.0, 0.93, 0.82), 1.05, 0.85],
	[12.0, Color(0.24, 0.52, 0.88), Color(0.68, 0.83, 0.94), Color(1.0, 0.98, 0.93), 1.25, 0.95],
	[17.0, Color(0.27, 0.5, 0.82), Color(0.74, 0.82, 0.9), Color(1.0, 0.9, 0.78), 1.05, 0.85],
	[19.2, Color(0.32, 0.3, 0.5), Color(0.98, 0.55, 0.35), Color(1.0, 0.55, 0.32), 0.5, 0.55],
	[20.6, Color(0.06, 0.08, 0.2), Color(0.16, 0.14, 0.28), Color(0.55, 0.62, 0.95), 0.22, 0.36],
	[24.0, Color(0.03, 0.05, 0.13), Color(0.08, 0.12, 0.22), Color(0.55, 0.62, 0.95), 0.18, 0.32],
]


func setup(w: Node3D, sun_light: DirectionalLight3D, environment: Environment) -> void:
	world = w
	sun = sun_light
	env = environment
	sky_mat = env.sky.sky_material if env.sky else null
	base_fog = env.fog_density
	_was_night = is_night()
	_last_hour = int(GameState.hour)
	_apply_visuals()


func is_night() -> bool:
	var h := GameState.hour
	return h >= GameData.bf("day_night.night_hour", 20.5) or h < GameData.bf("day_night.dawn_hour", 6.0)


## 0 (pleno día) .. 1 (noche cerrada)
func darkness() -> float:
	var e := _sample(GameState.hour)[3] as float
	return clampf(1.0 - (e - 0.18) / (1.25 - 0.18), 0.0, 1.0)


func hours_per_second() -> float:
	return 24.0 / maxf(GameData.bf("day_night.day_length", 720.0), 1.0)


func _process(delta: float) -> void:
	if paused or world == null:
		return
	advance(delta * hours_per_second())
	_apply_visuals()


func advance(hours: float) -> void:
	var before := GameState.hour
	GameState.hour += hours
	var dawn := GameData.bf("day_night.dawn_hour", 6.0)
	if GameState.hour >= 24.0:
		GameState.hour -= 24.0
	# Amanecer: cruce de la hora del alba.
	var crossed_dawn := (before < dawn and GameState.hour >= dawn) or (before > GameState.hour and GameState.hour >= dawn)
	if crossed_dawn:
		GameState.day += 1
		if _was_night:
			GameState.add_stat("nights")
		EventBus.day_started.emit(GameState.day)
	var night := is_night()
	if night and not _was_night:
		EventBus.night_started.emit(GameState.day)
	_was_night = night
	var hr := int(GameState.hour)
	if hr != _last_hour:
		_last_hour = hr
		EventBus.hour_changed.emit(hr)


## Duerme hasta la mañana (solo de noche o al atardecer).
func skip_to_morning() -> void:
	var target := GameData.bf("day_night.dawn_hour", 6.0) + 0.5
	var h := GameState.hour
	var add := target - h
	if add <= 0.0:
		add += 24.0
	advance(add)
	_apply_visuals()


func _sample(h: float) -> Array:
	for k in KEYS.size() - 1:
		var a: Array = KEYS[k]
		var b: Array = KEYS[k + 1]
		if h >= float(a[0]) and h <= float(b[0]):
			var t := (h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return [(a[1] as Color).lerp(b[1], t), (a[2] as Color).lerp(b[2], t), (a[3] as Color).lerp(b[3], t),
					lerpf(a[4], b[4], t), lerpf(a[5], b[5], t)]
	var last: Array = KEYS[0]
	return [last[1], last[2], last[3], last[4], last[5]]


func _apply_visuals() -> void:
	if sun == null:
		return
	var h := GameState.hour
	var s := _sample(h)
	# El sol recorre el cielo de este a oeste; de noche la luz es la luna (lado opuesto).
	var day_angle := (h - 6.0) / 12.0 * PI
	var night := h >= 19.5 or h < 6.0
	var elev: float
	var azim: float
	if not night:
		elev = clampf(sin(day_angle), 0.08, 1.0) * deg_to_rad(68.0)
		azim = lerpf(deg_to_rad(-80.0), deg_to_rad(80.0), clampf((h - 6.0) / 13.5, 0.0, 1.0))
	else:
		var nt := fposmod(h - 19.5, 24.0) / 10.5
		elev = deg_to_rad(28.0 + sin(nt * PI) * 22.0)
		azim = lerpf(deg_to_rad(60.0), deg_to_rad(-60.0), nt)
	sun.rotation = Vector3(-elev, azim + PI * 0.15, 0.0)
	# Clima: las nubes y la lluvia apagan el sol y agrisan el cielo; los relámpagos lo iluminan todo.
	var overcast := 0.0
	var rain := 0.0
	var flash := 0.0
	var weather: Variant = world.get("weather") if world else null
	if weather != null:
		overcast = float(weather.overcast)
		rain = float(weather.rain)
		flash = float(weather.flash)
	var gray := Color(0.5, 0.53, 0.58) * (1.0 - darkness() * 0.8)
	var top: Color = (s[0] as Color).lerp(gray, overcast * 0.65)
	var horizon: Color = (s[1] as Color).lerp(gray.lightened(0.15), overcast * 0.6)
	if flash > 0.0:
		top = top.lerp(Color(0.85, 0.88, 1.0), flash * 0.7)
		horizon = horizon.lerp(Color(0.9, 0.92, 1.0), flash * 0.7)
	sun.light_color = (s[2] as Color).lerp(Color(0.8, 0.85, 1.0), flash)
	sun.light_energy = float(s[3]) * sun_scale * (1.0 - 0.55 * overcast) + flash * 1.6
	if sky_mat is ShaderMaterial:
		var sm := sky_mat as ShaderMaterial
		sm.set_shader_parameter("sky_top", top)
		sm.set_shader_parameter("sky_horizon", horizon)
		sm.set_shader_parameter("ground_horizon", horizon.darkened(0.1))
		sm.set_shader_parameter("ground_bottom", top.darkened(0.5))
		sm.set_shader_parameter("sun_color", s[2])
		var sun_vis := 0.0
		var moon_vis := 0.0
		if night:
			moon_vis = clampf(fposmod(h - 19.5, 24.0) / 0.6, 0.0, 1.0) * (clampf((6.0 - h) / 0.5, 0.0, 1.0) if h < 12.0 else 1.0)
		else:
			sun_vis = clampf((h - 6.0) / 0.5, 0.0, 1.0) * clampf((19.5 - h) / 0.5, 0.0, 1.0)
		sm.set_shader_parameter("sun_disc", sun_vis * (1.0 - overcast * 0.85))
		sm.set_shader_parameter("moon_disc", moon_vis * (1.0 - overcast * 0.9))
		sm.set_shader_parameter("stars", smoothstep(0.55, 0.9, darkness()) * (1.0 - overcast))
		sm.set_shader_parameter("cloud_cover", 0.3 + overcast * 0.62)
		var cl: Color = Color(1, 1, 1).lerp(s[1], 0.35) * (1.0 - darkness() * 0.78)
		cl = cl.lerp(gray, overcast * 0.6)
		sm.set_shader_parameter("cloud_light", cl.lerp(Color(1, 1, 1), flash * 0.8))
		sm.set_shader_parameter("cloud_shadow", cl.darkened(0.3 + overcast * 0.2).lerp(Color(0.35, 0.4, 0.55), 0.2))
	elif sky_mat is ProceduralSkyMaterial:
		var pm := sky_mat as ProceduralSkyMaterial
		pm.sky_top_color = top
		pm.sky_horizon_color = horizon
		pm.ground_horizon_color = horizon.darkened(0.1)
		pm.ground_bottom_color = top.darkened(0.5)
	env.ambient_light_energy = float(s[4]) * ambient_scale * (1.0 - 0.2 * overcast) + flash * 0.8
	env.fog_light_color = horizon.lerp(top, 0.4)
	env.fog_density = base_fog * (1.0 + overcast * 0.5 + rain * 1.4)
