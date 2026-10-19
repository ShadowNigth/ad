class_name Crafter
extends Node
## Cola de fabricación manual. Comprueba recetas desbloqueadas, estación
## cercana e ingredientes; consume al empezar cada unidad y entrega al
## terminar (nunca duplica ni deja contadores negativos).

signal queue_changed
signal crafted(item_id: String, qty: int)

const MAX_QUEUE := 8

var world: World
var queue: Array = []       # [{"recipe": id}]
var current: Dictionary = {}
var progress := 0.0
var duration := 1.0


func setup(w: World) -> void:
	world = w


func recipe_unlocked(r: Dictionary) -> bool:
	return TechTree.is_unlocked(r.get("unlock"))


func station_for(r: Dictionary) -> Dictionary:
	var st: Variant = r.get("station")
	if st == null:
		return {"ok": true, "speed": 1.0}
	var pos: Vector3 = world.player.global_position if world and world.player else Vector3.ZERO
	var rec := Economy.station_near(str(st), pos, 7.0)
	if rec.is_empty():
		return {"ok": false, "speed": 1.0}
	var lvl := Economy.level_data(rec)
	return {"ok": true, "speed": float(lvl.get("craft_speed", 1.0)) * (1.0 + TechTree.mod("station_speed:" + str(st)))}


static func station_name(st: Variant) -> String:
	match str(st):
		"fogata":
			return "Fogata"
		"taller":
			return "Taller"
		"fundicion":
			return "Fundición"
	return "A mano"


func can_craft(recipe_id: String) -> Dictionary:
	var r := GameData.recipe(recipe_id)
	if r.is_empty():
		return {"ok": false, "reason": "Receta desconocida"}
	if not recipe_unlocked(r):
		return {"ok": false, "reason": "Requiere: %s" % GameData.tech(r.unlock).get("name", r.unlock)}
	if not station_for(r).ok:
		return {"ok": false, "reason": "Acércate a: %s" % station_name(r.station)}
	if not Economy.can_afford(r.ingredients):
		return {"ok": false, "reason": "Faltan ingredientes"}
	return {"ok": true, "reason": ""}


func enqueue(recipe_id: String, count: int = 1) -> int:
	var check := can_craft(recipe_id)
	if not check.ok:
		EventBus.notify(check.reason, "warn")
		return 0
	var added := 0
	for i in count:
		if queue.size() + (0 if current.is_empty() else 1) >= MAX_QUEUE:
			break
		queue.append({"recipe": recipe_id})
		added += 1
	queue_changed.emit()
	return added


func cancel_all() -> void:
	queue.clear()
	if not current.is_empty():
		# Devuelve los ingredientes de la unidad en curso.
		var r := GameData.recipe(current.recipe)
		for id in r.get("ingredients", {}):
			var left := GameState.give(id, int(r.ingredients[id]))
			if left > 0:
				Economy.add_storage(id, left)
	current = {}
	progress = 0.0
	queue_changed.emit()


func _process(delta: float) -> void:
	if current.is_empty():
		if queue.is_empty():
			return
		var next: Dictionary = queue.pop_front()
		var r := GameData.recipe(next.recipe)
		var check := can_craft(next.recipe)
		if not check.ok:
			EventBus.notify(check.reason, "warn")
			queue.clear()
			queue_changed.emit()
			return
		if not Economy.pay(r.ingredients):
			queue.clear()
			queue_changed.emit()
			return
		current = next
		progress = 0.0
		duration = float(r.get("time", 2.0)) / maxf(station_for(r).speed * (1.0 + TechTree.mod("craft_speed_mult")), 0.1)
		AudioManager.play("ui/cloth" if r.get("station") == null else "survival/cook", -4.0)
		queue_changed.emit()
		return
	progress += delta / maxf(duration, 0.05)
	if progress >= 1.0:
		var r := GameData.recipe(current.recipe)
		var qty := int(r.get("qty", 1))
		var left := GameState.give(r.result, qty)
		if left > 0:
			left -= int(Economy.add_storage(r.result, left))
		if left > 0 and world:
			world.spawn_drop(r.result, left, world.player.global_position + world.player.forward_dir(), true, true)
		GameState.count_stat("crafted", r.result, qty)
		GameState.add_xp(int(GameData.b("progression.xp_craft", 3)))
		EventBus.item_crafted.emit(r.result, qty)
		AudioManager.play("ui/coins", -4.0)
		EventBus.floating_text.emit(world.player.global_position + Vector3.UP * 2.2, "+%d %s" % [qty, GameData.item_name(r.result)], Color(0.7, 1.0, 0.7))
		if world:
			world.effects.sparkle(world.player.global_position + Vector3.UP * 1.4, Color(1.0, 0.9, 0.5))
		crafted.emit(r.result, qty)
		current = {}
		progress = 0.0
		queue_changed.emit()


func is_busy() -> bool:
	return not current.is_empty() or not queue.is_empty()
