class_name StatsPanel
extends UIPanel
## Estadísticas: producción/consumo por minuto de cada recurso, energía,
## estado de todos los edificios y registro del jugador.

var tabs: TabBar
var content: VBoxContainer
var _refresh_t := 0.0


func _init() -> void:
	super()
	title = "Producción y estadísticas"
	size_ratio = Vector2(0.92, 0.92)


func _build() -> void:
	tabs = TabBar.new()
	tabs.add_tab("Recursos")
	tabs.add_tab("Edificios")
	tabs.add_tab("Superviviente")
	tabs.tab_changed.connect(func(_i): refresh())
	body.add_child(tabs)
	content = make_scroll()


func refresh() -> void:
	UIPanel.clear_children(content)
	match tabs.current_tab:
		0:
			_resources()
		1:
			_buildings()
		2:
			_player()


func _row(cells: Array, widths: Array, color: Color = UITheme.BROWN, bold: bool = false) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	for i in cells.size():
		var c: Variant = cells[i]
		var ctrl: Control
		if c is Control:
			ctrl = c
		else:
			var l := UITheme.label(str(c), 17, color, bold)
			ctrl = l
		ctrl.custom_minimum_size.x = widths[i]
		hb.add_child(ctrl)
	return hb


func _resources() -> void:
	var r := Economy.rates()
	var prod: Dictionary = r.production
	var cons: Dictionary = r.consumption
	content.add_child(UITheme.label("Capacidad del almacén: %d por recurso · Energía: %s / %s (%d%%)" % [Economy.capacity(), UITheme.fmt_num(Economy.energy_supply), UITheme.fmt_num(Economy.energy_demand), int(Economy.energy_ratio * 100.0)], 18, UITheme.BROWN, true))
	var widths := [44, 210, 130, 130, 130, 170]
	content.add_child(_row(["", "Recurso", "Produce/min", "Consume/min", "Neto/min", "En almacén"], widths, UITheme.BROWN_LIGHT, true))
	var ids := {}
	for id in prod:
		ids[id] = true
	for id in cons:
		ids[id] = true
	for id in Economy.storage:
		ids[id] = true
	var order: Array = ids.keys()
	order.sort_custom(func(a, b): return GameData.item_order.find(a) < GameData.item_order.find(b))
	if order.is_empty():
		content.add_child(UITheme.label("Todavía no produces nada automáticamente. Construye un puesto de leñador.", 18))
	for id in order:
		var p := float(prod.get(id, 0.0))
		var c := float(cons.get(id, 0.0))
		var net := p - c
		var icon: Control = UITheme.item_icon(id, 36) if not str(id).begins_with("@") else UITheme.label("PT", 18)
		var stored := "—" if str(id).begins_with("@") else "%d/%d" % [Economy.stored(id), Economy.capacity()]
		content.add_child(_row([icon, GameData.item_name(id), UITheme.fmt_num(p), UITheme.fmt_num(c), ("+" if net >= 0 else "") + UITheme.fmt_num(net), stored], widths,
			UITheme.GOOD if net > 0.01 else (UITheme.BAD if net < -0.01 else UITheme.BROWN)))


func _buildings() -> void:
	if Economy.buildings.is_empty():
		content.add_child(UITheme.label("No hay edificios todavía.", 18))
		return
	var widths := [250, 70, 220, 230, 120]
	content.add_child(_row(["Edificio", "Nivel", "Estado", "Producción/min", ""], widths, UITheme.BROWN_LIGHT, true))
	for rec in Economy.buildings:
		var rate := Economy.building_rate(rec)
		var parts: Array[String] = []
		for id in rate:
			parts.append("%s %s" % [UITheme.fmt_num(float(rate[id])), GameData.item_name(id)])
		var status: String = rec.get("status", "")
		var ok := status == Economy.STATUS_OK or status == Economy.STATUS_IDLE
		var go := UITheme.button("Ver", func(): hud.open_panel("building", int(rec.uid)), Vector2(100, 44))
		content.add_child(_row([GameData.building(rec.type).name, str(rec.level), status, ", ".join(parts), go], widths, UITheme.BROWN if ok else UITheme.WARN))


func _player() -> void:
	var st := GameState.stats
	var lines: Array[String] = []
	lines.append("Nivel %d · %d/%d XP" % [GameState.level, GameState.xp, GameState.xp_for_level(GameState.level)])
	lines.append("Día %d · noches sobrevividas: %d · muertes: %d" % [GameState.day, int(st.get("nights", 0)), int(st.get("deaths", 0))])
	lines.append("Tiempo de juego: %s" % UITheme.fmt_time(GameState.playtime))
	lines.append("Edificios construidos: %d · trabajadores: %d" % [int(st.get("built", 0)), Workers.hired.size()])
	lines.append("Comidas y bebidas: %d · agua recogida: %d" % [int(st.get("eaten", 0)), int(st.get("water", 0))])
	lines.append("Era actual: %s · tecnologías: %d/%d" % [TechTree.age_name(), TechTree.researched.size(), GameData.techs.size()])
	lines.append("Objetivos completados: %d/%d" % [Quests.completed.size(), GameData.quests.size()])
	for l in lines:
		content.add_child(UITheme.label(l, 18))
	content.add_child(UITheme.label("Recolectado a mano:", 19, UITheme.BROWN, true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	content.add_child(flow)
	var g: Dictionary = st.get("gathered", {})
	for id in g:
		var hb := HBoxContainer.new()
		hb.add_child(UITheme.item_icon(id, 32))
		hb.add_child(UITheme.label(UITheme.fmt_num(float(g[id])), 17))
		flow.add_child(hb)
	content.add_child(UITheme.label("Criaturas derrotadas:", 19, UITheme.BROWN, true))
	var k: Dictionary = st.get("kills", {})
	if k.is_empty():
		content.add_child(UITheme.label("Ninguna todavía.", 17))
	for id in k:
		content.add_child(UITheme.label("• %s: %d" % [GameData.enemies.get(id, {}).get("name", id), int(k[id])], 17))


func _process(delta: float) -> void:
	if not is_open or tabs.current_tab == 2:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 2.0
		refresh()
