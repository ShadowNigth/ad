class_name UIPanel
extends Control
## Base de las ventanas de la interfaz: fondo oscurecido, marco con título y
## botón de cierre. Las subclases construyen su contenido en _build().

signal closed

var hud: Node
var title := "Panel"
var body: VBoxContainer
var frame: PanelContainer
var title_label: Label
var header: HBoxContainer
var size_ratio := Vector2(0.9, 0.9)
var data: Variant = null
var is_open := false
var pauses_game := false
var _tw: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func setup(hud_ref: Node) -> void:
	hud = hud_ref
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	frame = PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	add_child(frame)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	frame.add_child(outer)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	outer.add_child(header)
	title_label = UITheme.label(title, 28, UITheme.BROWN, true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close_btn := UITheme.round_button(UITheme.icon("cross"), close, 56.0)
	close_btn.name = "Cerrar"
	header.add_child(close_btn)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	outer.add_child(body)
	_build()
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if frame == null:
		return
	var vs := get_viewport_rect().size
	var s := Vector2(vs.x * size_ratio.x, vs.y * size_ratio.y)
	frame.custom_minimum_size = s
	frame.size = s
	frame.position = (vs - s) * 0.5


## Las subclases añaden aquí sus controles a `body`.
func _build() -> void:
	pass


func refresh() -> void:
	pass


func open(d: Variant = null) -> void:
	data = d
	title_label.text = title
	is_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	refresh()
	modulate = Color(1, 1, 1, 0)
	frame.scale = Vector2(0.94, 0.94)
	frame.pivot_offset = frame.size * 0.5
	if _tw:
		_tw.kill()
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(self, "modulate:a", 1.0, 0.12)
	_tw.tween_property(frame, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_ui("ui/open")
	if pauses_game:
		get_tree().paused = true


func close() -> void:
	if not is_open:
		return
	is_open = false
	AudioManager.play_ui("ui/close")
	if pauses_game:
		get_tree().paused = false
	closed.emit()
	# Se encoge y desvanece; se oculta al terminar (si no se ha vuelto a abrir).
	if _tw:
		_tw.kill()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.pivot_offset = frame.size * 0.5
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(self, "modulate:a", 0.0, 0.1)
	_tw.tween_property(frame, "scale", Vector2(0.95, 0.95), 0.1)
	_tw.chain().tween_callback(func():
		if not is_open:
			visible = false)


func _process(_delta: float) -> void:
	pass


## Contenedor desplazable que ocupa el espacio restante del cuerpo.
func make_scroll() -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	sc.add_child(vb)
	return vb


static func clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
