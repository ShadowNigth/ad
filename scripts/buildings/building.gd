class_name Building
extends Node3D
## Representación visual de un edificio de la economía: malla combinada,
## colisión, luz, fuego/humo, piezas giratorias, cultivos y animales que
## crecen/se mueven con la producción, barra de progreso y trabajadores.

const BAR_SHADER := preload("res://assets/shaders/billboard_bar.gdshader")

var uid: int = -1
var type_id := ""
var world: World
var _mesh_inst: MeshInstance3D
var _body: StaticBody3D
var _light: OmniLight3D
var _fire: CPUParticles3D
var _smoke: CPUParticles3D
var _spinner: MeshInstance3D
var _spinner_axis := Vector3.RIGHT
var _spinner_speed := 1.0
var _bar: MeshInstance3D
var _bar_mat: ShaderMaterial
var _hp_bar: MeshInstance3D
var _hp_mat: ShaderMaterial
var _crops: Array = []
var _animals: Array = []
var _workers: Array = []
var _fire_audio: AudioStreamPlayer3D
var _machine_audio: AudioStreamPlayer3D
var _level_built := -1
var _tower_t := 1.0
var _time := 0.0
var _visible_detail := true
var aabb := AABB()
var _badge: Node3D
var _badge_bg: Sprite3D
var _badge_icon: Sprite3D
var _badge_key := ""
var _badge_t := 0.0
var _dmg_fire: CPUParticles3D
var _dmg_smoke: CPUParticles3D
var _burnt := false
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D


func setup(w: World, rec: Dictionary, animate: bool) -> void:
	world = w
	uid = int(rec.uid)
	type_id = str(rec.type)
	name = "%s_%d" % [type_id, uid]
	position = Vector3(rec.pos[0], rec.pos[1], rec.pos[2])
	rotation.y = deg_to_rad(float(rec.rot))
	rebuild()
	if animate:
		_play_construction()
	EventBus.production_cycle.connect(_on_cycle)
	EventBus.workers_changed.connect(_sync_workers)
	_sync_workers()


func record() -> Dictionary:
	return Economy.get_building(uid)


func data() -> Dictionary:
	return GameData.building(type_id)


func level_data() -> Dictionary:
	var rec := record()
	return GameData.building_level(type_id, int(rec.get("level", 1)))


func rebuild() -> void:
	var rec := record()
	if rec.is_empty():
		return
	_level_built = int(rec.level)
	for c in get_children():
		c.queue_free()
	_crops.clear()
	_animals.clear()
	_workers.clear()
	_badge = null
	_badge_key = ""
	_dmg_fire = null
	_dmg_smoke = null
	_burnt = false
	_halo = null
	_light = null
	_fire = null
	_smoke = null
	_spinner = null
	_fire_audio = null
	_machine_audio = null
	var lvl := level_data()
	var parts: Array = lvl.get("models", [])
	var bd := data()
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = ModelLibrary.baked_merged(parts, "%s_%d" % [type_id, _level_built], bool(bd.get("sway", false)))
	add_child(_mesh_inst)
	aabb = ModelLibrary.parts_aabb(parts)
	var visual: String = bd.get("visual", "")
	if visual == "" and not bool(bd.get("walkable", false)):
		_make_collision(bd)
	if bd.get("walkable", false):
		_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if bd.get("fountain", false):
		_build_fountain()
	if lvl.has("spinner"):
		var sp: Dictionary = lvl.spinner
		_spinner = MeshInstance3D.new()
		_spinner.mesh = ModelLibrary.mesh(sp.model)
		var s := float(sp.get("scale", 1.0))
		_spinner.scale = Vector3.ONE * s
		var p: Array = sp.get("pos", [0, 0, 0])
		_spinner.position = Vector3(p[0], p[1], p[2])
		_spinner_axis = {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}.get(str(sp.get("axis", "x")), Vector3.RIGHT)
		_spinner_speed = float(sp.get("speed", 1.0))
		add_child(_spinner)
	var light_r := float(lvl.get("light", 0.0))
	if light_r > 0.0:
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.72, 0.42) if type_id != "laboratorio" else Color(0.6, 0.85, 1.0)
		_light.light_energy = 1.6
		_light.omni_range = light_r
		_light.omni_attenuation = 1.2
		_light.shadow_enabled = false
		_light.position = Vector3(0, 1.6 if type_id != "antorcha" else aabb.end.y * 0.92, 0)
		add_child(_light)
		# Halo luminoso alrededor de la llama o el farol (se nota de noche).
		_halo = MeshInstance3D.new()
		var hq := QuadMesh.new()
		hq.size = Vector2(1.6, 1.6) if type_id != "fogata" else Vector2(3.2, 3.2)
		_halo.mesh = hq
		_halo_mat = StandardMaterial3D.new()
		_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_halo_mat.albedo_texture = WorldEffects.glow_texture()
		_halo_mat.albedo_color = Color(_light.light_color, 0.0)
		_halo.material_override = _halo_mat
		_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_halo.position = _light.position + (Vector3(0, -0.9, 0) if type_id == "fogata" else Vector3.ZERO)
		add_child(_halo)
	if type_id == "fogata":
		_fire = world.effects.make_fire(self, Vector3(0, 0.35, 0), 1.0)
		_fire_audio = _loop_audio("res://assets/sounds/ambient/fire_loop.ogg", -6.0, 14.0)
	elif type_id == "antorcha" and _level_built >= 2:
		_fire = world.effects.make_fire(self, Vector3(0, aabb.end.y * 0.85, 0), 0.6)
	if bd.get("smoke", false):
		var top := Vector3(0, aabb.end.y + 0.2, 0)
		for part in parts:
			if str(part.model).begins_with("town/chimney"):
				var pp: Array = part.get("pos", [0, 0, 0])
				top = Vector3(pp[0], aabb.end.y + 0.1, pp[2])
		_smoke = world.effects.make_smoke(self, top)
		_smoke.emitting = false
	if type_id in ["generador", "fabrica", "refineria", "laboratorio"]:
		var key: String = {"generador": "generator_loop", "fabrica": "factory_loop", "refineria": "engine_loop", "laboratorio": "computer_loop"}[type_id]
		_machine_audio = _loop_audio("res://assets/sounds/machines/%s.ogg" % key, -14.0, 16.0)
	if visual == "crops":
		_build_crops(lvl)
	elif visual == "animals":
		_build_animals(lvl)
	if not bd.get("production", []).is_empty():
		_bar = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.5, 0.2)
		_bar.mesh = q
		_bar_mat = ShaderMaterial.new()
		_bar_mat.shader = BAR_SHADER
		_bar.material_override = _bar_mat
		_bar.position = Vector3(0, aabb.end.y + 0.6, 0)
		_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bar)
	_hp_bar = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(1.5, 0.16)
	_hp_bar.mesh = q2
	_hp_mat = ShaderMaterial.new()
	_hp_mat.shader = BAR_SHADER
	_hp_mat.set_shader_parameter("fill_color", Color(0.9, 0.25, 0.2))
	_hp_bar.material_override = _hp_mat
	_hp_bar.position = Vector3(0, aabb.end.y + 0.95, 0)
	_hp_bar.visible = false
	_hp_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hp_bar)
	_sync_workers()


## Chorro de agua de la fuente (gotas que suben y caen) y su murmullo.
func _build_fountain() -> void:
	var p := CPUParticles3D.new()
	p.name = "Chorro"
	p.amount = 24
	p.lifetime = 1.1
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = WorldEffects.glow_texture()
	p.material_override = m
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 3.2
	p.initial_velocity_max = 3.8
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.95, 1.0, 0.9))
	g.set_color(1, Color(0.7, 0.88, 1.0, 0.0))
	p.color_ramp = g
	p.position = Vector3(0, aabb.end.y * 0.9, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_loop_audio("res://assets/sounds/ambient/river_stream.ogg", -16.0, 10.0)


func _loop_audio(path: String, vol: float, dist: float) -> AudioStreamPlayer3D:
	if not ResourceLoader.exists(path):
		return null
	var p := AudioStreamPlayer3D.new()
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	p.stream = s
	p.bus = "Ambient"
	p.volume_db = vol
	p.max_distance = dist
	p.unit_size = 4.0
	p.autoplay = true
	add_child(p)
	return p


func _make_collision(bd: Dictionary) -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1 << 3
	_body.collision_mask = 0
	_body.set_meta("building_uid", uid)
	var cs := CollisionShape3D.new()
	var fp := float(bd.get("footprint", 1.5))
	if fp <= 0.6:
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.25
		cyl.height = maxf(aabb.size.y, 1.0)
		cs.shape = cyl
		cs.position.y = cyl.height * 0.5
	else:
		var box := BoxShape3D.new()
		var sx := clampf(aabb.size.x * 0.82, 0.6, fp * 2.0)
		var sz := clampf(aabb.size.z * 0.82, 0.6, fp * 2.0)
		box.size = Vector3(sx, maxf(aabb.size.y, 0.8), sz)
		cs.shape = box
		cs.position = Vector3(aabb.get_center().x, box.size.y * 0.5, aabb.get_center().z)
	_body.add_child(cs)
	add_child(_body)


func _crop_model(t: float) -> String:
	var p := Economy.production_of(record())
	match str(p.get("id", "")):
		"p_maiz":
			return ["nature/crops_cornStageA", "nature/crops_cornStageB", "nature/crops_cornStageC", "nature/crops_cornStageD"][clampi(int(t * 4.0), 0, 3)]
		"p_calabaza":
			return "nature/crop_pumpkin" if t > 0.5 else "nature/crops_leafsStageA"
		_:
			return "nature/crop_carrot" if t > 0.35 else "nature/crops_leafsStageB"


func _build_crops(lvl: Dictionary) -> void:
	var rows := int(lvl.get("crop_rows", 2))
	for r in rows:
		var z := -1.5 + r * 1.5 if rows == 3 else (-0.8 if r == 0 else 0.8)
		for k in 4:
			var mi := MeshInstance3D.new()
			mi.position = Vector3(-1.1 + k * 0.73, 0.05, z)
			mi.rotation.y = randf() * TAU
			add_child(mi)
			_crops.append(mi)
	_update_crops(0.0)


func _update_crops(t: float) -> void:
	if _crops.is_empty():
		return
	var model := _crop_model(t)
	var mesh := ModelLibrary.mesh(model)
	var s := 1.4 + 1.6 * clampf(t, 0.0, 1.0)
	for mi in _crops:
		if (mi as MeshInstance3D).mesh != mesh:
			mi.mesh = mesh
		mi.scale = Vector3.ONE * s


func _build_animals(lvl: Dictionary) -> void:
	var scales := {"animal-chick": 0.24, "animal-pig": 0.34, "animal-cow": 0.42}
	var k := 0
	for a in lvl.get("animals", []):
		var rig := ProceduralRig.new()
		add_child(rig)
		rig.build("animals/" + str(a), "quad", float(scales.get(a, 0.3)))
		var ang := TAU * k / maxf(float(lvl.animals.size()), 1.0)
		rig.position = Vector3(cos(ang) * 1.2, 0.0, sin(ang) * 1.2)
		_animals.append({"rig": rig, "target": rig.position, "wait": randf() * 2.0})
		k += 1


func _sync_workers() -> void:
	if not is_inside_tree():
		return
	var list := Workers.workers_in(uid)
	while _workers.size() > list.size():
		var w: Dictionary = _workers.pop_back()
		(w.rig as Node).queue_free()
	for i in list.size():
		if i < _workers.size():
			continue
		var wdata := Workers.type_data(str(list[i].type))
		var rig := ProceduralRig.new()
		add_child(rig)
		rig.build(str(wdata.get("model", "characters/character-male-b")), "biped", 2.4)
		var tool_model: String = wdata.get("tool", "")
		if tool_model != "" and rig.hand_socket:
			var tm := MeshInstance3D.new()
			tm.mesh = ModelLibrary.mesh(tool_model)
			var h := maxf(ModelLibrary.aabb(tool_model).size.y, 0.05)
			var s := 0.34 / h
			tm.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(s, s, s)), Vector3(0, 0, -h * s * 0.25))
			rig.hand_socket.add_child(tm)
		var fp := float(data().get("footprint", 1.5))
		var ang := 0.6 + i * 1.9
		var spot := Vector3(cos(ang) * (fp + 0.5), 0.0, sin(ang) * (fp + 0.5))
		rig.position = spot
		_workers.append({"rig": rig, "spot": spot, "t": randf() * 3.0, "mode": "work", "anim": _worker_anim(tool_model)})


## Gesto de trabajo según la herramienta del trabajador.
static func _worker_anim(tool_model: String) -> String:
	var n := tool_model.get_file()
	if n.contains("pickaxe") or n.contains("shovel") or n.contains("hoe"):
		return "mine"
	if n.contains("axe"):
		return "chop"
	if n.contains("hammer"):
		return "hammer"
	return "gather"


func _play_construction() -> void:
	scale = Vector3(0.15, 0.05, 0.15)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fp := float(data().get("footprint", 1.5))
	world.effects.dust(global_position, fp)
	world.effects.ring(global_position, Color(1.0, 0.92, 0.7, 0.8), fp * 2.2, 0.6)
	get_tree().create_timer(0.75).timeout.connect(func():
		if is_inside_tree():
			world.effects.sparkle(global_position + Vector3.UP * aabb.end.y * 0.6, Color(1.0, 0.95, 0.7), 10))
	for k in 3:
		get_tree().create_timer(0.12 + k * 0.28).timeout.connect(func():
			if is_inside_tree():
				AudioManager.play_at("build/hammer", global_position, -2.0))


## Mejora: destellos que suben, anillo dorado y rótulo del nuevo nivel.
func play_upgrade(level: int) -> void:
	if not is_inside_tree():
		return
	var top := global_position + Vector3.UP * (aabb.end.y + 0.4)
	world.effects.ring(global_position, Color(1.0, 0.85, 0.35, 0.95), float(data().get("footprint", 1.5)) * 2.6, 0.8)
	world.effects.sparkle(global_position + Vector3.UP * 1.2, Color(1.0, 0.88, 0.4), 22)
	world.effects.flash(top, Color(1.0, 0.9, 0.5), 2.0, 0.3)
	EventBus.floating_text.emit(top + Vector3.UP * 0.6, "¡Nivel %d!" % level, Color(1.0, 0.85, 0.3))


func _on_cycle(cycle_uid: int, outputs: Dictionary) -> void:
	if cycle_uid != uid or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(global_position) > GameData.bf("economy.visual_production_radius", 70.0):
		return
	var parts: Array[String] = []
	for id in outputs:
		if str(id).begins_with("@"):
			parts.append("+%d PT" % int(round(float(outputs[id]))))
		elif float(outputs[id]) >= 1.0:
			parts.append("+%d %s" % [int(floor(float(outputs[id]))), GameData.item_name(id)])
	if not parts.is_empty():
		EventBus.floating_text.emit(global_position + Vector3(0, aabb.end.y + 1.2, 0), "  ".join(parts), Color(0.75, 1.0, 0.7))
	var tw := create_tween()
	tw.tween_property(_mesh_inst, "scale", Vector3(1.06, 0.94, 1.06), 0.08)
	tw.tween_property(_mesh_inst, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	if type_id == "huerto":
		_update_crops(0.0)


func _process(delta: float) -> void:
	_time += delta
	var rec := record()
	if rec.is_empty():
		return
	if int(rec.level) != _level_built:
		rebuild()
		_play_construction()
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < 75.0
	if near != _visible_detail:
		_visible_detail = near
		if _bar:
			_bar.visible = near
	var working: bool = rec.get("status", "") == Economy.STATUS_OK
	if _bar_mat and near:
		_bar_mat.set_shader_parameter("progress", clampf(float(rec.get("progress", 0.0)), 0.0, 1.0))
		var col := Color(0.4, 0.86, 0.36)
		match str(rec.get("status", "")):
			Economy.STATUS_NO_INPUT, Economy.STATUS_NO_FUEL:
				col = Color(0.95, 0.65, 0.2)
			Economy.STATUS_FULL:
				col = Color(0.4, 0.65, 1.0)
			Economy.STATUS_NO_ENERGY, Economy.STATUS_DAMAGED:
				col = Color(0.9, 0.3, 0.25)
		_bar_mat.set_shader_parameter("fill_color", col)
	var hp_ratio := float(rec.hp) / maxf(Economy.max_hp(rec), 1.0)
	_hp_bar.visible = hp_ratio < 0.999 and near
	if _hp_bar.visible:
		_hp_mat.set_shader_parameter("progress", hp_ratio)
	_update_damage_fx(hp_ratio)
	_badge_t -= delta
	if _badge_t <= 0.0:
		_badge_t = 0.5
		_update_badge(rec, near)
	if _badge and _badge.visible:
		_badge.position.y = aabb.end.y + 1.45 + sin(_time * 3.0) * 0.08
	if _spinner and working:
		_spinner.rotate_object_local(_spinner_axis, delta * _spinner_speed * TAU * 0.25)
	if _smoke:
		_smoke.emitting = working or hp_ratio < 0.5
	if _light and _fire:
		_light.light_energy = 1.5 + sin(_time * 13.0) * 0.12 + sin(_time * 7.3) * 0.1
	if _halo and near:
		var dark: float = world.day_night.darkness()
		var flick := 1.0 + (sin(_time * 11.0) * 0.08 if _fire else 0.0)
		_halo_mat.albedo_color.a = clampf((dark - 0.25) * 1.2, 0.0, 0.75) * flick
	if _machine_audio:
		_machine_audio.stream_paused = not working
	if data().get("defense", false) and float(rec.hp) > 0.0:
		_tower_update(delta)
	if not near:
		return
	if type_id == "huerto":
		_update_crops(float(rec.get("progress", 0.0)))
	for a in _animals:
		_animate_animal(a, delta)
	for w in _workers:
		_animate_worker(w, delta, working)


func _animate_animal(a: Dictionary, delta: float) -> void:
	var rig: ProceduralRig = a.rig
	a.wait = float(a.wait) - delta
	var to: Vector3 = a.target - rig.position
	if to.length() < 0.15:
		rig.walk = 0.0
		if float(a.wait) <= 0.0:
			a.wait = randf_range(1.0, 3.5)
			a.target = Vector3(randf_range(-1.8, 1.8), 0.0, randf_range(-1.8, 1.8))
	else:
		var step := to.normalized() * delta * 0.7
		rig.position += step
		rig.rotation.y = atan2(-to.x, -to.z)
		rig.walk = 0.6


func _animate_worker(w: Dictionary, delta: float, working: bool) -> void:
	var rig: ProceduralRig = w.rig
	w.t = float(w.t) - delta
	if working:
		rig.walk = 0.0
		var to_center := -(w.spot as Vector3)
		rig.rotation.y = atan2(-to_center.x, -to_center.z)
		if float(w.t) <= 0.0:
			w.t = 0.9 + randf() * 0.25
			rig.play_action(str(w.get("anim", "hammer")))
	else:
		rig.walk = 0.0
		if float(w.t) <= 0.0:
			w.t = 3.0
			rig.rotation.y += randf_range(-1.0, 1.0)


## Torre de defensa: dispara lanzas a la criatura hostil más cercana.
func _tower_update(delta: float) -> void:
	_tower_t -= delta
	if _tower_t > 0.0:
		return
	var lvl := level_data()
	var rng := float(lvl.get("tower_range", 12.0))
	_tower_t = 0.5
	var target: Enemy = null
	var best := rng
	for e in world.enemies.enemies():
		if not e.is_hostile():
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best:
			best = d
			target = e
	if target == null:
		return
	_tower_t = float(lvl.get("tower_rate", 1.8))
	var dmg := float(lvl.get("tower_damage", 12))
	var from := global_position + Vector3(0, aabb.end.y + 0.3, 0)
	var proj := MeshInstance3D.new()
	proj.mesh = ModelLibrary.mesh("weapons/weapon-spear")
	world.effects.add_child(proj)
	proj.global_position = from
	var to := target.global_position + Vector3.UP * 0.8
	proj.look_at_from_position(from, to, Vector3.UP)
	proj.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	proj.scale = Vector3.ONE * 2.2
	AudioManager.play_at("combat/draw", from, -4.0)
	var tw := proj.create_tween()
	tw.tween_property(proj, "global_position", to, clampf(best / 30.0, 0.12, 0.5))
	tw.tween_callback(func():
		if is_instance_valid(target) and target.is_alive():
			target.take_damage(dmg, global_position)
		proj.queue_free())


func footprint() -> float:
	return float(data().get("footprint", 1.5))


# ------------------------------------------------------------------ avisos visuales
## Fuego y humo cuando está muy dañado; ennegrecido y humeante si está destruido.
func _update_damage_fx(hp_ratio: float) -> void:
	var burning := hp_ratio > 0.0 and hp_ratio < 0.25
	if burning and _dmg_fire == null:
		_dmg_fire = world.effects.make_fire(self, Vector3(aabb.get_center().x * 0.5, aabb.end.y * 0.55, 0.0), 0.7)
	elif not burning and _dmg_fire:
		_dmg_fire.queue_free()
		_dmg_fire = null
	var smoking := hp_ratio < 0.25
	if smoking and _dmg_smoke == null:
		_dmg_smoke = world.effects.make_smoke(self, Vector3(0.0, aabb.end.y * 0.7, 0.0))
	elif not smoking and _dmg_smoke:
		_dmg_smoke.queue_free()
		_dmg_smoke = null
	var burnt := hp_ratio <= 0.0
	if burnt != _burnt and _mesh_inst:
		_burnt = burnt
		if burnt:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.08, 0.06, 0.05, 0.55)
			_mesh_inst.material_overlay = m
		else:
			_mesh_inst.material_overlay = null


## Icono flotante cuando el edificio está parado: el material que falta, sin
## energía, almacén lleno o destruido.
func _update_badge(rec: Dictionary, near: bool) -> void:
	var key := ""
	var tex: Texture2D = null
	var col := Color(0.95, 0.62, 0.2)
	if float(rec.hp) <= 0.0:
		key = "dmg"
		tex = UITheme.icon("wrench")
		col = Color(0.85, 0.25, 0.2)
	else:
		match str(rec.get("status", "")):
			Economy.STATUS_NO_INPUT, Economy.STATUS_NO_FUEL:
				var missing := _first_missing(rec)
				key = "in:" + missing
				tex = GameData.item_icon(missing) if missing != "" else UITheme.icon("warning")
			Economy.STATUS_FULL:
				key = "full"
				tex = UITheme.icon("shoppingBasket")
				col = Color(0.35, 0.6, 0.95)
			Economy.STATUS_NO_ENERGY:
				key = "energy"
				tex = UITheme.icon("power")
				col = Color(0.85, 0.25, 0.2)
	if key == "" or not near:
		if _badge:
			_badge.visible = false
		_badge_key = ""
		return
	if _badge == null:
		_badge = Node3D.new()
		_badge.name = "Aviso"
		add_child(_badge)
		_badge_bg = Sprite3D.new()
		_badge_bg.texture = UITheme.tex("round_grey")
		_badge_bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_badge_bg.no_depth_test = true
		_badge_bg.render_priority = 1
		_badge_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_badge.add_child(_badge_bg)
		_badge_icon = Sprite3D.new()
		_badge_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_badge_icon.no_depth_test = true
		_badge_icon.render_priority = 2
		_badge_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_badge.add_child(_badge_icon)
	_badge.visible = true
	if key != _badge_key:
		_badge_key = key
		_badge_bg.modulate = col
		if _badge_bg.texture:
			_badge_bg.pixel_size = 0.8 / maxf(float(_badge_bg.texture.get_width()), 1.0)
		_badge_icon.texture = tex
		if tex:
			_badge_icon.pixel_size = 0.5 / maxf(float(tex.get_width()), 1.0)
		# Pequeño salto al aparecer.
		_badge.scale = Vector3.ONE * 0.3
		var tw := _badge.create_tween()
		tw.tween_property(_badge, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _first_missing(rec: Dictionary) -> String:
	var ins := Economy.inputs_for(rec)
	for id in ins:
		if str(id).begins_with("@"):
			continue
		if Economy.stored_f(id) + 0.0001 < float(ins[id]):
			return str(id)
	return ""
