class_name ProceduralRig
extends Node3D
## Animación procedural para modelos OBJ estáticos (sin esqueleto).
## Separa la malla en piezas (piernas, brazos, torso, cabeza) usando sus
## superficies o la posición de los triángulos, las cuelga de nodos pivote y
## las anima con transformaciones: caminar, atacar, recibir daño, morir.

enum Rig { BIPED, QUAD, CRAB, GHOST }

## Duración por defecto de cada acción (segundos). Cada una tiene su pose y se
## mezcla con la de andar/reposo: golpe, tala, minería, recoger, comer, martillo,
## celebrar, amago (aviso de ataque), embestida y retroceso al recibir daño.
const ACTIONS := {
	"attack": 0.42, "chop": 0.5, "mine": 0.56, "gather": 0.55, "eat": 0.9, "hammer": 0.42,
	"cheer": 1.1, "windup": 0.38, "lunge": 0.3, "flinch": 0.3,
}

static var _cache: Dictionary = {}

var rig: int = Rig.BIPED
var model_id := ""
var height := 1.0
var walk := 0.0            # 0..1 intensidad de la animación de andar
var walk_rate := 1.6       # ciclos por segundo a velocidad máxima
var arm_down := 1.2        # radianes para bajar los brazos en T
var phase := 0.0
var sprint_lean := 0.0     # inclinación extra al esprintar (radianes)
var airborne := false      # en el aire: piernas recogidas y brazos abiertos
var vertical_speed := 0.0  # para distinguir subida y caída
var idle_variations := true
var action := ""
var action_t := 0.0
var action_dur := 0.42
var dead := false
var _death_t := 0.0
var _death_axis := Vector3.RIGHT
var _death_sign := -1.0
var _flash_t := 0.0
var _telegraph_t := 0.0
var _freeze_t := 0.0
var _roll_t := -1.0
var _roll_dur := 0.32
var _squash := 0.0
var _spawn_t := -1.0
var _air := 0.0
var _idle_t := 0.0
var _idle_kind := ""
var _idle_anim_t := 0.0
var _time := 0.0
var _spin: Node3D
var _root: Node3D
var _pivots: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var hand_socket: Node3D
var _base_scale := 1.0
var _hip := 0.25


func build(model: String, rig_name: String, scale_factor: float, tint: Color = Color.WHITE) -> void:
	model_id = model
	rig = {"biped": Rig.BIPED, "quad": Rig.QUAD, "crab": Rig.CRAB, "ghost": Rig.GHOST}.get(rig_name, Rig.BIPED)
	_base_scale = scale_factor
	for c in get_children():
		c.queue_free()
	_pivots.clear()
	_meshes.clear()
	_overlay_on = false
	# Nodo intermedio para la voltereta (gira alrededor del centro del cuerpo).
	_spin = Node3D.new()
	_spin.name = "Giro"
	add_child(_spin)
	_root = Node3D.new()
	_root.name = "Modelo"
	_root.rotation.y = PI  # los modelos de Kenney miran a +Z; en Godot el frente es -Z
	_root.scale = Vector3.ONE * scale_factor
	_spin.add_child(_root)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 0.35, 0.3, 0.0)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var parts := _get_parts(model, rig, tint)
	height = float(parts.get("height", 1.0))
	_hip = height * 0.3
	for p in parts.list:
		var pivot := Node3D.new()
		pivot.name = p.name
		pivot.position = p.pivot
		_root.add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
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


## Lanza una acción con pose propia (ver ACTIONS). duration <= 0 usa la de la tabla.
func play_action(kind: String, duration: float = -1.0) -> void:
	if dead:
		return
	action = kind
	action_t = 0.0
	action_dur = duration if duration > 0.0 else float(ACTIONS.get(kind, 0.42))
	_idle_kind = ""
	_idle_t = 0.0


func play_attack() -> void:
	play_action("attack")


func is_acting() -> bool:
	return action != ""


## Voltereta hacia delante (esquiva).
func play_roll(duration: float) -> void:
	if dead:
		return
	_roll_t = 0.0
	_roll_dur = maxf(duration, 0.1)


func is_rolling() -> bool:
	return _roll_t >= 0.0


## Aplastamiento al aterrizar (0..1).
func land(strength: float) -> void:
	_squash = maxf(_squash, clampf(strength, 0.0, 1.0))


## Aparece creciendo con un pequeño rebote.
func spawn_in() -> void:
	_spawn_t = 0.0
	_root.scale = Vector3.ONE * 0.01


## Congela la pose un instante (sensación de impacto).
func freeze(seconds: float) -> void:
	_freeze_t = maxf(_freeze_t, seconds)


## Destello naranja intermitente: aviso de que va a atacar.
func telegraph(seconds: float) -> void:
	_telegraph_t = seconds


func flash() -> void:
	_flash_t = 0.18


func die() -> void:
	dead = true
	_death_t = 0.0
	action = ""
	_roll_t = -1.0
	_spin.transform = Transform3D.IDENTITY
	# Cae de espaldas o de lado, al azar.
	match randi() % 3:
		0:
			_death_axis = Vector3.RIGHT
			_death_sign = 1.0
		1:
			_death_axis = Vector3.BACK
			_death_sign = 1.0
		_:
			_death_axis = Vector3.BACK
			_death_sign = -1.0


func revive() -> void:
	dead = false
	_death_t = 0.0
	action = ""
	rotation = Vector3(0.0, rotation.y, 0.0)
	position = Vector3.ZERO
	scale = Vector3.ONE


# ------------------------------------------------------------------ animación
var _pose := {
	"leg_l": Vector3.ZERO, "leg_r": Vector3.ZERO, "arm_l": Vector3.ZERO, "arm_r": Vector3.ZERO,
	"leg_fl": Vector3.ZERO, "leg_fr": Vector3.ZERO, "leg_bl": Vector3.ZERO, "leg_br": Vector3.ZERO,
	"lean": 0.0, "twist": 0.0, "tilt": 0.0, "bob": 0.0, "lift": 0.0, "fwd": 0.0,
}
var _overlay_on := true
var _flash_color := Color(1, 0.35, 0.3)


static func _sm(x: float) -> float:
	return smoothstep(0.0, 1.0, x)


static func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


func _process(delta: float) -> void:
	_update_overlay(delta)
	if _freeze_t > 0.0:
		_freeze_t -= delta
		return
	_time += delta
	var w := clampf(walk, 0.0, 1.0)
	phase += delta * walk_rate * TAU * w
	_air = move_toward(_air, 1.0 if airborne else 0.0, delta * 7.0)
	_squash = move_toward(_squash, 0.0, delta * 5.5)
	var t := -1.0
	if action != "":
		action_t += delta
		t = action_t / maxf(action_dur, 0.01)
		if t >= 1.0:
			action = ""
			t = -1.0
	_base_pose(sin(phase), w)
	if t >= 0.0:
		_apply_action(t)
	_update_idle(delta, w)
	_apply_roll(delta)
	_apply_pose(delta, w)
	if dead:
		_update_death(delta)


func _base_pose(s: float, w: float) -> void:
	var idle := sin(_time * 2.0) * 0.05
	_pose.twist = 0.0
	_pose.tilt = 0.0
	_pose.lift = 0.0
	_pose.fwd = 0.0
	match rig:
		Rig.BIPED, Rig.GHOST:
			_pose.leg_l = Vector3(s * 0.65 * w, 0, 0)
			_pose.leg_r = Vector3(-s * 0.65 * w, 0, 0)
			_pose.arm_l = Vector3(-s * 0.55 * w, 0, -arm_down + idle)
			_pose.arm_r = Vector3(s * 0.55 * w, 0, arm_down - idle)
			# Inclinación positiva = hacia delante.
			_pose.lean = 0.06 * w + sprint_lean
			_pose.bob = absf(s) * 0.035 * w
			if rig == Rig.GHOST:
				_pose.bob = 0.12 + sin(_time * 2.2) * 0.06
				_pose.tilt = sin(_time * 1.3) * 0.05
			if _air > 0.001:
				var up := clampf(vertical_speed / 6.0, -1.0, 1.0)
				_pose.leg_l = _pose.leg_l.lerp(Vector3(-0.85 if up > 0.0 else -0.35, 0, 0), _air)
				_pose.leg_r = _pose.leg_r.lerp(Vector3(0.3 if up > 0.0 else -0.1, 0, 0), _air)
				_pose.arm_l = _pose.arm_l.lerp(Vector3(-0.35, 0, -arm_down + 0.8), _air)
				_pose.arm_r = _pose.arm_r.lerp(Vector3(-0.35, 0, arm_down - 0.8), _air)
				_pose.lean += 0.05 * _air
		Rig.QUAD:
			_pose.leg_fl = Vector3(s * 0.6 * w, 0, 0)
			_pose.leg_br = Vector3(s * 0.6 * w, 0, 0)
			_pose.leg_fr = Vector3(-s * 0.6 * w, 0, 0)
			_pose.leg_bl = Vector3(-s * 0.6 * w, 0, 0)
			_pose.lean = 0.0
			_pose.bob = absf(s) * 0.03 * w
		Rig.CRAB:
			_pose.leg_fl = Vector3(0, 0, s * 0.5 * w)
			_pose.leg_br = Vector3(0, 0, s * 0.5 * w)
			_pose.leg_fr = Vector3(0, 0, -s * 0.5 * w)
			_pose.leg_bl = Vector3(0, 0, -s * 0.5 * w)
			_pose.lean = 0.0
			_pose.bob = absf(s) * 0.02 * w
			_pose.tilt = sin(phase * 0.5) * 0.08 * w


func _apply_action(t: float) -> void:
	var biped := rig == Rig.BIPED or rig == Rig.GHOST
	var env := sin(clampf(t, 0.0, 1.0) * PI)
	match action:
		"attack":
			var r := _sm(t / 0.35)
			var k := _sm((t - 0.35) / 0.17)
			var amt := 1.0 - _sm((t - 0.6) / 0.4)
			if biped:
				var ax := lerpf(lerpf(0.0, -2.6, r), 0.45, k) * amt
				_pose.arm_r += Vector3(ax, 0, 0)
				_pose.arm_l.x += (0.3 * r * (1.0 - k) - 0.5 * k) * amt
				_pose.twist += (-0.25 * r * (1.0 - k) + 0.22 * k) * amt
				_pose.lean += (-0.1 * r * (1.0 - k) + 0.24 * k) * amt
			else:
				_lunge_quad(r, k, amt)
		"lunge":
			var k := _sm(t / 0.3)
			var amt := 1.0 - _sm((t - 0.45) / 0.55)
			if biped:
				_pose.arm_r += Vector3(lerpf(-2.4, 0.4, k) * amt, 0, 0)
				_pose.arm_l.x += lerpf(-1.2, 0.2, k) * amt
				_pose.lean += 0.3 * k * amt
				_pose.fwd += -0.12 * k * amt
			else:
				_lunge_quad(1.0, k, amt)
		"windup":
			var e := _sm(t / 0.7)
			if biped:
				_pose.arm_r += Vector3(-2.4 * e, 0, 0)
				_pose.arm_l.x += -1.2 * e
				_pose.lean += -0.26 * e
				_pose.twist += -0.2 * e
			else:
				_pose.lean += -0.3 * e
				_pose.fwd += 0.05 * e
				_pose.leg_fl += Vector3(-0.5 * e, 0, 0)
				_pose.leg_fr += Vector3(-0.5 * e, 0, 0)
		"chop":
			var r := _sm(t / 0.4)
			var k := _sm((t - 0.4) / 0.16)
			var amt := 1.0 - _sm((t - 0.62) / 0.38)
			var ay := lerpf(lerpf(0.0, -1.1, r), 0.75, k) * amt
			var ax := -1.5 * maxf(r, k) * amt
			_pose.arm_r += Vector3(ax, ay, -0.25 * amt)
			_pose.arm_l += Vector3(ax * 0.9, ay, 0.2 * amt)
			_pose.twist += lerpf(lerpf(0.0, -0.45, r), 0.4, k) * amt
			_pose.lean += (-0.05 * r * (1.0 - k) + 0.14 * k) * amt
		"mine":
			var r := _sm(t / 0.42)
			var k := _sm((t - 0.42) / 0.14)
			var amt := 1.0 - _sm((t - 0.62) / 0.38)
			var ax := lerpf(lerpf(0.0, -2.9, r), -0.5, k) * amt
			_pose.arm_r += Vector3(ax, 0, -0.3 * r * (1.0 - k) * amt)
			_pose.arm_l += Vector3(ax, 0, 0.3 * r * (1.0 - k) * amt)
			_pose.lean += (-0.18 * r * (1.0 - k) + 0.4 * k) * amt
			_pose.bob += -0.04 * k * amt
		"gather":
			var e := _sm(t / 0.25) * (1.0 - _sm((t - 0.7) / 0.3))
			if biped:
				var pick := sin(t * TAU * 2.0) * 0.25
				_pose.arm_r.x += (-1.0 + pick) * e
				_pose.arm_l.x += (-0.9 - pick) * e
				_pose.lean += 0.62 * e
				_pose.bob += -0.07 * e
				_pose.leg_l.x += 0.25 * e
				_pose.leg_r.x += -0.15 * e
			else:
				_pose.lean += 0.3 * e
		"eat":
			var e := _sm(t / 0.2) * (1.0 - _sm((t - 0.8) / 0.2))
			_pose.arm_r += Vector3(-2.1 * e, 0.7 * e, -0.5 * e)
			_pose.lean += (sin(t * TAU * 3.0) * 0.05 + 0.04) * e
		"hammer":
			var e := _sm(t / 0.12) * (1.0 - _sm((t - 0.85) / 0.15))
			var tap := absf(sin(t * PI * 3.0))
			_pose.arm_r.x += (-0.7 - 0.9 * tap) * e
			_pose.lean += 0.12 * e
		"cheer":
			var e := _sm(t / 0.15) * (1.0 - _sm((t - 0.8) / 0.2))
			if biped:
				var wave := sin(t * TAU * 3.0) * 0.3
				_pose.arm_l += Vector3(-2.9 * e, 0, wave * e)
				_pose.arm_r += Vector3(-2.9 * e, 0, -wave * e)
				_pose.lean += -0.08 * e
			_pose.lift += absf(sin(t * TAU)) * 0.14 * e
		"flinch":
			if biped:
				_pose.lean += -0.35 * env
				_pose.twist += 0.15 * env
				_pose.arm_l.z += 0.5 * env
				_pose.arm_r.z -= 0.5 * env
			else:
				_pose.lean += -0.28 * env
				_pose.tilt += 0.12 * env


## Embestida de cuadrúpedos y cangrejos: se echa atrás y muerde hacia delante.
func _lunge_quad(r: float, k: float, amt: float) -> void:
	_pose.lean += (-0.25 * r * (1.0 - k) + 0.35 * k) * amt
	_pose.fwd += (0.06 * r * (1.0 - k) - 0.16 * k) * amt
	if rig == Rig.QUAD:
		_pose.leg_fl += Vector3(-0.6 * k * amt, 0, 0)
		_pose.leg_fr += Vector3(-0.6 * k * amt, 0, 0)


## Pequeñas animaciones de reposo: mirar alrededor, estirarse o pastar.
func _update_idle(delta: float, w: float) -> void:
	if not idle_variations or dead:
		return
	if w < 0.05 and action == "" and _air < 0.01 and _roll_t < 0.0:
		_idle_t += delta
		if _idle_kind == "" and _idle_t > 6.0 and randf() < delta * 0.3:
			if rig == Rig.QUAD:
				_idle_kind = "graze" if randf() < 0.6 else "look"
			else:
				_idle_kind = "look" if randf() < 0.65 else "stretch"
			_idle_anim_t = 0.0
	else:
		_idle_t = 0.0
		_idle_kind = ""
	if _idle_kind == "":
		return
	_idle_anim_t += delta
	var dur: float = {"look": 2.6, "stretch": 1.8, "graze": 3.2}.get(_idle_kind, 2.0)
	var t := _idle_anim_t / dur
	if t >= 1.0:
		_idle_kind = ""
		_idle_t = 0.0
		return
	var e := _sm(t / 0.2) * (1.0 - _sm((t - 0.8) / 0.2))
	match _idle_kind:
		"look":
			_pose.twist += sin(t * TAU) * 0.4 * e
		"stretch":
			_pose.arm_l += Vector3(-2.6 * e, 0, 0.2 * e)
			_pose.arm_r += Vector3(-2.6 * e, 0, -0.2 * e)
			_pose.lean += -0.1 * e
		"graze":
			_pose.lean += (0.3 + sin(t * TAU * 4.0) * 0.04) * e


func _apply_roll(delta: float) -> void:
	if _roll_t < 0.0:
		return
	_roll_t += delta
	var rt := _roll_t / _roll_dur
	if rt >= 1.0:
		_roll_t = -1.0
		_spin.transform = Transform3D.IDENTITY
		return
	var env := sin(rt * PI)
	_pose.leg_l += Vector3(-1.3 * env, 0, 0)
	_pose.leg_r += Vector3(-1.3 * env, 0, 0)
	_pose.arm_l += Vector3(-1.0 * env, 0, 0.3 * env)
	_pose.arm_r += Vector3(-1.0 * env, 0, -0.3 * env)
	var ang := -TAU * _sm(rt)
	var c := Vector3(0.0, world_height() * 0.42, 0.0)
	var rb := Basis(Vector3.RIGHT, ang)
	_spin.transform = Transform3D(rb, c - rb * c + Vector3(0.0, env * world_height() * 0.12, 0.0))


func _apply_pose(delta: float, w: float) -> void:
	var lean: float = _pose.lean
	match rig:
		Rig.BIPED, Rig.GHOST:
			# El tronco se dobla por la cintura: las piernas compensan la inclinación.
			_set_rot("leg_l", _pose.leg_l + Vector3(-lean, 0, 0))
			_set_rot("leg_r", _pose.leg_r + Vector3(-lean, 0, 0))
			_set_rot("arm_l", _pose.arm_l)
			_set_rot("arm_r", _pose.arm_r)
		Rig.QUAD, Rig.CRAB:
			_set_rot("leg_fl", _pose.leg_fl)
			_set_rot("leg_fr", _pose.leg_fr)
			_set_rot("leg_bl", _pose.leg_bl)
			_set_rot("leg_br", _pose.leg_br)
	var breathe := 1.0 + sin(_time * 2.4) * 0.012 * (1.0 - w)
	var sy := breathe * (1.0 - 0.22 * _squash)
	var sxz := 1.0 + 0.12 * _squash
	var grow := 1.0
	if _spawn_t >= 0.0:
		_spawn_t += delta
		var k := clampf(_spawn_t / 0.45, 0.0, 1.0)
		grow = maxf(_ease_out_back(k), 0.01)
		if k >= 1.0:
			_spawn_t = -1.0
	_root.scale = Vector3(_base_scale * sxz, _base_scale * sy, _base_scale * sxz) * grow
	var bend := Vector3(lean, PI + float(_pose.twist), float(_pose.tilt))
	_root.rotation = bend
	var size_k := world_height() / 1.7
	var hip_local := Vector3(0.0, _hip * _root.scale.y, 0.0)
	var target := Vector3(0.0, hip_local.y + (float(_pose.bob) + float(_pose.lift)) * size_k, float(_pose.fwd) * world_height())
	_root.position = target - Basis.from_euler(bend) * hip_local


func _update_death(delta: float) -> void:
	_death_t = minf(_death_t + delta, 3.0)
	var k := clampf(_death_t / 0.5, 0.0, 1.0)
	var ang := (1.0 - pow(1.0 - k, 3.0)) * PI * 0.5
	if _death_t > 0.5 and _death_t < 0.72:
		ang -= sin((_death_t - 0.5) / 0.22 * PI) * 0.12
	if _death_axis == Vector3.RIGHT:
		rotation.x = ang * _death_sign
	else:
		rotation.z = ang * _death_sign
	position.y = -maxf(_death_t - 0.9, 0.0) * 1.0


func _update_overlay(delta: float) -> void:
	var a := 0.0
	var col := _flash_color
	if _flash_t > 0.0:
		_flash_t -= delta
		a = clampf(_flash_t / 0.18, 0.0, 1.0) * 0.75
	if _telegraph_t > 0.0:
		_telegraph_t -= delta
		if a <= 0.0:
			col = Color(1.0, 0.62, 0.15)
			a = 0.16 + 0.24 * (0.5 + 0.5 * sin(_time * 34.0))
	var want := a > 0.0
	if want != _overlay_on:
		# El material superpuesto solo se asigna mientras se ve (ahorra una pasada de dibujo).
		_overlay_on = want
		for mi in _meshes:
			mi.material_overlay = _flash_mat if want else null
	if want:
		_flash_mat.albedo_color = Color(col.r, col.g, col.b, a)


func _set_rot(part: String, r: Vector3) -> void:
	var p: Node3D = _pivots.get(part)
	if p:
		p.rotation = r


func set_tint_overlay(color: Color) -> void:
	_flash_color = color
