extends Control

signal menu_requested

const Finish := preload("res://scripts/finish.gd")
const Notes := preload("res://scripts/notes.gd")
const Chords := preload("res://scripts/chords.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const NoteBag := preload("res://scripts/note_bag.gd")
const Staff := preload("res://scripts/staff.gd")
const Piano := preload("res://scripts/piano.gd")
const HeaderButton := preload("res://scripts/header_button.gd")
const FEEDBACK_SECONDS := 0.4

var audio: PianoAudio
var _staff_mode := true
var _letter_names := false
var _bag := NoteBag.new()
var _answer := -1
var _menu: Button
var _sound: HeaderButton
var _staff: Staff
var _piano: Piano
var _note_name: Label
var _octave: Label
var _feedback: Timer


func _ready() -> void:
	_menu = Finish.menu_button()
	_menu.pressed.connect(func() -> void: menu_requested.emit())
	add_child(_menu)
	_sound = HeaderButton.new()
	_sound.audio = audio
	add_child(_sound)

	_staff = Staff.new()
	_staff.name = "Staff"
	_staff.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_staff)
	_note_name = Finish.label("", 132, Finish.WHITE, 0.85)
	_note_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_note_name)
	_piano = Piano.new()
	_piano.name = "Piano"
	_piano.key_pressed.connect(_answer_with)
	add_child(_piano)
	_octave = Finish.label("", 26)
	_octave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_octave)

	_feedback = Timer.new()
	_feedback.name = "Feedback"
	_feedback.wait_time = FEEDBACK_SECONDS
	_feedback.one_shot = true
	_feedback.timeout.connect(_next_note)
	add_child(_feedback)
	resized.connect(_layout)
	visibility_changed.connect(_layout)
	_layout()


func start(staff_mode: bool, letter_names: bool, range_mask: int) -> void:
	_feedback.stop()
	var ranges: Array[int] = [NoteBag.NO_RANGE]
	if staff_mode:
		ranges = Notes.enabled_ranges(range_mask)
	_bag.use_ranges(ranges, not staff_mode and letter_names != _letter_names)
	_staff_mode = staff_mode
	_letter_names = letter_names
	_staff.visible = staff_mode
	_octave.visible = staff_mode
	_note_name.visible = not staff_mode
	_next_note()


func stop() -> void:
	_feedback.stop()
	_answer = -1


func _next_note() -> void:
	var question := _bag.next()
	_answer = question.pitch_class
	_piano.highlight(-1)
	if _staff_mode:
		var range_index := question.range_index
		_staff.show_note(range_index, _answer)
		_octave.text = Notes.RANGES[range_index].title
	else:
		var names := Notes.LETTERS if _letter_names else Notes.RUSSIAN
		_note_name.text = names[_answer]


func _answer_with(pitch_class: int) -> void:
	if _answer < 0:
		return
	var octave: int = Notes.RANGES[_staff.range_index].octave if _staff_mode else 4
	audio.play_note((octave + 1) * Chords.PITCH_CLASSES + Chords.WHITE_PITCHES[pitch_class])
	if not _feedback.is_stopped():
		return
	var correct := pitch_class == _answer
	_piano.highlight(pitch_class, correct)
	if _staff_mode:
		_staff.show_answer(pitch_class, correct)
	if correct:
		_feedback.start()


func _layout() -> void:
	var piano_y := size.y * 0.673
	var piano_height := minf(size.x * 0.437, size.y * 0.251)
	var bounds := Finish.safe_bounds(self)
	var header_y := maxf(31.0, size.y * 0.03)
	_menu.position = bounds.position + Vector2(25.0, header_y)
	_menu.size = Vector2(58.0, 58.0)
	_sound.position = Vector2(bounds.end.x - 25.0 - _sound.size.x,
		_menu.position.y + (_menu.size.y - _sound.size.y) * 0.5)
	var header_to_piano := piano_y - _menu.get_rect().end.y
	_staff.position = Vector2(0.0, piano_y - 335.0 - header_to_piano * 0.10)
	_staff.size = Vector2(size.x, 260.0)
	_staff.queue_redraw()
	_note_name.position = Vector2(0.0, piano_y - 306.0)
	_note_name.size = Vector2(size.x, 214.0)
	var piano_margin := size.x * 0.023
	_piano.position = Vector2(piano_margin, piano_y)
	_piano.size = Vector2(size.x - piano_margin * 2.0, piano_height)
	_octave.position = Vector2(0.0, piano_y + piano_height + 27.0)
	_octave.size = Vector2(size.x, 50.0)
