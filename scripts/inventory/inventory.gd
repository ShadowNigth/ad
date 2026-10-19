class_name Inventory
extends RefCounted
## Inventario en cuadrícula con pilas, capacidad y durabilidad de herramientas.
## Cada hueco es null o {"id": String, "qty": int, "dur": int}.
## Todas las operaciones validan cantidades: nunca hay negativos ni duplicados.

signal changed

var slots: Array = []
var capacity: int = 24


func _init(cap: int = 24) -> void:
	set_capacity(cap)


func set_capacity(cap: int) -> void:
	capacity = maxi(cap, 1)
	while slots.size() < capacity:
		slots.append(null)
	# Nunca se eliminan objetos: si sobran huecos ocupados se mantienen.
	while slots.size() > capacity and slots.back() == null:
		slots.pop_back()
	changed.emit()


func clear() -> void:
	for i in slots.size():
		slots[i] = null
	changed.emit()


static func _stack(id: String) -> int:
	return maxi(GameData.stack_size(id), 1)


static func _max_dur(id: String) -> int:
	var t: Dictionary = GameData.item(id).get("tool", {})
	var base := int(t.get("durability", 0))
	if base <= 0:
		return 0
	return int(round(base * (1.0 + TechTree.mod("durability_mult"))))


func count(id: String) -> int:
	var total := 0
	for s in slots:
		if s != null and s.id == id:
			total += int(s.qty)
	return total


func has(id: String, qty: int = 1) -> bool:
	return count(id) >= qty


func free_slots() -> int:
	var n := 0
	for s in slots:
		if s == null:
			n += 1
	return n


func is_full() -> bool:
	return free_slots() == 0


## Cuántas unidades de `id` caben todavía.
func space_for(id: String) -> int:
	if not GameData.has_item(id):
		return 0
	var st := _stack(id)
	var room := 0
	for s in slots:
		if s == null:
			room += st
		elif s.id == id:
			room += maxi(st - int(s.qty), 0)
	return room


## Añade objetos. Devuelve lo que NO cupo.
func add(id: String, qty: int, dur: int = -1) -> int:
	if qty <= 0 or not GameData.has_item(id):
		return maxi(qty, 0)
	var st := _stack(id)
	var left := qty
	if st > 1:
		for s in slots:
			if left <= 0:
				break
			if s != null and s.id == id and int(s.qty) < st:
				var put := mini(st - int(s.qty), left)
				s.qty = int(s.qty) + put
				left -= put
	for i in slots.size():
		if left <= 0:
			break
		if slots[i] == null:
			var put := mini(st, left)
			var d := dur if dur >= 0 else _max_dur(id)
			slots[i] = {"id": id, "qty": put, "dur": d}
			left -= put
	if left != qty:
		changed.emit()
	return left


## Elimina `qty` unidades solo si hay suficientes. Devuelve true si se eliminaron.
func remove(id: String, qty: int) -> bool:
	if qty <= 0:
		return true
	if count(id) < qty:
		return false
	var left := qty
	# Se consumen primero las pilas más pequeñas (y herramientas más gastadas).
	var order: Array = []
	for i in slots.size():
		if slots[i] != null and slots[i].id == id:
			order.append(i)
	order.sort_custom(func(a, b): return int(slots[a].qty) < int(slots[b].qty))
	for i in order:
		if left <= 0:
			break
		var take := mini(int(slots[i].qty), left)
		slots[i].qty = int(slots[i].qty) - take
		left -= take
		if int(slots[i].qty) <= 0:
			slots[i] = null
	changed.emit()
	return true


func remove_at(index: int, qty: int = 1) -> Dictionary:
	if index < 0 or index >= slots.size() or slots[index] == null:
		return {}
	var s: Dictionary = slots[index]
	var take := mini(qty, int(s.qty))
	var out: Dictionary = {"id": s.id, "qty": take, "dur": s.get("dur", 0)}
	s.qty = int(s.qty) - take
	if int(s.qty) <= 0:
		slots[index] = null
	changed.emit()
	return out


## Mueve o fusiona el contenido de un hueco a otro.
func move(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= slots.size() or to >= slots.size():
		return
	var a: Variant = slots[from]
	var b: Variant = slots[to]
	if a == null:
		return
	if b != null and b.id == a.id and _stack(a.id) > 1:
		var st := _stack(a.id)
		var put := mini(st - int(b.qty), int(a.qty))
		b.qty = int(b.qty) + put
		a.qty = int(a.qty) - put
		if int(a.qty) <= 0:
			slots[from] = null
	else:
		slots[from] = b
		slots[to] = a
	changed.emit()


## Hueco con la mejor herramienta de un tipo (mayor potencia), o -1.
func best_tool(tool_type: String) -> int:
	var best := -1
	var best_power := -1
	for i in slots.size():
		var s: Variant = slots[i]
		if s == null:
			continue
		var t: Dictionary = GameData.item(s.id).get("tool", {})
		if t.get("type", "") == tool_type and int(t.get("power", 0)) > best_power:
			best_power = int(t.get("power", 0))
			best = i
	return best


func best_weapon() -> int:
	var best := -1
	var best_dmg := -1
	for i in slots.size():
		var s: Variant = slots[i]
		if s == null:
			continue
		var w: Dictionary = GameData.item(s.id).get("weapon", {})
		if not w.is_empty() and int(w.get("damage", 0)) > best_dmg:
			best_dmg = int(w.get("damage", 0))
			best = i
	return best


## Gasta durabilidad. Devuelve true si la herramienta se rompió.
func wear(index: int, amount: int = 1) -> bool:
	if index < 0 or index >= slots.size() or slots[index] == null:
		return false
	var s: Dictionary = slots[index]
	if int(s.get("dur", 0)) <= 0 and _max_dur(s.id) <= 0:
		return false  # herramienta sin desgaste
	s.dur = int(s.get("dur", 0)) - amount
	if int(s.dur) <= 0:
		slots[index] = null
		changed.emit()
		return true
	changed.emit()
	return false


func durability_ratio(index: int) -> float:
	if index < 0 or index >= slots.size() or slots[index] == null:
		return 0.0
	var mx := _max_dur(slots[index].id)
	if mx <= 0:
		return 1.0
	return clampf(float(slots[index].get("dur", mx)) / float(mx), 0.0, 1.0)


func sort_items() -> void:
	var items_list: Array = slots.filter(func(s): return s != null)
	items_list.sort_custom(func(a, b):
		var ia := GameData.item_order.find(a.id)
		var ib := GameData.item_order.find(b.id)
		if ia == ib:
			return int(a.qty) > int(b.qty)
		return ia < ib)
	for i in slots.size():
		slots[i] = items_list[i] if i < items_list.size() else null
	changed.emit()


func to_array() -> Array:
	var out: Array = []
	for s in slots:
		out.append(null if s == null else {"id": s.id, "qty": int(s.qty), "dur": int(s.get("dur", 0))})
	return out


func from_array(arr: Array) -> void:
	slots.clear()
	for s in arr:
		if s == null or typeof(s) != TYPE_DICTIONARY or not GameData.has_item(str(s.get("id", ""))):
			slots.append(null)
		else:
			var q := clampi(int(s.get("qty", 0)), 0, _stack(s.id))
			slots.append(null if q <= 0 else {"id": str(s.id), "qty": q, "dur": int(s.get("dur", 0))})
	while slots.size() < capacity:
		slots.append(null)
	changed.emit()


func all_items() -> Dictionary:
	var out := {}
	for s in slots:
		if s != null:
			out[s.id] = int(out.get(s.id, 0)) + int(s.qty)
	return out
