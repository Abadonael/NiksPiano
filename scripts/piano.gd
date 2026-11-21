extends Control

signal key_pressed(key: int)

const Notes := preload("res://scripts/notes.gd")
const Finish := preload("res://scripts/finish.gd")
const BLACK_BOUNDARIES := [1, 2, 4, 5, 6]
const WHITE_RADIUS := 7.0
const BLACK_RADIUS := 8.0
const GAP := 3.0

var highlighted_key := -1
var correct := false

var _white: StyleBoxTexture
var _black: StyleBoxTexture
var _green: StyleBoxTexture
var _red: StyleBoxTexture
var _shadow: StyleBoxFlat


func _ready() -> void:
	focus_mode = FOCUS_NONE
	_white = Finish.metal(Color("#fcfcfe"), Color("#d9dde4"), Color("#ffffff"), WHITE_RADIUS)
	_black = Finish.metal(Color("#292a2c"), Color("#070809"), Color("#55575c"), BLACK_RADIUS)
	_green = Finish.metal(Finish.SUCCESS_GREEN, Finish.SUCCESS_GREEN, Color("#b9ffd0"), WHITE_RADIUS)
	_red = Finish.metal(Color("#ff9d9d"), Color("#d24c54"), Color("#ffd0d0"), WHITE_RADIUS)
	_shadow = Finish.flat(Color("#060709"), Color.TRANSPARENT, 8)
	resized.connect(queue_redraw)


func highlight(pitch_class: int, is_correct := false) -> void:
	highlighted_key = pitch_class
	correct = is_correct
	queue_redraw()


func _draw() -> void:
	if _white == null:
		return
	draw_style_box(_shadow, Rect2(Vector2(-2.0, 2.0), size + Vector2(4.0, 5.0)))
	for pitch_class in range(Notes.KEY_COUNT):
		var rect := white_rect(pitch_class)
		var style := _white
		if pitch_class == highlighted_key:
			style = _green if correct else _red
		_draw_key(rect, style, 12.0, 0.58)

	for boundary in BLACK_BOUNDARIES:
		_draw_key(black_rect(boundary), _black, 11.0, 0.14)


func _draw_key(rect: Rect2, style: StyleBox, lip_inset: float, lip_opacity: float) -> void:
	draw_style_box(style, rect)
	var lip := rect.end.y - lip_inset
	draw_line(Vector2(rect.position.x + 6.0, lip), Vector2(rect.end.x - 6.0, lip),
		Color(1.0, 1.0, 1.0, lip_opacity), 2.0, true)


func white_rect(pitch_class: int) -> Rect2:
	var width := size.x / Notes.KEY_COUNT
	return Rect2(pitch_class * width + GAP * 0.5, 0.0, width - GAP, size.y)


func black_rect(boundary: int) -> Rect2:
	var white_width := size.x / Notes.KEY_COUNT
	var black_width := white_width * 0.61
	return Rect2(boundary * white_width - black_width * 0.5, 0.0, black_width, size.y * 0.67)


func key_at(point: Vector2) -> int:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return -1
	for boundary in BLACK_BOUNDARIES:
		if _rounded_contains(black_rect(boundary), BLACK_RADIUS, point):
			return -1
	var pitch_class := floori(point.x / (size.x / Notes.KEY_COUNT))
	if _rounded_contains(white_rect(pitch_class), WHITE_RADIUS, point):
		return pitch_class
	return -1


func _gui_input(event: InputEvent) -> void:
	# Keyboards handle each real finger. Menus still use touch-to-mouse emulation.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch or (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			var key := key_at(event.position)
			if key >= 0:
				key_pressed.emit(key)
		accept_event()


static func _rounded_contains(rect: Rect2, radius: float, point: Vector2) -> bool:
	if not rect.has_point(point):
		return false
	var corner := (point - rect.get_center()).abs() - (rect.size * 0.5 - Vector2.ONE * radius)
	return corner.max(Vector2.ZERO).length_squared() <= radius * radius
