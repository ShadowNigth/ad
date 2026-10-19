class_name Pickup
extends Node3D
## Objeto caído en el suelo (botín de enemigos, inventario lleno...).
## Se recoge automáticamente al acercarse. Desaparece tras un tiempo.

var item_id := ""
var qty := 1
var lifetime := 300.0
var _t := 0.0
var _mesh: MeshInstance3D
var _collect_cd := 0.6
var _base_y := 0.0


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
	add_child(_mesh)


func _ready() -> void:
	_base_y = position.y


func _process(delta: float) -> void:
	_t += delta
	_collect_cd -= delta
	if _mesh:
		_mesh.position.y = 0.25 + sin(_t * 3.0) * 0.08
		_mesh.rotation.y += delta * 1.5
	if _t > lifetime:
		queue_free()
		return
	if _collect_cd > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and not player.get("dead") and player.global_position.distance_to(global_position) < 1.7:
		var left := GameState.give(item_id, qty)
		var got := qty - left
		if got > 0:
			AudioManager.play_at("gather/pickup", global_position, -4.0)
			EventBus.floating_text.emit(global_position + Vector3.UP, "+%d %s" % [got, GameData.item_name(item_id)], Color(1, 0.95, 0.6))
			EventBus.item_gathered.emit(item_id, got)
		qty = left
		if qty <= 0:
			queue_free()
		else:
			_collect_cd = 3.0
