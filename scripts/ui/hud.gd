extends CanvasLayer
## Interfaz principal: barras de supervivencia, reloj, recursos, nivel,
## objetivo activo, joystick, cámara táctil, botones de acción, menús,
## avisos, textos flotantes y ventanas.

var world: World
var player: Player
var root: Control
var joystick: TouchJoystick
var look_area: TouchLook
var bars: Dictionary = {}
var clock_label: Label
var age_label: Label
var res_labels: Dictionary = {}
var level_label: Label
var xp_bar: ProgressBar
var points_label: Label
var quest_title: Label
var quest_desc: Label
var quest_bar: ProgressBar
var quest_count: Label
var quest_box: PanelContainer
var interact_btn: TextureButton
var interact_label: Label
var interact_icon: TextureRect
var action_box: Control
var build_box: Control
var build_reason: Label
var toast_box: VBoxContainer
var float_layer: Control
var vignette: TextureRect
var boss_box: PanelContainer
var boss_bar: ProgressBar
var boss_label: Label
var fps_label: Label
var save_icon: TextureRect
var panels: Dictionary = {}
var _floats: Array = []
var _toast_queue: Array = []
var _danger := false
var _low_health := false
var _update_t := 0.0
var _quest_flash := 0.0
var _quest_target := 0.0
var _banner_layer: Control
var _banner_queue: Array = []
var _banner_busy := false
var _fly_layer: Control
var _flyers := 0
var _time := 0.0
var _last_target_key := ""
var weather_label: Label

const RES_SHOWN := ["madera", "piedra", "fibra", "tablas", "lingote_hierro"]


func setup(w: World) -> void:
	world = w
	player = w.player
	layer = 10
	_build()
	_connect()
	_refresh_all()
	if not SaveManager.pending_report.is_empty():
		var rep := SaveManager.pending_report
		SaveManager.pending_report = {}
		get_tree().create_timer(0.6).timeout.connect(func(): open_panel("offline", rep))
	elif Quests.index == 0 and GameState.playtime < 5.0:
		get_tree().create_timer(1.5).timeout.connect(func():
			toast("¡Has naufragado en una isla salvaje! Recoge madera y piedra para sobrevivir.", "info"))


# ------------------------------------------------------------------ construcción
func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	# Zona de cámara (derecha) y joystick (izquierda) primero: quedan debajo de los botones.
	look_area = TouchLook.new()
	look_area.anchor_left = 0.38
	look_area.anchor_right = 1.0
	look_area.anchor_top = 0.0
	look_area.anchor_bottom = 1.0
	root.add_child(look_area)
	look_area.look.connect(func(d): player.add_look(d))
	look_area.zoom.connect(func(a): player.zoom(a))
	joystick = TouchJoystick.new()
	joystick.anchor_left = 0.0
	joystick.anchor_right = 0.38
	joystick.anchor_top = 0.42
	joystick.anchor_bottom = 1.0
	root.add_child(joystick)
	joystick.moved.connect(func(v, s): player.set_touch_move(v, s))
	vignette = TextureRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.texture = _vignette_texture()
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.modulate = Color(1, 1, 1, 0)
	root.add_child(vignette)
	float_layer = Control.new()
	float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(float_layer)
	_banner_layer = Control.new()
	_banner_layer.name = "Rotulos"
	_banner_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner_layer)
	_build_status()
	_build_top()
	_build_quest()
	_build_actions()
	_build_build_controls()
	_build_toasts()
	_build_boss()
	_fly_layer = Control.new()
	_fly_layer.name = "Recogidas"
	_fly_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fly_layer)
	_build_panels()


func _vignette_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.65, 0.0, 0.0, 0.75))
	g.add_point(0.62, Color(0.6, 0.0, 0.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 256
	gt.height = 256
	return gt


func _build_status() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat(Color(0.1, 0.07, 0.04, 0.45), 14))
	panel.position = Vector2(14, 12)
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var defs := [["health", "Salud", "red", "icon_star"], ["hunger", "Hambre", "green", ""], ["thirst", "Sed", "blue", ""], ["stamina", "Estamina", "white", ""]]
	var icons := {"health": UITheme.icon("star"), "hunger": GameData.item_icon("carne_cocida"), "thirst": GameData.item_icon("agua"), "stamina": UITheme.ctrl("icon_jump")}
	for d in defs:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		var ic := TextureRect.new()
		ic.texture = icons[d[0]]
		ic.custom_minimum_size = Vector2(30, 30)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if d[0] == "health":
			ic.modulate = Color(1, 0.4, 0.4)
		hb.add_child(ic)
		var pb := UITheme.progress_bar(d[2], 24)
		pb.custom_minimum_size = Vector2(190, 24)
		pb.tooltip_text = d[1]
		hb.add_child(pb)
		var l := UITheme.hud_label("100", 16)
		l.custom_minimum_size = Vector2(36, 0)
		hb.add_child(l)
		vb.add_child(hb)
		ic.pivot_offset = Vector2(15, 15)
		bars[d[0]] = {"bar": pb, "label": l, "icon": ic, "target": 1.0}


func _build_top() -> void:
	# Reloj y edad (centro superior).
	var clock := PanelContainer.new()
	clock.add_theme_stylebox_override("panel", UITheme.flat(Color(0.1, 0.07, 0.04, 0.5), 14))
	clock.anchor_left = 0.5
	clock.anchor_right = 0.5
	clock.offset_left = -130
	clock.offset_right = 130
	clock.offset_top = 10
	root.add_child(clock)
	var cvb := VBoxContainer.new()
	cvb.alignment = BoxContainer.ALIGNMENT_CENTER
	cvb.add_theme_constant_override("separation", 0)
	clock.add_child(cvb)
	clock_label = UITheme.hud_label("Día 1 · 08:00", 22)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cvb.add_child(clock_label)
	age_label = UITheme.hud_label("Edad primitiva", 15)
	age_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cvb.add_child(age_label)
	weather_label = UITheme.hud_label("", 14)
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weather_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	weather_label.visible = false
	cvb.add_child(weather_label)
	# Menú (derecha superior).
	var menu := HBoxContainer.new()
	menu.anchor_left = 1.0
	menu.anchor_right = 1.0
	menu.offset_left = -486
	menu.offset_right = -12
	menu.offset_top = 10
	menu.alignment = BoxContainer.ALIGNMENT_END
	menu.add_theme_constant_override("separation", 6)
	root.add_child(menu)
	var entries := [
		["inventory", "open", "Inventario (I)"], ["crafting", "wrench", "Fabricación (C)"], ["build", "home", "Construir (B)"],
		["tech", "star", "Tecnologías (T)"], ["workers", "multiplayer", "Trabajadores"], ["map", "zoom", "Mapa (M)"],
		["stats", "barsVertical", "Producción (P)"], ["settings", "gear", "Ajustes (Esc)"],
	]
	for e in entries:
		var ic: Texture2D = UITheme.icon(e[1])
		if ic == null:
			ic = UITheme.ctrl("icon_menu")
		var b := UITheme.round_button(ic, open_panel.bind(e[0]), 54.0)
		b.tooltip_text = e[2]
		b.name = "Btn_" + e[0]
		menu.add_child(b)
	# Recursos, nivel y puntos (debajo del menú).
	var info := HBoxContainer.new()
	info.anchor_left = 1.0
	info.anchor_right = 1.0
	info.offset_left = -640
	info.offset_right = -14
	info.offset_top = 72
	info.alignment = BoxContainer.ALIGNMENT_END
	info.add_theme_constant_override("separation", 12)
	root.add_child(info)
	for id in RES_SHOWN:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		hb.add_child(UITheme.item_icon(id, 30))
		var l := UITheme.hud_label("0", 18)
		hb.add_child(l)
		hb.tooltip_text = GameData.item_name(id)
		info.add_child(hb)
		res_labels[id] = {"label": l, "box": hb}
		hb.resized.connect(func(): hb.pivot_offset = hb.size * 0.5)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 0)
	level_label = UITheme.hud_label("Nivel 1", 17)
	lv.add_child(level_label)
	xp_bar = UITheme.progress_bar("blue", 14)
	xp_bar.custom_minimum_size = Vector2(110, 14)
	lv.add_child(xp_bar)
	info.add_child(lv)
	points_label = UITheme.hud_label("0 PT", 18)
	points_label.tooltip_text = "Puntos de tecnología"
	info.add_child(points_label)
	fps_label = UITheme.hud_label("", 14)
	fps_label.anchor_left = 0.5
	fps_label.anchor_right = 0.5
	fps_label.anchor_top = 1.0
	fps_label.anchor_bottom = 1.0
	fps_label.offset_left = -120
	fps_label.offset_right = 120
	fps_label.offset_top = -28
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(fps_label)
	save_icon = TextureRect.new()
	save_icon.texture = UITheme.icon("save")
	save_icon.custom_minimum_size = Vector2(28, 28)
	save_icon.size = Vector2(28, 28)
	save_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	save_icon.anchor_left = 1.0
	save_icon.anchor_right = 1.0
	save_icon.anchor_top = 1.0
	save_icon.anchor_bottom = 1.0
	save_icon.offset_left = -40
	save_icon.offset_top = -40
	save_icon.modulate = Color(1, 1, 1, 0)
	save_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(save_icon)


func _build_quest() -> void:
	quest_box = PanelContainer.new()
	quest_box.add_theme_stylebox_override("panel", UITheme.flat(Color(0.1, 0.07, 0.04, 0.5), 14))
	quest_box.position = Vector2(14, 160)
	quest_box.custom_minimum_size = Vector2(300, 0)
	root.add_child(quest_box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	quest_box.add_child(vb)
	var hb := HBoxContainer.new()
	var star := TextureRect.new()
	star.texture = UITheme.tex("minimap_icon_exclamation_yellow")
	star.custom_minimum_size = Vector2(14, 26)
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(star)
	quest_title = UITheme.hud_label("Objetivo", 19)
	quest_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(quest_title)
	quest_count = UITheme.hud_label("0/0", 17)
	hb.add_child(quest_count)
	vb.add_child(hb)
	quest_desc = UITheme.hud_label("", 15)
	quest_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_desc.custom_minimum_size = Vector2(290, 0)
	vb.add_child(quest_desc)
	quest_bar = UITheme.progress_bar("green", 14)
	vb.add_child(quest_bar)
	quest_box.gui_input.connect(func(ev):
		if ev is InputEventScreenTouch and ev.pressed:
			quest_desc.visible = not quest_desc.visible)


func _build_actions() -> void:
	action_box = Control.new()
	action_box.anchor_left = 1.0
	action_box.anchor_right = 1.0
	action_box.anchor_top = 1.0
	action_box.anchor_bottom = 1.0
	action_box.offset_left = -360
	action_box.offset_top = -330
	action_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(action_box)
	interact_btn = UITheme.round_button(UITheme.ctrl("icon_hand"), func(): pass, 136.0)
	interact_btn.name = "BtnInteractuar"
	interact_btn.position = Vector2(200, 170)
	interact_btn.button_down.connect(func():
		player.interact_held = true
		player.interact_pressed())
	interact_btn.button_up.connect(func(): player.interact_held = false)
	action_box.add_child(interact_btn)
	interact_icon = interact_btn.get_node("Icon")
	interact_label = UITheme.hud_label("", 16)
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_label.position = Vector2(96, 36)
	interact_label.custom_minimum_size = Vector2(260, 0)
	interact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_box.add_child(interact_label)
	var attack := UITheme.round_button(UITheme.ctrl("icon_sword"), func(): player.attack(), 100.0)
	attack.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	attack.name = "BtnAtacar"
	attack.tooltip_text = "Atacar (F)"
	attack.position = Vector2(84, 214)
	action_box.add_child(attack)
	var jump := UITheme.round_button(UITheme.ctrl("icon_jump"), func(): player.jump(), 84.0)
	jump.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	jump.name = "BtnSaltar"
	jump.tooltip_text = "Saltar (Espacio)"
	jump.position = Vector2(232, 72)
	action_box.add_child(jump)
	var dodge := UITheme.round_button(UITheme.ctrl("icon_arrow_curved"), func(): player.dodge(), 80.0)
	dodge.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	dodge.name = "BtnEsquivar"
	dodge.tooltip_text = "Esquivar (Q)"
	dodge.position = Vector2(110, 110)
	action_box.add_child(dodge)
	var eat := UITheme.round_button(GameData.item_icon("bayas"), func(): player.quick_eat(), 68.0)
	eat.name = "BtnComer"
	eat.tooltip_text = "Comer/beber lo mejor (H)"
	eat.position = Vector2(20, 120)
	(eat.get_node("Icon") as TextureRect).modulate = Color.WHITE
	action_box.add_child(eat)


func _build_build_controls() -> void:
	build_box = PanelContainer.new()
	build_box.add_theme_stylebox_override("panel", UITheme.flat(Color(0.1, 0.07, 0.04, 0.6), 14))
	build_box.anchor_left = 0.5
	build_box.anchor_right = 0.5
	build_box.anchor_top = 1.0
	build_box.anchor_bottom = 1.0
	build_box.offset_left = -300
	build_box.offset_right = 300
	build_box.offset_top = -150
	build_box.offset_bottom = -14
	build_box.visible = false
	root.add_child(build_box)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	build_box.add_child(vb)
	build_reason = UITheme.hud_label("", 18)
	build_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(build_reason)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 26)
	vb.add_child(hb)
	var rot := UITheme.round_button(UITheme.ctrl("icon_arrow_rotate"), func(): world.build_mode.rotate_step(45.0), 84.0)
	rot.name = "BtnGirar"
	rot.tooltip_text = "Girar (R)"
	hb.add_child(rot)
	var ok := UITheme.round_button(UITheme.ctrl("icon_checkmark"), func(): world.build_mode.confirm(), 92.0)
	ok.name = "BtnConfirmar"
	ok.tooltip_text = "Construir (Intro)"
	(ok.get_node("Icon") as TextureRect).modulate = UITheme.GOOD
	hb.add_child(ok)
	var cancel := UITheme.round_button(UITheme.ctrl("icon_cross"), func(): world.build_mode.cancel(), 84.0)
	cancel.name = "BtnCancelar"
	cancel.tooltip_text = "Cancelar (Esc)"
	(cancel.get_node("Icon") as TextureRect).modulate = UITheme.BAD
	hb.add_child(cancel)


func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.offset_left = -330
	toast_box.offset_right = 330
	toast_box.offset_top = 176
	toast_box.add_theme_constant_override("separation", 6)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)


func _build_boss() -> void:
	boss_box = PanelContainer.new()
	boss_box.add_theme_stylebox_override("panel", UITheme.flat(Color(0.1, 0.05, 0.05, 0.6), 12))
	boss_box.anchor_left = 0.5
	boss_box.anchor_right = 0.5
	boss_box.offset_left = -240
	boss_box.offset_right = 240
	boss_box.offset_top = 118
	boss_box.visible = false
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(boss_box)
	var vb := VBoxContainer.new()
	boss_box.add_child(vb)
	boss_label = UITheme.hud_label("", 18)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(boss_label)
	boss_bar = UITheme.progress_bar("red", 22)
	vb.add_child(boss_bar)


func _build_panels() -> void:
	var defs := {
		"inventory": InventoryPanel, "crafting": CraftingPanel, "build": BuildMenu, "building": BuildingPanel,
		"tech": TechPanel, "workers": WorkersPanel, "map": MapPanel, "stats": StatsPanel,
		"settings": SettingsPanel, "offline": OfflinePanel, "death": DeathPanel,
	}
	for key in defs:
		var p: UIPanel = defs[key].new()
		p.name = "Panel_" + key
		root.add_child(p)
		p.setup(self)
		panels[key] = p
		p.closed.connect(_on_panel_closed)


# ------------------------------------------------------------------ eventos
func _connect() -> void:
	EventBus.toast.connect(toast)
	EventBus.floating_text.connect(floating_text)
	EventBus.open_panel.connect(open_panel)
	EventBus.player_stats_changed.connect(_refresh_bars)
	EventBus.inventory_changed.connect(_refresh_resources)
	EventBus.storage_changed.connect(_refresh_resources)
	EventBus.xp_changed.connect(func(_x, _l): _refresh_level())
	EventBus.tech_points_changed.connect(func(_p): _refresh_level())
	EventBus.level_up.connect(_on_level_up)
	EventBus.quest_progress.connect(func(_q, _v, _t): _refresh_quest())
	EventBus.quest_completed.connect(_on_quest_completed)
	EventBus.tech_researched.connect(_on_tech)
	EventBus.age_changed.connect(_on_age)
	EventBus.build_mode_changed.connect(_on_build_mode)
	EventBus.player_died.connect(func(): get_tree().create_timer(1.4).timeout.connect(func(): open_panel("death")))
	EventBus.player_damaged.connect(func(_a, _s): _pulse_vignette())
	EventBus.danger_nearby.connect(func(a): _danger = a)
	EventBus.game_saved.connect(_on_saved)
	EventBus.region_unlocked.connect(_on_region)
	EventBus.banner.connect(banner)
	EventBus.item_collected_at.connect(_fly_item)
	EventBus.weather_changed.connect(func(_s): _refresh_clock())
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.settings_changed.connect(func(): fps_label.visible = bool(Settings.get_value("show_fps")))
	player.target_changed.connect(_on_target)
	world.build_mode.validity_changed.connect(func(ok, reason):
		build_reason.text = ("Lugar válido: " + str(GameData.building(world.build_mode.type_id).get("name", ""))) if ok else reason
		build_reason.add_theme_color_override("font_color", Color(0.7, 1.0, 0.6) if ok else Color(1.0, 0.6, 0.5)))
	fps_label.visible = bool(Settings.get_value("show_fps"))


func _refresh_all() -> void:
	_refresh_bars()
	_refresh_resources()
	_refresh_level()
	_refresh_quest()
	_refresh_clock()
	_on_target(player.target)


func _refresh_bars() -> void:
	var sv := player.survival
	for key in bars:
		var b: Dictionary = bars[key]
		b.target = sv.ratio(key)
		(b.label as Label).text = str(int(round(sv.s(key))))
	_low_health = sv.ratio("health") < 0.3


func _refresh_resources() -> void:
	for id in res_labels:
		var total := Economy.total_available(id)
		res_labels[id].label.text = UITheme.fmt_num(total)
		res_labels[id].box.visible = total > 0 or id in ["madera", "piedra", "fibra"]


func _refresh_level() -> void:
	level_label.text = "Nivel %d" % GameState.level
	xp_bar.value = float(GameState.xp) / maxf(float(GameState.xp_for_level(GameState.level)), 1.0)
	points_label.text = "%d PT" % TechTree.points


func _refresh_quest() -> void:
	var q := Quests.current()
	if q.is_empty():
		quest_title.text = "¡Isla dominada!"
		quest_desc.text = "Has completado todos los objetivos. Sigue ampliando tu base."
		quest_count.text = ""
		quest_bar.value = 1.0
		return
	quest_title.text = q.title
	quest_desc.text = q.desc
	var v := mini(Quests.current_value(), Quests.target_value())
	quest_count.text = "%d/%d" % [v, Quests.target_value()]
	_quest_target = float(v) / maxf(float(Quests.target_value()), 1.0)


func _refresh_clock() -> void:
	var h := int(GameState.hour)
	var m := int((GameState.hour - h) * 60.0)
	var night: bool = world.day_night.is_night()
	clock_label.text = "Día %d · %02d:%02d" % [GameState.day, h, m]
	clock_label.add_theme_color_override("font_color", Color(0.7, 0.82, 1.0) if night else Color(1.0, 0.96, 0.78))
	age_label.text = TechTree.age_name()
	var wlabel: String = world.weather.label() if world.weather else ""
	weather_label.visible = wlabel != "" and wlabel != "Despejado"
	weather_label.text = wlabel


func _on_level_up(level: int) -> void:
	AudioManager.play("events/level_up")
	banner("¡Nivel %d!" % level, "+%d puntos de tecnología" % int(GameData.b("progression.tech_points_per_level", 2)), "level")
	_refresh_level()
	_pulse(level_label, 1.35)


func _on_quest_completed(qid: String) -> void:
	var q: Dictionary = {}
	for x in GameData.quests:
		if x.id == qid:
			q = x
	AudioManager.play("events/jingle_%02d" % (randi() % 17), -2.0)
	banner("¡Objetivo cumplido!", "%s · %s" % [q.get("title", ""), Quests.reward_text(q)], "quest")
	_quest_flash = 1.0
	_refresh_quest()


func _on_tech(tech_id: String) -> void:
	AudioManager.play("events/research")
	toast("Tecnología investigada: %s" % GameData.tech(tech_id).get("name", tech_id), "good")


func _on_age(age: int) -> void:
	AudioManager.play("events/unlock")
	banner("¡Nueva era!", GameData.age_name(age), "age")
	_refresh_clock()


func _on_region(region_id: String) -> void:
	AudioManager.play("events/achievement")
	var reg_name: String = {"jungla": "La jungla", "cueva": "La cueva de cristal"}.get(region_id, region_id.capitalize())
	banner("Nueva región", reg_name, "region")


func _on_enemy_killed(enemy_type: String, _pos: Vector3) -> void:
	var ed: Dictionary = GameData.enemies.get(enemy_type, {})
	if bool(ed.get("boss", false)):
		banner("¡Guardián derrotado!", str(ed.get("name", "")), "quest")


func _on_build_mode(active: bool) -> void:
	build_box.visible = active
	action_box.visible = not active
	if active:
		close_all()


func _on_target(info: Dictionary) -> void:
	var has := not info.is_empty()
	interact_btn.modulate = Color(1, 1, 1, 1.0 if has else 0.55)
	var key := "%s|%s|%s" % [info.get("kind", ""), info.get("id", ""), info.get("uid", "")]
	if has and key != _last_target_key:
		_pulse(interact_btn, 1.12)
	_last_target_key = key
	interact_label.text = str(info.get("label", ""))
	var icon_name := str(info.get("icon", "icon_hand"))
	interact_icon.texture = UITheme.ctrl(icon_name) if UITheme.ctrl(icon_name) else UITheme.ctrl("icon_hand")


func _on_saved() -> void:
	var tw := create_tween()
	tw.tween_property(save_icon, "modulate:a", 0.9, 0.2)
	tw.tween_interval(0.8)
	tw.tween_property(save_icon, "modulate:a", 0.0, 0.5)


func _pulse_vignette() -> void:
	var tw := create_tween()
	tw.tween_property(vignette, "modulate:a", 1.0, 0.06)
	tw.tween_property(vignette, "modulate:a", 0.0, 0.5)


# ------------------------------------------------------------------ ventanas
func open_panel(panel_name: String, data: Variant = null) -> void:
	if not panels.has(panel_name):
		return
	if world.build_mode.active and panel_name != "settings":
		world.build_mode.cancel()
	for k in panels:
		if k != panel_name and panels[k].is_open:
			panels[k].close()
	joystick.release()
	look_area.clear()
	player.set_touch_move(Vector2.ZERO, false)
	panels[panel_name].open(data)


func close_all() -> void:
	for k in panels:
		if panels[k].is_open:
			panels[k].close()


func any_panel_open() -> bool:
	for k in panels:
		if panels[k].is_open:
			return true
	return false


func _on_panel_closed() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if world.build_mode.active:
			world.build_mode.cancel()
		elif any_panel_open():
			close_all()
		else:
			open_panel("settings")
		get_viewport().set_input_as_handled()
		return
	if world.build_mode.active:
		if event.is_action_pressed("rotate_building"):
			world.build_mode.rotate_step(45.0)
		elif event.is_action_pressed("confirm"):
			world.build_mode.confirm()
		return
	var shortcuts := {"inventory": "inventory", "crafting": "crafting", "build": "build", "tech": "tech", "map": "map", "stats": "stats"}
	for action in shortcuts:
		if event.is_action_pressed(action):
			if panels[shortcuts[action]].is_open:
				panels[shortcuts[action]].close()
			else:
				open_panel(shortcuts[action])
			get_viewport().set_input_as_handled()
			return


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if any_panel_open():
			close_all()
		else:
			open_panel("settings")


# ------------------------------------------------------------------ avisos y textos
func toast(text: String, kind: String = "info") -> void:
	if toast_box == null:
		return
	if toast_box.get_child_count() >= 4:
		toast_box.get_child(0).queue_free()
	var pc := PanelContainer.new()
	var col: Color = {"good": Color(0.16, 0.38, 0.14, 0.88), "warn": Color(0.5, 0.32, 0.06, 0.9), "bad": Color(0.5, 0.1, 0.08, 0.9)}.get(kind, Color(0.12, 0.09, 0.05, 0.85))
	pc.add_theme_stylebox_override("panel", UITheme.flat(col, 12, Color(1, 0.9, 0.7, 0.5), 2))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.hud_label(text, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	toast_box.add_child(pc)
	pc.modulate = Color(1, 1, 1, 0)
	pc.scale = Vector2(0.85, 0.6)
	pc.resized.connect(func(): pc.pivot_offset = Vector2(pc.size.x * 0.5, 0.0))
	var tw := pc.create_tween()
	tw.set_parallel(true)
	tw.tween_property(pc, "modulate:a", 1.0, 0.18)
	tw.tween_property(pc, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(3.2 if kind != "bad" else 4.5)
	tw.chain().tween_property(pc, "modulate:a", 0.0, 0.45)
	tw.parallel().tween_property(pc, "scale", Vector2(0.92, 0.92), 0.45)
	tw.chain().tween_callback(pc.queue_free)
	if kind == "warn" or kind == "bad":
		AudioManager.play_ui("ui/question" if kind == "warn" else "ui/error", -8.0)


func floating_text(world_pos: Vector3, text: String, color: Color) -> void:
	if float_layer == null:
		return
	if _floats.size() > 14:
		var old: Dictionary = _floats.pop_front()
		(old.label as Node).queue_free()
	var big := text.begins_with("-") or text.is_valid_int()
	var l := UITheme.hud_label(text, 26 if big else 20)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_layer.add_child(l)
	_floats.append({"label": l, "pos": world_pos, "t": 0.0, "dx": randf_range(-18.0, 18.0)})


func _process(delta: float) -> void:
	if world == null:
		return
	var cam := get_viewport().get_camera_3d()
	for i in range(_floats.size() - 1, -1, -1):
		var f: Dictionary = _floats[i]
		f.t = float(f.t) + delta
		var l: Label = f.label
		if float(f.t) > 1.4 or cam == null:
			l.queue_free()
			_floats.remove_at(i)
			continue
		var ft := float(f.t)
		var rise := 1.0 - pow(1.0 - clampf(ft / 1.4, 0.0, 1.0), 2.0)
		var p: Vector3 = f.pos + Vector3.UP * rise * 1.4
		if cam.is_position_behind(p):
			l.visible = false
			continue
		l.visible = true
		var sp := cam.unproject_position(p)
		l.pivot_offset = l.size * 0.5
		var pop := 1.0 + 0.55 * (1.0 - clampf(ft / 0.16, 0.0, 1.0))
		l.scale = Vector2.ONE * pop
		l.position = sp - l.size * 0.5 + Vector2(float(f.dx) * rise, 0.0)
		l.modulate.a = clampf(1.6 - ft * 1.2, 0.0, 1.0)
	_update_t -= delta
	if _update_t <= 0.0:
		_update_t = 0.25
		_refresh_clock()
		if fps_label.visible:
			fps_label.text = "%d FPS · %d obj" % [Engine.get_frames_per_second(), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]
		var boss: Enemy = world.enemies.active_boss()
		boss_box.visible = boss != null
		if boss:
			boss_label.text = str(boss.data.get("name", ""))
			boss_bar.value = boss.hp / maxf(boss.max_hp, 1.0)
		if Quests.current().get("type", "") in ["have", "build", "upgrade", "research", "hire", "reach_age"]:
			_refresh_quest()
	var target_a := 0.0
	if _low_health and not player.dead:
		target_a = 0.35 + sin(Time.get_ticks_msec() / 250.0) * 0.12
	elif _danger:
		target_a = 0.18
	if vignette.modulate.a < target_a:
		vignette.modulate.a = move_toward(vignette.modulate.a, target_a, delta * 2.0)
	elif vignette.modulate.a > target_a + 0.01:
		vignette.modulate.a = move_toward(vignette.modulate.a, target_a, delta * 0.8)
	if _quest_flash > 0.0:
		_quest_flash = maxf(_quest_flash - delta, 0.0)
		quest_box.modulate = Color(1, 1, 1).lerp(Color(1.6, 1.5, 0.8), _quest_flash)
	_time += delta
	_animate_bars(delta)
	quest_bar.value = lerpf(quest_bar.value, _quest_target, clampf(delta * 6.0, 0.0, 1.0)) if absf(quest_bar.value - _quest_target) > 0.002 else _quest_target
	var inputs_blocked := any_panel_open()
	joystick.visible = not inputs_blocked
	if inputs_blocked:
		player.set_touch_move(Vector2.ZERO, false)


# ------------------------------------------------------------------ animaciones de la interfaz
## Las barras se deslizan hacia su valor y laten cuando un recurso vital es bajo.
func _animate_bars(delta: float) -> void:
	for key in bars:
		var b: Dictionary = bars[key]
		var bar: ProgressBar = b.bar
		var target: float = b.target
		if absf(bar.value - target) > 0.001:
			bar.value = lerpf(bar.value, target, clampf(delta * (12.0 if target > bar.value else 7.0), 0.0, 1.0))
		var ic: TextureRect = b.icon
		var low: bool = key != "stamina" and target < 0.25 and not player.dead
		if low:
			var k := absf(sin(_time * 5.0))
			ic.scale = Vector2.ONE * (1.0 + 0.2 * k)
			bar.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.5, 0.75, 0.7), k)
		elif ic.scale != Vector2.ONE:
			ic.scale = Vector2.ONE
			bar.modulate = Color.WHITE


## Pequeño rebote de escala en un control.
func _pulse(c: Control, amount: float = 1.25) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * amount, 0.08)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Rótulo grande en el centro (subida de nivel, objetivos, nueva era, noche...).
func banner(title_text: String, subtitle: String = "", kind: String = "info") -> void:
	if _banner_layer == null:
		return
	_banner_queue.append([title_text, subtitle, kind])
	if _banner_queue.size() > 4:
		_banner_queue.pop_front()
	if not _banner_busy:
		_next_banner()


func _next_banner() -> void:
	if _banner_queue.is_empty():
		_banner_busy = false
		return
	_banner_busy = true
	var e: Array = _banner_queue.pop_front()
	var kind: String = e[2]
	var accent: Color = {"level": Color(1.0, 0.82, 0.3), "quest": Color(0.6, 1.0, 0.5), "age": Color(1.0, 0.65, 0.3),
		"region": Color(0.5, 0.85, 1.0), "night": Color(0.65, 0.72, 1.0), "day": Color(1.0, 0.9, 0.6)}.get(kind, Color(1.0, 0.95, 0.8))
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UITheme.flat(Color(0.08, 0.05, 0.03, 0.72), 18, Color(accent, 0.85), 3))
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	box.add_child(vb)
	var t := UITheme.hud_label(str(e[0]), 46 if kind in ["level", "quest", "age"] else 38)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", accent)
	t.add_theme_constant_override("outline_size", 12)
	vb.add_child(t)
	if str(e[1]) != "":
		var st := UITheme.hud_label(str(e[1]), 20)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size = Vector2(420, 0)
		vb.add_child(st)
	# Centrado horizontal automático; el rebote usa el centro de la caja.
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 0.22
	holder.anchor_bottom = 0.22
	holder.offset_bottom = 150.0
	_banner_layer.add_child(holder)
	holder.add_child(box)
	box.resized.connect(func(): box.pivot_offset = box.size * 0.5)
	box.scale = Vector2(0.6, 0.6)
	holder.modulate = Color(1, 1, 1, 0)
	var hold := 2.2 if kind in ["level", "quest", "age", "region"] else 1.6
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "modulate:a", 1.0, 0.2)
	tw.tween_property(box, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(hold)
	tw.chain().tween_property(holder, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(holder, "offset_top", -24.0, 0.4)
	tw.parallel().tween_property(holder, "offset_bottom", 126.0, 0.4)
	tw.chain().tween_callback(func():
		holder.queue_free()
		_next_banner())


## Icono del objeto que vuela desde el mundo hasta su contador (o la mochila).
func _fly_item(item_id: String, amount: int, world_pos: Vector3) -> void:
	if _fly_layer == null or _flyers >= 8 or amount <= 0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		return
	var start := cam.unproject_position(world_pos)
	var target_ctrl: Control = null
	if res_labels.has(item_id) and (res_labels[item_id].box as Control).is_visible_in_tree():
		target_ctrl = res_labels[item_id].box
	else:
		target_ctrl = root.find_child("Btn_inventory", true, false) as Control
	if target_ctrl == null:
		return
	var end := target_ctrl.get_global_rect().get_center()
	var ic := TextureRect.new()
	ic.texture = GameData.item_icon(item_id)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size = Vector2(40, 40)
	ic.pivot_offset = Vector2(20, 20)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.position = start - ic.size * 0.5
	_fly_layer.add_child(ic)
	_flyers += 1
	var ctrl_pt := Vector2(lerpf(start.x, end.x, 0.3), minf(start.y, end.y) - 80.0)
	var tw := ic.create_tween()
	tw.tween_method(func(k: float):
		var a := start.lerp(ctrl_pt, k)
		var b := ctrl_pt.lerp(end, k)
		ic.position = a.lerp(b, k) - ic.size * 0.5
		ic.scale = Vector2.ONE * lerpf(1.25, 0.7, k), 0.0, 1.0, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		_flyers -= 1
		ic.queue_free()
		_pulse(target_ctrl, 1.25))
