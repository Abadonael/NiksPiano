extends Control

signal menu_requested

const Finish := preload("res://scripts/finish.gd")
const FreeKeyboard := preload("res://scripts/free_keyboard.gd")
const HeaderButton := preload("res://scripts/header_button.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const Settings := preload("res://scripts/settings.gd")
const ZOOM_STEP := 1.12
const MIN_BLACK_DP := 24.0

var preferences: Settings
var audio: PianoAudio

@onready var _clip: Control = $KeyboardClip
@onready var _keyboard: FreeKeyboard = $KeyboardClip/Keyboard
@onready var _overview: Control = $Overview
var _menu: HeaderButton
var _lock: HeaderButton
var _sound: HeaderButton
var _minus: HeaderButton
var _plus: HeaderButton
var _default_width := 1.0
var _min_width := 1.0
var _max_width := 1.0
var _overview_height := 1.0
var _map_pointer := FreeKeyboard.NO_POINTER
var _map_grab := 0.0
var _map_origin := 0.0
var _map_dragging := false
var _active := false


func _ready() -> void:
	_menu = _button(HeaderButton.Icon.MENU)
	_lock = _button(HeaderButton.Icon.LOCK)
	_sound = _button(HeaderButton.Icon.SOUND)
	_minus = _button(HeaderButton.Icon.MINUS)
	_plus = _button(HeaderButton.Icon.PLUS)
	_menu.pressed.connect(func() -> void: menu_requested.emit())
	_lock.toggled.connect(_set_locked)
	_minus.pressed.connect(_zoom.bind(1.0 / ZOOM_STEP))
	_plus.pressed.connect(_zoom.bind(ZOOM_STEP))
	_keyboard.note_pressed.connect(audio.play_free_note)
	_keyboard.note_released.connect(audio.release_free_note)
	_keyboard.scrolled.connect(_scroll)
	_keyboard.scroll_finished.connect(preferences.save)
	_overview.draw.connect(_draw_overview)
	_overview.gui_input.connect(_map_input)
	resized.connect(_layout)
	get_window().size_changed.connect(_layout)
	get_window().focus_exited.connect(_cancel_gestures)


func start() -> void:
	audio.prepare_free_piano()
	_active = true
	_keyboard.locked = preferences.free_locked
	_layout()


func stop() -> void:
	_active = false
	_cancel_gestures()
	audio.fade_free_notes()
	preferences.save()


func _notification(what: int) -> void:
	if not _active:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_cancel_gestures()
		preferences.save()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_layout()


func _button(icon: HeaderButton.Icon) -> HeaderButton:
	var button := HeaderButton.new()
	button.symbol = icon
	button.translucent = true
	button.audio = audio
	add_child(button)
	return button


func _layout() -> void:
	if not _active or size.x < 2.0 or size.y < 2.0:
		return
	_cancel_gestures()
	var bounds := Finish.safe_bounds(self)
	var pixels_per_dp := 1.0
	if OS.get_name() == "Android":
		pixels_per_dp = maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	var canvas_scale := get_viewport().get_final_transform().x.length()
	var dp := minf(pixels_per_dp / maxf(0.01, canvas_scale), bounds.size.y / 160.0)
	var target := 48.0 * dp
	var padding := 4.0 * dp
	var bottom := bounds.end.y - target
	_clip.position = bounds.position + Vector2(padding, target)
	_clip.size = Vector2(bounds.size.x - 2.0 * padding, maxf(1.0, bottom - _clip.position.y))
	_keyboard.size = _clip.size
	_keyboard.drag_threshold = 9.0 * dp

	_min_width = maxf(_clip.size.x / FreeKeyboard.WHITE_COUNT, MIN_BLACK_DP * dp / FreeKeyboard.BLACK_WIDTH)
	var large_width := clampf(_clip.size.y * 0.31, 102.0 * dp, 145.0 * dp)
	_max_width = maxf(_min_width, minf(large_width, _clip.size.x / 3.5))
	_default_width = clampf(_clip.size.y * 0.143, 52.0 * dp, 66.0 * dp)
	_default_width = clampf(_default_width, _min_width, _max_width)
	_keyboard.key_width = clampf(_default_width * preferences.free_zoom, _min_width, _max_width)

	var left := bounds.position.x + padding
	var right := bounds.end.x - padding
	var button_target := minf(target, (right - left) / 5.0)
	var step := Vector2(button_target, 0.0)
	for button in [_menu, _lock, _sound, _minus, _plus]:
		button.set_metrics(button_target, button_target * (32.0 / 48.0))
	_menu.position = Vector2(left, bounds.position.y)
	_lock.position = _menu.position + step
	_minus.position = _lock.position + step
	_plus.position = _minus.position + step
	_sound.position = Vector2(right - button_target, bounds.position.y)
	_overview_height = 19.0 * dp
	_overview.position = Vector2(left, bottom)
	_overview.size = Vector2(right - left, target)
	_lock.set_locked(_keyboard.locked)
	_minus.visible = not _keyboard.locked
	_plus.visible = not _keyboard.locked
	_overview.mouse_filter = MOUSE_FILTER_IGNORE if _keyboard.locked else MOUSE_FILTER_STOP

	var middle_c := _keyboard.white_keys.find(PianoAudio.C4) + 0.5
	_set_center(middle_c if preferences.free_center < 0.0 else preferences.free_center)


func _cancel_gestures() -> void:
	_keyboard.cancel_input()
	if _map_pointer != FreeKeyboard.NO_POINTER:
		_map_pointer = FreeKeyboard.NO_POINTER
		preferences.save()


func _set_locked(value: bool) -> void:
	_cancel_gestures()
	_keyboard.locked = value
	preferences.free_locked = value
	_layout()
	preferences.save()


func _visible_keys() -> float:
	return minf(FreeKeyboard.WHITE_COUNT, _keyboard.size.x / _keyboard.key_width)


func _center() -> float:
	return _keyboard.offset / _keyboard.key_width + _visible_keys() * 0.5


func _set_center(center: float) -> void:
	var left := clampf(center - _visible_keys() * 0.5, 0.0, FreeKeyboard.WHITE_COUNT - _visible_keys())
	_keyboard.offset = left * _keyboard.key_width
	_minus.disabled = is_equal_approx(_keyboard.key_width, _min_width)
	_plus.disabled = is_equal_approx(_keyboard.key_width, _max_width)
	_keyboard.queue_redraw()
	_overview.queue_redraw()


func _scroll(pixels: float) -> void:
	if _keyboard.locked or is_zero_approx(pixels):
		return
	_set_center(_center() + pixels / _keyboard.key_width)
	preferences.free_center = _center()


func _zoom(factor: float) -> void:
	if _keyboard.locked:
		return
	var center := _center()
	_keyboard.key_width = clampf(_keyboard.key_width * factor, _min_width, _max_width)
	preferences.free_zoom = _keyboard.key_width / _default_width
	_set_center(center)
	preferences.free_center = _center()
	preferences.save()


func _map_face() -> Rect2:
	return Rect2(0.0, (_overview.size.y - _overview_height) * 0.5, _overview.size.x, _overview_height)


func _map_viewport() -> Rect2:
	var face := _map_face()
	var unit := face.size.x / FreeKeyboard.WHITE_COUNT
	return Rect2(_keyboard.offset / _keyboard.key_width * unit, face.position.y,
		_visible_keys() * unit, face.size.y)


func _draw_overview() -> void:
	if not _active:
		return
	var face := _map_face()
	var width := face.size.x / FreeKeyboard.WHITE_COUNT
	var frame := _map_viewport()
	var viewport_tint := Color("#cdd5e053")
	_overview.draw_rect(frame, viewport_tint)
	for index in range(FreeKeyboard.WHITE_COUNT):
		var rect := Rect2(index * width + 0.5, face.position.y, maxf(0.1, width - 1.0), face.size.y)
		var middle_c := _keyboard.white_keys[index] == PianoAudio.C4
		_overview.draw_rect(rect, FreeKeyboard.C4_MARKER_COLOR if middle_c else Color("#686d74"))
		# Keep the key's reference color visible inside the viewport frame.
		var visible_rect := rect.intersection(frame)
		if not middle_c and visible_rect.has_area():
			_overview.draw_rect(visible_rect, viewport_tint)
	var black_width := width * FreeKeyboard.BLACK_WIDTH
	for boundary in _keyboard.black_keys:
		var rect := Rect2(boundary * width - black_width * 0.5, face.position.y, black_width,
			face.size.y * FreeKeyboard.BLACK_HEIGHT)
		_overview.draw_rect(rect, Color("#191c21"))
		var visible_rect := rect.intersection(frame)
		if visible_rect.has_area():
			_overview.draw_rect(visible_rect, viewport_tint)
	_overview.draw_rect(frame.grow(-0.6), Color("#e2e7eec2"), false, 1.2)


func _map_input(event: InputEvent) -> void:
	if _keyboard.locked:
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		_overview.accept_event()
		return
	if event is InputEventScreenTouch:
		_map_touch(event.index, event.position.x, event.pressed, event.is_canceled())
	elif event is InputEventScreenDrag:
		_map_move(event.index, event.position.x)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_map_touch(FreeKeyboard.MOUSE_POINTER, event.position.x, event.pressed, event.is_canceled())
	elif event is InputEventMouseMotion:
		_map_move(FreeKeyboard.MOUSE_POINTER, event.position.x)
	else:
		return
	_overview.accept_event()


func _map_touch(pointer: int, x: float, pressed: bool, canceled: bool) -> void:
	if pressed and not canceled and _map_pointer == FreeKeyboard.NO_POINTER:
		_map_pointer = pointer
		_map_origin = x
		_map_dragging = false
		var frame := _map_viewport()
		_map_grab = x - frame.get_center().x if x >= frame.position.x and x <= frame.end.x else 0.0
		if is_zero_approx(_map_grab):
			_map_move(pointer, x)
	elif pointer == _map_pointer:
		if not canceled:
			_map_move(pointer, x)
			if not _map_dragging:
				_map_grab = 0.0
				_map_move(pointer, x)
		_map_pointer = FreeKeyboard.NO_POINTER
		preferences.save()


func _map_move(pointer: int, x: float) -> void:
	if pointer != _map_pointer:
		return
	_map_dragging = _map_dragging or absf(x - _map_origin) >= _keyboard.drag_threshold * 0.5
	if _map_dragging or is_zero_approx(_map_grab):
		_set_center((x - _map_grab) / _overview.size.x * FreeKeyboard.WHITE_COUNT)
		preferences.free_center = _center()
