class_name WorkersPanel
extends UIPanel
## Trabajadores: contratación por tipo (coste creciente, alojamiento),
## asignación a edificios y entrenamiento de habilidades.

var housing_label: Label
var list: VBoxContainer


func _init() -> void:
	super()
	title = "Trabajadores"
	size_ratio = Vector2(0.9, 0.92)


func _build() -> void:
	housing_label = UITheme.label("", 19, UITheme.BROWN, true)
	body.add_child(housing_label)
	list = make_scroll()
	EventBus.workers_changed.connect(func(): if is_open: refresh())


func refresh() -> void:
	housing_label.text = "Alojamiento: %d/%d · Mejora el refugio o construye cabañas para alojar a más trabajadores." % [Workers.housing_used(), Economy.housing_capacity()]
	UIPanel.clear_children(list)
	for type_id in GameData.worker_order:
		list.add_child(_type_card(type_id))


func _type_card(type_id: String) -> Control:
	var wd := Workers.type_data(type_id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.box("panel_brown", 20, 12, Color(0.97, 0.94, 0.88)))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(UITheme.label("%s · contratados: %d (libres: %d)" % [wd.name, Workers.count_of_type(type_id), Workers.idle_of_type(type_id)], 21, UITheme.BROWN, true))
	var dl := UITheme.label("%s Cada uno acelera el edificio un %d%% (más con entrenamiento)." % [wd.get("desc", ""), int(float(wd.get("boost", 0.5)) * 100.0)], 16)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(dl)
	var hv := VBoxContainer.new()
	top.add_child(hv)
	hv.add_child(UITheme.cost_row(Workers.hire_cost(type_id), 28, 16))
	var check := Workers.can_hire(type_id)
	var hb := UITheme.button("Contratar", func():
		var id := Workers.hire(type_id)
		if id >= 0:
			AudioManager.play("events/worker")
			EventBus.notify("¡%s se une a tu base!" % Workers.get_worker(id).name, "good")
			refresh(), Vector2(180, 52))
	hb.disabled = not check.ok
	hv.add_child(hb)
	if not check.ok:
		var r := UITheme.label(check.reason, 15, UITheme.BAD)
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.custom_minimum_size = Vector2(240, 0)
		hv.add_child(r)
	for w in Workers.hired:
		if w.type != type_id:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var where := "Sin asignar"
		if int(w.building) >= 0:
			var rec := Economy.get_building(int(w.building))
			if not rec.is_empty():
				where = "%s (nv %d)" % [GameData.building(rec.type).name, int(rec.level)]
		var l := UITheme.label("• %s · habilidad %d/%d · %s" % [w.name, int(w.skill), int(GameData.worker_settings.get("max_skill", 5)), where], 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UITheme.button("Asignar", _cycle_assign.bind(int(w.id)), Vector2(120, 46)))
		var tc := Workers.can_train(int(w.id))
		var tb := UITheme.button("Entrenar", func():
			if Workers.train(int(w.id)):
				AudioManager.play("events/upgrade", -4.0)
				refresh(), Vector2(130, 46))
		tb.disabled = not tc.ok
		tb.tooltip_text = tc.reason if not tc.ok else "Coste: " + _cost_text(Workers.train_cost(int(w.id)))
		row.add_child(tb)
		vb.add_child(row)
	return card


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		parts.append("%d %s" % [int(cost[id]), GameData.item_name(id)])
	return ", ".join(parts)


## Asigna al siguiente edificio compatible con hueco (o libera si no hay).
func _cycle_assign(worker_id: int) -> void:
	var w := Workers.get_worker(worker_id)
	var candidates: Array = []
	for rec in Economy.buildings:
		if GameData.building(rec.type).get("worker_type", "") == w.type:
			candidates.append(int(rec.uid))
	if candidates.is_empty():
		EventBus.notify("No hay edificios que acepten este trabajador.", "warn")
		return
	var start := candidates.find(int(w.building))
	for k in range(1, candidates.size() + 1):
		var uid: int = candidates[(start + k) % candidates.size()]
		if uid == int(w.building):
			continue
		if Workers.free_slots(uid) > 0:
			Workers.assign(worker_id, uid)
			refresh()
			return
	EventBus.notify("Todos los edificios compatibles están llenos. Mejóralos para tener más huecos.", "warn")
