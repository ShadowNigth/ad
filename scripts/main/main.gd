extends Node
## Punto de entrada: menú principal y carga de la partida.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const MENU_SCENE := "res://scenes/main/main_menu.tscn"

var current: Node
var loading_layer: CanvasLayer


func _ready() -> void:
	add_to_group("main")
	get_tree().set_auto_accept_quit(false)
	go_to_menu()


func _clear() -> void:
	if current:
		current.queue_free()
		current = null


func go_to_menu() -> void:
	GameState.session_active = false
	Economy.running = false
	Quests.active = false
	get_tree().paused = false
	_clear()
	current = load(MENU_SCENE).instantiate()
	add_child(current)
	AudioManager.stop_ambient()
	AudioManager.set_mood("menu")


func new_game() -> void:
	TechTree.reset()
	GameState.new_game()
	Economy.reset()
	Workers.reset()
	Quests.reset()
	SaveManager.pending_report = {}
	await _start_world()
	SaveManager.save_game()


func continue_game() -> void:
	if not SaveManager.load_game(true):
		EventBus.notify("No se pudo cargar la partida: %s" % SaveManager.last_error, "bad")
		return
	await _start_world()


func _start_world() -> void:
	_clear()
	_show_loading(true)
	await get_tree().process_frame
	await get_tree().process_frame
	current = load(WORLD_SCENE).instantiate()
	add_child(current)
	_show_loading(false)


func _show_loading(on: bool) -> void:
	if on:
		loading_layer = CanvasLayer.new()
		loading_layer.layer = 50
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.12, 0.12)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		loading_layer.add_child(bg)
		var l := UITheme.hud_label("Generando la isla...", 34)
		l.set_anchors_preset(Control.PRESET_CENTER)
		l.offset_left = -300
		l.offset_right = 300
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loading_layer.add_child(l)
		add_child(loading_layer)
	elif loading_layer:
		loading_layer.queue_free()
		loading_layer = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if GameState.session_active:
			SaveManager.save_game()
		get_tree().quit()
