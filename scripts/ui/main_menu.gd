extends Control
## Menú principal: continuar, nueva partida, ajustes, créditos y salir.

var settings: SettingsPanel
var credits: Control
var confirm_box: Control
var hud: Node = null  # compatibilidad con UIPanel
var world: Node = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var g := Gradient.new()
	g.set_color(0, Color(0.36, 0.72, 0.86))
	g.set_color(1, Color(0.95, 0.85, 0.6))
	g.add_point(0.62, Color(0.55, 0.82, 0.9))
	g.add_point(0.66, Color(0.12, 0.45, 0.6))
	g.add_point(0.8, Color(0.2, 0.55, 0.65))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	bg.texture = gt
	add_child(bg)
	var deco := TextureRect.new()
	deco.texture = load("res://assets/icons/buildings/refugio.png") if ResourceLoader.exists("res://assets/icons/buildings/refugio.png") else null
	deco.anchor_left = 0.62
	deco.anchor_right = 0.95
	deco.anchor_top = 0.3
	deco.anchor_bottom = 0.85
	deco.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	deco.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(deco)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.08
	vb.anchor_right = 0.5
	vb.anchor_top = 0.08
	vb.anchor_bottom = 0.95
	vb.add_theme_constant_override("separation", 14)
	add_child(vb)
	var t := UITheme.hud_label("Isla Salvaje", 72)
	vb.add_child(t)
	vb.add_child(UITheme.hud_label("Supervivencia Incremental", 30))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vb.add_child(spacer)
	if SaveManager.has_save():
		var c := UITheme.button("Continuar", _continue, Vector2(380, 70))
		c.name = "BtnContinuar"
		vb.add_child(c)
	var n := UITheme.button("Nueva partida", _new_game, Vector2(380, 70))
	n.name = "BtnNueva"
	vb.add_child(n)
	vb.add_child(UITheme.button("Ajustes", func(): settings.open(), Vector2(380, 64)))
	vb.add_child(UITheme.button("Créditos", func(): credits.visible = true, Vector2(380, 64)))
	if not OS.has_feature("web"):
		vb.add_child(UITheme.button("Salir", func(): get_tree().quit(), Vector2(380, 64)))
	vb.add_child(UITheme.hud_label("v%s · Godot %s" % [ProjectSettings.get_setting("application/config/version", "1.0"), Engine.get_version_info().string], 15))
	settings = SettingsPanel.new()
	add_child(settings)
	settings.setup(self)
	settings.pauses_game = false
	credits = _make_credits()
	add_child(credits)
	confirm_box = _make_confirm()
	add_child(confirm_box)


func _make_credits() -> Control:
	var pc := PanelContainer.new()
	pc.anchor_left = 0.15
	pc.anchor_right = 0.85
	pc.anchor_top = 0.1
	pc.anchor_bottom = 0.9
	pc.visible = false
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.text = "[b]Isla Salvaje: Supervivencia Incremental[/b]\n\n[b]Modelos 3D (OBJ), texturas, interfaz e iconos:[/b] Kenney — kenney.nl (CC0): Nature Kit, Survival Kit, Fantasy Town Kit, Pirate Kit, Food Kit, Cube Pets, Mini Characters, Graveyard Kit, Factory Kit, Tower Defense Kit, Modular Cave Kit, Space Station Kit, Mini Dungeon, UI Pack Adventure, Mobile Controls, Game Icons.\n\n[b]Audio:[/b] Kenney Impact, RPG, Foley, Interface, Digital, Sci-Fi, Music Jingles y Music Loops (CC0). Grabaciones de Freesound (CC0) de felix.blume, SecureSubset, IceVFX, FunWithSound, MrFossy, sgrowe, Kinoton y otros. Efectos de OpenGameArt (CC0): StarNinjas, OwlishMedia, rubberduck, Spring Spring, themightyglider.\n\n[b]Música:[/b] Kevin MacLeod vía FreePD.com (CC0).\n\n[b]Fuentes:[/b] Fredoka y Nunito (SIL Open Font License).\n\nLista detallada con enlaces y licencias en ASSET_CREDITS.md."
	vb.add_child(rt)
	vb.add_child(UITheme.button("Cerrar", func(): pc.visible = false, Vector2(0, 58)))
	return pc


func _make_confirm() -> Control:
	var pc := PanelContainer.new()
	pc.anchor_left = 0.3
	pc.anchor_right = 0.7
	pc.anchor_top = 0.35
	pc.anchor_bottom = 0.65
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	var l := UITheme.label("Ya tienes una partida guardada. ¿Empezar de nuevo y sobrescribirla?", 20)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	hb.add_child(UITheme.button("Sí, nueva partida", func():
		pc.visible = false
		_start_new(), Vector2(240, 58)))
	hb.add_child(UITheme.button("Cancelar", func(): pc.visible = false, Vector2(160, 58)))
	return pc


func _continue() -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main:
		main.continue_game()


func _new_game() -> void:
	if SaveManager.has_save():
		confirm_box.visible = true
	else:
		_start_new()


func _start_new() -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main:
		main.new_game()


func open_panel(_n: String, _d: Variant = null) -> void:
	pass
