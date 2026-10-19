class_name TouchButton
extends TextureButton
## Botón con soporte multitáctil real: responde a cualquier dedo (no solo al
## primero), para poder atacar o saltar mientras otro dedo usa el joystick.
## Con ratón funciona como un TextureButton normal.

var _touch_index := -1


func _gui_input(event: InputEvent) -> void:
	# Eventos de ratón emulados a partir de toques: los gestionamos como toques.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if event is InputEventScreenTouch:
		# Toques emulados desde el ratón (escritorio): deja actuar al ratón real.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if disabled:
			return
		if event.pressed and _touch_index < 0:
			_touch_index = event.index
			button_down.emit()
			if action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS:
				pressed.emit()
			accept_event()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			button_up.emit()
			if action_mode == BaseButton.ACTION_MODE_BUTTON_RELEASE:
				pressed.emit()
			accept_event()
