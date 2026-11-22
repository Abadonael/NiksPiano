extends "res://scripts/chord_game.gd"

const Theory := preload("res://scripts/key_theory.gd")
const Exercises := preload("res://scripts/melody_exercises.gd")
const Studies := preload("res://scripts/circle_exercises.gd")
const Progress := preload("res://scripts/melody_progress.gd")
const MelodyStaff := preload("res://scripts/melody_staff.gd")
const MelodyPiano := preload("res://scripts/melody_piano.gd")
const PREVIEW_STEP := 0.33

var _key: Theory.Tonality
var _scale := Progress.new()
var _scale_mode := false
var _scale_form := Theory.ScaleForm.NATURAL
var _scores: Array[Exercises.Exercise] = []
var _chord_index := -1
var _staff: MelodyStaff
var _scale_piano: MelodyPiano
var _action: Button
var _form_picker: HBoxContainer
var _natural_button: Button
var _status: Label
var _progression: Label
var _preview: Timer
var _preview_index := 0


func _ready() -> void:
	super._ready()
	_menu.text = "‹"
	_menu.accessibility_name = "К квинтовому кругу"
	_symbol.add_theme_font_size_override("font_size", 27)
	_symbol.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status = Finish.label("", 24, Finish.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_status)
	_progression = Finish.label("", 25, Finish.WHITE)
	_progression.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progression.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_progression)
	_staff = MelodyStaff.new()
	_staff.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_staff)
	_scale_piano = MelodyPiano.new()
	_scale_piano.name = "ScalePiano"
	_scale_piano.key_pressed.connect(_press_scale)
	add_child(_scale_piano)
	_action = Finish.action_button("Слушать", 22)
	_action.pressed.connect(_use_action)
	add_child(_action)
	_form_picker = HBoxContainer.new()
	_form_picker.add_theme_constant_override("separation", 8)
	add_child(_form_picker)
	var forms := ButtonGroup.new()
	_natural_button = _form_button("Натуральный", Theory.ScaleForm.NATURAL, forms)
	_form_button("Гармонический", Theory.ScaleForm.HARMONIC, forms)
	_form_picker.hide()
	_preview = Timer.new()
	_preview.wait_time = PREVIEW_STEP
	_preview.timeout.connect(_preview_note)
	add_child(_preview)
	audio.enabled_changed.connect(_preview_sound_changed)
	get_window().size_changed.connect(_layout)
	_layout()


func study(key: Theory.Tonality, scale_mode: bool) -> void:
	_key = key
	_scale_mode = scale_mode
	_scale_form = Theory.ScaleForm.NATURAL
	_natural_button.button_pressed = true
	_form_picker.visible = scale_mode and key.minor
	_scale_piano.visible = scale_mode
	_piano.visible = not scale_mode
	_restart()
	_layout()


func stop() -> void:
	if _scale_mode:
		_cancel_preview(true)
	else:
		super.stop()
	_scale.reset(null)
	_scores.clear()
	_staff.show_phrase(null)
	_key = null


func _restart() -> void:
	_status.add_theme_color_override("font_color", Finish.MUTED)
	if _scale_mode:
		if _scale.exercise == null:
			_scale.reset(Studies.scale(_key, _scale_form))
		else:
			_scale.reset(_scale.exercise)
		_staff.show_phrase(_scale.exercise)
		_scale_piano.clear_feedback()
		_symbol.text = "%s  ·  Гамма" % _key.short_name()
		_progression.text = ""
		_scale_status()
		_update_scale_action()
	else:
		_scores = Studies.progression(_key)
		_chord_index = -1
		_next_chord()


func _form_button(caption: String, form: Theory.ScaleForm, group: ButtonGroup) -> Button:
	var button := Finish.action_button(caption, 22)
	var selected := Finish.flat(Finish.TEAL, Color("#45949b"), 13, 1)
	selected.set_content_margin_all(8.0)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("hover_pressed", selected)
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_change_form.bind(form))
	_form_picker.add_child(button)
	return button


func _change_form(form: Theory.ScaleForm) -> void:
	if _scale_form == form:
		return
	_cancel_preview(true)
	_scale_form = form
	_scale.reset(Studies.scale(_key, _scale_form))
	_restart()


func _press_scale(key: int) -> void:
	if _scale.exercise == null:
		return
	_cancel_preview(true)
	var midi := Exercises.FIRST_MIDI + key
	audio.play_note(midi)
	var result := _scale.press(midi)
	if result == Progress.Result.IGNORED:
		return
	_scale_piano.show_feedback(key, result != Progress.Result.WRONG)
	_staff.show_progress(_scale.completed)
	_scale_status()
	_update_scale_action()


func _scale_status() -> void:
	if _scale.completed == _scale.exercise.attack_count:
		_status.text = "Гамма сыграна"
		_status.add_theme_color_override("font_color", Finish.SUCCESS_GREEN)
	else:
		_status.text = "%d / %d  ·  Сыграйте ноты по порядку" % [_scale.completed, _scale.exercise.attack_count]
		if _key.minor:
			var natural := _key.note_name(6)
			var raised := _key.note_name(6, Theory.ScaleForm.HARMONIC)
			var explanation := "VII ступень: %s. В гармоническом миноре — %s." % [natural, raised]
			if _scale_form == Theory.ScaleForm.HARMONIC:
				explanation = "VII ступень: %s → %s. До тоники %s — полутон." % [natural, raised, _key.note_name(0)]
			_status.text = "%d / %d  ·  %s" % [_scale.completed, _scale.exercise.attack_count, explanation]


func _update_scale_action() -> void:
	var complete := _scale.completed == _scale.exercise.attack_count
	_action.text = "Повторить" if complete else ("Стоп" if not _preview.is_stopped() else "Слушать")
	_action.disabled = not complete and not audio.enabled
	_action.show()


func _use_action() -> void:
	if not _scale_mode or _scale.completed == _scale.exercise.attack_count:
		_restart()
	elif not _preview.is_stopped():
		_cancel_preview(true)
	elif audio.enabled:
		_preview_index = 0
		_preview.start()
		_update_scale_action()
		_preview_note()


func _preview_note() -> void:
	if _preview_index >= _scale.exercise.notes.size():
		_cancel_preview(false)
		return
	var midi := _scale.exercise.notes[_preview_index].midi
	audio.play_note(midi)
	_scale_piano.show_feedback(midi - Exercises.FIRST_MIDI, true)
	_preview_index += 1


func _cancel_preview(fade: bool) -> void:
	if _preview.is_stopped():
		return
	_preview.stop()
	if fade:
		audio.fade_keys(PianoAudio.STOP_FADE_SECONDS)
	_update_scale_action()


func _preview_sound_changed(_enabled: bool) -> void:
	if _scale.exercise != null:
		if not audio.enabled:
			_cancel_preview(false)
		_update_scale_action()


func _next_chord() -> void:
	_completion = null
	_accepted.clear()
	_piano.clear_feedback()
	_chord_index += 1
	if _chord_index == _scores.size():
		_chord = null
		_status.text = "Последовательность сыграна"
		_status.add_theme_color_override("font_color", Finish.SUCCESS_GREEN)
		_action.text = "Повторить"
		_action.disabled = false
		_action.show()
		return
	var score := _scores[_chord_index]
	var degree: int = Studies.PROGRESSION[_chord_index]
	_chord = Chords.Triad.new(score.chord_symbol, _key.pitch_class(degree))
	var form := Studies.cadence_form(_key)
	_symbol.text = "%s  ·  %s — %s  ·  %d / %d" % [
		_key.short_name(), _key.triad_roman(degree, form), score.chord_symbol, _chord_index + 1, _scores.size()]
	var tones := PackedStringArray()
	for note in score.notes:
		tones.append(note.written_name())
	_progression.text = "  ·  ".join(tones)
	_staff.show_phrase(score)
	_status.text = Studies.FUNCTIONS[_chord_index]
	if _key.minor and degree == 4:
		_status.text = "В %s нота %s тяготеет к %s. Натуральная v — %s." % [
			score.chord_symbol, _key.note_name(6, form), _key.note_name(0), _key.triad_name(degree)]
	_action.hide()


func _answer_pitch(key: int) -> int:
	var pitch := PianoAudio.C4 + key
	for note in _scores[_chord_index].notes:
		if note.midi == pitch:
			return key % Chords.PITCH_CLASSES
	return -1


func _answer_with(key: int) -> void:
	super._answer_with(key)
	if _accepted.size() == 3:
		_staff.show_progress(1)


func _layout() -> void:
	if _staff == null:
		return
	var bounds := Finish.safe_bounds(self)
	var side := bounds.size.x * 0.006
	var upper := bounds.size.y * 0.335
	var target := clampf(bounds.size.y * 0.19, 56.0, 92.0)
	var rail := target + side * 2.0
	_menu.position = bounds.position + Vector2(side, side)
	_menu.size = Vector2.ONE * target
	_sound.set_metrics(target, target * 0.78)
	_sound.position = Vector2(bounds.end.x - side - target, _menu.position.y)
	var column := Rect2(bounds.position + Vector2(rail, 0.0), Vector2(bounds.size.x - 2.0 * rail, upper))
	_symbol.position = column.position
	_symbol.size = Vector2(column.size.x, 35.0)
	_symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var notation_top := 35.0
	if _form_picker.visible:
		_form_picker.position = Vector2(column.end.x - 420.0, column.position.y + 3.0)
		_form_picker.size = Vector2(420.0, 48.0)
		_symbol.size = Vector2(column.size.x - 428.0, 52.0)
		_symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		notation_top = 53.0
	_status.position = column.position + Vector2(0.0, upper - 36.0)
	_status.size = Vector2(column.size.x, 34.0)
	var tones_width := 0.0 if _scale_mode else 285.0
	_staff.position = column.position + Vector2(0.0, notation_top)
	_staff.size = Vector2(column.size.x - tones_width, upper - notation_top - 38.0)
	_staff.queue_redraw()
	_progression.position = Vector2(column.get_center().x + 55.0, bounds.position.y + upper * 0.49)
	_progression.size = Vector2(280.0, 36.0)
	_action.position = Vector2(bounds.end.x - side - 138.0, _menu.position.y + target + 7.0)
	_action.size = Vector2(138.0, 76.0)
	_scale_piano.position = bounds.position + Vector2(side, upper)
	_scale_piano.size = Vector2(bounds.size.x - 2.0 * side, bounds.size.y * 0.652)
	var chord_margin := bounds.size.x * 0.023
	_piano.position = bounds.position + Vector2(chord_margin, upper)
	_piano.size = Vector2(bounds.size.x - chord_margin * 2.0, minf(bounds.size.y * 0.61, bounds.size.x * 0.43))
	if OS.get_name() == "Android":
		var pixels_per_dp := maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
		var pixels_per_unit := get_viewport().get_final_transform().get_scale().x
		_scale_piano.fit_black_touch_width(40.0 * pixels_per_dp / maxf(0.01, pixels_per_unit))
