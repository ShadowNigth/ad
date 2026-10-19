extends Node
## Guardado y carga en user:// con escritura atómica, copia de seguridad y
## suma de verificación. Calcula el progreso sin conexión al cargar.

const SAVE_PATH := "user://savegame.json"
const TMP_PATH := "user://savegame.tmp"
const BAK_PATH := "user://savegame.bak"

var pending_report: Dictionary = {}
var last_error: String = ""
var last_save_time: float = 0.0
var _autosave_timer := 0.0
var _focus_save_cooldown := 0.0
## Si es false no se guarda nada (p. ej. en el menú o durante las pruebas).
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_focus_save_cooldown -= delta
	if not GameState.session_active:
		return
	GameState.playtime += delta
	_autosave_timer += delta
	if _autosave_timer >= GameData.bf("save.autosave_interval", 60.0):
		_autosave_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if GameState.session_active:
				save_game()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if GameState.session_active and _focus_save_cooldown <= 0.0:
				_focus_save_cooldown = 5.0
				save_game()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BAK_PATH)


func delete_save() -> void:
	for p in [SAVE_PATH, TMP_PATH, BAK_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func build_payload() -> Dictionary:
	get_tree().call_group("saveable", "sync_to_state")
	return {
		"game": GameState.to_dict(),
		"economy": Economy.to_dict(),
		"workers": Workers.to_dict(),
		"tech": TechTree.to_dict(),
		"quests": Quests.to_dict(),
	}


static func checksum(payload_json: String) -> String:
	return payload_json.sha256_text()


func save_game() -> bool:
	if not enabled:
		return false
	var payload := build_payload()
	# Forma canónica: tras un ciclo de serialización los números quedan como
	# los leerá JSON.parse_string, así la suma de verificación es estable.
	var canonical: Variant = JSON.parse_string(JSON.stringify(payload))
	payload = canonical
	var payload_json := JSON.stringify(payload)
	var doc := {
		"version": int(GameData.b("save.version", 1)),
		"saved_at": GameState.now(),
		"checksum": checksum(payload_json),
		"payload": payload,
	}
	var text := JSON.stringify(doc)
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		last_error = "No se pudo escribir el archivo temporal (%s)" % error_string(FileAccess.get_open_error())
		push_error(last_error)
		return false
	f.store_string(text)
	f.flush()
	f.close()
	# Verifica lo escrito antes de reemplazar la partida buena.
	if _read_doc(TMP_PATH).is_empty():
		last_error = "La verificación del guardado falló"
		push_error(last_error)
		return false
	var dir := DirAccess.open("user://")
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BAK_PATH):
			dir.remove(BAK_PATH.get_file())
		dir.rename(SAVE_PATH.get_file(), BAK_PATH.get_file())
	var err := dir.rename(TMP_PATH.get_file(), SAVE_PATH.get_file())
	if err != OK:
		last_error = "No se pudo renombrar el guardado (%s)" % error_string(err)
		push_error(last_error)
		return false
	last_save_time = GameState.now()
	EventBus.game_saved.emit()
	return true


## Lee y valida un documento de guardado. Devuelve {} si está dañado.
func _read_doc(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var doc: Dictionary = parsed
	if not doc.has("payload") or typeof(doc.payload) != TYPE_DICTIONARY:
		return {}
	if checksum(JSON.stringify(doc.payload)) != str(doc.get("checksum", "")):
		return {}
	return doc


## Carga la partida (o la copia de seguridad si la principal está dañada).
## Devuelve true si se cargó. Rellena pending_report con el progreso offline.
func load_game(apply_offline: bool = true) -> bool:
	last_error = ""
	var doc := _read_doc(SAVE_PATH)
	var used_backup := false
	if doc.is_empty():
		doc = _read_doc(BAK_PATH)
		used_backup = not doc.is_empty()
	if doc.is_empty():
		last_error = "No hay partida válida"
		return false
	var payload: Dictionary = doc.payload
	TechTree.from_dict(payload.get("tech", {}))
	GameState.from_dict(payload.get("game", {}))
	Economy.from_dict(payload.get("economy", {}))
	Workers.from_dict(payload.get("workers", {}))
	Quests.from_dict(payload.get("quests", {}))
	GameState.apply_capacity_bonuses()
	pending_report = {}
	if used_backup:
		EventBus.notify("La partida principal estaba dañada: se recuperó la copia de seguridad.", "warn")
	if apply_offline:
		var elapsed: float = GameState.now() - float(doc.get("saved_at", GameState.now()))
		pending_report = apply_offline_progress(elapsed)
	EventBus.game_loaded.emit()
	return true


func offline_cap_seconds() -> float:
	return (GameData.bf("economy.offline_cap_hours", 8.0) + TechTree.mod("offline_cap_hours")) * 3600.0


## Aplica la producción de edificios durante el tiempo ausente (con tope).
func apply_offline_progress(elapsed: float) -> Dictionary:
	if elapsed < GameData.bf("economy.offline_min_seconds", 60.0):
		return {}
	var capped := clampf(elapsed, 0.0, offline_cap_seconds())
	var summary := Economy.simulate(capped)
	summary["elapsed"] = elapsed
	summary["capped"] = elapsed > capped
	summary["cap_hours"] = offline_cap_seconds() / 3600.0
	return summary
