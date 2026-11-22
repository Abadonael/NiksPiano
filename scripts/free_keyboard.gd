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
const ATTACK_SPACING_USEC := 12000
const ATTACK_WINDOW_USEC := 48000
const CROSSING_EPSILON := 0.000001

enum Gesture { TAP, PLAY, SCROLL, CANCELED }

class Finger:
	var origin: Vector2
	var previous: Vector2
	var midi: int
	var gesture: Gesture
	var pending: Array[int] = []
	var next_attack_usec := 0
	var attack_deadline_usec := 0

	func _init(point: Vector2, key: int, state: Gesture) -> void:
		origin = point
		previous = point
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
	set_process(false)
	_white = Finish.metal(Color("#fcfcfe"), Color("#d9dde4"), Color("#ffffff"), 7.0)
	_black = Finish.metal(Color("#292a2c"), Color("#070809"), Color("#55575c"), 8.0)
	_white_down = Finish.metal(Color("#cbd0d7"), Color("#a2aab5"), Color("#e5e8ed"), 7.0)
	_black_down = Finish.metal(Color("#535960"), Color("#1b1f24"), Color("#8a9098"), 8.0)
	_black_shadow = Finish.flat(Color("#090a0d75"), Color.TRANSPARENT, 6)
	resized.connect(queue_redraw)


func _draw() -> void:
	var first := maxi(0, floori(offset / key_width))
	var last := mini(white_keys.size(), ceili((offset + size.x) / key_width))
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
	return white_keys[clampi(floori(white_position), 0, white_keys.size() - 1)]


func _pressed_notes() -> Array[int]:
	var result: Array[int] = []
	for finger in _fingers.values():
		if finger.midi >= 0 and (finger.gesture == Gesture.TAP or finger.gesture == Gesture.PLAY):
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
	var finger := Finger.new(point, midi, Gesture.PLAY if locked else Gesture.TAP)
	_fingers[pointer] = finger
	if locked:
		finger.next_attack_usec = Time.get_ticks_usec() + ATTACK_SPACING_USEC
		note_pressed.emit(midi, pointer)
	queue_redraw()


func _move(pointer: int, point: Vector2) -> void:
	if not _fingers.has(pointer):
		return
	var finger := _fingers[pointer]
	if locked:
		if finger.gesture == Gesture.PLAY:
			_play_drag(pointer, finger, point)
		return
	var displacement := point - finger.origin
	if finger.gesture == Gesture.TAP or finger.gesture == Gesture.CANCELED:
		if absf(displacement.x) >= drag_threshold and absf(displacement.x) > absf(displacement.y):
			finger.gesture = Gesture.CANCELED
			if _scroll_pointer == NO_POINTER:
				_scroll_pointer = pointer
				finger.gesture = Gesture.SCROLL
				finger.previous.x = finger.origin.x + signf(displacement.x) * drag_threshold
			queue_redraw()
		elif finger.gesture == Gesture.TAP and absf(displacement.y) >= drag_threshold:
			finger.gesture = Gesture.CANCELED
			queue_redraw()
	if finger.gesture == Gesture.SCROLL:
		scrolled.emit(finger.previous.x - point.x)
		finger.previous = point


func _play_drag(pointer: int, finger: Finger, point: Vector2) -> void:
	var start := finger.previous
	if start == point:
		return
	finger.previous = point
	var had_pending := not finger.pending.is_empty()
	var pending_count := finger.pending.size()
	var delta := point - start
	var crossings := _key_crossings(start, delta)
	var previous_t := 0.0
	# Hit testing is constant inside each interval between geometry edges.
	for t in crossings:
		if t - previous_t > CROSSING_EPSILON:
			_enter_key(finger, key_at(start + delta * ((previous_t + t) * 0.5)))
		previous_t = t
	_enter_key(finger, key_at(point))
	if finger.pending.size() == pending_count:
		return
	var now := Time.get_ticks_usec()
	if not had_pending:
		finger.attack_deadline_usec = now + ATTACK_WINDOW_USEC
	_play_pending(pointer, finger, now)
	if not finger.pending.is_empty():
		set_process(true)
	queue_redraw()


func _key_crossings(start: Vector2, delta: Vector2) -> Array[float]:
	var crossings: Array[float] = [1.0]
	if delta.x != 0.0:
		_add_crossing(crossings, start.x, delta.x, 0.0)
		_add_crossing(crossings, start.x, delta.x, size.x)
		var left := (start.x + minf(0.0, delta.x) + offset) / key_width
		var right := (start.x + maxf(0.0, delta.x) + offset) / key_width
		var first := maxi(1, ceili(left - BLACK_WIDTH * 0.5))
		var last := mini(WHITE_COUNT - 1, floori(right + BLACK_WIDTH * 0.5))
		for boundary in range(first, last + 1):
			_add_crossing(crossings, start.x, delta.x, boundary * key_width - offset)
			if black_keys.has(boundary):
				var rect := black_rect(boundary)
				_add_crossing(crossings, start.x, delta.x, rect.position.x)
				_add_crossing(crossings, start.x, delta.x, rect.end.x)
	if delta.y != 0.0:
		_add_crossing(crossings, start.y, delta.y, 0.0)
		_add_crossing(crossings, start.y, delta.y, size.y * BLACK_HEIGHT)
		_add_crossing(crossings, start.y, delta.y, size.y)
	crossings.sort()
	return crossings


func _add_crossing(crossings: Array[float], start: float, delta: float, edge: float) -> void:
	var t := (edge - start) / delta
	if t > 0.0 and t < 1.0:
		crossings.append(t)


func _enter_key(finger: Finger, midi: int) -> void:
	if midi != finger.midi:
		finger.midi = midi
		finger.pending.append(midi)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var waiting := false
	for pointer in _fingers.keys():
		var finger := _fingers[pointer]
		_play_pending(pointer, finger, now)
		waiting = waiting or not finger.pending.is_empty()
	set_process(waiting)


func _play_pending(pointer: int, finger: Finger, now: int) -> void:
	if finger.pending.is_empty() or (now < finger.next_attack_usec and now < finger.attack_deadline_usec):
		return
	# Spread sparse samples across mixer blocks where possible. Dense crossings
	# share a block when needed to stay within the original batch's time budget.
	var frame_usec := maxf(ATTACK_SPACING_USEC, get_process_delta_time() * 1000000.0)
	var slots := 1 + floori(maxi(0, finger.attack_deadline_usec - now) / frame_usec)
	var count := ceili(float(finger.pending.size()) / slots)
	var attacks := finger.pending.slice(0, count)
	finger.pending = finger.pending.slice(count)
	finger.next_attack_usec = now + ATTACK_SPACING_USEC
	for midi in attacks:
		if midi >= 0:
			note_pressed.emit(midi, pointer)
		else:
			note_released.emit(pointer)


func _end(pointer: int, point: Vector2, canceled: bool) -> void:
	if not _fingers.has(pointer):
		return
	if not canceled and not locked:
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
