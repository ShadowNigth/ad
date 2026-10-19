class_name ResourceNodeManager
extends Node3D
## Nodos recolectables (árboles, rocas, arbustos, vetas...). Se dibujan con
## MultiMesh por modelo y bloque del mapa (pocas llamadas de dibujo) y tienen
## colisiones simples (cilindros) solo donde hace falta.

const CHUNK := 128.0
const SHAKE_TIME := 0.28

var gen: IslandGenerator
var nodes: Array = []
var grid := SpatialGrid.new(8.0)
var _mm: Dictionary = {}          # clave -> MultiMeshInstance3D
var _mm_fill: Dictionary = {}     # clave -> instancias usadas
var _fruit_key := ""
var _shaking: Array = []
var _stumps: Dictionary = {}
var _respawn_timer := 0.0
var _blob_mm: Dictionary = {}   # trozo -> MultiMeshInstance3D con sombras suaves
var _blob_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _exclusions: Array = []       # [{pos: Vector2, radius: float}]
var _visibility_range := 105.0


func setup(generator: IslandGenerator, exclusions: Array) -> void:
	gen = generator
	_exclusions = exclusions
	_rng.seed = gen.seed_value + 101
	_scatter()
	_build_multimeshes()
	_restore_depleted()


# ------------------------------------------------------------------ dispersión
func _zone_cells() -> Dictionary:
	var by_zone := {}
	for j in range(1, gen.n - 1):
		for i in range(1, gen.n - 1):
			var zi: int = gen.zones[j * gen.n + i]
			if not by_zone.has(zi):
				by_zone[zi] = PackedInt32Array()
			by_zone[zi].append(j * gen.n + i)
	return by_zone


func _excluded(p: Vector2, extra: float) -> bool:
	for e in _exclusions:
		if p.distance_to(e.pos) < float(e.radius) + extra:
			return true
	return false


func _scatter() -> void:
	var cells := _zone_cells()
	var occupied := SpatialGrid.new(6.0)
	var area := gen.cell * gen.cell
	for rule in GameData.world.get("resources", []):
		var nd: Dictionary = GameData.nodes.get(rule.node, {})
		if nd.is_empty():
			continue
		var spacing := 1.3 + float(nd.get("radius", 0.0)) * (1.7 if str(nd.get("tool", "")) == "pickaxe" else 2.3)
		var big := float(nd.get("radius", 0.0)) > 0.0
		for zname in rule.zones:
			var zi: int = IslandGenerator.ZONE_IDS.find(zname)
			if not cells.has(zi):
				continue
			for idx: int in cells[zi]:
				if _rng.randf() >= float(rule.density) * area:
					continue
				var i := idx % gen.n
				var j := idx / gen.n
				var x := -gen.half + i * gen.cell + _rng.randf_range(-0.9, 0.9)
				var z := -gen.half + j * gen.cell + _rng.randf_range(-0.9, 0.9)
				var h := gen.height_at(x, z)
				var max_slope := 36.0
				if big:
					max_slope = 32.0 if str(nd.get("tool", "")) == "pickaxe" else 27.0
				if h < float(rule.get("min_height", 0.35)) or gen.slope_deg(x, z) > max_slope:
					continue
				if gen.zone_at(x, z) != zname:
					continue
				if _excluded(Vector2(x, z), 1.0 if big else 0.0):
					continue
				var pos := Vector3(x, h, z)
				if not occupied.query(pos, spacing).is_empty():
					continue
				occupied.insert(nodes.size(), pos)
				_add_node(rule.node, nd, pos)
	_scatter_fish(cells, occupied)


func _scatter_fish(cells: Dictionary, occupied: SpatialGrid) -> void:
	var nd: Dictionary = GameData.nodes.get("banco_peces", {})
	if nd.is_empty():
		return
	var placed := 0
	var candidates: Array = []
	for zi in [IslandGenerator.Zone.MAR, IslandGenerator.Zone.LAGO, IslandGenerator.Zone.RIO]:
		if cells.has(zi):
			for idx in cells[zi]:
				var h: float = gen.heights[idx]
				if h > -1.4 and h < -0.45:
					candidates.append(idx)
	var target := 14
	var tries := 0
	while placed < target and tries < 600 and not candidates.is_empty():
		tries += 1
		var idx: int = candidates[_rng.randi() % candidates.size()]
		var x := -gen.half + (idx % gen.n) * gen.cell
		var z := -gen.half + (idx / gen.n) * gen.cell
		if gen.region_at(x, z) != "" or Vector2(x, z).length() > gen.half - 20.0:
			continue
		var pos := Vector3(x, -0.25, z)
		if not occupied.query(pos, 9.0).is_empty():
			continue
		occupied.insert(-1000 - placed, pos)
		_add_node("banco_peces", nd, pos)
		placed += 1


func _add_node(type_id: String, nd: Dictionary, pos: Vector3) -> void:
	var models: Array = nd.get("models", [])
	var sc: Array = nd.get("scale", [1.0, 1.0])
	var rec := {
		"id": nodes.size(), "type": type_id, "pos": pos, "rot": _rng.randf() * TAU,
		"scale": _rng.randf_range(float(sc[0]), float(sc[1])), "model": models[_rng.randi() % models.size()],
		"hits": int(nd.get("hits", 1)), "depleted": false, "respawn_at": 0.0, "mm_key": "", "mm_index": -1,
		"fruit_index": -1, "body": null,
	}
	nodes.append(rec)
	grid.insert(rec.id, pos)


# ------------------------------------------------------------------ visual
func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x + gen.half) / CHUNK), floori((pos.z + gen.half) / CHUNK))


func node_transform(rec: Dictionary) -> Transform3D:
	var s: float = rec.scale
	return Transform3D(Basis(Vector3.UP, rec.rot).scaled(Vector3(s, s, s)), rec.pos)


func _build_multimeshes() -> void:
	var groups := {}
	for rec in nodes:
		var nd: Dictionary = GameData.nodes[rec.type]
		var key := "%s|%s|%s" % [rec.model, str(nd.get("tint", "")), str(_chunk_of(rec.pos))]
		rec.mm_key = key
		if not groups.has(key):
			groups[key] = []
		groups[key].append(rec)
		if nd.has("fruit"):
			var fkey := "%s|fruit|%s" % [nd.fruit, str(_chunk_of(rec.pos))]
			rec["fruit_key"] = fkey
			if not groups.has(fkey):
				groups[fkey] = []
			groups[fkey].append({"fruit_of": rec})
	for key in groups:
		var list: Array = groups[key]
		var first: Dictionary = list[0]
		var mesh: Mesh
		if first.has("fruit_of"):
			mesh = ModelLibrary.baked_mesh(GameData.nodes[first.fruit_of.type].fruit)
		else:
			var nd: Dictionary = GameData.nodes[first.type]
			var tint := Color.WHITE
			if nd.has("tint"):
				tint = Color(nd.tint[0], nd.tint[1], nd.tint[2])
			mesh = ModelLibrary.baked_mesh(first.model, tint)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = _visibility_range
		mmi.visibility_range_end_margin = 8.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_mm[key] = mmi
		for k in list.size():
			var e: Dictionary = list[k]
			if e.has("fruit_of"):
				var owner_rec: Dictionary = e.fruit_of
				owner_rec.fruit_index = k
				var nd2: Dictionary = GameData.nodes[owner_rec.type]
				var fs := float(nd2.get("fruit_scale", 2.5))
				var top: float = ModelLibrary.aabb(owner_rec.model).end.y * float(owner_rec.scale) * 0.82
				mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, owner_rec.rot).scaled(Vector3(fs, fs, fs)), owner_rec.pos + Vector3(0, top, 0)))
			else:
				e.mm_index = k
				mm.set_instance_transform(k, node_transform(e))
				_make_body(e)


func set_visibility_range(dist: float) -> void:
	_visibility_range = dist
	for key in _mm:
		(_mm[key] as MultiMeshInstance3D).visibility_range_end = dist
	for key in _blob_mm:
		(_blob_mm[key] as MultiMeshInstance3D).visibility_range_end = dist * 0.7


func set_blob_shadows(on: bool) -> void:
	if on and _blob_mm.is_empty():
		_build_blobs()
	for key in _blob_mm:
		(_blob_mm[key] as MultiMeshInstance3D).visible = on


## Tamaño de la sombra suave de un nodo (0 = sin sombra).
func _blob_size(rec: Dictionary) -> float:
	var nd: Dictionary = GameData.nodes[rec.type]
	var r := float(nd.get("radius", 0.0))
	var base_scale := maxf(float(nd.get("scale", [1.0, 1.0])[0]), 0.01)
	var k := clampf(float(rec.scale) / base_scale, 0.8, 1.4)
	if nd.get("falls", false):
		return r * 3.4 * k
	if r > 0.0:
		return r * 1.35 * k
	if float(nd.get("height", 0.0)) >= 1.0:
		return 0.75 * k
	return 0.0


func _blob_xf(rec: Dictionary, size: float) -> Transform3D:
	var p: Vector3 = rec.pos
	var b := BlobShadow.ground_basis(gen, p.x, p.z)
	return Transform3D(Basis(b.x * size, b.y, b.z * size), Vector3(p.x, gen.height_at(p.x, p.z) + 0.05, p.z))


## Sombras suaves de árboles, rocas y arbustos: un MultiMesh por trozo.
func _build_blobs() -> void:
	var groups := {}
	for rec in nodes:
		if _blob_size(rec) <= 0.0:
			continue
		var key := str(_chunk_of(rec.pos))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(rec)
	_blob_mat = BlobShadow.shared_material().duplicate()
	_blob_mat.albedo_color.a = 0.3
	for key in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BlobShadow.shared_mesh()
		mm.instance_count = list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Sombras_" + key
		mmi.multimesh = mm
		mmi.material_override = _blob_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = _visibility_range * 0.7
		add_child(mmi)
		_blob_mm[key] = mmi
		for k in list.size():
			var rec: Dictionary = list[k]
			rec["blob_key"] = key
			rec["blob_index"] = k
			_set_blob(rec, not rec.depleted)


func _set_blob(rec: Dictionary, visible_now: bool) -> void:
	if not rec.has("blob_key"):
		return
	var mmi: MultiMeshInstance3D = _blob_mm.get(rec.blob_key)
	if mmi == null:
		return
	var size := _blob_size(rec) if visible_now else 0.0001
	mmi.multimesh.set_instance_transform(int(rec.blob_index), _blob_xf(rec, size))


func _make_body(rec: Dictionary) -> void:
	var nd: Dictionary = GameData.nodes[rec.type]
	var r := float(nd.get("radius", 0.0))
	if r <= 0.0:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 4
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	var s: float = float(rec.scale) / maxf(float(nd.get("scale", [1.0, 1.0])[0]), 0.01)
	shape.radius = r * clampf(s, 0.8, 1.3)
	shape.height = float(nd.get("height", 2.0))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = shape.height * 0.5
	body.add_child(cs)
	body.position = rec.pos
	body.set_meta("node_id", rec.id)
	add_child(body)
	rec.body = body


func _set_visible(rec: Dictionary, visible_now: bool) -> void:
	var mmi: MultiMeshInstance3D = _mm.get(rec.mm_key)
	if mmi:
		if visible_now:
			mmi.multimesh.set_instance_transform(rec.mm_index, node_transform(rec))
		else:
			mmi.multimesh.set_instance_transform(rec.mm_index, Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), rec.pos + Vector3(0, -50, 0)))
	_set_fruit(rec, visible_now)
	_set_blob(rec, visible_now)
	if rec.body:
		(rec.body as StaticBody3D).process_mode = Node.PROCESS_MODE_INHERIT if visible_now else Node.PROCESS_MODE_DISABLED
		(rec.body as StaticBody3D).collision_layer = (1 << 4) if visible_now else 0


func _set_fruit(rec: Dictionary, visible_now: bool) -> void:
	if int(rec.fruit_index) < 0 or not rec.has("fruit_key"):
		return
	var mmi: MultiMeshInstance3D = _mm.get(rec.fruit_key)
	if mmi == null:
		return
	var nd: Dictionary = GameData.nodes[rec.type]
	var fs := float(nd.get("fruit_scale", 2.5)) * (1.0 if visible_now else 0.0001)
	var top: float = ModelLibrary.aabb(rec.model).end.y * float(rec.scale) * 0.82
	mmi.multimesh.set_instance_transform(rec.fruit_index, Transform3D(Basis(Vector3.UP, rec.rot).scaled(Vector3(fs, fs, fs)), rec.pos + Vector3(0, top, 0)))


# ------------------------------------------------------------------ consultas
func node_data(rec: Dictionary) -> Dictionary:
	return GameData.nodes.get(rec.type, {})


func get_node_rec(id: int) -> Dictionary:
	if id < 0 or id >= nodes.size():
		return {}
	return nodes[id]


func is_available(id: int) -> bool:
	var rec := get_node_rec(id)
	return not rec.is_empty() and not rec.depleted and GameState.is_region_unlocked(gen.region_at(rec.pos.x, rec.pos.z))


## Nodo disponible más cercano a `pos` (distancia horizontal) dentro del radio.
func nearest_available(pos: Vector3, radius: float) -> int:
	var best := -1
	var best_d := INF
	for e in grid.query(pos, radius + 1.5):
		var rec: Dictionary = nodes[e[0]]
		if rec.depleted:
			continue
		var nd := node_data(rec)
		var d := Vector2(pos.x, pos.z).distance_to(Vector2(rec.pos.x, rec.pos.z)) - float(nd.get("radius", 0.0))
		if absf(pos.y - rec.pos.y) > 3.5:
			continue
		if d <= radius and d < best_d:
			best_d = d
			best = rec.id
	return best


## ¿Hay nodos (con colisión o no) que estorben en esta posición?
func blocking_near(pos: Vector3, radius: float) -> bool:
	for e in grid.query(pos, radius + 1.5):
		var rec: Dictionary = nodes[e[0]]
		if rec.depleted:
			continue
		var r := float(node_data(rec).get("radius", 0.3))
		if Vector2(pos.x, pos.z).distance_to(Vector2(rec.pos.x, rec.pos.z)) < radius + maxf(r, 0.3):
			return true
	return false


# ------------------------------------------------------------------ recolección
## Golpea un nodo. `tool_power` = recursos por acción, `tool_tier` = nivel.
## Devuelve {"ok", "reason", "items": {}, "depleted"}.
func hit(id: int, tool_type: String, tool_power: int, tool_tier: int, hitter_pos: Vector3) -> Dictionary:
	var rec := get_node_rec(id)
	if rec.is_empty() or rec.depleted:
		return {"ok": false, "reason": "", "items": {}, "depleted": false}
	var nd := node_data(rec)
	var req_tool: Variant = nd.get("tool")
	var min_tier := int(nd.get("min_tier", 0))
	var power := 1
	if req_tool != null:
		if tool_type == req_tool:
			power = maxi(tool_power, 1)
			if tool_tier < min_tier:
				return {"ok": false, "reason": _tier_reason(str(req_tool), min_tier), "items": {}, "depleted": false}
		elif min_tier > 0:
			return {"ok": false, "reason": _tier_reason(str(req_tool), min_tier), "items": {}, "depleted": false}
	var items := {}
	var mult := 1.0 + TechTree.mod("gather_mult")
	for item_id in nd.get("yield", {}):
		var base := float(nd.yield[item_id]) * power * mult
		var q := int(floor(base))
		if _rng.randf() < base - q:
			q += 1
		items[item_id] = int(items.get(item_id, 0)) + maxi(q, 1)
	for bonus in nd.get("bonus", []):
		if _rng.randf() < float(bonus.chance):
			items[bonus.item] = int(items.get(bonus.item, 0)) + int(bonus.qty)
	rec.hits = int(rec.hits) - 1
	var depleted := int(rec.hits) <= 0
	if depleted:
		for item_id in nd.get("final", {}):
			items[item_id] = int(items.get(item_id, 0)) + int(nd.final[item_id])
		_deplete(rec, hitter_pos)
	else:
		_start_shake(rec)
	return {"ok": true, "reason": "", "items": items, "depleted": depleted}


func _tier_reason(tool_type: String, tier: int) -> String:
	var names := {"axe": "un hacha", "pickaxe": "un pico", "spear": "una lanza"}
	var tier_names := ["", "de piedra", "de hierro", "avanzado"]
	var t: String = names.get(tool_type, "otra herramienta")
	if tier >= 1 and tier < tier_names.size():
		t += " " + tier_names[tier]
	return "Necesitas %s o mejor" % t


func _deplete(rec: Dictionary, hitter_pos: Vector3) -> void:
	var nd := node_data(rec)
	rec.depleted = true
	rec.respawn_at = GameState.now() + float(nd.get("respawn", 300.0))
	GameState.depleted_nodes[str(rec.id)] = rec.respawn_at
	if nd.get("keep_when_empty", false):
		_set_fruit(rec, false)
		return
	_set_visible(rec, false)
	if nd.get("falls", false):
		_spawn_falling(rec, hitter_pos)
	if nd.has("stump"):
		var st := MeshInstance3D.new()
		st.mesh = ModelLibrary.baked_mesh(nd.stump)
		var width := maxf(ModelLibrary.aabb(nd.stump).size.x, 0.05)
		var ss := float(nd.get("radius", 0.4)) * 2.6 / width
		st.transform = Transform3D(Basis(Vector3.UP, rec.rot).scaled(Vector3(ss, ss, ss)), rec.pos)
		add_child(st)
		_stumps[rec.id] = st


func _spawn_falling(rec: Dictionary, hitter_pos: Vector3) -> void:
	var nd := node_data(rec)
	var mi := MeshInstance3D.new()
	var tint := Color.WHITE
	if nd.has("tint"):
		tint = Color(nd.tint[0], nd.tint[1], nd.tint[2])
	mi.mesh = ModelLibrary.tinted_mesh(rec.model, tint)
	add_child(mi)
	mi.transform = node_transform(rec)
	var away: Vector3 = rec.pos - hitter_pos
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	var axis := Vector3.UP.cross(away).normalized()
	var start := mi.transform
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var ang := t * t * deg_to_rad(88.0)
		mi.transform = Transform3D(Basis(axis, ang) * start.basis, start.origin), 0.0, 1.0, 1.1)
	tw.tween_interval(0.5)
	tw.tween_property(mi, "position:y", start.origin.y - 2.5, 0.8)
	tw.tween_callback(mi.queue_free)


func _start_shake(rec: Dictionary) -> void:
	for s in _shaking:
		if s.rec == rec:
			s.t = 0.0
			return
	_shaking.append({"rec": rec, "t": 0.0})


func _process(delta: float) -> void:
	for i in range(_shaking.size() - 1, -1, -1):
		var s: Dictionary = _shaking[i]
		s.t = float(s.t) + delta
		var rec: Dictionary = s.rec
		if rec.depleted:
			_shaking.remove_at(i)
			continue
		var mmi: MultiMeshInstance3D = _mm.get(rec.mm_key)
		if mmi == null:
			_shaking.remove_at(i)
			continue
		if float(s.t) >= SHAKE_TIME:
			mmi.multimesh.set_instance_transform(rec.mm_index, node_transform(rec))
			_shaking.remove_at(i)
		else:
			var k := 1.0 - float(s.t) / SHAKE_TIME
			var wob := sin(float(s.t) * 48.0) * 0.06 * k
			var xf := node_transform(rec)
			xf.basis = Basis(Vector3(1, 0, 0.3).normalized(), wob) * xf.basis
			mmi.multimesh.set_instance_transform(rec.mm_index, xf)
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = 2.0
		_check_respawns()


func _check_respawns() -> void:
	var now := GameState.now()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for key in GameState.depleted_nodes.keys():
		var id := int(key)
		var rec := get_node_rec(id)
		if rec.is_empty():
			GameState.depleted_nodes.erase(key)
			continue
		if now < float(GameState.depleted_nodes[key]):
			continue
		if player and player.global_position.distance_to(rec.pos) < 2.5:
			continue
		if get_parent().has_method("building_blocks") and get_parent().building_blocks(rec.pos, 0.6):
			continue
		_respawn(rec)


func _respawn(rec: Dictionary) -> void:
	rec.depleted = false
	rec.hits = int(node_data(rec).get("hits", 1))
	GameState.depleted_nodes.erase(str(rec.id))
	if _stumps.has(rec.id):
		(_stumps[rec.id] as Node).queue_free()
		_stumps.erase(rec.id)
	_set_visible(rec, true)


func _restore_depleted() -> void:
	var now := GameState.now()
	for key in GameState.depleted_nodes.keys():
		var rec := get_node_rec(int(key))
		if rec.is_empty():
			GameState.depleted_nodes.erase(key)
			continue
		var t := float(GameState.depleted_nodes[key])
		if now >= t:
			GameState.depleted_nodes.erase(key)
			continue
		var nd := node_data(rec)
		rec.depleted = true
		rec.respawn_at = t
		if nd.get("keep_when_empty", false):
			_set_fruit(rec, false)
		else:
			_set_visible(rec, false)


## Elimina definitivamente los nodos bajo un edificio recién colocado.
func clear_area(pos: Vector3, radius: float) -> void:
	for e in grid.query(pos, radius + 1.0):
		var rec: Dictionary = nodes[e[0]]
		if rec.depleted:
			continue
		if Vector2(pos.x, pos.z).distance_to(Vector2(rec.pos.x, rec.pos.z)) < radius + 0.4:
			rec.depleted = true
			rec.respawn_at = GameState.now() + float(node_data(rec).get("respawn", 300.0))
			GameState.depleted_nodes[str(rec.id)] = rec.respawn_at
			_set_visible(rec, false)
