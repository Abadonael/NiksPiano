extends "res://scripts/chord_piano.gd"

const BLACK_FACE_RATIO := 0.76
const BLACK_TOUCH_RATIO := 0.84
const MAX_BLACK_TOUCH_RATIO := 0.90
const MOUSE_POINTER := -1

var _black_touch_ratio := BLACK_TOUCH_RATIO
var _held: Dictionary[int, int] = {}


func black_rect(boundary: int) -> Rect2:
	var width := size.x / WHITE_COUNT
	return Rect2((boundary - BLACK_FACE_RATIO * 0.5) * width, 0.0,
		BLACK_FACE_RATIO * width, size.y * 0.67)


func black_touch_rect(boundary: int) -> Rect2:
	var rect := black_rect(boundary)
	var extra := (_black_touch_ratio - BLACK_FACE_RATIO) * size.x / WHITE_COUNT
	return rect.grow_individual(extra * 0.5, 0.0, extra * 0.5, 0.0)


func fit_black_touch_width(minimum: float) -> void:
	# Keep some room around the centers of neighboring white keys.
	_black_touch_ratio = clampf(minimum * WHITE_COUNT / maxf(1.0, size.x),
		BLACK_TOUCH_RATIO, MAX_BLACK_TOUCH_RATIO)


func _black_hit(boundary: int, point: Vector2) -> bool:
	return black_touch_rect(boundary).has_point(point)


func show_feedback(key: int, accepted: bool) -> void:
	if accepted:
		_red_until.erase(key)
		flash_correct(key)
	else:
		_green_until.erase(key)
		mark_wrong(key)


func held_pitches(first_midi: int) -> Array[int]:
	var pitches: Array[int] = []
	for key in _held.values():
		if key >= 0:
			pitches.append(first_midi + key)
	return pitches


func _gui_input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var pointer := MOUSE_POINTER
	if event is InputEventScreenTouch:
		pointer = event.index
	elif not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.is_canceled() or not event.is_pressed():
		_held.erase(pointer)
	elif not _held.has(pointer):
		var key := key_at(event.position)
		_held[pointer] = key
		if key >= 0:
			key_pressed.emit(key)
	accept_event()


func _notification(what: int) -> void:
	if (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()) or (
			what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT):
		_held.clear()
