class_name EnemySpawner
extends Node3D
## Genera fauna y criaturas alrededor del jugador según zona y hora.
## No simula nada lejos: lo que se aleja demasiado desaparece.

const SPAWN_MIN := 22.0
const SPAWN_MAX := 52.0
const DESPAWN := 85.0
const MAX_TOTAL := 14

var world: World
var _timer := 1.5
var _rng := RandomNumberGenerator.new()
var _guardians: Dictionary = {}
var _danger := false


func setup(w: World) -> void:
	world = w
	_rng.randomize()
	EventBus.day_started.connect(_on_dawn)
	_spawn_guardians()


func enemies() -> Array:
	return get_children().filter(func(e): return e is Enemy and e.is_alive())


func _spawn_guardians() -> void:
	for g in world.pois.guardian_spawns():
		var t: String = g.enemy
		if _guardians.has(t) and is_instance_valid(_guardians[t]):
			continue
		if GameState.now() < float(GameState.guardians_defeated.get(t, 0.0)):
			continue
		var e := _spawn(t, g.pos + Vector3(0, 0.3, 0), g.poi)
		_guardians[t] = e


func _spawn(t: String, pos: Vector3, poi: String = "") -> Enemy:
	var e := Enemy.new()
	add_child(e)
	e.setup(world, t, pos, poi)
	return e


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 2.5
	var player: Player = world.player
	if player == null:
		return
	var ppos := player.global_position
	# Retira criaturas lejanas (salvo guardianes) para no simular a distancia.
	var counts := {}
	var chasing := false
	for e in enemies():
		var d: float = e.global_position.distance_to(ppos)
		if d > DESPAWN and e.guardian_poi == "":
			e.queue_free()
			continue
		counts[e.type_id] = int(counts.get(e.type_id, 0)) + 1
		if e.is_hostile() and e.state in [Enemy.State.CHASE, Enemy.State.ATTACK] and d < 25.0:
			chasing = true
	if chasing != _danger:
		_danger = chasing
		EventBus.danger_nearby.emit(chasing)
	_spawn_guardians()
	if player.dead:
		return
	var total := enemies().size()
	var night: bool = world.day_night.is_night()
	for rule in GameData.world.get("spawns", []):
		if total >= MAX_TOTAL:
			break
		var t: String = rule.time
		if (t == "night" and not night) or (t == "day" and night):
			continue
		if int(counts.get(rule.enemy, 0)) >= int(rule.max):
			continue
		if _rng.randf() > 0.6:
			continue
		var pos: Variant = _find_spawn_point(ppos, rule.zones, GameData.enemies.get(rule.enemy, {}))
		if pos == null:
			continue
		_spawn(rule.enemy, pos)
		counts[rule.enemy] = int(counts.get(rule.enemy, 0)) + 1
		total += 1


func _find_spawn_point(ppos: Vector3, zones: Array, edata: Dictionary) -> Variant:
	var gen: IslandGenerator = world.gen
	for i in 10:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var x := ppos.x + cos(ang) * d
		var z := ppos.z + sin(ang) * d
		if not gen.in_bounds(x, z):
			continue
		if not zones.has(gen.zone_at(x, z)):
			continue
		var p := Vector3(x, gen.height_at(x, z), z)
		if not world.is_walkable(p, true) or gen.slope_deg(x, z) > 30.0:
			continue
		var region := gen.region_at(x, z)
		if region != "" and not GameState.is_region_unlocked(region):
			continue
		if edata.get("avoid_light", false) and world.is_lit(p, 6.0):
			continue
		if world.buildings.blocks(p, 2.0):
			continue
		return p + Vector3.UP * 0.3
	return null


func _on_dawn(_day: int) -> void:
	for e in enemies():
		if e.data.get("time", "") == "night":
			e.vanish()


func nearest(pos: Vector3, radius: float) -> Enemy:
	var best: Enemy = null
	var best_d := radius
	for e in enemies():
		var d: float = e.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = e
	return best


func in_arc(origin: Vector3, dir: Vector3, reach: float, arc_deg: float) -> Array:
	var out: Array = []
	var cos_half := cos(deg_to_rad(arc_deg * 0.5))
	for e in enemies():
		var to: Vector3 = e.global_position - origin
		to.y = 0.0
		var r := float(e.data.get("radius", 0.4))
		var d := to.length()
		if d > reach + r:
			continue
		if d < 0.6 or to.normalized().dot(dir) >= cos_half:
			out.append(e)
	return out


func active_boss() -> Enemy:
	var p: Player = world.player
	for e in enemies():
		if e.is_boss() and p and e.global_position.distance_to(p.global_position) < 22.0 and e.state in [Enemy.State.CHASE, Enemy.State.ATTACK]:
			return e
	return null
