class_name TouchButton
extends TextureButton
## Botón con soporte multitáctil real: responde a cualquier dedo (no solo al
## primero), para poder atacar o saltar mientras otro dedo usa el joystick.
## Con ratón funciona como un TextureButton normal. Al pulsarlo se encoge un
## poco y rebota al soltarlo.

var _touch_index := -1
var _press_tw: Tween


func _gui_input(event: InputEvent) -> void:
	# Eventos de ratón emulados a partir de toques: los gestionamos como toques.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not disabled:
		_press_feedback(event.pressed)
	if event is InputEventScreenTouch:
		# Toques emulados desde el ratón (escritorio): deja actuar al ratón real.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if disabled:
			return
		if event.pressed and _touch_index < 0:
			_touch_index = event.index
			_press_feedback(true)
			button_down.emit()
			if action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS:
				pressed.emit()
			accept_event()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_press_feedback(false)
			button_up.emit()
			if action_mode == BaseButton.ACTION_MODE_BUTTON_RELEASE:
				pressed.emit()
			accept_event()


func _press_feedback(down: bool) -> void:
	if not is_inside_tree():
		return
	if _press_tw:
		_press_tw.kill()
	pivot_offset = size * 0.5
	_press_tw = create_tween()
	if down:
		_press_tw.tween_property(self, "scale", Vector2.ONE * 0.86, 0.06)
	else:
		_press_tw.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
