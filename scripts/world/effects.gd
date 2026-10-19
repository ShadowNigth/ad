class_name WorldEffects
extends Node3D
## Efectos visuales ligeros (partículas por CPU, pensadas para móvil):
## astillas al talar, polvo al picar, explosiones, polvo de construcción.

const COLORS := {
	"palmera": Color(0.72, 0.48, 0.3), "arbol": Color(0.7, 0.45, 0.28), "arbol_oscuro": Color(0.45, 0.32, 0.22),
	"pino": Color(0.62, 0.42, 0.26), "roca": Color(0.62, 0.6, 0.58), "roca_hierro": Color(0.82, 0.48, 0.34),
	"roca_carbon": Color(0.2, 0.2, 0.22), "cristal": Color(0.5, 0.9, 1.0), "arbusto_bayas": Color(0.3, 0.6, 0.28),
	"hierba_alta": Color(0.42, 0.72, 0.3), "planta_medicinal": Color(0.62, 0.42, 0.8), "hongos": Color(0.85, 0.3, 0.25),
	"banco_peces": Color(0.75, 0.9, 1.0),
}

var _mesh: BoxMesh
var _mat_cache: Dictionary = {}
var budget := 1.0


func _ready() -> void:
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(0.12, 0.12, 0.12)


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.vertex_color_use_as_albedo = false
		_mat_cache[key] = m
	return _mat_cache[key]


func burst(pos: Vector3, color: Color, amount: int = 10, speed: float = 3.5, life: float = 0.7, size: float = 1.0, gravity: float = 9.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
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
	p.angular_velocity_min = -200.0
	p.angular_velocity_max = 200.0
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


func hit(pos: Vector3, node_type: String) -> void:
	burst(pos, COLORS.get(node_type, Color(0.6, 0.55, 0.45)), 9, 3.2, 0.6, 1.0)


func explosion(pos: Vector3) -> void:
	burst(pos, Color(0.55, 0.5, 0.45), 28, 9.0, 1.4, 2.5)
	burst(pos, Color(1.0, 0.6, 0.2), 14, 6.0, 0.6, 1.6, 2.0)
	AudioManager.play_at("build/wood_break", pos, 4.0)
	AudioManager.play_at("gather/rock_break", pos, 4.0)


func dust(pos: Vector3, radius: float = 1.5) -> void:
	burst(pos + Vector3(0, 0.3, 0), Color(0.78, 0.7, 0.55), 16, 2.5 + radius, 0.9, 1.4, 3.0)


func sparkle(pos: Vector3, color: Color = Color(1, 0.95, 0.5)) -> void:
	burst(pos, color, 14, 3.0, 0.9, 0.7, -0.5)


## Fuego continuo (fogatas, braseros). Devuelve el nodo para poder liberarlo.
func make_fire(parent: Node3D, offset: Vector3, scale_f: float = 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(int(14 * budget), 6)
	p.lifetime = 0.8
	p.mesh = _mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = 0.8 * scale_f
	p.initial_velocity_max = 1.6 * scale_f
	p.gravity = Vector3(0, 1.2, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25 * scale_f
	p.scale_amount_min = 1.2 * scale_f
	p.scale_amount_max = 2.2 * scale_f
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	grad.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	grad.add_point(0.45, Color(1.0, 0.45, 0.1, 0.9))
	p.color_ramp = grad
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	p.position = offset
	parent.add_child(p)
	return p


func make_smoke(parent: Node3D, offset: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(int(8 * budget), 4)
	p.lifetime = 3.0
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0.25, 0.3, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.55, 0.55, 0.55))
	grad.set_color(1, Color(0.8, 0.8, 0.8, 0.0))
	p.color_ramp = grad
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.2))
	p.scale_amount_curve = curve
	p.position = offset
	parent.add_child(p)
	return p
