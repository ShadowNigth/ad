extends Node
## Capturas de pantalla con el renderizador REAL (no headless). Recorre varias
## escenas preparadas (playa de día, base al atardecer, noche, lluvia,
## tormenta, combate e interfaz) y guarda un PNG de cada una.
## Uso (en CI con Xvfb + Mesa):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-method gl_compatibility \
##       --rendering-driver opengl3 --resolution 1280x720 tests/tools/capturas.tscn -- <carpeta>

var out_dir := "user://capturas"
var world: World
var shots: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("Renderizador: %s · %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	SaveManager.enabled = false
	Settings.values.quality = "alta"
	Settings.values.show_fps = true
	TechTree.reset()
	GameState.new_game()
	Economy.reset()
	Workers.reset()
	Quests.reset()
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(1.0)
	EventBus.settings_changed.emit()
	world.day_night.paused = true
	_prepare_base()
	await _wait(1.0)
	await _scene_beach()
	await _scene_base_sunset()
	await _scene_night()
	await _scene_rain()
	await _scene_storm()
	await _scene_combat()
	await _scene_ui()
	var f := FileAccess.open(out_dir.path_join("LEEME.md"), FileAccess.WRITE)
	if f:
		f.store_string("# Capturas automáticas\n\nGeneradas por `tests/tools/capturas.tscn` con el renderizador real (%s, %s) en GitHub Actions.\n\n%s\n" % [
			RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
			"\n".join(shots.map(func(s): return "![%s](%s)" % [s, s]))])
		f.close()
	print("CAPTURAS: %d imágenes en %s" % [shots.size(), out_dir])
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("captura omitida (modo headless): ", name)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_warning("No se pudo leer la imagen de la pantalla para " + name)
		return
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	shots.append(name + ".png")
	print("captura: ", path, " ", img.get_size())


func _camp() -> Vector3:
	var c: Array = [6.0, 28.0]
	for poi in GameData.world.pois:
		if poi.type == "camp":
			c = poi.pos
	return Vector3(c[0], world.height_at(c[0], c[1]), c[1])


func _place(pos: Vector3, yaw: float, pitch: float, dist: float) -> void:
	var p := world.player
	pos.y = world.height_at(pos.x, pos.z) + 0.1
	p.place_at(pos, yaw)
	p.pitch = pitch
	p.cam_distance = dist
	p.spring.spring_length = dist
	p.rig.rotation.y = yaw + PI


func _set_time(hour: float) -> void:
	GameState.hour = hour
	world.day_night._apply_visuals()


func _prepare_base() -> void:
	var c := _camp()
	for t in ["agr_cultivo", "agr_riego", "con_carpinteria", "min_canteria", "exp_antorchas", "aut_organizacion"]:
		TechTree.researched[t] = true
	TechTree._recalc()
	var list := [["refugio", Vector3(-6, 0, -4), 0], ["fogata", Vector3(0, 0, 2), 0], ["almacen", Vector3(6, 0, -5), 0],
		["lenador", Vector3(-9, 0, 6), 90], ["cantera", Vector3(9, 0, 6), 270], ["huerto", Vector3(-3, 0, 12), 0],
		["aserradero", Vector3(4, 0, 13), 0], ["antorcha", Vector3(3, 0, -1), 0], ["antorcha", Vector3(-3, 0, 5), 0],
		["fuente", Vector3(0, 0, -10), 0], ["estatua", Vector3(-4, 0, -12), 0], ["estandarte", Vector3(4, 0, -12), 0],
		["macetas", Vector3(-2.5, 0, -6.5), 0], ["macetas", Vector3(2.5, 0, -6.5), 0],
		["camino", Vector3(0, 0, -4.5), 90], ["camino", Vector3(0, 0, -2.6), 90],
		["valla", Vector3(-7, 0, -14), 0], ["valla", Vector3(-4.6, 0, -14), 0], ["valla", Vector3(4.6, 0, -14), 0], ["valla", Vector3(7, 0, -14), 0]]
	for e in list:
		var pos: Vector3 = c + e[1]
		pos.y = world.height_at(pos.x, pos.z)
		Economy.place_building(e[0], pos, float(e[2]), true)
	GameState.inventory.add("hacha_piedra", 1)
	GameState.inventory.add("martillo", 1)
	GameState.inventory.add("lanza", 1)
	GameState.inventory.add("madera", 40)
	Workers.hire("lenador")


func _beach_point() -> Vector3:
	var c := _camp()
	var best := c
	var best_d := INF
	for i in 400:
		var a := TAU * i / 400.0
		for r in [20.0, 35.0, 50.0, 70.0]:
			var x: float = c.x + cos(a) * r
			var z: float = c.z + sin(a) * r
			if world.gen.zone_at(x, z) == "playa" and world.gen.height_at(x, z) > 0.4:
				var d := Vector2(x - c.x, z - c.z).length()
				if d < best_d:
					best_d = d
					best = Vector3(x, 0, z)
	return best


func _scene_beach() -> void:
	world.weather.force("despejado", true)
	_set_time(10.0)
	var b := _beach_point()
	# Mira hacia el mar (hacia donde baja el terreno).
	var dir := Vector3.ZERO
	for k in 16:
		var a := TAU * k / 16.0
		var d := Vector3(cos(a), 0, sin(a))
		if world.gen.height_at(b.x + d.x * 12.0, b.z + d.z * 12.0) < world.gen.height_at(b.x + dir.x * 12.0, b.z + dir.z * 12.0):
			dir = d
	var yaw := atan2(dir.x, dir.z) + PI
	_place(b, yaw, -0.22, 7.0)
	await _wait(2.5)
	await _shot("01_playa_dia")


func _scene_base_sunset() -> void:
	_set_time(18.9)
	_place(_camp() + Vector3(0, 0, -17), 0.0, -0.32, 9.5)
	await _wait(2.5)
	await _shot("02_base_atardecer")


func _scene_night() -> void:
	_set_time(22.5)
	_place(_camp() + Vector3(1.5, 0, -2.0), PI * 0.85, -0.3, 8.0)
	await _wait(3.0)
	await _shot("03_noche_fogata")


func _scene_rain() -> void:
	_set_time(13.0)
	world.weather.force("lluvia", true)
	_place(_camp() + Vector3(-6, 0, 8), PI * 0.25, -0.25, 7.5)
	await _wait(3.0)
	await _shot("04_lluvia")


func _scene_storm() -> void:
	world.weather.force("tormenta", true)
	_set_time(16.0)
	_place(_camp() + Vector3(4, 0, -8), PI * 1.2, -0.18, 8.0)
	await _wait(2.0)
	world.weather._lightning()
	await _wait(0.08)
	await _shot("05_tormenta_relampago")
	world.weather.force("despejado", true)


func _scene_combat() -> void:
	_set_time(11.0)
	var p := world.player
	var pos := _camp() + Vector3(18, 0, 10)
	_place(pos, PI * 0.5, -0.28, 6.5)
	p._iframes = 999.0
	await _wait(0.5)
	var types := ["jabali", "cangrejo", "esqueleto"]
	for i in types.size():
		var a := -0.6 + i * 0.6
		var ep := p.global_position + Vector3(cos(a) * 3.0, 0.3, sin(a) * 3.0)
		world.enemies._spawn(types[i], ep)
	await _wait(1.2)
	var e: Node3D = world.nearest_enemy(p.global_position, 8.0)
	if e:
		var d := e.global_position - p.global_position
		p.rig.rotation.y = atan2(-d.x, -d.z)
	GameState.equip(GameState.inventory.best_weapon())
	p._attack_cd = 0.0
	GameState.survival.stamina = 100.0
	p.attack()
	await _wait(0.2)
	await _shot("06_combate")


func _scene_ui() -> void:
	var hud: Node = world.hud
	hud.banner("¡Nivel 5!", "+2 puntos de tecnología", "level")
	await _wait(0.7)
	await _shot("07_rotulo_nivel")
	hud.open_panel("build")
	await _wait(0.5)
	var bm: BuildMenu = hud.panels.build
	bm.tabs.current_tab = bm.tabs.tab_count - 1
	await _wait(0.6)
	await _shot("08_menu_decoracion")
	hud.close_all()
	await _wait(0.3)
