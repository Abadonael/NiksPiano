extends VBoxContainer

signal chord_chosen(chord: Dictionary, beats: int)
signal play_requested(pitches: Array)
signal canceled

const UI := preload("res://scripts/harmony_style.gd")
const Chord := preload("res://scripts/harmony_chords.gd")
const Model := preload("res://scripts/harmony_composition.gd")
const Keyboard := preload("res://scripts/harmony_keyboard.gd")
const Notation := preload("res://scripts/harmony_notation.gd")
const QUALITIES := {"major": "Мажор", "minor": "Минор", "diminished": "Уменьш.", "augmented": "Увелич."}

var initial: Dictionary
var initial_beats := 4
var initial_bass: Variant
var initial_bass_spelling := ""
var _quality := "major"
var _root := ""
var _custom := false
var _selected: Dictionary
var _custom_notes: Array[int] = []
var _custom_name := "Свой аккорд"
var _option: OptionButton
var _details: Label
var _notation: Notation
var _root_buttons: Array[Button] = []
var _spelling_toggle: Button
var _spelling_row: HBoxContainer
var _spelling_open := false
var _keyboard: Keyboard
var _octave_label: Label
var _octave_down: Button
var _octave_up: Button
var _name_edit: LineEdit
var _note_buttons: GridContainer
var _body_scroll: ScrollContainer
var _body: VBoxContainer
var _submit: Button
var _listen: Button
var _switch: Button


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	if not initial.is_empty():
		if initial.kind == "custom":
			_custom = true
			_custom_notes.assign(initial.pitches)
			_custom_name = initial.name
		else:
			_selected = initial.duplicate(true)
			_root = initial.root
			_quality = initial.quality
	var toolbar := UI.row(self)
	var back := UI.button(toolbar, "‹", canceled.emit, 86)
	back.accessibility_name = "Назад"
	UI.ellipsis(UI.label(toolbar, "Выбор аккорда" if initial.is_empty() else "Замена аккорда", 36))
	_switch = UI.button(toolbar, "", _switch_mode, 230)
	_body_scroll = UI.scroll(self)
	_body = UI.column(_body_scroll, 13)
	_body.size_flags_horizontal = SIZE_EXPAND_FILL
	_listen = UI.button(self, "Прослушать", _preview, 0, 80)
	var bottom := UI.row(self)
	var duration := UI.label(bottom, "Длительность", 24, true)
	_option = OptionButton.new()
	_option.custom_minimum_size = Vector2(158, 88)
	_option.accessibility_name = "Длительность аккорда"
	for beats: int in Model.DURATIONS:
		_option.add_item("%d дол." % beats, beats)
	_option.get_popup().add_theme_constant_override("v_separation", 40)
	_option.select(Model.DURATIONS.find(initial_beats))
	bottom.add_child(_option)
	_submit = UI.button(bottom, "Добавить" if initial.is_empty() else "Применить", _confirm, 172, 90, true)
	_submit.size_flags_horizontal = SIZE_EXPAND_FILL
	_rebuild()


func _switch_mode() -> void:
	_custom = not _custom
	_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_body_scroll.scroll_vertical = 0
	_root_buttons.clear()
	_spelling_open = false
	_switch.text = "Каталог" if _custom else "Свой аккорд"
	_listen.visible = _custom
	if _custom:
		_build_custom()
	else:
		_build_catalog()
	_notation = Notation.new()
	_notation.audition_enabled = true
	_body.add_child(_notation)
	_notation.audition_requested.connect(_preview)
	_refresh()


func _build_catalog() -> void:
	UI.label(_body, "Тип трезвучия", 25, true)
	var quality_group := ButtonGroup.new()
	var qualities := GridContainer.new()
	qualities.columns = 4
	qualities.add_theme_constant_override("h_separation", 10)
	qualities.add_theme_constant_override("v_separation", 8)
	_body.add_child(qualities)
	for quality: String in QUALITIES:
		var choice := UI.button(qualities, QUALITIES[quality], _choose_quality.bind(quality), 0, 80)
		choice.add_theme_font_size_override("font_size", 24)
		choice.size_flags_horizontal = SIZE_EXPAND_FILL
		choice.toggle_mode = true
		choice.button_group = quality_group
		choice.set_pressed_no_signal(quality == _quality)
	UI.label(_body, "Основной тон", 25, true)
	var roots := GridContainer.new()
	roots.columns = 4
	roots.add_theme_constant_override("h_separation", 8)
	roots.add_theme_constant_override("v_separation", 8)
	_body.add_child(roots)
	var root_group := ButtonGroup.new()
	for pitch_class in range(Chord.DEFAULT_ROOTS.size()):
		var choice := UI.button(roots, "", _choose_pitch_class.bind(pitch_class), 0, 76)
		choice.size_flags_horizontal = SIZE_EXPAND_FILL
		choice.toggle_mode = true
		choice.button_group = root_group
		_root_buttons.append(choice)
	_spelling_toggle = UI.button(_body, "Другое написание", _toggle_spellings, 0, 76)
	_spelling_toggle.toggle_mode = true
	_spelling_row = UI.row(_body)


func _selected_pitch_class() -> int:
	return -1 if _root.is_empty() else Chord.Chords._root_pitch(_root)


func _choose_pitch_class(pitch_class: int) -> void:
	if _selected_pitch_class() == pitch_class:
		_preview()
		return
	_spelling_open = false
	_choose_root(Chord.DEFAULT_ROOTS[pitch_class])


func _toggle_spellings() -> void:
	_spelling_open = _spelling_toggle.button_pressed
	_refresh_spellings(_selected_pitch_class())


func _refresh_spellings(pitch_class: int) -> void:
	var options := Chord.root_spellings(pitch_class) if pitch_class >= 0 else PackedStringArray()
	_spelling_toggle.visible = options.size() > 1
	_spelling_toggle.set_pressed_no_signal(_spelling_open)
	_spelling_row.visible = _spelling_toggle.visible and _spelling_open
	for child in _spelling_row.get_children():
		_spelling_row.remove_child(child)
		child.queue_free()
	if not _spelling_row.visible:
		return
	var group := ButtonGroup.new()
	for spelling in options:
		var choice := UI.button(_spelling_row, Chord.written_pitch_class(spelling), _choose_root.bind(spelling), 0, 76)
		choice.size_flags_horizontal = SIZE_EXPAND_FILL
		choice.toggle_mode = true
		choice.button_group = group
		choice.set_pressed_no_signal(spelling == _root)


func _choose_quality(quality: String) -> void:
	if _quality == quality:
		if not _selected.is_empty():
			_preview()
		return
	_quality = quality
	_select_catalog_chord()


func _choose_root(root: String) -> void:
	if _root == root and not _selected.is_empty():
		_preview()
		return
	_root = root
	_select_catalog_chord()


func _select_catalog_chord() -> void:
	if initial.get("quality") == _quality and Chord.Chords._root_pitch(initial.root) == _selected_pitch_class():
		_selected = initial.duplicate(true)
		_selected.root = _root
	else:
		_selected = Chord.catalog(_root, _quality)
	_refresh()


func _build_custom() -> void:
	_name_edit = UI.line_edit(_body, _custom_name, "Название аккорда", 48)
	_name_edit.accessibility_name = "Название своего аккорда"
	_name_edit.text_changed.connect(func(value: String) -> void:
		_custom_name = value
		_refresh())
	UI.label(_body, "Выберите от 2 до 6 клавиш.", 26, true)
	var range_row := UI.row(_body)
	_octave_down = UI.button(range_row, "‹", _move_octave.bind(-1), 86)
	_octave_down.accessibility_name = "Октава ниже"
	_octave_label = UI.label(range_row, "", 26, true)
	_octave_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_octave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_octave_up = UI.button(range_row, "›", _move_octave.bind(1), 86)
	_octave_up.accessibility_name = "Октава выше"
	_keyboard = Keyboard.new()
	_keyboard.custom_minimum_size.y = 248
	_keyboard.accessibility_name = "Клавиши для выбора нот"
	_keyboard.selected = _custom_notes
	_keyboard.note_pressed.connect(func(midi: int, _pointer: int) -> void: _toggle(midi))
	if not _custom_notes.is_empty():
		_keyboard.octave = clampi(floori(_custom_notes[0] / 12.0) - 1, 1, 7)
	_body.add_child(_keyboard)
	_move_octave(0)
	_details = UI.label(_body, "", 25, true)
	_note_buttons = GridContainer.new()
	_note_buttons.columns = 3
	_note_buttons.add_theme_constant_override("h_separation", 8)
	_note_buttons.add_theme_constant_override("v_separation", 8)
	_body.add_child(_note_buttons)
	_render_notes()


func _move_octave(offset: int) -> void:
	_keyboard.set_octave(_keyboard.octave + offset)
	_octave_label.text = "%s — %s" % [Chord.pitch_name(_keyboard.white_keys.front()), Chord.pitch_name(_keyboard.white_keys.back())]
	_octave_down.disabled = _keyboard.octave == 1
	_octave_up.disabled = _keyboard.octave == 7


func _toggle(midi: int) -> void:
	if midi in _custom_notes:
		_custom_notes.erase(midi)
	elif _custom_notes.size() < 6:
		_custom_notes.append(midi)
		_custom_notes.sort()
	else:
		return
	_keyboard.queue_redraw()
	_render_notes()
	_refresh()


func _render_notes() -> void:
	for child in _note_buttons.get_children():
		_note_buttons.remove_child(child)
		child.queue_free()
	for midi in _custom_notes:
		var key := UI.button(_note_buttons, Chord.pitch_name(midi) + "  ×", _toggle.bind(midi), 0, 80)
		key.size_flags_horizontal = SIZE_EXPAND_FILL
		key.accessibility_name = "Убрать " + Chord.pitch_name(midi)


func _refresh() -> void:
	var definition := _definition()
	if _custom:
		_details.text = "Выбрано %d из 6" % _custom_notes.size()
		_listen.disabled = not Chord.pitches_are_valid(_custom_notes)
		_submit.disabled = _listen.disabled or _custom_name.strip_edges().is_empty()
		if _custom_notes.is_empty():
			definition = {}
	else:
		var pitch_class := _selected_pitch_class()
		for index in range(_root_buttons.size()):
			var choice := _root_buttons[index]
			var spelling: String = _root if index == pitch_class else Chord.DEFAULT_ROOTS[index]
			choice.text = Chord.written_pitch_class(spelling)
			choice.set_pressed_no_signal(index == pitch_class)
		_refresh_spellings(pitch_class)
		_submit.disabled = _selected.is_empty()
	var bass: Variant = _preview_bass(definition)
	var hint := "Выберите ноты." if _custom else "Выберите основной тон."
	_notation.show_chord(definition, hint, bass, initial_bass_spelling)


func _definition() -> Dictionary:
	return Chord.custom(_custom_name, _custom_notes) if _custom else _selected


func _preview() -> void:
	var definition := _definition()
	if not definition.is_empty() and Chord.pitches_are_valid(definition.pitches):
		play_requested.emit(Chord.sounding(definition, _preview_bass(definition)))


func _preview_bass(definition: Dictionary) -> Variant:
	if definition.is_empty():
		return null
	return Chord.bass_for_replacement(definition, initial_bass, initial_bass_spelling)


func _confirm() -> void:
	chord_chosen.emit(_definition(), _option.get_selected_id())
