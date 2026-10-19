extends Node
## Economía de la base: almacén compartido, edificios y producción automática.
## Es pura lógica de datos (sin nodos 3D), por lo que también se usa para el
## progreso sin conexión. Los nodos visuales escuchan EventBus.

const STATUS_OK := "Produciendo"
const STATUS_NO_INPUT := "Faltan materiales"
const STATUS_FULL := "Almacén lleno"
const STATUS_NO_ENERGY := "Sin energía"
const STATUS_NO_FUEL := "Sin combustible"
const STATUS_DAMAGED := "Dañado"
const STATUS_IDLE := "Sin producción"

var storage: Dictionary = {}
var buildings: Array = []
var next_uid: int = 1
var produced_total: Dictionary = {}
var energy_supply: float = 0.0
var energy_demand: float = 0.0
var energy_ratio: float = 1.0
var research_accum: float = 0.0

var _by_uid: Dictionary = {}
var _simulating := false
var _sim_log: Dictionary = {}
var _tick_accum := 0.0
var _storage_signal_cooldown := 0.0
var running := false


func reset() -> void:
	storage.clear()
	buildings.clear()
	_by_uid.clear()
	next_uid = 1
	produced_total.clear()
	research_accum = 0.0
	energy_ratio = 1.0


func _process(delta: float) -> void:
	if not running:
		return
	_tick_accum += delta
	var step := GameData.bf("economy.production_tick", 0.25)
	if _tick_accum >= step:
		tick(_tick_accum)
		_tick_accum = 0.0
	_storage_signal_cooldown -= delta


# ------------------------------------------------------------------ almacén
func capacity() -> int:
	var cap := GameData.bf("economy.base_storage", 150.0)
	for rec in buildings:
		cap += float(level_data(rec).get("storage", 0))
	return int(cap * (1.0 + TechTree.mod("storage_mult")))


func stored(id: String) -> int:
	return int(floor(float(storage.get(id, 0.0)) + 0.0001))


func stored_f(id: String) -> float:
	return float(storage.get(id, 0.0))


## Añade al almacén respetando la capacidad. Devuelve la cantidad aceptada.
func add_storage(id: String, qty: float) -> float:
	if qty <= 0.0 or not GameData.has_item(id):
		return 0.0
	var cur := float(storage.get(id, 0.0))
	var room := maxf(float(capacity()) - cur, 0.0)
	var put := minf(qty, room)
	if put > 0.0:
		storage[id] = cur + put
		_storage_changed()
	return put


func remove_storage(id: String, qty: float) -> bool:
	if qty <= 0.0:
		return true
	var cur := float(storage.get(id, 0.0))
	if cur + 0.0001 < qty:
		return false
	storage[id] = maxf(cur - qty, 0.0)
	if float(storage[id]) <= 0.0001:
		storage.erase(id)
	_storage_changed()
	return true


func _storage_changed() -> void:
	if _simulating:
		return
	EventBus.storage_changed.emit()


func total_available(id: String) -> int:
	return GameState.inventory.count(id) + stored(id)


func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if total_available(id) < int(cost[id]):
			return false
	return true


func missing_for(cost: Dictionary) -> Dictionary:
	var out := {}
	for id in cost:
		var have := total_available(id)
		if have < int(cost[id]):
			out[id] = int(cost[id]) - have
	return out


## Paga un coste usando primero el inventario y después el almacén.
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for id in cost:
		var need := int(cost[id])
		var from_inv := mini(GameState.inventory.count(id), need)
		if from_inv > 0:
			GameState.inventory.remove(id, from_inv)
		var rest := need - from_inv
		if rest > 0:
			remove_storage(id, rest)
	GameState.validate_equipped()
	return true


## Mueve recursos del inventario al almacén. Devuelve {id: cantidad} movido.
func deposit_from_inventory(only_resources: bool = true) -> Dictionary:
	var moved := {}
	var inv := GameState.inventory
	for i in inv.slots.size():
		var s: Variant = inv.slots[i]
		if s == null:
			continue
		var cat: String = GameData.item(s.id).get("cat", "")
		if only_resources and cat not in ["recurso", "especial"]:
			continue
		if cat in ["herramienta", "arma", "contenedor"]:
			continue
		var put := int(add_storage(s.id, float(s.qty)))
		if put > 0:
			inv.remove_at(i, put)
			moved[s.id] = int(moved.get(s.id, 0)) + put
	return moved


func withdraw(id: String, qty: int) -> int:
	var take := mini(qty, stored(id))
	take = mini(take, GameState.inventory.space_for(id))
	if take <= 0:
		return 0
	remove_storage(id, take)
	var left := GameState.inventory.add(id, take)
	if left > 0:
		add_storage(id, left)
	return take - left


# ------------------------------------------------------------------ edificios
func get_building(uid: int) -> Dictionary:
	return _by_uid.get(uid, {})


func count_of(type_id: String) -> int:
	var n := 0
	for rec in buildings:
		if rec.type == type_id:
			n += 1
	return n


func buildings_of(type_id: String) -> Array:
	return buildings.filter(func(r): return r.type == type_id)


func level_data(rec: Dictionary) -> Dictionary:
	return GameData.building_level(rec.type, int(rec.level))


func max_hp(rec: Dictionary) -> float:
	return float(level_data(rec).get("hp", 100))


func _scaled_cost(cost: Dictionary, mult: float) -> Dictionary:
	var out := {}
	var cm := maxf(1.0 + TechTree.mod("build_cost_mult"), 0.2)
	for id in cost:
		out[id] = maxi(int(ceil(float(cost[id]) * mult * cm)), 1)
	return out


func build_cost(type_id: String) -> Dictionary:
	var bd := GameData.building(type_id)
	var growth := float(bd.get("cost_growth", 1.5))
	return _scaled_cost(bd.get("cost", {}), pow(growth, count_of(type_id)))


## {"ok": bool, "reason": String}
func can_build(type_id: String) -> Dictionary:
	var bd := GameData.building(type_id)
	if bd.is_empty():
		return {"ok": false, "reason": "Edificio desconocido"}
	if not TechTree.is_unlocked(bd.get("unlock")):
		return {"ok": false, "reason": "Requiere tecnología: %s" % GameData.tech(bd.unlock).get("name", bd.unlock)}
	if count_of(type_id) >= int(bd.get("max_count", 99)):
		return {"ok": false, "reason": "Límite alcanzado (%d)" % int(bd.max_count)}
	if not GameState.inventory.has("martillo"):
		return {"ok": false, "reason": "Necesitas un martillo de construcción"}
	var req_item: String = bd.get("requires_item", "")
	if req_item != "" and not GameState.inventory.has(req_item):
		return {"ok": false, "reason": "Necesitas: %s" % GameData.item_name(req_item)}
	if not can_afford(build_cost(type_id)):
		return {"ok": false, "reason": "Faltan materiales"}
	return {"ok": true, "reason": ""}


## Crea el registro del edificio (los visuales se crean al recibir la señal).
func place_building(type_id: String, pos: Vector3, rot_deg: float, free: bool = false) -> int:
	if not free:
		if not can_build(type_id).ok:
			return -1
		if not pay(build_cost(type_id)):
			return -1
	var rec := {
		"uid": next_uid, "type": type_id, "level": 1,
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "rot": snappedf(rot_deg, 0.1),
		"hp": 0.0, "recipe": 0, "progress": 0.0, "fuel": 0.0, "status": STATUS_IDLE, "built": GameState.now(),
	}
	rec.hp = max_hp(rec)
	next_uid += 1
	buildings.append(rec)
	_by_uid[rec.uid] = rec
	GameState.add_stat("built")
	EventBus.building_placed.emit(rec.uid, type_id)
	_storage_changed()
	return rec.uid


func upgrade_cost(uid: int) -> Dictionary:
	var rec := get_building(uid)
	if rec.is_empty():
		return {}
	var nxt := GameData.building_level(rec.type, int(rec.level) + 1)
	return _scaled_cost(nxt.get("upgrade_cost", {}), 1.0)


func can_upgrade(uid: int) -> Dictionary:
	var rec := get_building(uid)
	if rec.is_empty():
		return {"ok": false, "reason": "No existe"}
	if int(rec.level) >= GameData.building_max_level(rec.type):
		return {"ok": false, "reason": "Nivel máximo"}
	if not GameState.inventory.has("martillo"):
		return {"ok": false, "reason": "Necesitas un martillo de construcción"}
	if float(rec.hp) < max_hp(rec) * 0.999:
		return {"ok": false, "reason": "Repáralo antes de mejorarlo"}
	if not can_afford(upgrade_cost(uid)):
		return {"ok": false, "reason": "Faltan materiales"}
	return {"ok": true, "reason": ""}


func upgrade(uid: int) -> bool:
	if not can_upgrade(uid).ok:
		return false
	if not pay(upgrade_cost(uid)):
		return false
	var rec := get_building(uid)
	rec.level = int(rec.level) + 1
	rec.hp = max_hp(rec)
	EventBus.building_upgraded.emit(uid, rec.type, int(rec.level))
	_storage_changed()
	return true


func repair_cost(uid: int) -> Dictionary:
	var rec := get_building(uid)
	if rec.is_empty():
		return {}
	var missing := 1.0 - clampf(float(rec.hp) / max_hp(rec), 0.0, 1.0)
	if missing <= 0.001:
		return {}
	var factor := GameData.bf("economy.repair_cost_factor", 0.35) * missing
	var base: Dictionary = GameData.building(rec.type).get("cost", {})
	var out := {}
	for id in base:
		out[id] = maxi(int(ceil(float(base[id]) * factor)), 1)
	return out


func repair(uid: int) -> bool:
	var rec := get_building(uid)
	if rec.is_empty():
		return false
	var cost := repair_cost(uid)
	if cost.is_empty():
		return false
	if not pay(cost):
		return false
	rec.hp = max_hp(rec)
	EventBus.building_repaired.emit(uid)
	return true


func damage_building(uid: int, amount: float) -> void:
	var rec := get_building(uid)
	if rec.is_empty() or amount <= 0.0:
		return
	rec.hp = maxf(float(rec.hp) - amount, 0.0)
	EventBus.building_damaged.emit(uid, float(rec.hp))


func demolish(uid: int) -> Dictionary:
	var rec := get_building(uid)
	if rec.is_empty():
		return {}
	var refund := {}
	var frac := GameData.bf("economy.demolish_refund", 0.5)
	for id in GameData.building(rec.type).get("cost", {}):
		var q := int(floor(float(GameData.building(rec.type).cost[id]) * frac))
		if q > 0:
			refund[id] = int(add_storage(id, q))
	Workers.unassign_building(uid)
	buildings.erase(rec)
	_by_uid.erase(uid)
	EventBus.building_removed.emit(uid, rec.type)
	return refund


func housing_capacity() -> int:
	var n := 0
	for rec in buildings:
		n += int(level_data(rec).get("housing", 0))
	return n


func worker_slots(uid: int) -> int:
	var rec := get_building(uid)
	if rec.is_empty():
		return 0
	var base := int(level_data(rec).get("workers", 0))
	if base <= 0:
		return 0
	return base + int(TechTree.mod("worker_slots"))


## Fuentes de luz (para la seguridad nocturna): [{pos, radius}]
func light_sources() -> Array:
	var out: Array = []
	for rec in buildings:
		var r := float(level_data(rec).get("light", 0.0))
		if r > 0.0 and float(rec.hp) > 0.0:
			out.append({"pos": Vector3(rec.pos[0], rec.pos[1], rec.pos[2]), "radius": r})
	return out


## ¿Hay un edificio que ofrezca la estación de fabricación cerca de `pos`?
func station_near(station: String, pos: Vector3, radius: float = 7.0) -> Dictionary:
	for rec in buildings:
		if GameData.building(rec.type).get("station", "") == station and float(rec.hp) > 0.0:
			var bp := Vector3(rec.pos[0], rec.pos[1], rec.pos[2])
			if bp.distance_to(pos) <= radius + float(GameData.building(rec.type).get("footprint", 1.0)):
				return rec
	return {}


func set_recipe(uid: int, idx: int) -> void:
	var rec := get_building(uid)
	var prods: Array = GameData.building(rec.get("type", "")).get("production", [])
	if rec.is_empty() or idx < 0 or idx >= prods.size():
		return
	if not TechTree.is_unlocked(prods[idx].get("unlock")):
		return
	if int(rec.recipe) != idx:
		rec.recipe = idx
		rec.progress = 0.0
		rec.fuel = 0.0


func production_of(rec: Dictionary) -> Dictionary:
	var prods: Array = GameData.building(rec.type).get("production", [])
	if prods.is_empty():
		return {}
	var idx := clampi(int(rec.get("recipe", 0)), 0, prods.size() - 1)
	if not TechTree.is_unlocked(prods[idx].get("unlock")):
		idx = 0
	return prods[idx]


## Multiplicador de velocidad total del edificio.
func speed_mult(rec: Dictionary) -> float:
	var lvl := level_data(rec)
	var m := float(lvl.get("speed", 1.0))
	m *= 1.0 + TechTree.mod("production_mult") + TechTree.mod("production_mult:" + str(rec.type))
	m *= Workers.multiplier(int(rec.uid))
	var hp_ratio := float(rec.hp) / maxf(max_hp(rec), 1.0)
	if hp_ratio < 0.5:
		m *= GameData.bf("economy.damaged_efficiency", 0.5)
	return maxf(m, 0.01)


func cycle_time(rec: Dictionary) -> float:
	var p := production_of(rec)
	if p.is_empty():
		return 0.0
	return float(p.get("interval", 30.0)) / speed_mult(rec)


func inputs_for(rec: Dictionary) -> Dictionary:
	var p := production_of(rec)
	var mult := float(level_data(rec).get("input", 1.0))
	var out := {}
	for id in p.get("in", {}):
		out[id] = float(p["in"][id]) * mult
	return out


func outputs_for(rec: Dictionary) -> Dictionary:
	var p := production_of(rec)
	var mult := float(level_data(rec).get("output", 1.0))
	var out := {}
	for id in p.get("out", {}):
		out[id] = float(p["out"][id]) * mult
	return out


func energy_of(rec: Dictionary) -> float:
	var p := production_of(rec)
	var e := float(p.get("energy", 0.0))
	if e > 0.0:
		e *= float(level_data(rec).get("output", 1.0))
	return e


func _has_inputs(rec: Dictionary) -> bool:
	var need := inputs_for(rec)
	for id in need:
		if float(storage.get(id, 0.0)) + 0.0001 < float(need[id]):
			return false
	return true


func _has_room(rec: Dictionary) -> bool:
	var cap := float(capacity())
	var outs := outputs_for(rec)
	for id in outs:
		if str(id).begins_with("@"):
			continue
		if float(storage.get(id, 0.0)) + float(outs[id]) > cap + 0.0001:
			return false
	return true


func _consume_inputs(rec: Dictionary) -> void:
	var need := inputs_for(rec)
	for id in need:
		storage[id] = maxf(float(storage.get(id, 0.0)) - float(need[id]), 0.0)
		if float(storage[id]) <= 0.0001:
			storage.erase(id)
		if _simulating:
			_sim_log[id] = float(_sim_log.get(id, 0.0)) - float(need[id])


func _produce_outputs(rec: Dictionary) -> Dictionary:
	var outs := outputs_for(rec)
	var cap := float(capacity())
	for id in outs:
		var q := float(outs[id])
		if id == "@investigacion":
			research_accum += q
			var whole := int(floor(research_accum))
			if whole > 0:
				research_accum -= whole
				TechTree.add_points(whole)
		else:
			storage[id] = minf(float(storage.get(id, 0.0)) + q, cap)
			produced_total[id] = float(produced_total.get(id, 0.0)) + q
		if _simulating:
			_sim_log[id] = float(_sim_log.get(id, 0.0)) + q
	return outs


# ------------------------------------------------------------------ simulación
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	# 1) Energía disponible (generadores con combustible en marcha).
	energy_supply = 0.0
	energy_demand = 0.0
	for rec in buildings:
		if float(rec.hp) <= 0.0:
			continue
		var e := energy_of(rec)
		if e > 0.0 and float(rec.get("fuel", 0.0)) > 0.0:
			energy_supply += e
		elif e < 0.0 and _has_inputs(rec) and _has_room(rec):
			energy_demand += -e
	energy_ratio = 1.0 if energy_demand <= 0.0 else clampf(energy_supply / energy_demand, 0.0, 1.0)
	var changed := false
	# 2) Producción.
	for rec in buildings:
		var p := production_of(rec)
		if p.is_empty():
			rec.status = STATUS_IDLE
			continue
		if float(rec.hp) <= 0.0:
			rec.status = STATUS_DAMAGED
			continue
		var ct := cycle_time(rec)
		var e := energy_of(rec)
		if e > 0.0:
			# Generador: consume combustible por ciclos y aporta energía mientras arde.
			rec.fuel = float(rec.get("fuel", 0.0)) - delta
			var guard := 0
			while float(rec.fuel) <= 0.0 and guard < 64:
				guard += 1
				if _has_inputs(rec):
					_consume_inputs(rec)
					rec.fuel = float(rec.fuel) + ct
					changed = true
				else:
					rec.fuel = 0.0
					break
			rec.status = STATUS_OK if float(rec.fuel) > 0.0 else STATUS_NO_FUEL
			rec.progress = 1.0 - clampf(float(rec.fuel) / maxf(ct, 0.001), 0.0, 1.0)
			continue
		var factor := 1.0
		if e < 0.0:
			factor = energy_ratio
			if factor <= 0.0:
				rec.status = STATUS_NO_ENERGY
				continue
		if not _has_inputs(rec):
			rec.status = STATUS_NO_INPUT
			continue
		if not _has_room(rec):
			rec.status = STATUS_FULL
			continue
		rec.status = STATUS_OK if factor >= 0.999 else STATUS_NO_ENERGY
		rec.progress = float(rec.progress) + delta * factor / maxf(ct, 0.001)
		var cycles := 0
		while float(rec.progress) >= 0.99999 and cycles < 2000:
			if not _has_inputs(rec) or not _has_room(rec):
				rec.progress = 0.999
				break
			_consume_inputs(rec)
			var outs := _produce_outputs(rec)
			rec.progress = maxf(float(rec.progress) - 1.0, 0.0)
			cycles += 1
			changed = true
			if not _simulating:
				EventBus.production_cycle.emit(int(rec.uid), outs)
	if changed and not _simulating and _storage_signal_cooldown <= 0.0:
		_storage_signal_cooldown = 0.2
		EventBus.storage_changed.emit()


## Simula `seconds` de producción (progreso sin conexión). Solo economía:
## no afecta al hambre, la sed ni la salud. Devuelve un resumen.
func simulate(seconds: float) -> Dictionary:
	var result := {"seconds": seconds, "items": {}, "research": 0}
	if seconds <= 0.0 or buildings.is_empty():
		return result
	var points_before := TechTree.points
	_simulating = true
	_sim_log.clear()
	var max_steps := int(GameData.b("economy.offline_steps", 1800))
	var steps := clampi(int(ceil(seconds / 4.0)), 1, max_steps)
	var dt := seconds / float(steps)
	for i in steps:
		tick(dt)
	_simulating = false
	for id in _sim_log:
		if str(id).begins_with("@"):
			continue
		var v := int(round(float(_sim_log[id])))
		if v != 0:
			result.items[id] = v
	result.research = TechTree.points - points_before
	EventBus.storage_changed.emit()
	return result


## Producción y consumo teóricos por minuto con la configuración actual.
func rates() -> Dictionary:
	var prod := {}
	var cons := {}
	for rec in buildings:
		var p := production_of(rec)
		if p.is_empty() or float(rec.hp) <= 0.0:
			continue
		var ct := cycle_time(rec)
		if ct <= 0.0:
			continue
		var per_min := 60.0 / ct
		if energy_of(rec) < 0.0:
			per_min *= energy_ratio
		if rec.status in [STATUS_NO_INPUT, STATUS_FULL, STATUS_NO_FUEL]:
			continue
		for id in outputs_for(rec):
			prod[id] = float(prod.get(id, 0.0)) + float(outputs_for(rec)[id]) * per_min
		for id in inputs_for(rec):
			cons[id] = float(cons.get(id, 0.0)) + float(inputs_for(rec)[id]) * per_min
	return {"production": prod, "consumption": cons}


## Producción por minuto de un único edificio (para su panel).
func building_rate(rec: Dictionary) -> Dictionary:
	var ct := cycle_time(rec)
	var out := {}
	if ct <= 0.0:
		return out
	for id in outputs_for(rec):
		out[id] = float(outputs_for(rec)[id]) * 60.0 / ct
	return out


# ------------------------------------------------------------------ guardado
func to_dict() -> Dictionary:
	var recs: Array = []
	for rec in buildings:
		var r: Dictionary = rec.duplicate(true)
		r.erase("status")
		recs.append(r)
	return {"storage": storage.duplicate(), "buildings": recs, "next_uid": next_uid,
			"produced": produced_total.duplicate(), "research_accum": research_accum}


func from_dict(d: Dictionary) -> void:
	reset()
	var st: Variant = d.get("storage", {})
	if typeof(st) == TYPE_DICTIONARY:
		for id in st:
			if GameData.has_item(id):
				storage[id] = maxf(float(st[id]), 0.0)
	for r in d.get("buildings", []):
		if typeof(r) != TYPE_DICTIONARY or not GameData.buildings.has(str(r.get("type", ""))):
			continue
		var rec := {
			"uid": int(r.get("uid", next_uid)), "type": str(r.type),
			"level": clampi(int(r.get("level", 1)), 1, GameData.building_max_level(str(r.type))),
			"pos": r.get("pos", [0, 0, 0]), "rot": float(r.get("rot", 0.0)),
			"hp": float(r.get("hp", 100.0)), "recipe": int(r.get("recipe", 0)),
			"progress": clampf(float(r.get("progress", 0.0)), 0.0, 0.999), "fuel": maxf(float(r.get("fuel", 0.0)), 0.0),
			"status": STATUS_IDLE, "built": float(r.get("built", 0.0)),
		}
		if _by_uid.has(rec.uid):
			continue  # evita duplicados en partidas corruptas
		rec.hp = clampf(float(rec.hp), 0.0, max_hp(rec))
		buildings.append(rec)
		_by_uid[rec.uid] = rec
		next_uid = maxi(next_uid, int(rec.uid) + 1)
	next_uid = maxi(next_uid, int(d.get("next_uid", 1)))
	var pr: Variant = d.get("produced", {})
	if typeof(pr) == TYPE_DICTIONARY:
		produced_total = pr
	research_accum = clampf(float(d.get("research_accum", 0.0)), 0.0, 0.999)
	# Recorta el almacén a la capacidad actual (por si cambió el equilibrio).
	var cap := float(capacity())
	for id in storage.keys():
		storage[id] = minf(float(storage[id]), cap)
