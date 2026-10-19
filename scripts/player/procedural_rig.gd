class_name ProceduralRig
extends Node3D
## Animación procedural para modelos OBJ estáticos (sin esqueleto).
## Separa la malla en piezas (piernas, brazos, torso, cabeza) usando sus
## superficies o la posición de los triángulos, las cuelga de nodos pivote y
## las anima con transformaciones: caminar, atacar, recibir daño, morir.

enum Rig { BIPED, QUAD, CRAB, GHOST }

static var _cache: Dictionary = {}

var rig: int = Rig.BIPED
var model_id := ""
var height := 1.0
var walk := 0.0            # 0..1 intensidad de la animación de andar
var walk_rate := 1.6       # ciclos por segundo a velocidad máxima
var arm_down := 1.2        # radianes para bajar los brazos en T
var phase := 0.0
var attack_time := -1.0
var attack_duration := 0.42
var dead := false
var _death_t := 0.0
var _flash_t := 0.0
var _time := 0.0
var _root: Node3D
var _pivots: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var hand_socket: Node3D
var _base_scale := 1.0


func build(model: String, rig_name: String, scale_factor: float, tint: Color = Color.WHITE) -> void:
	model_id = model
	rig = {"biped": Rig.BIPED, "quad": Rig.QUAD, "crab": Rig.CRAB, "ghost": Rig.GHOST}.get(rig_name, Rig.BIPED)
	_base_scale = scale_factor
	for c in get_children():
		c.queue_free()
	_pivots.clear()
	_meshes.clear()
	_root = Node3D.new()
	_root.name = "Modelo"
	_root.rotation.y = PI  # los modelos de Kenney miran a +Z; en Godot el frente es -Z
	_root.scale = Vector3.ONE * scale_factor
	add_child(_root)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 0.35, 0.3, 0.0)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var parts := _get_parts(model, rig, tint)
	height = float(parts.get("height", 1.0))
	for p in parts.list:
		var pivot := Node3D.new()
		pivot.name = p.name
		pivot.position = p.pivot
		_root.add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.material_overlay = _flash_mat
		pivot.add_child(mi)
		_pivots[p.name] = pivot
		_meshes.append(mi)
	if _pivots.has("arm_r"):
		hand_socket = Node3D.new()
		hand_socket.name = "Mano"
		var arm_r: Dictionary = parts.list.filter(func(x): return x.name == "arm_r")[0]
		hand_socket.position = arm_r.get("hand", Vector3(-0.12, -0.02, 0.0))
		_pivots.arm_r.add_child(hand_socket)


static func _get_parts(model: String, rig_type: int, tint: Color) -> Dictionary:
	var key := "%s|%d|%s" % [model, rig_type, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var mesh := ModelLibrary.tinted_mesh(model, tint)
	var result := {"list": [], "height": 1.0}
	if mesh == null:
		_cache[key] = result
		return result
	var aabb := mesh.get_aabb()
	result.height = aabb.end.y
	# Triángulos de todas las superficies con su material.
	var buckets: Dictionary = {}
	var surf_count := mesh.get_surface_count()
	var surf_info: Array = []
	for s in surf_count:
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var box := AABB(verts[0], Vector3.ZERO)
		for v in verts:
			box = box.expand(v)
		surf_info.append({"arr": arr, "box": box, "count": verts.size(), "mat": mesh.surface_get_material(s)})
	var hip := aabb.end.y * 0.26
	var shoulder_x := aabb.size.x * 0.31
	for s in surf_count:
		var info: Dictionary = surf_info[s]
		var arr: Array = info.arr
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for k in verts.size():
				idx.append(k)
		var box: AABB = info.box
		var center := box.get_center()
		var whole_part := ""
		# Superficies que ya son una pieza completa (packs con grupos por extremidad).
		if surf_count > 2:
			if rig_type in [Rig.QUAD, Rig.CRAB] and info.count < 60 and center.y < aabb.end.y * 0.35:
				whole_part = ("leg_f" if center.z > 0.0 else "leg_b") + ("l" if center.x > 0.0 else "r")
			elif rig_type in [Rig.BIPED, Rig.GHOST] and center.y < hip * 1.25 and absf(center.x) < aabb.size.x * 0.3:
				whole_part = "leg_l" if center.x > 0.0 else "leg_r"
			elif rig_type in [Rig.BIPED, Rig.GHOST] and absf(center.x) > aabb.size.x * 0.22 and box.size.x > box.size.z:
				whole_part = "arm_l" if center.x > 0.0 else "arm_r"
		for t in range(0, idx.size() - 2, 3):
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			var part := whole_part
			if part == "":
				var cen := (verts[a] + verts[b] + verts[c]) / 3.0
				part = "body"
				if rig_type == Rig.BIPED and surf_count <= 2 and info.box.end.y < aabb.end.y * 0.62:
					if cen.y < hip * 0.95 and absf(cen.x) < shoulder_x * 0.66:
						part = "leg_l" if cen.x > 0.0 else "leg_r"
					elif absf(cen.x) > shoulder_x:
						part = "arm_l" if cen.x > 0.0 else "arm_r"
			if not buckets.has(part):
				buckets[part] = {"st": SurfaceTool.new(), "mat": info.mat, "box": AABB(verts[a], Vector3.ZERO), "begun": false}
			var bk: Dictionary = buckets[part]
			var st: SurfaceTool = bk.st
			if not bk.begun:
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				bk.begun = true
			for vi in [a, b, c]:
				if not norms.is_empty():
					st.set_normal(norms[vi])
				if not uvs.is_empty():
					st.set_uv(uvs[vi])
				st.add_vertex(verts[vi])
				bk.box = (bk.box as AABB).expand(verts[vi])
	for part in buckets:
		var bk: Dictionary = buckets[part]
		var box: AABB = bk.box
		var pivot := Vector3.ZERO
		var hand := Vector3.ZERO
		match part:
			"leg_l", "leg_r", "leg_fl", "leg_fr", "leg_bl", "leg_br":
				pivot = Vector3(box.get_center().x, box.end.y, box.get_center().z)
			"arm_l":
				pivot = Vector3(box.position.x, box.get_center().y + box.size.y * 0.3, box.get_center().z)
				hand = Vector3(box.size.x * 0.85, -box.size.y * 0.3, 0.0)
			"arm_r":
				pivot = Vector3(box.end.x, box.get_center().y + box.size.y * 0.3, box.get_center().z)
				hand = Vector3(-box.size.x * 0.85, -box.size.y * 0.3, 0.0)
		var st: SurfaceTool = bk.st
		st.set_material(bk.mat)
		var m := st.commit()
		# Desplaza los vértices para que el origen de la pieza sea su articulación.
		var moved := ArrayMesh.new()
		for s in m.get_surface_count():
			var a2 := m.surface_get_arrays(s)
			var vv: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
			for k in vv.size():
				vv[k] -= pivot
			a2[Mesh.ARRAY_VERTEX] = vv
			moved.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
			moved.surface_set_material(s, bk.mat)
		result.list.append({"name": part, "mesh": moved, "pivot": pivot, "hand": hand})
	_cache[key] = result
	return result


func world_height() -> float:
	return height * _base_scale


func play_attack() -> void:
	attack_time = 0.0


func flash() -> void:
	_flash_t = 0.18


func die() -> void:
	dead = true
	_death_t = 0.0


func revive() -> void:
	dead = false
	_death_t = 0.0
	rotation = Vector3.ZERO
	position = Vector3.ZERO


func _process(delta: float) -> void:
	_time += delta
	phase += delta * walk_rate * TAU * clampf(walk, 0.0, 1.0)
	var s := sin(phase)
	var w := clampf(walk, 0.0, 1.0)
	var atk := 0.0
	if attack_time >= 0.0:
		attack_time += delta
		var t := attack_time / attack_duration
		if t >= 1.0:
			attack_time = -1.0
		else:
			# Levanta rápido y golpea: curva asimétrica.
			atk = sin(clampf(t / 0.45, 0.0, 1.0) * PI * 0.5) if t < 0.45 else 1.0 - (t - 0.45) / 0.55
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash_mat.albedo_color.a = clampf(_flash_t / 0.18, 0.0, 1.0) * 0.75
	elif _flash_mat.albedo_color.a > 0.0:
		_flash_mat.albedo_color.a = 0.0
	match rig:
		Rig.BIPED, Rig.GHOST:
			_set_rot("leg_l", Vector3(s * 0.65 * w, 0, 0))
			_set_rot("leg_r", Vector3(-s * 0.65 * w, 0, 0))
			_set_rot("arm_l", Vector3(-s * 0.55 * w, 0, -arm_down + 0.05 * sin(_time * 2.0)))
			_set_rot("arm_r", Vector3(s * 0.55 * w - atk * 2.3, 0, arm_down - 0.05 * sin(_time * 2.0)))
			var bob := absf(s) * 0.035 * w
			if rig == Rig.GHOST:
				bob = 0.12 + sin(_time * 2.2) * 0.06
			_root.position.y = bob
			_root.rotation.x = -0.08 * w - atk * 0.12
		Rig.QUAD:
			_set_rot("leg_fl", Vector3(s * 0.6 * w, 0, 0))
			_set_rot("leg_br", Vector3(s * 0.6 * w, 0, 0))
			_set_rot("leg_fr", Vector3(-s * 0.6 * w, 0, 0))
			_set_rot("leg_bl", Vector3(-s * 0.6 * w, 0, 0))
			_root.position.y = absf(s) * 0.03 * w
			_root.rotation.x = -atk * 0.35
		Rig.CRAB:
			for leg in ["leg_fl", "leg_br"]:
				_set_rot(leg, Vector3(0, 0, s * 0.5 * w))
			for leg in ["leg_fr", "leg_bl"]:
				_set_rot(leg, Vector3(0, 0, -s * 0.5 * w))
			_root.position.y = absf(s) * 0.02 * w
			_root.rotation.z = sin(phase * 0.5) * 0.08 * w
			_root.rotation.x = -atk * 0.3
	# Respiración en reposo.
	var breathe := 1.0 + sin(_time * 2.4) * 0.012 * (1.0 - w)
	_root.scale = Vector3(_base_scale, _base_scale * breathe, _base_scale)
	if dead:
		_death_t = minf(_death_t + delta, 1.2)
		rotation.x = lerpf(0.0, -PI * 0.5, minf(_death_t / 0.5, 1.0))
		position.y = -maxf(_death_t - 0.6, 0.0) * 1.2


func _set_rot(part: String, r: Vector3) -> void:
	var p: Node3D = _pivots.get(part)
	if p:
		p.rotation = r


func set_tint_overlay(color: Color) -> void:
	_flash_mat.albedo_color = Color(color.r, color.g, color.b, _flash_mat.albedo_color.a)
