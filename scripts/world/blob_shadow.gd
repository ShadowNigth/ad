class_name BlobShadow
extends MeshInstance3D
## Sombra suave y barata (un único cuadro con degradado radial) bajo
## personajes, criaturas, objetos y edificios. Se apoya en el terreno, se
## inclina con la pendiente y se aclara al saltar.
##
## Por qué no se usan sombras en tiempo real: en el renderizador de
## Compatibilidad (el del juego) una luz direccional con sombras se dibuja en
## una pasada aditiva que se mezcla en espacio sRGB y deja la escena lavada al
## mediodía; además duplica las llamadas de dibujo. Ver docs/ARQUITECTURA.md.

static var _mesh: PlaneMesh
static var _mat: StandardMaterial3D

var target: Node3D
var radius := 0.5
var strength := 0.42
var world: Node3D
var follow := true
var _normal_t := 0.0


static func shared_mesh() -> PlaneMesh:
	if _mesh == null:
		_mesh = PlaneMesh.new()
		_mesh.size = Vector2(2.0, 2.0)
	return _mesh


static func shared_material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(0.0, 0.02, 0.04, 1.0)
		_mat.albedo_texture = WorldEffects.glow_texture()
		_mat.vertex_color_use_as_albedo = false
		_mat.disable_receive_shadows = true
		_mat.render_priority = -1
	return _mat


## Crea una sombra que sigue a `who` (se añade al mismo padre del mundo).
static func attach(who: Node3D, r: float, w: Node3D, alpha: float = 0.42) -> BlobShadow:
	var b := BlobShadow.new()
	b.target = who
	b.radius = r
	b.world = w
	b.strength = alpha
	b.mesh = shared_mesh()
	b.material_override = shared_material()
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.transparency = 1.0 - alpha
	b.name = "Sombra"
	who.add_child(b)
	b.top_level = true
	return b


func _process(delta: float) -> void:
	if not follow or not is_instance_valid(target) or world == null:
		return
	var p := target.global_position
	var ground: float = world.height_at(p.x, p.z)
	if ground < -0.05 and world.water_depth_at(p) > 0.2:
		visible = false
		return
	visible = target.is_visible_in_tree()
	var h := maxf(p.y - ground, 0.0)
	var k := clampf(1.0 - h / 3.0, 0.15, 1.0)
	transparency = 1.0 - strength * k
	_normal_t -= delta
	var b := global_transform.basis
	if _normal_t <= 0.0:
		_normal_t = 0.25
		b = _ground_basis(p.x, p.z)
	var s := radius * (0.7 + 0.3 * k)
	global_transform = Transform3D(b.orthonormalized().scaled(Vector3(s, 1.0, s)), Vector3(p.x, ground + 0.05, p.z))


## Orientación según la pendiente del terreno en (x, z).
func _ground_basis(x: float, z: float) -> Basis:
	return BlobShadow.ground_basis(world, x, z)


static func ground_basis(w, x: float, z: float) -> Basis:
	var e := 0.6
	var hx: float = w.height_at(x + e, z) - w.height_at(x - e, z)
	var hz: float = w.height_at(x, z + e) - w.height_at(x, z - e)
	var n := Vector3(-hx, 2.0 * e, -hz).normalized()
	# Base dextrógira (sin espejo) con el eje Y en la normal del terreno.
	var z_axis := Vector3.RIGHT.cross(n).normalized()
	var x_axis := n.cross(z_axis).normalized()
	return Basis(x_axis, n, z_axis)


## Sombra fija (edificios): no se actualiza cada fotograma.
static func place_static(parent: Node3D, pos: Vector3, r: float, w: Node3D, alpha: float = 0.38) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Sombra"
	mi.mesh = shared_mesh()
	mi.material_override = shared_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transparency = 1.0 - alpha
	parent.add_child(mi)
	mi.top_level = true
	var ground: float = w.height_at(pos.x, pos.z)
	mi.global_transform = Transform3D(ground_basis(w, pos.x, pos.z).scaled(Vector3(r, 1.0, r)), Vector3(pos.x, ground + 0.04, pos.z))
	return mi
