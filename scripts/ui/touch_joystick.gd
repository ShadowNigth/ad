class_name TouchJoystick
extends Control
## Joystick virtual (zona inferior izquierda). Aparece donde se apoya el
## pulgar. Empujarlo hasta el borde activa la carrera.

signal moved(vector: Vector2, sprint: bool)

@export var radius := 95.0
@export var deadzone := 0.12
@export var sprint_threshold := 0.93

var _touch_index := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO
var _pad_tex: Texture2D
var _nub_tex: Texture2D
var _rest_center := Vector2.ZERO
var value := Vector2.ZERO
var sprinting := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pad_tex = UITheme.ctrl("joystick_circle_pad_a")
	_nub_tex = UITheme.ctrl("joystick_circle_nub_a")
	resized.connect(_reset_rest)
	_reset_rest()


func _reset_rest() -> void:
	_rest_center = Vector2(radius + 30.0, size.y - radius - 30.0)
	if _touch_index < 0:
		_center = _rest_center
		_knob = _center
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index < 0:
			_touch_index = event.index
			_center = event.position.clamp(Vector2(radius, radius), size - Vector2(radius, radius))
			_update(event.position)
			accept_event()
		elif not event.pressed and event.index == _touch_index:
			release()
			accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update(event.position)
		accept_event()


func release() -> void:
	_touch_index = -1
	_center = _rest_center
	_knob = _center
	value = Vector2.ZERO
	sprinting = false
	moved.emit(Vector2.ZERO, false)
	queue_redraw()


func _update(pos: Vector2) -> void:
	var d := pos - _center
	var l := d.length()
	if l > radius:
		d = d / l * radius
		l = radius
	_knob = _center + d
	var v := d / radius
	if v.length() < deadzone:
		v = Vector2.ZERO
	value = v
	sprinting = v.length() >= sprint_threshold
	moved.emit(v, sprinting)
	queue_redraw()


func _draw() -> void:
	var a := 0.85 if _touch_index >= 0 else 0.45
	if _pad_tex:
		draw_texture_rect(_pad_tex, Rect2(_center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, Color(1, 1, 1, a))
	if _nub_tex:
		var nr := radius * 0.48
		var col := Color(1.0, 0.85, 0.55, a + 0.1) if sprinting else Color(1, 1, 1, a + 0.1)
		draw_texture_rect(_nub_tex, Rect2(_knob - Vector2(nr, nr), Vector2(nr, nr) * 2.0), false, col)
