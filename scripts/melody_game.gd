extends Control

signal menu_requested

const Finish := preload("res://scripts/finish.gd")
const HeaderButton := preload("res://scripts/header_button.gd")
const Notes := preload("res://scripts/notes.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const Exercises := preload("res://scripts/melody_exercises.gd")
const Progress := preload("res://scripts/melody_progress.gd")
const MelodyPiano := preload("res://scripts/melody_piano.gd")
const MelodyStaff := preload("res://scripts/melody_staff.gd")
const SUCCESS_SECONDS := 0.8
const BLACK_TOUCH_DP := 40.0

var audio: PianoAudio
var _generator := Exercises.new()
var _progress := Progress.new()
var _kind: Exercises.Kind
var _difficulty: Exercises.Difficulty
var _length: int
var _clef: Notes.Clef
var _menu: Button
var _sound: HeaderButton
var _symbol: Label
var _interval_answer: Label
var _staff: MelodyStaff
var _piano: MelodyPiano
var _success: Timer


func _ready() -> void:
	_menu = Finish.menu_button()
	_menu.pressed.connect(func() -> void: menu_requested.emit())
	add_child(_menu)
	_sound = HeaderButton.new()
	_sound.audio = audio
	add_child(_sound)
	_symbol = Finish.label("", 32)
	_symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_symbol.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_symbol)

	_staff = MelodyStaff.new()
	_staff.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_staff)
	_interval_answer = Finish.label("", 28, Finish.SUCCESS_GREEN)
	_interval_answer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interval_answer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_interval_answer)
	_piano = MelodyPiano.new()
	_piano.key_pressed.connect(_answer_with)
	add_child(_piano)
	_success = Timer.new()
	_success.one_shot = true
	_success.wait_time = SUCCESS_SECONDS
	_success.timeout.connect(_next_exercise)
	add_child(_success)

	resized.connect(_layout)
	get_window().size_changed.connect(_layout)
	visibility_changed.connect(_layout)
	_layout()


func start(kind: Exercises.Kind, difficulty: Exercises.Difficulty, length: int, clef: Notes.Clef) -> void:
	_kind = kind
	_difficulty = difficulty
	_length = length
	_clef = clef
	_success.stop()
	_next_exercise()


func stop() -> void:
	_success.stop()
	_show_exercise(null)


func _next_exercise() -> void:
	_show_exercise(_generator.next(_kind, _difficulty, _length, _clef))


func _show_exercise(exercise: Exercises.Exercise) -> void:
	_progress.reset(exercise)
	_staff.show_phrase(exercise)
	_symbol.text = exercise.chord_symbol if exercise != null else ""
	_interval_answer.text = ""
	_piano.clear_feedback()


func _answer_with(key: int) -> void:
	var exercise := _progress.exercise
	if exercise == null:
		return
	var first := Exercises.first_midi(exercise.clef)
	var midi := first + key
	audio.play_note(midi)
	var held: Array[int] = []
	if exercise.kind == Exercises.Kind.INTERVAL:
		held = _piano.held_pitches(first)
	var result := _progress.press(midi, held)
	if result == Progress.Result.IGNORED:
		return
	_piano.show_feedback(key, result != Progress.Result.WRONG)
	_staff.show_progress(_progress.completed)
	if result == Progress.Result.COMPLETE:
		if exercise.kind == Exercises.Kind.INTERVAL:
			_interval_answer.text = exercise.interval_name
			for note in exercise.notes:
				var expected := note.midi - first
				_piano.show_feedback(expected, true)
				_piano.mark_correct(expected)
		_success.start()


func _layout() -> void:
	var bounds := Finish.safe_bounds(self)
	var side := bounds.size.x * 0.006
	var bottom := bounds.size.y * 0.013
	var upper := bounds.size.y * 0.335
	var target := clampf(bounds.size.y * 0.19, 56.0, 92.0)
	var rail := target + side * 2.0
	_menu.position = bounds.position + Vector2(side, side)
	_menu.size = Vector2.ONE * target
	_sound.set_metrics(target, target * 0.78)
	_sound.position = Vector2(bounds.end.x - side - target, _menu.position.y)
	_symbol.position = _menu.position + Vector2(0.0, target + 3.0)
	_symbol.size = Vector2(target, 40.0)
	_staff.position = bounds.position + Vector2(rail, 0.0)
	_staff.size = Vector2(maxf(0.0, bounds.size.x - rail * 2.0), upper)
	_staff.queue_redraw()
	var answer_height := MelodyStaff.ANSWER_HEIGHT
	_interval_answer.position = _staff.position + Vector2(0.0, upper - answer_height - MelodyStaff.ANSWER_BOTTOM_MARGIN)
	_interval_answer.size = Vector2(_staff.size.x, answer_height)
	_piano.position = bounds.position + Vector2(side, upper)
	_piano.size = Vector2(bounds.size.x - 2.0 * side, bounds.size.y - upper - bottom)
	if OS.get_name() == "Android":
		var pixels_per_dp := maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
		var pixels_per_unit := get_viewport().get_final_transform().get_scale().x
		_piano.fit_black_touch_width(BLACK_TOUCH_DP * pixels_per_dp / maxf(0.01, pixels_per_unit))
