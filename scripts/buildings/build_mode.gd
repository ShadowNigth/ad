class_name BuildMode
extends Node3D
## Modo construcción: vista previa translúcida (verde válido / rojo inválido)
## delante del jugador, rotación, confirmación y cancelación.

signal validity_changed(ok: bool, reason: String)

var world: World
var active := false
var type_id := ""
var rot_deg := 0.0
var current_pos := Vector3.ZERO
var valid := false
var reason := ""
var _ghost: MeshInstance3D
var _ring: MeshInstance3D
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D
var _check_t := 0.0
var _offset := 0.0


func setup(w: World) -> void:
	world = w
	_mat_ok = StandardMaterial3D.new()
	_mat_ok.albedo_color = Color(0.35, 1.0, 0.45, 0.5)
	_mat_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_bad = _mat_ok.duplicate()
	_mat_bad.albedo_color = Color(1.0, 0.3, 0.25, 0.5)
	_ghost = MeshInstance3D.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 4
	_ring.mesh = torus
	_ring.visible = false
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func start(t: String) -> void:
	var check := Economy.can_build(t)
	if not check.ok:
		EventBus.notify(check.reason, "warn")
		AudioManager.play_ui("ui/error")
		return
	type_id = t
	active = true
	var lvl := GameData.building_level(t, 1)
	_ghost.mesh = ModelLibrary.baked_merged(lvl.models, "%s_1" % t)
	_ghost.material_override = _mat_ok
	_ghost.visible = true
	_ring.visible = true
	var fp := float(GameData.building(t).get("footprint", 1.5))
	_ring.scale = Vector3(fp, 1.0, fp)
	_offset = fp + 1.8
	rot_deg = snappedf(rad_to_deg(world.player.rig.rotation.y) + 180.0, 45.0)
	_check_t = 0.0
	AudioManager.play_ui("ui/open")
	EventBus.build_mode_changed.emit(true)


func cancel() -> void:
	if not active:
		return
	active = false
	_ghost.visible = false
	_ring.visible = false
	AudioManager.play_ui("ui/close")
	EventBus.build_mode_changed.emit(false)


func rotate_step(deg: float = 45.0) -> void:
	rot_deg = fposmod(rot_deg + deg, 360.0)
	_check_t = 0.0
	AudioManager.play_ui("ui/tick")


func confirm() -> bool:
	if not active:
		return false
	_update_placement(true)
	if not valid:
		EventBus.notify(reason, "warn")
		AudioManager.play_ui("ui/error")
		return false
	var check := Economy.can_build(type_id)
	if not check.ok:
		EventBus.notify(check.reason, "warn")
		AudioManager.play_ui("ui/error")
		return false
	var uid := Economy.place_building(type_id, current_pos, rot_deg)
	if uid < 0:
		return false
	# Si se puede construir otro igual se mantiene el modo para encadenar.
	if not Economy.can_build(type_id).ok or type_id in ["refugio"]:
		cancel()
	return true


func _process(delta: float) -> void:
	if not active:
		return
	_check_t -= delta
	_update_placement(_check_t <= 0.0)
	if _check_t <= 0.0:
		_check_t = 0.15
	_ring.rotation.y += delta


func _update_placement(validate: bool) -> void:
	var p: Player = world.player
	var fwd := p.forward_dir()
	var target := p.global_position + fwd * _offset
	target.x = snappedf(target.x, 0.5)
	target.z = snappedf(target.z, 0.5)
	target.y = world.gen.height_at(target.x, target.z)
	current_pos = target
	_ghost.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(rot_deg)), target)
	_ring.global_position = target + Vector3(0, 0.08, 0)
	if validate:
		var res: Dictionary = world.buildings.placement_valid(type_id, target, rot_deg)
		var was := valid
		valid = res.ok
		reason = res.reason
		_ghost.material_override = _mat_ok if valid else _mat_bad
		_ring.material_override = _mat_ok if valid else _mat_bad
		if was != valid or true:
			validity_changed.emit(valid, reason)
