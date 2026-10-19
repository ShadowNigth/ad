class_name World
extends Node3D
## Raíz de la partida: genera la isla, coloca recursos, puntos de interés,
## edificios, criaturas y al jugador, y ofrece consultas del mundo al resto
## de sistemas (altura, agua, zonas, luz, enemigos...).

signal ready_done

@onready var sun: DirectionalLight3D = $Sun
@onready var env_node: WorldEnvironment = $WorldEnvironment
@onready var terrain_root: Node3D = $Terrain
@onready var resources: ResourceNodeManager = $Resources
@onready var decor: DecorScatter = $Decor
@onready var pois: PoiManager = $POIs
@onready var buildings: BuildingManager = $Buildings
@onready var enemies: EnemySpawner = $Enemies
@onready var pickups_root: Node3D = $Pickups
@onready var effects: WorldEffects = $Effects
@onready var day_night: DayNight = $DayNight
@onready var player: Player = $Player
@onready var build_mode: BuildMode = $BuildMode
@onready var hud: Node = $HUD

var gen: IslandGenerator
var crafter: Crafter
var weather: Weather
var ambient_life: AmbientLife
var treasures: BeachTreasures
var water: MeshInstance3D
var water_mat: ShaderMaterial
var map_texture: ImageTexture
var exclusions: Array = []
var _backpack_node: Node3D
var _ambient_t := 0.0
var _fixed_lights: Array = []
var loaded := false
var gen_time_ms := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	gen = IslandGenerator.new(GameData.world, int(GameData.b("world.seed", 1)))
	gen.generate()
	_build_environment()
	_build_terrain()
	_build_water()
	exclusions = pois.compute_exclusions(gen)
	resources.setup(gen, exclusions)
	decor.setup(gen, exclusions)
	pois.setup(self)
	buildings.setup(self)
	weather = Weather.new()
	weather.name = "Clima"
	add_child(weather)
	weather.setup(self)
	day_night.setup(self, sun, env_node.environment)
	ambient_life = AmbientLife.new()
	ambient_life.name = "VidaAmbiental"
	add_child(ambient_life)
	ambient_life.setup(self)
	treasures = BeachTreasures.new()
	treasures.name = "Tesoros"
	add_child(treasures)
	treasures.setup(self)
	enemies.setup(self)
	build_mode.setup(self)
	crafter = Crafter.new()
	crafter.name = "Crafter"
	add_child(crafter)
	crafter.setup(self)
	player.world = self
	_place_player()
	map_texture = ImageTexture.create_from_image(gen.build_map_image(192))
	_restore_backpack()
	_apply_quality()
	EventBus.settings_changed.connect(_apply_quality)
	EventBus.night_started.connect(_on_night)
	EventBus.day_started.connect(_on_day)
	EventBus.danger_nearby.connect(_on_danger)
	if hud and hud.has_method("setup"):
		hud.setup(self)
	gen_time_ms = Time.get_ticks_msec() - t0
	print("Isla generada en %d ms: %d nodos de recursos, %d decoraciones" % [gen_time_ms, resources.nodes.size(), decor.instance_total()])
	Economy.running = true
	Quests.active = true
	Quests._queue_check()
	GameState.session_active = true
	AudioManager.set_mood("night" if day_night.is_night() else "day")
	loaded = true
	ready_done.emit()


func _exit_tree() -> void:
	Economy.running = false
	Quests.active = false
	GameState.session_active = false
	AudioManager.stop_ambient()


# ------------------------------------------------------------------ construcción del mundo
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# Cielo propio (degradado, sol, luna, estrellas y nubes); DayNight ajusta sus parámetros.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.2
	env_node.environment = env


func _build_terrain() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for chunk in gen.build_chunks(32):
		var mi := MeshInstance3D.new()
		mi.mesh = chunk.mesh
		mi.material_override = mat
		terrain_root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = gen.collision_shape()
	cs.scale = Vector3(gen.cell, 1.0, gen.cell)
	body.add_child(cs)
	terrain_root.add_child(body)


func _build_water() -> void:
	water = MeshInstance3D.new()
	water.name = "Agua"
	var plane := PlaneMesh.new()
	plane.size = Vector2(gen.size + 240.0, gen.size + 240.0)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	water.mesh = plane
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://assets/shaders/water.gdshader")
	water_mat.set_shader_parameter("water_data", ImageTexture.create_from_image(gen.build_water_data(128)))
	water_mat.set_shader_parameter("world_size", gen.size)
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _place_player() -> void:
	var pos: Vector3
	if GameState.has_position:
		pos = GameState.player_pos
		if not is_walkable(pos) or pos.y < height_at(pos.x, pos.z) - 1.0:
			pos = _safe_spawn(GameState.spawn_point)
		else:
			pos.y = height_at(pos.x, pos.z) + 0.2
	else:
		pos = _safe_spawn(GameState.spawn_point)
	player.place_at(pos, GameState.player_yaw if GameState.has_position else PI)


## Busca un punto de tierra transitable cerca del indicado.
func _safe_spawn(p: Vector3) -> Vector3:
	for r in range(0, 40, 2):
		for k in 12:
			var a := TAU * k / 12.0
			var x := p.x + cos(a) * r
			var z := p.z + sin(a) * r
			var h := gen.height_at(x, z)
			if h > 0.3 and gen.slope_deg(x, z) < 30.0 and gen.region_at(x, z) == "" and not buildings.blocks(Vector3(x, h, z), 0.8):
				return Vector3(x, h + 0.2, z)
	return Vector3(0, gen.height_at(0, 0) + 1.0, 0)


func _apply_quality() -> void:
	var q := Settings.quality()
	sun.shadow_enabled = bool(q.shadows)
	sun.directional_shadow_max_distance = 45.0 if int(q.shadow_size) <= 1024 else 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if int(q.shadow_size) <= 1024 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(int(q.shadow_size), true)
	var vd := float(q.view_distance)
	resources.set_visibility_range(vd)
	decor.apply_quality(float(q.vegetation), vd)
	effects.budget = 0.6 if Settings.get_value("quality") == "baja" else 1.0
	var env := env_node.environment
	env.fog_density = 2.4 / maxf(vd * 6.0, 1.0)
	day_night.base_fog = env.fog_density
	if env.sky and env.sky.sky_material is ShaderMaterial:
		(env.sky.sky_material as ShaderMaterial).set_shader_parameter("detail", 0 if Settings.get_value("quality") == "baja" else 1)


# ------------------------------------------------------------------ consultas
func height_at(x: float, z: float) -> float:
	return gen.height_at(x, z)


func water_depth_at(pos: Vector3) -> float:
	if pois.on_bridge(pos):
		return 0.0
	return gen.water_depth(pos.x, pos.z)


## Bonificación de velocidad del suelo (caminos de losas).
func ground_speed_bonus(pos: Vector3) -> float:
	var uid := buildings.nearest(pos, 0.0)
	if uid < 0:
		return 0.0
	return float(GameData.building(Economy.get_building(uid).get("type", "")).get("move_bonus", 0.0))


func is_fresh_water(pos: Vector3) -> bool:
	return gen.is_fresh_water(pos.x, pos.z) and not pois.on_bridge(pos)


## ¿Se puede caminar por aquí? (agua profunda y regiones bloqueadas no)
func is_walkable(pos: Vector3, for_enemy: bool = false) -> bool:
	if not gen.in_bounds(pos.x, pos.z):
		return false
	if pois.on_bridge(pos):
		return true
	var deep := GameData.bf("world.deep_water_block", 0.9)
	if gen.water_depth(pos.x, pos.z) > deep:
		return false
	var region := gen.region_at(pos.x, pos.z)
	if region != "" and not GameState.is_region_unlocked(region):
		return false
	return true


func surface_at(pos: Vector3) -> String:
	if gen.water_depth(pos.x, pos.z) > 0.15 and not pois.on_bridge(pos):
		return "water"
	if pois.on_bridge(pos):
		return "wood"
	var uid := buildings.nearest(pos, 0.0)
	if uid >= 0:
		return str(GameData.building(Economy.get_building(uid).get("type", "")).get("surface", "wood"))
	var zone := gen.zone_at(pos.x, pos.z)
	var zdata: Dictionary = GameData.world.get("zones", {}).get(zone, {})
	if gen.height_at(pos.x, pos.z) < 0.8:
		return "sand"
	return str(zdata.get("surface", "grass"))


func building_near(pos: Vector3, radius: float) -> int:
	return buildings.nearest(pos, radius)


func building_blocks(pos: Vector3, radius: float) -> bool:
	return buildings.blocks(pos, radius)


func nearest_enemy(pos: Vector3, radius: float) -> Node3D:
	return enemies.nearest(pos, radius)


func enemies_in_arc(origin: Vector3, dir: Vector3, reach: float, arc_deg: float) -> Array:
	return enemies.in_arc(origin, dir, reach, arc_deg)


## ¿Está iluminado (fogatas, antorchas...)? `margin` amplía/reduce el radio.
func is_lit(pos: Vector3, margin: float = 0.0) -> bool:
	for l in Economy.light_sources():
		if Vector2(pos.x, pos.z).distance_to(Vector2(l.pos.x, l.pos.z)) < float(l.radius) + margin:
			return true
	return false


func poi_near(pos: Vector3, radius: float) -> Dictionary:
	return pois.nearest_interactable(pos, radius)


func poi_label(info: Dictionary) -> String:
	return pois.label_for(info)


func interact_poi(id: String) -> void:
	pois.interact(id)


# ------------------------------------------------------------------ objetos y efectos
func spawn_drop(item_id: String, qty: int, pos: Vector3, launch: bool = true, player_drop: bool = false) -> Pickup:
	if qty <= 0 or not GameData.has_item(item_id):
		return null
	var p := Pickup.new()
	pickups_root.add_child(p)
	p.setup(item_id, qty)
	p.bind_world(self)
	p.player_drop = player_drop
	var ground := height_at(pos.x, pos.z)
	p.global_position = Vector3(pos.x, maxf(ground, 0.0) + 0.05, pos.z)
	if launch:
		# Sale despedido en arco y rebota antes de quedarse en el suelo.
		var a := randf() * TAU
		p.launch(Vector3(cos(a), 0.0, sin(a)) * randf_range(1.2, 2.6) + Vector3.UP * randf_range(3.5, 5.0), self)
	return p


func spawn_hit_effect(pos: Vector3, node_type: String) -> void:
	effects.hit(pos, node_type)


func spawn_explosion(pos: Vector3) -> void:
	effects.explosion(pos)


# ------------------------------------------------------------------ muerte y mochila
func on_player_died(pos: Vector3) -> void:
	var frac := GameData.bf("death.carried_loss_fraction", 0.5)
	var lost := {}
	var inv := GameState.inventory
	for i in inv.slots.size():
		var s: Variant = inv.slots[i]
		if s == null:
			continue
		var cat: String = GameData.item(s.id).get("cat", "")
		if cat in ["herramienta", "arma", "contenedor"]:
			continue
		var q := int(floor(int(s.qty) * frac))
		if q > 0:
			inv.remove_at(i, q)
			lost[s.id] = int(lost.get(s.id, 0)) + q
	# Si ya había una mochila sin recuperar, se fusiona (no se pierde nada).
	if not GameState.lost_backpack.is_empty():
		for id in GameState.lost_backpack.get("items", {}):
			lost[id] = int(lost.get(id, 0)) + int(GameState.lost_backpack.items[id])
	if not lost.is_empty():
		var ground := Vector3(pos.x, maxf(height_at(pos.x, pos.z), 0.1), pos.z)
		if not is_walkable(ground):
			ground = _safe_spawn(ground)
		GameState.lost_backpack = {"pos": [ground.x, ground.y, ground.z], "items": lost,
			"expires": GameState.now() + GameData.bf("death.backpack_lifetime", 1800.0)}
		_restore_backpack()


func respawn_player() -> void:
	var target := GameState.spawn_point
	var refugios := Economy.buildings_of("refugio")
	if not refugios.is_empty():
		var r: Dictionary = refugios[0]
		target = Vector3(r.pos[0], r.pos[1], r.pos[2]) + Vector3(0, 0, 3.5)
	player.respawn_at(_safe_spawn(target))
	AudioManager.play("events/stinger_dawn", -6.0)


func _restore_backpack() -> void:
	if is_instance_valid(_backpack_node):
		_backpack_node.queue_free()
	_backpack_node = null
	var bp := GameState.lost_backpack
	if bp.is_empty():
		return
	if GameState.now() > float(bp.get("expires", 0.0)):
		GameState.lost_backpack = {}
		return
	var mi := MeshInstance3D.new()
	mi.mesh = ModelLibrary.mesh("food/bag")
	mi.scale = Vector3.ONE * 2.2
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.3)
	light.omni_range = 3.0
	light.light_energy = 1.2
	mi.add_child(light)
	light.position.y = 0.3
	add_child(mi)
	mi.global_position = Vector3(bp.pos[0], bp.pos[1], bp.pos[2])
	_backpack_node = mi


func backpack_near(pos: Vector3, radius: float) -> bool:
	return is_instance_valid(_backpack_node) and _backpack_node.global_position.distance_to(pos) < radius


func backpack_position() -> Variant:
	if GameState.lost_backpack.is_empty():
		return null
	var p: Array = GameState.lost_backpack.pos
	return Vector3(p[0], p[1], p[2])


func recover_backpack() -> void:
	var bp := GameState.lost_backpack
	if bp.is_empty():
		return
	var remaining := {}
	var parts: Array[String] = []
	for id in bp.get("items", {}):
		var q := int(bp.items[id])
		var left := GameState.give(id, q)
		if left > 0:
			left -= int(Economy.add_storage(id, left))
		if left > 0:
			remaining[id] = left
		if q - left > 0:
			parts.append("%d %s" % [q - left, GameData.item_name(id)])
	AudioManager.play("events/reward")
	if remaining.is_empty():
		GameState.lost_backpack = {}
		if is_instance_valid(_backpack_node):
			_backpack_node.queue_free()
		EventBus.notify("Mochila recuperada: " + ", ".join(parts), "good")
	else:
		bp.items = remaining
		EventBus.notify("Recuperaste parte de la mochila (no cabe todo).", "warn")


# ------------------------------------------------------------------ descanso y ciclo
func try_sleep() -> bool:
	var h := GameState.hour
	if not (day_night.is_night() or h >= 18.5):
		EventBus.notify("Solo puedes dormir al anochecer o de noche.", "warn")
		return false
	for e in enemies.enemies():
		if e.is_hostile() and e.global_position.distance_to(player.global_position) < 14.0:
			EventBus.notify("No puedes dormir con enemigos cerca.", "warn")
			return false
	day_night.skip_to_morning()
	player.survival.refill_all()
	GameState.survival.hunger = maxf(GameState.survival.hunger - 15.0, 10.0)
	GameState.survival.thirst = maxf(GameState.survival.thirst - 15.0, 10.0)
	AudioManager.play("events/stinger_dawn", -4.0)
	EventBus.notify("Has dormido hasta el amanecer.", "good")
	SaveManager.save_game()
	return true


func _on_night(_day: int) -> void:
	AudioManager.play("events/stinger_night", -6.0)
	AudioManager.play_at("events/wolf_howl", player.global_position + Vector3(30, 0, -20), -4.0)
	AudioManager.set_mood("night")
	EventBus.banner.emit("Cae la noche", "Las criaturas despiertan: busca la luz de una fogata.", "night")


func _on_day(day: int) -> void:
	AudioManager.play("events/stinger_dawn", -6.0)
	if AudioManager.get_mood() != "danger":
		AudioManager.set_mood("day")
	EventBus.banner.emit("Día %d" % day, "Amanece en la isla", "day")


func _on_danger(active: bool) -> void:
	if active:
		AudioManager.set_mood("danger")
	else:
		AudioManager.set_mood("night" if day_night.is_night() else "day")


func _process(delta: float) -> void:
	if not loaded:
		return
	water_mat.set_shader_parameter("night", day_night.darkness())
	_ambient_t -= delta
	if _ambient_t <= 0.0:
		_ambient_t = 0.5
		_update_ambient()


func _update_ambient() -> void:
	var p := player.global_position
	var night := day_night.is_night()
	var near_sea := 0.0
	var near_river := 0.0
	for k in 8:
		var a := TAU * k / 8.0
		for d: float in [6.0, 14.0, 24.0]:
			var x: float = p.x + cos(a) * d
			var z: float = p.z + sin(a) * d
			if gen.height_at(x, z) < -0.3:
				var zi := gen.zone_index(x, z)
				if zi == IslandGenerator.Zone.MAR:
					near_sea = maxf(near_sea, 1.0 - d / 30.0)
				else:
					near_river = maxf(near_river, 1.0 - d / 26.0)
	var high := clampf((p.y - 7.0) / 8.0, 0.0, 1.0)
	var wet := weather.rain if weather else 0.0
	var gust := (weather.wind - 1.0) * 0.3 if weather else 0.0
	AudioManager.set_ambient("birds", 0.0 if night else 0.55 * (1.0 - near_sea * 0.5) * (1.0 - wet))
	AudioManager.set_ambient("crickets", 0.6 * (1.0 - wet * 0.7) if night else 0.0)
	AudioManager.set_ambient("waves", near_sea * 0.85)
	AudioManager.set_ambient("river", near_river * 0.7)
	AudioManager.set_ambient("wind", clampf(0.2 + high * 0.6 + gust, 0.0, 1.0))
	if night and randf() < 0.04:
		AudioManager.play_at("ambient/owl", p + Vector3(randf_range(-25, 25), 6, randf_range(-25, 25)), -8.0)
