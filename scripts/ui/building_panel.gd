class_name BuildingPanel
extends UIPanel
## Panel de un edificio: nivel, estado, producción por minuto, receta,
## progreso, trabajadores, mejora (con comparación), reparación, demolición
## y acciones especiales (dormir, fabricar, almacén).

var uid := -1
var info: VBoxContainer
var progress_bar: ProgressBar
var status_label: Label
var _confirm_demolish := false


func _init() -> void:
	super()
	title = "Edificio"
	size_ratio = Vector2(0.78, 0.92)


func _build() -> void:
	status_label = UITheme.label("", 19, UITheme.BROWN, true)
	body.add_child(status_label)
	progress_bar = UITheme.progress_bar("green", 26)
	body.add_child(progress_bar)
	info = make_scroll()
	EventBus.building_upgraded.connect(func(u, _t, _l): if is_open and u == uid: refresh())
	EventBus.building_repaired.connect(func(u): if is_open and u == uid: refresh())
	EventBus.workers_changed.connect(func(): if is_open: refresh())


func open(d: Variant = null) -> void:
	uid = int(d) if d != null else -1
	_confirm_demolish = false
	super(d)


func refresh() -> void:
	var rec := Economy.get_building(uid)
	if rec.is_empty():
		close()
		return
	var bd := GameData.building(rec.type)
	var lvl := Economy.level_data(rec)
	title_label.text = "%s · Nivel %d/%d" % [bd.name, int(rec.level), GameData.building_max_level(rec.type)]
	UIPanel.clear_children(info)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	info.add_child(top)
	var thumb := TextureRect.new()
	var tp := "res://assets/icons/buildings/%s.png" % rec.type
	thumb.texture = load(tp) if ResourceLoader.exists(tp) else null
	thumb.custom_minimum_size = Vector2(120, 120)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(thumb)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(UITheme.label(str(lvl.get("name", "")), 22, UITheme.BROWN, true))
	var d := UITheme.label(str(bd.get("desc", "")), 16)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(d)
	var hp_ratio := float(rec.hp) / maxf(Economy.max_hp(rec), 1.0)
	tv.add_child(UITheme.label("Integridad: %d/%d" % [int(rec.hp), int(Economy.max_hp(rec))], 17, UITheme.GOOD if hp_ratio > 0.5 else UITheme.BAD))
	var extras: Array[String] = []
	if int(lvl.get("storage", 0)) > 0:
		extras.append("+%d de almacén" % int(lvl.storage))
	if int(lvl.get("housing", 0)) > 0:
		extras.append("Aloja %d trabajadores" % int(lvl.housing))
	if float(lvl.get("light", 0)) > 0:
		extras.append("Luz: %.0f m" % float(lvl.light))
	if lvl.has("tower_range"):
		extras.append("Defensa: %d daño, %.0f m" % [int(lvl.tower_damage), float(lvl.tower_range)])
	if not extras.is_empty():
		tv.add_child(UITheme.label(" · ".join(extras), 16, UITheme.BROWN_LIGHT))
	_special_actions(rec, bd)
	_production_section(rec, bd)
	_workers_section(rec, bd)
	_upgrade_section(rec, bd)
	_maintenance_section(rec, bd)


func _section(text: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box("panel_brown", 20, 12, Color(0.96, 0.92, 0.85)))
	info.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	vb.add_child(UITheme.label(text, 20, UITheme.BROWN, true))
	return vb


func _special_actions(rec: Dictionary, bd: Dictionary) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	var any := false
	if bd.get("interact", "") == "rest":
		row.add_child(UITheme.button("Dormir hasta el amanecer", func():
			if hud.world.try_sleep():
				close(), Vector2(320, 54)))
		any = true
	if bd.has("station"):
		var st := str(bd.station)
		if st in ["fogata", "taller", "fundicion"]:
			row.add_child(UITheme.button("Fabricar aquí", func(): hud.open_panel("crafting", {"station": st}), Vector2(220, 54)))
			any = true
	if rec.type in ["almacen", "refugio"]:
		row.add_child(UITheme.button("Abrir almacén", func(): hud.open_panel("inventory", {"tab": "storage"}), Vector2(220, 54)))
		row.add_child(UITheme.button("Depositar recursos", func():
			var moved := Economy.deposit_from_inventory(true)
			GameState.validate_equipped()
			var total := 0
			for id in moved:
				total += int(moved[id])
			EventBus.notify("Depositados %d objetos." % total if total > 0 else "Nada que depositar.", "good" if total > 0 else "warn")
			refresh(), Vector2(240, 54)))
		any = true
	if any:
		info.add_child(row)


func _production_section(rec: Dictionary, bd: Dictionary) -> void:
	var prods: Array = bd.get("production", [])
	if prods.is_empty():
		return
	var vb := _section("Producción")
	if prods.size() > 1:
		var opt := HFlowContainer.new()
		opt.add_theme_constant_override("h_separation", 8)
		for i in prods.size():
			var p: Dictionary = prods[i]
			var unlocked := TechTree.is_unlocked(p.get("unlock"))
			var b := UITheme.button(("✓ " if int(rec.recipe) == i else "") + str(p.name), func():
				Economy.set_recipe(uid, i)
				refresh(), Vector2(0, 48))
			b.disabled = not unlocked
			if not unlocked:
				b.tooltip_text = "Requiere: %s" % GameData.tech(p.unlock).get("name", "")
			opt.add_child(b)
		vb.add_child(opt)
	var p := Economy.production_of(rec)
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 8)
	var ins := Economy.inputs_for(rec)
	if not ins.is_empty():
		line.add_child(UITheme.label("Consume:", 17))
		for id in ins:
			line.add_child(UITheme.item_icon(id, 28))
			line.add_child(UITheme.label("%s" % UITheme.fmt_num(float(ins[id])), 17))
		line.add_child(UITheme.label("  →  ", 17))
	line.add_child(UITheme.label("Produce:", 17))
	var outs := Economy.outputs_for(rec)
	for id in outs:
		line.add_child(UITheme.item_icon(id, 28))
		line.add_child(UITheme.label("%s" % UITheme.fmt_num(float(outs[id])), 17))
	if float(p.get("energy", 0)) > 0:
		line.add_child(UITheme.label("⚡ +%s energía" % UITheme.fmt_num(Economy.energy_of(rec)), 17, UITheme.GOOD))
	elif float(p.get("energy", 0)) < 0:
		line.add_child(UITheme.label("⚡ %s energía" % UITheme.fmt_num(float(p.energy)), 17, UITheme.WARN))
	vb.add_child(line)
	var ct := Economy.cycle_time(rec)
	var rate := Economy.building_rate(rec)
	var rate_parts: Array[String] = []
	for id in rate:
		rate_parts.append("%s %s/min" % [UITheme.fmt_num(float(rate[id])), GameData.item_name(id)])
	vb.add_child(UITheme.label("Ciclo: %.1f s · %s" % [ct, ", ".join(rate_parts)], 17, UITheme.GOOD))
	vb.add_child(UITheme.label("Velocidad total ×%.2f (nivel, tecnología, trabajadores, estado)" % Economy.speed_mult(rec), 15, UITheme.BROWN_LIGHT))


func _workers_section(rec: Dictionary, bd: Dictionary) -> void:
	if not bd.has("worker_type"):
		return
	var slots := Economy.worker_slots(uid)
	if slots <= 0:
		return
	var wt: String = bd.worker_type
	var vb := _section("Trabajadores (%s)" % Workers.type_data(wt).get("name", wt))
	var list := Workers.workers_in(uid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	row.add_child(UITheme.label("%d/%d asignados · ×%.2f velocidad" % [list.size(), slots, Workers.multiplier(uid)], 17))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var minus := UITheme.button("−", func():
		Workers.remove_one(uid)
		refresh(), Vector2(60, 50))
	minus.disabled = list.is_empty()
	row.add_child(minus)
	var plus := UITheme.button("+", func():
		if not Workers.assign_any(uid):
			EventBus.notify("No hay %ss libres. Contrata más en Trabajadores." % Workers.type_data(wt).get("name", "trabajador").to_lower(), "warn")
		refresh(), Vector2(60, 50))
	plus.disabled = list.size() >= slots or Workers.idle_of_type(wt) <= 0
	row.add_child(plus)
	row.add_child(UITheme.button("Contratar", func(): hud.open_panel("workers", wt), Vector2(150, 50)))
	for w in list:
		vb.add_child(UITheme.label("• %s — habilidad %d" % [w.name, int(w.skill)], 16, UITheme.BROWN_LIGHT))


func _upgrade_section(rec: Dictionary, bd: Dictionary) -> void:
	var max_level := GameData.building_max_level(rec.type)
	if int(rec.level) >= max_level:
		var vb0 := _section("Mejora")
		vb0.add_child(UITheme.label("Nivel máximo alcanzado.", 17, UITheme.GOOD))
		return
	var vb := _section("Mejorar a nivel %d" % (int(rec.level) + 1))
	var cur := Economy.level_data(rec)
	var nxt := GameData.building_level(rec.type, int(rec.level) + 1)
	vb.add_child(UITheme.label(str(nxt.get("name", "")), 18, UITheme.BROWN, true))
	var cmp: Array[String] = []
	for key in [["speed", "Velocidad ×%.2f → ×%.2f"], ["output", "Producción ×%.2f → ×%.2f"], ["input", "Consumo ×%.2f → ×%.2f"]]:
		if not bd.get("production", []).is_empty() and absf(float(cur.get(key[0], 1.0)) - float(nxt.get(key[0], 1.0))) > 0.001:
			cmp.append(key[1] % [float(cur.get(key[0], 1.0)), float(nxt.get(key[0], 1.0))])
	for key in [["workers", "Trabajadores %d → %d"], ["storage", "Almacén +%d → +%d"], ["housing", "Alojamiento %d → %d"], ["hp", "Integridad %d → %d"]]:
		if int(cur.get(key[0], 0)) != int(nxt.get(key[0], 0)):
			cmp.append(key[1] % [int(cur.get(key[0], 0)), int(nxt.get(key[0], 0))])
	if float(cur.get("light", 0)) != float(nxt.get("light", 0)):
		cmp.append("Luz %.0f → %.0f m" % [float(cur.get("light", 0)), float(nxt.get("light", 0))])
	if float(cur.get("craft_speed", 1)) != float(nxt.get("craft_speed", 1)):
		cmp.append("Fabricación ×%.2f → ×%.2f" % [float(cur.get("craft_speed", 1)), float(nxt.get("craft_speed", 1))])
	var cmp_l := UITheme.label("\n".join(cmp), 16, UITheme.GOOD)
	vb.add_child(cmp_l)
	vb.add_child(UITheme.cost_row(Economy.upgrade_cost(uid), 30, 17))
	var check := Economy.can_upgrade(uid)
	var b := UITheme.button("Mejorar", func():
		if Economy.upgrade(uid):
			refresh(), Vector2(220, 54))
	b.disabled = not check.ok
	vb.add_child(b)
	if not check.ok:
		vb.add_child(UITheme.label(check.reason, 15, UITheme.BAD))


func _maintenance_section(rec: Dictionary, bd: Dictionary) -> void:
	var vb := _section("Mantenimiento")
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	vb.add_child(row)
	var cost := Economy.repair_cost(uid)
	if not cost.is_empty():
		row.add_child(UITheme.cost_row(cost, 28, 16))
		var rb := UITheme.button("Reparar", func():
			if Economy.repair(uid):
				AudioManager.play_at("build/hammer", Vector3(rec.pos[0], rec.pos[1], rec.pos[2]))
				refresh()
			else:
				EventBus.notify("Faltan materiales para reparar.", "warn"), Vector2(170, 52))
		rb.disabled = not Economy.can_afford(cost)
		row.add_child(rb)
	else:
		row.add_child(UITheme.label("En perfecto estado.", 17, UITheme.GOOD))
	if rec.type != "refugio" or Economy.count_of("refugio") > 1:
		var db := UITheme.button("¿Demoler? Pulsa otra vez" if _confirm_demolish else "Demoler (recuperas 50%)", func():
			if not _confirm_demolish:
				_confirm_demolish = true
				refresh()
				return
			Economy.demolish(uid)
			close(), Vector2(330, 52))
		db.add_theme_stylebox_override("normal", UITheme.box("button_red", 14, 12))
		row.add_child(db)


func _process(_delta: float) -> void:
	if not is_open:
		return
	var rec := Economy.get_building(uid)
	if rec.is_empty():
		close()
		return
	var has_prod: bool = not GameData.building(rec.type).get("production", []).is_empty()
	progress_bar.visible = has_prod
	if has_prod:
		progress_bar.value = float(rec.get("progress", 0.0))
		status_label.text = "Estado: %s" % rec.get("status", "")
		var ok: bool = rec.get("status", "") == Economy.STATUS_OK
		status_label.add_theme_color_override("font_color", UITheme.GOOD if ok else UITheme.WARN)
	else:
		status_label.text = ""
