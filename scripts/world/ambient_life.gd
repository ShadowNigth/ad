class_name AmbientLife
extends Node3D
## Vida ambiental alrededor del jugador (solo cerca de él, para no gastar en
## zonas lejanas): luciérnagas de noche, mariposas y polen de día, gaviotas
## sobre la costa, hojas que caen en el bosque y peces que saltan en los
## bancos de pesca. Todo se apaga con la lluvia o en calidad baja se reduce.

const BUTTERFLY_COLORS := [Color(1.0, 0.62, 0.15), Color(1.0, 0.92, 0.3), Color(0.45, 0.7, 1.0), Color(1.0, 1.0, 1.0), Color(0.95, 0.45, 0.75)]

var world: Node3D
var _fireflies: CPUParticles3D
var _pollen: CPUParticles3D
var _leaves: CPUParticles3D
var _butterflies: Array = []
var _gulls: Array = []
var _fish_t := 4.0
var _zone_t := 0.0
var _zone := ""
var _low := false
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _wing_mesh: QuadMesh


func setup(w: Node3D) -> void:
	world = w
	_rng.randomize()
	_low = Settings.get_value("quality") == "baja"
	_wing_mesh = QuadMesh.new()
	_wing_mesh.size = Vector2(0.16, 0.13)
	_fireflies = _make_glow_emitter("Luciernagas", 10 if _low else 24, 4.0, Color(0.85, 1.0, 0.35), Vector3(14, 1.2, 14), 0.22)
	_pollen = _make_glow_emitter("Polen", 8 if _low else 18, 5.0, Color(1.0, 0.98, 0.85), Vector3(12, 1.5, 12), 0.08)
	_leaves = _make_leaf_emitter()
	for i in (2 if _low else 5):
		_butterflies.append(_make_flyer(BUTTERFLY_COLORS[i % BUTTERFLY_COLORS.size()], 1.0))
	for i in (1 if _low else 3):
		_gulls.append(_make_flyer(Color(0.95, 0.95, 0.97), 5.5))


func _make_glow_emitter(n: String, amount: int, life: float, color: Color, extents: Vector3, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = life
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = WorldEffects.glow_texture()
	p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0, 0.02, 0)
	p.damping_min = 0.0
	p.damping_max = 0.1
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.0))
	g.set_color(1, Color(color, 0.0))
	g.add_point(0.3, Color(color, 1.0))
	g.add_point(0.5, Color(color, 0.35))
	g.add_point(0.7, Color(color, 1.0))
	p.color_ramp = g
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-20, -6, -20), Vector3(40, 12, 40))
	add_child(p)
	return p


func _make_leaf_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "HojasCayendo"
	p.amount = 5 if _low else 12
	p.lifetime = 6.0
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.09)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.62, 0.25)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(12, 1.0, 12)
	p.direction = Vector3(1, -0.3, 0.2)
	p.spread = 40.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0.2, -0.45, 0.1)
	p.angular_velocity_min = -160.0
	p.angular_velocity_max = 160.0
	p.particle_flag_rotate_y = true
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.75, 0.3))
	g.set_color(1, Color(0.6, 0.75, 0.3))
	p.color_initial_ramp = g
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-16, -12, -16), Vector3(32, 16, 32))
	add_child(p)
	return p


## Mariposa o gaviota: dos alas que aletean y una ruta errante.
func _make_flyer(color: Color, size: float) -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if size < 2.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = color
	m.albedo_texture = WorldEffects.glow_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wings: Array = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		root.add_child(pivot)
		var w := MeshInstance3D.new()
		w.mesh = _wing_mesh
		w.material_override = m
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.rotation.x = -PI * 0.5
		w.position = Vector3(side * 0.08, 0, 0)
		pivot.add_child(w)
		wings.append({"pivot": pivot, "side": side})
	root.scale = Vector3.ONE * size
	return {"node": root, "wings": wings, "pos": Vector3.ZERO, "target": Vector3.ZERO, "phase": _rng.randf() * TAU,
		"speed": 1.2 if size < 2.0 else 6.0, "size": size, "active": false}


func _process(delta: float) -> void:
	if world == null:
		return
	_time += delta
	var player: Node3D = world.get("player")
	if player == null:
		return
	var pp := player.global_position
	var dn = world.get("day_night")
	var dark: float = dn.darkness() if dn else 0.0
	var weather = world.get("weather")
	var raining: bool = weather != null and weather.rain > 0.3
	_zone_t -= delta
	if _zone_t <= 0.0:
		_zone_t = 1.0
		_zone = world.gen.zone_at(pp.x, pp.z) if world.get("gen") else ""
	var near_ground := Vector3(pp.x, pp.y + 1.2, pp.z)
	_set_emitter(_fireflies, dark > 0.6 and not raining and _zone != "playa", near_ground)
	_set_emitter(_pollen, dark < 0.35 and not raining and _zone in ["pradera", "bosque", "jungla"], near_ground)
	_set_emitter(_leaves, not raining and _zone in ["bosque", "jungla"], pp + Vector3(0, 7.0, 0))
	_update_flyers(_butterflies, delta, pp, dark < 0.4 and not raining and _zone in ["pradera", "bosque", "playa", "jungla"], false)
	_update_flyers(_gulls, delta, pp, dark < 0.5 and not raining, true)
	_fish_t -= delta
	if _fish_t <= 0.0:
		_fish_t = _rng.randf_range(3.0, 7.0)
		_fish_jump(pp)


func _set_emitter(p: CPUParticles3D, on: bool, pos: Vector3) -> void:
	if p.emitting != on:
		p.emitting = on
	if on:
		p.global_position = pos


func _update_flyers(list: Array, delta: float, center: Vector3, on: bool, gull: bool) -> void:
	for f in list:
		var node: Node3D = f.node
		if not on:
			if node.visible:
				node.visible = false
				f.active = false
			continue
		if not f.active or (f.pos as Vector3).distance_to(center) > (70.0 if gull else 28.0):
			f.active = true
			f.pos = _spawn_point(center, gull)
			f.target = _spawn_point(center, gull)
			node.visible = true
		var to: Vector3 = f.target - f.pos
		if to.length() < (4.0 if gull else 0.6):
			f.target = _spawn_point(center, gull)
		var dir := to.normalized()
		var p: Vector3 = f.pos + dir * float(f.speed) * delta
		if not gull:
			p.y += sin(_time * 3.0 + float(f.phase)) * 0.02
		f.pos = p
		node.global_position = p
		if Vector2(dir.x, dir.z).length() > 0.01:
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 4.0, 0.0, 1.0))
		# Aleteo: rápido en mariposas, lento y con planeo en gaviotas.
		var flap: float
		if gull:
			var glide := 0.5 + 0.5 * sin(_time * 0.6 + float(f.phase))
			flap = sin(_time * 5.0 + float(f.phase)) * 0.55 * (1.0 - glide) + 0.1
		else:
			flap = sin(_time * 22.0 + float(f.phase)) * 0.9
		for wd in f.wings:
			(wd.pivot as Node3D).rotation.z = flap * float(wd.side)


func _spawn_point(center: Vector3, gull: bool) -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(10.0, 45.0) if gull else _rng.randf_range(2.0, 14.0)
	var x := center.x + cos(a) * r
	var z := center.z + sin(a) * r
	var ground: float = world.height_at(x, z)
	if gull:
		return Vector3(x, maxf(ground, 0.0) + _rng.randf_range(14.0, 26.0), z)
	return Vector3(x, maxf(ground, 0.0) + _rng.randf_range(0.6, 2.2), z)


## Un pez salta fuera del agua cerca de un banco de pesca o en el mar.
func _fish_jump(center: Vector3) -> void:
	var res = world.get("resources")
	var spot := Vector3.INF
	if res:
		for rec in res.nodes:
			if rec.type == "banco_peces" and not rec.depleted and (rec.pos as Vector3).distance_to(center) < 35.0:
				spot = rec.pos + Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5))
				break
	if spot == Vector3.INF:
		for i in 6:
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(10.0, 30.0)
			var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
			if world.water_depth_at(p) > 1.2:
				spot = p
				break
	if spot == Vector3.INF:
		return
	spot.y = 0.0
	var fx = world.get("effects")
	var mi := MeshInstance3D.new()
	mi.mesh = ModelLibrary.mesh("food/fish")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var s := 0.9
	mi.scale = Vector3.ONE * s
	var dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	var start := spot
	var end := spot + dir * 1.6
	mi.global_position = start
	if fx:
		fx.splash(start, 0.6)
	var tw := mi.create_tween()
	tw.tween_method(func(t: float):
		var p := start.lerp(end, t)
		p.y = sin(t * PI) * 1.1 - 0.1
		mi.global_position = p
		mi.rotation = Vector3(lerpf(-1.0, 1.0, t), atan2(-dir.x, -dir.z) + PI * 0.5, 0.0), 0.0, 1.0, 0.75)
	tw.tween_callback(func():
		if fx:
			fx.splash(end, 0.5)
		AudioManager.play_at("footsteps/water", end, -10.0)
		mi.queue_free())
