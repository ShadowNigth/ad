class_name Player
extends CharacterBody3D
## Jugador en tercera persona: movimiento con joystick/teclado, cámara por
## arrastre, recolección contextual, combate cuerpo a cuerpo, esquiva y muerte.

signal target_changed(info: Dictionary)

const MODEL := "characters/character-male-a"
const MODEL_SCALE := 2.6

@onready var rig: ProceduralRig = $Rig
@onready var cam_rig: Node3D = $CameraRig
@onready var spring: SpringArm3D = $CameraRig/SpringArm3D
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var survival: SurvivalStats = $SurvivalStats

var world: World = null
var move_input := Vector2.ZERO
var touch_move := Vector2.ZERO
var touch_sprint := false
var yaw := 0.0
var pitch := -0.38
var cam_distance := 6.5
var dead := false
var resting := false
var target: Dictionary = {}
var interact_held := false
var _gather_cd := 0.0
var _attack_cd := 0.0
var _iframes := 0.0
var _dodge_t := 0.0
var _dodge_dir := Vector3.ZERO
var _target_timer := 0.0
var _step_accum := 0.0
var _shake := 0.0
var _tool_mesh: MeshInstance3D
var _tool_show_t := 0.0
var _tool_shown_id := ""
var _knockback := Vector3.ZERO
var _last_safe_pos := Vector3.ZERO
var _water_tick := 0.0
var _gravity := 18.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("saveable")
	_gravity = GameData.bf("player.gravity", 18.0)
	rig.build(MODEL, "biped", MODEL_SCALE)
	_tool_mesh = MeshInstance3D.new()
	_tool_mesh.visible = false
	if rig.hand_socket:
		rig.hand_socket.add_child(_tool_mesh)
	cam_rig.top_level = true
	survival.died.connect(_on_died)
	EventBus.equipped_changed.connect(func(_id): _refresh_tool())
	EventBus.settings_changed.connect(_apply_settings)
	_apply_settings()
	_last_safe_pos = global_position


func _apply_settings() -> void:
	cam_distance = float(Settings.get_value("camera_distance"))
	if is_instance_valid(spring):
		spring.spring_length = cam_distance
	if is_instance_valid(camera):
		camera.far = float(Settings.quality().view_distance) + 40.0


# ------------------------------------------------------------------ entrada
func set_touch_move(v: Vector2, sprint: bool) -> void:
	touch_move = v
	touch_sprint = sprint


func add_look(delta_px: Vector2) -> void:
	var sens := 0.0045 * float(Settings.get_value("sensitivity"))
	yaw -= delta_px.x * sens
	var inv := -1.0 if bool(Settings.get_value("invert_y")) else 1.0
	pitch = clampf(pitch - delta_px.y * sens * inv, -1.15, 0.35)


func zoom(amount: float) -> void:
	cam_distance = clampf(cam_distance + amount, 3.5, 11.0)
	spring.spring_length = cam_distance


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(0.6)
	if event.is_action_pressed("jump"):
		jump()
	elif event.is_action_pressed("attack"):
		attack()
	elif event.is_action_pressed("dodge"):
		dodge()
	elif event.is_action_pressed("interact"):
		interact_held = true
		interact_pressed()
	elif event.is_action_released("interact"):
		interact_held = false
	elif event.is_action_pressed("eat_quick"):
		quick_eat()


func _keyboard_move() -> Vector2:
	var v := Vector2(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	return v.limit_length(1.0)


# ------------------------------------------------------------------ física
func _physics_process(delta: float) -> void:
	if world == null:
		return
	_gather_cd -= delta
	_attack_cd -= delta
	_iframes -= delta
	_tool_show_t -= delta
	if dead:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= _gravity * delta
		move_and_slide()
		return
	var kb := _keyboard_move()
	move_input = kb if kb.length() > 0.05 else touch_move
	var sprint := (Input.is_action_pressed("sprint") or touch_sprint) and move_input.length() > 0.6
	if resting and move_input.length() > 0.1:
		set_resting(false)
	var basis_yaw := Basis(Vector3.UP, yaw)
	var dir := basis_yaw * Vector3(move_input.x, 0.0, move_input.y)
	var speed := GameData.bf("player.walk_speed", 4.6) * (1.0 + TechTree.mod("move_speed_mult"))
	if sprint and survival.has_stamina(5.0):
		speed = GameData.bf("player.sprint_speed", 7.2) * (1.0 + TechTree.mod("move_speed_mult"))
		survival.sprinting = true
	else:
		survival.sprinting = false
	var in_water := world.water_depth_at(global_position) > 0.35
	if in_water:
		speed *= 0.6
	var target_vel := dir * speed
	if _dodge_t > 0.0:
		_dodge_t -= delta
		target_vel = _dodge_dir * GameData.bf("player.dodge_speed", 11.0)
	target_vel += _knockback
	_knockback = _knockback.move_toward(Vector3.ZERO, delta * 18.0)
	var accel := 14.0 if is_on_floor() else 5.0
	velocity.x = move_toward(velocity.x, target_vel.x, accel * speed * delta + 0.5)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * speed * delta + 0.5)
	# Agua profunda o regiones bloqueadas: no se puede avanzar.
	var ahead := global_position + Vector3(velocity.x, 0.0, velocity.z) * delta * 6.0
	if not world.is_walkable(ahead):
		var slide_x := Vector3(velocity.x, 0.0, 0.0)
		var slide_z := Vector3(0.0, 0.0, velocity.z)
		if world.is_walkable(global_position + slide_x * delta * 6.0):
			velocity.z = 0.0
		elif world.is_walkable(global_position + slide_z * delta * 6.0):
			velocity.x = 0.0
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -0.5
	move_and_slide()
	# Seguridad: si caes por debajo del terreno, vuelve a la última posición segura.
	var ground: float = world.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 3.0 or global_position.y < -12.0:
		global_position = _last_safe_pos + Vector3.UP
		velocity = Vector3.ZERO
	elif is_on_floor() and world.is_walkable(global_position):
		_last_safe_pos = global_position
	# Orientación del modelo.
	var hvel := Vector2(velocity.x, velocity.z)
	if hvel.length() > 0.3 and _dodge_t <= 0.0:
		var face := atan2(-velocity.x, -velocity.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, face, clampf(delta * 12.0, 0.0, 1.0))
	elif target.has("pos") and interact_held:
		_face_point(target.pos, delta)
	rig.walk = clampf(hvel.length() / 5.0, 0.0, 1.3)
	rig.walk_rate = 1.5 + hvel.length() * 0.12
	_footsteps(hvel.length() * delta)
	if in_water:
		_water_tick -= delta
		if _water_tick <= 0.0 and hvel.length() > 1.0:
			_water_tick = 0.45
			AudioManager.play_at("footsteps/water", global_position, -6.0)


func _process(delta: float) -> void:
	if world == null:
		return
	# Cámara en tercera persona.
	var focus := global_position + Vector3(0.0, 1.55, 0.0)
	cam_rig.global_position = cam_rig.global_position.lerp(focus, clampf(delta * 14.0, 0.0, 1.0))
	cam_rig.rotation = Vector3(pitch, yaw, 0.0)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 2.5, 0.0)
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	_target_timer -= delta
	if _target_timer <= 0.0:
		_target_timer = 0.12
		_update_target()
	if interact_held and not dead and target.get("kind", "") == "node" and _gather_cd <= 0.0:
		interact_pressed()
	if _tool_show_t <= 0.0 and _tool_shown_id != GameState.equipped_item_id():
		_refresh_tool()


func _face_point(p: Vector3, delta: float) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-d.x, -d.z), clampf(delta * 14.0, 0.0, 1.0))


func forward_dir() -> Vector3:
	return Vector3(-sin(rig.rotation.y), 0.0, -cos(rig.rotation.y))


func _footsteps(dist: float) -> void:
	if not is_on_floor():
		return
	_step_accum += dist
	if _step_accum >= 1.7:
		_step_accum = 0.0
		var surf: String = world.surface_at(global_position)
		var key: String = {"sand": "footsteps/sand", "stone": "footsteps/stone", "dirt": "footsteps/dirt", "wood": "footsteps/wood", "water": "footsteps/water"}.get(surf, "footsteps/grass")
		AudioManager.play_at(key, global_position, -9.0, 0.12)


# ------------------------------------------------------------------ acciones
func jump() -> void:
	if dead or not is_on_floor():
		return
	if not survival.spend_stamina(GameData.bf("survival.stamina_jump", 6.0)):
		return
	velocity.y = GameData.bf("player.jump_velocity", 6.2)
	AudioManager.play_at("combat/woosh", global_position, -14.0)


func dodge() -> void:
	if dead or _dodge_t > 0.0:
		return
	if not survival.spend_stamina(GameData.bf("survival.stamina_dodge", 18.0)):
		EventBus.notify("Sin estamina", "warn")
		return
	var d := Basis(Vector3.UP, yaw) * Vector3(move_input.x, 0.0, move_input.y)
	if d.length() < 0.2:
		d = -forward_dir()
	_dodge_dir = d.normalized()
	_dodge_t = GameData.bf("player.dodge_time", 0.32)
	_iframes = maxf(_iframes, GameData.bf("player.iframes_dodge", 0.36))
	rig.rotation.y = atan2(-_dodge_dir.x, -_dodge_dir.z)
	AudioManager.play_at("combat/woosh", global_position, -4.0)


func attack() -> void:
	if dead or _attack_cd > 0.0 or resting:
		return
	if not survival.spend_stamina(GameData.bf("survival.stamina_attack", 8.0)):
		return
	_attack_cd = GameData.bf("player.attack_cooldown", 0.55)
	var weapon_id := GameState.equipped_item_id()
	if weapon_id == "":
		var best := GameState.inventory.best_weapon()
		if best >= 0:
			GameState.equip(best)
			weapon_id = GameState.equipped_item_id()
	_show_tool(weapon_id, 0.6)
	# Gira hacia el enemigo más cercano en el frente.
	var reach := GameState.weapon_reach()
	var enemy: Node3D = world.nearest_enemy(global_position, reach + 1.5)
	if enemy:
		var d := enemy.global_position - global_position
		rig.rotation.y = atan2(-d.x, -d.z)
	rig.play_attack()
	AudioManager.play_at("combat/swing", global_position, -3.0)
	await get_tree().create_timer(0.16).timeout
	if dead:
		return
	var hits: Array = world.enemies_in_arc(global_position, forward_dir(), reach + 0.4, GameData.bf("player.attack_arc_deg", 110.0))
	var dmg := GameState.weapon_damage()
	for e in hits:
		e.take_damage(dmg, global_position)
	if not hits.is_empty() and GameState.equipped_index >= 0:
		if GameState.inventory.wear(GameState.equipped_index, 1):
			EventBus.notify("¡Tu %s se ha roto!" % GameData.item_name(weapon_id), "bad")
			GameState.validate_equipped()
	if not hits.is_empty():
		_shake = maxf(_shake, 0.25)


func interact_pressed() -> void:
	if dead:
		return
	_update_target()
	match str(target.get("kind", "")):
		"node":
			_gather(int(target.id))
		"building":
			EventBus.open_panel.emit("building", int(target.uid))
			interact_held = false
		"poi":
			world.interact_poi(str(target.id))
			interact_held = false
		"water":
			_use_water()
			interact_held = false
		"backpack":
			world.recover_backpack()
			interact_held = false
		_:
			interact_held = false


func _gather(node_id: int) -> void:
	if _gather_cd > 0.0:
		return
	var rec: Dictionary = world.resources.get_node_rec(node_id)
	if rec.is_empty():
		return
	var nd: Dictionary = world.resources.node_data(rec)
	_gather_cd = GameData.bf("player.gather_interval", 0.62)
	survival.spend_stamina(GameData.bf("survival.stamina_gather", 2.0))
	var tool_type: Variant = nd.get("tool")
	var slot := -1
	var power := 1
	var tier := 0
	var tool_id := ""
	if tool_type != null:
		slot = GameState.inventory.best_tool(str(tool_type))
		if slot >= 0:
			tool_id = GameState.inventory.slots[slot].id
			var t: Dictionary = GameData.item(tool_id).tool
			power = int(t.get("power", 1))
			tier = int(t.get("tier", 1))
	_face_point(rec.pos, 1.0)
	rig.play_attack()
	_show_tool(tool_id, 0.8)
	var res: Dictionary = world.resources.hit(node_id, str(tool_type) if tool_id != "" else "", power, tier, global_position)
	if not res.ok:
		if res.reason != "":
			EventBus.notify(res.reason, "warn")
			AudioManager.play_ui("ui/error")
		interact_held = false
		return
	AudioManager.play_at(str(nd.get("sound", "gather/pickup")), rec.pos + Vector3.UP, -2.0)
	world.spawn_hit_effect(rec.pos + Vector3(0, minf(float(nd.get("height", 1.0)) * 0.4, 1.4), 0), str(rec.type))
	if res.depleted and nd.has("break_sound"):
		AudioManager.play_at(str(nd.break_sound), rec.pos, 0.0)
	if slot >= 0 and tool_id != "":
		if GameState.inventory.wear(slot, 1):
			EventBus.notify("¡Tu %s se ha roto!" % GameData.item_name(tool_id), "bad")
			GameState.validate_equipped()
	var text_parts: Array[String] = []
	for item_id in res.items:
		var q := int(res.items[item_id])
		var left := GameState.give(item_id, q)
		var got := q - left
		if got > 0:
			text_parts.append("+%d %s" % [got, GameData.item_name(item_id)])
			GameState.count_stat("gathered", item_id, got)
			EventBus.item_gathered.emit(item_id, got)
		if left > 0:
			world.spawn_drop(item_id, left, global_position + forward_dir() * 0.8)
			EventBus.notify("Inventario lleno: deposita recursos en el almacén.", "warn")
	if not text_parts.is_empty():
		EventBus.floating_text.emit(rec.pos + Vector3(0, 1.8, 0), "  ".join(text_parts), Color(1, 0.95, 0.6))
	GameState.add_xp(int(nd.get("xp", GameData.b("progression.xp_gather", 2))))
	if res.depleted:
		interact_held = false
		_update_target()


func _use_water() -> void:
	var inv := GameState.inventory
	var container_cap := 0
	for s in inv.slots:
		if s != null and GameData.is_container(s.id):
			container_cap = maxi(container_cap, int(GameData.item(s.id).container.get("capacity", 1)))
	if container_cap > 0 and inv.space_for("agua_sucia") > 0:
		var got := container_cap - inv.add("agua_sucia", container_cap)
		if got > 0:
			AudioManager.play_at("survival/water_fill", global_position)
			EventBus.floating_text.emit(global_position + Vector3.UP * 2.0, "+%d Agua sin tratar" % got, Color(0.6, 0.85, 1.0))
			EventBus.water_collected.emit(got)
			GameState.add_stat("water", got)
			EventBus.notify("Hierve el agua en una fogata para hacerla potable.", "info")
			return
	# Sin recipiente: beber directamente (poca agua y riesgo de enfermar).
	survival.consume({"thirst": 12.0})
	AudioManager.play_at("survival/drink", global_position)
	if randf() < GameData.bf("survival.dirty_water_sick_chance", 0.45) * 0.6:
		survival.damage(5.0)
		EventBus.notify("El agua sin tratar te sienta mal. Fabrica un cuenco de coco y hiérvela.", "warn")


## Come o bebe el objeto del hueco indicado.
func eat_slot(index: int) -> bool:
	var inv := GameState.inventory
	if index < 0 or index >= inv.slots.size() or inv.slots[index] == null:
		return false
	var id: String = inv.slots[index].id
	var it := GameData.item(id)
	if not it.has("food"):
		return false
	inv.remove_at(index, 1)
	var food: Dictionary = it.food.duplicate()
	if it.get("risky", false) and randf() < GameData.bf("survival.dirty_water_sick_chance", 0.45):
		food["health"] = float(food.get("health", 0.0)) - 8.0
		EventBus.notify("Te sientes mal... deberías haber hervido el agua.", "warn")
	survival.consume(food)
	var is_drink := float(it.food.get("thirst", 0)) > float(it.food.get("hunger", 0))
	AudioManager.play_at("survival/drink" if is_drink else "survival/eat", global_position)
	if float(it.food.get("health", 0)) > 10.0:
		AudioManager.play("survival/heal", -6.0)
	EventBus.item_consumed.emit(id)
	EventBus.player_ate.emit(id)
	GameState.add_stat("eaten")
	return true


## Come automáticamente lo más adecuado del inventario (botón rápido).
func quick_eat() -> void:
	var inv := GameState.inventory
	var need_thirst := survival.s("thirst") < survival.s("hunger")
	var best := -1
	var best_score := -INF
	for i in inv.slots.size():
		var s: Variant = inv.slots[i]
		if s == null or not GameData.is_consumable(s.id):
			continue
		var f: Dictionary = GameData.item(s.id).food
		var score := float(f.get("thirst", 0)) * (2.0 if need_thirst else 1.0) + float(f.get("hunger", 0)) * (1.0 if need_thirst else 2.0) + float(f.get("health", 0))
		if GameData.item(s.id).get("risky", false):
			score -= 20.0
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		EventBus.notify("No llevas comida ni bebida.", "warn")
		return
	eat_slot(best)


# ------------------------------------------------------------------ objetivo
func _update_target() -> void:
	var info := _find_target()
	var changed: bool = info.get("kind", "") != target.get("kind", "") or info.get("id", -9) != target.get("id", -9) or info.get("uid", -9) != target.get("uid", -9)
	target = info
	if changed:
		target_changed.emit(info)


func _find_target() -> Dictionary:
	var pos := global_position
	var fwd := forward_dir()
	var probe := pos + fwd * 0.8
	var reach := GameData.bf("player.interact_range", 2.6)
	# Mochila perdida.
	if world.backpack_near(pos, 2.5):
		return {"kind": "backpack", "label": "Recuperar mochila", "icon": "icon_hand", "pos": pos}
	# Puntos de interés (cofres, puente, derrumbe...).
	var poi: Dictionary = world.poi_near(pos, 3.2)
	if not poi.is_empty():
		return {"kind": "poi", "id": poi.id, "label": world.poi_label(poi), "icon": "icon_hand", "pos": poi.world_pos}
	# Recursos (prioriza lo que hay delante).
	var node_id: int = world.resources.nearest_available(probe, reach)
	var node_label := ""
	if node_id >= 0:
		var rec: Dictionary = world.resources.get_node_rec(node_id)
		node_label = "%s %s" % [world.resources.node_data(rec).get("label", "Recoger"), world.resources.node_data(rec).get("name", "").to_lower()]
	# Edificios.
	var uid: int = world.building_near(probe, reach + 0.6)
	if uid >= 0 and node_id < 0:
		var rec2 := Economy.get_building(uid)
		return {"kind": "building", "uid": uid, "label": GameData.building(rec2.type).name, "icon": "icon_wrench", "pos": Vector3(rec2.pos[0], rec2.pos[1], rec2.pos[2])}
	if node_id >= 0:
		var rec3: Dictionary = world.resources.get_node_rec(node_id)
		var tool: Variant = world.resources.node_data(rec3).get("tool")
		var icon := "icon_hand"
		if tool == "axe":
			icon = "icon_sword"
		elif tool == "pickaxe":
			icon = "icon_burst"
		return {"kind": "node", "id": node_id, "label": node_label, "icon": icon, "pos": rec3.pos}
	if uid >= 0:
		var rec4 := Economy.get_building(uid)
		return {"kind": "building", "uid": uid, "label": GameData.building(rec4.type).name, "icon": "icon_wrench", "pos": Vector3(rec4.pos[0], rec4.pos[1], rec4.pos[2])}
	# Agua dulce delante.
	for d: float in [1.2, 2.0, 2.8]:
		var wp := pos + fwd * d
		if world.is_fresh_water(wp):
			var has_container := false
			for s in GameState.inventory.slots:
				if s != null and GameData.is_container(s.id):
					has_container = true
					break
			return {"kind": "water", "label": "Recoger agua" if has_container else "Beber agua", "icon": "icon_hand", "pos": wp}
	return {}


# ------------------------------------------------------------------ herramienta en mano
func _show_tool(item_id: String, seconds: float) -> void:
	_tool_show_t = seconds
	_set_tool_mesh(item_id)


func _refresh_tool() -> void:
	_set_tool_mesh(GameState.equipped_item_id())


func _set_tool_mesh(item_id: String) -> void:
	_tool_shown_id = item_id
	if _tool_mesh == null:
		return
	if item_id == "":
		_tool_mesh.visible = false
		return
	var it := GameData.item(item_id)
	var model: String = it.get("hand_model", "")
	if model == "":
		_tool_mesh.visible = false
		return
	var tint := Color.WHITE
	if it.has("hand_tint"):
		tint = Color(it.hand_tint[0], it.hand_tint[1], it.hand_tint[2])
	_tool_mesh.mesh = ModelLibrary.tinted_mesh(model, tint)
	var h := maxf(ModelLibrary.aabb(model).size.y, 0.05)
	var target_len: float = 0.5 if it.get("cat", "") == "arma" else 0.36
	var s := target_len / h
	_tool_mesh.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(s, s, s)), Vector3(0.0, 0.0, -h * s * 0.25))
	_tool_mesh.visible = true


# ------------------------------------------------------------------ daño y muerte
func take_damage(amount: float, from_pos: Vector3, source: String = "") -> void:
	if dead or _iframes > 0.0 or amount <= 0.0:
		return
	if resting:
		set_resting(false)
	_iframes = GameData.bf("player.iframes_hit", 0.7)
	survival.damage(amount)
	rig.flash()
	_shake = 0.6
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() > 0.01:
		_knockback = away.normalized() * 6.0
	AudioManager.play_at("combat/player_hurt", global_position)
	AudioManager.play_at("combat/punch_heavy", global_position, -4.0)
	EventBus.player_damaged.emit(amount, source)
	EventBus.floating_text.emit(global_position + Vector3.UP * 2.2, "-%d" % int(round(amount)), Color(1, 0.35, 0.3))


func is_invulnerable() -> bool:
	return _iframes > 0.0 or dead


func _on_died() -> void:
	if dead:
		return
	dead = true
	interact_held = false
	rig.die()
	AudioManager.play_at("combat/player_death", global_position)
	AudioManager.play("events/stinger_death", -4.0)
	GameState.add_stat("deaths")
	world.on_player_died(global_position)
	EventBus.player_died.emit()


func respawn_at(pos: Vector3) -> void:
	dead = false
	rig.revive()
	global_position = pos + Vector3.UP * 0.5
	velocity = Vector3.ZERO
	_last_safe_pos = global_position
	GameState.survival.health = maxf(GameData.bf("player.respawn_health", 60.0), GameState.max_health() * 0.6)
	GameState.survival.hunger = maxf(GameState.survival.hunger, 45.0)
	GameState.survival.thirst = maxf(GameState.survival.thirst, 45.0)
	GameState.survival.stamina = GameState.max_stamina()
	_iframes = 3.0
	EventBus.player_stats_changed.emit()
	EventBus.player_respawned.emit()


func set_resting(on: bool) -> void:
	resting = on
	survival.resting = on


func sync_to_state() -> void:
	GameState.player_pos = global_position
	GameState.player_yaw = yaw
	GameState.has_position = true


func place_at(pos: Vector3, yaw_in: float) -> void:
	global_position = pos
	yaw = yaw_in
	_last_safe_pos = pos
	cam_rig.global_position = pos + Vector3(0, 1.55, 0)
