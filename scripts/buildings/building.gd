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
	_light = null
	_fire = null
	_smoke = null
	_spinner = null
	_fire_audio = null
	_machine_audio = null
	var lvl := level_data()
	var parts: Array = lvl.get("models", [])
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = ModelLibrary.merged(parts, "%s_%d" % [type_id, _level_built])
	add_child(_mesh_inst)
	aabb = ModelLibrary.parts_aabb(parts)
	var bd := data()
	var visual: String = bd.get("visual", "")
	if visual == "":
		_make_collision(bd)
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
		_workers.append({"rig": rig, "spot": spot, "t": randf() * 3.0, "mode": "work"})


func _play_construction() -> void:
	scale = Vector3(0.15, 0.05, 0.15)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	world.effects.dust(global_position, float(data().get("footprint", 1.5)))
	for k in 3:
		get_tree().create_timer(0.12 + k * 0.28).timeout.connect(func():
			if is_inside_tree():
				AudioManager.play_at("build/hammer", global_position, -2.0))


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
	if _spinner and working:
		_spinner.rotate_object_local(_spinner_axis, delta * _spinner_speed * TAU * 0.25)
	if _smoke:
		_smoke.emitting = working or hp_ratio < 0.5
	if _light and _fire:
		_light.light_energy = 1.5 + sin(_time * 13.0) * 0.12 + sin(_time * 7.3) * 0.1
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
			w.t = 0.9
			rig.play_attack()
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
