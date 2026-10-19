class_name OfflinePanel
extends UIPanel
## Resumen de bienvenida con lo producido mientras no jugabas.

var content: VBoxContainer


func _init() -> void:
	super()
	title = "¡Bienvenido de nuevo!"
	size_ratio = Vector2(0.62, 0.8)


func _build() -> void:
	content = make_scroll()
	body.add_child(UITheme.button("¡A seguir!", close, Vector2(0, 60)))


func refresh() -> void:
	UIPanel.clear_children(content)
	var rep: Dictionary = data if data is Dictionary else {}
	var elapsed := float(rep.get("elapsed", 0.0))
	var l := UITheme.label("Has estado fuera %s." % UITheme.fmt_time(elapsed), 21, UITheme.BROWN, true)
	content.add_child(l)
	if rep.get("capped", false):
		content.add_child(UITheme.label("La producción sin conexión se limita a %.0f horas (amplíalo con Logística)." % float(rep.get("cap_hours", 8.0)), 17, UITheme.WARN))
	content.add_child(UITheme.label("Tus edificios y trabajadores siguieron produciendo (el hambre y la sed no avanzan sin conexión):", 17))
	var items: Dictionary = rep.get("items", {})
	var any := false
	for id in items:
		var v := int(items[id])
		if v == 0:
			continue
		any = true
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		hb.add_child(UITheme.item_icon(id, 42))
		hb.add_child(UITheme.label("%s%d %s" % ["+" if v > 0 else "", v, GameData.item_name(id)], 20, UITheme.GOOD if v > 0 else UITheme.BAD))
		content.add_child(hb)
	if int(rep.get("research", 0)) > 0:
		content.add_child(UITheme.label("+%d puntos de tecnología" % int(rep.research), 20, UITheme.GOOD))
	if not any and int(rep.get("research", 0)) <= 0:
		content.add_child(UITheme.label("No se produjo nada: construye edificios de producción y asegúrate de que tengan materiales y espacio en el almacén.", 18))
	AudioManager.play("events/reward")
