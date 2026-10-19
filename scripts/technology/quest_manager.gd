extends Node
## Objetivos progresivos. Escucha EventBus y avanza la cadena de misiones.

var index: int = 0
var progress: int = 0
var completed: Array = []
var _check_pending := false
var active := false


func reset() -> void:
	index = 0
	progress = 0
	completed.clear()


func _ready() -> void:
	EventBus.item_gathered.connect(func(id, n): _on_event("gather", id, n))
	EventBus.item_crafted.connect(func(id, n): _on_event("craft", id, n))
	EventBus.player_ate.connect(func(id): _on_event("eat", id, 1))
	EventBus.enemy_killed.connect(func(t, _p): _on_event("kill", t, 1))
	EventBus.day_started.connect(func(_d): _on_event("survive_nights", "", 1))
	EventBus.water_collected.connect(func(n): _on_event("collect_water", "", n))
	for sig in [EventBus.building_placed, EventBus.building_upgraded, EventBus.tech_researched, EventBus.worker_hired,
			EventBus.region_unlocked, EventBus.age_changed, EventBus.inventory_changed, EventBus.storage_changed]:
		sig.connect(func(_a = null, _b = null, _c = null): _queue_check())


func current() -> Dictionary:
	if index < 0 or index >= GameData.quests.size():
		return {}
	return GameData.quests[index]


func is_finished() -> bool:
	return index >= GameData.quests.size()


func target_value() -> int:
	return int(current().get("qty", 1))


## Progreso actual (para la interfaz), incluido el de los tipos "de estado".
func current_value() -> int:
	var q := current()
	if q.is_empty():
		return 0
	match str(q.type):
		"have":
			return Economy.total_available(q.target)
		"build":
			return Economy.count_of(q.target)
		"upgrade":
			var best := 0
			for rec in Economy.buildings_of(q.target):
				best = maxi(best, int(rec.level))
			return best
		"research":
			return TechTree.researched.size()
		"hire":
			return Workers.hired.size()
		"unlock_region":
			return 1 if GameState.is_region_unlocked(q.target) else 0
		"reach_age":
			return TechTree.age()
		_:
			return progress


func _on_event(kind: String, id: String, amount: int) -> void:
	if not active:
		return
	var q := current()
	if q.is_empty() or str(q.type) != kind:
		return
	var target: String = q.get("target", "")
	if target != "" and target != id:
		return
	progress += amount
	EventBus.quest_progress.emit(q.id, current_value(), target_value())
	_queue_check()


func _queue_check() -> void:
	if _check_pending or not active:
		return
	_check_pending = true
	call_deferred("_check")


func _check() -> void:
	_check_pending = false
	var guard := 0
	while not is_finished() and current_value() >= target_value() and guard < 8:
		guard += 1
		_complete()


func _complete() -> void:
	var q := current()
	var reward: Dictionary = q.get("reward", {})
	if reward.has("points"):
		TechTree.add_points(int(reward.points))
	if reward.has("xp"):
		GameState.add_xp(int(reward.xp))
	for id in reward.get("items", {}):
		var left := GameState.give(id, int(reward.items[id]))
		if left > 0:
			Economy.add_storage(id, left)
	completed.append(q.id)
	index += 1
	progress = 0
	EventBus.quest_completed.emit(q.id)
	var next := current()
	if not next.is_empty():
		EventBus.quest_progress.emit(next.id, current_value(), target_value())


func reward_text(q: Dictionary) -> String:
	var parts: Array[String] = []
	var reward: Dictionary = q.get("reward", {})
	if reward.has("points"):
		parts.append("+%d PT" % int(reward.points))
	if reward.has("xp"):
		parts.append("+%d XP" % int(reward.xp))
	for id in reward.get("items", {}):
		parts.append("%d %s" % [int(reward.items[id]), GameData.item_name(id)])
	return ", ".join(parts)


func to_dict() -> Dictionary:
	return {"index": index, "progress": progress, "completed": completed.duplicate()}


func from_dict(d: Dictionary) -> void:
	index = clampi(int(d.get("index", 0)), 0, GameData.quests.size())
	progress = maxi(int(d.get("progress", 0)), 0)
	completed = d.get("completed", []).duplicate()
