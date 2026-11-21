extends RefCounted

const Exercises := preload("res://scripts/melody_exercises.gd")
const Notes := preload("res://scripts/notes.gd")
const Chords := preload("res://scripts/chords.gd")
const TRIALS := 160
const SIGNATURES := {"C major": 0, "A minor": 0, "G major": 1, "F major": -1, "E minor": 1,
	"D minor": -1, "D major": 2, "Bb major": -2, "B minor": 2, "G minor": -2}
const INTERVAL_NAMES := [
	["Малая терция", "Большая терция", "Чистая кварта", "Чистая квинта", "Малая терция", "Чистая квинта"],
	["Малая секунда", "Малая секунда", "Малая терция", "Чистая кварта", "Чистая квинта",
		"Большая секста", "Большая секста", "Чистая октава", "Большая секунда", "Большая терция", "Малая секста"],
	["Увеличенная кварта", "Уменьшённая квинта", "Уменьшённая кварта", "Уменьшённая квинта", "Уменьшённая квинта",
		"Малая септима", "Малая септима", "Малая септима", "Большая септима", "Большая септима"],
]
const CLEF_BOTTOM := [30, 18]


func run(suite: SceneTree) -> void:
	seed(50112)
	_check_written_music(suite)
	var total := 0
	var generator := Exercises.new()
	for clef: Notes.Clef in Notes.Clef.values():
		for level: Exercises.Difficulty in Exercises.Difficulty.values():
			for kind: Exercises.Kind in Exercises.Kind.values():
				var lengths := [4] if kind == Exercises.Kind.INTERVAL else Exercises.LENGTHS
				for length: int in lengths:
					var catalog: Dictionary[String, bool] = {}
					var shapes: Dictionary[String, bool] = {}
					var previous: Exercises.Exercise
					for trial in range(TRIALS):
						var exercise := generator.next(kind, level, length, clef)
						if exercise == null:
							suite.expect(false, "generator must return an exercise")
							return
						var sample := "%s, %s, %s, %s, trial %d" % [kind, level, length, clef, trial]
						suite.expect(exercise.clef == clef and exercise.difficulty == level and exercise.kind == kind,
							"requested configuration is preserved " + sample)
						suite.expect(Exercises.is_valid(exercise), "structural validation " + sample)
						_check_measures(suite, exercise, length, sample)
						match kind:
							Exercises.Kind.PHRASE:
								var key := _check_phrase(suite, exercise, sample)
								if previous != null:
									suite.expect(exercise.key_name != previous.key_name or exercise.natural_minor != previous.natural_minor
										or exercise.template_id != previous.template_id, "phrases rotate")
								catalog[key] = true
							Exercises.Kind.ARPEGGIO:
								_check_arpeggio(suite, exercise, sample)
								catalog[exercise.chord_symbol] = true
							Exercises.Kind.INTERVAL:
								_check_interval(suite, exercise, sample)
								if previous != null:
									suite.expect(exercise.template_id != previous.template_id, "intervals rotate")
								catalog[exercise.interval_name] = true
						shapes[exercise.template_id] = true
						previous = exercise
						total += 1
					var counts := [[6, 8, 24], [2, 4, 4], [4, 9, 5]]
					suite.expect(catalog.size() == counts[kind][level] and shapes.size() >= 3,
						"every intended key, chord or interval quality appears at this length and clef")
	print("Melodies music theory: %d seeded exercises across all kinds, difficulties, clefs and applicable lengths." % total)


func _check_measures(suite: SceneTree, exercise: Exercises.Exercise, length: int, sample: String) -> void:
	var interval := exercise.kind == Exercises.Kind.INTERVAL
	var attacks := 0
	var first := 60 if exercise.clef == Notes.Clef.TREBLE else 36
	for measure in exercise.measures:
		var beats := 0
		var signs := Exercises.accidental_signs(measure, exercise.key_signature)
		var effective: Dictionary[int, int] = {}
		for slot in range(measure.events.size()):
			var event := measure.events[slot]
			beats += event.duration
			if event.pitches.is_empty():
				suite.expect(event.attack == -1 and event.duration in [2, 4], "rests have duration and no attack " + sample)
				continue
			suite.expect(event.attack == attacks, "attack order ignores rests " + sample)
			attacks += 1
			for voice in range(event.pitches.size()):
				var pitch := event.pitches[voice]
				var position := pitch.octave * 7 + pitch.letter
				var sig_letters: Array = [3, 0] if exercise.key_signature > 0 else [6, 2]
				var implied := signi(exercise.key_signature) if pitch.letter in sig_letters.slice(0, absi(exercise.key_signature)) else 0
				var sign: int = signs[slot][voice]
				var before: int = effective.get(position, implied)
				suite.expect((sign == Exercises.NO_SIGN and before == pitch.accidental)
					or (sign == pitch.accidental and before != sign), "written accidental reconstructs pitch " + sample)
				effective[position] = pitch.accidental
				suite.expect(pitch.staff_step(exercise.clef) == position - int(CLEF_BOTTOM[exercise.clef])
					and pitch.midi == (pitch.octave + 1) * 12 + int(Chords.WHITE_PITCHES[pitch.letter]) + pitch.accidental
					and pitch.midi in range(first, first + 24), "written pitches match staff and keyboard " + sample)
		suite.expect(beats == 8, "each measure sums to four beats " + sample)
	suite.expect(exercise.time_signature == Vector2i(4, 4) and attacks == (1 if interval else length)
		and exercise.measures.size() == (1 if interval else length / 4.0)
		and exercise.notes.size() == (2 if interval else length), "selected length gives total notes and bars " + sample)


func _check_phrase(suite: SceneTree, exercise: Exercises.Exercise, sample: String) -> String:
	var key := "%s %s" % [exercise.key_name, "minor" if exercise.natural_minor else "major"]
	suite.expect(SIGNATURES.get(key, 99) == exercise.key_signature, "key signature fits tonic and mode " + sample)
	var tonic: int = Chords._root_pitch(exercise.key_name)
	var scale := [0, 2, 3, 5, 7, 8, 10] if exercise.natural_minor else [0, 2, 4, 5, 7, 9, 11]
	var pitches: Array[int] = []
	var widest := 0
	for note in exercise.notes:
		suite.expect(posmod(note.midi - tonic, 12) in scale, "melody stays in its diatonic scale " + sample)
		if not pitches.is_empty():
			widest = maxi(widest, absi(note.midi - pitches.back()))
		pitches.append(note.midi)
	var ambitus := int(pitches.max()) - int(pitches.min())
	var ending := posmod(pitches.back() - tonic, 12)
	var level := exercise.difficulty
	suite.expect(widest <= [4, 7, 12][level] and ambitus <= [7, 12, 19][level],
		"length does not raise interval or range limits " + sample)
	suite.expect(level != Exercises.Difficulty.ADVANCED or widest >= 7, "short advanced phrases still contain larger leaps " + sample)
	suite.expect(ending == 0 or (exercise.selected_length == 4 and ending == scale[2]), "phrase has a tonal end " + sample)
	return key


func _check_arpeggio(suite: SceneTree, exercise: Exercises.Exercise, sample: String) -> void:
	var chord := Chords.Triad.new(exercise.chord_symbol, Chords._root_pitch(exercise.chord_symbol))
	var root_letter := Notes.LETTERS.find(chord.symbol[0])
	var black := 0
	for pitch in chord.pitches:
		black += int(pitch in Chords.BLACK_PITCHES)
	for note in exercise.notes:
		var tone := chord.pitches.find(note.midi % 12)
		suite.expect(tone != -1 and note.letter == (root_letter + 2 * tone) % 7, "chord spelling and membership " + sample)
	suite.expect(black == exercise.difficulty or exercise.difficulty == Exercises.Difficulty.ADVANCED,
		"beginner and intermediate black-key budgets are independent of length " + sample)
	if exercise.difficulty == Exercises.Difficulty.BEGINNER:
		var lowest := 127
		var highest := 0
		for note in exercise.notes:
			lowest = mini(lowest, note.midi)
			highest = maxi(highest, note.midi)
		suite.expect(lowest % 12 == chord.root and highest - lowest == 7, "beginner arpeggio uses one root-position triad " + sample)


func _check_interval(suite: SceneTree, exercise: Exercises.Exercise, sample: String) -> void:
	var black := 0
	for note in exercise.notes:
		black += int(note.midi % 12 in Chords.BLACK_PITCHES)
	var index := exercise.template_id.get_slice("-", 2).to_int() - 1
	suite.expect(exercise.interval_name == INTERVAL_NAMES[exercise.difficulty][index] and black <= exercise.difficulty
		and exercise.notes[0].midi < exercise.notes[1].midi, "interval size, spelling and black-key budget " + sample)


func _check_written_music(suite: SceneTree) -> void:
	var exercise := Exercises.Exercise.new(Exercises.Kind.PHRASE, Exercises.Difficulty.INTERMEDIATE, 8, Notes.Clef.TREBLE)
	var first := Exercises.Measure.new()
	var second := Exercises.Measure.new()
	exercise.measures.assign([first, second])
	# F sharp from the signature, F natural, repeated F natural, and
	# the other octave (still sharp), followed by restoration and reset.
	for midi in [66, 65, 65, 78]:
		exercise.add_event(first, Exercises.QUARTER, [Exercises.SpelledNote.new(midi, 3)])
	for midi in [66, 65, 66, 66]:
		exercise.add_event(second, Exercises.QUARTER, [Exercises.SpelledNote.new(midi, 3)])
	suite.expect(Exercises.accidental_signs(first, 1) == _signs([2, 0, 2, 2]), "natural scope and key signature spans octaves")
	suite.expect(Exercises.accidental_signs(second, 1) == _signs([2, 0, 1, 2]), "bar reset and sharp reassertion")
	suite.expect(Exercises.accidental_signs(second, 0) == _signs([1, 0, 1, 2]), "standalone sharp resets at bar line")
	for clef: Notes.Clef in Notes.Clef.values():
		var treble := clef == Notes.Clef.TREBLE
		suite.expect(Exercises.signature_steps(2, clef) == ([8, 5] if treble else [6, 3]), "F and C sharp placement")
		suite.expect(Exercises.signature_steps(-2, clef) == ([4, 7] if treble else [2, 5]), "B and E flat placement")
	suite.expect(Notes.ledger_steps(Notes.diatonic_step(2, 0, Notes.Clef.BASS)) == [-2, -4]
		and Notes.ledger_steps(Notes.diatonic_step(3, 6, Notes.Clef.BASS)).is_empty()
		and Notes.ledger_steps(Notes.diatonic_step(4, 0, Notes.Clef.BASS)) == [10], "bass ledger lines around the keyboard boundaries")
	var c := Exercises.SpelledNote.new(60, 0)
	suite.expect(Exercises.name_interval(c, Exercises.SpelledNote.new(66, 3)) == "Увеличенная кварта"
		and Exercises.name_interval(c, Exercises.SpelledNote.new(66, 4)) == "Уменьшённая квинта",
		"equal-sized tritones have different interval names")
	var underfull := Exercises.new().next(Exercises.Kind.PHRASE, Exercises.Difficulty.BEGINNER)
	underfull.measures[0].events[3].duration = Exercises.QUARTER
	suite.expect(not Exercises.is_valid(underfull), "measure validation rejects an otherwise valid underfull phrase")


static func _signs(values: Array) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for value: int in values:
		result.append(PackedInt32Array([value]))
	return result
