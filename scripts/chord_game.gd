extends Control

signal menu_requested

const Finish := preload("res://scripts/finish.gd")
const Chords := preload("res://scripts/chords.gd")
const ChordBag := preload("res://scripts/chord_bag.gd")
const ChordPiano := preload("res://scripts/chord_piano.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const HeaderButton := preload("res://scripts/header_button.gd")
const SUCCESS_SECONDS := 0.4
const KEY_HOLD_SECONDS := 0.26
const KEY_RELEASE_SECONDS := 0.35
const SILENCE_SECONDS := 0.35
const TRIAD_LISTEN_SECONDS := 1.25
const TRIAD_FADE_SECONDS := 0.25
const SILENCE_MIX_GUARD_FRAMES := 2 * PianoAudio.MIX_BLOCK_FRAMES

var audio: PianoAudio
var _bag := ChordBag.new()
var _chord: Chords.Triad
var _accepted: Array[int] = []
var _menu: Button
var _sound: HeaderButton
var _symbol: Label
var _piano: ChordPiano
var _success: Timer
var _completion: Tween
var _completed_at_usec: int
var _silence_until_usec: int


func _ready() -> void:
	_menu = Finish.menu_button()
	_menu.pressed.connect(func() -> void: menu_requested.emit())
	add_child(_menu)
	_sound = HeaderButton.new()
	_sound.audio = audio
	add_child(_sound)
	audio.enabled_changed.connect(_on_sound_changed)

	_symbol = Finish.label("", 116, Finish.WHITE, 0.85)
	_symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_symbol.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_symbol)

	_piano = ChordPiano.new()
	_piano.name = "Piano"
	_piano.key_pressed.connect(_answer_with)
	add_child(_piano)

	_success = Timer.new()
	_success.one_shot = true
	_success.wait_time = SUCCESS_SECONDS
	_success.timeout.connect(_next_chord)
	add_child(_success)

	resized.connect(_layout)
	visibility_changed.connect(_layout)
	set_process(false)
	_layout()


func start(group_mask: int) -> void:
	_success.stop()
	_cancel_completion()
	_bag.use_groups(group_mask)
	_next_chord()


func stop() -> void:
	_success.stop()
	_cancel_completion()
	audio.fade_keys(PianoAudio.STOP_FADE_SECONDS)
	audio.fade_triad(PianoAudio.STOP_FADE_SECONDS)
	_chord = null
	_accepted.clear()
	_piano.clear_feedback()


func _next_chord() -> void:
	_completion = null
	_chord = _bag.next()
	_accepted.clear()
	_symbol.text = _chord.symbol
	_piano.clear_feedback()


func _answer_with(key: int) -> void:
	if _chord == null or _completion != null or not _success.is_stopped():
		return
	audio.play_note(PianoAudio.C4 + key)
	var pitch := key % Chords.PITCH_CLASSES
	if pitch not in _chord.pitches:
		_piano.mark_wrong(key)
		return
	if pitch in _accepted:
		_piano.flash_correct(key)
		return
	_accepted.append(pitch)
	_piano.mark_correct(key)
	if _accepted.size() == _chord.pitches.size():
		if audio.enabled:
			_complete_with_sound()
		else:
			_success.start(SUCCESS_SECONDS)


func _complete_with_sound() -> void:
	_completed_at_usec = Time.get_ticks_usec()
	_wait_for_audio(KEY_HOLD_SECONDS, _release_keys)


func _release_keys() -> void:
	var fade := audio.release_keys(KEY_RELEASE_SECONDS)
	if fade == null:
		_start_silence()
		return
	_completion = fade
	fade.finished.connect(_start_silence, CONNECT_ONE_SHOT)


func _start_silence() -> void:
	# Leave room for the mixer's stop ramp and block scheduling before counting silence.
	var mix_guard := SILENCE_MIX_GUARD_FRAMES / AudioServer.get_mix_rate()
	_silence_until_usec = Time.get_ticks_usec() + ceili((SILENCE_SECONDS + mix_guard) * 1_000_000.0)
	set_process(true)


func _process(_delta: float) -> void:
	if Time.get_ticks_usec() >= _silence_until_usec:
		set_process(false)
		_play_completed_chord()


func _play_completed_chord() -> void:
	_wait_for_audio(TRIAD_LISTEN_SECONDS - TRIAD_FADE_SECONDS, _release_triad)
	audio.play_triad(_chord.root_position(PianoAudio.C4))


func _release_triad() -> void:
	var fade := audio.fade_triad(TRIAD_FADE_SECONDS)
	if fade == null:
		_next_chord()
		return
	_completion = fade
	fade.finished.connect(_next_chord, CONNECT_ONE_SHOT)


func _wait_for_audio(seconds: float, next_step: Callable) -> void:
	_completion = create_tween()
	_completion.tween_interval(seconds)
	_completion.tween_callback(next_step)


func _on_sound_changed(value: bool) -> void:
	if value or _completion == null:
		return
	var remaining := SUCCESS_SECONDS - (Time.get_ticks_usec() - _completed_at_usec) / 1_000_000.0
	_cancel_completion()
	if remaining > 0.0:
		_success.start(remaining)
	else:
		_next_chord()


func _cancel_completion() -> void:
	set_process(false)
	if _completion != null:
		_completion.kill()
		_completion = null


func _layout() -> void:
	var bounds := Finish.safe_bounds(self)
	var margin := bounds.size.x * 0.023
	var header := bounds.size.y * 0.32
	_menu.position = bounds.position + Vector2(margin, bounds.size.y * 0.038)
	_menu.size = Vector2(80.0, 76.0)
	_sound.position = Vector2(bounds.end.x - margin - _sound.size.x, _menu.position.y)
	var symbol_inset := margin + _sound.size.x + 12.0
	_symbol.position = bounds.position + Vector2(symbol_inset, 0.0)
	_symbol.size = Vector2(bounds.size.x - symbol_inset * 2.0, header)
	_piano.position = bounds.position + Vector2(margin, header)
	_piano.size = Vector2(bounds.size.x - margin * 2.0, minf(bounds.size.y * 0.61, bounds.size.x * 0.43))
