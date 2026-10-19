extends Node
## Herramienta de depuración: genera la isla y guarda un mapa anotado en PNG
## (zonas, río, caminos, puntos de interés, nodos de recursos, aparición).
## Uso: godot --headless --path . tests/tools/debug_map.tscn -- /ruta/salida.png

func _ready() -> void:
	var out_path := "/tmp/isla_mapa.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	var gen := IslandGenerator.new(GameData.world, int(GameData.b("world.seed", 1)))
	var t0 := Time.get_ticks_msec()
	gen.generate()
	print("generate: ", Time.get_ticks_msec() - t0, " ms")
	t0 = Time.get_ticks_msec()
	var img := gen.build_map_image(512)
	print("map image: ", Time.get_ticks_msec() - t0, " ms")
	var scale := 512.0 / gen.size
	var to_px := func(x: float, z: float) -> Vector2i:
		return Vector2i(int((x + gen.half) * scale), int((z + gen.half) * scale))
	# Nodos de recursos
	var rm := ResourceNodeManager.new()
	add_child(rm)
	var pm := PoiManager.new()
	rm.setup(gen, pm.compute_exclusions(gen))
	var colors := {"palmera": Color(0.1, 0.5, 0.1), "arbol": Color(0.0, 0.35, 0.0), "arbol_oscuro": Color(0.0, 0.2, 0.05), "pino": Color(0.1, 0.4, 0.3),
		"roca": Color(0.4, 0.4, 0.4), "roca_hierro": Color(0.8, 0.4, 0.2), "roca_carbon": Color(0.1, 0.1, 0.1), "cristal": Color(0.3, 0.9, 1.0),
		"arbusto_bayas": Color(0.8, 0.1, 0.3), "hierba_alta": Color(0.6, 0.9, 0.3), "banco_peces": Color(1, 1, 1)}
	var counts := {}
	for rec in rm.nodes:
		counts[rec.type] = int(counts.get(rec.type, 0)) + 1
		var c: Color = colors.get(rec.type, Color(0.9, 0.9, 0.2))
		var p: Vector2i = to_px.call(rec.pos.x, rec.pos.z)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var q := p + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < 512 and q.y < 512:
					img.set_pixelv(q, c)
	print("nodos por tipo: ", counts)
	for poi in GameData.world.pois:
		var p: Vector2i = to_px.call(float(poi.pos[0]), float(poi.pos[1]))
		for dx in range(-4, 5):
			for dy in range(-4, 5):
				if abs(dx) + abs(dy) <= 5:
					var q := p + Vector2i(dx, dy)
					if q.x >= 0 and q.y >= 0 and q.x < 512 and q.y < 512:
						img.set_pixelv(q, Color(1, 0, 1))
		print("POI %s (%s): altura %.2f zona %s región '%s'" % [poi.id, poi.type, gen.height_at(poi.pos[0], poi.pos[1]), gen.zone_at(poi.pos[0], poi.pos[1]), gen.region_at(poi.pos[0], poi.pos[1])])
	var sp: Array = GameData.world.spawn
	var spx: Vector2i = to_px.call(float(sp[0]), float(sp[1]))
	for dx in range(-5, 6):
		img.set_pixelv(spx + Vector2i(dx, 0), Color(1, 1, 0))
		img.set_pixelv(spx + Vector2i(0, dx), Color(1, 1, 0))
	print("spawn altura %.2f zona %s" % [gen.height_at(sp[0], sp[1]), gen.zone_at(sp[0], sp[1])])
	var zc := {}
	for z in gen.zones:
		zc[IslandGenerator.ZONE_IDS[z]] = int(zc.get(IslandGenerator.ZONE_IDS[z], 0)) + 1
	print("celdas por zona: ", zc)
	img.save_png(out_path)
	print("guardado ", out_path)
	get_tree().quit(0)
