extends Node
## Trabajadores: contratación, asignación a edificios, entrenamiento y su
## efecto real sobre la velocidad de producción.

var hired: Array = []
var next_id: int = 1


func reset() -> void:
	hired.clear()
	next_id = 1


func type_data(type_id: String) -> Dictionary:
	return GameData.workers.get(type_id, {})


func is_type_unlocked(type_id: String) -> bool:
	return TechTree.is_unlocked(type_data(type_id).get("unlock"))


func count_of_type(type_id: String) -> int:
	return hired.filter(func(w): return w.type == type_id).size()


func housing_used() -> int:
	return hired.size()


func hire_cost(type_id: String) -> Dictionary:
	var growth := float(GameData.worker_settings.get("hire_growth", 1.35))
	var mult := pow(growth, count_of_type(type_id))
	var out := {}
	for id in type_data(type_id).get("hire_cost", {}):
		out[id] = int(ceil(float(type_data(type_id).hire_cost[id]) * mult))
	return out


func can_hire(type_id: String) -> Dictionary:
	if type_data(type_id).is_empty():
		return {"ok": false, "reason": "Tipo desconocido"}
	if not is_type_unlocked(type_id):
		return {"ok": false, "reason": "Requiere: %s" % GameData.tech(type_data(type_id).unlock).get("name", "")}
	if housing_used() >= Economy.housing_capacity():
		return {"ok": false, "reason": "Sin alojamiento: mejora el refugio o construye cabañas"}
	if not Economy.can_afford(hire_cost(type_id)):
		return {"ok": false, "reason": "Faltan materiales"}
	return {"ok": true, "reason": ""}


func hire(type_id: String) -> int:
	if not can_hire(type_id).ok:
		return -1
	if not Economy.pay(hire_cost(type_id)):
		return -1
	var names: Array = GameData.worker_names
	var w := {"id": next_id, "type": type_id, "name": names[(next_id - 1) % maxi(names.size(), 1)] if not names.is_empty() else "Trabajador",
			  "skill": 1, "building": -1}
	next_id += 1
	hired.append(w)
	# Se asigna automáticamente a un edificio compatible con hueco libre.
	for rec in Economy.buildings:
		if GameData.building(rec.type).get("worker_type", "") == type_id and free_slots(int(rec.uid)) > 0:
			w.building = int(rec.uid)
			break
	EventBus.worker_hired.emit(type_id)
	EventBus.workers_changed.emit()
	return int(w.id)


func get_worker(worker_id: int) -> Dictionary:
	for w in hired:
		if int(w.id) == worker_id:
			return w
	return {}


func workers_in(uid: int) -> Array:
	return hired.filter(func(w): return int(w.building) == uid)


func free_slots(uid: int) -> int:
	return Economy.worker_slots(uid) - workers_in(uid).size()


func assign(worker_id: int, uid: int) -> bool:
	var w := get_worker(worker_id)
	var rec := Economy.get_building(uid)
	if w.is_empty() or rec.is_empty():
		return false
	if GameData.building(rec.type).get("worker_type", "") != w.type:
		return false
	if int(w.building) == uid:
		return true
	if free_slots(uid) <= 0:
		return false
	w.building = uid
	EventBus.workers_changed.emit()
	return true


func unassign(worker_id: int) -> void:
	var w := get_worker(worker_id)
	if not w.is_empty():
		w.building = -1
		EventBus.workers_changed.emit()


func unassign_building(uid: int) -> void:
	for w in hired:
		if int(w.building) == uid:
			w.building = -1
	EventBus.workers_changed.emit()


## Asigna al edificio un trabajador libre del tipo correcto (botón "+").
func assign_any(uid: int) -> bool:
	var rec := Economy.get_building(uid)
	if rec.is_empty():
		return false
	var wt: String = GameData.building(rec.type).get("worker_type", "")
	for w in hired:
		if w.type == wt and int(w.building) < 0:
			return assign(int(w.id), uid)
	return false


func remove_one(uid: int) -> bool:
	var list := workers_in(uid)
	if list.is_empty():
		return false
	unassign(int(list.back().id))
	return true


func idle_of_type(type_id: String) -> int:
	return hired.filter(func(w): return w.type == type_id and int(w.building) < 0).size()


func train_cost(worker_id: int) -> Dictionary:
	var w := get_worker(worker_id)
	if w.is_empty():
		return {}
	var growth := float(GameData.worker_settings.get("train_growth", 1.7))
	var mult := pow(growth, int(w.skill) - 1)
	var out := {}
	for id in type_data(w.type).get("train_cost", {}):
		out[id] = int(ceil(float(type_data(w.type).train_cost[id]) * mult))
	return out


func can_train(worker_id: int) -> Dictionary:
	var w := get_worker(worker_id)
	if w.is_empty():
		return {"ok": false, "reason": "No existe"}
	if TechTree.mod("worker_training") <= 0.0:
		return {"ok": false, "reason": "Requiere: Capataces"}
	if int(w.skill) >= int(GameData.worker_settings.get("max_skill", 5)):
		return {"ok": false, "reason": "Habilidad máxima"}
	if not Economy.can_afford(train_cost(worker_id)):
		return {"ok": false, "reason": "Faltan materiales"}
	return {"ok": true, "reason": ""}


func train(worker_id: int) -> bool:
	if not can_train(worker_id).ok:
		return false
	if not Economy.pay(train_cost(worker_id)):
		return false
	var w := get_worker(worker_id)
	w.skill = int(w.skill) + 1
	EventBus.workers_changed.emit()
	return true


## Multiplicador de velocidad que aportan los trabajadores asignados.
func multiplier(uid: int) -> float:
	var m := 1.0
	var bonus := float(GameData.worker_settings.get("skill_bonus", 0.25))
	for w in workers_in(uid):
		var boost := float(type_data(w.type).get("boost", 0.5))
		m += boost * (1.0 + bonus * (int(w.skill) - 1)) * (1.0 + TechTree.mod("worker_efficiency"))
	return m


func to_dict() -> Dictionary:
	return {"hired": hired.duplicate(true), "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	reset()
	var seen := {}
	for w in d.get("hired", []):
		if typeof(w) != TYPE_DICTIONARY or not GameData.workers.has(str(w.get("type", ""))):
			continue
		var wid := int(w.get("id", next_id))
		if seen.has(wid):
			continue
		seen[wid] = true
		hired.append({"id": wid, "type": str(w.type), "name": str(w.get("name", "Trabajador")),
					  "skill": clampi(int(w.get("skill", 1)), 1, int(GameData.worker_settings.get("max_skill", 5))),
					  "building": int(w.get("building", -1))})
		next_id = maxi(next_id, wid + 1)
	next_id = maxi(next_id, int(d.get("next_id", 1)))
	# Asignaciones a edificios inexistentes o por encima de los huecos se liberan.
	for w in hired:
		if int(w.building) >= 0 and Economy.get_building(int(w.building)).is_empty():
			w.building = -1
	for rec in Economy.buildings:
		var list := workers_in(int(rec.uid))
		while list.size() > Economy.worker_slots(int(rec.uid)):
			list.back().building = -1
			list.pop_back()
