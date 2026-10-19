class_name WorldEffects
extends Node3D
## Efectos visuales ligeros (partículas por CPU y mallas sencillas, pensados
## para móvil): astillas y hojas al talar, chispas al golpear, estela del arma,
## anillos, polvo, salpicaduras, destellos, confeti y avisos sobre criaturas.
## Hay un tope de efectos simultáneos y la cantidad se reduce en calidad baja.

const COLORS := {
	"palmera": Color(0.72, 0.48, 0.3), "arbol": Color(0.7, 0.45, 0.28), "arbol_oscuro": Color(0.45, 0.32, 0.22),
	"pino": Color(0.62, 0.42, 0.26), "roca": Color(0.62, 0.6, 0.58), "roca_hierro": Color(0.82, 0.48, 0.34),
	"roca_carbon": Color(0.2, 0.2, 0.22), "cristal": Color(0.5, 0.9, 1.0), "arbusto_bayas": Color(0.3, 0.6, 0.28),
	"hierba_alta": Color(0.42, 0.72, 0.3), "planta_medicinal": Color(0.62, 0.42, 0.8), "hongos": Color(0.85, 0.3, 0.25),
	"banco_peces": Color(0.75, 0.9, 1.0),
}
## Hojas que se desprenden al golpear árboles y arbustos.
const LEAF_COLORS := {
	"palmera": Color(0.38, 0.64, 0.26), "arbol": Color(0.32, 0.6, 0.24), "arbol_oscuro": Color(0.22, 0.42, 0.2),
	"pino": Color(0.2, 0.44, 0.26), "arbusto_bayas": Color(0.3, 0.6, 0.28), "hierba_alta": Color(0.55, 0.78, 0.32),
	"planta_medicinal": Color(0.45, 0.7, 0.38),
}
## Nodos de piedra: los golpes sueltan chispas.
const STONE_TYPES := ["roca", "roca_hierro", "roca_carbon", "cristal"]
const MAX_ACTIVE := 40

static var _glow_tex: GradientTexture2D

var budget := 1.0
var _mesh: BoxMesh
var _quad: QuadMesh
var _leaf: QuadMesh
var _slash_mesh: ArrayMesh
var _ring_mesh: ArrayMesh
var _mat_cache: Dictionary = {}
var _active := 0


func _ready() -> void:
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(0.12, 0.12, 0.12)
	_quad = QuadMesh.new()
	_quad.size = Vector2(0.5, 0.5)
	_leaf = QuadMesh.new()
	_leaf.size = Vector2(0.16, 0.1)
	_slash_mesh = _build_crescent()
	_ring_mesh = _build_ring()


## Textura radial suave (destellos, humo, luciérnagas, brillo de objetos).
static func glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 64
		_glow_tex.height = 64
	return _glow_tex


# ------------------------------------------------------------------ materiales
func _material(color: Color) -> StandardMaterial3D:
	var key := "lit" + color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_mat_cache[key] = m
	return _mat_cache[key]


## Material sin iluminación con color de vértice (para rampas de color).
func _unshaded(additive: bool, billboard: bool, textured: bool, double_sided: bool = false) -> StandardMaterial3D:
	var key := "u%d%d%d%d" % [int(additive), int(billboard), int(textured), int(double_sided)]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		if billboard:
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		if textured:
			m.albedo_texture = glow_texture()
		if double_sided:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		_mat_cache[key] = m
	return _mat_cache[key]


func _leaf_material(color: Color) -> StandardMaterial3D:
	var key := "leaf" + color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_cache[key] = m
	return _mat_cache[key]


func _can_spawn() -> bool:
	return _active < MAX_ACTIVE and is_inside_tree()


func _one_shot(p: CPUParticles3D, pos: Vector3, life: float) -> void:
	p.one_shot = true
	p.emitting = false
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_active += 1
	get_tree().create_timer(life + 0.35).timeout.connect(func():
		_active -= 1
		p.queue_free())


static func _ramp(c0: Color, c1: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	return g


static func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c


# ------------------------------------------------------------------ ráfagas básicas
func burst(pos: Vector3, color: Color, amount: int = 10, speed: float = 3.5, life: float = 0.7, size: float = 1.0, gravity: float = 9.0) -> void:
	if not _can_spawn():
		return
	var p := CPUParticles3D.new()
	p.amount = maxi(int(amount * budget), 3)
	p.lifetime = life
	p.explosiveness = 0.95
	p.mesh = _mesh
	p.material_override = _material(color)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.5 * size
	p.scale_amount_max = 1.2 * size
	p.scale_amount_curve = _curve(1.0, 0.35)
	p.angular_velocity_min = -200.0
	p.angular_velocity_max = 200.0
	_one_shot(p, pos, life)


## Golpe a un recurso: astillas del color del material, hojas en árboles y
## arbustos, y chispas en las rocas.
func hit(pos: Vector3, node_type: String) -> void:
	burst(pos, COLORS.get(node_type, Color(0.6, 0.55, 0.45)), 9, 3.2, 0.6, 1.0)
	if LEAF_COLORS.has(node_type):
		leaves(pos + Vector3.UP * 0.9, LEAF_COLORS[node_type], 7)
	elif node_type in STONE_TYPES:
		spark(pos, Color(1.0, 0.85, 0.5), 6)


## Hojas que caen balanceándose.
func leaves(pos: Vector3, color: Color, amount: int = 8, spread_radius: float = 0.6) -> void:
	if not _can_spawn():
		return
	var p := CPUParticles3D.new()
	p.amount = maxi(int(amount * budget), 3)
	p.lifetime = 1.8
	p.explosiveness = 0.9
	p.mesh = _leaf
	p.material_override = _leaf_material(color)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread_radius
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0.3, -2.2, 0)
	p.damping_min = 1.2
	p.damping_max = 2.0
	p.angular_velocity_min = -280.0
	p.angular_velocity_max = 280.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.5
	_one_shot(p, pos, 1.8)


## Chispas brillantes y rápidas (golpes de metal, piedra y combate).
func spark(pos: Vector3, color: Color = Color(1.0, 0.9, 0.55), amount: int = 8) -> void:
	if not _can_spawn():
		return
	var p := CPUParticles3D.new()
	p.amount = maxi(int(amount * budget), 3)
	p.lifetime = 0.3
	p.explosiveness = 1.0
	p.mesh = _quad
	p.material_override = _unshaded(true, true, true)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 3.5
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -8.0, 0)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.45
	p.scale_amount_curve = _curve(1.0, 0.0)
	p.color = color
	_one_shot(p, pos, 0.3)


## Destello circular que crece y se apaga.
func flash(pos: Vector3, color: Color, size: float = 1.2, life: float = 0.16) -> void:
	if not is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = glow_texture()
	m.albedo_color = color
	m.no_depth_test = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.4
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 2.0, life).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)


## Impacto en combate: chispas, destello y unas pocas astillas.
func impact(pos: Vector3, color: Color = Color(1.0, 0.92, 0.7)) -> void:
	spark(pos, color, 9)
	flash(pos, color, 1.0, 0.14)


## Estela curva del arma o herramienta delante del jugador.
func slash(origin: Vector3, dir: Vector3, reach: float, color: Color = Color(1.0, 0.97, 0.85)) -> void:
	if not is_inside_tree() or dir.length() < 0.01:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _slash_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var yaw := atan2(-dir.x, -dir.z)
	var s := maxf(reach, 0.8)
	mi.global_position = origin
	mi.rotation = Vector3(0.12, yaw + 0.7, -0.25)
	mi.scale = Vector3(s, s, s)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "rotation:y", yaw - 0.55, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.24).set_delay(0.06)
	tw.chain().tween_callback(mi.queue_free)


## Anillo plano que se expande (aterrizajes, mejoras, recogidas).
func ring(pos: Vector3, color: Color, radius: float = 1.5, life: float = 0.45) -> void:
	if not is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.06
	mi.scale = Vector3.ONE * radius * 0.15
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Nube de humo o polvo suave.
func poof(pos: Vector3, color: Color, amount: int = 10, size: float = 1.0, life: float = 0.9, rise: float = 0.6) -> void:
	if not _can_spawn():
		return
	var p := CPUParticles3D.new()
	p.amount = maxi(int(amount * budget), 3)
	p.lifetime = life
	p.explosiveness = 0.92
	p.mesh = _quad
	p.material_override = _unshaded(false, true, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3 * size
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.6 * size
	p.initial_velocity_max = 1.8 * size
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.gravity = Vector3(0, rise, 0)
	p.scale_amount_min = 1.2 * size
	p.scale_amount_max = 2.2 * size
	p.scale_amount_curve = _curve(0.6, 1.6)
	p.color_ramp = _ramp(Color(color.r, color.g, color.b, 0.7), Color(color.r, color.g, color.b, 0.0))
	_one_shot(p, pos, life)


func dust(pos: Vector3, radius: float = 1.5) -> void:
	poof(pos + Vector3(0, 0.25, 0), Color(0.82, 0.74, 0.6), 10 + int(radius * 3.0), 0.8 + radius * 0.35, 1.0, 0.3)
	burst(pos + Vector3(0, 0.3, 0), Color(0.62, 0.52, 0.38), 8, 2.0 + radius, 0.7, 0.8, 6.0)


## Pequeña nube de polvo bajo los pies (correr, aterrizar).
func footstep_dust(pos: Vector3, color: Color = Color(0.82, 0.74, 0.6), amount: int = 4) -> void:
	poof(pos + Vector3(0, 0.12, 0), color, amount, 0.45, 0.6, 0.2)


## Salpicadura de agua con gotas y onda.
func splash(pos: Vector3, size: float = 1.0) -> void:
	if not _can_spawn():
		return
	var p := CPUParticles3D.new()
	p.amount = maxi(int(12 * size * budget), 4)
	p.lifetime = 0.65
	p.explosiveness = 0.95
	p.mesh = _quad
	p.material_override = _unshaded(false, true, true)
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 2.0 * size
	p.initial_velocity_max = 4.2 * size
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.5
	p.color_ramp = _ramp(Color(0.92, 0.97, 1.0, 0.95), Color(0.75, 0.9, 1.0, 0.0))
	_one_shot(p, pos, 0.65)
	ring(pos, Color(0.85, 0.95, 1.0, 0.8), 1.2 * size, 0.6)


## Destellos que suben (mejoras, curación, objetos raros).
func sparkle(pos: Vector3, color: Color = Color(1, 0.95, 0.5), amount: int = 14) -> void:
	if not _can_spawn():
		return
	var p := CPUParticles3D.new()
	p.amount = maxi(int(amount * budget), 4)
	p.lifetime = 1.1
	p.explosiveness = 0.75
	p.mesh = _quad
	p.material_override = _unshaded(true, true, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.7
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 0.8
	p.damping_max = 1.4
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	p.scale_amount_curve = _curve(1.0, 0.0)
	p.color = color
	_one_shot(p, pos, 1.1)


## Confeti de colores (objetivos cumplidos, subida de nivel).
func confetti(pos: Vector3, amount: int = 26) -> void:
	if not _can_spawn():
		return
	var p := CPUParticles3D.new()
	p.amount = maxi(int(amount * budget), 8)
	p.lifetime = 1.8
	p.explosiveness = 0.95
	p.mesh = _leaf
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = m
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -5.0, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.6
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.35, 0.3))
	g.set_color(1, Color(0.35, 0.6, 1.0))
	g.add_point(0.25, Color(1.0, 0.85, 0.25))
	g.add_point(0.5, Color(0.4, 0.9, 0.4))
	g.add_point(0.75, Color(0.95, 0.5, 0.95))
	p.color_initial_ramp = g
	_one_shot(p, pos, 1.8)


## Celebración alrededor de un punto: anillo dorado, destellos y confeti.
func celebrate(pos: Vector3) -> void:
	ring(pos, Color(1.0, 0.85, 0.35, 0.9), 2.6, 0.7)
	sparkle(pos + Vector3.UP * 0.8, Color(1.0, 0.9, 0.45), 18)
	confetti(pos + Vector3.UP * 1.6)


func explosion(pos: Vector3) -> void:
	flash(pos + Vector3.UP, Color(1.0, 0.7, 0.3), 4.0, 0.25)
	poof(pos + Vector3.UP * 0.5, Color(0.45, 0.42, 0.4), 16, 2.0, 1.6, 1.0)
	burst(pos, Color(0.55, 0.5, 0.45), 22, 9.0, 1.4, 2.2)
	spark(pos + Vector3.UP * 0.5, Color(1.0, 0.6, 0.2), 14)
	AudioManager.play_at("build/wood_break", pos, 4.0)
	AudioManager.play_at("gather/rock_break", pos, 4.0)


## Signo sobre una criatura ("!" al detectarte, "?" al perderte de vista).
func alert_mark(target: Node3D, height: float, text: String = "!", color: Color = Color(1.0, 0.82, 0.2)) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	var old := target.get_node_or_null("Aviso")
	if old:
		old.queue_free()
	var l := Label3D.new()
	l.name = "Aviso"
	l.text = text
	UITheme.get_theme()
	l.font = UITheme.font_title
	l.font_size = 120
	l.outline_size = 28
	l.modulate = color
	l.outline_modulate = Color(0.15, 0.05, 0.0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.006
	l.position = Vector3(0, height + 0.55, 0)
	l.scale = Vector3.ONE * 0.2
	target.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.1)
	tw.tween_interval(0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(l, "position:y", height + 0.95, 0.3)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ fuego y humo continuos
## Fuego continuo (fogatas, braseros) con llamas brillantes y brasas.
func make_fire(parent: Node3D, offset: Vector3, scale_f: float = 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(int(16 * budget), 8)
	p.lifetime = 0.75
	p.mesh = _quad
	p.material_override = _unshaded(true, true, true)
	p.direction = Vector3.UP
	p.spread = 14.0
	p.initial_velocity_min = 0.7 * scale_f
	p.initial_velocity_max = 1.5 * scale_f
	p.gravity = Vector3(0, 1.4, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.22 * scale_f
	p.scale_amount_min = 1.0 * scale_f
	p.scale_amount_max = 1.8 * scale_f
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.35, 0.95))
	grad.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	grad.add_point(0.4, Color(1.0, 0.5, 0.12, 0.85))
	p.color_ramp = grad
	p.scale_amount_curve = _curve(1.0, 0.25)
	p.position = offset
	parent.add_child(p)
	# Brasas que suben y parpadean.
	var e := CPUParticles3D.new()
	e.amount = maxi(int(6 * budget), 3)
	e.lifetime = 1.6
	e.mesh = _quad
	e.material_override = _unshaded(true, true, true)
	e.direction = Vector3.UP
	e.spread = 25.0
	e.initial_velocity_min = 0.8 * scale_f
	e.initial_velocity_max = 1.8 * scale_f
	e.gravity = Vector3(0.2, 0.5, 0)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.25 * scale_f
	e.scale_amount_min = 0.12
	e.scale_amount_max = 0.22
	e.color_ramp = _ramp(Color(1.0, 0.75, 0.3, 1.0), Color(1.0, 0.3, 0.05, 0.0))
	e.position = Vector3(0, 0.2, 0)
	p.add_child(e)
	return p


func make_smoke(parent: Node3D, offset: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(int(8 * budget), 4)
	p.lifetime = 3.0
	p.mesh = _quad
	p.material_override = _unshaded(false, true, true)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0.25, 0.3, 0)
	p.scale_amount_min = 1.6
	p.scale_amount_max = 2.6
	p.color_ramp = _ramp(Color(0.5, 0.5, 0.5, 0.5), Color(0.8, 0.8, 0.8, 0.0))
	p.scale_amount_curve = _curve(0.5, 2.2)
	p.position = offset
	parent.add_child(p)
	return p


# ------------------------------------------------------------------ mallas de efectos
## Media luna para la estela del arma (alfa creciente hacia el extremo).
func _build_crescent() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	var a0 := deg_to_rad(-75.0)
	var a1 := deg_to_rad(75.0)
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var ang0 := lerpf(a0, a1, t0)
		var ang1 := lerpf(a0, a1, t1)
		# Más ancho en el centro y fino en los extremos.
		var w0 := 0.1 + 0.32 * sin(t0 * PI)
		var w1 := 0.1 + 0.32 * sin(t1 * PI)
		var o0 := Vector3(sin(ang0), 0, -cos(ang0))
		var o1 := Vector3(sin(ang1), 0, -cos(ang1))
		var c0 := Color(1, 1, 1, t0 * t0)
		var c1 := Color(1, 1, 1, t1 * t1)
		var pa := o0 * 1.0
		var pb := o0 * (1.0 - w0)
		var pc := o1 * 1.0
		var pd := o1 * (1.0 - w1)
		for v in [[pa, c0], [pb, Color(c0, c0.a * 0.2)], [pc, c1], [pc, c1], [pb, Color(c0, c0.a * 0.2)], [pd, Color(c1, c1.a * 0.2)]]:
			st.set_color(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	return st.commit()


## Corona circular fina para las ondas.
func _build_ring() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 32
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		var outer := Color(1, 1, 1, 0.0)
		var mid := Color(1, 1, 1, 1.0)
		var inner := Color(1, 1, 1, 0.0)
		# Dos bandas: interior (transparente → opaco) y exterior (opaco → transparente).
		for band in [[0.78, 0.9, inner, mid], [0.9, 1.0, mid, outer]]:
			var r0: float = band[0]
			var r1: float = band[1]
			var ca: Color = band[2]
			var cb: Color = band[3]
			for v in [[o0 * r0, ca], [o0 * r1, cb], [o1 * r1, cb], [o0 * r0, ca], [o1 * r1, cb], [o1 * r0, ca]]:
				st.set_color(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	return st.commit()
