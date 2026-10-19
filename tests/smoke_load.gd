extends SceneTree
## Carga todos los scripts y escenas del proyecto para detectar errores de
## sintaxis/referencias. Uso: godot --headless --path . -s tests/smoke_load.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := 0
	var files := []
	_collect("res://scripts", files)
	_collect("res://scenes", files)
	for f in files:
		var res = load(f)
		if res == null:
			printerr("FALLO al cargar: ", f)
			failures += 1
		elif res is GDScript and not res.can_instantiate():
			printerr("Script no instanciable: ", f)
			failures += 1
	print("Cargados %d archivos, %d fallos" % [files.size(), failures])
	quit(1 if failures > 0 else 0)


func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			if not n.begins_with("."):
				_collect(dir + "/" + n, out)
		elif n.ends_with(".gd") or n.ends_with(".tscn"):
			out.append(dir + "/" + n)
		n = d.get_next()
