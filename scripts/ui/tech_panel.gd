class_name TechPanel
extends UIPanel
## Árbol tecnológico: matriz ramas × edades con estado de cada tecnología
## (investigada, disponible, bloqueada) y panel de detalle para investigar.

var header_label: Label
var matrix: GridContainer
var detail: VBoxContainer
var selected := ""


func _init() -> void:
	super()
	title = "Árbol tecnológico"
	size_ratio = Vector2(0.96, 0.94)


func _build() -> void:
	header_label = UITheme.label("", 19, UITheme.BROWN, true)
	header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(header_label)
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 10)
	body.add_child(hb)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_stretch_ratio = 2.2
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(sc)
	matrix = GridContainer.new()
	matrix.columns = GameData.branches.size() + 1
	matrix.add_theme_constant_override("h_separation", 4)
	matrix.add_theme_constant_override("v_separation", 4)
	sc.add_child(matrix)
	var dp := PanelContainer.new()
	dp.add_theme_stylebox_override("panel", UITheme.box("panel_brown_dark", 20, 14))
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp.custom_minimum_size = Vector2(320, 0)
	hb.add_child(dp)
	var dsc := ScrollContainer.new()
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dp.add_child(dsc)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	dsc.add_child(detail)
	EventBus.tech_points_changed.connect(func(_p): if is_open: refresh())


func refresh() -> void:
	var next := TechTree.techs_for_next_age()
	header_label.text = "Puntos: %d PT · %s%s · %d tecnologías investigadas" % [TechTree.points, TechTree.age_name(),
		(" (faltan %d para la siguiente era)" % next) if next > 0 else "", TechTree.researched.size()]
	UIPanel.clear_children(matrix)
	matrix.add_child(UITheme.label("", 14))
	for br in GameData.branches:
		var l := UITheme.label(br.name, 15, Color(br.color).darkened(0.35), true)
		l.custom_minimum_size = Vector2(118, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		matrix.add_child(l)
	var ages: Array = GameData.b("progression.age_names", [])
	for age in ages.size():
		var al := UITheme.label(str(ages[age]), 14, UITheme.BROWN_LIGHT, true)
		al.custom_minimum_size = Vector2(96, 0)
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		matrix.add_child(al)
		for br in GameData.branches:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 3)
			for t in GameData.techs_in_branch(br.id):
				if int(t.age) == age:
					cell.add_child(_tech_button(t, br))
			matrix.add_child(cell)
	if selected == "" or not GameData.techs.has(selected):
		for id in GameData.tech_order:
			if TechTree.can_research(id).ok:
				selected = id
				break
	_refresh_detail()


func _tech_button(t: Dictionary, br: Dictionary) -> Button:
	var b := Button.new()
	b.text = t.name
	b.custom_minimum_size = Vector2(118, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 14)
	var col := Color(br.color)
	var state := "locked"
	if TechTree.is_researched(t.id):
		state = "done"
	elif TechTree.can_research(t.id).ok:
		state = "ready"
	elif int(t.age) <= TechTree.age() and t.get("requires", []).all(func(r): return TechTree.is_researched(r)):
		state = "afford"
	var sb := UITheme.flat(col.darkened(0.15) if state == "done" else (col.lightened(0.35) if state == "ready" else (col.lightened(0.6) if state == "afford" else Color(0.55, 0.53, 0.5))), 8,
		Color(1, 0.95, 0.6) if t.id == selected else col.darkened(0.4), 3 if t.id == selected else 2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color.WHITE if state == "done" else UITheme.BROWN)
	b.text = ("✓ " if state == "done" else "") + str(t.name)
	b.tooltip_text = str(t.get("desc", ""))
	b.pressed.connect(func():
		selected = t.id
		AudioManager.play_ui("ui/select")
		refresh())
	return b


func _refresh_detail() -> void:
	UIPanel.clear_children(detail)
	if selected == "":
		detail.add_child(UITheme.label("Selecciona una tecnología.", 18, UITheme.CREAM))
		return
	var t := GameData.tech(selected)
	detail.add_child(UITheme.label(t.name, 25, UITheme.CREAM, true))
	var br_name := ""
	for br in GameData.branches:
		if br.id == t.branch:
			br_name = br.name
	detail.add_child(UITheme.label("%s · %s" % [br_name, GameData.age_name(int(t.age))], 16, Color(1, 0.85, 0.55)))
	var d := UITheme.label(str(t.get("desc", "")), 17, Color(0.96, 0.92, 0.84))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(d)
	var unl: Array[String] = []
	for id in GameData.building_order:
		if GameData.building(id).get("unlock") == selected:
			unl.append("Edificio: " + GameData.building(id).name)
	for r in GameData.recipes:
		if r.get("unlock") == selected:
			unl.append("Receta: " + GameData.item_name(r.result))
	for w in GameData.worker_order:
		if GameData.workers[w].get("unlock") == selected:
			unl.append("Trabajador: " + GameData.workers[w].name)
	if not unl.is_empty():
		var ul := UITheme.label("Desbloquea:\n• " + "\n• ".join(unl), 16, Color(0.75, 1.0, 0.7))
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(ul)
	var req: Array = t.get("requires", [])
	if not req.is_empty():
		var names: Array[String] = []
		for r in req:
			names.append(("✓ " if TechTree.is_researched(r) else "✗ ") + str(GameData.tech(r).get("name", r)))
		detail.add_child(UITheme.label("Requisitos:\n" + "\n".join(names), 16, Color(0.95, 0.9, 0.8)))
	detail.add_child(UITheme.label("Coste: %d PT" % int(t.get("cost", 0)), 19, Color(1, 0.9, 0.5), true))
	if not t.get("items", {}).is_empty():
		detail.add_child(UITheme.cost_row(t.items, 30, 17))
	if TechTree.is_researched(selected):
		detail.add_child(UITheme.label("✓ Investigada", 20, Color(0.6, 1.0, 0.6), true))
		return
	var check := TechTree.can_research(selected)
	var b := UITheme.button("Investigar", func():
		if TechTree.research(selected):
			refresh(), Vector2(240, 58))
	b.disabled = not check.ok
	detail.add_child(b)
	if not check.ok:
		var rl := UITheme.label(check.reason, 16, Color(1.0, 0.6, 0.5))
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(rl)
