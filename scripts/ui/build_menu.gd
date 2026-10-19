class_name BuildMenu
extends UIPanel
## Menú de construcción: edificios por categoría con miniatura, coste,
## límite de unidades y requisitos bloqueados.

const CATEGORIES := [["supervivencia", "Supervivencia"], ["produccion", "Producción"], ["procesado", "Procesado"], ["avanzado", "Avanzado"], ["defensa", "Defensa"], ["decoracion", "Decoración"]]

var tabs: TabBar
var grid: GridContainer


func _init() -> void:
	super()
	title = "Construir"
	size_ratio = Vector2(0.94, 0.92)


func _build() -> void:
	tabs = TabBar.new()
	for c in CATEGORIES:
		tabs.add_tab(c[1])
	tabs.tab_changed.connect(func(_i): refresh())
	body.add_child(tabs)
	var hint := UITheme.label("Necesitas un martillo de construcción. El edificio se coloca delante de ti: muévete para elegir el sitio y gíralo antes de confirmar.", 16, UITheme.BROWN_LIGHT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)


func refresh() -> void:
	UIPanel.clear_children(grid)
	var cat: String = CATEGORIES[tabs.current_tab][0]
	for id in GameData.building_order:
		var bd := GameData.building(id)
		if bd.get("category", "") != cat:
			continue
		grid.add_child(_card(id, bd))


func _card(id: String, bd: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(340, 0)
	card.add_theme_stylebox_override("panel", UITheme.box("panel_brown", 20, 12, Color(0.97, 0.94, 0.88)))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	var thumb := TextureRect.new()
	var tp := "res://assets/icons/buildings/%s.png" % id
	thumb.texture = load(tp) if ResourceLoader.exists(tp) else UITheme.icon("home")
	thumb.custom_minimum_size = Vector2(96, 96)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(thumb)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(UITheme.label(bd.name, 21, UITheme.BROWN, true))
	tv.add_child(UITheme.label("Construidos: %d/%d" % [Economy.count_of(id), int(bd.get("max_count", 1))], 16, UITheme.BROWN_LIGHT))
	var prod: Array = bd.get("production", [])
	if not prod.is_empty():
		var outs: Array[String] = []
		for p in prod:
			for o in p.get("out", {}):
				var nm := GameData.item_name(o)
				if not outs.has(nm):
					outs.append(nm)
		tv.add_child(UITheme.label("Produce: " + ", ".join(outs), 15, UITheme.GOOD))
	if float(bd.get("beauty", 0.0)) > 0.0:
		var extra := ""
		if float(bd.get("move_bonus", 0.0)) > 0.0:
			extra = " · +%d %% velocidad al caminar" % int(round(float(bd.move_bonus) * 100.0))
		tv.add_child(UITheme.label("Belleza +%s%s" % [str(snappedf(float(bd.beauty), 0.5)).trim_suffix(".0"), extra], 15, UITheme.GOOD))
	var desc := UITheme.label(str(bd.get("desc", "")), 15)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)
	vb.add_child(UITheme.cost_row(Economy.build_cost(id), 30, 17))
	var check := Economy.can_build(id)
	var status := UITheme.label("" if check.ok else check.reason, 15, UITheme.BAD)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(status)
	var b := UITheme.button("Construir", _start.bind(id))
	b.disabled = not check.ok
	vb.add_child(b)
	if not TechTree.is_unlocked(bd.get("unlock")):
		card.modulate = Color(0.75, 0.75, 0.75)
	return card


func _start(id: String) -> void:
	close()
	hud.world.build_mode.start(id)
