extends Node
## Exporta los rectángulos de los controles visibles del HUD (sin GPU) para
## revisar solapamientos: godot --headless --path . tests/tools/hud_layout.tscn -- 1280 720
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(1280, 720)
	if args.size() >= 2:
		size = Vector2i(int(args[0]), int(args[1]))
	get_tree().root.size = size
	SaveManager.enabled = false
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	for i in 10:
		await get_tree().process_frame
	var panel := args[2] if args.size() > 2 else ""
	if panel != "":
		var arg: Variant = null
		if panel == "building":
			var uid := Economy.place_building("lenador", world.player.global_position + Vector3(4, 0, 0), 0.0, true)
			arg = uid
		world.hud.open_panel(panel, arg)
		for i in 5:
			await get_tree().process_frame
	var out: Array = []
	_collect(world.hud.root, out, 0)
	var f := FileAccess.open("/tmp/hud_layout.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"size": [size.x, size.y], "rects": out}))
	f.close()
	print("rects: ", out.size())
	get_tree().quit()

func _collect(n: Node, out: Array, depth: int) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		var txt := ""
		if c is Label:
			txt = (c as Label).text
		elif c is Button:
			txt = (c as Button).text
		var kind := c.get_class()
		if r.size.x > 2 and r.size.y > 2 and r.size.x < get_viewport().get_visible_rect().size.x * 0.99:
			out.append({"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y, "name": str(c.name), "kind": kind, "text": txt, "depth": depth})
	for ch in n.get_children():
		_collect(ch, out, depth + 1)
