class_name DeathPanel
extends UIPanel
## Pantalla de muerte: explica qué se perdió y permite reaparecer.

var info: Label


func _init() -> void:
	super()
	title = "Has caído"
	size_ratio = Vector2(0.6, 0.62)


func _build() -> void:
	info = UITheme.label("", 19)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(info)
	body.add_child(UITheme.button("Reaparecer", _respawn, Vector2(0, 64)))
	# Tras morir solo se puede reaparecer: se oculta la cruz de cierre.
	header.get_node("Cerrar").visible = false


func refresh() -> void:
	var lines: Array[String] = ["Pierdes la mitad de los recursos que llevabas encima (las herramientas se conservan)."]
	var bp := GameState.lost_backpack
	if not bp.is_empty():
		var parts: Array[String] = []
		for id in bp.get("items", {}):
			parts.append("%d %s" % [int(bp.items[id]), GameData.item_name(id)])
		lines.append("Se han quedado en una mochila donde caíste: %s." % ", ".join(parts))
		lines.append("Puedes recuperarla durante 30 minutos (aparece en el mapa).")
	lines.append("Tu base, el almacén y tus edificios no se ven afectados.")
	info.text = "\n\n".join(lines)


func _respawn() -> void:
	close()
	hud.world.respawn_player()
