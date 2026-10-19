extends Node
## Flujo completo desde el menú principal: nueva partida, guardar, volver al
## menú y continuar con progreso sin conexión.
## Uso: godot --headless --path . tests/main_flow.tscn

var ok := true


func expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ FALLO: ") + msg)
	if not cond:
		ok = false


func _ready() -> void:
	SaveManager.delete_save()
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	expect(main.current != null and main.current.name == "MainMenu", "Se muestra el menú principal")
	expect(main.current.get_node_or_null("VBoxContainer/BtnContinuar") == null, "Sin partida no aparece «Continuar»")
	await main.new_game()
	for i in 10:
		await get_tree().process_frame
	expect(main.current is World, "«Nueva partida» carga la isla")
	expect(SaveManager.has_save(), "La nueva partida se guarda automáticamente")
	var world: World = main.current
	Economy.place_building("lenador", world.player.global_position + Vector3(5, 0, 0), 0.0, true)
	GameState.give("madera", 7)
	expect(SaveManager.save_game(), "Guardado manual")
	main.go_to_menu()
	await get_tree().process_frame
	expect(main.current.name == "MainMenu", "Salir al menú")
	# Se simulan 2 horas de ausencia retrasando la fecha del guardado.
	var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	doc.saved_at = float(doc.saved_at) - 7200.0
	var w := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	w.store_string(JSON.stringify(doc))
	w.close()
	await main.continue_game()
	for i in 60:
		await get_tree().process_frame
	expect(main.current is World, "«Continuar» carga la partida")
	expect(GameState.inventory.count("madera") == 7, "El inventario se conserva al continuar")
	expect(Economy.count_of("lenador") == 1, "El edificio se conserva (sin duplicados)")
	var hud: Node = main.current.hud
	expect(hud.panels.offline.is_open, "Se muestra el resumen de bienvenida con lo producido offline")
	expect(Economy.stored("madera") > 0, "El leñador produjo madera durante la ausencia (%d)" % Economy.stored("madera"))
	SaveManager.delete_save()
	print("RESULTADO FLUJO: ", "OK" if ok else "FALLOS")
	get_tree().quit(0 if ok else 1)
