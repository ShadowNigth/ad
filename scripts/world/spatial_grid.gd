class_name SpatialGrid
extends RefCounted
## Rejilla espacial uniforme para buscar objetos cercanos sin recorrer todo
## el mundo (interacción, colocación de edificios, IA).

var cell_size: float
var cells: Dictionary = {}


func _init(cs: float = 8.0) -> void:
	cell_size = cs


func _key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / cell_size), floori(z / cell_size))


func insert(id: Variant, pos: Vector3) -> void:
	var k := _key(pos.x, pos.z)
	if not cells.has(k):
		cells[k] = {}
	cells[k][id] = pos


func remove(id: Variant, pos: Vector3) -> void:
	var k := _key(pos.x, pos.z)
	if cells.has(k):
		cells[k].erase(id)
		if cells[k].is_empty():
			cells.erase(k)


## Devuelve [[id, pos], ...] dentro del radio.
func query(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	var k0 := _key(pos.x - radius, pos.z - radius)
	var k1 := _key(pos.x + radius, pos.z + radius)
	for kx in range(k0.x, k1.x + 1):
		for kz in range(k0.y, k1.y + 1):
			var c: Variant = cells.get(Vector2i(kx, kz))
			if c == null:
				continue
			for id in c:
				var p: Vector3 = c[id]
				var dx := p.x - pos.x
				var dz := p.z - pos.z
				if dx * dx + dz * dz <= r2:
					out.append([id, p])
	return out


func nearest(pos: Vector3, radius: float, filter: Callable = Callable()) -> Variant:
	var best: Variant = null
	var best_d := INF
	for e in query(pos, radius):
		if filter.is_valid() and not filter.call(e[0]):
			continue
		var d := pos.distance_squared_to(e[1])
		if d < best_d:
			best_d = d
			best = e[0]
	return best
