extends Button

const Finish := preload("res://scripts/finish.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const FLAG := preload("res://assets/icons/flag-ru.svg")
const TARGET := 96.0
const FACE := 56.0

enum Icon { INFO, LANGUAGE, SOUND, CLOSE, MENU, LOCK, MINUS, PLUS }

var symbol := Icon.SOUND
var audio: PianoAudio
var translucent := false
var _face_size := FACE
var _normal: StyleBoxFlat
var _highlight: StyleBoxFlat
var _focus: StyleBoxFlat


func _ready() -> void:
	name = ["Information", "Language", "Sound", "Close", "BackToMenu", "Lock", "ZoomOut", "ZoomIn"][symbol]
	accessibility_name = ["Об игре", "Русский язык", "Звук", "Закрыть", "Меню",
		"Заблокировать клавиатуру", "Уменьшить клавиши", "Увеличить клавиши"][symbol]
	if not translucent:
		tooltip_text = accessibility_name
	set_metrics(TARGET, FACE)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	_normal = Finish.flat(Color("#24282d"), Color("#51565d"), 13, 1)
	_highlight = Finish.flat(Color("#343940"), Color("#717882"), 13, 1)
	_focus = Finish.flat(Color.TRANSPARENT, Finish.WHITE, 13, 2)
	if translucent:
		_normal = Finish.flat(Color("#24282dc4"), Color("#595f679c"), 9, 1)
		_highlight = Finish.flat(Color("#373d45eb"), Color("#878e99ba"), 9, 1)
		_focus = Finish.flat(Color.TRANSPARENT, Finish.WHITE, 9, 2)
	match symbol:
		Icon.LANGUAGE:
			mouse_filter = MOUSE_FILTER_IGNORE
			focus_mode = FOCUS_NONE
			disabled = true
		Icon.SOUND:
			toggle_mode = true
			toggled.connect(audio.set_enabled)
			audio.enabled_changed.connect(_sync_sound)
			_sync_sound(audio.enabled)
		Icon.LOCK:
			toggle_mode = true


func set_metrics(target: float, face: float) -> void:
	_face_size = face
	custom_minimum_size = Vector2.ONE * target
	size = custom_minimum_size
	queue_redraw()


func set_locked(locked: bool) -> void:
	set_pressed_no_signal(locked)
	accessibility_name = "Разблокировать клавиатуру" if locked else "Заблокировать клавиатуру"
	queue_redraw()


func _sync_sound(value: bool) -> void:
	set_pressed_no_signal(value)
	accessibility_name = "Выключить звук" if value else "Включить звук"
	if not translucent:
		tooltip_text = accessibility_name
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var face := Rect2(center - Vector2.ONE * _face_size * 0.5, Vector2.ONE * _face_size)
	var pressed := button_pressed and symbol not in [Icon.SOUND, Icon.LOCK]
	draw_style_box(_highlight if not disabled and (is_hovered() or pressed) else _normal, face)
	if has_focus():
		draw_style_box(_focus, face)
	draw_set_transform(center, 0.0, Vector2.ONE * (_face_size / FACE))
	center = Vector2.ZERO
	match symbol:
		Icon.INFO:
			draw_arc(center, 14.0, 0.0, TAU, 32, Finish.MUTED, 2.0, true)
			draw_circle(center + Vector2(0.0, -5.5), 1.6, Finish.WHITE, true, -1.0, true)
			draw_line(center + Vector2(0.0, -1.0), center + Vector2(0.0, 7.0), Finish.WHITE, 2.5, true)
		Icon.LANGUAGE:
			draw_texture_rect(FLAG, Rect2(center - Vector2(15.0, 10.0), Vector2(30.0, 20.0)), false)
		Icon.SOUND:
			_draw_speaker(center)
		Icon.CLOSE:
			_draw_cross(center, 7.0, Finish.WHITE)
		Icon.MENU:
			for y in [-8.0, 0.0, 8.0]:
				draw_line(Vector2(-12.0, y), Vector2(12.0, y), Finish.WHITE, 2.5, true)
		Icon.LOCK:
			_draw_lock()
		Icon.MINUS, Icon.PLUS:
			var ink := Finish.MUTED.darkened(0.45) if disabled else Finish.WHITE
			draw_line(Vector2(-10.0, 0.0), Vector2(10.0, 0.0), ink, 2.5, true)
			if symbol == Icon.PLUS:
				draw_line(Vector2(0.0, -10.0), Vector2(0.0, 10.0), ink, 2.5, true)


func _draw_lock() -> void:
	var ink := Finish.WHITE if button_pressed else Finish.MUTED
	var shackle := Vector2(0.0, -6.0) if button_pressed else Vector2(-4.0, -11.0)
	draw_arc(shackle, 7.0, PI, TAU, 16, ink, 2.5, true)
	draw_line(shackle + Vector2(7.0, 0.0), Vector2(shackle.x + 7.0, 0.0 if button_pressed else -7.0), ink, 2.5, true)
	draw_line(shackle - Vector2(7.0, 0.0), Vector2(shackle.x - 7.0, 0.0), ink, 2.5, true)
	draw_rect(Rect2(-12.0, 0.0, 24.0, 15.0), ink, false, 2.5, true)
	draw_circle(Vector2(0.0, 7.0), 2.0, ink, true, -1.0, true)


func _draw_speaker(center: Vector2) -> void:
	var color := Finish.WHITE if button_pressed else Finish.MUTED
	var speaker := PackedVector2Array([
		Vector2(-17.0, -5.0), Vector2(-11.0, -5.0), Vector2(-3.0, -12.0),
		Vector2(-3.0, 12.0), Vector2(-11.0, 5.0), Vector2(-17.0, 5.0),
	])
	for index in range(speaker.size()):
		speaker[index] += center
	draw_colored_polygon(speaker, color)
	if button_pressed:
		for radius in [8.0, 14.0]:
			draw_arc(center + Vector2(1.0, 0.0), radius, -0.8, 0.8, 12, color, 2.3, true)
	else:
		_draw_cross(center + Vector2(9.0, 0.0), 4.5, color)


func _draw_cross(center: Vector2, radius: float, color: Color) -> void:
	draw_line(center + Vector2(-radius, -radius), center + Vector2(radius, radius), color, 2.3, true)
	draw_line(center + Vector2(-radius, radius), center + Vector2(radius, -radius), color, 2.3, true)
