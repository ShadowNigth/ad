class_name Enemy
extends CharacterBody3D
## Criatura con IA de estados: deambular, detectar, perseguir, atacar con
## enfriamiento, huir, volver a casa. Esquiva obstáculos con rayos y
## detecta atascos. Los datos (vida, velocidad, daño...) vienen de JSON.

enum State { IDLE, WANDER, CHASE, ATTACK, FLEE, RETURN, BUILDING, DEAD }

var type_id := ""
var data: Dictionary = {}
var world: World
var rig: ProceduralRig
var hp := 10.0
var max_hp := 10.0
var state: int = State.IDLE
var home := Vector3.ZERO
var guardian_poi := ""
var _state_t := 0.0
var _wander_target := Vector3.ZERO
var _attack_cd := 0.0
var _attack_windup := -1.0
var _avoid_dir := Vector3.ZERO
var _avoid_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _knock := Vector3.ZERO
var _think_t := 0.0
var _target_building := -1
var _hp_bar: MeshInstance3D
var _hp_mat: ShaderMaterial
var _idle_sound_t := 0.0
var _gravity := 18.0
var _rng := RandomNumberGenerator.new()
var _aggro := false


func setup(w: World, t: String, pos: Vector3, poi_id: String = "") -> void:
	world = w
	type_id = t
	data = GameData.enemies.get(t, {})
	guardian_poi = poi_id
	max_hp = float(data.get("hp", 20))
	hp = max_hp
	home = pos
	position = pos
	_last_pos = pos
	_rng.randomize()
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 3) | (1 << 4) | (1 << 5)
	floor_max_angle = deg_to_rad(48.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = float(data.get("radius", 0.45))
	var tint := Color.WHITE
	if data.has("tint"):
		tint = Color(data.tint[0], data.tint[1], data.tint[2])
	rig = ProceduralRig.new()
	add_child(rig)
	rig.build(str(data.model), str(data.get("rig", "biped")), float(data.get("scale", 1.0)), tint)
	cap.height = maxf(rig.world_height() * 0.9, cap.radius * 2.0 + 0.1)
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	_hp_bar = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.1 if not data.get("boss", false) else 2.2, 0.14)
	_hp_bar.mesh = q
	_hp_mat = ShaderMaterial.new()
	_hp_mat.shader = load("res://assets/shaders/billboard_bar.gdshader")
	_hp_mat.set_shader_parameter("fill_color", Color(0.9, 0.22, 0.2))
	_hp_bar.material_override = _hp_mat
	_hp_bar.position.y = rig.world_height() + 0.45
	_hp_bar.visible = false
	_hp_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hp_bar)
	rig.walk_rate = 1.8
	rig.spawn_in()
	BlobShadow.attach(self, maxf(float(data.get("radius", 0.45)) * 1.5, 0.35) * (1.6 if is_boss() else 1.0), w, 0.42)
	if str(data.get("time", "")) == "night" and w.effects:
		w.effects.poof(pos + Vector3.UP * 0.6, Color(0.45, 0.3, 0.65), 12, 1.2, 1.1, 0.8)
	_pick_wander()
	add_to_group("enemies")


func is_alive() -> bool:
	return state != State.DEAD


func is_hostile() -> bool:
	return str(data.get("behavior", "")) in ["aggressive", "territorial", "guardian"]


func is_boss() -> bool:
	return bool(data.get("boss", false))


func _player() -> Player:
	return world.player


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= _gravity * delta
		move_and_slide()
		return
	_attack_cd -= delta
	_state_t += delta
	_think_t -= delta
	_idle_sound_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.2
		_think()
	var desired := Vector3.ZERO
	var speed := float(data.get("speed", 1.5))
	var p := _player()
	match state:
		State.WANDER:
			desired = _wander_target - global_position
			if Vector2(desired.x, desired.z).length() < 0.8:
				state = State.IDLE
				_state_t = 0.0
		State.CHASE:
			if p:
				desired = p.global_position - global_position
				speed = float(data.get("chase_speed", 3.0))
		State.FLEE:
			if p:
				desired = global_position - p.global_position
				speed = float(data.get("chase_speed", 4.0))
		State.RETURN:
			desired = home - global_position
			speed = float(data.get("chase_speed", 3.0)) * 0.8
		State.BUILDING:
			var brec := Economy.get_building(_target_building)
			if brec.is_empty():
				state = State.WANDER
			else:
				desired = Vector3(brec.pos[0], brec.pos[1], brec.pos[2]) - global_position
				speed = float(data.get("chase_speed", 3.0)) * 0.7
		State.ATTACK:
			if p:
				var to := p.global_position - global_position
				rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-to.x, -to.z), clampf(delta * 10.0, 0.0, 1.0))
	desired.y = 0.0
	var move := Vector3.ZERO
	if desired.length() > 0.05 and state != State.ATTACK and state != State.IDLE:
		move = _steer(desired.normalized()) * speed
	if _attack_windup >= 0.0:
		_attack_windup -= delta
		move *= 0.2
		if _attack_windup < 0.0:
			_resolve_attack()
	move += _knock
	_knock = _knock.move_toward(Vector3.ZERO, delta * 14.0)
	velocity.x = move_toward(velocity.x, move.x, 22.0 * delta)
	velocity.z = move_toward(velocity.z, move.z, 22.0 * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= _gravity * delta
	var ahead := global_position + Vector3(velocity.x, 0, velocity.z) * delta * 8.0
	if not _can_enter(ahead):
		velocity.x = 0.0
		velocity.z = 0.0
		if state == State.WANDER:
			_pick_wander()
	move_and_slide()
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.2:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-velocity.x, -velocity.z), clampf(delta * 9.0, 0.0, 1.0))
	rig.walk = clampf(hv.length() / 3.0, 0.0, 1.2)
	var ground: float = world.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 2.0:
		global_position.y = ground + 0.2
		velocity.y = 0.0


## Esquiva obstáculos con tres rayos (centro, izquierda, derecha).
func _steer(dir: Vector3) -> Vector3:
	if _avoid_t > 0.0:
		_avoid_t -= get_physics_process_delta_time()
		return (_avoid_dir * 0.75 + dir * 0.25).normalized()
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.6
	var look := 1.6 + float(data.get("radius", 0.45))
	var mask := (1 << 3) | (1 << 4) | (1 << 5)
	if _ray_hit(space, origin, origin + dir * look, mask):
		for ang in [0.8, -0.8, 1.5, -1.5, 2.3, -2.3]:
			var alt := dir.rotated(Vector3.UP, ang)
			if not _ray_hit(space, origin, origin + alt * look, mask) and _can_enter(global_position + alt * 1.5):
				_avoid_dir = alt
				_avoid_t = 0.6
				return alt
		return -dir
	return dir


func _ray_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()


func _can_enter(pos: Vector3) -> bool:
	if not world.is_walkable(pos, true):
		return false
	if data.get("avoid_light", false) and world.is_lit(pos, 0.5):
		return false
	return true


func _think() -> void:
	var p := _player()
	var behavior: String = data.get("behavior", "aggressive")
	var dist := INF
	if p and not p.dead:
		dist = global_position.distance_to(p.global_position)
	# Atascos: si no avanza mientras persigue, busca un desvío.
	if state in [State.CHASE, State.RETURN, State.BUILDING, State.WANDER]:
		if global_position.distance_to(_last_pos) < 0.08:
			_stuck_t += 0.2
			if _stuck_t > 1.2:
				_stuck_t = 0.0
				_avoid_dir = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
				_avoid_t = 0.9
				if state == State.WANDER:
					_pick_wander()
		else:
			_stuck_t = 0.0
	_last_pos = global_position
	var detect := float(data.get("detect", 10.0))
	var leash := float(data.get("leash", 25.0))
	if world.day_night.is_night() and data.get("time", "") == "night":
		detect *= 1.2
	if p and p.resting and world.is_lit(p.global_position, 0.0):
		detect *= 0.3
	var was_chasing := state in [State.CHASE, State.ATTACK]
	var was_fleeing := state == State.FLEE
	match behavior:
		"flee":
			if dist < detect or _aggro:
				if not was_fleeing:
					world.effects.alert_mark(self, rig.world_height(), "!", Color(1.0, 1.0, 1.0))
				state = State.FLEE
				if dist > detect * 2.5:
					_aggro = false
					state = State.WANDER
					_pick_wander()
			elif state == State.FLEE:
				state = State.WANDER
				_pick_wander()
			elif state == State.IDLE and _state_t > _rng.randf_range(2.0, 5.0):
				_pick_wander()
		"guardian":
			var from_home := global_position.distance_to(home)
			if dist < detect and p.global_position.distance_to(home) < leash:
				_set_chase_or_attack(dist)
			elif from_home > 2.0:
				state = State.RETURN
				hp = minf(hp + max_hp * 0.05, max_hp)
			else:
				state = State.IDLE
		_:
			var territorial := behavior == "territorial"
			var trigger := detect * (0.6 if territorial else 1.0)
			if dist < trigger or (_aggro and dist < leash):
				if data.get("avoid_light", false) and world.is_lit(p.global_position, 0.0):
					state = State.IDLE
				else:
					_set_chase_or_attack(dist)
			elif state in [State.CHASE, State.ATTACK]:
				_aggro = false
				state = State.WANDER
				_pick_wander()
				world.effects.alert_mark(self, rig.world_height(), "?", Color(0.85, 0.85, 0.9))
			elif state == State.IDLE and _state_t > _rng.randf_range(1.5, 4.0):
				# De noche, algunas criaturas atacan edificios si no hay nadie cerca.
				if data.get("building_damage", 0) > 0 and world.day_night.is_night() and _rng.randf() < GameData.bf("night.building_attack_chance", 0.35):
					var uid: int = world.buildings.nearest(global_position, 14.0)
					if uid >= 0 and not world.is_lit(global_position, 0.0):
						_target_building = uid
						state = State.BUILDING
						return
				_pick_wander()
			elif state == State.BUILDING:
				var brec := Economy.get_building(_target_building)
				if brec.is_empty() or float(brec.hp) <= 0.0:
					state = State.WANDER
					_pick_wander()
				else:
					var bpos := Vector3(brec.pos[0], brec.pos[1], brec.pos[2])
					var fp := float(GameData.building(brec.type).get("footprint", 1.5))
					if global_position.distance_to(bpos) < fp + 1.4 and _attack_cd <= 0.0:
						_attack_cd = float(data.get("attack_cooldown", 1.5)) * 1.5
						rig.play_action("lunge")
						Economy.damage_building(_target_building, float(data.get("building_damage", 5)))
	if not was_chasing and state in [State.CHASE, State.ATTACK]:
		world.effects.alert_mark(self, rig.world_height(), "!", Color(1.0, 0.35, 0.2) if is_hostile() else Color(1.0, 0.85, 0.3))
		if data.get("sounds", {}).has("idle"):
			AudioManager.play_at(str(data.sounds.idle), global_position, -3.0)
	if _idle_sound_t <= 0.0 and dist < 22.0 and data.get("sounds", {}).has("idle"):
		_idle_sound_t = _rng.randf_range(5.0, 11.0)
		AudioManager.play_at(str(data.sounds.idle), global_position, -6.0)


func _set_chase_or_attack(dist: float) -> void:
	var reach := float(data.get("attack_range", 1.4)) + float(data.get("radius", 0.4))
	if float(data.get("damage", 0)) <= 0.0:
		state = State.FLEE
		return
	if dist <= reach:
		state = State.ATTACK
		if _attack_cd <= 0.0 and _attack_windup < 0.0:
			# Amago visible (se echa atrás y parpadea en naranja) antes de golpear.
			var windup := float(data.get("windup", GameData.bf("combat.enemy_windup", 0.45)))
			_attack_windup = windup
			_attack_cd = float(data.get("attack_cooldown", 1.4))
			rig.play_action("windup", windup)
			rig.telegraph(windup)
			if data.get("sounds", {}).has("attack"):
				AudioManager.play_at(str(data.sounds.attack), global_position, -2.0)
	else:
		if state != State.CHASE:
			_aggro = true
		state = State.CHASE


func _resolve_attack() -> void:
	var p := _player()
	rig.play_action("lunge")
	if p == null or p.dead:
		return
	var to := p.global_position - global_position
	to.y = 0.0
	if to.length() > 0.05:
		_knock = to.normalized() * GameData.bf("combat.lunge_speed", 4.0)
	var reach := float(data.get("attack_range", 1.4)) + float(data.get("radius", 0.4)) + 0.5
	if global_position.distance_to(p.global_position) <= reach:
		p.take_damage(float(data.get("damage", 5)), global_position, type_id)


func _pick_wander() -> void:
	var r: float = 8.0 if data.get("behavior", "") != "guardian" else 3.0
	for i in 6:
		var t := home + Vector3(_rng.randf_range(-r, r), 0, _rng.randf_range(-r, r))
		t.y = world.height_at(t.x, t.z)
		if _can_enter(t):
			_wander_target = t
			state = State.WANDER
			_state_t = 0.0
			return
	state = State.IDLE
	_state_t = 0.0


func take_damage(amount: float, from_pos: Vector3) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	rig.flash()
	rig.freeze(GameData.bf("combat.hit_freeze", 0.07))
	_aggro = true
	# Golpearle durante el amago le interrumpe (salvo a los guardianes).
	if _attack_windup >= 0.0 and not is_boss() and hp > 0.0:
		_attack_windup = -1.0
		rig.telegraph(0.0)
		rig.play_action("flinch")
	elif hp > 0.0 and not rig.is_acting():
		rig.play_action("flinch")
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() > 0.01:
		_knock = away.normalized() * (5.0 if not is_boss() else 1.5)
	_hp_bar.visible = true
	_hp_mat.set_shader_parameter("progress", clampf(hp / max_hp, 0.0, 1.0))
	EventBus.floating_text.emit(global_position + Vector3.UP * (rig.world_height() + 0.6), str(int(round(amount))), Color(1.0, 0.85, 0.3))
	world.effects.impact(global_position + Vector3.UP * rig.world_height() * 0.55)
	var snd: String = data.get("sounds", {}).get("hurt", "combat/soft_hit")
	AudioManager.play_at(snd, global_position)
	AudioManager.play_at("combat/hit_flesh", global_position, -6.0)
	if hp <= 0.0:
		_die()
	elif data.get("behavior", "") == "flee":
		state = State.FLEE
	elif data.get("behavior", "") == "territorial":
		state = State.CHASE


func _die() -> void:
	state = State.DEAD
	hp = 0.0
	_hp_bar.visible = false
	rig.die()
	collision_layer = 0
	var snd: String = data.get("sounds", {}).get("death", "combat/body_fall")
	AudioManager.play_at(snd, global_position)
	for d in data.get("drops", []):
		if _rng.randf() <= float(d.get("chance", 1.0)):
			var q := _rng.randi_range(int(d.get("min", 1)), int(d.get("max", 1)))
			if q > 0:
				world.spawn_drop(str(d.item), q, global_position + Vector3(_rng.randf_range(-0.6, 0.6), 0.2, _rng.randf_range(-0.6, 0.6)))
	GameState.add_xp(int(data.get("xp", 5)))
	GameState.count_stat("kills", type_id)
	EventBus.enemy_killed.emit(type_id, global_position)
	if guardian_poi != "":
		GameState.guardians_defeated[type_id] = GameState.now() + float(data.get("respawn", 1800.0))
		EventBus.notify("¡Has derrotado a %s!" % data.get("name", type_id), "good")
		AudioManager.play("events/stinger_victory", -3.0)
	var fx: WorldEffects = world.effects
	var at := global_position
	get_tree().create_timer(0.45).timeout.connect(func():
		if is_instance_valid(fx):
			fx.poof(at + Vector3.UP * 0.3, Color(0.85, 0.82, 0.76), 10, 1.0 + rig.world_height() * 0.3, 1.0, 0.5))
	var tw := create_tween()
	tw.tween_interval(1.15)
	tw.tween_property(rig, "scale", Vector3.ONE * 0.05, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(queue_free)


## Desaparece con un destello (al amanecer para las criaturas nocturnas).
func vanish() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	collision_layer = 0
	world.effects.burst(global_position + Vector3.UP, Color(0.7, 0.5, 1.0), 12, 2.5, 0.8, 0.8, -1.0)
	world.effects.poof(global_position + Vector3.UP * 0.6, Color(0.6, 0.45, 0.85), 12, 1.2, 1.2, 0.8)
	var tw := create_tween()
	tw.tween_property(rig, "scale", Vector3.ONE * 0.01, 0.6)
	tw.tween_callback(queue_free)
