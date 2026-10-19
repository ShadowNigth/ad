extends Node
## Bus de eventos global. Desacopla sistemas (UI, misiones, audio, guardado)
## sin crear dependencias circulares entre scripts.

# Interfaz y notificaciones
signal toast(text: String, kind: String)
signal floating_text(world_pos: Vector3, text: String, color: Color)
signal open_panel(panel_name: String, data: Variant)
signal close_panels

# Inventario y almacén
signal inventory_changed
signal storage_changed
signal equipped_changed(item_id: String)
signal item_gathered(item_id: String, amount: int)
signal item_crafted(item_id: String, amount: int)
signal item_consumed(item_id: String)
signal water_collected(amount: int)

# Construcción y economía
signal building_placed(uid: int, type_id: String)
signal building_upgraded(uid: int, type_id: String, level: int)
signal building_removed(uid: int, type_id: String)
signal building_damaged(uid: int, hp: float)
signal building_repaired(uid: int)
signal production_cycle(uid: int, outputs: Dictionary)
signal build_mode_changed(active: bool)

# Progresión
signal xp_changed(xp: int, level: int)
signal level_up(level: int)
signal tech_points_changed(points: int)
signal tech_researched(tech_id: String)
signal age_changed(age: int)
signal quest_progress(quest_id: String, value: int, target: int)
signal quest_completed(quest_id: String)
signal worker_hired(type_id: String)
signal workers_changed
signal region_unlocked(region_id: String)

# Jugador y combate
signal player_stats_changed
signal player_damaged(amount: float, source: String)
signal player_died
signal player_respawned
signal player_ate(item_id: String)
signal enemy_killed(enemy_type: String, position: Vector3)
signal danger_nearby(active: bool)

# Tiempo
signal day_started(day: int)
signal night_started(day: int)
signal hour_changed(hour: int)

# Sistema
signal settings_changed
signal game_loaded
signal game_saved
signal offline_report(summary: Dictionary)


func notify(text: String, kind: String = "info") -> void:
	toast.emit(text, kind)
