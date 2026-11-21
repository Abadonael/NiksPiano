extends Control

signal note_pressed(midi: int, pointer: int)
signal note_released(pointer: int)
signal scrolled(pixels: float)
signal scroll_finished

const Chords := preload("res://scripts/chords.gd")
const Finish := preload("res://scripts/finish.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const WHITE_COUNT := 52
const BLACK_WIDTH := 0.61
const BLACK_HEIGHT := 0.67
const C4_MARKER_COLOR := Color("#076B73")
const MOUSE_POINTER := -1
const NO_POINTER := -2

enum Gesture { TAP, PLAY, SCROLL, CANCELED }

class Finger:
	var origin: Vector2
	var last_x: float
	var midi: int
	var gesture: Gesture

	func _init(point: Vector2, key: int, state: Gesture) -> void:
		origin = point
		last_x = point.x
		midi = key
		gesture = state

var white_keys: Array[int] = []
# A black key sits across the boundary after this many white keys.
var black_keys: Dictionary[int, int] = {}
var key_width := 1.0
var offset := 0.0
var drag_threshold := 9.0
var locked := true

var _fingers: Dictionary[int, Finger] = {}
var _scroll_pointer := NO_POINTER
var _white: StyleBoxTexture
var _black: StyleBoxTexture
var _white_down: StyleBoxTexture
var _black_down: StyleBoxTexture
var _black_shadow: StyleBoxFlat


func _init() -> void:
	for midi in range(PianoAudio.FREE_LOWEST, PianoAudio.FREE_HIGHEST + 1):
		if midi % Chords.PITCH_CLASSES in Chords.WHITE_PITCHES:
			white_keys.append(midi)
		else:
			black_keys[white_keys.size()] = midi


func _ready() -> void:
	_white = Finish.metal(Color("#fcfcfe"), Color("#d9dde4"), Color("#ffffff"), 7.0)
	_black = Finish.metal(Color("#292a2c"), Color("#070809"), Color("#55575c"), 8.0)
	_white_down = Finish.metal(Color("#cbd0d7"), Color("#a2aab5"), Color("#e5e8ed"), 7.0)
	_black_down = Finish.metal(Color("#535960"), Color("#1b1f24"), Color("#8a9098"), 8.0)
	_black_shadow = Finish.flat(Color("#090a0d75"), Color.TRANSPARENT, 6)
	resized.connect(queue_redraw)


func _draw() -> void:
	var first := maxi(0, floori(offset / key_width))
	var last := mini(WHITE_COUNT, ceili((offset + size.x) / key_width))
	var pressed := _pressed_notes()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0e1013"))
	for index in range(first, last):
		var midi := white_keys[index]
		var rect := white_rect(index)
		draw_style_box(_white_down if midi in pressed else _white, rect)
		var lip_y := rect.end.y - minf(10.0, rect.size.y * 0.035)
		var inset := minf(7.0, rect.size.x * 0.14)
		draw_line(Vector2(rect.position.x + inset, lip_y), Vector2(rect.end.x - inset, lip_y),
			Color("#ffffff86"), 1.5, true)
		if midi == PianoAudio.C4:
			var center := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.91)
			var radius := rect.size.x * 0.19 * 0.5
			draw_circle(center, radius, C4_MARKER_COLOR, true, -1.0, true)
	for boundary in range(first, last + 1):
		if not black_keys.has(boundary):
			continue
		var rect := black_rect(boundary)
		var shadow := Rect2(rect.position + Vector2(1.0, 1.0), rect.size + Vector2(2.0, 3.0))
		draw_style_box(_black_shadow, shadow)
		draw_style_box(_black_down if black_keys[boundary] in pressed else _black, rect)
		var lip_y := rect.end.y - minf(9.0, rect.size.y * 0.05)
		var inset := rect.size.x * 0.18
		draw_line(Vector2(rect.position.x + inset, lip_y), Vector2(rect.end.x - inset, lip_y),
			Color("#ffffff25"), 1.4, true)


func white_rect(index: int) -> Rect2:
	var gap := clampf(key_width * 0.027, 1.4, 3.0)
	return Rect2(index * key_width - offset + gap * 0.5, 0.0, key_width - gap, size.y)


func black_rect(boundary: int) -> Rect2:
	var width := key_width * BLACK_WIDTH
	return Rect2(boundary * key_width - offset - width * 0.5, 0.0, width, size.y * BLACK_HEIGHT)


func key_at(point: Vector2) -> int:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return -1
	var white_position := (point.x + offset) / key_width
	var boundary := roundi(white_position)
	if black_keys.has(boundary) and black_rect(boundary).has_point(point):
		return black_keys[boundary]
	return white_keys[clampi(floori(white_position), 0, WHITE_COUNT - 1)]


func _pressed_notes() -> Array[int]:
	var result: Array[int] = []
	for finger in _fingers.values():
		if finger.gesture == Gesture.TAP or finger.gesture == Gesture.PLAY:
			result.append(finger.midi)
	return result


func _gui_input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed, event.is_canceled())
	elif event is InputEventScreenDrag:
		_move(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch(MOUSE_POINTER, event.position, event.pressed, event.is_canceled())
	elif event is InputEventMouseMotion:
		_move(MOUSE_POINTER, event.position)
	else:
		return
	accept_event()


func _touch(pointer: int, point: Vector2, pressed: bool, canceled: bool) -> void:
	if not pressed or canceled:
		_end(pointer, point, canceled)
		return
	var midi := key_at(point)
	if midi < 0:
		return
	_fingers[pointer] = Finger.new(point, midi, Gesture.PLAY if locked else Gesture.TAP)
	if locked:
		note_pressed.emit(midi, pointer)
	queue_redraw()


func _move(pointer: int, point: Vector2) -> void:
	if locked or not _fingers.has(pointer):
		return
	var finger := _fingers[pointer]
	var displacement := point - finger.origin
	if finger.gesture == Gesture.TAP or finger.gesture == Gesture.CANCELED:
		if absf(displacement.x) >= drag_threshold and absf(displacement.x) > absf(displacement.y):
			finger.gesture = Gesture.CANCELED
			if _scroll_pointer == NO_POINTER:
				_scroll_pointer = pointer
				finger.gesture = Gesture.SCROLL
				finger.last_x = finger.origin.x + signf(displacement.x) * drag_threshold
			queue_redraw()
		elif finger.gesture == Gesture.TAP and absf(displacement.y) >= drag_threshold:
			finger.gesture = Gesture.CANCELED
			queue_redraw()
	if finger.gesture == Gesture.SCROLL:
		scrolled.emit(finger.last_x - point.x)
		finger.last_x = point.x


func _end(pointer: int, point: Vector2, canceled: bool) -> void:
	if not _fingers.has(pointer):
		return
	if not canceled:
		_move(pointer, point)
	var finger := _fingers[pointer]
	_fingers.erase(pointer)
	match finger.gesture:
		Gesture.TAP:
			if not canceled:
				# Commit only after ruling out a swipe, then let the attack ring.
				note_pressed.emit(finger.midi, pointer)
				note_released.emit(pointer)
		Gesture.PLAY:
			note_released.emit(pointer)
		Gesture.SCROLL:
			_scroll_pointer = NO_POINTER
			scroll_finished.emit()
	queue_redraw()


func cancel_input() -> void:
	for pointer in _fingers.keys():
		_end(pointer, Vector2.ZERO, true)
