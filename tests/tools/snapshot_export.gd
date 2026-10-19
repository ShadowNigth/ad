extends Node
## Exporta la geometría visible de una zona del mundo (terreno, MultiMesh,
## mallas) a JSON para renderizarla sin GPU con tools/render_snapshot.py.
## Sirve para revisar escala, orientación y materiales de los modelos OBJ.
## Uso: godot --headless --path . tests/tools/snapshot_export.tscn -- x z radio [escenario]

var meshes: Dictionary = {}
var items: Array = []
var focus := Vector3.ZERO
var radius := 40.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	SaveManager.enabled = false
	TechTree.reset()
	GameState.new_game()
	Economy.reset()
	Workers.reset()
	Quests.reset()
	var scenario := args[3] if args.size() > 3 else ""
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	for i in 30:
		await get_tree().process_frame
	if scenario == "base":
		_prepare_base(world)
		for i in 90:
			await get_tree().process_frame
	if scenario in ["enemies", "unlock"]:
		GameState.unlock_region("jungla")
		GameState.unlock_region("cueva")
		for i in 5:
			await get_tree().process_frame
	var p: Node3D = world.player
	focus = p.global_position
	if args.size() >= 2:
		focus = Vector3(float(args[0]), 0.0, float(args[1]))
		focus.y = world.height_at(focus.x, focus.z)
	if args.size() >= 3:
		radius = float(args[2])
	if scenario in ["player", "enemies", "unlock", "base"]:
		p.global_position = focus + Vector3(0, 0.1, 0)
	if scenario == "enemies":
		var k := 0
		for t in ["cangrejo", "jabali", "esqueleto", "zombi", "fantasma", "tigre", "ciervo"]:
			var a := TAU * k / 7.0
			world.enemies._spawn(t, focus + Vector3(cos(a) * 5.0, 0.5, sin(a) * 5.0))
			k += 1
	for i in 10:
		await get_tree().process_frame
	_walk(world)
	var cam := {"focus": [focus.x, focus.y, focus.z], "player": [p.global_position.x, p.global_position.y, p.global_position.z]}
	var doc := {"meshes": meshes, "items": items, "camera": cam}
	var f := FileAccess.open("/tmp/snapshot.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	print("Exportados %d elementos, %d mallas" % [items.size(), meshes.size()])
	get_tree().quit()


func _prepare_base(world: Node) -> void:
	# Base de ejemplo para revisar edificios: se colocan algunos sin coste.
	var c := Vector3(6, 0, 28)
	var list := [["refugio", Vector3(-6, 0, -4), 0], ["fogata", Vector3(0, 0, 2), 0], ["almacen", Vector3(6, 0, -5), 0],
		["lenador", Vector3(-9, 0, 6), 90], ["cantera", Vector3(9, 0, 6), 270], ["huerto", Vector3(-3, 0, 12), 0],
		["aserradero", Vector3(4, 0, 13), 0], ["purificador", Vector3(12, 0, 0), 0], ["antorcha", Vector3(3, 0, -1), 0]]
	for e in list:
		var pos: Vector3 = c + e[1]
		pos.y = world.height_at(pos.x, pos.z)
		Economy.place_building(e[0], pos, float(e[2]), true)
	TechTree.researched["aut_organizacion"] = true
	TechTree._recalc()
	GameState.inventory.add("bayas", 50)
	GameState.inventory.add("madera", 200)
	Workers.hire("lenador")


func _mesh_id(m: Mesh) -> String:
	var id := str(m.get_instance_id())
	if meshes.has(id):
		return id
	var surfs: Array = []
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var mat: Material = m.surface_get_material(s)
		var info := {"color": [1, 1, 1, 1], "tex": "", "vcol": false}
		_mat_info(mat, info)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var vflat := PackedFloat32Array()
		for v in verts:
			vflat.append(v.x); vflat.append(v.y); vflat.append(v.z)
		var entry := {"v": Marshalls.raw_to_base64(vflat.to_byte_array()), "info": info}
		if arr[Mesh.ARRAY_TEX_UV] != null:
			var uvf := PackedFloat32Array()
			for uv in (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array):
				uvf.append(uv.x); uvf.append(uv.y)
			entry["uv"] = Marshalls.raw_to_base64(uvf.to_byte_array())
		if arr[Mesh.ARRAY_COLOR] != null:
			var cf := PackedFloat32Array()
			for c in (arr[Mesh.ARRAY_COLOR] as PackedColorArray):
				cf.append(c.r); cf.append(c.g); cf.append(c.b)
			entry["c"] = Marshalls.raw_to_base64(cf.to_byte_array())
		if arr[Mesh.ARRAY_INDEX] != null:
			entry["i"] = Marshalls.raw_to_base64((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())
		surfs.append(entry)
	meshes[id] = surfs
	return id


func _mat_info(mat: Material, info: Dictionary) -> void:
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		info.color = [bm.albedo_color.r, bm.albedo_color.g, bm.albedo_color.b, bm.albedo_color.a]
		if bm.albedo_texture:
			info.tex = ProjectSettings.globalize_path(bm.albedo_texture.resource_path)
		info.vcol = bm.vertex_color_use_as_albedo
	elif mat is ShaderMaterial:
		info.color = [0.2, 0.6, 0.75, 0.6]
		info.shader = true


## En modo headless el servidor de render no guarda las transformaciones de
## MultiMesh, así que se reconstruyen desde los registros de nodos.
func _resource_xf(rm: ResourceNodeManager, mmi: MultiMeshInstance3D, k: int) -> Transform3D:
	var key := ""
	for kk in rm._mm:
		if rm._mm[kk] == mmi:
			key = kk
	for rec in rm.nodes:
		if rec.mm_key == key and int(rec.mm_index) == k:
			if rec.depleted:
				return Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), rec.pos)
			return rm.node_transform(rec)
		if rec.get("fruit_key", "") == key and int(rec.fruit_index) == k:
			var nd: Dictionary = GameData.nodes[rec.type]
			var fs := float(nd.get("fruit_scale", 2.5))
			var top: float = ModelLibrary.aabb(rec.model).end.y * float(rec.scale) * 0.82
			return Transform3D(Basis(Vector3.UP, rec.rot).scaled(Vector3(fs, fs, fs)), rec.pos + Vector3(0, top, 0))
	return Transform3D()


func _xf(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]


func _walk(n: Node) -> void:
	if n is Node3D and not (n as Node3D).is_visible_in_tree():
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var gt := mi.global_transform
		var far := Vector2(gt.origin.x - focus.x, gt.origin.z - focus.z).length() > radius + 40.0
		var is_big := mi.mesh.get_aabb().size.length() * gt.basis.get_scale().x > 60.0
		if not far or is_big:
			if not (mi.material_override is ShaderMaterial and mi.name != "Agua"):
				var item := {"mesh": _mesh_id(mi.mesh), "xf": _xf(gt)}
				if mi.material_override:
					var info := {"color": [1, 1, 1, 1], "tex": "", "vcol": false}
					_mat_info(mi.material_override, info)
					item["override"] = info
				items.append(item)
	elif n is MeshInstance3D and n.has_meta("parts") and false:
		pass
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		var mid := ""
		var xfs: Array = mmi.get_meta("xforms", [])
		var owner_rm: Node = mmi.get_parent()
		for k in count:
			var local: Transform3D
			if not xfs.is_empty():
				local = xfs[k]
			elif owner_rm is ResourceNodeManager:
				local = _resource_xf(owner_rm, mmi, k)
			else:
				local = mm.get_instance_transform(k)
			var t := mmi.global_transform * local
			if Vector2(t.origin.x - focus.x, t.origin.z - focus.z).length() > radius:
				continue
			if t.basis.get_scale().x < 0.01:
				continue
			if mid == "":
				mid = _mesh_id(mm.mesh)
			items.append({"mesh": mid, "xf": _xf(t)})
	for c in n.get_children():
		_walk(c)
