extends Node

signal note_started(midi: int)
signal triad_started(midi_notes: Array[int])
signal enabled_changed(value: bool)

const C4 := 60
const LOWEST_SAMPLE := 36
const HIGHEST_SAMPLE := 84
const KEY_VOICES := 10
const TRIAD_VOICES := 3
const FREE_VOICES := 64
const FREE_LOWEST := 21
const FREE_HIGHEST := 108
const KEY_DB := -3.0
const TRIAD_DB := -6.0
const FREE_DB := -12.0
const FREE_MIN_ATTACK_SECONDS := 0.065
const FREE_RELEASE_SECONDS := 0.35
const STOP_FADE_SECONDS := 0.025
const KEY_DAMPING_DB := 32.0
const KEY_DAMPING_RAMP_FRACTION := 0.35
const KEY_RELEASE_TAPER_FRACTION := 0.22
# The Godot 4.7 stream mixer processes 512 frames at a time.
const MIX_BLOCK_FRAMES := 512
const SAMPLES: Array[AudioStreamWAV] = [
	preload("res://assets/piano/36.wav"), preload("res://assets/piano/39.wav"),
	preload("res://assets/piano/42.wav"), preload("res://assets/piano/45.wav"),
	preload("res://assets/piano/48.wav"), preload("res://assets/piano/51.wav"),
	preload("res://assets/piano/54.wav"), preload("res://assets/piano/57.wav"),
	preload("res://assets/piano/60.wav"), preload("res://assets/piano/63.wav"),
	preload("res://assets/piano/66.wav"), preload("res://assets/piano/69.wav"),
	preload("res://assets/piano/72.wav"), preload("res://assets/piano/75.wav"),
	preload("res://assets/piano/78.wav"), preload("res://assets/piano/81.wav"),
	preload("res://assets/piano/84.wav"),
]
const BASS: Array[AudioStreamWAV] = [
	preload("res://assets/piano/21.wav"), preload("res://assets/piano/24.wav"),
	preload("res://assets/piano/27.wav"), preload("res://assets/piano/30.wav"),
	preload("res://assets/piano/33.wav"),
]
const TREBLE: Array[AudioStreamWAV] = [
	preload("res://assets/piano/87.wav"), preload("res://assets/piano/90.wav"),
	preload("res://assets/piano/93.wav"), preload("res://assets/piano/96.wav"),
	preload("res://assets/piano/99.wav"), preload("res://assets/piano/102.wav"),
	preload("res://assets/piano/105.wav"), preload("res://assets/piano/108.wav"),
]
# Measured fundamental corrections to A440, in cents, for each recorded anchor A0–C8.
# Apply these only in Free Piano so the training modes keep their established sound.
const FREE_TUNING_CENTS := [
	19, 13, 5, 13, 17, 21, 23, 13, 9, 15,
	7, 11, 3, 7, 3, 3, 3, 5, 5, 1,
	-1, 1, 3, -1, 3, -5, -3, 1, -1, -61,
]

var enabled := true
var _keys: Array[AudioStreamPlayer] = []
var _triads: Array[AudioStreamPlayer] = []
var _next_key := 0
var _fades: Dictionary[AudioStreamPlayer, Tween] = {}
var _free_keys: Array[AudioStreamPlayer] = []
var _free_held: Dictionary[int, AudioStreamPlayer] = {}


func _ready() -> void:
	for index in range(KEY_VOICES + TRIAD_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		voice.volume_db = KEY_DB if index < KEY_VOICES else TRIAD_DB
		add_child(voice)
		if index < KEY_VOICES:
			_keys.append(voice)
		else:
			_triads.append(voice)


func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	enabled = value
	if not enabled:
		fade_keys(STOP_FADE_SECONDS)
		fade_triad(STOP_FADE_SECONDS)
		fade_free_notes()
	enabled_changed.emit(enabled)


func play_note(midi: int) -> void:
	if not enabled:
		return
	var voice := _keys[_next_key]
	_next_key = (_next_key + 1) % KEY_VOICES
	_prepare_voice(voice, midi, KEY_DB)
	voice.play()
	note_started.emit(midi)


func prepare_free_piano() -> void:
	if not _free_keys.is_empty():
		return
	for index in range(FREE_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(voice)
		_free_keys.append(voice)


func play_free_note(midi: int, pointer: int) -> void:
	if not enabled or midi < FREE_LOWEST or midi > FREE_HIGHEST:
		return
	prepare_free_piano()
	release_free_note(pointer)
	var voice := _take_free_voice()
	_prepare_voice(voice, midi, FREE_DB, free_sample_midi(midi))
	_free_held[pointer] = voice
	voice.play()
	note_started.emit(midi)


func release_free_note(pointer: int) -> void:
	var voice: AudioStreamPlayer = _free_held.get(pointer)
	if voice == null:
		return
	_free_held.erase(pointer)
	# The highest strings have no dampers, and keep ringing after release.
	if not voice.playing or voice.get_meta("undamped", false):
		return
	_fade_voice(voice, FREE_RELEASE_SECONDS, true, maxf(0.0, FREE_MIN_ATTACK_SECONDS - voice.get_playback_position()))


func fade_free_notes() -> void:
	_free_held.clear()
	_fade_voices(_free_keys, STOP_FADE_SECONDS)


func _take_free_voice() -> AudioStreamPlayer:
	var voice: AudioStreamPlayer
	for candidate in _free_keys:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		# The pool is ordered by age. Recycle a released note before a held one.
		for candidate in _free_keys:
			if _free_held.find_key(candidate) == null:
				voice = candidate
				break
	if voice == null:
		voice = _free_keys[0]
	var old_pointer: Variant = _free_held.find_key(voice)
	if old_pointer != null:
		_free_held.erase(old_pointer)
	_free_keys.erase(voice)
	_free_keys.append(voice)
	return voice


func fade_keys(seconds: float) -> Tween:
	return _fade_voices(_keys, seconds)


func release_keys(seconds: float) -> Tween:
	return _fade_voices(_keys, seconds, true)


func fade_triad(seconds: float) -> Tween:
	return _fade_voices(_triads, seconds)


func play_triad(midi_notes: Array[int]) -> void:
	if not enabled:
		return
	for index in range(TRIAD_VOICES):
		_prepare_voice(_triads[index], midi_notes[index], TRIAD_DB)
	# Keep the audio thread from mixing only part of the triad.
	AudioServer.lock()
	for voice in _triads:
		voice.play()
	AudioServer.unlock()
	triad_started.emit(midi_notes)


func _fade_voices(voices: Array[AudioStreamPlayer], seconds: float, damp_keys := false) -> Tween:
	var last_fade: Tween
	for voice in voices:
		if not voice.playing:
			continue
		last_fade = _fade_voice(voice, seconds, damp_keys)
	return last_fade


func _fade_voice(voice: AudioStreamPlayer, seconds: float, damp_keys: bool, delay := 0.0) -> Tween:
	_cancel_fade(voice)
	var fade := create_tween()
	_fades[voice] = fade
	if delay > 0.0:
		fade.tween_interval(delay)
	if damp_keys:
		fade.tween_method(_apply_key_release.bind(voice, voice.volume_linear), 0.0, 1.0, seconds)
	else:
		fade.tween_property(voice, "volume_linear", 0.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_callback(_stop_voice.bind(voice))
	return fade


static func key_release_gain(progress: float) -> float:
	# Ramp in the extra decay, then damp at a steady rate in dB while the sample rings.
	var ramp := minf(progress, KEY_DAMPING_RAMP_FRACTION)
	var damping := ramp * ramp / (2.0 * KEY_DAMPING_RAMP_FRACTION)
	damping += maxf(0.0, progress - KEY_DAMPING_RAMP_FRACTION)
	var attenuation_db := KEY_DAMPING_DB * damping / (1.0 - KEY_DAMPING_RAMP_FRACTION * 0.5)
	# Bring the already-quiet tail to zero before recycling the voice.
	var taper := 1.0 - smoothstep(1.0 - KEY_RELEASE_TAPER_FRACTION, 1.0, progress)
	return db_to_linear(-attenuation_db) * taper


func _apply_key_release(progress: float, voice: AudioStreamPlayer, initial_gain: float) -> void:
	voice.volume_linear = initial_gain * key_release_gain(progress)


func _stop_voice(voice: AudioStreamPlayer) -> void:
	_fades.erase(voice)
	voice.stop()


func _cancel_fade(voice: AudioStreamPlayer) -> void:
	if _fades.has(voice):
		_fades[voice].kill()
		_fades.erase(voice)


func _prepare_voice(voice: AudioStreamPlayer, midi: int, volume: float, sampled_midi := -1) -> void:
	_cancel_fade(voice)
	voice.volume_db = volume
	var cents := 0
	if sampled_midi < 0:
		sampled_midi = clampi(free_sample_midi(midi), LOWEST_SAMPLE, HIGHEST_SAMPLE)
	else:
		voice.set_meta("undamped", midi >= 89)
		cents = free_tuning_cents(sampled_midi)
	voice.stream = sample_at(sampled_midi)
	voice.pitch_scale = pow(2.0, ((midi - sampled_midi) * 100 + cents) / 1200.0)


static func free_sample_midi(midi: int) -> int:
	return clampi(roundi(midi / 3.0) * 3, FREE_LOWEST, FREE_HIGHEST)


@warning_ignore("integer_division")
static func free_tuning_cents(anchor: int) -> int:
	return FREE_TUNING_CENTS[(anchor - FREE_LOWEST) / 3]


@warning_ignore("integer_division")
static func sample_at(anchor: int) -> AudioStreamWAV:
	if anchor < LOWEST_SAMPLE:
		return BASS[(anchor - FREE_LOWEST) / 3]
	if anchor > HIGHEST_SAMPLE:
		return TREBLE[(anchor - HIGHEST_SAMPLE) / 3 - 1]
	return SAMPLES[(anchor - LOWEST_SAMPLE) / 3]
