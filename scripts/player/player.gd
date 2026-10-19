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
var _air_time := 0.0
var _min_vy := 0.0
var _was_in_water := false
var _base_fov := 65.0
var _fov_kick := 0.0
var _ground_bonus := 0.0
var _ground_t := 0.0


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
	EventBus.level_up.connect(func(_l): _cheer())
	EventBus.quest_completed.connect(func(_q): _cheer())
	EventBus.building_placed.connect(func(uid, _t): _hammer_at(uid))
	EventBus.building_upgraded.connect(func(uid, _t, _l): _hammer_at(uid))
	EventBus.building_repaired.connect(_hammer_at)
	_base_fov = camera.fov
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
	rig.sprint_lean = lerpf(rig.sprint_lean, 0.14 if survival.sprinting else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	var in_water := world.water_depth_at(global_position) > 0.35
	if in_water:
		speed *= 0.6
	_ground_t -= delta
	if _ground_t <= 0.0:
		_ground_t = 0.25
		_ground_bonus = world.ground_speed_bonus(global_position)
	speed *= 1.0 + _ground_bonus
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
	_update_air(delta, in_water)
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
			world.effects.splash(Vector3(global_position.x, 0.02, global_position.z), 0.45)
	if in_water and not _was_in_water and (hvel.length() > 2.5 or velocity.y < -3.0):
		world.effects.splash(Vector3(global_position.x, 0.02, global_position.z), 1.0)
		AudioManager.play_at("footsteps/water", global_position, -1.0)
	_was_in_water = in_water


func _process(delta: float) -> void:
	if world == null:
		return
	# Cámara en tercera persona.
	var focus := global_position + Vector3(0.0, 1.55, 0.0)
	cam_rig.global_position = cam_rig.global_position.lerp(focus, clampf(delta * 14.0, 0.0, 1.0))
	cam_rig.rotation = Vector3(pitch, yaw, 0.0)
	# Ligero aumento del campo de visión al esprintar o esquivar.
	_fov_kick = move_toward(_fov_kick, 0.0, delta * 30.0)
	var fov_target := _base_fov + (5.0 if survival.sprinting else 0.0) + _fov_kick
	camera.fov = lerpf(camera.fov, fov_target, clampf(delta * 6.0, 0.0, 1.0))
	if not bool(Settings.get_value("camera_shake")):
		_shake = 0.0
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
		if survival.sprinting and surf in ["sand", "dirt", "grass"]:
			world.effects.footstep_dust(global_position, _dust_color(surf), 3)


# ------------------------------------------------------------------ acciones
func jump() -> void:
	if dead or not is_on_floor():
		return
	if not survival.spend_stamina(GameData.bf("survival.stamina_jump", 6.0)):
		return
	velocity.y = GameData.bf("player.jump_velocity", 6.2)
	AudioManager.play_at("combat/woosh", global_position, -14.0)
	rig.land(0.25)
	world.effects.footstep_dust(global_position, _dust_color(world.surface_at(global_position)), 4)


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
	rig.play_roll(_dodge_t + 0.08)
	_fov_kick = 6.0
	AudioManager.play_at("combat/woosh", global_position, -4.0)
	world.effects.footstep_dust(global_position, _dust_color(world.surface_at(global_position)), 5)


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
	rig.play_action("attack")
	AudioManager.play_at("combat/swing", global_position, -3.0)
	await get_tree().create_timer(0.16).timeout
	if dead:
		return
	world.effects.slash(global_position + Vector3.UP * 1.05, forward_dir(), reach * 0.9)
	var hits: Array = world.enemies_in_arc(global_position, forward_dir(), reach + 0.4, GameData.bf("player.attack_arc_deg", 110.0))
	var dmg := GameState.weapon_damage()
	for e in hits:
		e.take_damage(dmg, global_position)
	if not hits.is_empty():
		rig.freeze(GameData.bf("combat.hit_freeze", 0.07))
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
		"treasure":
			_face_point(target.pos, 1.0)
			rig.play_action("gather")
			world.treasures.open(int(target.id))
			interact_held = false
			_update_target()
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
	var anim := "gather"
	var strike := 0.12
	match str(tool_type):
		"axe":
			anim = "chop"
			strike = 0.22
		"pickaxe":
			anim = "mine"
			strike = 0.27
		"spear":
			anim = "attack"
			strike = 0.18
	if tool_id == "" and anim != "gather":
		anim = "attack"
		strike = 0.16
	rig.play_action(anim)
	_show_tool(tool_id, 0.8)
	var res: Dictionary = world.resources.hit(node_id, str(tool_type) if tool_id != "" else "", power, tier, global_position)
	if not res.ok:
		if res.reason != "":
			EventBus.notify(res.reason, "warn")
			AudioManager.play_ui("ui/error")
		interact_held = false
		return
	# El golpe se ve y se oye cuando la herramienta llega al recurso.
	var hit_pos: Vector3 = rec.pos + Vector3(0, minf(float(nd.get("height", 1.0)) * 0.4, 1.4), 0)
	var node_type := str(rec.type)
	var depleted: bool = res.depleted
	get_tree().create_timer(strike).timeout.connect(func():
		if not is_instance_valid(world):
			return
		AudioManager.play_at(str(nd.get("sound", "gather/pickup")), hit_pos, -2.0)
		world.spawn_hit_effect(hit_pos, node_type)
		if str(tool_type) == "spear":
			world.effects.splash(Vector3(hit_pos.x, 0.02, hit_pos.z), 0.8)
		if depleted:
			world.effects.burst(hit_pos, WorldEffects.COLORS.get(node_type, Color(0.6, 0.55, 0.45)), 16, 4.5, 0.9, 1.5)
			if nd.has("break_sound"):
				AudioManager.play_at(str(nd.break_sound), hit_pos, 0.0)
		if anim != "gather":
			_shake = maxf(_shake, 0.12))
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
			EventBus.item_collected_at.emit(item_id, got, rec.pos + Vector3.UP * 1.2)
		if left > 0:
			world.spawn_drop(item_id, left, global_position + forward_dir() * 0.8, true, true)
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
	rig.play_action("eat")
	_show_held_item(id, 0.9)
	if float(it.food.get("health", 0)) > 10.0:
		AudioManager.play("survival/heal", -6.0)
		world.effects.sparkle(global_position + Vector3.UP * 1.0, Color(0.5, 1.0, 0.5), 12)
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
	# Tesoros en la orilla.
	if world.treasures:
		var ti: int = world.treasures.nearest(pos, 2.4)
		if ti >= 0:
			return {"kind": "treasure", "id": ti, "label": world.treasures.label_for(ti), "icon": "icon_hand", "pos": world.treasures.position_of(ti)}
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
	if uid >= 0 and node_id < 0 and not bool(GameData.building(Economy.get_building(uid).get("type", "")).get("walkable", false)):
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
	var walkable_uid := -1
	if uid >= 0:
		var rec4 := Economy.get_building(uid)
		if not bool(GameData.building(rec4.type).get("walkable", false)):
			return {"kind": "building", "uid": uid, "label": GameData.building(rec4.type).name, "icon": "icon_wrench", "pos": Vector3(rec4.pos[0], rec4.pos[1], rec4.pos[2])}
		walkable_uid = uid
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
	# Los caminos solo se seleccionan si no hay nada más a mano.
	if walkable_uid >= 0:
		var rec5 := Economy.get_building(walkable_uid)
		return {"kind": "building", "uid": walkable_uid, "label": GameData.building(rec5.type).name, "icon": "icon_wrench", "pos": Vector3(rec5.pos[0], rec5.pos[1], rec5.pos[2])}
	return {}


# ------------------------------------------------------------------ animación y efectos
## Aterrizajes: aplastamiento proporcional a la caída, polvo y sonido.
func _update_air(delta: float, in_water: bool) -> void:
	var ground: float = world.height_at(global_position.x, global_position.z)
	var on_floor := is_on_floor()
	rig.airborne = not on_floor and global_position.y - ground > 0.3
	rig.vertical_speed = velocity.y
	if not on_floor:
		_air_time += delta
		_min_vy = minf(_min_vy, velocity.y)
		return
	if _air_time > 0.15:
		var fall := -_min_vy
		rig.land(clampf(fall / 12.0, 0.15, 1.0))
		if not in_water and fall > 4.0:
			var surf: String = world.surface_at(global_position)
			world.effects.footstep_dust(global_position, _dust_color(surf), 4 + int(fall))
			AudioManager.play_at({"sand": "footsteps/sand", "stone": "footsteps/stone", "wood": "footsteps/wood"}.get(surf, "footsteps/grass"), global_position, -3.0)
			if fall > 9.0:
				_shake = maxf(_shake, 0.3)
				world.effects.ring(global_position, Color(0.9, 0.85, 0.7, 0.6), 1.6, 0.4)
	_air_time = 0.0
	_min_vy = 0.0


func _dust_color(surf: String) -> Color:
	match surf:
		"sand":
			return Color(0.93, 0.86, 0.66)
		"stone":
			return Color(0.7, 0.68, 0.66)
		"grass":
			return Color(0.66, 0.72, 0.5)
	return Color(0.75, 0.66, 0.52)


## Celebra (subida de nivel, objetivo cumplido) si no está ocupado.
func _cheer() -> void:
	if dead or world == null:
		return
	world.effects.celebrate(global_position)
	if not rig.is_acting() and _dodge_t <= 0.0:
		rig.play_action("cheer")


## Martillea al construir, mejorar o reparar un edificio cercano.
func _hammer_at(uid: int) -> void:
	if dead or world == null:
		return
	var rec := Economy.get_building(uid)
	if rec.is_empty():
		return
	var bpos := Vector3(rec.pos[0], rec.pos[1], rec.pos[2])
	if bpos.distance_to(global_position) > 14.0:
		return
	_face_point(bpos, 1.0)
	_show_tool("martillo" if GameState.inventory.count("martillo") > 0 else "", 1.0)
	rig.play_action("hammer", 0.9)


## Muestra un objeto (comida) en la mano durante un momento.
func _show_held_item(item_id: String, seconds: float) -> void:
	if _tool_mesh == null:
		return
	var it := GameData.item(item_id)
	var model: String = it.get("drop_model", it.get("icon_model", ""))
	if model == "":
		return
	var tint := Color.WHITE
	if it.has("icon_tint"):
		tint = Color(it.icon_tint[0], it.icon_tint[1], it.icon_tint[2])
	_tool_mesh.mesh = ModelLibrary.tinted_mesh(model, tint)
	var size := maxf(ModelLibrary.aabb(model).get_longest_axis_size(), 0.05)
	var sc := 0.22 / size
	_tool_mesh.transform = Transform3D(Basis().scaled(Vector3(sc, sc, sc)), Vector3(0.0, -0.02, -0.04))
	_tool_mesh.visible = true
	_tool_shown_id = "@" + item_id
	_tool_show_t = seconds


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
	if not rig.is_rolling():
		rig.play_action("flinch")
	world.effects.impact(global_position + Vector3.UP * 1.1, Color(1.0, 0.45, 0.35))
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
