extends Node
## Biblioteca de modelos OBJ.
## - Carga los .obj importados como Mesh y unifica sus materiales (un material
##   compartido por textura/color) para reducir cambios de estado en la GPU.
## - Combina piezas de edificios en una única malla (menos draw calls en móvil).
## - Genera variantes tintadas (vetas de mineral, guardián de cristal...).

const MODEL_ROOT := "res://assets/models/%s.obj"

var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _tinted: Dictionary = {}
var _merged: Dictionary = {}
var _aabbs: Dictionary = {}


func path_for(model_id: String) -> String:
	return MODEL_ROOT % model_id


func exists(model_id: String) -> bool:
	return ResourceLoader.exists(path_for(model_id))


## Devuelve la malla del modelo con materiales canónicos (cacheada).
func mesh(model_id: String) -> Mesh:
	if _meshes.has(model_id):
		return _meshes[model_id]
	var path := path_for(model_id)
	if not ResourceLoader.exists(path):
		push_warning("ModelLibrary: no existe el modelo " + model_id)
		_meshes[model_id] = null
		return null
	var src: Mesh = load(path)
	var m: ArrayMesh = src.duplicate() if src is ArrayMesh else src
	if m is ArrayMesh:
		for s in m.get_surface_count():
			m.surface_set_material(s, canonical_material(m.surface_get_material(s)))
	_meshes[model_id] = m
	return m


func aabb(model_id: String) -> AABB:
	if not _aabbs.has(model_id):
		var m := mesh(model_id)
		_aabbs[model_id] = m.get_aabb() if m else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return _aabbs[model_id]


func _mat_key(mat: Material) -> String:
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		var tex_path := bm.albedo_texture.resource_path if bm.albedo_texture else ""
		return "%s|%s" % [tex_path, bm.albedo_color.to_html()]
	return str(mat.get_instance_id()) if mat else "none"


## Paleta tropical: ajusta los colores planos del Nature Kit (verdes azulados
## y piedra casi blanca) para que encajen con el terreno de la isla.
const PALETTE := {
	"grass": Color(0.38, 0.72, 0.3),
	"leafsGreen": Color(0.27, 0.64, 0.27),
	"leafsDark": Color(0.17, 0.46, 0.25),
	"stone": Color(0.68, 0.68, 0.66),
	"stoneDark": Color(0.54, 0.54, 0.53),
}


## Material compartido equivalente: mate, sin especular (más barato en móvil).
func canonical_material(mat: Material) -> Material:
	var key := _mat_key(mat)
	if _materials.has(key):
		return _materials[key]
	var out := StandardMaterial3D.new()
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		out.albedo_color = bm.albedo_color
		out.albedo_texture = bm.albedo_texture
		out.resource_name = bm.resource_name
		if bm.albedo_texture == null and PALETTE.has(bm.resource_name):
			out.albedo_color = PALETTE[bm.resource_name]
	out.roughness = 1.0
	out.metallic_specular = 0.15
	out.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	out.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_materials[key] = out
	return out


## Variante de la malla con todos los materiales multiplicados por un color.
func tinted_mesh(model_id: String, tint: Color) -> Mesh:
	if tint == Color.WHITE:
		return mesh(model_id)
	var key := "%s#%s" % [model_id, tint.to_html()]
	if _tinted.has(key):
		return _tinted[key]
	var base := mesh(model_id)
	if base == null:
		return null
	var m: ArrayMesh = base.duplicate()
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		var mk := "%s#%s" % [_mat_key(mat), tint.to_html()]
		if not _materials.has(mk):
			var t: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
			t.albedo_color = Color(t.albedo_color.r * tint.r, t.albedo_color.g * tint.g, t.albedo_color.b * tint.b, 1.0)
			_materials[mk] = t
		m.surface_set_material(s, _materials[mk])
	_tinted[key] = m
	return m


static func part_transform(part: Dictionary) -> Transform3D:
	var s: float = float(part.get("scale", 1.0))
	var rot: float = deg_to_rad(float(part.get("rot", 0.0)))
	var p: Array = part.get("pos", [0.0, 0.0, 0.0])
	var basis := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


## Combina varias piezas {model, scale, pos, rot, tint?} en una sola ArrayMesh.
func merged(parts: Array, cache_key: String = "") -> ArrayMesh:
	if cache_key != "" and _merged.has(cache_key):
		return _merged[cache_key]
	var tools: Dictionary = {}
	var mats: Dictionary = {}
	for part in parts:
		var tint := Color.WHITE
		if part.has("tint"):
			var t: Array = part.tint
			tint = Color(t[0], t[1], t[2])
		var m := tinted_mesh(part.model, tint)
		if m == null:
			continue
		var xf := part_transform(part)
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var mk := _mat_key(mat)
			if not tools.has(mk):
				tools[mk] = SurfaceTool.new()
				mats[mk] = mat
			(tools[mk] as SurfaceTool).append_from(m, s, xf)
	var out := ArrayMesh.new()
	for mk in tools:
		var st: SurfaceTool = tools[mk]
		st.set_material(mats[mk])
		st.commit(out)
	if cache_key != "":
		_merged[cache_key] = out
	return out


## ------------------------------------------------------------------
## Mallas "horneadas": el color de cada vértice se toma de la textura de paleta
## (colormap) o del color del material, y todas usan UN único material con
## color de vértice. Así una malla combinada o un MultiMesh = 1 llamada de dibujo.
var _baked_arrays: Dictionary = {}
var _baked_meshes: Dictionary = {}
var _tex_images: Dictionary = {}
var _vc_material: StandardMaterial3D
var _foliage_material: ShaderMaterial

## Vegetación que se mueve con el viento: fragmento del nombre -> amplitud.
const SWAY := {"palm": 1.0, "tree_": 0.9, "bush": 0.55, "plant_": 0.45, "grass": 0.45, "flower": 0.4, "crops_": 0.35,
	"flag": 0.6, "banner": 0.5}
const NO_SWAY := ["stump", "log", "moss"]


## Amplitud de balanceo de un modelo (0 = rígido).
func sway_amount(model_id: String) -> float:
	var n := model_id.get_file()
	for bad in NO_SWAY:
		if n.contains(bad):
			return 0.0
	for key in SWAY:
		if n.contains(key):
			return float(SWAY[key])
	return 0.0


## Material de la vegetación con viento (mismo aspecto que el de color de vértice).
func foliage_material() -> ShaderMaterial:
	if _foliage_material == null:
		_foliage_material = ShaderMaterial.new()
		_foliage_material.shader = load("res://assets/shaders/foliage.gdshader")
	return _foliage_material


## Fuerza del viento en la vegetación (el clima la sube con lluvia y tormenta).
func set_wind(strength: float, speed: float = 1.0) -> void:
	var m := foliage_material()
	m.set_shader_parameter("wind_strength", strength)
	m.set_shader_parameter("wind_speed", speed)


func vertex_color_material() -> StandardMaterial3D:
	if _vc_material == null:
		_vc_material = StandardMaterial3D.new()
		_vc_material.vertex_color_use_as_albedo = true
		_vc_material.vertex_color_is_srgb = true
		_vc_material.roughness = 1.0
		_vc_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _vc_material


func _texture_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var key := tex.resource_path
	if not _tex_images.has(key):
		var img := tex.get_image()
		if img and img.is_compressed():
			img.decompress()
		_tex_images[key] = img
	return _tex_images[key]


## Triángulos (sin índices) con posición, normal y color de vértice.
func baked_arrays(model_id: String, tint: Color = Color.WHITE) -> Dictionary:
	var key := "%s#%s" % [model_id, tint.to_html()]
	if _baked_arrays.has(key):
		return _baked_arrays[key]
	var out := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray()}
	var m := mesh(model_id)
	if m == null:
		_baked_arrays[key] = out
		return out
	var sway := sway_amount(model_id)
	var box := m.get_aabb()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var mat := m.surface_get_material(s) as StandardMaterial3D
		var albedo := mat.albedo_color if mat else Color.WHITE
		var img := _texture_image(mat.albedo_texture) if mat else null
		var base := Color(albedo.r * tint.r, albedo.g * tint.g, albedo.b * tint.b, 1.0)
		var vcols := PackedColorArray()
		vcols.resize(verts.size())
		for k in verts.size():
			var c := base
			if img and not uvs.is_empty():
				var uv := uvs[k]
				var px := clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1)
				var py := clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1)
				var t := img.get_pixel(px, py)
				c = Color(t.r * base.r, t.g * base.g, t.b * base.b, 1.0)
			# Alfa = peso del viento (0 en la base). El material opaco lo ignora.
			c.a = sway * clampf((verts[k].y - box.position.y) / maxf(box.size.y, 0.001), 0.0, 1.0)
			vcols[k] = c
		if idx.is_empty():
			out.v.append_array(verts)
			out.n.append_array(norms)
			out.c.append_array(vcols)
		else:
			for i in idx:
				out.v.append(verts[i])
				out.n.append(norms[i] if not norms.is_empty() else Vector3.UP)
				out.c.append(vcols[i])
	_baked_arrays[key] = out
	return out


func _arrays_to_mesh(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, foliage: bool = false) -> ArrayMesh:
	var am := ArrayMesh.new()
	if v.is_empty():
		return am
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, foliage_material() if foliage else vertex_color_material())
	return am


## Malla de un solo material (color de vértice) para MultiMesh.
func baked_mesh(model_id: String, tint: Color = Color.WHITE) -> ArrayMesh:
	var key := "%s#%s" % [model_id, tint.to_html()]
	if _baked_meshes.has(key):
		return _baked_meshes[key]
	var a := baked_arrays(model_id, tint)
	var am := _arrays_to_mesh(a.v, a.n, a.c, sway_amount(model_id) > 0.0)
	_baked_meshes[key] = am
	return am


## Combina piezas en una sola malla de un único material (1 llamada de dibujo).
func baked_merged(parts: Array, cache_key: String = "", foliage: bool = false) -> ArrayMesh:
	if cache_key != "" and _merged.has("B:" + cache_key):
		return _merged["B:" + cache_key]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	for part in parts:
		var tint := Color.WHITE
		if part.has("tint"):
			var t: Array = part.tint
			tint = Color(t[0], t[1], t[2])
		var a := baked_arrays(part.model, tint)
		if a.v.is_empty():
			continue
		var xf: Transform3D = part.get("xform", part_transform(part))
		v.append_array(xf * (a.v as PackedVector3Array))
		n.append_array(Transform3D(xf.basis, Vector3.ZERO) * (a.n as PackedVector3Array))
		c.append_array(a.c)
	var am := _arrays_to_mesh(v, n, c, foliage)
	if cache_key != "":
		_merged["B:" + cache_key] = am
	return am


## Caja que envuelve una lista de piezas (para colisiones y selección).
func parts_aabb(parts: Array) -> AABB:
	var result := AABB()
	var first := true
	for part in parts:
		var box := part_transform(part) * aabb(part.model)
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result
