class_name UITheme
extends RefCounted
## Tema visual (Kenney UI Pack Adventure) y utilidades para crear controles
## táctiles grandes y coherentes.

const TEX := "res://assets/textures/ui/%s.png"
const ICON := "res://assets/icons/ui/%s.png"
const CTRL := "res://assets/textures/controls/%s.png"
const BROWN := Color(0.29, 0.18, 0.1)
const BROWN_LIGHT := Color(0.55, 0.36, 0.2)
const CREAM := Color(1.0, 0.95, 0.84)
const GOOD := Color(0.24, 0.55, 0.2)
const BAD := Color(0.75, 0.2, 0.15)
const WARN := Color(0.85, 0.5, 0.1)

static var _theme: Theme
static var font_title: FontVariation
static var font_body: FontVariation


static func tex(name: String) -> Texture2D:
	var p := TEX % name
	return load(p) if ResourceLoader.exists(p) else null


static func icon(name: String) -> Texture2D:
	var p := ICON % name
	return load(p) if ResourceLoader.exists(p) else null


static func ctrl(name: String) -> Texture2D:
	var p := CTRL % name
	return load(p) if ResourceLoader.exists(p) else null


static func box(name: String, margin: int, content: int = 14, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(name)
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = content * 0.8
	sb.content_margin_bottom = content * 0.8
	sb.modulate_color = modulate
	return sb


static func flat(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT, bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var title_file: FontFile = load("res://assets/fonts/Fredoka.ttf")
	var body_file: FontFile = load("res://assets/fonts/Nunito.ttf")
	font_title = FontVariation.new()
	font_title.base_font = title_file
	font_title.variation_opentype = {"wght": 600}
	font_body = FontVariation.new()
	font_body.base_font = body_file
	font_body.variation_opentype = {"wght": 700}
	t.default_font = font_body
	t.default_font_size = 20
	# Paneles
	t.set_stylebox("panel", "PanelContainer", box("panel_brown", 20, 18))
	t.set_stylebox("panel", "Panel", box("panel_brown", 20, 18))
	# Botones
	var normal := box("button_brown", 14, 12)
	var hover := box("button_brown", 14, 12, Color(1.06, 1.04, 0.98))
	var pressed := box("button_brown", 14, 12, Color(0.85, 0.8, 0.72))
	var disabled := box("button_grey", 14, 12)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, BROWN)
		t.set_color("font_hover_color", cls, BROWN)
		t.set_color("font_pressed_color", cls, BROWN)
		t.set_color("font_disabled_color", cls, Color(0.25, 0.27, 0.32))
		t.set_font("font", cls, font_title)
		t.set_font_size("font_size", cls, 21)
	t.set_color("font_color", "Label", BROWN)
	t.set_font_size("font_size", "Label", 20)
	t.set_color("default_color", "RichTextLabel", BROWN)
	t.set_font("normal_font", "RichTextLabel", font_body)
	t.set_font("bold_font", "RichTextLabel", font_title)
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	t.set_font_size("bold_font_size", "RichTextLabel", 20)
	# Barras
	var bg := box("progress_transparent", 15, 0)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", box("progress_green", 15, 0))
	t.set_color("font_color", "ProgressBar", BROWN)
	# Deslizadores
	t.set_stylebox("slider", "HSlider", flat(Color(0.55, 0.36, 0.2, 0.85), 6))
	t.set_stylebox("grabber_area", "HSlider", flat(Color(0.35, 0.65, 0.3), 6))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(Color(0.45, 0.75, 0.35), 6))
	t.set_icon("grabber", "HSlider", _circle_tex(30, Color(0.98, 0.93, 0.8), BROWN))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(30, Color(1, 1, 0.9), BROWN))
	# Desplazamiento
	t.set_stylebox("scroll", "VScrollBar", flat(Color(0.4, 0.26, 0.14, 0.35), 8))
	t.set_stylebox("grabber", "VScrollBar", flat(Color(0.55, 0.36, 0.2, 0.9), 8))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(Color(0.65, 0.45, 0.25, 0.95), 8))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(Color(0.45, 0.3, 0.15, 1.0), 8))
	# Pestañas
	t.set_stylebox("tab_selected", "TabBar", box("button_brown", 14, 10))
	t.set_stylebox("tab_unselected", "TabBar", box("button_brown", 14, 10, Color(0.78, 0.72, 0.64)))
	t.set_stylebox("tab_hovered", "TabBar", box("button_brown", 14, 10, Color(0.92, 0.88, 0.8)))
	t.set_font("font", "TabBar", font_title)
	t.set_color("font_selected_color", "TabBar", BROWN)
	t.set_color("font_unselected_color", "TabBar", Color(0.35, 0.25, 0.15))
	t.set_color("font_hovered_color", "TabBar", BROWN)
	t.set_font_size("font_size", "TabBar", 19)
	# Ventanas emergentes (OptionButton)
	t.set_stylebox("panel", "PopupMenu", box("panel_brown", 20, 12))
	t.set_color("font_color", "PopupMenu", BROWN)
	t.set_color("font_hover_color", "PopupMenu", Color(0.1, 0.05, 0.0))
	t.set_font_size("font_size", "PopupMenu", 21)
	t.set_stylebox("hover", "PopupMenu", flat(Color(0.85, 0.7, 0.45, 0.6), 6))
	t.set_stylebox("tooltip", "TooltipPanel", box("panel_brown", 20, 10))
	_theme = t
	return t


static func _circle_tex(size: int, fill: Color, border: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			if d <= c - 3.0:
				img.set_pixel(x, y, fill)
			elif d <= c:
				img.set_pixel(x, y, border)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ fábricas de controles
static func label(text: String, size: int = 20, color: Color = BROWN, title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if title:
		get_theme()
		l.add_theme_font_override("font", font_title)
	return l


static func hud_label(text: String, size: int = 20) -> Label:
	var l := label(text, size, Color.WHITE, true)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.05, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func button(text: String, callback: Callable, min_size: Vector2 = Vector2(0, 54)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): AudioManager.play_ui("ui/click"))
	b.pressed.connect(callback)
	return b


## Botón redondo con icono (barra de menús y acciones táctiles).
static func round_button(icon_tex: Texture2D, callback: Callable, size: float = 72.0, base: String = "round_brown") -> TextureButton:
	var b := TouchButton.new()
	b.texture_normal = tex(base)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	var ic := TextureRect.new()
	ic.texture = icon_tex
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = size * 0.2
	ic.offset_right = -size * 0.2
	ic.offset_top = size * 0.2
	ic.offset_bottom = -size * 0.2
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.modulate = BROWN
	ic.name = "Icon"
	b.add_child(ic)
	b.pressed.connect(func(): AudioManager.play_ui("ui/click"))
	b.pressed.connect(callback)
	b.button_down.connect(func(): b.scale = Vector2(0.92, 0.92))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	return b


static func item_icon(id: String, size: float = 40.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = GameData.item_icon(id)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Fila con iconos y cantidades de un coste (verde si se tiene, rojo si falta).
static func cost_row(cost: Dictionary, size: float = 32.0, font_size: int = 18) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	for id in cost:
		var have := Economy.total_available(id)
		var need := int(cost[id])
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		hb.add_child(item_icon(id, size))
		var l := label("%d/%d" % [mini(have, 9999), need], font_size, GOOD if have >= need else BAD)
		l.tooltip_text = GameData.item_name(id)
		hb.add_child(l)
		hb.tooltip_text = GameData.item_name(id)
		row.add_child(hb)
	return row


static func progress_bar(color_name: String = "green", height: float = 26.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(80, height)
	pb.show_percentage = false
	pb.add_theme_stylebox_override("fill", box("progress_%s" % color_name, 15, 0))
	pb.max_value = 1.0
	pb.step = 0.0
	return pb


static func fmt_num(v: float) -> String:
	if absf(v) >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if absf(v) >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	if absf(v - round(v)) < 0.05:
		return str(int(round(v)))
	return "%.1f" % v


static func fmt_time(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d h %02d min" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d min %02d s" % [s / 60, s % 60]
	return "%d s" % s
