class_name InventoryPanel
extends UIPanel
## Inventario en cuadrícula (pilas, iconos, durabilidad, equipo) y almacén
## compartido de la base (depositar/retirar cuando estás cerca de un almacén
## o del refugio).

var grid: GridContainer
var detail_icon: TextureRect
var detail_name: Label
var detail_desc: Label
var detail_stats: Label
var btn_use: Button
var btn_equip: Button
var btn_drop: Button
var capacity_label: Label
var storage_box: VBoxContainer
var storage_title: Label
var btn_deposit: Button
var selected := -1
var _slot_buttons: Array = []
var _tabs: TabBar
var _inv_view: Control
var _store_view: Control


func _init() -> void:
	super()
	title = "Inventario"
	size_ratio = Vector2(0.94, 0.92)


func _build() -> void:
	_tabs = TabBar.new()
	_tabs.add_tab("Mochila")
	_tabs.add_tab("Almacén de la base")
	_tabs.tab_changed.connect(func(_i): refresh())
	body.add_child(_tabs)
	# --- Mochila
	_inv_view = HBoxContainer.new()
	_inv_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_inv_view as HBoxContainer).add_theme_constant_override("separation", 14)
	body.add_child(_inv_view)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	_inv_view.add_child(left)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	left.add_child(bottom)
	capacity_label = UITheme.label("", 18)
	capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(capacity_label)
	bottom.add_child(UITheme.button("Ordenar", func():
		GameState.inventory.sort_items()
		GameState.validate_equipped()
		selected = -1
		refresh(), Vector2(140, 52)))
	btn_deposit = UITheme.button("Depositar recursos", _deposit, Vector2(250, 52))
	bottom.add_child(btn_deposit)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UITheme.box("panel_brown_dark", 20, 16))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(330, 0)
	_inv_view.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	detail_icon = TextureRect.new()
	detail_icon.custom_minimum_size = Vector2(110, 110)
	detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rv.add_child(detail_icon)
	detail_name = UITheme.label("", 24, UITheme.CREAM, true)
	rv.add_child(detail_name)
	detail_desc = UITheme.label("", 17, Color(0.95, 0.9, 0.8))
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(detail_desc)
	detail_stats = UITheme.label("", 17, Color(1.0, 0.92, 0.6))
	detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(detail_stats)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(spacer)
	btn_use = UITheme.button("Comer / beber", _use)
	rv.add_child(btn_use)
	btn_equip = UITheme.button("Equipar", _equip)
	rv.add_child(btn_equip)
	btn_drop = UITheme.button("Soltar 1", _drop)
	rv.add_child(btn_drop)
	# --- Almacén
	_store_view = VBoxContainer.new()
	_store_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_store_view)
	storage_title = UITheme.label("", 20, UITheme.BROWN, true)
	_store_view.add_child(storage_title)
	var sc2 := ScrollContainer.new()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_store_view.add_child(sc2)
	storage_box = VBoxContainer.new()
	storage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(storage_box)
	var sb := HBoxContainer.new()
	sb.add_theme_constant_override("separation", 10)
	_store_view.add_child(sb)
	sb.add_child(UITheme.button("Depositar recursos", _deposit, Vector2(260, 52)))
	sb.add_child(UITheme.button("Depositar todo (incl. comida)", func(): _deposit_all(false), Vector2(330, 52)))
	EventBus.inventory_changed.connect(func(): if is_open: refresh())
	EventBus.storage_changed.connect(func(): if is_open and _tabs.current_tab == 1: refresh())


func near_storage() -> bool:
	if hud == null or hud.world == null:
		return false
	var pos: Vector3 = hud.world.player.global_position
	for rec in Economy.buildings:
		if rec.type in ["almacen", "refugio"]:
			if Vector3(rec.pos[0], rec.pos[1], rec.pos[2]).distance_to(pos) < 9.0:
				return true
	return false


func open(d: Variant = null) -> void:
	if d is Dictionary and d.get("tab", "") == "storage":
		_tabs.current_tab = 1
	super(d)


func refresh() -> void:
	var inv := GameState.inventory
	_inv_view.visible = _tabs.current_tab == 0
	_store_view.visible = _tabs.current_tab == 1
	var near := near_storage()
	btn_deposit.disabled = not near
	btn_deposit.tooltip_text = "" if near else "Acércate a un almacén o al refugio"
	if _tabs.current_tab == 1:
		_refresh_storage(near)
		return
	if _slot_buttons.size() != inv.slots.size():
		UIPanel.clear_children(grid)
		_slot_buttons.clear()
		for i in inv.slots.size():
			var b := _make_slot(i)
			grid.add_child(b)
			_slot_buttons.append(b)
	var used := 0
	for i in inv.slots.size():
		_update_slot(i)
		if inv.slots[i] != null:
			used += 1
	capacity_label.text = "Capacidad: %d/%d huecos" % [used, inv.slots.size()]
	_refresh_detail()


func _make_slot(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(78, 78)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UITheme.box("panel_brown_dark", 16, 4))
	b.add_theme_stylebox_override("hover", UITheme.box("panel_brown_dark", 16, 4, Color(1.1, 1.05, 1.0)))
	b.add_theme_stylebox_override("pressed", UITheme.box("panel_brown_dark", 16, 4, Color(0.9, 0.85, 0.8)))
	var ic := TextureRect.new()
	ic.name = "Icon"
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 8
	ic.offset_top = 6
	ic.offset_right = -8
	ic.offset_bottom = -10
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var q := UITheme.hud_label("", 16)
	q.name = "Qty"
	q.anchor_left = 1.0
	q.anchor_right = 1.0
	q.anchor_top = 1.0
	q.anchor_bottom = 1.0
	q.offset_left = -44
	q.offset_top = -26
	q.offset_right = -6
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(q)
	var dur := ColorRect.new()
	dur.name = "Dur"
	dur.anchor_top = 1.0
	dur.anchor_bottom = 1.0
	dur.offset_left = 8
	dur.offset_top = -9
	dur.offset_bottom = -5
	dur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(dur)
	var eq := TextureRect.new()
	eq.name = "Eq"
	eq.texture = UITheme.tex("minimap_icon_star_yellow")
	eq.position = Vector2(4, 4)
	eq.size = Vector2(22, 22)
	eq.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(eq)
	b.pressed.connect(_on_slot.bind(i))
	return b


func _update_slot(i: int) -> void:
	var b: Button = _slot_buttons[i]
	var s: Variant = GameState.inventory.slots[i]
	var ic: TextureRect = b.get_node("Icon")
	var q: Label = b.get_node("Qty")
	var dur: ColorRect = b.get_node("Dur")
	var eq: TextureRect = b.get_node("Eq")
	b.modulate = Color(1.25, 1.2, 0.9) if i == selected else Color.WHITE
	if s == null:
		ic.texture = null
		q.text = ""
		dur.visible = false
		eq.visible = false
		b.tooltip_text = ""
		return
	ic.texture = GameData.item_icon(s.id)
	q.text = str(s.qty) if int(s.qty) > 1 else ""
	b.tooltip_text = GameData.item_name(s.id)
	var r := GameState.inventory.durability_ratio(i)
	dur.visible = GameData.is_tool(s.id) and r < 0.999
	dur.size.x = 62.0 * r
	dur.color = Color(0.3, 0.85, 0.3) if r > 0.4 else (Color(0.95, 0.7, 0.2) if r > 0.15 else Color(0.9, 0.2, 0.15))
	eq.visible = i == GameState.equipped_index


func _on_slot(i: int) -> void:
	var inv := GameState.inventory
	if selected >= 0 and selected != i and inv.slots[selected] != null:
		var eq_id := GameState.equipped_item_id()
		inv.move(selected, i)
		# Mantiene el equipo apuntando al objeto movido.
		if eq_id != "":
			for k in inv.slots.size():
				if inv.slots[k] != null and inv.slots[k].id == eq_id and (k == i or k == selected):
					GameState.equipped_index = k
					break
		selected = i
		AudioManager.play_ui("ui/drop")
	elif selected == i:
		selected = -1
	else:
		selected = i
		AudioManager.play_ui("ui/select")
	refresh()


func _refresh_detail() -> void:
	var inv := GameState.inventory
	var s: Variant = inv.slots[selected] if selected >= 0 and selected < inv.slots.size() else null
	if s == null:
		detail_icon.texture = null
		detail_name.text = "Selecciona un objeto"
		detail_desc.text = "Toca un hueco para ver sus detalles. Toca otro hueco después para moverlo."
		detail_stats.text = ""
		btn_use.disabled = true
		btn_equip.disabled = true
		btn_drop.disabled = true
		return
	var it := GameData.item(s.id)
	detail_icon.texture = GameData.item_icon(s.id)
	detail_name.text = "%s ×%d" % [it.name, int(s.qty)]
	detail_desc.text = str(it.get("desc", ""))
	var lines: Array[String] = []
	if it.has("food"):
		var f: Dictionary = it.food
		if float(f.get("hunger", 0)) != 0:
			lines.append("Hambre %+d" % int(f.hunger))
		if float(f.get("thirst", 0)) != 0:
			lines.append("Sed %+d" % int(f.thirst))
		if float(f.get("health", 0)) != 0:
			lines.append("Salud %+d" % int(f.health))
		if it.get("risky", false):
			lines.append("¡Puede enfermarte!")
	if it.has("tool"):
		var t: Dictionary = it.tool
		lines.append("Herramienta: %d por golpe" % int(t.get("power", 1)))
		if int(t.get("durability", 0)) > 0:
			lines.append("Durabilidad: %d%%" % int(inv.durability_ratio(selected) * 100.0))
	if it.has("weapon"):
		lines.append("Daño: %d" % int(it.weapon.damage))
	if it.has("container"):
		lines.append("Recoge %d de agua" % int(it.container.capacity))
	detail_stats.text = "\n".join(lines)
	btn_use.disabled = not it.has("food")
	btn_equip.disabled = not GameData.is_equippable(s.id)
	btn_equip.text = "Desequipar" if selected == GameState.equipped_index else "Equipar"
	btn_drop.disabled = false


func _use() -> void:
	if selected < 0:
		return
	hud.player.eat_slot(selected)
	if GameState.inventory.slots[selected] == null:
		selected = -1
	refresh()


func _equip() -> void:
	if selected < 0:
		return
	if selected == GameState.equipped_index:
		GameState.equip(-1)
	else:
		GameState.equip(selected)
		AudioManager.play_ui("ui/equip")
	refresh()


func _drop() -> void:
	if selected < 0:
		return
	var out := GameState.inventory.remove_at(selected, 1)
	if out.is_empty():
		return
	GameState.validate_equipped()
	var p: Player = hud.player
	hud.world.spawn_drop(out.id, int(out.qty), p.global_position + p.forward_dir() * 1.5)
	AudioManager.play_ui("ui/drop_item")
	if GameState.inventory.slots[selected] == null:
		selected = -1
	refresh()


func _deposit() -> void:
	_deposit_all(true)


func _deposit_all(only_resources: bool) -> void:
	if not near_storage():
		EventBus.notify("Acércate a un almacén o a tu refugio para depositar.", "warn")
		return
	var moved := Economy.deposit_from_inventory(only_resources)
	GameState.validate_equipped()
	if moved.is_empty():
		EventBus.notify("No hay nada que depositar (o el almacén está lleno).", "warn")
	else:
		var total := 0
		for id in moved:
			total += int(moved[id])
		EventBus.notify("Depositados %d objetos en el almacén." % total, "good")
		AudioManager.play_ui("ui/latch")
	selected = -1
	refresh()


func _refresh_storage(near: bool) -> void:
	UIPanel.clear_children(storage_box)
	storage_title.text = "Almacén compartido · capacidad %d por recurso%s" % [Economy.capacity(), "" if near else " (acércate a un almacén para retirar)"]
	var ids: Array = Economy.storage.keys()
	ids.sort_custom(func(a, b): return GameData.item_order.find(a) < GameData.item_order.find(b))
	if ids.is_empty():
		storage_box.add_child(UITheme.label("El almacén está vacío. Los edificios de producción depositan aquí lo que fabrican.", 18))
	for id in ids:
		var amount := Economy.stored(id)
		if amount <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UITheme.item_icon(id, 44))
		var name_l := UITheme.label(GameData.item_name(id), 19)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var pb := UITheme.progress_bar("green", 20)
		pb.custom_minimum_size = Vector2(160, 20)
		pb.value = float(amount) / maxf(float(Economy.capacity()), 1.0)
		row.add_child(pb)
		row.add_child(UITheme.label("%d/%d" % [amount, Economy.capacity()], 18))
		for n in [1, 10]:
			var b := UITheme.button("+%d" % n, _withdraw.bind(id, n), Vector2(70, 46))
			b.disabled = not near
			row.add_child(b)
		var all := UITheme.button("Todo", _withdraw.bind(id, 9999), Vector2(90, 46))
		all.disabled = not near
		row.add_child(all)
		storage_box.add_child(row)


func _withdraw(id: String, n: int) -> void:
	var got := Economy.withdraw(id, n)
	if got <= 0:
		EventBus.notify("No cabe más en el inventario.", "warn")
	else:
		AudioManager.play_ui("ui/drop")
	refresh()
