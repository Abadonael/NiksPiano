extends Control

signal sector_selected(index: int, minor: bool)

const Theory := preload("res://scripts/key_theory.gd")
const Finish := preload("res://scripts/finish.gd")
const COUNT := 12
const SLICE := TAU / COUNT
const INNER_EDGE := 0.37
const RING_DIVIDE := 0.68

var _selected := 0
var _prefer_flats := false
var _minor := false
var _font: Font


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_font = Finish.weighted_font(0.75)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)


func show_selection(index: int, prefer_flats: bool, minor: bool) -> void:
	_selected = index
	_prefer_flats = prefer_flats
	_minor = minor
	accessibility_name = "Квинтовый круг. " + Theory.at_sector(index, prefer_flats, minor).name()
	accessibility_description = "Выберите сектор касанием или стрелками. Вверх — мажор, вниз — минор."
	queue_redraw()


func sector_at(point: Vector2) -> Vector2i:
	var delta := point - size * 0.5
	var distance := delta.length() / _radius()
	if distance < INNER_EDGE or distance > 1.0:
		return Vector2i(-1, -1)
	var index := posmod(floori((delta.angle() + PI * 0.5) / SLICE + 0.5), COUNT)
	return Vector2i(index, int(distance < RING_DIVIDE))


func _gui_input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION or not event.is_pressed():
		return
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		var hit := sector_at(event.position)
		if hit.x >= 0:
			sector_selected.emit(hit.x, bool(hit.y))
		accept_event()
	elif event.is_action("ui_right") or event.is_action("ui_left"):
		var direction := 1 if event.is_action("ui_right") else -1
		sector_selected.emit(posmod(_selected + direction, COUNT), _minor)
		accept_event()
	elif event.is_action("ui_up") or event.is_action("ui_down"):
		sector_selected.emit(_selected, event.is_action("ui_down"))
		accept_event()


func _draw() -> void:
	var radius := _radius()
	if radius < 12.0:
		return
	var center := size * 0.5
	draw_circle(center + Vector2(0, 4), radius + 1, Color("#13171b"), true, -1.0, true)
	draw_circle(center, radius, Color("#181c21"), true, -1.0, true)
	for index in range(COUNT):
		var angle := index * SLICE - PI * 0.5
		var active := index == _selected
		var major_fill := Color("#282e34")
		var minor_fill := Color("#22272d")
		if active:
			major_fill = Color("#10494f") if _minor else Finish.TEAL
			minor_fill = Finish.TEAL if _minor else Color("#10494f")
		_draw_slice(angle, RING_DIVIDE, 1.0, major_fill)
		_draw_slice(angle, INNER_EDGE, RING_DIVIDE, minor_fill)
		var key := Theory.major(index, _prefer_flats)
		var major_ink := (Color("#c3eeee") if _minor else Color.WHITE) if active else Finish.WHITE
		var minor_ink := (Color.WHITE if _minor else Color("#c3eeee")) if active else Finish.MUTED
		var major := key.note_name(0)
		var minor := key.relative_minor().note_name(0) + "m"
		if index == Theory.ENHARMONIC_SECTOR and not active:
			major = "F♯/G♭"
		_center_text(major, center + Vector2.from_angle(angle) * radius * 0.84, radius * 0.115, major_ink)
		if index == Theory.ENHARMONIC_SECTOR and not active:
			_center_text("D♯m", center + Vector2(0, radius * 0.47), radius * 0.075, minor_ink)
			_center_text("E♭m", center + Vector2(0, radius * 0.58), radius * 0.075, minor_ink)
		else:
			_center_text(minor, center + Vector2.from_angle(angle) * radius * 0.52, radius * 0.083, minor_ink)
	var accent := Color("#84c4c9") if has_focus() else Color("#454d55")
	draw_arc(center, radius, 0.0, TAU, 128, accent, 2.0, true)
	draw_arc(center, radius * INNER_EDGE, 0.0, TAU, 96, Color("#3b444a"), 1.0, true)
	var current := Theory.at_sector(_selected, _prefer_flats, _minor)
	_center_text(current.note_name(0), center - Vector2(0, radius * 0.052), radius * 0.21, Finish.WHITE)
	_center_text("минор" if _minor else "мажор", center + Vector2(0, radius * 0.125), radius * 0.075, Finish.MUTED)


func _radius() -> float:
	return maxf(1.0, minf(size.x, size.y) * 0.5 - 4.0)


func _draw_slice(angle: float, inner: float, outer: float, fill: Color) -> void:
	var points := PackedVector2Array()
	var center := size * 0.5
	var radius := _radius()
	var half := SLICE * 0.5 - 0.007
	for index in range(17):
		points.append(center + Vector2.from_angle(lerpf(angle - half, angle + half, index / 16.0)) * (outer * radius - 1.0))
	for index in range(16, -1, -1):
		points.append(center + Vector2.from_angle(lerpf(angle - half, angle + half, index / 16.0)) * (inner * radius + 1.0))
	draw_colored_polygon(points, fill)


func _center_text(caption: String, center: Vector2, points: float, ink: Color) -> void:
	var font_size := roundi(points)
	var width := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var y := (_font.get_ascent(font_size) - _font.get_descent(font_size)) * 0.5
	draw_string(_font, center + Vector2(-width * 0.5, y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
