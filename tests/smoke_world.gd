extends Node
## Carga el mundo completo en modo headless y lo ejecuta unos segundos.
## Uso: godot --headless --path . tests/smoke_world.tscn

func _ready() -> void:
	SaveManager.enabled = false
	TechTree.reset()
	GameState.new_game()
	Economy.reset()
	Workers.reset()
	Quests.reset()
	var t0 := Time.get_ticks_msec()
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	print("Instanciado en ", Time.get_ticks_msec() - t0, " ms")
	for i in 120:
		await get_tree().process_frame
	var p: Node3D = world.player
	print("Jugador en ", p.global_position, " suelo=", world.height_at(p.global_position.x, p.global_position.z), " zona=", world.gen.zone_at(p.global_position.x, p.global_position.z))
	print("Nodos: ", world.resources.nodes.size(), " enemigos: ", world.enemies.enemies().size())
	print("Errores de datos: ", GameData.validate())
	get_tree().quit(0)
