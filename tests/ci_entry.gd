extends Node
## Punto de entrada de la build EXPORTADA de pruebas (preset «Linux (pruebas CI)»).
## Ese preset activa la característica «pruebas_ci», que en project.godot cambia la
## escena principal a esta. Así las pruebas se ejecutan sobre el juego tal como se
## distribuye (PCK, recursos importados, scripts compilados) y no sólo en el editor.
## Uso: ./IslaSalvaje-pruebas.x86_64 --headless -- unitarias|flujo


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := "res://tests/main_flow.tscn" if args.has("flujo") else "res://tests/test_runner.tscn"
	print("Build exportada (%s): ejecutando %s" % [OS.get_name(), scene])
	get_tree().change_scene_to_file.call_deferred(scene)
