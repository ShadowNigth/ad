class_name SurvivalStats
extends Node
## Salud, hambre, sed y estamina del jugador. Los valores viven en
## GameState.survival (fuente única para guardar). El desgaste es suave para
## no estropear la progresión incremental.

signal died

var resting := false
var sprinting := false
var _stamina_delay := 0.0
var _emit_timer := 0.0
var _warned := {}
var enabled := true


func s(key: String) -> float:
	return float(GameState.survival.get(key, 0.0))


func set_stat(key: String, value: float) -> void:
	GameState.survival[key] = value


func max_of(key: String) -> float:
	match key:
		"health":
			return GameState.max_health()
		"stamina":
			return GameState.max_stamina()
		"hunger":
			return GameData.bf("survival.max_hunger", 100.0)
		"thirst":
			return GameData.bf("survival.max_thirst", 100.0)
	return 100.0


func ratio(key: String) -> float:
	return clampf(s(key) / maxf(max_of(key), 1.0), 0.0, 1.0)


func _process(delta: float) -> void:
	if not enabled or s("health") <= 0.0:
		return
	var night_mult := GameData.bf("survival.night_drain_mult", 1.1) if _is_night() else 1.0
	var sprint_mult := GameData.bf("survival.sprint_drain_mult", 1.5) if sprinting else 1.0
	var hunger_rate := GameData.bf("survival.hunger_drain_per_min", 4.0) / 60.0 * night_mult * sprint_mult * (1.0 + TechTree.mod("hunger_drain_mult"))
	var thirst_rate := GameData.bf("survival.thirst_drain_per_min", 5.5) / 60.0 * night_mult * sprint_mult * (1.0 + TechTree.mod("thirst_drain_mult"))
	if resting:
		hunger_rate *= 0.5
		thirst_rate *= 0.5
	set_stat("hunger", clampf(s("hunger") - hunger_rate * delta, 0.0, max_of("hunger")))
	set_stat("thirst", clampf(s("thirst") - thirst_rate * delta, 0.0, max_of("thirst")))
	# Salud: se pierde lentamente si falta comida o agua, se recupera si estás bien alimentado.
	var hp := s("health")
	if s("hunger") <= 0.0 or s("thirst") <= 0.0:
		hp -= GameData.bf("survival.starving_damage_per_min", 18.0) / 60.0 * delta
	elif s("hunger") >= GameData.bf("survival.regen_min_food", 45.0) and s("thirst") >= GameData.bf("survival.regen_min_food", 45.0):
		var regen := GameData.bf("survival.rest_regen_per_min", 60.0) if resting else GameData.bf("survival.regen_per_min", 12.0)
		hp += regen / 60.0 * delta
	set_stat("health", clampf(hp, 0.0, max_of("health")))
	# Estamina.
	if sprinting:
		var cost := GameData.bf("survival.stamina_sprint_per_sec", 14.0) * (1.0 + TechTree.mod("sprint_stamina_mult"))
		spend_stamina(cost * delta)
	elif _stamina_delay > 0.0:
		_stamina_delay -= delta
	else:
		set_stat("stamina", minf(s("stamina") + GameData.bf("survival.stamina_regen_per_sec", 20.0) * delta, max_of("stamina")))
	_check_warnings()
	if s("health") <= 0.0:
		died.emit()
	_emit_timer -= delta
	if _emit_timer <= 0.0:
		_emit_timer = 0.2
		EventBus.player_stats_changed.emit()


func _is_night() -> bool:
	var h := GameState.hour
	return h >= GameData.bf("day_night.night_hour", 20.5) or h < GameData.bf("day_night.dawn_hour", 6.0)


func _check_warnings() -> void:
	for key in ["hunger", "thirst"]:
		var low := s(key) < 20.0
		if low and not _warned.get(key, false):
			_warned[key] = true
			EventBus.notify("Tienes mucha hambre: come algo." if key == "hunger" else "Tienes mucha sed: bebe agua.", "warn")
		elif s(key) > 30.0:
			_warned[key] = false


func spend_stamina(amount: float) -> bool:
	if s("stamina") < amount * 0.5:
		return false
	set_stat("stamina", maxf(s("stamina") - amount, 0.0))
	_stamina_delay = GameData.bf("survival.stamina_regen_delay", 0.9)
	return true


func has_stamina(amount: float) -> bool:
	return s("stamina") >= amount


func damage(amount: float) -> void:
	set_stat("health", clampf(s("health") - amount, 0.0, max_of("health")))
	EventBus.player_stats_changed.emit()
	if s("health") <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	set_stat("health", clampf(s("health") + amount * (1.0 + TechTree.mod("heal_mult")), 0.0, max_of("health")))
	EventBus.player_stats_changed.emit()


## Aplica los valores de comida/bebida de un objeto.
func consume(food: Dictionary) -> void:
	set_stat("hunger", clampf(s("hunger") + float(food.get("hunger", 0.0)), 0.0, max_of("hunger")))
	set_stat("thirst", clampf(s("thirst") + float(food.get("thirst", 0.0)), 0.0, max_of("thirst")))
	var hp := float(food.get("health", 0.0))
	if hp > 0.0:
		heal(hp)
	elif hp < 0.0:
		damage(-hp)
	EventBus.player_stats_changed.emit()


func refill_all() -> void:
	set_stat("health", max_of("health"))
	set_stat("stamina", max_of("stamina"))
	EventBus.player_stats_changed.emit()
