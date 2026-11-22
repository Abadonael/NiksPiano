extends RefCounted

const Theory := preload("res://scripts/key_theory.gd")
const Comparison := preload("res://scripts/circle_comparison.gd")
const Studies := preload("res://scripts/circle_exercises.gd")
const Exercises := preload("res://scripts/melody_exercises.gd")
const Progress := preload("res://scripts/melody_progress.gd")
const Notes := preload("res://scripts/notes.gd")
const Chords := preload("res://scripts/chords.gd")
const Staff := preload("res://scripts/melody_staff.gd")
const Finish := preload("res://scripts/finish.gd")

# Expected spelling, relative tonic and signed accidental count in wheel order.
const KEYS := [
	["C D E F G A B", "A", 0],
	["G A B C D E F♯", "E", 1],
	["D E F♯ G A B C♯", "B", 2],
	["A B C♯ D E F♯ G♯", "F♯", 3],
	["E F♯ G♯ A B C♯ D♯", "C♯", 4],
	["B C♯ D♯ E F♯ G♯ A♯", "G♯", 5],
	["F♯ G♯ A♯ B C♯ D♯ E♯", "D♯", 6],
	["D♭ E♭ F G♭ A♭ B♭ C", "B♭", -5],
	["A♭ B♭ C D♭ E♭ F G", "F", -4],
	["E♭ F G A♭ B♭ C D", "C", -3],
	["B♭ C D E♭ F G A", "G", -2],
	["F G A B♭ C D E", "D", -1],
]
const G_FLAT := ["G♭ A♭ B♭ C♭ D♭ E♭ F", "E♭", -6]
const SHARPS := ["F♯", "C♯", "G♯", "D♯", "A♯", "E♯"]
const FLATS := ["B♭", "E♭", "A♭", "D♭", "G♭", "C♭"]
const CLOCKWISE := [
	["F", "F♯"], ["C", "C♯"], ["G", "G♯"], ["D", "D♯"], ["A", "A♯"], ["E", "E♯"],
	["B", "C"], ["G♭", "G"], ["D♭", "D"], ["A♭", "A"], ["E♭", "E"], ["B♭", "B"],
]
const MAJOR := [0, 2, 4, 5, 7, 9, 11]
const MINOR := [0, 2, 3, 5, 7, 8, 10]
const TRIAD_INTERVALS := [[4, 7], [3, 7], [3, 7], [4, 7], [4, 7], [3, 7], [3, 6]]
const MINOR_KEYS := [
	["A B C D E F G", "G♯", 1],
	["E F♯ G A B C D", "D♯", 1],
	["B C♯ D E F♯ G A", "A♯", 1],
	["F♯ G♯ A B C♯ D E", "E♯", 1],
	["C♯ D♯ E F♯ G♯ A B", "B♯", 1],
	["G♯ A♯ B C♯ D♯ E F♯", "F𝄪", 2],
	["D♯ E♯ F♯ G♯ A♯ B C♯", "C𝄪", 2],
	["B♭ C D♭ E♭ F G♭ A♭", "A", 0],
	["F G A♭ B♭ C D♭ E♭", "E", 0],
	["C D E♭ F G A♭ B♭", "B", 0],
	["G A B♭ C D E♭ F", "F♯", 1],
	["D E F G A B♭ C", "C♯", 1],
]
const E_FLAT_MINOR := ["E♭ F G♭ A♭ B♭ C♭ D♭", "D", 0]
const MINOR_ROMANS := ["i", "ii°", "III", "iv", "v", "VI", "VII"]
const HARMONIC_ROMANS := ["i", "ii°", "III+", "iv", "V", "VI", "vii°"]
const MINOR_TRIADS := [[3, 7], [3, 6], [4, 7], [3, 7], [3, 7], [4, 7], [4, 7]]
const HARMONIC_TRIADS := [[3, 7], [3, 6], [4, 8], [3, 7], [4, 7], [4, 7], [3, 6]]


func run(suite: SceneTree) -> void:
	suite.expect(Theory.WHEEL.size() == KEYS.size(), "twelve wheel positions")
	var key_c := Theory.major(0)
	var symbols := PackedStringArray()
	for degree in range(7):
		symbols.append(key_c.triad_name(degree))
	suite.expect(" ".join(symbols) == "C Dm Em F G Am Bdim", "major triad qualities include diminished vii")
	for slot in range(KEYS.size()):
		var key := Theory.major(slot)
		_check_key(suite, key, KEYS[slot])
		_check_minor_key(suite, slot, false, MINOR_KEYS[slot])
		if slot == 6:
			_check_key(suite, Theory.major(slot, true), G_FLAT)
			_check_minor_key(suite, slot, true, E_FLAT_MINOR)
		for flats in [false, true]:
			_check_neighbors(suite, slot, flats)
	var sharp_scale := Studies.scale(Theory.major(6))
	var flat_scale := Studies.scale(Theory.major(6, true))
	suite.expect(sharp_scale.notes[6].written_name() == "E♯5" and flat_scale.notes[3].written_name() == "C♭5",
		"enharmonic notes retain their written staff letter and octave")
	for index in range(15):
		suite.expect(sharp_scale.notes[index].midi == flat_scale.notes[index].midi, "enharmonic scales share MIDI")
	_check_minor_enharmonics(suite)
	_check_accidental_cancellation(suite)


func _check_key(suite: SceneTree, key: Theory.Tonality, fixture: Array) -> void:
	var expected := String(fixture[0]).split(" ")
	var context := expected[0] + " major"
	suite.expect(key.scale_names() == expected and key.signature == fixture[2], context + " written notes and signature count")
	var signs := SHARPS if key.signature > 0 else FLATS
	suite.expect(key.signature_names() == PackedStringArray(signs.slice(0, absi(key.signature))), context + " signature order")
	var minor := key.relative_minor()
	suite.expect(minor.minor and minor.note_name(0) == fixture[1] and minor.signature == key.signature,
		context + " relative minor")
	for degree in range(7):
		suite.expect(posmod(key.pitch_class(degree) - key.pitch_class(0), 12) == MAJOR[degree] and (
			posmod(minor.pitch_class(degree) - minor.pitch_class(0), 12) == MINOR[degree]), context + " diatonic MIDI")
		var names := PackedStringArray([expected[degree], expected[(degree + 2) % 7], expected[(degree + 4) % 7]])
		var third := posmod(key.pitch_class(degree + 2) - key.pitch_class(degree), 12)
		var fifth := posmod(key.pitch_class(degree + 4) - key.pitch_class(degree), 12)
		suite.expect(key.triad_names(degree) == names and [third, fifth] == TRIAD_INTERVALS[degree],
			context + " spelling and quality of triad %d" % degree)
	_check_scale(suite, key, expected)
	_check_progression(suite, key, expected)


func _check_scale(suite: SceneTree, key: Theory.Tonality, names: PackedStringArray) -> void:
	var exercise := Studies.scale(key)
	suite.expect(exercise.attack_count == 15 and exercise.notes.size() == 15 and exercise.key_signature == key.signature,
		"scale contains a full round trip under the chosen signature")
	var signature_steps := [8, 5, 9, 6, 3, 7] if key.signature > 0 else [4, 7, 3, 6, 2, 5]
	suite.expect(Exercises.signature_steps(exercise.key_signature, Notes.Clef.TREBLE) ==
		signature_steps.slice(0, absi(key.signature)), "staff puts key signature glyphs on correct lines")
	var progress := Progress.new()
	progress.reset(exercise)
	for index in range(15):
		var degree := mini(index, 14 - index)
		var note := exercise.notes[index]
		_check_note(suite, note, names[degree % 7])
		var offset: int = 12 if degree == 7 else MAJOR[degree]
		suite.expect(note.midi == 60 + key.pitch_class(0) + offset, "scale MIDI runs in both directions")
		suite.expect(progress.press(note.midi + 1) == Progress.Result.WRONG and progress.completed == index,
			"wrong scale pitch never advances")
		suite.expect(progress.press(note.midi) == (Progress.Result.COMPLETE if index == 14 else Progress.Result.CORRECT),
			"immediate correct scale input advances")
	suite.expect(progress.press(exercise.notes[0].midi) == Progress.Result.IGNORED, "finished scale stays finished")
	for measure in exercise.measures:
		for signs in Exercises.accidental_signs(measure, exercise.key_signature):
			suite.expect(signs == PackedInt32Array([Exercises.NO_SIGN]), "signature covers each written scale note")


func _check_progression(suite: SceneTree, key: Theory.Tonality, names: PackedStringArray) -> void:
	var scores := Studies.progression(key)
	suite.expect(scores.size() == 4, "four chords in a progression")
	var degrees := [0, 3, 4, 0]
	for slot in range(degrees.size()):
		var degree: int = degrees[slot]
		var score := scores[slot]
		suite.expect(score.key_name == key.note_name(0) and score.key_signature == key.signature and
			score.chord_symbol == names[degree], "progression retains key, signature and Roman function")
		suite.expect(Exercises.accidental_signs(score.measures[0], key.signature)[0] ==
			PackedInt32Array([Exercises.NO_SIGN, Exercises.NO_SIGN, Exercises.NO_SIGN]), "signature covers all chord tones")
		var offsets := [0, 4, 7]
		for tone in range(3):
			var note := score.notes[tone]
			_check_note(suite, note, names[(degree + tone * 2) % 7])
			suite.expect(note.midi == 60 + key.pitch_class(degree) + offsets[tone], "playable root-position major triad")


func _check_note(suite: SceneTree, note: Exercises.SpelledNote, expected: String) -> void:
	suite.expect(note.midi >= 60 and note.midi <= 83, "written pitch is on the C4–B5 keyboard")
	suite.expect(note.written_name() == expected + str(note.octave), "written note matches expected scale letter")
	suite.expect(note.midi == (note.octave + 1) * 12 + Chords.WHITE_PITCHES[note.letter] + note.accidental,
		"written note agrees with MIDI even across written octave boundaries")


func _check_neighbors(suite: SceneTree, slot: int, flats: bool) -> void:
	var forward := Comparison.new(slot, 1, flats)
	var next := posmod(slot + 1, KEYS.size())
	var back := Comparison.new(next, -1, flats)
	var source := Theory.major(slot, flats)
	suite.expect(posmod(forward.target.pitch_class(0) - source.pitch_class(0), 12) == 7 and
		back.target.note_name(0) == source.note_name(0), "wheel moves a perfect fifth in either direction")
	var expected: Array = CLOCKWISE[slot]
	if flats and slot == 5:
		expected = ["E", "F"]
	elif flats and slot == 6:
		expected = ["C♭", "C"]
	suite.expect(forward.common == 6 and back.common == 6 and [forward.removed, forward.added] == expected
		and [back.added, back.removed] == expected, "comparison matches six sounding pitch classes and one written change")
	if source.signature * forward.target.signature < 0:
		suite.expect(forward.signature_change.begins_with("Смена записи") and back.signature_change.begins_with("Смена записи"),
			"enharmonic branch crossing displays both written signatures")
	if slot == 0:
		suite.expect(forward.signature_change.ends_with("F♯") and back.signature_change.begins_with("Убран"),
			"C and G add and remove F sharp")
	if slot == 11:
		suite.expect(back.signature_change == "Новый ключевой знак: B♭", "C to F adds B flat")


func _check_minor_key(suite: SceneTree, slot: int, flats: bool, fixture: Array) -> void:
	var key := Theory.at_sector(slot, flats, true)
	var major := Theory.major(slot, flats)
	var natural_names := String(fixture[0]).split(" ")
	var harmonic_names := natural_names.duplicate()
	harmonic_names[6] = fixture[1]
	suite.expect(key.minor and key.relative_major().name() == major.name() and
		key.signature_names() == major.signature_names() and key.note_name(0) == natural_names[0],
		key.name() + " tonic and relative major signature")
	var relative := Comparison.new(slot, 0, flats, true)
	suite.expect(relative.target.name() == major.name() and relative.common == 7 and
		relative.removed.is_empty() and relative.added.is_empty(), key.name() + " shares all seven pitches with relative major")
	for direction in [-1, 1]:
		var neighbor := Comparison.new(slot, direction, flats, true)
		var major_neighbor := Comparison.new(slot, direction, flats)
		suite.expect(neighbor.common == 6 and neighbor.target.minor and neighbor.removed == major_neighbor.removed and
			neighbor.added == major_neighbor.added and neighbor.signature_change == major_neighbor.signature_change,
			key.name() + " adjacent natural-minor comparison")
	for form in [Theory.ScaleForm.NATURAL, Theory.ScaleForm.HARMONIC]:
		var harmonic: bool = form == Theory.ScaleForm.HARMONIC
		var names := harmonic_names if harmonic else natural_names
		var romans := HARMONIC_ROMANS if harmonic else MINOR_ROMANS
		var intervals := HARMONIC_TRIADS if harmonic else MINOR_TRIADS
		suite.expect(key.scale_names(form) == names, key.name() + " spells each scale degree")
		var exercise := Studies.scale(key, form)
		suite.expect(exercise.key_signature == major.signature and exercise.notes.size() == 15, "minor score retains key signature")
		for index in range(15):
			var degree := mini(index, 14 - index)
			var offset: int = 12 if degree == 7 else MINOR[degree]
			_check_note(suite, exercise.notes[index], names[degree % 7])
			suite.expect(exercise.notes[index].midi == 60 + key.pitch_class(0) + offset + int(harmonic and degree == 6),
				"minor form changes only degree seven in both directions")
		for measure in exercise.measures:
			var signs := Exercises.accidental_signs(measure, key.signature)
			for index in range(measure.events.size()):
				var attack := measure.events[index].attack
				var expected: int = fixture[2] if harmonic and attack in [6, 8] else Exercises.NO_SIGN
				suite.expect(signs[index] == PackedInt32Array([expected]), "minor accidental in the correct measure and octave")
		for degree in range(7):
			var expected := PackedStringArray([names[degree], names[(degree + 2) % 7], names[(degree + 4) % 7]])
			var root := key.pitch_class(degree, form)
			var third := posmod(key.pitch_class(degree + 2, form) - root, 12)
			var fifth := posmod(key.pitch_class(degree + 4, form) - root, 12)
			var suffix: String = {[3, 7]: "m", [3, 6]: "dim", [4, 7]: "", [4, 8]: "aug"}[intervals[degree]]
			suite.expect(key.triad_names(degree, form) == expected and key.triad_roman(degree, form) == romans[degree]
				and [third, fifth] == intervals[degree] and key.triad_name(degree, form) == names[degree] + suffix,
				"all seven minor triads have their correct pitches, qualities, and Roman numerals")
	_check_minor_cadence(suite, key, harmonic_names, fixture[2])


func _check_minor_cadence(suite: SceneTree, key: Theory.Tonality, names: PackedStringArray, raised_sign: int) -> void:
	var scores := Studies.progression(key)
	suite.expect(scores.size() == 4, "minor cadence has four chords")
	var degrees := [0, 3, 4, 0]
	for index in range(degrees.size()):
		var score := scores[index]
		var degree: int = degrees[index]
		var dominant := index == 2
		suite.expect(score.key_signature == key.signature and score.chord_symbol == names[degree] + ("" if dominant else "m"),
			"minor progression is i–iv–V–i")
		var third := 4 if dominant else 3
		var root := 60 + key.pitch_class(degree)
		var audio := Chords.Triad.new(score.chord_symbol, key.pitch_class(degree))
		for tone in range(3):
			var note := score.notes[tone]
			_check_note(suite, note, names[(degree + tone * 2) % 7])
			suite.expect(note.midi == root + [0, third, 7][tone] and note.midi == audio.root_position(60)[tone],
				"accepted and replayed chord uses the same written root position")
		var signs := Exercises.accidental_signs(score.measures[0], key.signature)[0]
		suite.expect(signs == PackedInt32Array([Exercises.NO_SIGN, raised_sign if dominant else Exercises.NO_SIGN, Exercises.NO_SIGN]),
			"only the minor dominant's written third needs an accidental")
		if dominant:
			suite.expect(posmod(key.pitch_class(0) - score.notes[1].midi, 12) == 1, "dominant third leads to the tonic")


func _check_minor_enharmonics(suite: SceneTree) -> void:
	var sharp := Theory.at_sector(6, false, true)
	var flat := Theory.at_sector(6, true, true)
	for form in [Theory.ScaleForm.NATURAL, Theory.ScaleForm.HARMONIC]:
		var sharp_scale := Studies.scale(sharp, form)
		var flat_scale := Studies.scale(flat, form)
		for index in range(15):
			suite.expect(sharp_scale.notes[index].midi == flat_scale.notes[index].midi, "enharmonic minor scales keep all MIDI pitches")
	var sharp_cadence := Studies.progression(sharp)
	var flat_cadence := Studies.progression(flat)
	for index in range(4):
		for tone in range(3):
			suite.expect(sharp_cadence[index].notes[tone].midi == flat_cadence[index].notes[tone].midi,
				"enharmonic minor cadences keep all MIDI pitches")
	suite.expect(sharp_cadence[2].notes[1].written_name() == "C𝄪5" and flat_cadence[2].notes[1].written_name() == "D5",
		"enharmonic dominants keep distinct written scales and octave")
	for pair in [[2, 0xE263], [1, 0xE262], [0, 0xE261]]:
		var glyph := Staff._accidental(pair[0])
		suite.expect(glyph.unicode_at(0) == pair[1] and Finish.MUSIC_FONT.has_char(pair[1]),
			"Bravura has the correct SMuFL glyph for accidental %d" % pair[0])


func _check_accidental_cancellation(suite: SceneTree) -> void:
	var measure := Exercises.Measure.new()
	for midi in [62, 62, 74, 61, 60]:
		measure.events.append(Exercises.Event.new(1, [Exercises.SpelledNote.new(midi, 0)], 0))
	var signs := Exercises.accidental_signs(measure, 6)
	var none := Exercises.NO_SIGN
	suite.expect(signs == [PackedInt32Array([2]), PackedInt32Array([none]), PackedInt32Array([2]),
		PackedInt32Array([1]), PackedInt32Array([0])],
		"double sharps carry within their own octave, cancel to sharp, then cancel to natural")
	var next := Exercises.Measure.new()
	next.events.append(Exercises.Event.new(1, [Exercises.SpelledNote.new(61, 0)], 0))
	suite.expect(Exercises.accidental_signs(next, 6) == [PackedInt32Array([none])],
		"barline restores the signature after a chromatic accidental")
