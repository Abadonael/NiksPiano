extends RefCounted

const PianoAudio := preload("res://scripts/piano_audio.gd")
const AUDIBLE := 0.00001
const MIX_BLOCK := PianoAudio.MIX_BLOCK_FRAMES
const KEYS_TRACK := 1
const FINAL_KEY_TRACK := 2
const REFERENCE_TRACK := 3
const FIRST_TRIAD_TRACK := 4
const ENVELOPE_STEP := 0.010
const ATTACK_CHECK_SECONDS := 0.21
const RELEASE_CHECK_SECONDS := 0.008
const MAX_EDGE_STEP_DBFS := -60.0

var _captures: Array[AudioEffectCapture] = []
var _rate: float
var _lost_frames := false
var _final_key: AudioStreamPlayer
var _reference: AudioStreamPlayer


func attach(audio: PianoAudio) -> void:
	_rate = AudioServer.get_mix_rate()
	_add_capture(0)
	var keys_bus := _add_test_bus("SmokeKeys")
	for voice in audio._keys:
		voice.bus = keys_bus
	# The burst fills the pool once. Route its last key through an isolated tap.
	_final_key = audio._keys[posmod(audio._next_key - 1, PianoAudio.KEY_VOICES)]
	_final_key.bus = _add_test_bus("SmokeFinalKey")
	AudioServer.set_bus_send(AudioServer.get_bus_index(_final_key.bus), keys_bus)
	_reference = AudioStreamPlayer.new()
	_reference.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_reference.bus = _add_test_bus("SmokeReference")
	# Capture the dry sample before muting the reference bus's send to Master.
	AudioServer.set_bus_mute(AudioServer.get_bus_index(_reference.bus), true)
	audio.add_child(_reference)
	for index in range(audio._triads.size()):
		audio._triads[index].bus = _add_test_bus("SmokeTriad%s" % index)


func clear() -> void:
	AudioServer.lock()
	for capture in _captures:
		capture.clear_buffer()
	AudioServer.unlock()


func play_reference() -> void:
	_reference.stream = _final_key.stream
	_reference.pitch_scale = _final_key.pitch_scale
	_reference.volume_db = PianoAudio.KEY_DB
	_reference.play()


func take(audio: PianoAudio) -> Array[PackedVector2Array]:
	var tracks: Array[PackedVector2Array] = []
	AudioServer.lock()
	for capture in _captures:
		tracks.append(capture.get_buffer(capture.get_frames_available()))
		_lost_frames = _lost_frames or capture.get_discarded_frames() > 0
	AudioServer.unlock()
	_reference.free()
	for voice in audio._keys + audio._triads:
		voice.bus = &"Master"
	for index in range(_captures.size() - 1):
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	var speaker_pairs := int(AudioServer.get_speaker_mode()) + 1
	if speaker_pairs > 1:
		for index in range(tracks.size()):
			tracks[index] = _front_pair(tracks[index], speaker_pairs)
	return tracks


func verify(tracks: Array[PackedVector2Array], wav_path: String) -> PackedStringArray:
	var problems := _validate_capture(tracks)
	if not problems.is_empty():
		return problems
	var mix := tracks[0]
	var keys := tracks[KEYS_TRACK]
	var first_key := _first_sound(keys, 0)
	var last_key := _last_sound(keys, keys.size() - 1, 0.0)
	var starts: Array[int] = []
	var ends: Array[int] = []
	for index in range(FIRST_TRIAD_TRACK, tracks.size()):
		starts.append(_first_sound(tracks[index], 0))
		ends.append(_last_sound(tracks[index], tracks[index].size() - 1))
	if first_key < 0 or starts.has(-1):
		return ["mix capture did not contain every key and triad track"]

	var first_triad: int = starts.min()
	var attack_spread := (int(starts.max()) - first_triad) / _rate
	var key_duration := (last_key - first_key) / _rate
	var triad_start := (first_triad - first_key) / _rate
	var listening := (float(ends.max()) - first_triad) / _rate
	var split := (last_key + first_triad) >> 1
	var key_end_in_mix := _last_sound(mix, split, 0.0)
	var triad_start_in_mix := _first_sound(mix, split, 0.0)
	var triad_end_in_mix := _last_sound(mix, mix.size() - 1, 0.0)
	var quiet_frames := triad_start_in_mix - key_end_in_mix - 1
	var gap := quiet_frames / _rate
	var peak := _peak(mix)
	var triad_peak := _peak(mix.slice(split))
	if key_duration < 0.55 or key_duration > 0.68:
		problems.append("mixed key audio should cover the 260 ms hold and 350 ms release")
	if triad_start < 0.94 or triad_start > 1.05:
		problems.append("the triad should be audible near 960 ms, allowing for mix blocks")
	if last_key >= first_triad:
		problems.append("residual key audio overlaps the demonstration")
	if quiet_frames < ceili(_rate * 0.35) or gap > 0.43:
		problems.append("the mix should contain at least 350 ms of consecutive digital zeros")
	if attack_spread > 0.003:
		problems.append("all three triad attacks should occur in the same mix block")
	if listening < 1.17 or listening > 1.33:
		problems.append("mixed demonstration should last about 1.25 seconds")
	if peak <= 0.05 or peak > db_to_linear(-0.95):
		problems.append("mixed output should peak at or below approximately -1 dBFS")
	if triad_peak <= 0.03 or triad_peak > db_to_linear(-0.95):
		problems.append("completed chord mix should be audible without clipping")
	if _peak(mix.slice(-roundi(_rate * 0.10))) != 0.0:
		problems.append("the master mix should be digitally silent after muted input")
	if _save_wav(mix, wav_path) != OK:
		problems.append("could not save captured mixed waveform")
	problems.append_array(_verify_key_envelope(tracks[FINAL_KEY_TRACK], tracks[REFERENCE_TRACK]))
	if key_end_in_mix >= 0 and triad_start_in_mix > 0 and triad_end_in_mix > triad_start_in_mix:
		var key_release_step := _peak_step_near(mix, key_end_in_mix)
		var triad_attack_step := _level(mix[triad_start_in_mix] - mix[triad_start_in_mix - 1])
		var triad_release_step := _peak_step_near(mix, triad_end_in_mix)
		if maxf(key_release_step, maxf(triad_attack_step, triad_release_step)) > db_to_linear(MAX_EDGE_STEP_DBFS):
			problems.append("abrupt sample step near the key release, triad onset, or triad release")
		print("Edge steps: %.1f dBFS maximum near key release, %.1f dBFS at triad onset, "
			% [linear_to_db(key_release_step), linear_to_db(triad_attack_step)]
			+ "%.1f dBFS maximum near triad release." % linear_to_db(triad_release_step))
	print("Mixed audio (%s, %s Hz): keys %.1f ms, digital gap %.1f ms, triad onset %.1f ms, "
		% [AudioServer.get_driver_name(), _rate, key_duration * 1000, gap * 1000, triad_start * 1000]
		+ "attack spread %.2f ms, listening %.1f ms, peaks %.2f dBFS overall / %.2f dBFS triad"
		% [attack_spread * 1000, listening * 1000, linear_to_db(peak), linear_to_db(triad_peak)])
	return problems


func verify_canceled(tracks: Array[PackedVector2Array]) -> PackedStringArray:
	var problems := _validate_capture(tracks)
	if not problems.is_empty():
		return problems
	var mix := tracks[0]
	var first := _first_sound(mix, 0)
	var last := _last_sound(mix, mix.size() - 1, 0.0)
	if first < 0 or last <= first or last - first > roundi(_rate * 0.46):
		problems.append("muting during the fade should cut the key tail and leave the mix silent")
	for index in range(FIRST_TRIAD_TRACK, tracks.size()):
		if _peak(tracks[index]) != 0.0:
			problems.append("unmuting must not revive a canceled triad voice")
	print("Canceled mix: %.1f ms of key audio before digital silence; captured %.2f s."
		% [(last - first) * 1000.0 / _rate, mix.size() / _rate])
	return problems


func _validate_capture(tracks: Array[PackedVector2Array]) -> PackedStringArray:
	var total := tracks[0].size()
	for track in tracks:
		if _lost_frames or track.size() != total or total < _rate * 2.4:
			return ["mix capture is incomplete or its buses are out of sync: %s frames, lost=%s, %s at %s Hz"
				% [tracks.map(func(data: PackedVector2Array) -> int: return data.size()),
					_lost_frames, AudioServer.get_driver_name(), _rate]]
	return []


func _verify_key_envelope(key: PackedVector2Array, dry: PackedVector2Array) -> PackedStringArray:
	var key_start := _first_sound(key, 0)
	var dry_start := _first_sound(dry, 0)
	if key_start < 0 or dry_start < 0:
		return ["missing the isolated final key or its dry reference"]
	# Project onto the same unattenuated sample to remove the piano's natural decay.
	var gains := PackedFloat32Array()
	var frames_per_step := roundi(_rate * ENVELOPE_STEP)
	for window in range(70):
		var numerator := 0.0
		var energy := 0.0
		for offset in range(window * frames_per_step, (window + 1) * frames_per_step):
			var reference := dry[dry_start + offset]
			numerator += key[key_start + offset].dot(reference)
			energy += reference.length_squared()
		gains.append(numerator / energy)
	# Both crossings lie in the steady damping section, away from the engagement and taper.
	var early := _crossing(gains, db_to_linear(-8.0))
	var late := _crossing(gains, db_to_linear(-22.0))
	if early < 0.0 or late <= early:
		return ["the captured final key never passed through the expected fade levels"]
	var ramp_offset := PianoAudio.KEY_DAMPING_RAMP_FRACTION * 0.5
	var progress_per_db := (1.0 - ramp_offset) / PianoAudio.KEY_DAMPING_DB
	var release := (late - early) / (14.0 * progress_per_db)
	var hold := early - release * (ramp_offset + 8.0 * progress_per_db)
	var max_error := 0.0
	var attack_error := 0.0
	var max_gain_rise := 0.0
	for index in range(gains.size()):
		var time := (index + 0.5) * ENVELOPE_STEP
		if time < ATTACK_CHECK_SECONDS:
			attack_error = maxf(attack_error, absf(gains[index] - 1.0))
		var along := clampf((time - hold) / release, 0.0, 1.0)
		max_error = maxf(max_error, absf(gains[index] - PianoAudio.key_release_gain(along)))
		if index > 0 and time >= hold:
			max_gain_rise = maxf(max_gain_rise, gains[index] - gains[index - 1])
	var taper_time := hold + release * (1.0 - PianoAudio.KEY_RELEASE_TAPER_FRACTION)
	var taper_index := clampi(roundi(taper_time / ENVELOPE_STEP - 0.5), 0, gains.size() - 1)
	var taper_db := linear_to_db(maxf(gains[taper_index], 0.0))
	print("Captured key envelope: %.1f ms hold, %.1f ms release, %.1f dB gain at the final taper, "
		% [hold * 1000.0, release * 1000.0, taper_db]
		+ "%.1f%% maximum gain deviation, %.1f%% attack deviation."
		% [max_error * 100.0, attack_error * 100.0])
	if attack_error > 0.04:
		return ["the final key attack should match the unattenuated sample"]
	if hold < 0.22 or hold > 0.30 or release < 0.30 or release > 0.405 or max_error > 0.12:
		return ["mixed key gain should follow the damped release after the 260 ms hold"]
	if max_gain_rise > 0.03 or taper_db > -20.0:
		return ["the release should decay without a gain rebound and taper only when already quiet"]
	return []


static func _crossing(gains: PackedFloat32Array, level: float) -> float:
	for index in range(1, gains.size()):
		if gains[index] < level and gains[index - 1] >= level:
			return (index - 0.5 + inverse_lerp(gains[index - 1], gains[index], level)) * ENVELOPE_STEP
	return -1.0


func _add_capture(index: int) -> void:
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 10.0
	AudioServer.add_bus_effect(index, capture)
	_captures.append(capture)


func _add_test_bus(id: StringName) -> StringName:
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, id)
	_add_capture(index)
	return id


static func _first_sound(frames: PackedVector2Array, start: int, threshold := AUDIBLE) -> int:
	for index in range(start, frames.size()):
		if _level(frames[index]) > threshold:
			return index
	return -1


static func _front_pair(frames: PackedVector2Array, pairs: int) -> PackedVector2Array:
	var front := PackedVector2Array()
	var stride := MIX_BLOCK * pairs
	if frames.size() % stride != 0:
		return front
	for offset in range(0, frames.size(), stride):
		front.append_array(frames.slice(offset, offset + MIX_BLOCK))
	return front


static func _last_sound(frames: PackedVector2Array, start: int, threshold := AUDIBLE) -> int:
	for index in range(start, -1, -1):
		if _level(frames[index]) > threshold:
			return index
	return -1


static func _peak(frames: PackedVector2Array) -> float:
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, _level(frame))
	return peak


func _peak_step_near(frames: PackedVector2Array, boundary: int) -> float:
	var radius := roundi(_rate * RELEASE_CHECK_SECONDS)
	var step := 0.0
	for index in range(maxi(1, boundary - radius), mini(frames.size(), boundary + radius + 1)):
		step = maxf(step, _level(frames[index] - frames[index - 1]))
	return step


static func _level(frame: Vector2) -> float:
	return maxf(absf(frame.x), absf(frame.y))


func _save_wav(frames: PackedVector2Array, path: String) -> Error:
	var pcm := PackedByteArray()
	pcm.resize(frames.size() * 4)
	for index in range(frames.size()):
		pcm.encode_s16(index * 4, roundi(clampf(frames[index].x, -1.0, 1.0) * 32767.0))
		pcm.encode_s16(index * 4 + 2, roundi(clampf(frames[index].y, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.mix_rate = int(_rate)
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.data = pcm
	return wav.save_to_wav(path)
