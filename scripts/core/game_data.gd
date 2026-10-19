extends Node
## Carga y expone todos los datos de diseño (JSON en res://data).
## Ningún coste, receta ni tasa de producción está escrito en el código:
## todo se consulta aquí.

const DATA_FILES := {
	"balance": "res://data/balance.json",
	"items": "res://data/items/items.json",
	"recipes": "res://data/recipes/recipes.json",
	"buildings": "res://data/buildings/buildings.json",
	"technologies": "res://data/technologies/technologies.json",
	"workers": "res://data/workers/workers.json",
	"enemies": "res://data/enemies/enemies.json",
	"quests": "res://data/quests/quests.json",
	"nodes": "res://data/world/nodes.json",
	"world": "res://data/world/world.json",
}

var balance: Dictionary = {}
var items: Dictionary = {}
var item_order: Array[String] = []
var recipes: Array = []
var recipes_by_id: Dictionary = {}
var buildings: Dictionary = {}
var building_order: Array[String] = []
var techs: Dictionary = {}
var tech_order: Array[String] = []
var branches: Array = []
var workers: Dictionary = {}
var worker_order: Array[String] = []
var worker_names: Array = []
var worker_settings: Dictionary = {}
var enemies: Dictionary = {}
var quests: Array = []
var nodes: Dictionary = {}
var world: Dictionary = {}
var load_errors: Array[String] = []

var _icon_cache: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	load_errors.clear()
	balance = _load_json(DATA_FILES.balance)
	items.clear()
	item_order.clear()
	for it in _load_json(DATA_FILES.items).get("items", []):
		items[it.id] = it
		item_order.append(it.id)
	recipes = _load_json(DATA_FILES.recipes).get("recipes", [])
	recipes_by_id.clear()
	for r in recipes:
		recipes_by_id[r.id] = r
	buildings.clear()
	building_order.clear()
	for b in _load_json(DATA_FILES.buildings).get("buildings", []):
		buildings[b.id] = b
		building_order.append(b.id)
	var tech_data := _load_json(DATA_FILES.technologies)
	branches = tech_data.get("branches", [])
	techs.clear()
	tech_order.clear()
	for t in tech_data.get("technologies", []):
		techs[t.id] = t
		tech_order.append(t.id)
	var wdata := _load_json(DATA_FILES.workers)
	workers.clear()
	worker_order.clear()
	for w in wdata.get("types", []):
		workers[w.id] = w
		worker_order.append(w.id)
	worker_names = wdata.get("names", [])
	worker_settings = wdata.get("settings", {})
	enemies.clear()
	for e in _load_json(DATA_FILES.enemies).get("enemies", []):
		enemies[e.id] = e
	quests = _load_json(DATA_FILES.quests).get("quests", [])
	nodes.clear()
	for n in _load_json(DATA_FILES.nodes).get("nodes", []):
		nodes[n.id] = n
	world = _load_json(DATA_FILES.world)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		load_errors.append("No existe " + path)
		push_error("GameData: no existe " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		load_errors.append("JSON inválido: " + path)
		push_error("GameData: JSON inválido en " + path)
		return {}
	return parsed


# ------------------------------------------------------------------ balance
## Acceso por ruta "seccion.clave" a balance.json.
func b(path: String, default: Variant = null) -> Variant:
	var cur: Variant = balance
	for part in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(part):
			return default
		cur = cur[part]
	return cur


func bf(path: String, default: float = 0.0) -> float:
	return float(b(path, default))


# ------------------------------------------------------------------ items
func item(id: String) -> Dictionary:
	return items.get(id, {})


func has_item(id: String) -> bool:
	return items.has(id)


func item_name(id: String) -> String:
	if id == "@investigacion":
		return "Puntos de tecnología"
	if id == "@energia":
		return "Energía"
	return str(items.get(id, {}).get("name", id))


func stack_size(id: String) -> int:
	return int(items.get(id, {}).get("stack", 99))


func item_icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var path := "res://assets/icons/items/%s.png" % id
	if id == "@investigacion":
		path = "res://assets/icons/ui/star.png"
	elif id == "@energia":
		path = "res://assets/textures/controls/icon_burst.png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_icon_cache[id] = tex
	return tex


func is_tool(id: String) -> bool:
	return items.get(id, {}).has("tool")


func is_weapon(id: String) -> bool:
	return items.get(id, {}).has("weapon")


func is_equippable(id: String) -> bool:
	var it: Dictionary = items.get(id, {})
	return it.has("tool") or it.has("weapon")


func is_consumable(id: String) -> bool:
	return items.get(id, {}).has("food")


func is_container(id: String) -> bool:
	return items.get(id, {}).has("container")


# ------------------------------------------------------------------ recetas
func recipe(id: String) -> Dictionary:
	return recipes_by_id.get(id, {})


func recipes_for_station(station: Variant) -> Array:
	var out: Array = []
	for r in recipes:
		if r.get("station") == station:
			out.append(r)
	return out


# ------------------------------------------------------------------ edificios
func building(id: String) -> Dictionary:
	return buildings.get(id, {})


func building_max_level(id: String) -> int:
	return buildings.get(id, {}).get("levels", []).size()


## Datos del nivel (1..n) con valores por defecto rellenados.
func building_level(id: String, level: int) -> Dictionary:
	var levels: Array = buildings.get(id, {}).get("levels", [])
	if levels.is_empty():
		return {}
	var idx := clampi(level - 1, 0, levels.size() - 1)
	var base := {
		"name": "", "hp": 100, "housing": 0, "storage": 0, "workers": 0, "speed": 1.0, "output": 1.0,
		"input": 1.0, "light": 0.0, "craft_speed": 1.0, "upgrade_cost": {}, "models": [],
	}
	var merged := base.duplicate(true)
	for k in levels[idx]:
		merged[k] = levels[idx][k]
	if (merged.models as Array).is_empty():
		for j in range(idx, -1, -1):
			if not (levels[j].get("models", []) as Array).is_empty():
				merged.models = levels[j].models
				break
	return merged


# ------------------------------------------------------------------ tecnologías
func tech(id: String) -> Dictionary:
	return techs.get(id, {})


func techs_in_branch(branch_id: String) -> Array:
	var out: Array = []
	for id in tech_order:
		if techs[id].branch == branch_id:
			out.append(techs[id])
	return out


func age_name(age: int) -> String:
	var names: Array = b("progression.age_names", [])
	if age >= 0 and age < names.size():
		return str(names[age])
	return "Edad %d" % age


# ------------------------------------------------------------------ validación
## Comprueba que todas las referencias cruzadas entre ficheros existen.
## Se usa en las pruebas automáticas y al arrancar en modo depuración.
func validate() -> Array[String]:
	var errors: Array[String] = load_errors.duplicate()
	var check_items := func(dict: Dictionary, where: String) -> void:
		for k in dict:
			if str(k).begins_with("@"):
				continue
			if not items.has(k):
				errors.append("%s: objeto desconocido '%s'" % [where, k])
	var check_tech := func(t: Variant, where: String) -> void:
		if t != null and not techs.has(t):
			errors.append("%s: tecnología desconocida '%s'" % [where, t])
	for r in recipes:
		if not items.has(r.result):
			errors.append("Receta %s: resultado desconocido %s" % [r.id, r.result])
		check_items.call(r.ingredients, "Receta " + r.id)
		check_tech.call(r.get("unlock"), "Receta " + r.id)
	for id in buildings:
		var bd: Dictionary = buildings[id]
		check_items.call(bd.get("cost", {}), "Edificio " + id)
		check_tech.call(bd.get("unlock"), "Edificio " + id)
		if bd.has("worker_type") and not workers.has(bd.worker_type):
			errors.append("Edificio %s: tipo de trabajador desconocido %s" % [id, bd.worker_type])
		for p in bd.get("production", []):
			check_items.call(p.get("in", {}), "Producción %s/%s" % [id, p.id])
			check_items.call(p.get("out", {}), "Producción %s/%s" % [id, p.id])
			check_tech.call(p.get("unlock"), "Producción %s/%s" % [id, p.id])
		var lvl := 0
		for l in bd.get("levels", []):
			lvl += 1
			check_items.call(l.get("upgrade_cost", {}), "Mejora %s nv%d" % [id, lvl])
			for m in l.get("models", []):
				if not ResourceLoader.exists("res://assets/models/%s.obj" % m.model):
					errors.append("Edificio %s nv%d: modelo inexistente %s" % [id, lvl, m.model])
			if l.has("spinner") and not ResourceLoader.exists("res://assets/models/%s.obj" % l.spinner.model):
				errors.append("Edificio %s: modelo de giro inexistente" % id)
	for id in techs:
		for req in techs[id].get("requires", []):
			check_tech.call(req, "Tecnología " + id)
		check_items.call(techs[id].get("items", {}), "Tecnología " + id)
	for id in items:
		var it: Dictionary = items[id]
		if not ResourceLoader.exists("res://assets/icons/items/%s.png" % id):
			errors.append("Objeto %s sin icono" % id)
		for key in ["drop_model", "hand_model"]:
			if it.has(key) and not ResourceLoader.exists("res://assets/models/%s.obj" % it[key]):
				errors.append("Objeto %s: modelo inexistente %s" % [id, it[key]])
	for id in enemies:
		var e: Dictionary = enemies[id]
		if not ResourceLoader.exists("res://assets/models/%s.obj" % e.model):
			errors.append("Enemigo %s: modelo inexistente %s" % [id, e.model])
		for d in e.get("drops", []):
			if not items.has(d.item):
				errors.append("Enemigo %s: botín desconocido %s" % [id, d.item])
	for id in nodes:
		var n: Dictionary = nodes[id]
		for m in n.get("models", []):
			if not ResourceLoader.exists("res://assets/models/%s.obj" % m):
				errors.append("Nodo %s: modelo inexistente %s" % [id, m])
		check_items.call(n.get("yield", {}), "Nodo " + id)
		for d in n.get("bonus", []):
			if not items.has(d.item):
				errors.append("Nodo %s: bonus desconocido %s" % [id, d.item])
	for q in quests:
		var qt: String = q.get("type", "")
		if qt in ["gather", "craft", "have", "eat"] and q.has("target") and q.target != "" and not items.has(q.target):
			errors.append("Misión %s: objeto desconocido %s" % [q.id, q.target])
		if qt in ["build", "upgrade"] and not buildings.has(q.target):
			errors.append("Misión %s: edificio desconocido %s" % [q.id, q.target])
		if qt == "research" and q.get("target", "") != "" and not techs.has(q.target):
			errors.append("Misión %s: tecnología desconocida %s" % [q.id, q.target])
		check_items.call(q.get("reward", {}).get("items", {}), "Misión " + q.id)
	for w in worker_order:
		check_items.call(workers[w].get("hire_cost", {}), "Trabajador " + w)
		check_items.call(workers[w].get("train_cost", {}), "Trabajador " + w)
		if not ResourceLoader.exists("res://assets/models/%s.obj" % workers[w].model):
			errors.append("Trabajador %s: modelo inexistente" % w)
	return errors
