extends Control

signal start_requested

const Finish := preload("res://scripts/finish.gd")
const Notes := preload("res://scripts/notes.gd")
const Chords := preload("res://scripts/chords.gd")
const Settings := preload("res://scripts/settings.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const HeaderButton := preload("res://scripts/header_button.gd")
const Credits := preload("res://scripts/credits.gd")
const Exercises := preload("res://scripts/melody_exercises.gd")
const MODE_ORDER: Array[Settings.Mode] = [
	Settings.Mode.FREE_PIANO, Settings.Mode.STAFF, Settings.Mode.NAMES, Settings.Mode.CHORDS, Settings.Mode.MELODIES,
]

var preferences: Settings
var audio: PianoAudio

var _title: Label
var _toolbar: HBoxContainer
var _info: HeaderButton
var _sound: HeaderButton
var _credits: Credits
var _headline: Label
var _mode_heading: Label
var _staff_rows: Array[Control]
var _naming_rows: Array[Control]
var _chord_heading: Label
var _mode_buttons: Array[Button]
var _range_buttons: Array[Button]
var _naming_buttons: Array[Button]
var _chord_buttons: Array[Button]
var _exercise_heading: Label
var _difficulty_heading: Label
var _length_heading: Label
var _clef_heading: Label
var _exercise_buttons: Array[Button]
var _difficulty_buttons: Array[Button]
var _length_buttons: Array[Button]
var _clef_buttons: Array[Button]
var _start: Button
var _dark: StyleBoxTexture
var _selected: StyleBoxTexture
var _focus: StyleBoxFlat
var _radio_hover: StyleBoxTexture
var _radio_selected_hover: StyleBoxTexture
var _radio_focus: StyleBoxFlat
var _radio: StyleBoxFlat
var _check: StyleBoxFlat
var _checked: StyleBoxFlat


func _ready() -> void:
	_dark = Finish.metal(Color("#2e3237"), Color("#15181c"), Color("#595e65"), 19.0, true)
	_selected = Finish.metal(Color("#383d42"), Color("#181b1f"), Color("#ebeff5"), 19.0, true)
	_focus = Finish.flat(Color.TRANSPARENT, Color("#f4f6fa"), 19, 2)
	_radio_hover = Finish.metal(Color("#373c41"), Color("#1d2024"), Color("#595e65"), 19.0, true)
	_radio_selected_hover = Finish.metal(Color("#41464b"), Color("#202327"), Color("#ebeff5"), 19.0, true)
	_radio_focus = Finish.flat(Color.TRANSPARENT, Finish.MUTED, 0)
	_radio_focus.border_width_left = 3
	_radio_focus.expand_margin_left = -10.0
	_radio_focus.expand_margin_top = -20.0
	_radio_focus.expand_margin_bottom = -20.0
	_radio = Finish.flat(Color("#1b1e22"), Color("#a3aab4"), 18, 2)
	_check = Finish.flat(Color("#1b1e22"), Color("#a3aab4"), 9, 2)
	_checked = Finish.flat(Color("#cdd3db"), Color("#e3e8ee"), 9, 2)

	_title = _add_label("NIKS PIANO", 24, Finish.MUTED, 0.75)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toolbar = HBoxContainer.new()
	_toolbar.name = "Toolbar"
	_toolbar.add_theme_constant_override("separation", 0)
	_toolbar.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_toolbar)
	_info = HeaderButton.new()
	_info.symbol = HeaderButton.Icon.INFO
	_info.pressed.connect(_open_credits)
	_toolbar.add_child(_info)
	var language := HeaderButton.new()
	language.symbol = HeaderButton.Icon.LANGUAGE
	_toolbar.add_child(language)
	_sound = HeaderButton.new()
	_sound.audio = audio
	_toolbar.add_child(_sound)
	_headline = _add_label("Тренировка нот", 46, Finish.WHITE, 1.0)
	_mode_heading = _add_label("РЕЖИМ ИГРЫ", 22, Finish.MUTED, 0.75)

	var mode_captions := ["По нотному стану", "По названию", "Аккорды", "Свободная клавиатура", "Мелодии"]
	var mode_group := ButtonGroup.new()
	for mode: Settings.Mode in Settings.Mode.values():
		var row := _choice(mode_captions[mode], 29, 108, mode_group)
		row.pressed.connect(_select_mode.bind(mode))
		_add_radio(row)
		_add_mode_icon(row, mode)
		_mode_buttons.append(row)

	_staff_rows.append(_add_label("ДИАПАЗОНЫ", 22, Finish.MUTED, 0.75))
	for index in range(Notes.RANGES.size()):
		if index == 0:
			_staff_rows.append(_add_label("Скрипичный ключ", 29, Finish.WHITE, 0.8))
		elif index == 2:
			_staff_rows.append(_add_label("Басовый ключ", 29, Finish.WHITE, 0.8))
		var row := _choice(Notes.RANGES[index].title, 27, 93)
		row.pressed.connect(_toggle_range.bind(index))
		_add_checkbox(row)
		_staff_rows.append(row)
		_range_buttons.append(row)

	_naming_rows.append(_add_label("НАЗВАНИЯ НОТ", 22, Finish.MUTED, 0.75))
	var naming_group := ButtonGroup.new()
	for caption in ["До Ре Ми", "C D E"]:
		var row := _choice(caption, 29, 28, naming_group)
		row.pressed.connect(_select_naming.bind(not _naming_buttons.is_empty()))
		_add_radio(row)
		_naming_rows.append(row)
		_naming_buttons.append(row)

	_chord_heading = _add_label("ГРУППЫ АККОРДОВ", 22, Finish.MUTED, 0.75)
	for index in range(Chords.GROUPS.size()):
		var row := _choice("", 27, 93)
		row.accessibility_name = Chords.GROUP_TITLES[index]
		row.accessibility_description = ", ".join(Chords.GROUPS[index])
		row.pressed.connect(_toggle_chord_group.bind(index))
		_add_checkbox(row)
		_add_chord_labels(row, row.accessibility_name, row.accessibility_description)
		_chord_buttons.append(row)

	_exercise_heading = _add_label("УПРАЖНЕНИЕ", 22, Finish.MUTED, 0.75)
	var exercise_group := ButtonGroup.new()
	var exercise_captions := ["Арпеджио", "Музыкальные фразы", "Гармонические интервалы"]
	for kind: Exercises.Kind in Exercises.Kind.values():
		var row := _choice(exercise_captions[kind], 27, 28, exercise_group)
		row.pressed.connect(_select_exercise.bind(kind))
		_add_radio(row)
		_exercise_buttons.append(row)
	_difficulty_heading = _add_label("СЛОЖНОСТЬ", 22, Finish.MUTED, 0.75)
	var difficulty_group := ButtonGroup.new()
	var difficulty_captions := ["Начальный", "Средний", "Продвинутый"]
	for level: Exercises.Difficulty in Exercises.Difficulty.values():
		var row := _choice(difficulty_captions[level], 22, 10, difficulty_group)
		row.pressed.connect(_select_difficulty.bind(level))
		_add_radio(row, true)
		_difficulty_buttons.append(row)
	_length_heading = _add_label("КОЛИЧЕСТВО НОТ", 22, Finish.MUTED, 0.75)
	var length_group := ButtonGroup.new()
	for length: int in Exercises.LENGTHS:
		var row := _choice(str(length), 22, 10, length_group)
		row.pressed.connect(_select_length.bind(length))
		_add_radio(row, true)
		_length_buttons.append(row)
	_clef_heading = _add_label("НОТНЫЙ КЛЮЧ", 22, Finish.MUTED, 0.75)
	var clef_group := ButtonGroup.new()
	var clef_captions := ["Скрипичный", "Басовый"]
	for clef: Notes.Clef in Notes.Clef.values():
		var row := _choice(clef_captions[clef], 22, 10, clef_group)
		row.pressed.connect(_select_clef.bind(clef))
		_add_radio(row, true)
		_clef_buttons.append(row)

	_start = Button.new()
	_start.name = "Start"
	_start.text = "СТАРТ"
	_start.add_theme_font_size_override("font_size", 40)
	_start.add_theme_font_override("font", Finish.weighted_font(1.25))
	for tint in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_start.add_theme_color_override(tint, Color("#11151a"))
	var silver := Finish.metal(Color("#e0e4ea"), Color("#8e96a2"), Color("#f5f7fa"), 24.0, true)
	var bright := Finish.metal(Color("#f8f9fc"), Color("#aab1ba"), Color("#ffffff"), 24.0, true)
	_apply_styles(_start, silver, bright, _focus)
	_start.pressed.connect(func() -> void: start_requested.emit())
	add_child(_start)
	_credits = Credits.new()
	_credits.hide()
	add_child(_credits)
	_credits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_credits.closed.connect(close_credits)
	resized.connect(_layout)
	visibility_changed.connect(_layout)
	_refresh()
	_layout()


func _layout() -> void:
	var margin := size.x * 0.062
	var column_width := size.x - margin * 2.0
	var unit := clampf(size.y / 1570.0, 0.8, 1.05)
	var bounds := Finish.safe_bounds(self)
	var body_y := size.y * 0.181
	var mode_step := 76.0 * unit
	var settings_y := body_y + 438.0 * unit
	var start_height := 89.0 * unit
	var start_y := minf(size.y * 0.937, bounds.end.y) - start_height
	var toolbar_width := HeaderButton.TARGET * _toolbar.get_child_count()
	var title_y := bounds.position.y + size.y * 0.033
	var toolbar_y := maxf(bounds.position.y, title_y + (44.0 - HeaderButton.TARGET) * 0.5)
	var toolbar_x := bounds.end.x - margin - toolbar_width
	_place(_toolbar, toolbar_x, toolbar_y, toolbar_width, HeaderButton.TARGET)
	_place(_title, bounds.position.x + margin, title_y, _title.get_minimum_size().x, 44.0)
	var headline_y := maxf(size.y * 0.092, toolbar_y + HeaderButton.TARGET)
	_place(_headline, margin, headline_y, column_width, 67.0)
	_place(_mode_heading, margin, body_y, column_width, 38.0 * unit)
	for index in range(MODE_ORDER.size()):
		_place(_mode_buttons[MODE_ORDER[index]], margin, body_y + 50.0 * unit + index * mode_step,
			column_width, 67.0 * unit)

	var staff_offsets := [0.0, 64.0, 117.0, 209.0, 325.0, 379.0, 471.0]
	var staff_heights := [39.0, 43.0, 75.0, 75.0, 43.0, 75.0, 75.0]
	for index in range(_staff_rows.size()):
		_place(_staff_rows[index], margin, settings_y + staff_offsets[index] * unit,
			column_width, staff_heights[index] * unit)
	_place(_naming_rows[0], margin, settings_y, column_width, 39.0 * unit)
	_place(_naming_rows[1], margin, settings_y + 58.0 * unit, column_width, 75.0 * unit)
	_place(_naming_rows[2], margin, settings_y + 150.0 * unit, column_width, 75.0 * unit)

	_place(_chord_heading, margin, settings_y, column_width, 39.0 * unit)
	for index in range(_chord_buttons.size()):
		_place(_chord_buttons[index], margin, settings_y + (58.0 + index * 100.0) * unit,
			column_width, 86.0 * unit)

	_layout_melody_options(margin, settings_y, column_width, start_y - settings_y)
	_place(_start, margin, start_y, column_width, start_height)


func _layout_melody_options(left: float, top: float, width: float, available: float) -> void:
	var unit := minf(1.0, available / 520.0)
	var row_height := 56.0 * unit
	var y := top
	_place(_exercise_heading, left, y, width, 34.0 * unit)
	y += 37.0 * unit
	for index in range(_exercise_buttons.size()):
		_place(_exercise_buttons[index], left, y, width, row_height)
		y += 63.0 * unit
	var sections := [[_difficulty_heading, _difficulty_buttons], [_length_heading, _length_buttons],
		[_clef_heading, _clef_buttons]]
	for section: Array in sections:
		if not section[0].visible:
			continue
		y += 5.0 * unit
		_place(section[0], left, y, width, 34.0 * unit)
		y += 37.0 * unit
		var buttons: Array[Button] = section[1]
		var gap := 9.0
		var button_width := (width - gap * (buttons.size() - 1)) / buttons.size()
		for index in range(buttons.size()):
			_place(buttons[index], left + index * (button_width + gap), y, button_width, row_height)
		y += row_height


func _select_mode(mode: Settings.Mode) -> void:
	preferences.mode = mode
	_changed()


func _select_naming(letters: bool) -> void:
	preferences.letter_names = letters
	_changed()


func _select_exercise(kind: Exercises.Kind) -> void:
	preferences.melody_kind = kind
	_changed()


func _select_difficulty(level: Exercises.Difficulty) -> void:
	preferences.melody_difficulty = level
	_changed()


func _select_length(length: int) -> void:
	preferences.melody_length = length
	_changed()


func _select_clef(clef: Notes.Clef) -> void:
	preferences.melody_clef = clef
	_changed()


func _toggle_range(index: int) -> void:
	preferences.toggle_range(index)
	_changed()


func _toggle_chord_group(index: int) -> void:
	preferences.toggle_chord_group(index)
	_changed()


func _open_credits() -> void:
	_credits.open()


func close_credits() -> bool:
	if not _credits.visible:
		return false
	_credits.hide()
	_info.grab_focus()
	return true


func _changed() -> void:
	preferences.save()
	_refresh()


func _refresh() -> void:
	var chord_mode := preferences.mode == Settings.Mode.CHORDS
	var melody_mode := preferences.mode == Settings.Mode.MELODIES
	_headline.text = "Тренировка аккордов" if chord_mode else "Тренировка нот"
	if preferences.mode == Settings.Mode.FREE_PIANO:
		_headline.text = "Свободная клавиатура"
	elif melody_mode:
		_headline.text = "Мелодии"
	for row in _staff_rows:
		row.visible = preferences.mode == Settings.Mode.STAFF
	for row in _naming_rows:
		row.visible = preferences.mode == Settings.Mode.NAMES
	_chord_heading.visible = chord_mode
	for mode: Settings.Mode in Settings.Mode.values():
		_refresh_radio(_mode_buttons[mode], preferences.mode == mode, 108)
	_refresh_radio(_naming_buttons[0], not preferences.letter_names, 28)
	_refresh_radio(_naming_buttons[1], preferences.letter_names, 28)
	for index in range(_range_buttons.size()):
		_refresh_checkbox(_range_buttons[index], (preferences.range_mask & (1 << index)) != 0)
	for index in range(_chord_buttons.size()):
		var row := _chord_buttons[index]
		row.visible = chord_mode
		_refresh_checkbox(row, (preferences.chord_mask & (1 << index)) != 0)
	_exercise_heading.visible = melody_mode
	_difficulty_heading.visible = melody_mode
	_length_heading.visible = melody_mode and preferences.melody_kind != Exercises.Kind.INTERVAL
	_clef_heading.visible = melody_mode
	for index in range(_exercise_buttons.size()):
		var row := _exercise_buttons[index]
		row.visible = melody_mode
		_refresh_radio(row, preferences.melody_kind == index, 28)
	for index in range(_difficulty_buttons.size()):
		var row := _difficulty_buttons[index]
		row.visible = melody_mode
		_refresh_radio(row, preferences.melody_difficulty == index, 10, 38)
	for index in range(_length_buttons.size()):
		var row := _length_buttons[index]
		row.visible = _length_heading.visible
		_refresh_radio(row, preferences.melody_length == Exercises.LENGTHS[index], 10, 38)
	for index in range(_clef_buttons.size()):
		var row := _clef_buttons[index]
		row.visible = melody_mode
		_refresh_radio(row, preferences.melody_clef == index, 10, 38)
	_layout()


func _refresh_checkbox(row: Button, selected: bool) -> void:
	row.set_pressed_no_signal(selected)
	var box := row.get_node("Checkbox") as Panel
	box.add_theme_stylebox_override("panel", _checked if selected else _check)
	box.get_node("Mark").visible = selected


func _refresh_radio(row: Button, selected: bool, indent: float, trailing := 78.0) -> void:
	row.set_pressed_no_signal(selected)
	row.get_node("Radio/Dot").visible = selected
	var normal := _selected if selected else _dark
	var hover := _radio_selected_hover if selected else _radio_hover
	_apply_styles(row, _with_indent(normal, indent, trailing), _with_indent(hover, indent, trailing), _radio_focus)


func _choice(caption: String, points: int, indent: float, group: ButtonGroup = null) -> Button:
	var row := Button.new()
	row.text = caption
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.toggle_mode = true
	row.button_group = group
	row.add_theme_font_size_override("font_size", points)
	row.add_theme_color_override("font_color", Finish.WHITE)
	row.add_theme_color_override("font_pressed_color", Finish.WHITE)
	if group == null:
		_apply_styles(row, _with_indent(_dark, indent), _with_indent(_selected, indent), _focus)
	add_child(row)
	return row


func _apply_styles(button: Button, normal: StyleBox, hover: StyleBox, focus: StyleBox) -> void:
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("hover_pressed", hover)
	button.add_theme_stylebox_override("focus", focus)


func _add_radio(row: Button, compact := false) -> void:
	var ring := _panel(row, "Radio", _radio, 1.0, -34.0 if compact else -56.0, 22.0 if compact else 32.0)
	var dot_size := 10.0 if compact else 18.0
	var dot := _panel(ring, "Dot", Finish.flat(Color("#d6dde7"), Color.TRANSPARENT, 10), 0.5, -dot_size * 0.5, dot_size)
	dot.hide()


func _add_checkbox(row: Button) -> void:
	var box := _panel(row, "Checkbox", _check, 0.0, 28.0, 40.0)
	var mark := Finish.label("✓", 31, Color("#161a1f"), 1.8)
	mark.name = "Mark"
	_center_icon(box, mark)


func _add_chord_labels(row: Button, title: String, symbols: String) -> void:
	var labels := VBoxContainer.new()
	labels.mouse_filter = MOUSE_FILTER_IGNORE
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.add_theme_constant_override("separation", 0)
	labels.add_child(Finish.label(title, 27))
	labels.add_child(Finish.label(symbols, 21, Finish.MUTED))
	row.add_child(labels)
	labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	labels.offset_left = 93.0
	labels.offset_right = -22.0


func _add_mode_icon(row: Button, mode: Settings.Mode) -> void:
	var tile_style := Finish.flat(Color("#262a2e"), Color("#636970"), 15, 1)
	var tile := _panel(row, "ModeIcon", tile_style, 0.0, 22.0, 50.0)
	if mode == Settings.Mode.STAFF:
		tile.draw.connect(_draw_mode_clef.bind(tile))
	elif mode == Settings.Mode.FREE_PIANO:
		tile.draw.connect(_draw_mode_keyboard.bind(tile))
	else:
		var symbol: String = {Settings.Mode.NAMES: "C", Settings.Mode.MELODIES: "♪"}.get(mode, "♫")
		_center_icon(tile, Finish.label(symbol, 41, Color("#d1d6dc"), 0.95))


func _draw_mode_clef(tile: Control) -> void:
	# Center the glyph's ink using the Bravura bounding box in staff spaces.
	var center_to_baseline := Vector2(-1.342, 0.88) * 8.0
	tile.draw_char(Finish.MUSIC_FONT, tile.size * 0.5 + center_to_baseline, "\uE050", 32, Color("#d1d6dc"))


func _draw_mode_keyboard(tile: Control) -> void:
	var origin := tile.size * 0.5 - Vector2(17.0, 12.0)
	for index in range(4):
		tile.draw_rect(Rect2(origin + Vector2(index * 8.5, 0.0), Vector2(7.5, 24.0)), Finish.WHITE)
	for boundary in [1, 2]:
		tile.draw_rect(Rect2(origin + Vector2(boundary * 8.5 - 2.5, 0.0), Vector2(4.0, 14.0)), Color("#262a2e"))


func _add_label(caption: String, points: int, color: Color, weight: float) -> Label:
	var result := Finish.label(caption, points, color, weight)
	add_child(result)
	return result


static func _panel(
		parent: Control, id: String, style: StyleBox, anchor_x: float, left: float, side: float
) -> Panel:
	var result := Panel.new()
	result.name = id
	result.mouse_filter = MOUSE_FILTER_IGNORE
	result.add_theme_stylebox_override("panel", style)
	parent.add_child(result)
	result.anchor_left = anchor_x
	result.anchor_right = anchor_x
	result.anchor_top = 0.5
	result.anchor_bottom = 0.5
	result.offset_left = left
	result.offset_right = left + side
	result.offset_top = -side * 0.5
	result.offset_bottom = side * 0.5
	return result


static func _center_icon(parent: Control, icon: Label) -> void:
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func _with_indent(style: StyleBox, indent: float, trailing := 78.0) -> StyleBox:
	var inset := style.duplicate() as StyleBox
	inset.set_content_margin(SIDE_LEFT, indent)
	inset.set_content_margin(SIDE_RIGHT, trailing)
	return inset


static func _place(control: Control, x: float, y: float, width: float, height: float) -> void:
	control.position = Vector2(x, y)
	control.size = Vector2(width, height)
