class_name DecorScatter
extends Node3D
## Vegetación decorativa no interactiva (hierba, flores, rocas pequeñas).
## Todas las piezas de cada bloque de 64 m se combinan en UNA malla con color
## de vértice (1 llamada de dibujo por bloque). La densidad visible depende de
## la calidad gráfica y se reconstruye al cambiarla.

const CHUNK := 64.0

var gen: IslandGenerator
var _chunks: Dictionary = {}       # Vector2i -> Array de partes {model, xform}
var _instances: Dictionary = {}    # Vector2i -> MeshInstance3D
var _density := -1.0
var _view := 60.0


func setup(generator: IslandGenerator, exclusions: Array) -> void:
	gen = generator
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_value + 202
	var area := gen.cell * gen.cell
	for rule in GameData.world.get("decor", []):
		var models: Array = rule.models
		var sc: Array = rule.get("scale", [1.0, 1.0])
		var by_model: Dictionary = rule.get("scale_by_model", {})
		for j in range(1, gen.n - 1):
			for i in range(1, gen.n - 1):
				var zid: String = IslandGenerator.ZONE_IDS[gen.zones[j * gen.n + i]]
				if not rule.zones.has(zid):
					continue
				if rng.randf() >= float(rule.density) * area:
					continue
				var x := -gen.half + i * gen.cell + rng.randf_range(-1.0, 1.0)
				var z := -gen.half + j * gen.cell + rng.randf_range(-1.0, 1.0)
				var h := gen.height_at(x, z)
				if h < 0.25 or gen.slope_deg(x, z) > 36.0:
					continue
				var skip := false
				for e in exclusions:
					if Vector2(x, z).distance_to(e.pos) < float(e.radius) * 0.6:
						skip = true
						break
				if skip:
					continue
				var model: String = models[rng.randi() % models.size()]
				var s := rng.randf_range(float(sc[0]), float(sc[1]))
				if by_model.has(model):
					s *= float(by_model[model]) / maxf(float(sc[1]), 0.01)
				var key := Vector2i(floori((x + gen.half) / CHUNK), floori((z + gen.half) / CHUNK))
				if not _chunks.has(key):
					_chunks[key] = []
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h - 0.02, z))
				_chunks[key].append({"model": model, "xform": xf})
	# Orden aleatorio dentro de cada bloque: reducir la densidad aclara de forma uniforme.
	for key in _chunks:
		var list: Array = _chunks[key]
		for k in list.size():
			var r := rng.randi_range(k, list.size() - 1)
			var tmp: Variant = list[k]
			list[k] = list[r]
			list[r] = tmp
	apply_quality(1.0, 100.0)


func _rebuild() -> void:
	for key in _instances:
		(_instances[key] as Node).queue_free()
	_instances.clear()
	for key in _chunks:
		var list: Array = _chunks[key]
		var count := int(list.size() * clampf(_density, 0.1, 1.0))
		if count <= 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Decor_%d_%d" % [key.x, key.y]
		mi.mesh = ModelLibrary.baked_merged(list.slice(0, count), "", true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = _view
		mi.visibility_range_end_margin = 8.0
		add_child(mi)
		mi.set_meta("parts", list.slice(0, count))
		_instances[key] = mi


func apply_quality(density: float, view_distance: float) -> void:
	_view = minf(view_distance * 0.7, 80.0)
	if absf(density - _density) > 0.01:
		_density = density
		_rebuild()
	for key in _instances:
		(_instances[key] as MeshInstance3D).visibility_range_end = _view


func instance_total() -> int:
	var t := 0
	for key in _chunks:
		t += (_chunks[key] as Array).size()
	return t


func visible_total() -> int:
	var t := 0
	for key in _instances:
		t += ((_instances[key] as Node).get_meta("parts", []) as Array).size()
	return t
