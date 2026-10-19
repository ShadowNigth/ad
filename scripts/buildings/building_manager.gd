class_name BuildingManager
extends Node3D
## Crea y mantiene los nodos visuales de los edificios de Economy, valida la
## colocación y responde a mejoras, daños y demoliciones.

var world: World
var nodes: Dictionary = {}       # uid -> Building
var grid := SpatialGrid.new(8.0)


func setup(w: World) -> void:
	world = w
	for rec in Economy.buildings:
		_spawn(rec, false)
	EventBus.building_placed.connect(_on_placed)
	EventBus.building_removed.connect(_on_removed)
	EventBus.building_damaged.connect(_on_damaged)
	EventBus.building_upgraded.connect(_on_upgraded)


func _spawn(rec: Dictionary, animate: bool) -> Building:
	var b := Building.new()
	add_child(b)
	b.setup(world, rec, animate)
	nodes[int(rec.uid)] = b
	grid.insert(int(rec.uid), b.position)
	return b


func _on_placed(uid: int, type_id: String) -> void:
	var rec := Economy.get_building(uid)
	if rec.is_empty():
		return
	var b := _spawn(rec, true)
	world.resources.clear_area(b.position, b.footprint())
	AudioManager.play_at("build/place", b.position)
	GameState.add_xp(int(GameData.b("progression.xp_build", 10)))
	EventBus.notify("%s construido." % GameData.building(type_id).name, "good")


func _on_upgraded(uid: int, type_id: String, level: int) -> void:
	var b: Building = nodes.get(uid)
	if b:
		AudioManager.play_at("build/creak", b.position)
		AudioManager.play("events/upgrade", -4.0)
		world.effects.sparkle(b.global_position + Vector3.UP * 2.0)
	GameState.add_xp(int(GameData.b("progression.xp_upgrade", 14)))
	EventBus.notify("%s mejorado a nivel %d." % [GameData.building(type_id).name, level], "good")


func _on_removed(uid: int, _type_id: String) -> void:
	var b: Building = nodes.get(uid)
	if b:
		grid.remove(uid, b.position)
		world.effects.dust(b.global_position, b.footprint())
		AudioManager.play_at("build/wood_break", b.position)
		b.queue_free()
	nodes.erase(uid)


func _on_damaged(uid: int, hp: float) -> void:
	var b: Building = nodes.get(uid)
	if b:
		world.effects.hit(b.global_position + Vector3.UP, "arbol")
		AudioManager.play_at("build/plank", b.position, -2.0)
		if hp <= 0.0:
			EventBus.notify("¡%s ha quedado destruido! Repáralo." % GameData.building(b.type_id).name, "bad")


func get_building_node(uid: int) -> Building:
	return nodes.get(uid)


## uid del edificio más cercano cuyo contorno esté dentro de `radius`, o -1.
func nearest(pos: Vector3, radius: float) -> int:
	var best := -1
	var best_d := INF
	for e in grid.query(pos, radius + 4.0):
		var b: Building = nodes.get(e[0])
		if b == null or Economy.get_building(int(e[0])).is_empty():
			continue
		var d := Vector2(pos.x, pos.z).distance_to(Vector2(b.position.x, b.position.z)) - b.footprint()
		if d <= radius and d < best_d:
			best_d = d
			best = int(e[0])
	return best


func blocks(pos: Vector3, radius: float) -> bool:
	for e in grid.query(pos, radius + 4.0):
		var b: Building = nodes.get(e[0])
		if b and Vector2(pos.x, pos.z).distance_to(Vector2(b.position.x, b.position.z)) < radius + b.footprint():
			return true
	return false


## Valida una posición de construcción. Devuelve {"ok": bool, "reason": String}.
func placement_valid(type_id: String, pos: Vector3, rot_deg: float) -> Dictionary:
	var bd := GameData.building(type_id)
	var fp := float(bd.get("footprint", 1.5))
	var gen: IslandGenerator = world.gen
	if not gen.in_bounds(pos.x, pos.z):
		return {"ok": false, "reason": "Fuera de la isla"}
	var region := gen.region_at(pos.x, pos.z)
	if region != "" and not GameState.is_region_unlocked(region):
		return {"ok": false, "reason": "Región bloqueada"}
	var min_h := INF
	var max_h := -INF
	var samples := [Vector2.ZERO, Vector2(fp, 0), Vector2(-fp, 0), Vector2(0, fp), Vector2(0, -fp),
		Vector2(fp, fp) * 0.7, Vector2(-fp, fp) * 0.7, Vector2(fp, -fp) * 0.7, Vector2(-fp, -fp) * 0.7]
	for s in samples:
		var h := gen.height_at(pos.x + s.x, pos.z + s.y)
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
	if min_h < 0.25:
		return {"ok": false, "reason": "Demasiado cerca del agua"}
	if max_h - min_h > maxf(1.1, fp * 0.45):
		return {"ok": false, "reason": "Terreno demasiado inclinado"}
	if blocks(pos, fp + 0.3):
		return {"ok": false, "reason": "Choca con otro edificio"}
	for poi in world.pois.pois:
		if poi.type in ["shipwreck", "bridge", "cave_gate", "ruins", "lookout", "chest"]:
			if Vector2(pos.x, pos.z).distance_to(Vector2(poi.pos[0], poi.pos[1])) < fp + 5.0:
				return {"ok": false, "reason": "Demasiado cerca de un lugar de interés"}
	# Árboles y rocas grandes estorban; la vegetación pequeña se despeja sola.
	for e in world.resources.grid.query(pos, fp + 2.0):
		var rec: Dictionary = world.resources.nodes[e[0]]
		if rec.depleted:
			continue
		var r := float(world.resources.node_data(rec).get("radius", 0.0))
		if r > 0.0 and Vector2(pos.x, pos.z).distance_to(Vector2(rec.pos.x, rec.pos.z)) < fp + r:
			return {"ok": false, "reason": "Hay árboles o rocas en medio"}
	match str(bd.get("zone", "any")):
		"rocky":
			var z := gen.zone_at(pos.x, pos.z)
			if z != "rocosa" and z != "cueva":
				return {"ok": false, "reason": "Debe construirse en la zona rocosa"}
		"near_water":
			var found := false
			for a in 12:
				var ang := TAU * a / 12.0
				for d in [4.0, 8.0, 12.0]:
					if gen.is_fresh_water(pos.x + cos(ang) * d, pos.z + sin(ang) * d):
						found = true
			if not found:
				return {"ok": false, "reason": "Debe estar cerca de agua dulce"}
	var player: Node3D = world.player
	if player and player.global_position.distance_to(pos) > 30.0:
		return {"ok": false, "reason": "Demasiado lejos"}
	if player and Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(pos.x, pos.z)) < fp * 0.8:
		return {"ok": false, "reason": "Apártate del lugar de construcción"}
	return {"ok": true, "reason": ""}


func light_sources() -> Array:
	return Economy.light_sources()
