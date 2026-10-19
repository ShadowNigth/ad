class_name MapPanel
extends UIPanel
## Mapa de la isla generado desde el relieve real, con el jugador, los
## edificios, los lugares de interés (con Cartografía) y la mochila perdida.

var map_rect: TextureRect
var overlay: Control
var legend: Label


func _init() -> void:
	super()
	title = "Mapa de la isla"
	size_ratio = Vector2(0.8, 0.95)


func _build() -> void:
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 12)
	body.add_child(hb)
	var holder := AspectRatioContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.size_flags_stretch_ratio = 2.2
	hb.add_child(holder)
	map_rect = TextureRect.new()
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	holder.add_child(map_rect)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	map_rect.add_child(overlay)
	legend = UITheme.label("", 17)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(legend)


func refresh() -> void:
	map_rect.texture = hud.world.map_texture
	var lines: Array[String] = ["▲ Tú", "■ Edificios"]
	if TechTree.mod("map_markers") > 0.0:
		lines.append("● Lugares de interés")
	else:
		lines.append("(Investiga «Cartografía» para ver los lugares de interés)")
	if not GameState.lost_backpack.is_empty():
		lines.append("◆ Mochila perdida")
	var regions: Array[String] = []
	for r in ["jungla", "cueva"]:
		regions.append("%s: %s" % ["Jungla de las ruinas" if r == "jungla" else "Cueva de cristal", "abierta" if GameState.is_region_unlocked(r) else "bloqueada"])
	lines.append("")
	lines.append("Regiones:")
	lines.append_array(regions)
	var zone: String = hud.world.gen.zone_at(hud.player.global_position.x, hud.player.global_position.z)
	lines.append("")
	lines.append("Estás en: %s" % GameData.world.get("zones", {}).get(zone, {}).get("name", zone))
	legend.text = "\n".join(lines)
	overlay.queue_redraw()


func _to_map(p: Vector3) -> Vector2:
	var gen: IslandGenerator = hud.world.gen
	var s := overlay.size
	return Vector2((p.x + gen.half) / gen.size * s.x, (p.z + gen.half) / gen.size * s.y)


func _draw_overlay() -> void:
	if hud == null:
		return
	var font := UITheme.font_title
	for rec in Economy.buildings:
		var mp := _to_map(Vector3(rec.pos[0], rec.pos[1], rec.pos[2]))
		overlay.draw_rect(Rect2(mp - Vector2(5, 5), Vector2(10, 10)), Color(0.95, 0.85, 0.45))
		overlay.draw_rect(Rect2(mp - Vector2(5, 5), Vector2(10, 10)), Color(0.3, 0.2, 0.1), false, 2.0)
	if TechTree.mod("map_markers") > 0.0:
		for m in hud.world.pois.map_markers:
			if m.type in ["chest"]:
				continue
			var mp := _to_map(m.pos)
			overlay.draw_circle(mp, 6.0, Color(0.85, 0.25, 0.2))
			overlay.draw_string(font, mp + Vector2(8, 5), m.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.15, 0.08, 0.04))
	var bp: Variant = hud.world.backpack_position()
	if bp != null:
		var mp: Vector2 = _to_map(bp)
		var pts := PackedVector2Array([mp + Vector2(0, -8), mp + Vector2(8, 0), mp + Vector2(0, 8), mp + Vector2(-8, 0)])
		overlay.draw_colored_polygon(pts, Color(1, 0.85, 0.2))
	var pp := _to_map(hud.player.global_position)
	var a: float = -hud.player.rig.rotation.y
	var fwd := Vector2(0, -1).rotated(a)
	var right := Vector2(1, 0).rotated(a)
	var tri := PackedVector2Array([pp + fwd * 13.0, pp - fwd * 7.0 + right * 8.0, pp - fwd * 7.0 - right * 8.0])
	overlay.draw_colored_polygon(tri, Color(1, 1, 1))
	overlay.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.1, 0.1, 0.1), 2.0)


func _process(_delta: float) -> void:
	if is_open:
		overlay.queue_redraw()
