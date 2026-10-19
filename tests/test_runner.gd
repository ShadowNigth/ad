extends Node
## Pruebas automáticas (sección 19). Ejecutar en modo headless:
##   godot --headless --path . tests/test_runner.tscn
## Devuelve código de salida 0 si todo pasa. Escribe un informe en
## user://test_report.txt además de la consola.

var passed := 0
var failed := 0
var lines: Array[String] = []
var world: World
var _section := ""


func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		lines.append("  ✔ " + msg)
	else:
		failed += 1
		lines.append("  ✘ FALLO: " + msg)
		push_warning("PRUEBA FALLIDA [%s]: %s" % [_section, msg])


func section(name: String) -> void:
	_section = name
	lines.append("")
	lines.append("== " + name)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	SaveManager.enabled = false
	var t0 := Time.get_ticks_msec()
	_test_data()
	_test_inventory()
	_reset_game()
	await _load_world()
	await _test_world()
	await _test_core_loop()
	await _cleanup_after_loop()
	await _test_touch_movement()
	await _test_gathering()
	_test_crafting_rules()
	await _test_crafting_queue()
	_test_placement()
	await _test_production_and_upgrades()
	_test_workers()
	_test_tech()
	await _test_quests()
	await _test_combat()
	await _test_death_and_backpack()
	await _test_day_night()
	await _test_regions()
	await _test_polish()
	await _test_save_load()
	_test_offline()
	await _test_ui_scaling_and_buttons()
	_test_performance()
	lines.append("")
	lines.append("RESULTADO: %d correctas, %d fallidas (%.1f s)" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	var text := "\n".join(lines)
	print(text)
	var f := FileAccess.open("user://test_report.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	SaveManager.delete_save()
	get_tree().quit(0 if failed == 0 else 1)


func _reset_game() -> void:
	TechTree.reset()
	GameState.new_game()
	Economy.reset()
	Workers.reset()
	Quests.reset()


func _load_world() -> void:
	var t0 := Time.get_ticks_msec()
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await frames(5)
	lines.append("Mundo cargado en %d ms" % (Time.get_ticks_msec() - t0))


# ------------------------------------------------------------------ 1. Proyecto y datos
func _test_data() -> void:
	section("Proyecto y datos")
	var errors := GameData.validate()
	check(errors.is_empty(), "Los datos JSON no tienen referencias rotas %s" % str(errors.slice(0, 5)))
	check(GameData.items.size() >= 40, "Hay %d objetos definidos" % GameData.items.size())
	check(GameData.buildings.size() >= 15, "Hay %d edificios definidos" % GameData.buildings.size())
	check(GameData.techs.size() >= 30, "Hay %d tecnologías en 8 ramas" % GameData.techs.size())
	check(GameData.branches.size() == 8, "Ramas tecnológicas: 8")
	for scene in ["res://scenes/main/main.tscn", "res://scenes/main/main_menu.tscn", "res://scenes/world/world.tscn", "res://scenes/player/player.tscn", "res://scenes/ui/hud.tscn"]:
		check(load(scene) != null, "Escena carga: " + scene)
	var obj_count := 0
	for b in GameData.buildings.values():
		for l in b.levels:
			for m in l.get("models", []):
				if ModelLibrary.mesh(m.model) != null:
					obj_count += 1
	check(obj_count > 100, "Las piezas OBJ de los edificios se importan como Mesh (%d piezas)" % obj_count)
	var tex_mesh := ModelLibrary.mesh("survival/tool-axe")
	var mat := tex_mesh.surface_get_material(0) as StandardMaterial3D
	check(mat != null and mat.albedo_texture != null, "Los OBJ con MTL conservan su textura (colormap.png)")
	var nat := ModelLibrary.mesh("nature/tree_palmTall")
	check(nat != null and nat.get_surface_count() >= 2, "Los OBJ con varios materiales MTL mantienen sus superficies")
	var aabb := ModelLibrary.aabb("characters/character-male-a")
	check(aabb.size.y > 0.5 and aabb.size.y < 0.8 and aabb.position.y >= -0.01, "Personaje OBJ con origen en los pies (alto %.2f u)" % aabb.size.y)


# ------------------------------------------------------------------ 2. Inventario
func _test_inventory() -> void:
	section("Inventario")
	var inv := Inventory.new(4)
	check(inv.add("madera", 150) == 0, "Se apilan 150 de madera en 2 huecos (pila 99)")
	check(inv.count("madera") == 150 and inv.free_slots() == 2, "Cuenta 150 y quedan 2 huecos libres")
	check(inv.add("hacha_piedra", 3) == 1, "Herramientas no apilables: caben 2, sobra 1")
	check(inv.add("piedra", 5) == 5, "Inventario lleno: no se añade nada más")
	check(not inv.remove("madera", 151), "No se puede quitar más de lo que hay")
	check(inv.count("madera") == 150, "Un fallo al quitar no altera la cantidad")
	check(inv.remove("madera", 149) and inv.count("madera") == 1, "Quitar 149 deja 1")
	var total_before := inv.count("madera") + inv.count("hacha_piedra")
	inv.move(0, 3)
	inv.move(3, 1)
	check(inv.count("madera") + inv.count("hacha_piedra") == total_before, "Mover huecos no duplica ni pierde objetos")
	check(inv.add("noexiste", 3) == 3, "Objetos desconocidos se rechazan")
	var inv2 := Inventory.new(3)
	inv2.add("hacha_piedra", 1)
	var slot := inv2.best_tool("axe")
	var dur := int(inv2.slots[slot].dur)
	check(dur > 0, "La herramienta tiene durabilidad (%d)" % dur)
	for i in dur - 1:
		inv2.wear(slot, 1)
	check(inv2.count("hacha_piedra") == 1, "Sigue existiendo antes del último uso")
	check(inv2.wear(slot, 1) and inv2.count("hacha_piedra") == 0, "Se rompe al agotar la durabilidad")
	var data := inv.to_array()
	var inv3 := Inventory.new(4)
	inv3.from_array(data)
	check(inv3.all_items() == inv.all_items(), "Serialización del inventario sin pérdidas")


# ------------------------------------------------------------------ 3. Mundo
func _test_world() -> void:
	section("Mundo e isla")
	var gen := world.gen
	check(gen.heights.size() == gen.n * gen.n, "Mapa de alturas %dx%d" % [gen.n, gen.n])
	var zones := {}
	for z in gen.zones:
		zones[IslandGenerator.ZONE_IDS[z]] = true
	for z in ["playa", "pradera", "bosque", "rocosa", "jungla", "cueva", "rio", "lago", "camino"]:
		check(zones.has(z), "La isla contiene la zona: " + z)
	# Determinismo: misma semilla, mismo terreno.
	var gen2 := IslandGenerator.new(GameData.world, int(GameData.b("world.seed", 1)))
	gen2.generate()
	check(gen2.heights == gen.heights, "Generación determinista con semilla fija")
	# La colisión coincide con la malla (rayos contra el HeightMapShape3D).
	var space := world.get_world_3d().direct_space_state
	var max_err := 0.0
	var samples := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		var x := rng.randf_range(-90, 90)
		var z := rng.randf_range(-90, 90)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			max_err = maxf(max_err, absf(hit.position.y - gen.height_at(x, z)))
			samples += 1
	check(samples > 30 and max_err < 0.05, "La colisión del terreno coincide con la malla (error máx. %.3f m)" % max_err)
	var counts := {}
	for rec in world.resources.nodes:
		counts[rec.type] = int(counts.get(rec.type, 0)) + 1
	for t in ["palmera", "arbol", "roca", "roca_hierro", "arbusto_bayas", "hierba_alta", "cristal", "arbol_oscuro"]:
		check(int(counts.get(t, 0)) > 0, "Hay nodos de %s (%d)" % [t, int(counts.get(t, 0))])
	var p := world.player
	check(world.is_walkable(p.global_position), "El jugador aparece en tierra firme")
	check(absf(p.global_position.y - world.height_at(p.global_position.x, p.global_position.z)) < 1.0, "El jugador está sobre el terreno")
	check(world.pois.pois.size() >= 8, "Puntos de interés colocados (%d)" % world.pois.pois.size())
	# Agua: dulce en el lago, salada en el mar.
	var lake: Array = GameData.world.lake.center
	check(world.is_fresh_water(Vector3(lake[0], 0, lake[1])), "La laguna es agua dulce")
	check(not world.is_fresh_water(Vector3(0, 0, 120)), "El mar no es agua dulce")
	check(not world.is_walkable(Vector3(0, 0, 124)), "El mar profundo no es transitable")


# ------------------------------------------------------------------ 3b. Bucle principal (fase 1)
func _gather_until(types: Array, item: String, target: int) -> void:
	var p := world.player
	var guard := 0
	while GameState.inventory.count(item) < target and guard < 400:
		guard += 1
		var id := -1
		for t in types:
			id = _nearest_node(t)
			if id >= 0:
				break
		if id < 0:
			return
		var rec := world.resources.get_node_rec(id)
		var r := float(world.resources.node_data(rec).get("radius", 0.0))
		p.global_position = rec.pos + Vector3(r + 0.9, 0.4, 0)
		p.rig.rotation.y = atan2(1.0, 0.0)  # mira hacia -X (hacia el nodo)
		await physics_frames(2)
		p._gather_cd = 0.0
		p._update_target()
		if p.target.get("kind", "") != "node":
			continue
		p.interact_pressed()


func _wait_crafter() -> void:
	for i in 600:
		await get_tree().process_frame
		if not world.crafter.is_busy():
			return


func _build_in_front(type_id: String, offset: Vector3) -> int:
	var p := world.player
	var camp := _camp_pos()
	p.global_position = camp + offset + Vector3(0, 0.5, 0)
	p.rig.rotation.y = 0.0  # mira al norte (-Z)
	await physics_frames(3)
	var bm := world.build_mode
	bm.start(type_id)
	await frames(3)
	var before := Economy.count_of(type_id)
	bm.confirm()
	bm.cancel()
	await frames(2)
	return Economy.count_of(type_id) - before


func _test_core_loop() -> void:
	section("Bucle principal: recoger, fabricar, construir, sobrevivir y producir")
	Quests.active = true
	var p := world.player
	var inv := GameState.inventory
	# Cofre del naufragio.
	var chest := world.pois.poi_by_id("cofre_naufragio")
	p.global_position = chest.world_pos + Vector3(1.5, 0.5, 0)
	await physics_frames(2)
	p._update_target()
	check(p.target.get("kind", "") == "poi", "El cofre del naufragio es interactuable")
	p.interact_pressed()
	check(inv.count("madera") >= 4 and inv.count("coco") >= 2, "El cofre da materiales iniciales")
	await _gather_until(["arbol", "palmera"], "madera", 30)
	check(inv.count("madera") >= 30, "Se recolectan 30 de madera talando (%d)" % inv.count("madera"))
	await _gather_until(["roca", "piedras_suelo"], "piedra", 22)
	check(inv.count("piedra") >= 22, "Se recolecta piedra (%d)" % inv.count("piedra"))
	await _gather_until(["hierba_alta"], "fibra", 22)
	check(inv.count("fibra") >= 22, "Se recolecta fibra (%d)" % inv.count("fibra"))
	await frames(3)
	check(Quests.index >= 3, "Los tres primeros objetivos se completan recolectando (objetivo %d)" % Quests.index)
	for r in ["r_hacha_piedra", "r_pico_piedra", "r_martillo", "r_cuenco_coco"]:
		world.crafter.enqueue(r, 1)
		await _wait_crafter()
	for it in ["hacha_piedra", "pico_piedra", "martillo", "cuenco_coco"]:
		check(inv.count(it) == 1, "Fabricado: " + GameData.item_name(it))
	# Con hacha se tala el triple de rápido.
	var w0 := inv.count("madera")
	await _gather_until(["arbol", "palmera"], "madera", w0 + 3)
	check(inv.count("madera") >= w0 + 3, "Con el hacha se consigue madera más rápido")
	p.eat_slot(_slot_of("bayas"))
	await frames(2)
	check(_built(await _build_in_front("fogata", Vector3(0, 0, 4))), "Se construye una fogata con el modo construcción")
	check(_built(await _build_in_front("refugio", Vector3(-7, 0, 6))), "Se construye el refugio")
	await _gather_until(["arbol", "palmera"], "madera", 40)
	await _gather_until(["roca", "piedras_suelo"], "piedra", 15)
	check(_built(await _build_in_front("lenador", Vector3(7, 0, 6))), "Se construye el puesto de leñador (primera automatización)")
	# Agua: recoger con el cuenco en la laguna y hervirla en la fogata.
	var lk: Array = GameData.world.lake.center
	var lake_r := float(GameData.world.lake.radius)
	var shore := Vector3(lk[0] + lake_r + 1.2, 0, lk[1])
	shore.y = world.height_at(shore.x, shore.z)
	p.global_position = shore + Vector3(0, 0.5, 0)
	p.rig.rotation.y = PI * 0.5  # mira hacia -X (hacia el agua)
	await physics_frames(3)
	p._update_target()
	check(p.target.get("kind", "") == "water", "Junto a la laguna se puede recoger agua")
	p.interact_pressed()
	check(inv.count("agua_sucia") >= 1, "El cuenco de coco recoge agua sin tratar")
	var fog := Economy.buildings_of("fogata")
	if not fog.is_empty():
		p.global_position = Vector3(fog[0].pos[0] + 2.0, fog[0].pos[1] + 0.5, fog[0].pos[2])
		await physics_frames(2)
		world.crafter.enqueue("r_hervir_agua", 1)
		await _wait_crafter()
		check(inv.count("agua") >= 1, "Hervir el agua en la fogata produce agua potable")
	await frames(3)
	check(Quests.index >= 9, "La cadena de objetivos avanza con el bucle (objetivo %d: %s)" % [Quests.index, Quests.current().get("title", "")])
	var len := Economy.buildings_of("lenador")
	check(not len.is_empty(), "Hay un leñador produciendo")
	var m0 := Economy.stored("madera")
	Economy.tick(61.0)
	check(Economy.stored("madera") >= m0 + 4, "El leñador produce madera automáticamente (+%d en 1 min)" % (Economy.stored("madera") - m0))


func _cleanup_after_loop() -> void:
	for rec in Economy.buildings.duplicate():
		Economy.demolish(int(rec.uid))
	await frames(2)
	Economy.storage.clear()
	GameState.inventory.clear()
	Workers.reset()
	TechTree.reset()
	Quests.reset()
	GameState.stats = {"gathered": {}, "crafted": {}, "kills": {}, "built": 0, "nights": 0, "deaths": 0, "eaten": 0, "water": 0}
	Quests.active = false


func _slot_of(id: String) -> int:
	for i in GameState.inventory.slots.size():
		if GameState.inventory.slots[i] != null and GameState.inventory.slots[i].id == id:
			return i
	return -1


func _built(n: int) -> bool:
	return n == 1


# ------------------------------------------------------------------ 4. Movimiento táctil
func _test_touch_movement() -> void:
	section("Controles táctiles")
	var p := world.player
	var hud: Node = world.hud
	var joy: TouchJoystick = hud.joystick
	var start := p.global_position
	# Se simula un dedo en el joystick: pulsación y arrastre hacia arriba.
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = Vector2(150, joy.size.y - 150)
	joy._gui_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = press.position + Vector2(0, -80)
	joy._gui_input(drag)
	check(joy.value.length() > 0.5, "El joystick produce un vector de movimiento (%.2f)" % joy.value.length())
	# Segundo dedo sobre el botón de saltar mientras el primero mueve el joystick.
	var jump_btn: TouchButton = hud.action_box.get_node("BtnSaltar")
	var jumped := [false]
	var cb := func(): jumped[0] = true
	jump_btn.button_down.connect(cb)
	var t2 := InputEventScreenTouch.new()
	t2.index = 1
	t2.pressed = true
	t2.position = jump_btn.size * 0.5
	jump_btn._gui_input(t2)
	var t2r := InputEventScreenTouch.new()
	t2r.index = 1
	t2r.pressed = false
	jump_btn._gui_input(t2r)
	jump_btn.button_down.disconnect(cb)
	check(jumped[0], "Multitáctil: se puede pulsar un botón de acción mientras se usa el joystick")
	check(joy.value.length() > 0.5, "El joystick sigue activo durante el segundo toque")
	await physics_frames(60)
	var moved := p.global_position.distance_to(start)
	check(moved > 1.0, "El jugador se mueve con el joystick (%.1f m en 1 s)" % moved)
	var rel := InputEventScreenTouch.new()
	rel.index = 0
	rel.pressed = false
	joy._gui_input(rel)
	check(joy.value == Vector2.ZERO, "Al soltar el joystick el movimiento se detiene")
	var yaw0 := p.yaw
	var look: TouchLook = hud.look_area
	var t1 := InputEventScreenTouch.new()
	t1.index = 1
	t1.pressed = true
	t1.position = Vector2(900, 300)
	look._gui_input(t1)
	var d1 := InputEventScreenDrag.new()
	d1.index = 1
	d1.position = Vector2(1000, 300)
	look._gui_input(d1)
	check(absf(p.yaw - yaw0) > 0.1, "Arrastrar en la zona derecha gira la cámara")
	var t1r := InputEventScreenTouch.new()
	t1r.index = 1
	t1r.pressed = false
	look._gui_input(t1r)


# ------------------------------------------------------------------ 5. Recolección
func _nearest_node(type_id: String) -> int:
	var best := -1
	var best_d := INF
	for rec in world.resources.nodes:
		if rec.type == type_id and not rec.depleted and world.is_walkable(rec.pos):
			var d: float = rec.pos.distance_to(world.player.global_position)
			if d < best_d:
				best_d = d
				best = rec.id
	return best


func _test_gathering() -> void:
	section("Recolección")
	var rm := world.resources
	var inv := GameState.inventory
	var tree_id := _nearest_node("arbol")
	if tree_id < 0:
		tree_id = _nearest_node("palmera")
	check(tree_id >= 0, "Hay un árbol accesible")
	var rec := rm.get_node_rec(tree_id)
	var before := inv.count("madera")
	var res := rm.hit(tree_id, "", 1, 0, rec.pos + Vector3(1, 0, 0))
	check(res.ok and int(res.items.get("madera", 0)) >= 1, "A mano se obtiene 1 de madera por golpe")
	var hits_left := int(rec.hits)
	res = rm.hit(tree_id, "axe", 3, 1, rec.pos + Vector3(1, 0, 0))
	check(int(res.items.get("madera", 0)) >= 3, "Con hacha de piedra se obtienen 3 por golpe (%d)" % int(res.items.get("madera", 0)))
	check(int(rec.hits) == hits_left - 1, "Cada golpe reduce la vida del nodo")
	var guard := 0
	while not rec.depleted and guard < 20:
		rm.hit(tree_id, "axe", 3, 1, rec.pos + Vector3(1, 0, 0))
		guard += 1
	check(rec.depleted, "El árbol se agota tras varios golpes")
	check(GameState.depleted_nodes.has(str(tree_id)), "El nodo agotado se registra para guardarse")
	check(rm.nearest_available(rec.pos, 1.0) != tree_id, "Un nodo agotado no se puede volver a recolectar")
	var res2 := rm.hit(tree_id, "axe", 3, 1, rec.pos)
	check(not res2.ok, "Golpear un nodo agotado no da recursos")
	GameState.depleted_nodes[str(tree_id)] = GameState.now() - 1.0
	world.player.global_position = rec.pos + Vector3(8, 1, 8)
	rm._check_respawns()
	check(not rec.depleted, "El nodo reaparece cuando vence su tiempo")
	var iron := _nearest_node("roca_hierro")
	if iron >= 0:
		var r3 := rm.hit(iron, "", 1, 0, Vector3.ZERO)
		check(not r3.ok and r3.reason != "", "La veta de hierro exige pico de piedra: «%s»" % r3.reason)
		var r4 := rm.hit(iron, "pickaxe", 3, 1, Vector3.ZERO)
		check(r4.ok and int(r4.items.get("mineral_hierro", 0)) >= 3, "Con pico de piedra se obtiene mineral de hierro")
	# Recolección real desde el jugador (botón de acción).
	var bush := _nearest_node("arbusto_bayas")
	if bush >= 0:
		var brec := rm.get_node_rec(bush)
		world.player.global_position = brec.pos + Vector3(1.2, 0.5, 0)
		await physics_frames(5)
		world.player._update_target()
		var t := world.player.target
		check(t.get("kind", "") == "node", "El botón contextual detecta el arbusto cercano")
		var b0 := inv.count("bayas")
		world.player._gather_cd = 0.0
		world.player.interact_pressed()
		check(inv.count("bayas") > b0, "Recoger con el botón de acción añade bayas al inventario")
	var tree2 := _nearest_node("arbol")
	if tree2 < 0:
		tree2 = _nearest_node("palmera")
	if tree2 >= 0:
		var trec := rm.get_node_rec(tree2)
		world.player.global_position = trec.pos + Vector3(1.4, 0.5, 0)
		await physics_frames(5)
		world.player._update_target()
		var m0 := inv.count("madera")
		world.player._gather_cd = 0.0
		world.player.interact_pressed()
		check(inv.count("madera") > m0, "Talar con el botón de acción añade madera al inventario")


# ------------------------------------------------------------------ 6. Fabricación
func _test_crafting_rules() -> void:
	section("Fabricación")
	var inv := GameState.inventory
	inv.clear()
	Economy.storage.clear()
	var crafter: Crafter = world.crafter
	check(not crafter.can_craft("r_hacha_piedra").ok, "Sin materiales no se puede fabricar el hacha")
	inv.add("madera", 3)
	inv.add("piedra", 2)
	inv.add("fibra", 2)
	check(crafter.can_craft("r_hacha_piedra").ok, "Con 3 madera, 2 piedra y 2 fibra se puede fabricar")
	check(not crafter.can_craft("r_carbon").ok, "El carbón exige estar junto a una fogata")
	check(not crafter.can_craft("r_tablas").ok, "Las tablas requieren la tecnología Carpintería")


func _test_crafting_queue() -> void:
	var inv := GameState.inventory
	var crafter: Crafter = world.crafter
	var added := crafter.enqueue("r_hacha_piedra", 2)
	check(added == 2, "Se encolan 2 unidades")
	for i in 400:
		await get_tree().process_frame
		if not crafter.is_busy():
			break
	check(inv.count("hacha_piedra") == 1, "Solo se fabrica 1 hacha (los materiales daban para una)")
	check(inv.count("madera") == 0 and inv.count("piedra") == 0 and inv.count("fibra") == 0, "Se consumen exactamente los ingredientes")
	inv.add("madera", 10)
	inv.add("piedra", 10)
	inv.add("fibra", 10)
	crafter.enqueue("r_martillo", 1)
	crafter.cancel_all()
	check(inv.count("madera") == 10 and inv.count("piedra") == 10, "Cancelar la cola devuelve los materiales de la unidad en curso")


# ------------------------------------------------------------------ 7. Construcción
func _camp_pos() -> Vector3:
	var c: Array = [6.0, 28.0]
	for poi in GameData.world.pois:
		if poi.type == "camp":
			c = poi.pos
	return Vector3(c[0], world.height_at(c[0], c[1]), c[1])


func _test_placement() -> void:
	section("Construcción")
	var bm := world.buildings
	var camp := _camp_pos()
	world.player.global_position = camp + Vector3(0, 0.5, 6)
	var ok := bm.placement_valid("fogata", camp, 0.0)
	check(ok.ok, "Colocación válida en el claro del campamento (%s)" % ok.reason)
	check(not bm.placement_valid("fogata", Vector3(0, 0, 118), 0.0).ok, "No se puede construir en el agua")
	var lk: Array = GameData.world.lake.center
	check(not bm.placement_valid("fogata", Vector3(lk[0], 0, lk[1]), 0.0).ok, "No se puede construir en la laguna")
	var ruins: Array = [0, 0]
	for poi in GameData.world.pois:
		if poi.id == "ruinas":
			ruins = poi.pos
	check(not bm.placement_valid("fogata", Vector3(ruins[0], 1, ruins[1]), 0.0).ok, "No se puede construir en una región bloqueada")
	check(not bm.placement_valid("mina", camp, 0.0).ok, "La mina exige la zona rocosa")
	GameState.inventory.clear()
	check(not Economy.can_build("fogata").ok, "Sin martillo no se puede construir")
	GameState.inventory.add("martillo", 1)
	GameState.inventory.add("madera", 50)
	GameState.inventory.add("piedra", 50)
	GameState.inventory.add("fibra", 50)
	check(Economy.can_build("fogata").ok, "Con martillo y materiales se puede construir")
	var madera0 := Economy.total_available("madera")
	var uid := Economy.place_building("fogata", camp, 0.0)
	check(uid > 0, "Se construye la fogata")
	check(Economy.total_available("madera") == madera0 - 5, "La construcción descuenta el coste exacto")
	check(bm.get_building_node(uid) != null, "Aparece el edificio en el mundo")
	check(not bm.placement_valid("fogata", camp + Vector3(0.5, 0, 0.5), 0.0).ok, "No se puede construir encima de otro edificio")
	var c2 := Economy.build_cost("fogata")
	check(int(c2.madera) > 5, "La segunda fogata cuesta más (coste progresivo: %d madera)" % int(c2.madera))
	var bmode := world.build_mode
	bmode.start("refugio")
	check(bmode.active, "El modo construcción se activa")
	bmode.rotate_step(45)
	check(is_equal_approx(fmod(bmode.rot_deg, 45.0), 0.0), "La vista previa rota en pasos de 45°")
	bmode.cancel()
	check(not bmode.active, "Cancelar sale del modo construcción")


# ------------------------------------------------------------------ 8. Producción y mejoras
func _test_production_and_upgrades() -> void:
	section("Producción automática y mejoras")
	var camp := _camp_pos()
	Economy.storage.clear()
	var uid := Economy.place_building("lenador", camp + Vector3(-8, 0, 0), 0.0, true)
	var rec := Economy.get_building(uid)
	check(uid > 0 and rec.type == "lenador", "Puesto de leñador construido")
	var ct1 := Economy.cycle_time(rec)
	check(is_equal_approx(ct1, 30.0), "Ciclo base de 30 s (datos JSON)")
	Economy.tick(30.0)
	check(Economy.stored("madera") == 2, "En 30 s produce 2 de madera en el almacén (%d)" % Economy.stored("madera"))
	var rate1: float = Economy.building_rate(rec).get("madera", 0.0)
	check(is_equal_approx(rate1, 4.0), "Producción visible: 4 madera/min")
	Economy.running = true
	var before := Economy.stored_f("madera")
	await frames(30)
	check(float(rec.progress) > 0.0 or Economy.stored_f("madera") > before, "La producción avanza en tiempo real (progreso %.3f)" % float(rec.progress))
	Economy.running = false
	GameState.inventory.add("madera", 200)
	GameState.inventory.add("piedra", 100)
	GameState.inventory.add("cuerda", 20)
	GameState.inventory.add("martillo", 1)
	check(Economy.can_upgrade(uid).ok, "Se puede mejorar el leñador")
	check(Economy.upgrade(uid), "Mejora a nivel 2")
	var ct2 := Economy.cycle_time(rec)
	var rate2: float = Economy.building_rate(rec).get("madera", 0.0)
	check(ct2 < ct1, "La mejora reduce el tiempo de ciclo (%.1f → %.1f s)" % [ct1, ct2])
	check(rate2 > rate1 * 1.5, "La mejora aumenta la producción por minuto (%.1f → %.1f)" % [rate1, rate2])
	# Cadena: aserradero convierte madera en tablas y no produce sin materia prima.
	var saw := Economy.place_building("aserradero", camp + Vector3(8, 0, 0), 0.0, true)
	var srec := Economy.get_building(saw)
	rec.hp = 0.0  # se detiene el leñador para medir solo el aserradero
	Economy.storage.clear()
	Economy.tick(20.0)
	check(srec.status == Economy.STATUS_NO_INPUT and Economy.stored("tablas") == 0, "Sin madera el aserradero se detiene (sin producción infinita)")
	Economy.add_storage("madera", 10)
	Economy.tick(12.0)
	check(Economy.stored("tablas") >= 1, "Con madera produce tablas")
	check(Economy.stored_f("madera") < 10.0, "Consume la madera de entrada")
	rec.hp = Economy.max_hp(rec)
	# Tope de almacén: nada por encima de la capacidad ni negativos.
	Economy.storage["madera"] = float(Economy.capacity())
	var lrec := Economy.get_building(uid)
	Economy.tick(120.0)
	check(Economy.stored("madera") <= Economy.capacity(), "El almacén nunca supera su capacidad")
	check(lrec.status == Economy.STATUS_FULL or lrec.status == Economy.STATUS_OK, "Con el almacén lleno el leñador espera")
	for id in Economy.storage:
		check(float(Economy.storage[id]) >= 0.0, "Sin cantidades negativas (%s)" % id)
	Economy.storage.clear()
	var dmg_rec := Economy.get_building(uid)
	Economy.damage_building(uid, Economy.max_hp(dmg_rec) * 0.7)
	check(Economy.speed_mult(dmg_rec) < 1.5, "Un edificio dañado produce más lento")
	GameState.inventory.add("madera", 100)
	GameState.inventory.add("piedra", 100)
	check(Economy.repair(uid) and is_equal_approx(float(dmg_rec.hp), Economy.max_hp(dmg_rec)), "Reparar restaura la integridad")


# ------------------------------------------------------------------ 9. Trabajadores
func _test_workers() -> void:
	section("Trabajadores")
	check(not Workers.can_hire("lenador").ok, "Sin la tecnología Organización no se contrata")
	TechTree.researched["aut_organizacion"] = true
	TechTree._recalc()
	GameState.inventory.add("bayas", 30)
	GameState.inventory.add("madera", 100)
	var r := Workers.can_hire("lenador")
	check(not r.ok and "alojamiento" in r.reason.to_lower(), "Sin alojamiento no se puede contratar")
	var camp := _camp_pos()
	Economy.place_building("refugio", camp + Vector3(0, 0, -10), 0.0, true)
	check(Workers.can_hire("lenador").ok, "Con refugio (2 plazas) se puede contratar")
	var lenador := Economy.buildings_of("lenador")[0] as Dictionary
	var m0 := Economy.speed_mult(lenador)
	var wid := Workers.hire("lenador")
	check(wid > 0, "Trabajador contratado")
	check(Workers.workers_in(int(lenador.uid)).size() == 1, "Se asigna automáticamente al leñador")
	check(Economy.speed_mult(lenador) > m0 * 1.3, "El trabajador acelera la producción (×%.2f → ×%.2f)" % [m0, Economy.speed_mult(lenador)])
	var cost1: int = Workers.hire_cost("lenador").madera
	check(cost1 > 25, "El segundo trabajador cuesta más (%d madera)" % cost1)
	TechTree.researched["aut_capataz"] = true
	TechTree._recalc()
	GameState.inventory.add("cuerda", 20)
	GameState.inventory.add("madera", 200)
	var m1 := Workers.multiplier(int(lenador.uid))
	check(Workers.train(wid), "Entrenar al trabajador")
	check(Workers.multiplier(int(lenador.uid)) > m1, "El entrenamiento mejora su efecto")


# ------------------------------------------------------------------ 10. Tecnología
func _test_tech() -> void:
	section("Árbol tecnológico")
	TechTree.points = 0
	check(not TechTree.can_research("con_almacen").ok, "Sin puntos no se investiga")
	TechTree.add_points(3)
	check(TechTree.can_research("con_almacen").ok, "Con puntos se puede investigar Almacenaje")
	check(not Economy.can_build("almacen").ok, "El almacén está bloqueado antes de investigar")
	check(TechTree.research("con_almacen"), "Investigar Almacenaje")
	check(TechTree.points == 2, "Se descuentan los puntos")
	GameState.inventory.add("madera", 100)
	GameState.inventory.add("piedra", 100)
	GameState.inventory.add("martillo", 1)
	check(Economy.can_build("almacen").ok, "La tecnología desbloquea el almacén")
	check(not TechTree.can_research("min_acero").ok, "Las tecnologías de edades futuras están bloqueadas")
	var cap0 := GameState.inventory.capacity
	TechTree.researched["rec_mochila"] = true
	TechTree._recalc()
	check(GameState.inventory.capacity == cap0 + 8, "Mochila de fibra amplía el inventario (+8)")


# ------------------------------------------------------------------ 11. Misiones
func _test_quests() -> void:
	section("Objetivos")
	Quests.reset()
	Quests.active = true
	var q0: String = Quests.current().id
	EventBus.item_gathered.emit("madera", 5)
	await frames(2)
	check(Quests.current().id != q0, "Recoger 5 de madera completa el primer objetivo")
	check(Quests.completed.has(q0), "El objetivo queda registrado como completado")


# ------------------------------------------------------------------ 12. Combate
func _test_combat() -> void:
	section("Enemigos y combate")
	var p := world.player
	p.global_position = _camp_pos() + Vector3(0, 0.5, 15)
	await physics_frames(3)
	var e := world.enemies._spawn("jabali", p.global_position + Vector3(3, 0.3, 0))
	await physics_frames(2)
	check(e != null and e.is_alive(), "Aparece un jabalí")
	var hp0 := e.hp
	e.take_damage(10.0, p.global_position)
	check(e.hp == hp0 - 10.0, "El enemigo recibe daño (%d → %d)" % [int(hp0), int(e.hp)])
	GameState.survival.health = 100.0
	p._iframes = 0.0
	p.take_damage(11.0, e.global_position, "jabali")
	var h1: float = GameState.survival.health
	check(h1 < 100.0, "El jugador recibe daño (%.0f)" % h1)
	p.take_damage(11.0, e.global_position, "jabali")
	check(GameState.survival.health == h1, "Los fotogramas de invulnerabilidad evitan el doble golpe")
	# La IA detecta y persigue.
	p._iframes = 99.0
	var start_d := e.global_position.distance_to(p.global_position)
	e.global_position = p.global_position + Vector3(7, 0.3, 0)
	await physics_frames(70)
	check(e.state in [Enemy.State.CHASE, Enemy.State.ATTACK], "El jabalí detecta y persigue al jugador")
	check(e.global_position.distance_to(p.global_position) < 7.0, "Se acerca al jugador (%.1f m)" % e.global_position.distance_to(p.global_position))
	# El ataque del jugador daña a los enemigos en el arco frontal.
	var d := e.global_position - p.global_position
	p.rig.rotation.y = atan2(-d.x, -d.z)
	e.global_position = p.global_position + p.forward_dir() * 1.5
	var hp1 := e.hp
	p._attack_cd = 0.0
	GameState.survival.stamina = 100.0
	p.attack()
	await get_tree().create_timer(0.3).timeout
	check(e.hp < hp1, "El ataque del jugador golpea al enemigo de enfrente")
	var kills_before := int(GameState.stats.kills.get("jabali", 0))
	e.take_damage(999.0, p.global_position)
	check(not e.is_alive(), "El enemigo muere al llegar a 0 de vida")
	check(int(GameState.stats.kills.get("jabali", 0)) == kills_before + 1, "La muerte se contabiliza")
	await frames(3)
	check(world.pickups_root.get_child_count() > 0, "Deja botín en el suelo")
	p._iframes = 0.0
	# Las criaturas nocturnas no entran en la luz.
	var lit_pos := Vector3.ZERO
	var lights := Economy.light_sources()
	check(not lights.is_empty(), "Las fogatas son fuentes de luz")
	if not lights.is_empty():
		lit_pos = lights[0].pos
		check(world.is_lit(lit_pos), "La zona de la fogata está iluminada")
		var sk := world.enemies._spawn("esqueleto", lit_pos + Vector3(float(lights[0].radius) + 6.0, 0.5, 0))
		check(not sk._can_enter(lit_pos + Vector3(1, 0, 0)), "Un esqueleto no puede entrar en la luz")
		sk.queue_free()
	# Una torre dispara a enemigos cercanos.
	TechTree.researched["con_defensas"] = true
	var tower := Economy.place_building("torre", _camp_pos() + Vector3(-14, 0, 10), 0.0, true)
	await frames(2)
	var tnode: Building = world.buildings.get_building_node(tower)
	var target := world.enemies._spawn("cangrejo", tnode.global_position + Vector3(5, 0.5, 0))
	var thp := target.hp
	tnode._tower_t = 0.0
	tnode._tower_update(0.016)
	await get_tree().create_timer(0.7).timeout
	check(not is_instance_valid(target) or target.hp < thp, "La torre de defensa daña a los enemigos")


# ------------------------------------------------------------------ 13. Muerte
func _test_death_and_backpack() -> void:
	section("Muerte y recuperación")
	var p := world.player
	GameState.inventory.clear()
	GameState.inventory.add("madera", 40)
	GameState.inventory.add("hacha_piedra", 1)
	GameState.lost_backpack = {}
	var death_pos := p.global_position
	p.survival.damage(9999.0)
	await frames(3)
	check(p.dead, "El jugador muere al llegar a 0 de salud")
	check(GameState.inventory.count("madera") == 20, "Pierde la mitad de los recursos que llevaba")
	check(GameState.inventory.count("hacha_piedra") == 1, "Las herramientas se conservan")
	check(int(GameState.lost_backpack.get("items", {}).get("madera", 0)) == 20, "Los recursos perdidos quedan en una mochila recuperable")
	world.hud.close_all()
	world.respawn_player()
	await physics_frames(3)
	check(not p.dead and GameState.survival.health > 0.0, "Reaparece con salud")
	p.global_position = death_pos + Vector3(0, 0.5, 0)
	world.recover_backpack()
	check(GameState.inventory.count("madera") == 40, "Recuperar la mochila devuelve lo perdido (sin duplicar)")
	check(GameState.lost_backpack.is_empty(), "La mochila desaparece tras recuperarla")


# ------------------------------------------------------------------ 14. Día y noche
func _test_day_night() -> void:
	section("Ciclo día/noche y supervivencia")
	var dn := world.day_night
	var got_night := [false]
	var got_day := [false]
	var c1 := func(_d): got_night[0] = true
	var c2 := func(_d): got_day[0] = true
	EventBus.night_started.connect(c1)
	EventBus.day_started.connect(c2)
	GameState.hour = 20.0
	dn.advance(1.0)
	check(got_night[0] and dn.is_night(), "Anochece a las 20:30")
	var day0 := GameState.day
	dn.skip_to_morning()
	check(got_day[0] and GameState.day == day0 + 1 and not dn.is_night(), "Dormir salta a la mañana del día siguiente")
	EventBus.night_started.disconnect(c1)
	EventBus.day_started.disconnect(c2)
	var sv := world.player.survival
	GameState.survival.hunger = 50.0
	GameState.survival.thirst = 50.0
	sv._process(60.0)
	check(GameState.survival.hunger < 50.0 and GameState.survival.hunger > 40.0, "El hambre baja suavemente (%.1f tras 1 min)" % GameState.survival.hunger)
	check(GameState.survival.thirst < 50.0 and GameState.survival.thirst > 40.0, "La sed baja suavemente (%.1f tras 1 min)" % GameState.survival.thirst)
	GameState.inventory.add("coco", 1)
	var slot := -1
	for i in GameState.inventory.slots.size():
		if GameState.inventory.slots[i] != null and GameState.inventory.slots[i].id == "coco":
			slot = i
	var t0: float = GameState.survival.thirst
	world.player.eat_slot(slot)
	check(GameState.survival.thirst > t0, "Comer un coco quita sed")


# ------------------------------------------------------------------ 15. Regiones
func _test_regions() -> void:
	section("Regiones desbloqueables")
	var ruins: Array = [0, 0]
	for poi in GameData.world.pois:
		if poi.id == "ruinas":
			ruins = poi.pos
	var rp := Vector3(ruins[0], 1, ruins[1])
	check(not world.is_walkable(rp), "La jungla está bloqueada al principio")
	var bridge := world.pois.poi_by_id("puente")
	check(not world.pois.on_bridge(bridge.world_pos), "El puente está roto")
	world.player.global_position = bridge.world_pos + Vector3(8, 1, 0)
	world.pois._try_unlock(bridge, world.pois.interactables.filter(func(x): return x.id == "puente")[0])
	check(not GameState.is_region_unlocked("jungla"), "Sin la tecnología no se repara el puente")
	TechTree.researched["con_puentes"] = true
	GameState.inventory.add("tablas", 30)
	GameState.inventory.add("cuerda", 20)
	GameState.inventory.add("madera", 30)
	world.pois._try_unlock(bridge, world.pois.interactables.filter(func(x): return x.id == "puente")[0])
	await frames(2)
	check(GameState.is_region_unlocked("jungla"), "Con tecnología y materiales se repara el puente")
	check(world.is_walkable(rp), "La jungla pasa a ser transitable")
	var c: Vector2 = world.pois.bridge_rect.center
	check(world.is_walkable(Vector3(c.x, 0.5, c.y)), "Se puede cruzar el río por el puente")


# ------------------------------------------------------------------ 16. Guardado
func _snapshot() -> Dictionary:
	return {"inv": GameState.inventory.all_items(), "buildings": Economy.buildings.size(), "storage": Economy.storage.duplicate(),
			"techs": TechTree.researched.size(), "quest": Quests.index, "workers": Workers.hired.size(),
			"hp": snappedf(float(GameState.survival.health), 0.01), "day": GameState.day, "regions": GameState.regions.size(),
			"levels": Economy.buildings.map(func(b): return int(b.level)), "weather": str(GameState.weather.get("state", ""))}


# ------------------------------------------------------------------ 15b. Pulido visual, clima y contenido
func _test_polish() -> void:
	section("Animaciones, efectos, clima y decoración")
	var p := world.player
	# Todos los shaders compilan (el renderizador de prueba los analiza igual que el real).
	var bad: Array[String] = []
	for f in DirAccess.get_files_at("res://assets/shaders"):
		if not f.ends_with(".gdshader"):
			continue
		var sh := Shader.new()
		sh.code = FileAccess.get_file_as_string("res://assets/shaders/" + f)
		if sh.get_shader_uniform_list().is_empty():
			bad.append(f)
	check(bad.is_empty(), "Todos los shaders compilan sin errores %s" % [bad])
	# Vegetación con viento: solo plantas y árboles, con peso creciente hacia la copa.
	check(ModelLibrary.sway_amount("pirate/palm-straight") > 0.5 and ModelLibrary.sway_amount("nature/grass") > 0.0, "Palmeras y hierba se mueven con el viento")
	check(ModelLibrary.sway_amount("nature/stone_largeA") == 0.0 and ModelLibrary.sway_amount("nature/stump_old") == 0.0, "Rocas y tocones no se mueven")
	var palm := ModelLibrary.baked_mesh("pirate/palm-straight")
	check(palm.surface_get_material(0) == ModelLibrary.foliage_material(), "Las palmeras usan el material con viento")
	var arr := ModelLibrary.baked_arrays("pirate/palm-straight")
	var lo := 1.0
	var hi := 0.0
	for k in (arr.v as PackedVector3Array).size():
		var a: float = (arr.c as PackedColorArray)[k].a
		lo = minf(lo, a)
		hi = maxf(hi, a)
	check(lo < 0.05 and hi > 0.8, "El peso del viento va de la base (%.2f) a la copa (%.2f)" % [lo, hi])
	# Animación procedural: acciones con duración, voltereta, muerte y aparición.
	var rig := ProceduralRig.new()
	add_child(rig)
	rig.build(Player.MODEL, "biped", Player.MODEL_SCALE)
	rig.idle_variations = false
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig._process(0.016)
	var rest: Vector3 = rig._pivots.arm_r.rotation
	rig.play_action("chop")
	for i in 14:
		rig._process(0.016)
	check(rig.is_acting() and rig._pivots.arm_r.rotation.distance_to(rest) > 0.5, "La tala mueve el brazo (%.2f rad)" % rig._pivots.arm_r.rotation.distance_to(rest))
	for i in 30:
		rig._process(0.016)
	check(not rig.is_acting(), "Las acciones terminan solas")
	rig.play_roll(0.4)
	for i in 12:
		rig._process(0.016)
	var mid_roll: bool = not rig._spin.transform.is_equal_approx(Transform3D.IDENTITY)
	for i in 20:
		rig._process(0.016)
	check(mid_roll and rig._spin.transform.is_equal_approx(Transform3D.IDENTITY), "La voltereta gira el cuerpo y vuelve a su sitio")
	rig.play_action("gather")
	for i in 15:
		rig._process(0.016)
	check(rig._root.rotation.x > 0.3, "Al recoger se inclina hacia delante (%.2f rad)" % rig._root.rotation.x)
	check(not rig._overlay_on, "Sin destello no se dibuja la capa superpuesta (ahorra llamadas)")
	rig.flash()
	rig._process(0.016)
	check(rig._overlay_on, "El destello de daño activa la capa superpuesta")
	rig.spawn_in()
	rig._process(0.016)
	var small: float = rig._root.scale.x
	for i in 40:
		rig._process(0.016)
	check(small < rig._base_scale * 0.6 and absf(rig._root.scale.x - rig._base_scale) < 0.05, "Las criaturas aparecen creciendo")
	rig.die()
	for i in 60:
		rig._process(0.016)
	check(absf(rig.rotation.x) > 1.3 or absf(rig.rotation.z) > 1.3, "Al morir cae al suelo")
	rig.queue_free()
	# El jugador anima sus acciones.
	p._iframes = 0.0
	GameState.survival.stamina = 100.0
	p._dodge_t = 0.0
	p.dodge()
	check(p.rig.is_rolling(), "Esquivar hace una voltereta")
	await physics_frames(30)
	GameState.inventory.add("bayas", 3)
	var slot := -1
	for i in GameState.inventory.slots.size():
		var sl: Variant = GameState.inventory.slots[i]
		if sl != null and sl.id == "bayas":
			slot = i
	p.eat_slot(slot)
	check(p.rig.action == "eat", "Comer tiene su animación")
	var tree_id := _nearest_node("palmera")
	if tree_id < 0:
		tree_id = _nearest_node("arbol")
	if tree_id >= 0:
		var trec: Dictionary = world.resources.get_node_rec(tree_id)
		GameState.inventory.add("hacha_piedra", 1)
		p.global_position = trec.pos + Vector3(1.4, 0.5, 0)
		await physics_frames(5)
		p._update_target()
		p._gather_cd = 0.0
		p.interact_pressed()
		check(p.rig.action == "chop", "Talar con hacha usa el gesto de tala")
	# Enemigos: aviso de detección, amago con destello e interrupción.
	p.global_position = _camp_pos() + Vector3(0, 0.5, 18)
	await physics_frames(3)
	var e := world.enemies._spawn("jabali", p.global_position + Vector3(5, 0.3, 0))
	await physics_frames(2)
	e.state = Enemy.State.IDLE
	e._think()
	check(e.state in [Enemy.State.CHASE, Enemy.State.ATTACK] and e.get_node_or_null("Aviso") != null, "Al detectarte muestra un «!» sobre la cabeza")
	e._attack_cd = 0.0
	e._attack_windup = -1.0
	e._set_chase_or_attack(0.5)
	check(e.rig.action == "windup" and e.rig._telegraph_t > 0.0, "Antes de atacar se echa atrás y parpadea en naranja")
	e.take_damage(1.0, p.global_position)
	check(e._attack_windup < 0.0, "Golpearle durante el amago interrumpe su ataque")
	e.queue_free()
	# Objetos caídos: arco, imán y recogida.
	var wood0 := GameState.inventory.count("madera")
	var drop := world.spawn_drop("madera", 2, p.global_position + Vector3(2.0, 0.0, 0.0))
	check(drop != null and drop._airborne, "El botín sale despedido en arco")
	for i in 120:
		await get_tree().process_frame
		if not is_instance_valid(drop):
			break
	check(not is_instance_valid(drop) and GameState.inventory.count("madera") == wood0 + 2, "El imán atrae el botín y se recoge sin duplicar")
	var own := world.spawn_drop("piedra", 1, p.global_position + Vector3(1.0, 0.0, 0.0), false, true)
	await get_tree().create_timer(1.0).timeout
	check(is_instance_valid(own), "Lo que suelta el propio jugador no vuelve solo a la mochila")
	if is_instance_valid(own):
		own.queue_free()
	# Clima: lluvia, tormenta y efectos sobre la economía y la sed.
	var wt: Weather = world.weather
	wt.force("lluvia", true)
	await frames(2)
	check(GameState.is_raining() and wt._rain_fx.emitting, "La lluvia se ve (partículas activas)")
	check(GameState.weather_thirst_mult() < 1.0, "Con lluvia la sed baja más despacio (x%.2f)" % GameState.weather_thirst_mult())
	TechTree.researched["agr_cultivo"] = true
	var hu := Economy.place_building("huerto", _camp_pos() + Vector3(14, 0, -12), 0.0, true)
	var hrec := Economy.get_building(hu)
	var ct_rain := Economy.cycle_time(hrec)
	wt.force("despejado", true)
	var ct_dry := Economy.cycle_time(hrec)
	check(ct_rain < ct_dry * 0.85, "Los huertos crecen más rápido con lluvia (%.1f s frente a %.1f s)" % [ct_rain, ct_dry])
	Economy._simulating = true
	wt.force("lluvia", true)
	var ct_sim := Economy.cycle_time(hrec)
	Economy._simulating = false
	check(absf(ct_sim - ct_dry) < 0.001, "El cálculo sin conexión no usa la bonificación de lluvia")
	wt.force("tormenta", true)
	wt._lightning()
	await frames(3)
	check(wt.flash > 0.0, "Los relámpagos iluminan la escena")
	world.day_night._apply_visuals()
	var sky: ShaderMaterial = world.env_node.environment.sky.sky_material
	check(float(sky.get_shader_parameter("cloud_cover")) > 0.8, "La tormenta cubre el cielo de nubes")
	wt.force("despejado", true)
	await frames(2)
	check(not wt._rain_fx.emitting, "Al despejar deja de llover")
	# Cielo de noche con estrellas y luna.
	var h0 := GameState.hour
	GameState.hour = 23.5
	world.day_night._apply_visuals()
	check(float(sky.get_shader_parameter("stars")) > 0.5 and float(sky.get_shader_parameter("moon_disc")) > 0.5, "De noche se ven estrellas y la luna")
	GameState.hour = 12.0
	world.day_night._apply_visuals()
	check(float(sky.get_shader_parameter("stars")) < 0.01 and float(sky.get_shader_parameter("sun_disc")) > 0.5, "De día se ve el sol y no las estrellas")
	GameState.hour = h0
	world.day_night._apply_visuals()
	# Tesoros en la orilla.
	var tr: BeachTreasures = world.treasures
	var n0 := tr.count()
	GameState.flags["tesoro_t"] = 0.0
	var spawned := tr.spawn_one()
	check(spawned and tr.count() == n0 + 1, "El mar deja tesoros en la playa")
	var xp0 := GameState.xp + GameState.level * 100000
	var got := tr.open(tr.count() - 1)
	check(not got.is_empty() and tr.count() == n0 and GameState.xp + GameState.level * 100000 > xp0, "Abrir un tesoro da botín y experiencia")
	check((GameState.flags.get("tesoros", []) as Array).size() == tr.count(), "Los tesoros sin abrir se guardan con la partida")
	# Decoración: belleza, caminos rápidos y aviso de edificio parado.
	var b0 := Economy.beauty()
	var deco := Economy.place_building("macetas", _camp_pos() + Vector3(-12, 0, -14), 0.0, true)
	var path_uid := Economy.place_building("camino", _camp_pos() + Vector3(-16, 0, -14), 0.0, true)
	await frames(2)
	check(Economy.beauty() > b0 and Economy.beauty_bonus() > 0.0, "Las decoraciones suman belleza (+%d %% producción)" % int(round(Economy.beauty_bonus() * 100.0)))
	var prec := Economy.get_building(path_uid)
	var ppos := Vector3(prec.pos[0], prec.pos[1], prec.pos[2])
	check(world.ground_speed_bonus(ppos) > 0.1 and world.surface_at(ppos) == "stone", "Los caminos de losas aceleran el paso y suenan a piedra")
	var pnode: Building = world.buildings.get_building_node(path_uid)
	check(pnode._body == null, "Los caminos no bloquean el paso")
	TechTree.researched["con_carpinteria"] = true
	var saw := Economy.place_building("aserradero", _camp_pos() + Vector3(-12, 0, 14), 0.0, true)
	Economy.storage.erase("madera")
	Economy.tick(0.5)
	await frames(2)
	var snode: Building = world.buildings.get_building_node(saw)
	snode._update_badge(Economy.get_building(saw), true)
	check(snode._badge != null and snode._badge.visible and snode._badge_key == "in:madera", "Un edificio parado muestra el material que le falta")
	var srec := Economy.get_building(saw)
	var hp_full := float(srec.hp)
	srec.hp = hp_full * 0.1
	snode._update_damage_fx(0.1)
	check(snode._dmg_fire != null, "Un edificio muy dañado arde")
	srec.hp = hp_full
	snode._update_damage_fx(1.0)
	check(snode._dmg_fire == null, "Al repararlo se apaga el fuego")
	for uid in [hu, deco, path_uid, saw]:
		Economy.demolish(uid)
	# Interfaz: rótulos, objetos que vuelan al contador y cierre animado.
	var hud: Node = world.hud
	EventBus.banner.emit("Prueba", "Rótulo", "level")
	await frames(1)
	check(hud._banner_layer.get_child_count() > 0, "Los rótulos grandes aparecen en pantalla")
	var cam := get_viewport().get_camera_3d()
	EventBus.item_collected_at.emit("madera", 1, cam.global_position - cam.global_transform.basis.z * 4.0)
	await frames(1)
	check(hud._fly_layer.get_child_count() > 0, "El objeto recogido vuela hasta su contador")
	hud.open_panel("inventory")
	await frames(2)
	hud.panels.inventory.close()
	check(not hud.panels.inventory.is_open and hud.panels.inventory.visible, "Las ventanas se cierran con una animación")
	await get_tree().create_timer(0.3).timeout
	check(not hud.panels.inventory.visible, "Al terminar la animación la ventana queda oculta")
	# Vida ambiental: luciérnagas de noche y no de día.
	var al: AmbientLife = world.ambient_life
	GameState.hour = 23.0
	al._zone = "pradera"
	al._zone_t = 99.0
	al._process(0.1)
	var night_ok: bool = al._fireflies.emitting
	GameState.hour = 12.0
	al._process(0.1)
	check(night_ok and not al._fireflies.emitting and al._pollen.emitting, "Luciérnagas de noche y polen de día en la pradera")
	GameState.hour = h0


func _test_save_load() -> void:
	section("Guardado y carga")
	SaveManager.enabled = true
	SaveManager.delete_save()
	world.player.sync_to_state()
	world.weather.force("nublado", true)
	var before := _snapshot()
	var pos_before := world.player.global_position
	check(SaveManager.save_game(), "Guardar partida en user://")
	check(FileAccess.file_exists(SaveManager.SAVE_PATH), "Existe el archivo de guardado")
	# Se altera el estado y se recarga.
	GameState.inventory.clear()
	Economy.reset()
	Workers.reset()
	TechTree.reset()
	Quests.reset()
	check(SaveManager.load_game(false), "Cargar partida")
	var after := _snapshot()
	check(after.inv == before.inv, "El inventario se restaura igual")
	check(after.buildings == before.buildings and after.levels == before.levels, "Edificios y niveles restaurados (%d)" % after.buildings)
	check(after.techs == before.techs and after.quest == before.quest, "Tecnologías y objetivos restaurados")
	check(after.workers == before.workers, "Trabajadores restaurados")
	check(after.storage == before.storage, "Almacén restaurado")
	check(after.hp == before.hp and after.day == before.day and after.regions == before.regions, "Supervivencia, día y regiones restaurados")
	check(GameState.player_pos.distance_to(pos_before) < 0.05, "Posición del jugador restaurada")
	check(str(GameState.weather.get("state", "")) == before.weather, "El clima se guarda y se restaura (%s)" % before.weather)
	# Cargar dos veces no duplica nada.
	SaveManager.load_game(false)
	check(_snapshot().buildings == before.buildings and _snapshot().inv == before.inv, "Cargar dos veces no duplica edificios ni objetos")
	# Guardado dañado: se usa la copia de seguridad.
	SaveManager.save_game()
	SaveManager.save_game()
	var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{corrupto")
	f.close()
	check(SaveManager.load_game(false), "Con el archivo principal dañado se recupera la copia de seguridad")
	check(_snapshot().buildings == before.buildings, "La copia de seguridad contiene la partida")
	SaveManager.save_game()
	var f2 := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
	var doc2: Variant = JSON.parse_string(f2.get_as_text())
	f2.close()
	check(typeof(doc2) == TYPE_DICTIONARY and doc2.has("checksum") and doc2.has("saved_at"), "El guardado incluye fecha y suma de verificación")
	var tampered: Dictionary = doc2
	tampered.payload.game.level = 99
	var f3 := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	f3.store_string(JSON.stringify(tampered))
	f3.close()
	check(SaveManager._read_doc(SaveManager.SAVE_PATH).is_empty(), "Un guardado manipulado se detecta por la suma de verificación")
	SaveManager.enabled = false


# ------------------------------------------------------------------ 17. Sin conexión
func _test_offline() -> void:
	section("Progreso sin conexión")
	Economy.reset()
	Workers.reset()
	Economy.place_building("lenador", Vector3(0, 5, 0), 0.0, true)
	var hunger0: float = GameState.survival.hunger
	var rep := SaveManager.apply_offline_progress(1800.0)
	check(int(rep.get("items", {}).get("madera", 0)) == 120, "30 min sin conexión con un leñador = 120 de madera (%d)" % int(rep.get("items", {}).get("madera", 0)))
	check(GameState.survival.hunger == hunger0, "El hambre no baja sin conexión")
	Economy.storage.clear()
	var rep2 := SaveManager.apply_offline_progress(48.0 * 3600.0)
	check(rep2.capped, "El tiempo sin conexión se limita a %.0f h" % float(rep2.cap_hours))
	check(Economy.stored("madera") <= Economy.capacity(), "Respeta la capacidad del almacén (%d/%d)" % [Economy.stored("madera"), Economy.capacity()])
	var rep3 := SaveManager.apply_offline_progress(30.0)
	check(rep3.is_empty(), "Ausencias muy cortas no generan informe")
	var rep4 := SaveManager.apply_offline_progress(-500.0)
	check(rep4.is_empty(), "Un reloj atrasado no genera recursos")


# ------------------------------------------------------------------ 18. Interfaz
func _all_buttons(n: Node, out: Array) -> void:
	if n is BaseButton:
		out.append(n)
	for c in n.get_children():
		_all_buttons(c, out)


func _test_ui_scaling_and_buttons() -> void:
	section("Interfaz: escalado y botones")
	var hud: Node = world.hud
	var root_ctrl: Control = hud.root
	for size in [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(854, 480), Vector2i(1024, 768)]:
		get_tree().root.size = size
		await frames(3)
		var vp := root_ctrl.get_viewport_rect().size
		var inside := true
		for ctrl in [hud.interact_btn, hud.joystick, hud.quest_box, hud.clock_label]:
			var r: Rect2 = (ctrl as Control).get_global_rect()
			if r.position.x < -1 or r.position.y < -1 or r.end.x > vp.x + 1 or r.end.y > vp.y + 1:
				inside = false
		check(inside, "Controles principales dentro de pantalla a %dx%d" % [size.x, size.y])
	get_tree().root.size = Vector2i(1280, 720)
	await frames(2)
	var dead: Array[String] = []
	var total := 0
	for key in hud.panels:
		var p: UIPanel = hud.panels[key]
		var arg: Variant = null
		if key == "building":
			arg = int(Economy.buildings[0].uid) if not Economy.buildings.is_empty() else null
		elif key == "offline":
			arg = {"elapsed": 3600.0, "items": {"madera": 10}}
		if key == "building" and arg == null:
			continue
		hud.open_panel(key, arg)
		await frames(2)
		check(p.is_open and p.visible, "El panel «%s» se abre" % key)
		if key == "inventory" or key == "build" or key == "crafting" or key == "stats":
			# Recorre también las pestañas para generar todos los botones.
			var tabs: TabBar = p.get("tabs") if p.get("tabs") else p.get("_tabs")
			if tabs:
				for t in tabs.tab_count:
					tabs.current_tab = t
					await frames(1)
					var bl: Array = []
					_all_buttons(p, bl)
					for b in bl:
						total += 1
						if b.get_signal_connection_list("pressed").is_empty() and b.get_signal_connection_list("button_down").is_empty():
							dead.append("%s/%s" % [key, b.name])
		var bl2: Array = []
		_all_buttons(p, bl2)
		for b in bl2:
			total += 1
			if b.get_signal_connection_list("pressed").is_empty() and b.get_signal_connection_list("button_down").is_empty():
				dead.append("%s/%s(%s)" % [key, b.name, b.get("text") if b.get("text") else ""])
		p.close()
		get_tree().paused = false
	var hud_buttons: Array = []
	for c in root_ctrl.get_children():
		if not (c is UIPanel):
			_all_buttons(c, hud_buttons)
	for b in hud_buttons:
		total += 1
		if b.get_signal_connection_list("pressed").is_empty() and b.get_signal_connection_list("button_down").is_empty():
			dead.append("hud/" + b.name)
	check(dead.is_empty(), "Ningún botón sin función (%d revisados) %s" % [total, dead.slice(0, 8)])


# ------------------------------------------------------------------ 19. Rendimiento
func _count(n: Node, acc: Dictionary) -> void:
	if n is MultiMeshInstance3D:
		acc.mmi = int(acc.get("mmi", 0)) + 1
		acc.instances = int(acc.get("instances", 0)) + (n as MultiMeshInstance3D).multimesh.instance_count
	elif n is MeshInstance3D:
		acc.mesh = int(acc.get("mesh", 0)) + 1
	elif n is OmniLight3D:
		acc.lights = int(acc.get("lights", 0)) + 1
	elif n is CPUParticles3D or n is GPUParticles3D:
		acc.particles = int(acc.get("particles", 0)) + 1
	elif n is PhysicsBody3D:
		acc.bodies = int(acc.get("bodies", 0)) + 1
	for c in n.get_children():
		_count(c, acc)


func _test_performance() -> void:
	section("Rendimiento (estimación sin GPU)")
	var acc := {}
	_count(world, acc)
	lines.append("  · MultiMesh: %d con %d instancias · Mallas sueltas: %d · Luces: %d · Partículas: %d · Cuerpos físicos: %d" % [
		int(acc.get("mmi", 0)), int(acc.get("instances", 0)), int(acc.get("mesh", 0)), int(acc.get("lights", 0)), int(acc.get("particles", 0)), int(acc.get("bodies", 0))])
	check(int(acc.get("mmi", 0)) < 220, "Vegetación agrupada en pocos MultiMesh (%d)" % int(acc.get("mmi", 0)))
	check(int(acc.get("lights", 0)) <= 16, "Pocas luces dinámicas (%d)" % int(acc.get("lights", 0)))
	check(world.gen_time_ms < 6000, "La isla se genera en %d ms (escritorio)" % world.gen_time_ms)
	var t0 := Time.get_ticks_usec()
	for i in 200:
		Economy.tick(0.25)
	var per_tick := (Time.get_ticks_usec() - t0) / 200.0
	check(per_tick < 2000.0, "Un tick de producción cuesta %.0f µs" % per_tick)
	t0 = Time.get_ticks_usec()
	Economy.simulate(8.0 * 3600.0)
	var sim_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(sim_ms < 3000.0, "Simular 8 h sin conexión tarda %.0f ms" % sim_ms)
