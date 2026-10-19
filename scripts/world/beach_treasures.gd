class_name BeachTreasures
extends Node3D
## Tesoros que el mar deja en la orilla: botellas con mensaje y pequeños cofres
## con botín aleatorio (tabla en data/balance.json, sección "treasure").
## Brillan para llamar la atención y se abren con el botón de interactuar.
## Los que no se han abierto se guardan con la partida.

const MODELS := {"botella": "pirate/bottle-large", "cofre": "pirate/chest"}

var world: Node3D
var _items: Array = []   # {kind, pos: Vector3, node: Node3D}
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(w: Node3D) -> void:
	world = w
	_rng.randomize()
	var saved: Variant = GameState.flags.get("tesoros", [])
	if typeof(saved) == TYPE_ARRAY:
		for e in saved:
			if typeof(e) == TYPE_ARRAY and e.size() >= 3:
				_add(str(e[0]), Vector3(float(e[1]), 0.0, float(e[2])))
	# Tiempo desde la última aparición (también cuenta con el juego cerrado, con tope).
	var cfg: Dictionary = GameData.balance.get("treasure", {})
	var interval := float(cfg.get("spawn_interval", 240.0))
	var last := float(GameState.flags.get("tesoro_t", 0.0))
	if last <= 0.0:
		GameState.flags["tesoro_t"] = GameState.now() - interval * 0.75
	else:
		var pending := int(floor((GameState.now() - last) / maxf(interval, 1.0)))
		for i in mini(pending, int(cfg.get("max_active", 3))):
			spawn_one()


func _process(delta: float) -> void:
	_t += delta
	if fmod(_t, 5.0) < delta:
		var cfg: Dictionary = GameData.balance.get("treasure", {})
		var interval := float(cfg.get("spawn_interval", 240.0))
		if GameState.now() - float(GameState.flags.get("tesoro_t", 0.0)) >= interval:
			spawn_one()
	_bob(delta)


func _bob(_delta: float) -> void:
	for e in _items:
		var n: Node3D = e.node
		if is_instance_valid(n):
			var m := n.get_child(0) as Node3D
			if m:
				m.rotation.z = sin(_t * 1.6 + e.pos.x) * (0.12 if e.kind == "botella" else 0.02)


## Hace aparecer un tesoro en una playa (si no se ha llegado al máximo).
func spawn_one() -> bool:
	var cfg: Dictionary = GameData.balance.get("treasure", {})
	GameState.flags["tesoro_t"] = GameState.now()
	if _items.size() >= int(cfg.get("max_active", 3)):
		return false
	var gen = world.get("gen")
	if gen == null:
		return false
	for i in 80:
		var x: float = _rng.randf_range(-gen.half + 8.0, gen.half - 8.0)
		var z: float = _rng.randf_range(-gen.half + 8.0, gen.half - 8.0)
		if gen.zone_at(x, z) != "playa":
			continue
		var h: float = gen.height_at(x, z)
		if h < 0.15 or h > 1.1:
			continue
		var p := Vector3(x, h, z)
		if not world.is_walkable(p) or world.buildings.blocks(p, 1.5):
			continue
		var too_close := false
		for e in _items:
			if (e.pos as Vector3).distance_to(p) < 12.0:
				too_close = true
				break
		if too_close:
			continue
		_add("cofre" if _rng.randf() < 0.3 else "botella", p)
		_save()
		return true
	return false


func _add(kind: String, pos: Vector3) -> void:
	var gen = world.get("gen")
	pos.y = gen.height_at(pos.x, pos.z) if gen else pos.y
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = ModelLibrary.mesh(MODELS.get(kind, MODELS.botella))
	var s := 1.6 if kind == "botella" else 1.3
	mi.scale = Vector3.ONE * s
	mi.rotation = Vector3(0.0, _rng.randf() * TAU, 0.0)
	if kind == "botella":
		# Medio enterrada y tumbada en la arena.
		mi.rotation.x = PI * 0.42
		mi.position.y = 0.12
	root.add_child(mi)
	# Destello que la hace visible a distancia.
	var p := CPUParticles3D.new()
	p.amount = 5
	p.lifetime = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.25, 0.25)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = WorldEffects.glow_texture()
	p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_curve = WorldEffects._curve(1.0, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	g.set_color(1, Color(1.0, 0.8, 0.3, 0.0))
	p.color_ramp = g
	p.position.y = 0.4
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	_items.append({"kind": kind, "pos": pos, "node": root})


func nearest(pos: Vector3, radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in _items.size():
		var d := (_items[i].pos as Vector3).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func label_for(index: int) -> String:
	if index < 0 or index >= _items.size():
		return ""
	return "Abrir botella" if _items[index].kind == "botella" else "Abrir cofre"


func position_of(index: int) -> Vector3:
	return _items[index].pos if index >= 0 and index < _items.size() else Vector3.ZERO


func count() -> int:
	return _items.size()


## Abre un tesoro: da botín aleatorio de la tabla y lo celebra.
func open(index: int) -> Dictionary:
	if index < 0 or index >= _items.size():
		return {}
	var e: Dictionary = _items[index]
	_items.remove_at(index)
	_save()
	var cfg: Dictionary = GameData.balance.get("treasure", {})
	var loot: Array = cfg.get("loot", [])
	var rolls := 2 if e.kind == "botella" else 3
	var got := {}
	for r in rolls:
		var total := 0.0
		for l in loot:
			total += float(l.get("weight", 1.0))
		var pick := _rng.randf() * maxf(total, 0.001)
		for l in loot:
			pick -= float(l.get("weight", 1.0))
			if pick <= 0.0:
				var id := str(l.item)
				got[id] = int(got.get(id, 0)) + _rng.randi_range(int(l.get("min", 1)), int(l.get("max", 1)))
				break
	var parts: Array[String] = []
	for id in got:
		var q := int(got[id])
		var left := GameState.give(id, q)
		if left > 0:
			world.spawn_drop(id, left, e.pos + Vector3.UP * 0.4)
		parts.append("+%d %s" % [q, GameData.item_name(id)])
	var pos: Vector3 = e.pos
	var fx = world.get("effects")
	if fx:
		fx.sparkle(pos + Vector3.UP * 0.5, Color(1.0, 0.9, 0.4), 18)
		fx.ring(pos, Color(1.0, 0.85, 0.4, 0.9), 2.0, 0.6)
	AudioManager.play_at("events/reward", pos, -2.0)
	EventBus.floating_text.emit(pos + Vector3.UP * 1.6, "  ".join(parts), Color(1.0, 0.9, 0.45))
	GameState.add_xp(int(cfg.get("xp", 8)))
	GameState.add_stat("treasures")
	EventBus.treasure_opened.emit(str(e.kind))
	if is_instance_valid(e.node):
		var n: Node3D = e.node
		var tw := n.create_tween()
		tw.tween_property(n, "scale", Vector3.ONE * 1.3, 0.1)
		tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.25)
		tw.tween_callback(n.queue_free)
	return got


func _save() -> void:
	var arr: Array = []
	for e in _items:
		arr.append([e.kind, snappedf(e.pos.x, 0.01), snappedf(e.pos.z, 0.01)])
	GameState.flags["tesoros"] = arr
