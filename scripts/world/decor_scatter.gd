class_name DecorScatter
extends Node3D
## Vegetación decorativa no interactiva (hierba, flores, rocas pequeñas).
## Se dibuja con MultiMesh por bloque y modelo; la densidad visible depende
## de la calidad gráfica elegida.

const CHUNK := 128.0

var gen: IslandGenerator
var _instances: Array = []   # MultiMeshInstance3D
var _full_counts: Array = []


func setup(generator: IslandGenerator, exclusions: Array) -> void:
	gen = generator
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_value + 202
	var groups := {}
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
				var key := "%s|%d|%d" % [model, floori((x + gen.half) / CHUNK), floori((z + gen.half) / CHUNK)]
				if not groups.has(key):
					groups[key] = {"model": model, "xf": []}
				groups[key].xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h - 0.02, z)))
	for key in groups:
		var g: Dictionary = groups[key]
		var mesh := ModelLibrary.mesh(g.model)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = g.xf.size()
		# Orden aleatorio para que reducir visible_instance_count aclare de forma uniforme.
		var xfs: Array = g.xf
		for k in xfs.size():
			var r := rng.randi_range(k, xfs.size() - 1)
			var tmp: Transform3D = xfs[k]
			xfs[k] = xfs[r]
			xfs[r] = tmp
			mm.set_instance_transform(k, xfs[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.set_meta("xforms", xfs)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 60.0
		mmi.visibility_range_end_margin = 6.0
		add_child(mmi)
		_instances.append(mmi)
		_full_counts.append(xfs.size())


func apply_quality(density: float, view_distance: float) -> void:
	for k in _instances.size():
		var mmi: MultiMeshInstance3D = _instances[k]
		mmi.multimesh.visible_instance_count = int(_full_counts[k] * clampf(density, 0.1, 1.0))
		mmi.visibility_range_end = minf(view_distance * 0.6, 70.0)


func instance_total() -> int:
	var t := 0
	for c in _full_counts:
		t += int(c)
	return t
