class_name SettingsPanel
extends UIPanel
## Pausa y ajustes: sensibilidad, volúmenes, calidad gráfica, límite de FPS,
## escala de interfaz, guardar y salir al menú.

var content: VBoxContainer
var credits_label: RichTextLabel


func _init() -> void:
	super()
	title = "Pausa · Ajustes"
	size_ratio = Vector2(0.8, 0.94)
	pauses_game = true
	process_mode = Node.PROCESS_MODE_ALWAYS


func _build() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	top.add_child(UITheme.button("Continuar", close, Vector2(180, 54)))
	top.add_child(UITheme.button("Guardar partida", func():
		if SaveManager.save_game():
			EventBus.notify("Partida guardada.", "good")
		else:
			EventBus.notify("No se pudo guardar: %s" % SaveManager.last_error, "bad"), Vector2(220, 54)))
	top.add_child(UITheme.button("Créditos", func(): credits_label.visible = not credits_label.visible, Vector2(160, 54)))
	var quit := UITheme.button("Salir al menú", _quit_to_menu, Vector2(200, 54))
	quit.add_theme_stylebox_override("normal", UITheme.box("button_red", 14, 12))
	top.add_child(quit)
	credits_label = RichTextLabel.new()
	credits_label.bbcode_enabled = true
	credits_label.fit_content = true
	credits_label.visible = false
	credits_label.text = _credits_text()
	body.add_child(credits_label)
	content = make_scroll()


func _credits_text() -> String:
	return "[b]Isla Salvaje: Supervivencia Incremental[/b]\nModelos 3D, interfaz, iconos de controles y gran parte del audio: [b]Kenney[/b] (kenney.nl, CC0). Música: Kevin MacLeod vía FreePD (CC0) y Kenney Music Loops (CC0). Grabaciones de campo y efectos: autores de Freesound y OpenGameArt (CC0). Fuentes: Fredoka y Nunito (SIL OFL). Lista completa en ASSET_CREDITS.md."


func refresh() -> void:
	UIPanel.clear_children(content)
	_slider("Sensibilidad de cámara", "sensitivity", 0.3, 2.5, 0.05)
	_slider("Distancia de cámara", "camera_distance", 3.5, 11.0, 0.5)
	_slider("Volumen general", "volume_master", 0.0, 1.0, 0.05)
	_slider("Música", "volume_music", 0.0, 1.0, 0.05)
	_slider("Efectos", "volume_sfx", 0.0, 1.0, 0.05)
	_slider("Ambiente", "volume_ambient", 0.0, 1.0, 0.05)
	_options("Calidad gráfica", "quality", [["baja", "Baja"], ["media", "Media"], ["alta", "Alta"]])
	_options("Límite de FPS", "fps_limit", [[30, "30"], [60, "60"], [0, "Sin límite"]])
	_options("Escala de interfaz", "ui_scale", [[0.85, "85%"], [1.0, "100%"], [1.15, "115%"], [1.3, "130%"]])
	_toggle("Invertir eje vertical", "invert_y")
	_toggle("Mostrar FPS", "show_fps")


func _row(text: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var l := UITheme.label(text, 19)
	l.custom_minimum_size = Vector2(280, 0)
	hb.add_child(l)
	content.add_child(hb)
	return hb


func _slider(text: String, key: String, mn: float, mx: float, step: float) -> void:
	var hb := _row(text)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(360, 44)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := UITheme.label("%.2f" % s.value, 18)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v):
		val.text = "%.2f" % v
		Settings.set_value(key, v))
	s.drag_ended.connect(func(_c): AudioManager.play_ui("ui/tick"))
	hb.add_child(s)
	hb.add_child(val)


func _options(text: String, key: String, opts: Array) -> void:
	var hb := _row(text)
	for o in opts:
		var b := UITheme.button(str(o[1]), func():
			Settings.set_value(key, o[0])
			refresh(), Vector2(130, 50))
		var cur: Variant = Settings.get_value(key)
		if (typeof(o[0]) == TYPE_STRING and str(cur) == o[0]) or (typeof(o[0]) != TYPE_STRING and absf(float(cur) - float(o[0])) < 0.001):
			b.add_theme_stylebox_override("normal", UITheme.box("button_brown", 14, 12, Color(0.75, 1.0, 0.7)))
			b.text = "» " + b.text + " «"
		hb.add_child(b)


func _toggle(text: String, key: String) -> void:
	var hb := _row(text)
	var on := bool(Settings.get_value(key))
	var b := UITheme.button("Sí" if on else "No", func():
		Settings.set_value(key, not bool(Settings.get_value(key)))
		refresh(), Vector2(120, 50))
	hb.add_child(b)


func _quit_to_menu() -> void:
	SaveManager.save_game()
	close()
	get_tree().paused = false
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("go_to_menu"):
		main.go_to_menu()
	else:
		get_tree().quit()
