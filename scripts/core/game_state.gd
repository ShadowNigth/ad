extends Node
## Estado persistente del jugador y del mundo (inventario, progreso, tiempo,
## regiones desbloqueadas, nodos agotados...). Lo guarda SaveManager.

var inventory: Inventory
var equipped_index: int = -1
var level: int = 1
var xp: int = 0
var stats: Dictionary = {}
var survival: Dictionary = {}
var player_pos: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var has_position: bool = false
var day: int = 1
var hour: float = 8.0
var regions: Dictionary = {}
var flags: Dictionary = {}
var depleted_nodes: Dictionary = {}
var guardians_defeated: Dictionary = {}
var lost_backpack: Dictionary = {}
var spawn_point: Vector3 = Vector3.ZERO
var playtime: float = 0.0
var session_active := false
## Clima actual y segundos que le quedan (lo gestiona Weather; se guarda).
var weather: Dictionary = {"state": "despejado", "left": 300.0}


func _ready() -> void:
	inventory = Inventory.new(int(GameData.b("player.inventory_slots", 24)))
	inventory.changed.connect(func(): EventBus.inventory_changed.emit())
	new_game()


func new_game() -> void:
	inventory.set_capacity(int(GameData.b("player.inventory_slots", 24)))
	inventory.clear()
	equipped_index = -1
	level = 1
	xp = 0
	stats = {"gathered": {}, "crafted": {}, "kills": {}, "built": 0, "nights": 0, "deaths": 0, "eaten": 0, "water": 0}
	survival = {"health": max_health(), "hunger": 80.0, "thirst": 80.0, "stamina": max_stamina()}
	has_position = false
	player_pos = Vector3.ZERO
	player_yaw = 0.0
	day = 1
	hour = float(GameData.b("day_night.start_hour", 8.0))
	regions.clear()
	flags.clear()
	depleted_nodes.clear()
	guardians_defeated.clear()
	lost_backpack = {}
	var sp: Array = GameData.world.get("spawn", [0.0, 0.0])
	spawn_point = Vector3(float(sp[0]), 0.0, float(sp[1]))
	playtime = 0.0
	weather = {"state": "despejado", "left": 300.0}


func now() -> float:
	return Time.get_unix_time_from_system()


func is_raining() -> bool:
	return str(weather.get("state", "")) in ["lluvia", "tormenta"]


## Multiplicador del gasto de sed según el clima (la lluvia la reduce).
func weather_thirst_mult() -> float:
	return GameData.bf("weather.rain_thirst_mult", 0.6) if is_raining() else 1.0


# ------------------------------------------------------------------ atributos
func max_health() -> float:
	return GameData.bf("survival.max_health", 100.0) + TechTree.mod("max_health")


func max_stamina() -> float:
	return GameData.bf("survival.max_stamina", 100.0) + TechTree.mod("max_stamina")


func apply_capacity_bonuses() -> void:
	if inventory:
		inventory.set_capacity(int(GameData.b("player.inventory_slots", 24)) + int(TechTree.mod("inventory_slots")))


# ------------------------------------------------------------------ experiencia
func xp_for_level(lv: int) -> int:
	var base := float(GameData.b("progression.xp_base", 30))
	var growth := float(GameData.b("progression.xp_growth", 1.3))
	return int(round(base * pow(growth, lv - 1)))


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var max_level := int(GameData.b("progression.max_level", 60))
	while level < max_level and xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1
		TechTree.add_points(int(GameData.b("progression.tech_points_per_level", 2)))
		EventBus.level_up.emit(level)
	EventBus.xp_changed.emit(xp, level)


func count_stat(category: String, key: String, amount: int = 1) -> void:
	if not stats.has(category) or typeof(stats[category]) != TYPE_DICTIONARY:
		stats[category] = {}
	stats[category][key] = int(stats[category].get(key, 0)) + amount


func add_stat(key: String, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


# ------------------------------------------------------------------ equipo
func equipped_item_id() -> String:
	if equipped_index < 0 or equipped_index >= inventory.slots.size():
		return ""
	var s: Variant = inventory.slots[equipped_index]
	return "" if s == null else str(s.id)


func equip(index: int) -> void:
	if index >= 0 and index < inventory.slots.size() and inventory.slots[index] != null:
		if GameData.is_equippable(inventory.slots[index].id):
			equipped_index = index
			EventBus.equipped_changed.emit(equipped_item_id())
			return
	equipped_index = -1
	EventBus.equipped_changed.emit("")


## Revisa que el arma equipada siga existiendo (p. ej. tras romperse).
func validate_equipped() -> void:
	if equipped_index >= 0 and equipped_item_id() == "":
		equipped_index = -1
		EventBus.equipped_changed.emit("")


func weapon_damage() -> float:
	var id := equipped_item_id()
	var base := float(GameData.b("player.fist_damage", 5))
	if id != "":
		base = float(GameData.item(id).get("weapon", {}).get("damage", base))
	return base * (1.0 + TechTree.mod("damage_mult"))


func weapon_reach() -> float:
	var id := equipped_item_id()
	var base := float(GameData.b("player.attack_range", 2.0))
	if id != "":
		base = float(GameData.item(id).get("weapon", {}).get("reach", base))
	return base


## Da objetos al jugador. Devuelve lo que no cupo en el inventario.
func give(id: String, qty: int) -> int:
	return inventory.add(id, qty)


# ------------------------------------------------------------------ regiones
func is_region_unlocked(region_id: String) -> bool:
	return region_id == "" or regions.has(region_id)


func unlock_region(region_id: String) -> void:
	if regions.has(region_id):
		return
	regions[region_id] = true
	EventBus.region_unlocked.emit(region_id)


# ------------------------------------------------------------------ guardado
func to_dict() -> Dictionary:
	return {
		"inventory": inventory.to_array(),
		"capacity": inventory.capacity,
		"equipped": equipped_index,
		"level": level, "xp": xp, "stats": stats,
		"survival": survival,
		"player_pos": [player_pos.x, player_pos.y, player_pos.z], "player_yaw": player_yaw, "has_position": has_position,
		"day": day, "hour": hour,
		"regions": regions.keys(), "flags": flags,
		"depleted_nodes": depleted_nodes,
		"guardians": guardians_defeated,
		"lost_backpack": lost_backpack,
		"spawn_point": [spawn_point.x, spawn_point.y, spawn_point.z],
		"playtime": playtime,
		"weather": weather,
	}


func from_dict(d: Dictionary) -> void:
	new_game()
	apply_capacity_bonuses()
	inventory.from_array(d.get("inventory", []))
	equipped_index = int(d.get("equipped", -1))
	level = clampi(int(d.get("level", 1)), 1, int(GameData.b("progression.max_level", 60)))
	xp = maxi(int(d.get("xp", 0)), 0)
	var st: Variant = d.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in st:
			stats[k] = st[k]
	var sv: Variant = d.get("survival", {})
	if typeof(sv) == TYPE_DICTIONARY:
		survival.health = clampf(float(sv.get("health", max_health())), 1.0, max_health())
		survival.hunger = clampf(float(sv.get("hunger", 80.0)), 0.0, 100.0)
		survival.thirst = clampf(float(sv.get("thirst", 80.0)), 0.0, 100.0)
		survival.stamina = clampf(float(sv.get("stamina", max_stamina())), 0.0, max_stamina())
	var p: Array = d.get("player_pos", [0, 0, 0])
	if p.size() == 3:
		player_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	player_yaw = float(d.get("player_yaw", 0.0))
	has_position = bool(d.get("has_position", false))
	day = maxi(int(d.get("day", 1)), 1)
	hour = fposmod(float(d.get("hour", 8.0)), 24.0)
	for r in d.get("regions", []):
		regions[str(r)] = true
	var fl: Variant = d.get("flags", {})
	if typeof(fl) == TYPE_DICTIONARY:
		flags = fl
	var dn: Variant = d.get("depleted_nodes", {})
	if typeof(dn) == TYPE_DICTIONARY:
		depleted_nodes = dn
	var gd: Variant = d.get("guardians", {})
	if typeof(gd) == TYPE_DICTIONARY:
		guardians_defeated = gd
	var lb: Variant = d.get("lost_backpack", {})
	if typeof(lb) == TYPE_DICTIONARY:
		lost_backpack = lb
	var spp: Array = d.get("spawn_point", [])
	if spp.size() == 3:
		spawn_point = Vector3(float(spp[0]), float(spp[1]), float(spp[2]))
	playtime = float(d.get("playtime", 0.0))
	var wt: Variant = d.get("weather", {})
	if typeof(wt) == TYPE_DICTIONARY and str(wt.get("state", "")) in ["despejado", "nublado", "lluvia", "tormenta"]:
		weather = {"state": str(wt.state), "left": clampf(float(wt.get("left", 300.0)), 1.0, 3600.0)}
	validate_equipped()
