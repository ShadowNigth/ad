extends Node
## Árbol tecnológico: puntos, tecnologías investigadas, edades y bonificaciones.

var points: int = 0
var researched: Dictionary = {}
var modifiers: Dictionary = {}
var _age := 0


func reset() -> void:
	points = 0
	researched.clear()
	_recalc()
	_age = age()


func is_researched(id: String) -> bool:
	return researched.has(id)


## true si la tecnología es null/"" (sin requisito) o ya está investigada.
func is_unlocked(tech_id: Variant) -> bool:
	if tech_id == null or str(tech_id) == "":
		return true
	return researched.has(str(tech_id))


func add_points(n: int) -> void:
	if n == 0:
		return
	points = maxi(points + n, 0)
	EventBus.tech_points_changed.emit(points)


func age() -> int:
	var req: Array = GameData.b("progression.age_requirements", [0, 2, 5, 9, 14, 20])
	var n := researched.size()
	var a := 0
	for i in req.size():
		if n >= int(req[i]):
			a = i
	return a


func age_name() -> String:
	return GameData.age_name(age())


func techs_for_next_age() -> int:
	var req: Array = GameData.b("progression.age_requirements", [0, 2, 5, 9, 14, 20])
	var a := age()
	if a + 1 >= req.size():
		return 0
	return int(req[a + 1]) - researched.size()


## Comprueba si se puede investigar. Devuelve {"ok": bool, "reason": String}.
func can_research(id: String) -> Dictionary:
	var t := GameData.tech(id)
	if t.is_empty():
		return {"ok": false, "reason": "Tecnología desconocida"}
	if researched.has(id):
		return {"ok": false, "reason": "Ya investigada"}
	if int(t.get("age", 0)) > age():
		return {"ok": false, "reason": "Requiere %s" % GameData.age_name(int(t.age))}
	for req in t.get("requires", []):
		if not researched.has(req):
			return {"ok": false, "reason": "Requiere: %s" % GameData.tech(req).get("name", req)}
	if points < int(t.get("cost", 0)):
		return {"ok": false, "reason": "Faltan puntos de tecnología"}
	var costs: Dictionary = t.get("items", {})
	if not costs.is_empty() and not Economy.can_afford(costs):
		return {"ok": false, "reason": "Faltan materiales"}
	return {"ok": true, "reason": ""}


func research(id: String) -> bool:
	var check := can_research(id)
	if not check.ok:
		return false
	var t := GameData.tech(id)
	var costs: Dictionary = t.get("items", {})
	if not costs.is_empty() and not Economy.pay(costs):
		return false
	points -= int(t.get("cost", 0))
	researched[id] = true
	_recalc()
	EventBus.tech_points_changed.emit(points)
	EventBus.tech_researched.emit(id)
	var new_age := age()
	if new_age != _age:
		_age = new_age
		EventBus.age_changed.emit(new_age)
	return true


func _recalc() -> void:
	modifiers.clear()
	for id in researched:
		var bonuses: Dictionary = GameData.tech(id).get("bonuses", {})
		for k in bonuses:
			modifiers[k] = float(modifiers.get(k, 0.0)) + float(bonuses[k])
	if is_inside_tree():
		GameState.apply_capacity_bonuses()


## Modificador acumulado (0.0 si no existe).
func mod(key: String, default: float = 0.0) -> float:
	return float(modifiers.get(key, default))


func to_dict() -> Dictionary:
	return {"points": points, "researched": researched.keys()}


func from_dict(d: Dictionary) -> void:
	points = maxi(int(d.get("points", 0)), 0)
	researched.clear()
	for id in d.get("researched", []):
		if GameData.techs.has(id):
			researched[id] = true
	_recalc()
	_age = age()
