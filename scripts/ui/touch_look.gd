class_name TouchLook
extends Control
## Zona derecha de la pantalla: arrastrar para girar la cámara, pellizcar
## con dos dedos para acercar/alejar.

signal look(delta: Vector2)
signal zoom(amount: float)

var _touches: Dictionary = {}
var _pinch_dist := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_dist = _pinch_distance()
		accept_event()
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		var prev: Vector2 = _touches[event.index]
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var d := _pinch_distance()
			if _pinch_dist > 0.0:
				zoom.emit((_pinch_dist - d) * 0.02)
			_pinch_dist = d
		else:
			look.emit(event.position - prev)
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom.emit(-0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom.emit(0.6)


func _pinch_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1])


func clear() -> void:
	_touches.clear()
