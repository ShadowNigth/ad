class_name CraftingPanel
extends UIPanel
## Fabricación: recetas por estación con indicadores de bloqueo, coste
## (tienes/necesitas), cola con progreso y aviso de estación cercana.

const STATIONS := [null, "fogata", "taller", "fundicion"]

var tabs: TabBar
var list: VBoxContainer
var queue_icon: TextureRect
var queue_label: Label
var queue_bar: ProgressBar
var station_hint: Label
var _rows: Array = []


func _init() -> void:
	super()
	title = "Fabricación"
	size_ratio = Vector2(0.9, 0.92)


func _build() -> void:
	tabs = TabBar.new()
	for st in STATIONS:
		tabs.add_tab(Crafter.station_name(st))
	tabs.tab_changed.connect(func(_i): _rebuild_list())
	body.add_child(tabs)
	var qbox := PanelContainer.new()
	qbox.add_theme_stylebox_override("panel", UITheme.box("panel_brown_dark", 20, 12))
	body.add_child(qbox)
	var qh := HBoxContainer.new()
	qh.add_theme_constant_override("separation", 12)
	qbox.add_child(qh)
	queue_icon = TextureRect.new()
	queue_icon.custom_minimum_size = Vector2(52, 52)
	queue_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	queue_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qh.add_child(queue_icon)
	var qv := VBoxContainer.new()
	qv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qh.add_child(qv)
	queue_label = UITheme.label("", 19, UITheme.CREAM)
	qv.add_child(queue_label)
	queue_bar = UITheme.progress_bar("green", 22)
	qv.add_child(queue_bar)
	qh.add_child(UITheme.button("Cancelar cola", func():
		hud.world.crafter.cancel_all()
		refresh(), Vector2(190, 52)))
	station_hint = UITheme.label("", 17)
	station_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(station_hint)
	list = make_scroll()
	EventBus.inventory_changed.connect(func(): if is_open: _refresh_rows())
	EventBus.storage_changed.connect(func(): if is_open: _refresh_rows())


func open(d: Variant = null) -> void:
	if d is Dictionary and d.has("station"):
		var idx := STATIONS.find(d.station)
		if idx >= 0:
			tabs.current_tab = idx
	super(d)


func refresh() -> void:
	_rebuild_list()


func _rebuild_list() -> void:
	UIPanel.clear_children(list)
	_rows.clear()
	var st: Variant = STATIONS[tabs.current_tab]
	var crafter: Crafter = hud.world.crafter
	var recipes := GameData.recipes_for_station(st)
	var station_ok := true
	if st != null:
		station_ok = crafter.station_for({"station": st}).ok
		station_hint.text = "Estás junto a: %s" % Crafter.station_name(st) if station_ok else "Necesitas estar junto a un edificio «%s» para usar estas recetas." % Crafter.station_name(st)
		station_hint.add_theme_color_override("font_color", UITheme.GOOD if station_ok else UITheme.BAD)
	else:
		station_hint.text = "Recetas que puedes fabricar en cualquier lugar."
		station_hint.add_theme_color_override("font_color", UITheme.BROWN)
	for r in recipes:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme.box("panel_brown", 20, 10, Color(0.97, 0.94, 0.88)))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row.add_child(hb)
		hb.add_child(UITheme.item_icon(r.result, 60))
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vb)
		var name_l := UITheme.label("%s%s" % [GameData.item_name(r.result), (" ×%d" % int(r.qty)) if int(r.qty) > 1 else ""], 21, UITheme.BROWN, true)
		vb.add_child(name_l)
		var cost_holder := HBoxContainer.new()
		vb.add_child(cost_holder)
		var status := UITheme.label("", 16)
		vb.add_child(status)
		var b1 := UITheme.button("Fabricar", _craft.bind(r.id, 1), Vector2(150, 54))
		var b5 := UITheme.button("×5", _craft.bind(r.id, 5), Vector2(80, 54))
		hb.add_child(b1)
		hb.add_child(b5)
		list.add_child(row)
		_rows.append({"recipe": r, "cost": cost_holder, "status": status, "b1": b1, "b5": b5, "name": name_l, "row": row})
	_refresh_rows()


func _refresh_rows() -> void:
	var crafter: Crafter = hud.world.crafter
	for e in _rows:
		var r: Dictionary = e.recipe
		UIPanel.clear_children(e.cost)
		e.cost.add_child(UITheme.cost_row(r.ingredients, 30, 17))
		e.cost.add_child(UITheme.label("  %.1f s" % float(r.time), 16, UITheme.BROWN_LIGHT))
		var unlocked := crafter.recipe_unlocked(r)
		var check := crafter.can_craft(r.id)
		(e.b1 as Button).disabled = not check.ok
		(e.b5 as Button).disabled = not check.ok
		(e.row as Control).modulate = Color.WHITE if unlocked else Color(0.7, 0.7, 0.7)
		if not unlocked:
			e.status.text = "🔒 Requiere tecnología: %s" % GameData.tech(r.unlock).get("name", r.unlock)
			e.status.add_theme_color_override("font_color", UITheme.BAD)
		elif not check.ok:
			e.status.text = check.reason
			e.status.add_theme_color_override("font_color", UITheme.WARN)
		else:
			e.status.text = GameData.item(r.result).get("desc", "")
			e.status.add_theme_color_override("font_color", UITheme.BROWN_LIGHT)


func _craft(recipe_id: String, n: int) -> void:
	var added: int = hud.world.crafter.enqueue(recipe_id, n)
	if added > 0:
		AudioManager.play_ui("ui/confirm")


func _process(_delta: float) -> void:
	if not is_open:
		return
	var crafter: Crafter = hud.world.crafter
	if crafter.current.is_empty():
		queue_icon.texture = null
		queue_label.text = "Cola vacía" if crafter.queue.is_empty() else "Esperando..."
		queue_bar.value = 0.0
	else:
		var r := GameData.recipe(crafter.current.recipe)
		queue_icon.texture = GameData.item_icon(r.result)
		queue_label.text = "Fabricando %s · %d en cola" % [GameData.item_name(r.result), crafter.queue.size()]
		queue_bar.value = crafter.progress
