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
