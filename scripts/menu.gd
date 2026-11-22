extends Control

signal start_requested

const Finish := preload("res://scripts/finish.gd")
const Style := preload("res://scripts/workspace_style.gd")
const Notes := preload("res://scripts/notes.gd")
const Chords := preload("res://scripts/chords.gd")
const Settings := preload("res://scripts/settings.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const Credits := preload("res://scripts/credits.gd")
const Exercises := preload("res://scripts/melody_exercises.gd")

const MODE_TITLES := [
	"По нотному стану", "По названию", "Аккорды", "Свободная клавиатура",
	"Мелодии", "Квинтовый круг", "Гармоническая лаборатория",
]
const MODE_DETAILS := [
	"Чтение нот", "Названия и клавиши", "Трезвучия", "88 клавиш · глиссандо",
	"Фразы и арпеджио", "Тональности и гармония", "Аккордовые последовательности",
]
const MODE_ICONS := ["staff", "names", "chords", "piano", "note", "circle", "layers"]
const PRACTICE := [Settings.Mode.STAFF, Settings.Mode.NAMES, Settings.Mode.CHORDS, Settings.Mode.MELODIES]

var preferences: Settings
var audio: PianoAudio

var _style := Style.new()
var _frame: VBoxContainer
var _toolbar: HBoxContainer
var _title: Label
var _brand_mark: Panel
var _headline: Label
var _info: Button
var _sound: Button
var _back: Button
var _credits: Credits
var _home_scroll: ScrollContainer
var _scroll: ScrollContainer
var _settings_pages: Dictionary[Settings.Mode, VBoxContainer]
var _mode_buttons: Array[Button]
var _range_buttons: Array[Button]
var _naming_buttons: Array[Button]
var _chord_buttons: Array[Button]
var _exercise_buttons: Array[Button]
var _difficulty_buttons: Array[Button]
var _length_buttons: Array[Button]
var _clef_buttons: Array[Button]
var _length_section: VBoxContainer
var _start: Button


func _ready() -> void:
	theme = _style.make_theme()
	var background := TextureRect.new()
	background.texture = Style.background()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	_frame = _column(self, 23)
	_frame.mouse_filter = MOUSE_FILTER_IGNORE
	_build_header()

	_home_scroll = _make_scroll("WorkspaceModules")
	_build_home(_column(_home_scroll, 44))
	_scroll = _make_scroll("ExerciseSettings")
	var pages := _column(_scroll, 0)
	for mode: Settings.Mode in PRACTICE:
		_settings_pages[mode] = _column(pages, 32)
		_settings_pages[mode].hide()
	_build_note_settings()
	_build_chord_settings()
	_build_melody_settings()

	_start = Button.new()
	_start.name = "Start"
	_start.text = "Начать"
	_start.theme_type_variation = &"Primary"
	_start.custom_minimum_size.y = 108
	_start.add_theme_font_size_override("font_size", 34)
	_start.pressed.connect(func() -> void: start_requested.emit())
	_frame.add_child(_start)
	_set_settings_visible(false)

	_credits = Credits.new()
	_credits.hide()
	add_child(_credits)
	_credits.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_credits.closed.connect(close_credits)

	resized.connect(_layout)
	visibility_changed.connect(_layout)
	_layout()


func _build_header() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 15)
	_frame.add_child(header)
	_brand_mark = Panel.new()
	_brand_mark.custom_minimum_size = Vector2(66, 66)
	_brand_mark.size_flags_vertical = SIZE_SHRINK_CENTER
	_brand_mark.mouse_filter = MOUSE_FILTER_IGNORE
	_brand_mark.add_theme_stylebox_override("panel", Finish.flat(Color("#21484c"), Color("#3c696d"), 16, 2))
	_brand_mark.draw.connect(func() -> void:
		var baseline := _brand_mark.size * 0.5 + Vector2(-1.342, 0.88) * 8.0
		_brand_mark.draw_char(Finish.MUSIC_FONT, baseline, "\uE050", 32, Style.INK))
	header.add_child(_brand_mark)
	_title = _label("Nik's Piano", 40, Style.INK, _style.title_font)
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_title)
	_back = _header_action("SettingsBack", "Назад", "back")
	_back.pressed.connect(close_settings)
	header.add_child(_back)
	_headline = _label("", 38, Style.INK, _style.title_font)
	_headline.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_headline)

	_toolbar = HBoxContainer.new()
	_toolbar.name = "Toolbar"
	_toolbar.add_theme_constant_override("separation", 12)
	header.add_child(_toolbar)
	_info = _header_action("Information", "Об игре", "info")
	_info.pressed.connect(func() -> void: _credits.open())
	_toolbar.add_child(_info)
	_sound = _header_action("Sound", "Звук", "sound")
	_sound.toggle_mode = true
	_sound.toggled.connect(audio.set_enabled)
	audio.enabled_changed.connect(_sync_sound)
	_toolbar.add_child(_sound)
	_sync_sound(audio.enabled)

	var rule := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Style.LINE
	line.thickness = 2
	rule.add_theme_stylebox_override("separator", line)
	_frame.add_child(rule)


func _build_home(home: VBoxContainer) -> void:
	_mode_buttons.resize(Settings.Mode.size())
	var practice := _section(home, "Практика")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	practice.add_child(grid)
	for mode: Settings.Mode in PRACTICE:
		_add_mode(grid, mode, true)

	var theory := _section(home, "Теория и творчество")
	_add_mode(theory, Settings.Mode.CIRCLE)
	_add_mode(theory, Settings.Mode.HARMONY_LAB)
	var tools := _section(home, "Инструменты")
	_add_mode(tools, Settings.Mode.FREE_PIANO)


func _add_mode(parent: Container, mode: Settings.Mode, tile := false) -> void:
	var button := _card(parent, MODE_TITLES[mode], MODE_DETAILS[mode], MODE_ICONS[mode], tile)
	button.pressed.connect(_select_mode.bind(mode))
	_mode_buttons[mode] = button


func _build_note_settings() -> void:
	var ranges := _section(_settings_pages[Settings.Mode.STAFF], "Диапазоны")
	for clef: Notes.Clef in Notes.Clef.values():
		var group := _section(ranges, "Скрипичный ключ" if clef == Notes.Clef.TREBLE else "Басовый ключ", 27)
		var choices := _choice_row(group)
		for index in range(Notes.RANGES.size()):
			if Notes.RANGES[index].clef == clef:
				var button := _chip(choices, Notes.RANGES[index].title)
				button.pressed.connect(_toggle_range.bind(index))
				_range_buttons.append(button)

	var naming := _section(_settings_pages[Settings.Mode.NAMES], "Названия нот")
	var formats := _choice_row(naming)
	var radio := ButtonGroup.new()
	for caption in ["До Ре Ми", "C D E"]:
		var button := _chip(formats, caption, radio)
		button.pressed.connect(_select_naming.bind(not _naming_buttons.is_empty()))
		_naming_buttons.append(button)


func _build_chord_settings() -> void:
	var groups := _section(_settings_pages[Settings.Mode.CHORDS], "Группы аккордов")
	for index in range(Chords.GROUPS.size()):
		var button := _card(groups, Chords.GROUP_TITLES[index], ", ".join(Chords.GROUPS[index]), "chords", false, true)
		button.pressed.connect(_toggle_chord_group.bind(index))
		_chord_buttons.append(button)


func _build_melody_settings() -> void:
	var page := _settings_pages[Settings.Mode.MELODIES]
	var exercises := _section(page, "Вид упражнения")
	var exercise_group := ButtonGroup.new()
	var exercise_titles := ["Арпеджио", "Музыкальные фразы", "Гармонические интервалы"]
	var exercise_icons := ["arpeggio", "note", "interval"]
	for kind: Exercises.Kind in Exercises.Kind.values():
		var button := _card(exercises, exercise_titles[kind], "", exercise_icons[kind], false, true)
		button.button_group = exercise_group
		button.pressed.connect(_select_exercise.bind(kind))
		_exercise_buttons.append(button)

	var difficulty := _choice_row(_section(page, "Сложность"))
	var difficulty_group := ButtonGroup.new()
	var difficulty_titles := ["Начальный", "Средний", "Продвинутый"]
	for level: Exercises.Difficulty in Exercises.Difficulty.values():
		var button := _chip(difficulty, difficulty_titles[level], difficulty_group, 26)
		button.pressed.connect(_select_difficulty.bind(level))
		_difficulty_buttons.append(button)

	_length_section = _section(page, "Количество нот")
	var counts := _choice_row(_length_section)
	var length_group := ButtonGroup.new()
	for count: int in Exercises.LENGTHS:
		var button := _chip(counts, str(count), length_group)
		button.pressed.connect(_select_length.bind(count))
		_length_buttons.append(button)

	var clefs := _choice_row(_section(page, "Нотный ключ"))
	var clef_group := ButtonGroup.new()
	for clef: Notes.Clef in Notes.Clef.values():
		var button := _chip(clefs, "Скрипичный" if clef == Notes.Clef.TREBLE else "Басовый", clef_group)
		button.pressed.connect(_select_clef.bind(clef))
		_clef_buttons.append(button)


func _make_scroll(id: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = id
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 14
	scroll.follow_focus = true
	_frame.add_child(scroll)
	return scroll


func _card(parent: Container, title: String, detail: String, symbol: String, tile: bool, selectable := false) -> Button:
	var button := Button.new()
	button.accessibility_name = title
	button.accessibility_description = detail
	button.theme_type_variation = &"Tile" if tile else &"Navigation"
	button.toggle_mode = selectable
	button.custom_minimum_size.y = 206 if tile else (102 if detail.is_empty() else 134)
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(button)

	var inset := MarginContainer.new()
	inset.mouse_filter = MOUSE_FILTER_IGNORE
	button.add_child(inset)
	inset.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 24 if side in ["left", "right"] else 20)

	var labels := VBoxContainer.new()
	labels.mouse_filter = MOUSE_FILTER_IGNORE
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.size_flags_horizontal = SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 3)
	var name_label := _label(title, 29, Style.INK, _style.strong_font)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.add_child(name_label)
	if not detail.is_empty():
		var description := _label(detail, 23, Style.MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		labels.add_child(description)

	if tile:
		var stack := _column(inset, 0)
		var mark := _icon_rect(symbol, 42)
		mark.size_flags_horizontal = SIZE_SHRINK_END
		stack.add_child(mark)
		labels.size_flags_vertical = SIZE_EXPAND | SIZE_SHRINK_END
		stack.add_child(labels)
	else:
		var row := HBoxContainer.new()
		row.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 24)
		inset.add_child(row)
		row.add_child(_icon_rect(symbol, 40))
		row.add_child(labels)
		var indicator := _icon_rect("check" if selectable else "arrow", 34)
		indicator.modulate.a = 0.0 if selectable else 1.0
		row.add_child(indicator)
		if selectable:
			button.set_meta(&"selection_indicator", indicator)
	return button


func _icon_rect(symbol: String, side: int) -> TextureRect:
	var result := TextureRect.new()
	result.texture = _style.icon(symbol)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.custom_minimum_size = Vector2.ONE * side
	result.size_flags_vertical = SIZE_SHRINK_CENTER
	result.modulate = Style.ICON
	result.mouse_filter = MOUSE_FILTER_IGNORE
	return result


func _header_action(id: String, caption: String, symbol: String) -> Button:
	var button := Button.new()
	button.name = id
	button.accessibility_name = caption
	button.tooltip_text = caption
	button.theme_type_variation = &"HeaderAction"
	button.custom_minimum_size = Vector2.ONE * 100
	button.icon = _style.icon(symbol)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 43)
	return button


func _sync_sound(enabled: bool) -> void:
	_sound.set_pressed_no_signal(enabled)
	_sound.icon = _style.icon("sound" if enabled else "muted")
	_sound.accessibility_name = "Выключить звук" if enabled else "Включить звук"
	_sound.tooltip_text = _sound.accessibility_name


func _label(caption: String, points: int, color: Color, font: Font = null) -> Label:
	var label := Finish.label(caption, points, color)
	if font != null:
		label.add_theme_font_override("font", font)
	return label


func _section(parent: Container, caption: String, points := 26) -> VBoxContainer:
	var group := _column(parent, 14)
	group.add_child(_label(caption, points, Style.SECTION, _style.strong_font))
	return group


static func _column(parent: Control, separation: int) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.size_flags_horizontal = SIZE_EXPAND_FILL
	result.mouse_filter = MOUSE_FILTER_IGNORE
	result.add_theme_constant_override("separation", separation)
	parent.add_child(result)
	return result


static func _choice_row(parent: Container) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	return row


static func _chip(parent: Container, caption: String, group: ButtonGroup = null, points := 28) -> Button:
	var button := Button.new()
	button.text = caption
	button.theme_type_variation = &"Choice"
	button.custom_minimum_size.y = 100
	button.add_theme_font_size_override("font_size", points)
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_group = group
	parent.add_child(button)
	return button


func _layout() -> void:
	var bounds := Finish.safe_bounds(self)
	var margin := clampf(bounds.size.x * 0.049, 30.0, 48.0)
	var width := minf(840.0, bounds.size.x - margin * 2.0)
	var vertical_margin := clampf(bounds.size.y * 0.024, 18.0, 34.0)
	_frame.position = Vector2(bounds.get_center().x - width * 0.5, bounds.position.y + vertical_margin)
	_frame.size = Vector2(width, bounds.size.y - vertical_margin * 2.0)


func _select_mode(mode: Settings.Mode) -> void:
	preferences.mode = mode
	preferences.save()
	if not _settings_pages.has(mode):
		start_requested.emit()
		return
	_headline.text = MODE_TITLES[mode]
	_refresh()
	_set_settings_visible(true)
	_scroll.set_deferred("scroll_vertical", 0)


func _set_settings_visible(active: bool) -> void:
	_home_scroll.visible = not active
	_scroll.visible = active
	_start.visible = active
	_title.visible = not active
	_brand_mark.visible = not active
	_headline.visible = active
	_back.visible = active
	_info.visible = not active
	for mode: Settings.Mode in _settings_pages:
		_settings_pages[mode].visible = active and preferences.mode == mode


func close_settings() -> bool:
	if not _scroll.visible:
		return false
	_set_settings_visible(false)
	return true


func close_credits() -> bool:
	if not _credits.visible:
		return false
	_credits.hide()
	_info.grab_focus()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and close_settings():
		get_viewport().set_input_as_handled()


func _select_naming(letters: bool) -> void:
	preferences.letter_names = letters
	_changed()


func _select_exercise(kind: Exercises.Kind) -> void:
	preferences.melody_kind = kind
	_changed()


func _select_difficulty(level: Exercises.Difficulty) -> void:
	preferences.melody_difficulty = level
	_changed()


func _select_length(count: int) -> void:
	preferences.melody_length = count
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


func _changed() -> void:
	preferences.save()
	_refresh()


func _refresh() -> void:
	_select_one(_naming_buttons, int(preferences.letter_names))
	for index in range(_range_buttons.size()):
		_range_buttons[index].set_pressed_no_signal((preferences.range_mask & (1 << index)) != 0)
	for index in range(_chord_buttons.size()):
		_set_card_selected(_chord_buttons[index], (preferences.chord_mask & (1 << index)) != 0)
	for index in range(_exercise_buttons.size()):
		_set_card_selected(_exercise_buttons[index], index == preferences.melody_kind)
	_select_one(_difficulty_buttons, preferences.melody_difficulty)
	_length_section.visible = preferences.melody_kind != Exercises.Kind.INTERVAL
	_select_one(_length_buttons, Exercises.LENGTHS.find(preferences.melody_length))
	_select_one(_clef_buttons, preferences.melody_clef)


static func _set_card_selected(button: Button, selected: bool) -> void:
	button.set_pressed_no_signal(selected)
	var indicator: TextureRect = button.get_meta(&"selection_indicator")
	indicator.modulate.a = float(selected)


static func _select_one(buttons: Array[Button], index: int) -> void:
	for choice in range(buttons.size()):
		buttons[choice].set_pressed_no_signal(choice == index)
