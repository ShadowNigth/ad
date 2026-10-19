class_name Pickup
extends Node3D
## Objeto caído en el suelo (botín de enemigos, tesoros, inventario lleno...).
## Sale despedido en arco y rebota; al acercarse el jugador vuela hacia él
## (imán) y se recoge con un destello. Desaparece tras un tiempo.

var item_id := ""
var qty := 1
var lifetime := 300.0
## Lo ha soltado el propio jugador: el imán no actúa hasta que se aleja.
var player_drop := false
var _t := 0.0
var _mesh: MeshInstance3D
var _glow: MeshInstance3D
var _collect_cd := 0.6
var _vel := Vector3.ZERO
var _airborne := false
var _bounces := 0
var _magnet := false
var _magnet_speed := 0.0
var _world: Node3D
var _spin := 1.5


func setup(id: String, amount: int) -> void:
	item_id = id
	qty = amount
	_mesh = MeshInstance3D.new()
	var it := GameData.item(id)
	var model: String = it.get("drop_model", it.get("icon_model", "survival/box"))
	var tint := Color.WHITE
	if it.has("icon_tint"):
		tint = Color(it.icon_tint[0], it.icon_tint[1], it.icon_tint[2])
	_mesh.mesh = ModelLibrary.tinted_mesh(model, tint)
	var size := ModelLibrary.aabb(model).get_longest_axis_size()
	var s := 0.55 / maxf(size, 0.05)
	_mesh.scale = Vector3.ONE * s
	_mesh.position.y = 0.25
	add_child(_mesh)
	# Brillo suave en el suelo para verlo entre la hierba.
	_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	q.orientation = PlaneMesh.FACE_Y
	_glow.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = WorldEffects.glow_texture()
	m.albedo_color = Color(1.0, 0.9, 0.5, 0.35)
	_glow.material_override = m
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position.y = 0.04
	add_child(_glow)


func bind_world(world: Node3D) -> void:
	_world = world


## Lanza el objeto con una velocidad inicial (arco con rebotes).
func launch(velocity: Vector3, world: Node3D) -> void:
	_vel = velocity
	_world = world
	_airborne = true
	_spin = 9.0
	_collect_cd = maxf(_collect_cd, 0.7)


func _ground_y() -> float:
	if _world and _world.has_method("height_at"):
		return maxf(_world.height_at(global_position.x, global_position.z), 0.0) + 0.05
	return global_position.y


func _process(delta: float) -> void:
	_t += delta
	_collect_cd -= delta
	if _airborne:
		_update_flight(delta)
	elif _mesh and not _magnet:
		_mesh.position.y = 0.25 + sin(_t * 3.0) * 0.08
	if _mesh:
		_mesh.rotation.y += delta * _spin
		_spin = move_toward(_spin, 1.5, delta * 6.0)
	if _glow and not _magnet:
		var pulse := 0.28 + sin(_t * 2.5) * 0.08
		(_glow.material_override as StandardMaterial3D).albedo_color.a = pulse
	if _t > lifetime:
		queue_free()
		return
	if _collect_cd > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player.get("dead"):
		_magnet = false
		return
	var target := player.global_position + Vector3.UP * 0.9
	var dist := global_position.distance_to(player.global_position)
	var magnet_r := GameData.bf("player.pickup_magnet_radius", 3.2)
	if player_drop:
		if dist > magnet_r + 0.5:
			player_drop = false
		return
	if not _magnet and dist < magnet_r and GameState.inventory.space_for(item_id) > 0:
		_magnet = true
		_airborne = false
		_magnet_speed = 2.0
		if _glow:
			_glow.visible = false
	if _magnet:
		# Acelera hacia el jugador.
		_magnet_speed = minf(_magnet_speed + delta * 22.0, 16.0)
		var to := target - (global_position + Vector3.UP * _mesh.position.y)
		var step := _magnet_speed * delta
		if to.length() <= maxf(step, GameData.bf("player.pickup_collect_radius", 0.7)):
			_collect(player)
			return
		global_position += to.normalized() * step
		_mesh.scale = _mesh.scale.lerp(_mesh.scale * 0.92, clampf(delta * 6.0, 0.0, 1.0))
		if dist > magnet_r * 2.5:
			_magnet = false
			if _glow:
				_glow.visible = true


func _update_flight(delta: float) -> void:
	_vel.y -= 16.0 * delta
	global_position += _vel * delta
	var gy := _ground_y()
	if global_position.y <= gy:
		global_position.y = gy
		if _bounces < 2 and _vel.y < -1.5:
			_bounces += 1
			_vel = Vector3(_vel.x * 0.5, -_vel.y * 0.38, _vel.z * 0.5)
		else:
			_airborne = false
			_vel = Vector3.ZERO


func _collect(player: Node3D) -> void:
	var left := GameState.give(item_id, qty)
	var got := qty - left
	if got > 0:
		AudioManager.play_at("gather/pickup", global_position, -4.0, 0.15)
		EventBus.floating_text.emit(player.global_position + Vector3.UP * 2.0, "+%d %s" % [got, GameData.item_name(item_id)], Color(1, 0.95, 0.6))
		EventBus.item_gathered.emit(item_id, got)
		EventBus.item_collected_at.emit(item_id, got, global_position)
		var fx = _world.get("effects") if _world else null
		if fx:
			fx.flash(global_position, Color(1.0, 0.92, 0.6), 0.8, 0.14)
	qty = left
	if qty <= 0:
		queue_free()
	else:
		# No cabe todo: vuelve al suelo y espera.
		_magnet = false
		_collect_cd = 3.0
		global_position.y = _ground_y()
		if _glow:
			_glow.visible = true
