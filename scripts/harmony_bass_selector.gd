extends VBoxContainer

signal applied(bass: Variant, spelling: String)

const Chord := preload("res://scripts/harmony_chords.gd")
const Model := preload("res://scripts/harmony_composition.gd")
const UI := preload("res://scripts/harmony_style.gd")

var event: Dictionary
var _midi: Variant
var _spelling := ""
var _available: Array[int]
var _register_row: HBoxContainer
var _register: Label
var _lower: Button
var _higher: Button
var _spellings: OptionButton
var _summary: Label
var _explanation: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var scroll := UI.scroll(self)
	var body := UI.column(scroll, 11)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	_wrap(body, "Бас — самый низкий звучащий звук аккорда.", 29)
	var group := ButtonGroup.new()
	var automatic := UI.button(body, "По расположению аккорда", _choose_automatic, 0, 76)
	automatic.toggle_mode = true
	automatic.button_group = group
	var lowest := int(event.chord.pitches.min())
	var automatic_name := Chord.written_pitch(lowest, Chord.tone_spelling(event.chord, lowest))
	var automatic_hint := "Использовать нижний звук выбранного обращения." if event.chord.kind == "catalog" else "Использовать нижний звук заданного аккорда."
	_wrap(body, "%s\n%s: %s" % [automatic_hint,
		"Сейчас в басу" if event.bass_midi == null else "Бас по расположению", automatic_name], 24, true)
	UI.label(body, "Выбрать другой бас", 27)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	var has_register := false
	for pitch_class in range(12):
		var spelling := Chord.explicit_bass_spelling(event.chord, pitch_class)
		if event.bass_midi != null and int(event.bass_midi) % 12 == pitch_class:
			spelling = event.bass_spelling
		var choice := UI.button(grid, Chord.written_pitch_class(spelling), _choose_pitch.bind(pitch_class), 0, 79)
		choice.size_flags_horizontal = SIZE_EXPAND_FILL
		choice.toggle_mode = true
		choice.button_group = group
		choice.disabled = Chord.bass_registers(event.chord, pitch_class).is_empty()
		has_register = has_register or not choice.disabled
		choice.set_pressed_no_signal(event.bass_midi != null and int(event.bass_midi) % 12 == pitch_class)
	automatic.set_pressed_no_signal(event.bass_midi == null)
	if not has_register:
		_wrap(body, "Ниже этого аккорда нет доступных клавиш.", 24, true)
	_register_row = UI.row(body)
	_lower = UI.button(_register_row, "−", _step_register.bind(1), 76, 76)
	_lower.accessibility_name = "Бас на октаву ниже"
	_register = UI.label(_register_row, "", 26)
	_register.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_register.size_flags_horizontal = SIZE_EXPAND_FILL
	_higher = UI.button(_register_row, "+", _step_register.bind(-1), 76, 76)
	_higher.accessibility_name = "Бас на октаву выше"
	_spellings = UI.selector(_register_row, "Написание басовой ноты", 76)
	_spellings.item_selected.connect(_change_spelling)
	_summary = _wrap(body, "", 29)
	_explanation = _wrap(body, "", 24, true)
	_wrap(body, "Бас может менять переход между аккордами. У до мажора C, E и G в басу дают основной вид, первое и второе обращения.", 23, true)
	UI.button(self, "Применить бас", func() -> void: applied.emit(_midi, _spelling), 0, 86, true)
	_midi = event.bass_midi
	_spelling = event.bass_spelling
	if _midi != null:
		_available = Chord.bass_pitches(event.chord, _spelling)
	_refresh()


func _wrap(parent: Control, caption: String, points: int, muted := false) -> Label:
	var label := UI.label(parent, caption, points, muted)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _choose_automatic() -> void:
	_midi = null
	_spelling = ""
	_refresh()


func _choose_pitch(pitch_class: int) -> void:
	if _midi != null and int(_midi) % 12 == pitch_class:
		return
	_available = Chord.bass_registers(event.chord, pitch_class)
	if _available.is_empty():
		return
	_midi = _available[0]
	_spelling = Chord.explicit_bass_spelling(event.chord, pitch_class)
	if event.bass_midi != null and int(event.bass_midi) % 12 == pitch_class:
		_spelling = event.bass_spelling
		_midi = event.bass_midi
	_refresh()


func _step_register(amount: int) -> void:
	var index := _available.find(_midi) + amount
	if index >= 0 and index < _available.size():
		_midi = _available[index]
		_refresh()


func _change_spelling(index: int) -> void:
	_spelling = _spellings.get_item_metadata(index)
	_refresh()


func _refresh() -> void:
	var explicit: bool = _midi != null
	_register_row.visible = explicit
	if explicit:
		var register_index := _available.find(_midi)
		_lower.disabled = register_index == _available.size() - 1
		_higher.disabled = register_index <= 0
		_register.text = "Октава · " + Chord.written_pitch(_midi, _spelling)
		_spellings.clear()
		var spellings := Chord.bass_spellings(event.chord, int(_midi) % 12)
		for spelling in spellings:
			_spellings.add_item("Запись: " + Chord.written_pitch_class(spelling))
			_spellings.set_item_metadata(_spellings.item_count - 1, spelling)
		_spellings.select(spellings.find(_spelling))
	var preview := {}
	Model.set_voicing(preview, event.chord, _midi, _spelling)
	var bass := Chord.bass_name(preview, int(preview.sounding_pitches.min()))
	_summary.text = "Выбрано: %s  ·  Аккорд: %s" % [bass, Chord.event_title(preview)]
	if preview.voicing.inversion != null:
		_explanation.text = "%s — нижний звук. %s — %s." % [bass, Chord.identity(event.chord), Chord.INVERSION_NAMES[preview.voicing.inversion]]
	elif event.chord.kind == "catalog":
		_explanation.text = "%s — отдельный бас в аккорде %s." % [bass, Chord.title(event.chord)]
	else:
		_explanation.text = "%s — нижний звук этой раскладки." % bass
