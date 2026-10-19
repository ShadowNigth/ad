class_name PoiManager
extends Node3D
## Puntos de interés colocados a mano: naufragio, cofres, campamento, laguna,
## puente roto (región de la jungla), ruinas, cementerio, derrumbe de la cueva,
## cueva de cristal y mirador. Gestiona sus interacciones y desbloqueos.

var world: World
var gen: IslandGenerator
var pois: Array = []
var interactables: Array = []
var bridge_rect: Dictionary = {}     # zona transitable sobre el agua cuando el puente está reparado
var _bridge_nodes: Array = []
var _gate_blockers: Array = []
var map_markers: Array = []


func compute_exclusions(generator: IslandGenerator) -> Array:
	var out: Array = []
	for poi in GameData.world.get("pois", []):
		var r := float(poi.get("radius", 7.0))
		if poi.type == "label":
			continue
		if poi.type == "shipwreck":
			r = 9.0
		elif poi.type == "bridge":
			r = 8.0
		elif poi.type == "cave_gate":
			r = 6.0
		elif poi.type == "cave":
			r = 4.0
		elif poi.type == "lake":
			r = 2.0
		out.append({"pos": Vector2(poi.pos[0], poi.pos[1]), "radius": r})
	var sp: Array = GameData.world.get("spawn", [0, 0])
	out.append({"pos": Vector2(sp[0], sp[1]), "radius": 4.0})
	return out


func setup(w: World) -> void:
	world = w
	gen = w.gen
	for poi in GameData.world.get("pois", []):
		var p: Dictionary = poi.duplicate(true)
		p["world_pos"] = _ground(float(poi.pos[0]), float(poi.pos[1]))
		pois.append(p)
		match str(poi.type):
			"shipwreck":
				_build_shipwreck(p)
			"chest":
				_build_chest(p)
			"camp":
				_build_camp(p)
			"lake":
				_build_lake(p)
			"bridge":
				_build_bridge(p)
			"ruins":
				_build_ruins(p)
			"graveyard":
				_build_graveyard(p)
			"cave_gate":
				_build_cave_gate(p)
			"cave":
				_build_cave(p)
			"lookout":
				_build_lookout(p)
		map_markers.append({"id": p.id, "name": p.name, "pos": p.world_pos, "type": p.type})
	EventBus.region_unlocked.connect(_on_region_unlocked)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, gen.height_at(x, z), z)


func _prop(model: String, pos: Vector3, rot_deg: float = 0.0, scale: float = 1.0, collide: bool = false, tint: Color = Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ModelLibrary.tinted_mesh(model, tint)
	mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(rot_deg)).scaled(Vector3.ONE * scale), pos)
	add_child(mi)
	if collide and mi.mesh:
		var aabb := mi.mesh.get_aabb()
		var body := StaticBody3D.new()
		body.collision_layer = 1 << 5
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(aabb.size.x * scale * 0.85, 0.3), maxf(aabb.size.y * scale, 0.3), maxf(aabb.size.z * scale * 0.85, 0.3))
		cs.shape = box
		cs.position = (aabb.get_center()) * scale
		body.add_child(cs)
		mi.add_child(body)
		body.scale = Vector3.ONE / scale
	return mi


# ------------------------------------------------------------------ construcción
## Busca cerca de `c` un punto con la profundidad de agua indicada.
func _find_depth(c: Vector2, min_depth: float, max_depth: float, radius: float) -> Vector2:
	for r in range(0, int(radius), 2):
		for k in 16:
			var a := TAU * k / 16.0
			var q := c + Vector2(cos(a), sin(a)) * r
			var d := -gen.height_at(q.x, q.y)
			if d >= min_depth and d <= max_depth:
				return q
	return c


func _build_shipwreck(p: Dictionary) -> void:
	var base := _find_depth(Vector2(p.pos[0], p.pos[1]), 1.0, 2.4, 24.0)
	p.world_pos = Vector3(base.x, gen.height_at(base.x, base.y), base.y)
	var pos: Vector3 = p.world_pos
	pos.y = minf(pos.y, 0.0) - 0.9
	_prop("pirate/ship-wreck", pos, float(p.get("rot", 0.0)), 1.0, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var props := ["pirate/barrel", "pirate/crate", "pirate/crate-bottles", "pirate/barrel"]
	for k in props.size():
		var a := -1.2 + k * 0.7
		var off := Vector2(cos(a), sin(a)) * rng.randf_range(9.0, 13.0)
		var q := base - Vector2(off.x, absf(off.y) + 4.0)
		var g := _ground(q.x, q.y)
		if g.y > 0.05:
			_prop(props[k], g, rng.randf() * 360.0, 0.55, true)
	var boat := _ground(base.x - 14.0, base.y - 4.0)
	if boat.y > -0.3:
		_prop("pirate/boat-row-small", boat + Vector3(0, 0.05, 0), 120.0, 0.9, true)


func _build_chest(p: Dictionary) -> void:
	var opened := bool(GameState.flags.get("poi_" + p.id, false))
	var mi := _prop("pirate/chest", p.world_pos, float(p.get("rot", 0.0)), 0.6, true)
	mi.name = "Cofre_" + p.id
	if not opened:
		interactables.append({"id": p.id, "type": "chest", "pos": p.world_pos, "label": "Abrir " + str(p.name).to_lower()})
	else:
		mi.scale = Vector3.ONE * 0.6
		mi.rotation_degrees.x = 0.0


func _build_camp(p: Dictionary) -> void:
	var pos: Vector3 = p.world_pos
	_prop("survival/signpost", pos + Vector3(-5.0, 0, 6.0), 20.0, 4.0, true)
	var ring := 7
	for k in ring:
		var a := TAU * k / ring
		var q := Vector2(p.pos[0], p.pos[1]) + Vector2(cos(a), sin(a)) * (float(p.get("radius", 15.0)) + 1.5)
		var g := _ground(q.x, q.y)
		_prop("nature/rock_smallFlatA", g, rad_to_deg(a), 3.0)


func _build_lake(p: Dictionary) -> void:
	var c := Vector2(p.pos[0], p.pos[1])
	var lk: Dictionary = GameData.world.get("lake", {})
	var r := float(lk.get("radius", 12.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for k in 9:
		var a := rng.randf() * TAU
		var d := rng.randf_range(r * 0.35, r * 0.85)
		var q := c + Vector2(cos(a), sin(a)) * d
		_prop("nature/lily_large" if k % 2 == 0 else "nature/lily_small", Vector3(q.x, 0.03, q.y), rng.randf() * 360.0, 3.0)
	var shore := c + Vector2(r + 4.0, 3.0)
	_prop("nature/canoe", _ground(shore.x, shore.y) + Vector3(0, 0.05, 0), 70.0, 3.0, true)
	_prop("nature/log_large", _ground(shore.x + 2.0, shore.y + 4.0), 20.0, 3.0, true)


func _river_dir_at(p: Vector2) -> Vector2:
	var best := INF
	var dir := Vector2(0, 1)
	for k in gen.river_pts.size() - 1:
		var a: Vector2 = gen.river_pts[k]
		var b: Vector2 = gen.river_pts[k + 1]
		var d := IslandGenerator._seg_dist(p, a, b)
		if d < best:
			best = d
			dir = (b - a).normalized()
	return dir


func _build_bridge(p: Dictionary) -> void:
	var c := Vector2(p.pos[0], p.pos[1])
	var rdir := _river_dir_at(c)
	var across := Vector2(-rdir.y, rdir.x)
	var length := float(p.get("length", 12.0))
	var yaw := atan2(across.x, across.y)
	p["across"] = across
	p["yaw"] = yaw
	# Pilares rotos a cada orilla.
	for side in [-1.0, 1.0]:
		var q: Vector2 = c + across * side * (length * 0.5 - 0.6)
		var g := _ground(q.x, q.y)
		for off in [-1.1, 1.1]:
			var post: Vector2 = q + rdir * off
			_prop("town/pillar-wood", Vector3(post.x, g.y - 0.3, post.y), 0.0, 1.6, true)
	var unlocked := GameState.is_region_unlocked(str(p.get("region", "")))
	if unlocked:
		_make_bridge_deck(p)
	else:
		# Restos del puente caído en el agua.
		_prop("nature/bridge_wood", Vector3(c.x, -0.45, c.y), rad_to_deg(yaw) + 25.0, 3.0)
		var g := _ground(c.x + across.x * (length * 0.5 + 2.5), c.y + across.y * (length * 0.5 + 2.5))
		_prop("survival/signpost-single", g, rad_to_deg(yaw), 4.0, true)
		interactables.append({"id": p.id, "type": "bridge", "pos": _ground(c.x + across.x * (length * 0.5 + 1.5), c.y + across.y * (length * 0.5 + 1.5)),
							  "label": "Reparar el puente"})
	bridge_rect = {"center": c, "across": across, "along": rdir, "half_len": length * 0.5 + 1.0, "half_w": 1.7, "active": unlocked}


func _make_bridge_deck(p: Dictionary) -> void:
	var c := Vector2(p.pos[0], p.pos[1])
	var across: Vector2 = p.across
	var length := float(p.get("length", 12.0))
	var deck_y := 0.55
	var segments := 4
	for k in segments:
		var t := (k + 0.5) / segments - 0.5
		var q := c + across * t * length
		var mi := _prop("nature/bridge_wood", Vector3(q.x, deck_y - 0.6, q.y), rad_to_deg(float(p.yaw)) + 90.0, 3.0)
		_bridge_nodes.append(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 0.3, length + 3.0)
	cs.shape = box
	body.add_child(cs)
	body.transform = Transform3D(Basis(Vector3.UP, float(p.yaw)), Vector3(c.x, deck_y - 0.15, c.y))
	add_child(body)
	_bridge_nodes.append(body)


func _build_ruins(p: Dictionary) -> void:
	var c := Vector2(p.pos[0], p.pos[1])
	var models := ["nature/statue_column", "nature/statue_columnDamaged", "nature/statue_obelisk", "nature/statue_column", "nature/statue_head", "nature/statue_columnDamaged", "nature/statue_block", "nature/statue_column"]
	for k in models.size():
		var a := TAU * k / models.size()
		var q := c + Vector2(cos(a), sin(a)) * 8.0
		_prop(models[k], _ground(q.x, q.y), rad_to_deg(-a), 3.4, true)
	_prop("graveyard/altar-stone", _ground(c.x, c.y), 0.0, 2.6, true)
	_prop("nature/statue_ring", _ground(c.x, c.y - 4.0), 0.0, 3.0, true)
	_prop("graveyard/fire-basket", _ground(c.x + 3.0, c.y + 3.0), 0.0, 2.6, true)
	_prop("graveyard/fire-basket", _ground(c.x - 3.0, c.y + 3.0), 0.0, 2.6, true)


func _build_graveyard(p: Dictionary) -> void:
	var c := Vector2(p.pos[0], p.pos[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var stones := ["graveyard/gravestone-round", "graveyard/gravestone-cross", "graveyard/gravestone-broken", "graveyard/cross-wood"]
	for row in 3:
		for col in 4:
			var q := c + Vector2(-4.5 + col * 3.0 + rng.randf_range(-0.4, 0.4), -3.0 + row * 3.0)
			_prop(stones[rng.randi() % stones.size()], _ground(q.x, q.y), rng.randf_range(-15, 15), 2.4, true)
	_prop("graveyard/crypt-small", _ground(c.x, c.y - 7.5), 0.0, 2.4, true)
	_prop("graveyard/crypt-small-roof", _ground(c.x, c.y - 7.5), 0.0, 2.4)
	_prop("graveyard/pine-crooked", _ground(c.x + 7.0, c.y - 5.0), 30.0, 2.6, true)
	_prop("graveyard/pine-crooked", _ground(c.x - 8.0, c.y + 3.0), 200.0, 2.6, true)
	for k in 6:
		var q := c + Vector2(-7.5 + k * 3.0, 6.0)
		_prop("graveyard/iron-fence" if k != 3 else "graveyard/iron-fence-damaged", _ground(q.x, q.y), 0.0, 2.4)
	_prop("graveyard/pumpkin-carved", _ground(c.x + 2.0, c.y + 4.0), 40.0, 2.0)
	_prop("graveyard/lantern-candle", _ground(c.x - 2.0, c.y + 4.0), 0.0, 2.4)


func _build_cave_gate(p: Dictionary) -> void:
	var pos: Vector3 = p.world_pos
	var rot := float(p.get("rot", 0.0))
	_prop("cave/gate-rock", pos + Vector3(0, -0.2, 0), rot, 1.3)
	var unlocked := GameState.is_region_unlocked(str(p.get("region", "")))
	if not unlocked:
		var blocker := _prop("pirate/rocks-b", pos + Vector3(0, -0.4, 0), rot + 20.0, 1.05, true)
		_gate_blockers.append(blocker)
		var blocker2 := _prop("pirate/rocks-a", pos + Vector3(0, -0.6, 0), rot - 30.0, 0.8, true)
		_gate_blockers.append(blocker2)
		var dir := Vector3(sin(deg_to_rad(rot)), 0, cos(deg_to_rad(rot)))
		interactables.append({"id": p.id, "type": "cave_gate", "pos": pos - dir * 3.0, "label": "Volar el derrumbe"})


func _build_cave(p: Dictionary) -> void:
	var c := Vector2(p.pos[0], p.pos[1])
	_prop("crystals/tower-round-crystals", _ground(c.x, c.y), 0.0, 3.0, true)
	for k in 5:
		var a := TAU * k / 5.0 + 0.3
		var q := c + Vector2(cos(a), sin(a)) * 6.5
		var light := OmniLight3D.new()
		light.light_color = Color(0.45, 0.85, 1.0)
		light.light_energy = 1.4
		light.omni_range = 7.0
		light.position = _ground(q.x, q.y) + Vector3(0, 1.5, 0)
		light.shadow_enabled = false
		add_child(light)


func _build_lookout(p: Dictionary) -> void:
	var pos: Vector3 = p.world_pos
	_prop("pirate/tower-watch", pos, 15.0, 1.2, true)
	var opened := bool(GameState.flags.get("poi_" + p.id, false))
	var chest_pos := pos + Vector3(3.0, 0, 2.0)
	chest_pos.y = gen.height_at(chest_pos.x, chest_pos.z)
	_prop("pirate/chest", chest_pos, -30.0, 0.6, true)
	if not opened:
		interactables.append({"id": p.id, "type": "chest", "pos": chest_pos, "label": "Abrir cofre del mirador"})


# ------------------------------------------------------------------ interacción
func nearest_interactable(pos: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	for it in interactables:
		var d := pos.distance_to(it.pos)
		if d < best_d:
			best_d = d
			best = it
	if best.is_empty():
		return {}
	return {"id": best.id, "type": best.type, "world_pos": best.pos, "label": best.label}


func poi_by_id(id: String) -> Dictionary:
	for p in pois:
		if p.id == id:
			return p
	return {}


func label_for(info: Dictionary) -> String:
	var p := poi_by_id(info.id)
	match str(info.type):
		"bridge", "cave_gate":
			var tech := str(p.get("tech", ""))
			if not TechTree.is_unlocked(tech):
				return "%s (requiere %s)" % [info.label, GameData.tech(tech).get("name", tech)]
	return info.label


func interact(id: String) -> void:
	var p := poi_by_id(id)
	var it: Dictionary = {}
	for x in interactables:
		if x.id == id:
			it = x
	if p.is_empty() or it.is_empty():
		return
	match str(it.type):
		"chest":
			_open_chest(p, it)
		"bridge", "cave_gate":
			_try_unlock(p, it)


func _open_chest(p: Dictionary, it: Dictionary) -> void:
	GameState.flags["poi_" + p.id] = true
	interactables.erase(it)
	AudioManager.play_at("ui/latch", it.pos)
	AudioManager.play("events/reward")
	var parts: Array[String] = []
	for item_id in p.get("loot", {}):
		var q := int(p.loot[item_id])
		var left := GameState.give(item_id, q)
		if left > 0:
			world.spawn_drop(item_id, left, it.pos + Vector3(0, 0.5, 1.0))
		parts.append("%d %s" % [q, GameData.item_name(item_id)])
	EventBus.notify("Has encontrado: " + ", ".join(parts), "good")
	EventBus.floating_text.emit(it.pos + Vector3.UP * 1.5, "¡Botín!", Color(1, 0.9, 0.4))


func _try_unlock(p: Dictionary, it: Dictionary) -> void:
	var tech := str(p.get("tech", ""))
	if not TechTree.is_unlocked(tech):
		EventBus.notify("Necesitas investigar «%s» en el árbol tecnológico." % GameData.tech(tech).get("name", tech), "warn")
		AudioManager.play_ui("ui/error")
		return
	var cost: Dictionary = p.get("cost", {})
	if not Economy.can_afford(cost):
		var miss := Economy.missing_for(cost)
		var parts: Array[String] = []
		for id in miss:
			parts.append("%d %s" % [int(miss[id]), GameData.item_name(id)])
		EventBus.notify("Faltan materiales: " + ", ".join(parts), "warn")
		AudioManager.play_ui("ui/error")
		return
	Economy.pay(cost)
	interactables.erase(it)
	GameState.unlock_region(str(p.get("region", "")))


func _on_region_unlocked(region_id: String) -> void:
	for p in pois:
		if str(p.get("region", "")) != region_id:
			continue
		if p.type == "bridge":
			_make_bridge_deck(p)
			bridge_rect.active = true
			AudioManager.play_at("build/hammer", p.world_pos)
			AudioManager.play("events/stinger_victory", -6.0)
			EventBus.notify("¡Puente reparado! La jungla de las ruinas está abierta.", "good")
		elif p.type == "cave_gate":
			for b in _gate_blockers:
				if is_instance_valid(b):
					world.spawn_explosion(b.global_position + Vector3.UP)
					b.queue_free()
			_gate_blockers.clear()
			AudioManager.play("events/stinger_victory", -6.0)
			EventBus.notify("¡El derrumbe ha volado por los aires! La Cueva de cristal está abierta.", "good")


## ¿Está el punto sobre el puente reparado?
func on_bridge(pos: Vector3) -> bool:
	if bridge_rect.is_empty() or not bridge_rect.active:
		return false
	var rel := Vector2(pos.x, pos.z) - (bridge_rect.center as Vector2)
	return absf(rel.dot(bridge_rect.across)) <= float(bridge_rect.half_len) and absf(rel.dot(bridge_rect.along)) <= float(bridge_rect.half_w)


func guardian_spawns() -> Array:
	var out: Array = []
	for p in pois:
		if p.has("guardian"):
			out.append({"poi": p.id, "enemy": p.guardian, "pos": p.world_pos})
	return out
