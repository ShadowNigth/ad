class_name IslandGenerator
extends RefCounted
## Genera la isla de forma determinista a partir de data/world/world.json:
## alturas, zonas jugables, río, laguna, caminos, cráter de la cueva y la
## malla low poly del terreno (sombreado plano con colores por cara).

enum Zone { MAR, PLAYA, PRADERA, BOSQUE, ROCOSA, JUNGLA, CUEVA, RIO, LAGO, CAMINO }
const ZONE_IDS := ["mar", "playa", "pradera", "bosque", "rocosa", "jungla", "cueva", "rio", "lago", "camino"]

var size := 256.0
var cell := 2.0
var n := 129
var half := 128.0
var seed_value := 1
var heights := PackedFloat32Array()
var zones := PackedByteArray()
var path_mask := PackedByteArray()
var world: Dictionary
var noise_coast := FastNoiseLite.new()
var noise_detail := FastNoiseLite.new()
var noise_ridge := FastNoiseLite.new()
var noise_color := FastNoiseLite.new()
var river_pts: Array[Vector2] = []
var paths: Array = []
var beach_width := 12.0


func _init(world_data: Dictionary, seed_in: int) -> void:
	world = world_data
	seed_value = seed_in
	size = GameData.bf("world.size", 256.0)
	cell = GameData.bf("world.cell", 2.0)
	n = int(size / cell) + 1
	half = size * 0.5
	noise_coast.seed = seed_in
	noise_coast.frequency = 0.9
	noise_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_detail.seed = seed_in + 11
	noise_detail.frequency = 0.035
	noise_ridge.seed = seed_in + 23
	noise_ridge.frequency = 0.03
	noise_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_ridge.fractal_octaves = 3
	noise_color.seed = seed_in + 37
	noise_color.frequency = 0.08
	for p in world.get("river", {}).get("points", []):
		river_pts.append(Vector2(float(p[0]), float(p[1])))
	for path in world.get("paths", []):
		var pts: Array[Vector2] = []
		for p in path.points:
			pts.append(Vector2(float(p[0]), float(p[1])))
		paths.append({"pts": pts, "width": float(path.get("width", 2.0))})


# ------------------------------------------------------------------ generación
func generate() -> void:
	heights.resize(n * n)
	zones.resize(n * n)
	path_mask.resize(n * n)
	for j in n:
		for i in n:
			var x := -half + i * cell
			var z := -half + j * cell
			heights[j * n + i] = _raw_height(x, z)
	_flatten_paths_and_camp()
	for j in n:
		for i in n:
			var x := -half + i * cell
			var z := -half + j * cell
			zones[j * n + i] = _classify(x, z, heights[j * n + i])


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _coast_signed(x: float, z: float) -> float:
	var island: Dictionary = world.get("island", {})
	var r := float(island.get("radius", 100.0))
	var a := atan2(z, x)
	var nr := noise_coast.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0)
	var radius: float = r + nr * float(island.get("coast_noise", 10.0))
	var s := radius - Vector2(x, z).length()
	# El cráter de la cueva siempre queda rodeado de tierra.
	var cr: Dictionary = world.get("crater", {})
	if not cr.is_empty():
		var c := Vector2(cr.center[0], cr.center[1])
		s = maxf(s, float(cr.outer_radius) + 10.0 - Vector2(x, z).distance_to(c))
	return s


func _raw_height(x: float, z: float) -> float:
	var island: Dictionary = world.get("island", {})
	var p := Vector2(x, z)
	var s := _coast_signed(x, z)
	var land := float(island.get("base_height", 2.6))
	for r in world.get("relief", []):
		var c := Vector2(r.center[0], r.center[1])
		var d := p.distance_to(c) / float(r.radius)
		if d < 1.0:
			var w := (1.0 - d * d) * (1.0 - d * d)
			land += float(r.height) * w
			if r.has("ridged"):
				land += float(r.ridged) * w * (noise_ridge.get_noise_2d(x, z) * 0.5 + 0.5)
	land += noise_detail.get_noise_2d(x, z) * 0.9
	var h: float
	var bw := beach_width + noise_detail.get_noise_2d(x * 0.4, z * 0.4) * 4.0
	if s < 0.0:
		h = maxf(s * 0.38, -7.0)
	elif s < bw:
		h = s / bw * 1.3
	else:
		h = lerpf(1.3, maxf(land, 1.3), _smooth(0.0, 22.0, s - bw))
	h = _apply_crater(p, h)
	h = _apply_water_carving(p, h)
	return h


func _apply_crater(p: Vector2, h: float) -> float:
	var cr: Dictionary = world.get("crater", {})
	if cr.is_empty():
		return h
	var c := Vector2(cr.center[0], cr.center[1])
	var d := p.distance_to(c)
	var r_in := float(cr.inner_radius)
	var r_out := float(cr.outer_radius)
	var fl := float(cr.floor)
	var rim := float(cr.rim)
	var out := h
	if d < r_in:
		out = fl + noise_detail.get_noise_2d(p.x * 2.0, p.y * 2.0) * 0.35
	elif d < r_in + 3.0:
		out = lerpf(fl, rim, _smooth(r_in, r_in + 3.0, d))
	elif d < r_out - 3.0:
		out = rim + noise_ridge.get_noise_2d(p.x, p.y) * 1.2
	elif d < r_out + 2.0:
		out = lerpf(rim, maxf(h, 4.0), _smooth(r_out - 3.0, r_out + 2.0, d))
	# Cañón de acceso (bloqueado por el derrumbe hasta usar explosivos).
	var canyon: Array = cr.get("canyon", [])
	if canyon.size() >= 2 and d < r_out + 6.0:
		var dist_c := INF
		for k in canyon.size() - 1:
			var a := Vector2(canyon[k][0], canyon[k][1])
			var b := Vector2(canyon[k + 1][0], canyon[k + 1][1])
			dist_c = minf(dist_c, _seg_dist(p, a, b))
		var w := float(cr.get("canyon_width", 3.0))
		if dist_c < w + 3.0:
			var t := _smooth(w, w + 3.0, dist_c)
			out = lerpf(float(cr.get("canyon_floor", fl + 0.5)), out, t)
	return out


func _apply_water_carving(p: Vector2, h: float) -> float:
	var out := h
	var rv: Dictionary = world.get("river", {})
	if river_pts.size() >= 2:
		var hw := float(rv.get("half_width", 3.5))
		var depth := float(rv.get("depth", 2.0))
		var dr := river_distance(p)
		if dr < hw:
			out = minf(out, -depth * (1.0 - pow(dr / hw, 2.0)) - 0.05)
		elif dr < hw + 7.0:
			out = minf(out, lerpf(0.15, out, _smooth(hw, hw + 7.0, dr)))
	var lk: Dictionary = world.get("lake", {})
	if not lk.is_empty():
		var c := Vector2(lk.center[0], lk.center[1])
		var r := float(lk.radius)
		var dl := p.distance_to(c)
		if dl < r:
			out = minf(out, -float(lk.depth) * sqrt(maxf(1.0 - pow(dl / r, 2.0), 0.0)) - 0.05)
		elif dl < r + 7.0:
			out = minf(out, lerpf(0.2, out, _smooth(r, r + 7.0, dl)))
	return out


func _flatten_paths_and_camp() -> void:
	var src := heights.duplicate()
	for j in range(2, n - 2):
		for i in range(2, n - 2):
			var x := -half + i * cell
			var z := -half + j * cell
			var p := Vector2(x, z)
			var idx := j * n + i
			var on_path := false
			for path in paths:
				if _poly_dist(p, path.pts) < float(path.width):
					on_path = true
					break
			if on_path and src[idx] > 0.3:
				var acc := 0.0
				for dj in range(-2, 3):
					for di in range(-2, 3):
						acc += src[(j + dj) * n + (i + di)]
				heights[idx] = maxf(lerpf(src[idx], acc / 25.0, 0.75), 0.35)
				path_mask[idx] = 1
	for poi in world.get("pois", []):
		if poi.get("type", "") != "camp":
			continue
		var c := Vector2(poi.pos[0], poi.pos[1])
		var r := float(poi.get("radius", 15.0))
		var target := sample_raw(c.x, c.y)
		for j in n:
			for i in n:
				var p := Vector2(-half + i * cell, -half + j * cell)
				var d := p.distance_to(c)
				if d < r + 6.0:
					var idx := j * n + i
					var t := _smooth(r + 6.0, r * 0.6, d)
					heights[idx] = lerpf(heights[idx], target, t)


func sample_raw(x: float, z: float) -> float:
	var i := clampi(int(round((x + half) / cell)), 0, n - 1)
	var j := clampi(int(round((z + half) / cell)), 0, n - 1)
	return heights[j * n + i]


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _poly_dist(p: Vector2, pts: Array) -> float:
	var best := INF
	for k in pts.size() - 1:
		best = minf(best, _seg_dist(p, pts[k], pts[k + 1]))
	return best


func river_distance(p: Vector2) -> float:
	return _poly_dist(p, river_pts)


## >0 al oeste del río (lado de la jungla).
func river_side(p: Vector2) -> float:
	var best := INF
	var side := 0.0
	for k in river_pts.size() - 1:
		var a := river_pts[k]
		var b := river_pts[k + 1]
		var d := _seg_dist(p, a, b)
		if d < best:
			best = d
			var dir := (b - a).normalized()
			var v := p - a
			side = dir.x * v.y - dir.y * v.x
	return side


func _classify(x: float, z: float, h: float) -> int:
	var p := Vector2(x, z)
	var lk: Dictionary = world.get("lake", {})
	if not lk.is_empty() and p.distance_to(Vector2(lk.center[0], lk.center[1])) < float(lk.radius) and h < 0.1:
		return Zone.LAGO
	if river_pts.size() >= 2 and river_distance(p) < float(world.river.get("half_width", 3.5)) + 0.5 and h < 0.1:
		return Zone.RIO
	if h < -0.02:
		return Zone.MAR
	var cr: Dictionary = world.get("crater", {})
	if not cr.is_empty():
		var d := p.distance_to(Vector2(cr.center[0], cr.center[1]))
		if d < float(cr.inner_radius) + 1.5:
			return Zone.CUEVA
	if river_pts.size() >= 2 and river_side(p) > 0.0:
		return Zone.JUNGLA
	var s := _coast_signed(x, z)
	if s < beach_width + 2.0 and h < 1.7:
		return Zone.PLAYA
	if path_mask[int(round((z + half) / cell)) * n + int(round((x + half) / cell))] == 1:
		return Zone.CAMINO
	for r in world.get("relief", []):
		if r.has("zone") and p.distance_to(Vector2(r.center[0], r.center[1])) < float(r.get("zone_radius", r.radius)):
			if r.zone == "rocosa" or h > 3.0:
				return ZONE_IDS.find(r.zone)
	if not cr.is_empty() and p.distance_to(Vector2(cr.center[0], cr.center[1])) < float(cr.outer_radius) + 4.0:
		return Zone.ROCOSA
	if h > 10.0:
		return Zone.ROCOSA
	return Zone.PRADERA


# ------------------------------------------------------------------ consultas
func in_bounds(x: float, z: float) -> bool:
	return absf(x) < half - cell and absf(z) < half - cell


## Altura exacta del terreno (misma triangulación que HeightMapShape3D).
func height_at(x: float, z: float) -> float:
	var u := clampf((x + half) / cell, 0.0, n - 1.001)
	var v := clampf((z + half) / cell, 0.0, n - 1.001)
	var i := int(u)
	var j := int(v)
	var fx := u - i
	var fz := v - j
	var ha := heights[j * n + i]
	var hb := heights[j * n + i + 1]
	var hc := heights[(j + 1) * n + i]
	var hd := heights[(j + 1) * n + i + 1]
	if fx + fz <= 1.0:
		return ha + (hb - ha) * fx + (hc - ha) * fz
	return hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.6
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func slope_deg(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))


func zone_index(x: float, z: float) -> int:
	var i := clampi(int(round((x + half) / cell)), 0, n - 1)
	var j := clampi(int(round((z + half) / cell)), 0, n - 1)
	return zones[j * n + i]


func zone_at(x: float, z: float) -> String:
	return ZONE_IDS[zone_index(x, z)]


func water_depth(x: float, z: float) -> float:
	return maxf(-height_at(x, z), 0.0)


func is_fresh_water(x: float, z: float) -> bool:
	var zi := zone_index(x, z)
	return (zi == Zone.RIO or zi == Zone.LAGO) and height_at(x, z) < 0.0


## Zona "de región" para los bloqueos: jungla al oeste del río, cueva en el cráter.
func region_at(x: float, z: float) -> String:
	var p := Vector2(x, z)
	var cr: Dictionary = world.get("crater", {})
	if not cr.is_empty() and p.distance_to(Vector2(cr.center[0], cr.center[1])) < float(cr.inner_radius) + 2.0:
		return "cueva"
	if river_pts.size() >= 2 and river_side(p) > 0.0 and river_distance(p) > 2.0:
		return "jungla"
	return ""


# ------------------------------------------------------------------ malla
func _face_color(cx: float, cz: float, h: float, slope: float) -> Color:
	var zi := zone_index(cx, cz)
	var zid: String = ZONE_IDS[zi]
	var zdata: Dictionary = world.get("zones", {}).get(zid, {})
	var col_arr: Array = zdata.get("color", [0.5, 0.7, 0.3])
	var col := Color(col_arr[0], col_arr[1], col_arr[2])
	var sand := Color(0.94, 0.84, 0.58)
	var wet_sand := Color(0.80, 0.69, 0.47)
	var rock := Color(0.56, 0.53, 0.5)
	if h < 0.0:
		var depth := -h
		col = wet_sand.lerp(Color(0.52, 0.5, 0.42), clampf(depth / 4.0, 0.0, 1.0))
	elif zi == Zone.PLAYA or h < 0.7:
		col = sand if h > 0.25 else wet_sand
	elif zi == Zone.CAMINO:
		col = Color(0.66, 0.53, 0.36)
	elif zi == Zone.JUNGLA and h < 1.2:
		col = sand.lerp(col, 0.5)
	if slope > 38.0 and h > 0.5:
		col = col.lerp(rock, clampf((slope - 38.0) / 14.0, 0.0, 1.0))
	if zi == Zone.ROCOSA or zi == Zone.CUEVA:
		col = col.lerp(rock.darkened(0.08), 0.35 + clampf((h - 8.0) / 20.0, 0.0, 0.4))
	var v := noise_color.get_noise_2d(cx, cz) * 0.06 + (fposmod(sin(cx * 12.9898 + cz * 78.233) * 43758.5453, 1.0) - 0.5) * 0.05
	return Color(clampf(col.r + v, 0, 1), clampf(col.g + v, 0, 1), clampf(col.b + v * 0.7, 0, 1))


## Construye la malla del terreno troceada en bloques (para descartar por frustum).
func build_chunks(chunk_cells: int = 32) -> Array:
	var out: Array = []
	var cells := n - 1
	var cj := 0
	while cj < cells:
		var ci := 0
		while ci < cells:
			out.append({"mesh": _build_chunk(ci, cj, mini(ci + chunk_cells, cells), mini(cj + chunk_cells, cells)),
						"center": Vector3(-half + (ci + chunk_cells * 0.5) * cell, 0.0, -half + (cj + chunk_cells * 0.5) * cell)})
			ci += chunk_cells
		cj += chunk_cells
	return out


func _build_chunk(i0: int, j0: int, i1: int, j1: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var count := (i1 - i0) * (j1 - j0) * 6
	verts.resize(count)
	norms.resize(count)
	cols.resize(count)
	var k := 0
	for j in range(j0, j1):
		for i in range(i0, i1):
			var x0 := -half + i * cell
			var z0 := -half + j * cell
			var a := Vector3(x0, heights[j * n + i], z0)
			var b := Vector3(x0 + cell, heights[j * n + i + 1], z0)
			var c := Vector3(x0, heights[(j + 1) * n + i], z0 + cell)
			var d := Vector3(x0 + cell, heights[(j + 1) * n + i + 1], z0 + cell)
			for tri in [[a, b, c], [b, d, c]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var nrm := (p2 - p0).cross(p1 - p0).normalized()
				var cen := (p0 + p1 + p2) / 3.0
				var slope := rad_to_deg(acos(clampf(nrm.y, -1.0, 1.0)))
				var col := _face_color(cen.x, cen.z, cen.y, slope)
				verts[k] = p0
				verts[k + 1] = p1
				verts[k + 2] = p2
				for m in 3:
					norms[k + m] = nrm
					cols[k + m] = col
				k += 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func collision_shape() -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	return shape


## Imagen del mapa (1 px = cell metros) coloreada por zona y relieve.
func build_map_image(res: int = 256) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for py in res:
		for px in res:
			var x := -half + (px + 0.5) * size / res
			var z := -half + (py + 0.5) * size / res
			var h := height_at(x, z)
			var col: Color
			if h < 0.0:
				var zi := zone_index(x, z)
				var shallow := Color(0.36, 0.72, 0.78) if zi in [Zone.RIO, Zone.LAGO] else Color(0.33, 0.66, 0.78)
				col = shallow.lerp(Color(0.12, 0.33, 0.52), clampf(-h / 6.0, 0.0, 1.0))
			else:
				col = _face_color(x, z, h, slope_deg(x, z))
				var shade := clampf(normal_at(x, z).dot(Vector3(-0.5, 0.8, -0.3).normalized()), 0.4, 1.0)
				col = col * (0.75 + 0.3 * shade)
				col.a = 1.0
			img.set_pixel(px, py, col)
	return img


## Textura de datos para el agua: R = profundidad, G = espuma de orilla, B = agua dulce.
func build_water_data(res: int = 256) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for py in res:
		for px in res:
			var x := -half + (px + 0.5) * size / res
			var z := -half + (py + 0.5) * size / res
			var h := height_at(x, z)
			var depth := clampf(-h / 6.0, 0.0, 1.0)
			var foam := clampf(1.0 - absf(h) / 0.9, 0.0, 1.0) if h < 0.25 else 0.0
			var zi := zone_index(x, z)
			var fresh := 1.0 if zi in [Zone.RIO, Zone.LAGO] else 0.0
			img.set_pixel(px, py, Color(depth, foam, fresh, 1.0))
	return img
