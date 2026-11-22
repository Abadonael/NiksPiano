extends Control

signal menu_requested

const Audio := preload("res://scripts/piano_audio.gd")
const Finish := preload("res://scripts/finish.gd")
const UI := preload("res://scripts/harmony_style.gd")
const Model := preload("res://scripts/harmony_composition.gd")
const Chord := preload("res://scripts/harmony_chords.gd")
const Store := preload("res://scripts/harmony_store.gd")
const Sequence := preload("res://scripts/harmony_sequence.gd")
const Picker := preload("res://scripts/harmony_picker.gd")
const Transport := preload("res://scripts/harmony_transport.gd")
const Interchange := preload("res://scripts/harmony_interchange.gd")
const Settings := preload("res://scripts/settings.gd")
const Notation := preload("res://scripts/harmony_notation.gd")
const Patterns := preload("res://scripts/harmony_patterns.gd")
const Examples := preload("res://scripts/harmony_examples.gd")
const VoicingEditor := preload("res://scripts/harmony_voicing_editor.gd")
const BassSelector := preload("res://scripts/harmony_bass_selector.gd")
const SAVE_DELAY := 0.35
const REPEAT_LABELS := {1: "1×", 2: "2×", 4: "4×", 0: "Цикл"}

enum Page { LIBRARY, EDITOR, SETTINGS, EVENT, PICKER, PROJECT, RENAME, DELETE, EXAMPLES, EXAMPLE, BASS, EVENT_DELETE, COMPARISON }

var audio: Audio
var preferences: Settings
var store := Store.new()
var project: Dictionary
var _undo: Dictionary
var _transport := Transport.new()
var _interchange: Interchange
var _autosave: Timer
var _dirty := false
var _page := Page.LIBRARY
var _frame: VBoxContainer
var _status: Label
var _message := ""
var _save_error := ""
var _sequence: Sequence
var _position: Label
var _run_details: Label
var _editing_controls: Array[BaseButton]
var _play: Button
var _stop: Button
var _undo_button: Button
var _add_button: Button
var _scroll_position := 0
var _picker_event := -1
var _event_index := -1
var _example_index := -1
var _wide_editor := false
var _examples_from_project := false
var _preview_play: Button
var _preview_stop: Button
var _comparison_buttons: Array[Button]
var _comparison_variant := 0
var _comparison_copy: Button
var _pattern_warning := ""


func _ready() -> void:
	theme = UI.make_theme()
	_autosave = Timer.new()
	_autosave.one_shot = true
	add_child(_autosave)
	_autosave.timeout.connect(_flush)
	_interchange = Interchange.new()
	add_child(_interchange)
	_interchange.result.connect(_transfer_result)
	resized.connect(_layout)
	set_process(false)


func enter() -> void:
	_interchange.store = store
	show()
	_message = ""
	_show_library()


func close_page() -> void:
	if _interchange.pending:
		return
	match _page:
		Page.LIBRARY:
			_stop_playback()
			hide()
			menu_requested.emit()
		Page.EDITOR:
			_show_library()
		Page.RENAME, Page.DELETE:
			_show_project()
		Page.PICKER:
			if _picker_event >= 0:
				_show_event(_picker_event)
			else:
				_show_editor()
		Page.BASS, Page.EVENT_DELETE:
			_show_event(_event_index)
		Page.EXAMPLE:
			_show_example_list()
		Page.COMPARISON:
			_show_example(_example_index)
		Page.EXAMPLES:
			if _examples_from_project:
				_show_project()
			else:
				_show_library()
		_:
			_show_editor()


func _notification(what: int) -> void:
	if not is_node_ready() or not visible:
		return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		if is_instance_valid(_sequence):
			_sequence.cancel_gesture()
		_stop_playback()
		_flush()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_page()
		get_viewport().set_input_as_handled()


func _start_page(page: Page) -> void:
	if _page in [Page.EVENT, Page.EXAMPLE, Page.COMPARISON]:
		_stop_playback()
	if is_instance_valid(_sequence):
		_scroll_position = _sequence.scroll_vertical
		_sequence.cancel_gesture()
	_sequence = null
	_play = null
	_preview_play = null
	_preview_stop = null
	_comparison_buttons.clear()
	_comparison_copy = null
	if is_instance_valid(_frame):
		remove_child(_frame)
		_frame.queue_free()
	_page = page
	_frame = VBoxContainer.new()
	_frame.add_theme_constant_override("separation", 12)
	add_child(_frame)
	_status = null
	_layout()


func _layout() -> void:
	if not is_instance_valid(_frame):
		return
	var bounds := Finish.safe_bounds(self)
	var wide := _page == Page.EDITOR and _uses_wide_editor(bounds)
	var width := minf(1220.0 if wide else 780.0, bounds.size.x - 48.0)
	_frame.position = Vector2(bounds.get_center().x - width * 0.5, bounds.position.y + 18.0)
	_frame.size = Vector2(width, bounds.size.y - 36.0)
	if wide != _wide_editor and is_instance_valid(_sequence):
		_sync_editor_layout.call_deferred()


func _sync_editor_layout() -> void:
	if _page == Page.EDITOR and _wide_editor != _uses_wide_editor(Finish.safe_bounds(self)):
		_show_editor()


static func _uses_wide_editor(bounds: Rect2) -> bool:
	return bounds.size.x >= 1080.0 and bounds.size.x > bounds.size.y


func _toolbar(title: String, back: Callable, points := 39, multiline := false) -> HBoxContainer:
	var bar := UI.row(_frame)
	var button := UI.button(bar, "‹", back, 88)
	button.accessibility_name = "Назад"
	var heading := UI.label(bar, title, points)
	UI.ellipsis(heading)
	if multiline:
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		heading.max_lines_visible = 2
		heading.tooltip_text = title
	return bar


func _status_line() -> void:
	_status = UI.label(_frame, "", 22, true)
	_status.custom_minimum_size.y = 36
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_message()


func _update_message() -> void:
	if is_instance_valid(_status):
		_status.text = _save_error if not _save_error.is_empty() else _message
		if _status.text.is_empty() and _page == Page.EDITOR and not project.events.is_empty():
			if not _pattern_warning.is_empty():
				_status.text = _pattern_warning
			elif _transport.state == Transport.State.STOPPED:
				_status.text = "Касание — звук  ·  Удержание аккорда — порядок"
			else:
				_status.text = "Остановите воспроизведение для правки."


func _notify(message: String) -> void:
	_message = message
	_update_message()


func _show_library() -> void:
	_stop_playback()
	if not _flush():
		return
	project = {}
	_start_page(Page.LIBRARY)
	_toolbar("Гармоническая лаборатория", close_page, 33)
	var actions := UI.row(_frame)
	var create := UI.button(actions, "+ Новая композиция", _create_project, 0, 90, true)
	create.size_flags_horizontal = SIZE_EXPAND_FILL
	UI.button(actions, "Импорт", _interchange.choose_import, 164)
	UI.button(_frame, "Примеры", _open_examples)
	var library := store.library()
	var projects: Array = library.projects
	var last := store.last_id()
	if not projects.is_empty():
		var recent: Dictionary = projects[0]
		for item: Dictionary in projects:
			if item.id == last:
				recent = item
				break
		var keep := UI.button(_frame, "Продолжить  ·  " + recent.title, _open.bind(recent.id))
		keep.alignment = HORIZONTAL_ALIGNMENT_LEFT
		keep.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var scroll := UI.scroll(_frame)
	var list := UI.column(scroll, 12)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	UI.label(list, "Сохранённые композиции", 27, true)
	for item: Dictionary in projects:
		_add_library_item(list, item)
	if projects.is_empty():
		UI.label(list, "Здесь появятся ваши композиции.", 25, true)
	if library.damaged > 0:
		var warning := UI.label(list, "Не удалось открыть файлов: %d. Они сохранены для восстановления." % library.damaged, 24, true)
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_line()


func _add_library_item(list: VBoxContainer, item: Dictionary) -> void:
	var button := UI.button(list, "", _open.bind(item.id), 0, 116)
	button.accessibility_name = item.title
	var inset := MarginContainer.new()
	inset.mouse_filter = MOUSE_FILTER_IGNORE
	button.add_child(inset)
	inset.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", 22)
	inset.add_theme_constant_override("margin_right", 20)
	inset.add_theme_constant_override("margin_top", 15)
	var content := UI.column(inset, 1)
	content.mouse_filter = MOUSE_FILTER_IGNORE
	UI.ellipsis(UI.label(content, item.title, 33))
	var modified := Time.get_date_string_from_unix_time(item.modified_at)
	UI.ellipsis(UI.label(content, "%d BPM  ·  %d такт.  ·  %s" % [item.bpm, Model.measures(item), modified], 24, true))


func _create_project() -> void:
	_create(Model.create())


func _open_examples() -> void:
	_examples_from_project = _page == Page.PROJECT
	_show_example_list()


func _show_example_list() -> void:
	_stop_playback()
	_start_page(Page.EXAMPLES)
	_toolbar("Примеры", close_page)
	var scroll := UI.scroll(_frame)
	var list := UI.column(scroll)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	for index in range(Examples.ENTRIES.size()):
		var entry: Dictionary = Examples.ENTRIES[index]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.card_style(false))
		list.add_child(card)
		var content := UI.column(card, 4)
		var open := UI.button(content, entry.roman + "  ·  " + entry.title, _show_example.bind(index), 0, 76)
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.accessibility_name = entry.title
		open.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var summary := UI.label(content, "%s  ·  %s" % [entry.key_label, Examples.progression(Examples.arrangement(index))], 25, true)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _show_example(index: int) -> void:
	_stop_playback()
	_start_page(Page.EXAMPLE)
	_example_index = index
	var entry: Dictionary = Examples.ENTRIES[index]
	var arrangement := Examples.arrangement(index)
	_toolbar(entry.title, close_page, 34, true)
	var scroll := UI.scroll(_frame)
	var body := UI.column(scroll, 16)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	UI.label(body, entry.roman, 37)
	UI.label(body, "%s  ·  4/4  ·  %d BPM" % [entry.key_label, arrangement.bpm], 26, true)
	UI.label(body, Examples.progression(arrangement), 34)
	UI.label(body, Patterns.LABELS[arrangement.default_pattern], 25, true)
	var explanation := UI.label(body, entry.explanation, 29)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var listening := UI.label(body, "Что услышать\n" + entry.listen, 27, true)
	listening.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var controls := UI.row(_frame)
	_preview_play = UI.button(controls, "▶  Слушать", _toggle_arrangement.bind(arrangement))
	_preview_play.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_stop = UI.button(controls, "■  Стоп", _stop_playback, 173)
	if entry.has("comparison"):
		UI.button(_frame, "Сравнить звучание", _show_comparison.bind(index))
	UI.button(_frame, "Открыть копию", _copy_example.bind(arrangement), 0, 86, true)
	_status_line()
	_refresh_transport()


func _show_comparison(index: int) -> void:
	_start_page(Page.COMPARISON)
	_example_index = index
	_comparison_variant = 0
	var entry: Dictionary = Examples.ENTRIES[index]
	var arrangements := [Examples.arrangement(index), Examples.arrangement(index, true)]
	_toolbar("Сравнить звучание", close_page, 34)
	var scroll := UI.scroll(_frame)
	var body := UI.column(scroll, 16)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	var title := UI.label(body, entry.title, 34)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.label(body, "%s  ·  4/4  ·  %d BPM" % [entry.key_label, entry.bpm], 26, true)
	var hint := UI.label(body, entry.compare_listen, 27, true)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for variant in range(2):
		var arrangement: Dictionary = arrangements[variant]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.card_style(false))
		body.add_child(card)
		var content := UI.column(card, 6)
		UI.label(content, "А · Исходная версия" if variant == 0 else "Б · " + entry.comparison, 26, true).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UI.label(content, Examples.progression(arrangement), 34)
		var roman: String = entry.get("comparison_roman", entry.roman) if variant == 1 else entry.roman
		UI.label(content, roman + "  ·  " + Patterns.LABELS[arrangement.default_pattern], 25, true)
		_comparison_buttons.append(UI.button(content, "", _toggle_comparison.bind(arrangement, variant)))
	_preview_stop = UI.button(_frame, "■  Стоп", _stop_playback)
	_comparison_copy = UI.button(_frame, "", func() -> void:
		_copy_example(arrangements[_comparison_variant]), 0, 86, true)
	_status_line()
	_refresh_transport()


func _toggle_comparison(arrangement: Dictionary, variant: int) -> void:
	if _comparison_variant != variant:
		_stop_playback()
		_comparison_variant = variant
	_toggle_arrangement(arrangement)


func _copy_example(arrangement: Dictionary) -> void:
	_create(Model.copy_project(arrangement, arrangement.title.left(Model.MAX_TITLE - 8) + " (копия)"))


func _create(new_project: Dictionary) -> void:
	if not _flush():
		return
	var error := store.save(new_project)
	if error != OK:
		_notify("Не удалось создать композицию (%s)." % error_string(error))
		return
	_switch_project(new_project)


func _open(id: String) -> void:
	var saved := store.load_project(id)
	if saved.is_empty():
		_notify("Не удалось открыть композицию. Файл сохранён для восстановления.")
		return
	_switch_project(saved)


func _switch_project(next: Dictionary) -> void:
	if not _flush():
		return
	_stop_playback()
	project = next
	_undo = {}
	_message = ""
	_show_editor()
	_scroll_position = 0
	_sequence.set_deferred("scroll_vertical", 0)
	if store.remember(project.id) != OK:
		_notify("Не удалось запомнить последнюю открытую композицию.")


func _show_editor() -> void:
	_start_page(Page.EDITOR)
	_wide_editor = _uses_wide_editor(Finish.safe_bounds(self))
	var toolbar := _toolbar(project.title, close_page, 34, true)
	var projects := UI.button(toolbar, "Проект", _show_project, 146)
	projects.accessibility_name = "Меню проекта и сохранение"
	var canvas := _frame
	var controls := _frame
	if _wide_editor:
		var workspace := UI.row(_frame, 20)
		workspace.size_flags_vertical = SIZE_EXPAND_FILL
		canvas = UI.column(workspace, 9)
		canvas.size_flags_horizontal = SIZE_EXPAND_FILL
		controls = UI.column(workspace, 12)
		controls.custom_minimum_size.x = 514
	var settings := UI.row(controls)
	var tempo := UI.button(settings, "%d BPM" % project.bpm, _show_settings, 162)
	tempo.accessibility_name = "Темп и повтор"
	var repeat_button := UI.button(settings, "Повтор  " + REPEAT_LABELS[project.repeat], _show_settings, 192)
	repeat_button.size_flags_horizontal = SIZE_EXPAND_FILL if _wide_editor else SIZE_FILL
	repeat_button.accessibility_name = "Настройки повтора"
	_editing_controls.assign([projects, tempo, repeat_button])
	var performance := settings
	if _wide_editor:
		performance = UI.row(controls)
		UI.label(performance, "Способ исполнения", 23, true)
	var pattern := UI.selector(performance, "Способ исполнения")
	pattern.add_theme_font_size_override("font_size", 24 if _wide_editor else 25)
	for key: String in Patterns.LABELS:
		pattern.add_item(Patterns.LABELS[key])
		pattern.set_item_tooltip(pattern.item_count - 1, Patterns.HINTS[key])
	pattern.select(Patterns.LABELS.keys().find(project.default_pattern))
	pattern.tooltip_text = "Способ исполнения\n" + Patterns.HINTS[project.default_pattern]
	pattern.item_selected.connect(_pattern_changed.bind(pattern))
	_editing_controls.append(pattern)
	_update_pattern_warning()

	var views := UI.row(canvas)
	var group := ButtonGroup.new()
	for by_measure: bool in [true, false]:
		var choice := UI.button(views, "По тактам" if by_measure else "Список", _set_view.bind(by_measure), 0, 74)
		choice.toggle_mode = true
		choice.button_group = group
		choice.size_flags_horizontal = SIZE_EXPAND_FILL
		choice.set_pressed_no_signal(preferences.harmony_by_measure == by_measure)
	_sequence = Sequence.new()
	_sequence.by_measure = preferences.harmony_by_measure
	canvas.add_child(_sequence)
	_sequence.preview_requested.connect(_preview_event)
	_sequence.edit_requested.connect(_show_event)
	_sequence.reorder_requested.connect(_move_event)
	_sequence.gesture_changed.connect(_drag_feedback)
	_sequence.render(project.events)
	_sequence.set_deferred("scroll_vertical", _scroll_position)
	if _wide_editor:
		var space := Control.new()
		space.size_flags_vertical = SIZE_EXPAND_FILL
		controls.add_child(space)
	var actions := UI.row(controls)
	_add_button = UI.button(actions, "+ Добавить аккорд", _show_picker.bind(-1, -1), 0, 86, true)
	_add_button.size_flags_horizontal = SIZE_EXPAND_FILL
	_undo_button = UI.button(actions, "Отменить", _undo_edit, 176)
	_undo_button.accessibility_name = "Отменить последнее изменение"
	_undo_button.disabled = _undo.is_empty()
	_add_button.disabled = project.events.size() >= Model.MAX_EVENTS
	var repeat_label: String = "Цикл с начала" if project.repeat == 0 else "Повтор " + REPEAT_LABELS[project.repeat]
	_run_details = UI.label(controls, "4/4   ·   " + Model.duration_label(Model.length_beats(project)) + "   ·   " + repeat_label, 24, true)
	_run_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_position = UI.label(controls, "", 23, true)
	_position.custom_minimum_size.y = 32
	_position.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_position.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var transport := UI.row(controls)
	_play = UI.button(transport, "▶  Играть", _toggle_play, 0, 98, true)
	_play.size_flags_horizontal = SIZE_EXPAND_FILL
	_stop = UI.button(transport, "■  Стоп", _stop_playback, 200, 98)
	_status_line()
	_refresh_transport()


func _set_view(by_measure: bool) -> void:
	if preferences.harmony_by_measure == by_measure:
		return
	preferences.harmony_by_measure = by_measure
	preferences.save()
	_sequence.by_measure = by_measure
	_sequence.render(project.events)
	_sequence.set_deferred("scroll_vertical", 0)
	_refresh_transport()


func _pattern_changed(index: int, selector: OptionButton) -> void:
	var selected: String = Patterns.LABELS.keys()[index]
	if selected == project.default_pattern:
		return
	var before := project.duplicate(true)
	project.default_pattern = selected
	_changed(before)
	selector.tooltip_text = "Способ исполнения\n" + Patterns.HINTS[selected]
	_undo_button.disabled = false
	_update_pattern_warning()
	_notify(Patterns.HINTS[selected] if _pattern_warning.is_empty() else _pattern_warning)


func _update_pattern_warning() -> void:
	_pattern_warning = ""
	for event: Dictionary in project.events:
		if Patterns.effective(project.default_pattern, event) == "alberti" and not Patterns.alberti_available(event):
			_pattern_warning = Patterns.ALBERTI_FALLBACK
			return


func _show_settings() -> void:
	_stop_for_edit()
	_start_page(Page.SETTINGS)
	_toolbar("Темп и повтор", close_page)
	var scroll := UI.scroll(_frame)
	var content := UI.column(scroll, 17)
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	UI.label(content, "Темп (BPM)", 31)
	var tempo := UI.row(content)
	var value := UI.line_edit(tempo, str(project.bpm), "40–200", 3)
	value.alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	value.size_flags_horizontal = SIZE_EXPAND_FILL
	value.accessibility_name = "Темп в ударах в минуту"
	UI.button(tempo, "−", _step_tempo.bind(value, -5), 105)
	UI.button(tempo, "+", _step_tempo.bind(value, 5), 105)
	UI.label(content, "40–200 BPM  ·  Размер 4/4", 24, true)
	UI.label(content, "Повтор", 31)
	var repeat_group := ButtonGroup.new()
	var repeat_row := UI.row(content)
	var choice := [int(project.repeat)]
	for count: int in Model.REPEATS:
		var button := UI.button(repeat_row, REPEAT_LABELS[count], func() -> void: choice[0] = count)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = repeat_group
		button.set_pressed_no_signal(project.repeat == count)
	var apply := func() -> void:
		var input := value.text.strip_edges()
		if not input.is_valid_int() or int(input) < Model.MIN_BPM or int(input) > Model.MAX_BPM:
			_notify("Введите темп от 40 до 200 BPM.")
			return
		_settings_changed(int(input), choice[0])
	UI.button(_frame, "Применить", apply, 0, 90, true)
	value.text_submitted.connect(func(_text: String) -> void: apply.call())
	_status_line()


func _step_tempo(field: LineEdit, amount: int) -> void:
	var bpm := int(field.text) if field.text.is_valid_int() else int(project.bpm)
	field.text = str(clampi(bpm + amount, Model.MIN_BPM, Model.MAX_BPM))


func _settings_changed(bpm: int, count: int) -> void:
	if bpm != project.bpm or count != project.repeat:
		var before := project.duplicate(true)
		project.bpm = bpm
		project.repeat = count
		_changed(before)
	_show_editor()


func _show_event(index: int) -> void:
	_stop_for_edit()
	_start_page(Page.EVENT)
	_event_index = index
	var event: Dictionary = project.events[index]
	var title_bar := _toolbar(Chord.event_title(event), close_page)
	var heading := title_bar.get_child(1) as Label
	_add_event_menu(title_bar, index)
	var scroll := UI.scroll(_frame)
	var body := UI.column(scroll, 10)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	var identity := UI.label(body, "", 25, true)
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var notation := Notation.new()
	body.add_child(notation)
	var previews := UI.row(body)
	var quick := UI.button(previews, "Аккорд", _audition_event.bind(index), 175)
	_preview_play = UI.button(previews, "С аккомпанементом", _toggle_event_pattern.bind(index), 0, 86, true)
	_preview_play.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_play.accessibility_name = "С аккомпанементом"
	var pattern_source := UI.label(body, "", 25)
	pattern_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pattern_hint := UI.label(body, "", 24, true)
	pattern_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var voicing := VoicingEditor.new()
	voicing.event = event
	body.add_child(voicing)
	voicing.bass_requested.connect(_show_bass.bind(index))
	var refresh := func() -> void:
		heading.text = Chord.event_title(event)
		identity.text = Chord.identity(event.chord)
		identity.visible = event.chord.kind == "catalog"
		if identity.visible:
			identity.text += " — " + (Chord.INVERSION_NAMES[int(event.voicing.inversion)] if event.voicing.inversion != null else "отдельный бас")
		notation.show_event(event)
		voicing.refresh()
		_describe_event_pattern(event, pattern_source, pattern_hint)
	voicing.voicing_changed.connect(func(chord: Dictionary, bass: Variant, spelling: String) -> void:
		var moved: bool = event.bass_midi != bass
		_set_event_voicing(event, chord, bass, spelling)
		refresh.call()
		if moved:
			_notify("Бас перенесён ниже аккорда: %s." % Chord.bass_name(event, int(bass))))
	refresh.call()
	UI.label(body, "Длительность", 27, true)
	var durations := UI.row(body)
	var group := ButtonGroup.new()
	for beats: int in Model.DURATIONS:
		var choice := UI.button(durations, "%d дол." % beats, func() -> void:
			_change_duration(index, beats)
			refresh.call(), 0, 78)
		choice.size_flags_horizontal = SIZE_EXPAND_FILL
		choice.toggle_mode = true
		choice.button_group = group
		choice.set_pressed_no_signal(event.duration_beats == beats)
	UI.button(_frame, "Готово", close_page, 0, 90, true)
	_status_line()


func _describe_event_pattern(event: Dictionary, source: Label, hint: Label) -> void:
	var pattern := Patterns.effective(project.default_pattern, event)
	if event.pattern == null:
		source.text = "Исполнение: %s (из проекта)" % Patterns.LABELS[pattern]
	else:
		source.text = "Для аккорда: %s\nВ проекте: %s" % [Patterns.LABELS[pattern], Patterns.LABELS[project.default_pattern]]
	hint.text = Patterns.event_hint(event, pattern)


func _set_event_voicing(event: Dictionary, chord: Dictionary, bass: Variant, spelling: String) -> void:
	if event.chord == chord and event.bass_midi == bass and event.bass_spelling == spelling:
		return
	var before := project.duplicate(true)
	Model.set_voicing(event, chord, bass, spelling)
	_changed(before)


func _show_bass(index: int) -> void:
	_start_page(Page.BASS)
	_toolbar("Басовая нота", close_page)
	var event: Dictionary = project.events[index]
	var selector := BassSelector.new()
	selector.event = event
	selector.size_flags_vertical = SIZE_EXPAND_FILL
	_frame.add_child(selector)
	selector.applied.connect(func(bass: Variant, spelling: String) -> void:
		_set_event_voicing(event, event.chord, bass, spelling)
		_show_event(index))


func _add_event_menu(toolbar: Control, index: int) -> void:
	var menu := MenuButton.new()
	menu.text = "⋯"
	menu.flat = false
	menu.accessibility_name = "Действия с аккордом"
	menu.custom_minimum_size = Vector2(88, 86)
	menu.add_theme_font_size_override("font_size", 36)
	toolbar.add_child(menu)
	var popup := menu.get_popup()
	popup.add_theme_font_size_override("font_size", 27)
	popup.add_theme_constant_override("v_separation", 44)
	for action: String in ["Заменить аккорд", "Вставить аккорд следом", "Дублировать", "Удалить"]:
		popup.add_item(action)
	var is_full: bool = project.events.size() >= Model.MAX_EVENTS
	popup.set_item_disabled(1, is_full)
	popup.set_item_disabled(2, is_full)
	var actions := [_show_picker.bind(index, -1), _show_picker.bind(-1, index + 1),
		_copy_event.bind(index), _confirm_event_delete.bind(index)]
	popup.id_pressed.connect(func(action: int) -> void: actions[action].call())


func _confirm_event_delete(index: int) -> void:
	_start_page(Page.EVENT_DELETE)
	_toolbar("Удаление аккорда", close_page)
	var title := Chord.event_title(project.events[index])
	var prompt := UI.label(_frame, "Удалить аккорд %s из композиции?" % title, 29)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.button(_frame, "Удалить аккорд", _delete_event.bind(index))
	UI.button(_frame, "Отмена", close_page, 0, 86, true)


func _show_picker(event_index: int, insertion: int) -> void:
	_stop_for_edit()
	_start_page(Page.PICKER)
	_picker_event = event_index
	var picker := Picker.new()
	picker.size_flags_vertical = SIZE_EXPAND_FILL
	if event_index >= 0:
		var event: Dictionary = project.events[event_index]
		picker.initial = event.chord
		picker.initial_beats = event.duration_beats
		picker.initial_bass = event.bass_midi
		picker.initial_bass_spelling = event.bass_spelling
	_frame.add_child(picker)
	picker.canceled.connect(close_page)
	picker.play_requested.connect(_attack)
	picker.chord_chosen.connect(_accept_chord.bind(event_index, insertion))
	_status_line()


func _accept_chord(chord: Dictionary, beats: int, event_index: int, insertion: int) -> void:
	var before := project.duplicate(true)
	var index := event_index
	if event_index >= 0:
		var valid := Chord.validate(chord)
		if valid.is_empty():
			_notify("Не удалось сохранить аккорд. Проверьте название и ноты.")
			return
		var event: Dictionary = project.events[event_index]
		if event.chord != valid:
			var spelling: String = event.bass_spelling
			var bass: Variant = Chord.bass_for_replacement(valid, event.bass_midi, spelling)
			Model.set_voicing(event, valid, bass, spelling if bass != null else "")
		event.duration_beats = beats
		Model.recalculate(project)
	else:
		index = project.events.size() if insertion < 0 else insertion
		if not Model.insert(project, index, chord, beats):
			_notify("Не удалось добавить аккорд.")
			return
	if project != before:
		_changed(before)
	if event_index >= 0:
		_show_event(event_index)
		return
	_show_editor()
	_sequence.reveal.call_deferred(index)


func _change_duration(index: int, beats: int) -> void:
	if int(project.events[index].duration_beats) == beats:
		return
	var before := project.duplicate(true)
	project.events[index].duration_beats = beats
	Model.recalculate(project)
	_changed(before)
	_notify("Длительность изменена.")


func _move_event(from: int, to: int) -> void:
	if _transport.state != Transport.State.STOPPED:
		return
	var before := project.duplicate(true)
	if Model.move(project, from, to):
		_changed(before)
		_sequence.render(project.events)
		_undo_button.disabled = false


func _drag_feedback(reordering: bool) -> void:
	if reordering:
		if _message.is_empty():
			_notify("Перетащите аккорд на новое место.")
	elif _message == "Перетащите аккорд на новое место.":
		_notify("")


func _copy_event(index: int) -> void:
	var before := project.duplicate(true)
	if Model.duplicate_event(project, index):
		_changed(before)
		_show_editor()
		_sequence.reveal.call_deferred(index + 1)


func _delete_event(index: int) -> void:
	var before := project.duplicate(true)
	Model.remove(project, index)
	_changed(before)
	_notify("Аккорд удалён. Изменение можно отменить.")
	_show_editor()


func _undo_edit() -> void:
	if _undo.is_empty():
		return
	_stop_for_edit()
	project = _undo
	_undo = {}
	_mark_dirty()
	_notify("Изменение отменено.")
	_show_editor()


func _changed(before: Dictionary) -> void:
	_stop_for_edit()
	_undo = before
	_mark_dirty()


func _mark_dirty() -> void:
	project.modified_at = maxi(Model.now(), project.created_at)
	_dirty = true
	_autosave.start(SAVE_DELAY)


func _flush() -> bool:
	if not _dirty:
		return true
	_autosave.stop()
	var error := store.save(project)
	_save_error = "" if error == OK else "Не удалось сохранить (%s). Повторите через меню проекта." % error_string(error)
	_update_message()
	_dirty = error != OK
	return not _dirty


func _show_project() -> void:
	_stop_for_edit()
	_start_page(Page.PROJECT)
	_toolbar("Меню проекта", close_page)
	var scroll := UI.scroll(_frame)
	var body := UI.column(scroll, 12)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	UI.ellipsis(UI.label(body, project.title, 32))
	UI.button(body, "Сохранить", _save_now, 0, 86, true)
	UI.button(body, "Переименовать", _show_rename)
	UI.button(body, "Дублировать композицию", _duplicate_project)
	UI.button(body, "Экспорт в файл…", _export)
	UI.button(body, "Библиотека", _show_library)
	UI.button(body, "Примеры", _open_examples)
	UI.button(body, "Удалить композицию…", _confirm_delete)
	_status_line()


func _save_now() -> void:
	if _flush():
		_notify("Композиция сохранена.")


func _show_rename() -> void:
	_start_page(Page.RENAME)
	_toolbar("Название композиции", close_page)
	var value := UI.line_edit(_frame, project.title, "Название", Model.MAX_TITLE)
	var apply := func() -> void:
		var title := value.text.strip_edges()
		if title.is_empty():
			_notify("Введите название композиции.")
			return
		if title != project.title:
			var before := project.duplicate(true)
			project.title = title
			_changed(before)
		_show_editor()
	UI.button(_frame, "Сохранить название", apply, 0, 90, true)
	value.text_submitted.connect(func(_text: String) -> void: apply.call())
	_status_line()


func _duplicate_project() -> void:
	if _flush():
		_create(Model.copy_project(project, project.title.left(Model.MAX_TITLE - 8) + " (копия)"))


func _confirm_delete() -> void:
	_start_page(Page.DELETE)
	_toolbar("Удаление композиции", close_page)
	var prompt := UI.label(_frame, "Удалить «%s» с этого устройства?" % project.title, 31)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.button(_frame, "Удалить композицию", _delete_project)
	UI.button(_frame, "Отмена", close_page, 0, 86, true)
	_status_line()


func _delete_project() -> void:
	var error := store.delete_project(project.id)
	if error != OK:
		_notify("Не удалось удалить композицию (%s)." % error_string(error))
		return
	_autosave.stop()
	_dirty = false
	_save_error = ""
	_notify("Композиция удалена.")
	_show_library()


func _export() -> void:
	if _flush():
		_interchange.choose_export(project)


func _transfer_result(action: String, error: Error, imported: Dictionary) -> void:
	if error == OK:
		if action == "import":
			_switch_project(imported)
			_notify("Импортирована новая композиция.")
		else:
			_notify("Композиция экспортирована.")
	elif error == ERR_UNAVAILABLE:
		_notify("Формат или системный выбор файла недоступен.")
	elif error == ERR_FILE_CORRUPT or error == ERR_INVALID_DATA:
		_notify("Не удалось проверить файл композиции.")
	else:
		_notify("Ошибка работы с файлом (%s)." % error_string(error))


func _preview_event(index: int) -> void:
	if _transport.state == Transport.State.STOPPED:
		_attack(project.events[index].sounding_pitches)


func _audition_event(index: int) -> void:
	if _transport.state != Transport.State.STOPPED:
		_stop_playback()
	_preview_event(index)


func _toggle_event_pattern(index: int) -> void:
	var preview := project.duplicate()
	var event: Dictionary = project.events[index].duplicate()
	event.start_beat = 0
	preview.events = [event]
	preview.repeat = 1
	_toggle_arrangement(preview)


func _attack(notes: Array) -> void:
	var pitches: Array[int] = []
	pitches.assign(notes)
	audio.play_harmony(pitches)


func _toggle_play() -> void:
	_toggle_arrangement(project)


func _toggle_arrangement(arrangement: Dictionary) -> void:
	var now := Time.get_ticks_usec()
	match _transport.state:
		Transport.State.PLAYING:
			_transport.pause(now)
			audio.fade_harmony()
			set_process(false)
		Transport.State.PAUSED:
			_transport.resume(now)
			set_process(true)
		_:
			if _transport.start(arrangement, now):
				_notify("")
				set_process(true)
				_tick(now)
	_refresh_transport()


func _stop_for_edit() -> void:
	var was_playing := _transport.state != Transport.State.STOPPED
	_stop_playback()
	if was_playing:
		_notify("Воспроизведение остановлено для редактирования.")


func _stop_playback() -> void:
	_transport.stop()
	set_process(false)
	if audio != null:
		audio.fade_harmony()
	_refresh_transport()


func _process(_delta: float) -> void:
	_tick(Time.get_ticks_usec())


func _tick(now: int) -> void:
	var event := _transport.tick(now)
	if not event.is_empty():
		_attack(event.attack_pitches)
	if _transport.state == Transport.State.STOPPED:
		set_process(false)
	_refresh_transport()


func _refresh_transport() -> void:
	var active := _transport.state != Transport.State.STOPPED
	if is_instance_valid(_preview_play):
		var caption := "С аккомпанементом" if _page == Page.EVENT else "▶  Слушать"
		_preview_play.text = _play_label(caption)
	if is_instance_valid(_preview_stop):
		_preview_stop.disabled = not active
	if _page == Page.COMPARISON and is_instance_valid(_comparison_copy):
		var letters := ["А", "Б"]
		for variant in range(_comparison_buttons.size()):
			var caption := "▶  Слушать " + str(letters[variant])
			_comparison_buttons[variant].text = _play_label(caption) if variant == _comparison_variant else caption
		_comparison_copy.text = "Открыть копию версии " + str(letters[_comparison_variant])
	if not is_instance_valid(_play):
		return
	var position := ""
	if active:
		position = "Такт %d / %d · доля %d / %d" % [Model.measure(_transport.beat),
			Model.measures(project), _transport.beat % Model.BEATS_PER_MEASURE + 1, Model.BEATS_PER_MEASURE]
	_position.text = position
	for button in _editing_controls:
		button.disabled = active
	_add_button.disabled = active or project.events.size() >= Model.MAX_EVENTS
	_undo_button.disabled = active or _undo.is_empty()
	_play.text = _play_label("▶  Играть")
	_play.disabled = project.events.is_empty()
	_stop.disabled = not active
	_sequence.set_locked(active)
	_sequence.show_position(_transport.event_index, _transport.beat if active else -1)
	_update_message()


func _play_label(start: String) -> String:
	return {Transport.State.STOPPED: start, Transport.State.PLAYING: "Ⅱ  Пауза",
		Transport.State.PAUSED: "▶  Продолжить"}[_transport.state]
