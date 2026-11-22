extends RefCounted

const Chords := preload("res://scripts/chords.gd")
const ChordBag := preload("res://scripts/chord_bag.gd")
const Notes := preload("res://scripts/notes.gd")
const Theory := preload("res://scripts/key_theory.gd")

enum Kind { ARPEGGIO, PHRASE, INTERVAL }
enum Study { MELODY, SCALE, TRIAD }
enum Difficulty { BEGINNER, INTERMEDIATE, ADVANCED }

const LENGTHS := [4, 8, 12, 16, 24]
const DEFAULT_LENGTH := 4
const FIRST_MIDI := 60
const BASS_FIRST_MIDI := 36
const KEYBOARD_SIZE := 24

# Durations are measured in eighth-note units. Each template fills one 4/4 bar.
const EIGHTH := 1
const QUARTER := 2
const HALF := 4
const WHOLE := 8
const TIME_SIGNATURE := Vector2i(4, 4)
const NO_SIGN := 3
# Each phrase choice identifies a wheel sector and whether to use its relative minor.
const KEYS := [
	[[0, false], [0, true]],
	[[1, false], [11, false], [1, true], [11, true]],
	[[2, false], [10, false], [2, true], [10, true]],
]

# Each row has a four-attack miniature, five optional development bars, and a
# closing bar. Longer forms use the opening, as many development bars as fit,
# and the common cadence. Degrees are relative to the tonic, including lower
# neighbors (negative degrees) and octave doublings.
const PHRASES := [
	[
		[[0, 1, 2, 0], [0, 1, 2, 3], [4, 3, 2, 1], [2, 1, 2, 3], [4, 2, 3, 2], [3, 4, 3, 2], [2, 3, 1, 0]],
		[[2, 3, 1, 0], [2, 3, 4, 2], [3, 2, 1, 0], [1, 2, 1, 2], [3, 2, 4, 3], [4, 3, 2, 3], [2, 1, 1, 0]],
		[[4, 2, 1, 0], [4, 3, 2, 0], [1, 2, 3, 2], [4, 3, 4, 2], [3, 2, 1, 2], [4, 3, 2, 1], [2, 2, 1, 0]],
	],
	[
		[[0, 4, 2, 0], [0, 2, 3, 4], [5, 4, 2, 3], [4, 6, 7, 6], [5, 3, 4, 3], [2, 4, 3, 2], [4, 2, 1, 0]],
		[[4, 1, 2, 0], [4, 3, 2, 1], [0, 2, 4, 2], [3, 5, 4, 3], [4, 6, 7, 5], [4, 3, 2, 1], [2, 3, 1, 0]],
		[[2, 5, 4, 2], [2, 3, 4, 6], [7, 5, 6, 4], [3, 1, 2, 4], [5, 4, 5, 3], [2, 1, 0, 2], [3, 2, 1, 0]],
	],
	[
		[[2, 7, 6, 7], [0, 4, 2, 7], [6, 4, 5, 3], [4, 7, 9, 7], [8, 6, 7, 4], [2, 4, 3, 2], [5, 4, 1, 0]],
		[[0, 7, 4, 0], [0, 7, 6, 4], [2, 4, 3, 1], [-1, 1, 0, 2], [5, 7, 6, 5], [4, 2, 4, 5], [4, 2, 1, 0]],
		[[4, -1, 1, 0], [4, -1, 0, 2], [3, 5, 4, 2], [7, 6, 4, 5], [7, 9, 8, 7], [6, 4, 6, 4], [3, 2, 1, 0]],
	],
]

const ARPEGGIO_SHAPES := [
	[[0, 1, 2, 1], [2, 1, 0, 1], [1, 2, 1, 0], [1, 0, 1, 2]],
	[[0, 1, 2, 3], [3, 2, 1, 2], [1, 2, 3, 1], [2, 3, 1, 0]],
	[[0, 2, 3, 1], [4, 3, 1, 2], [1, 4, 5, 3], [5, 3, 2, 0]],
]
const UPPER_TONIC_DEVELOPMENT := {
	0: [[0, 4, 2, 7], [6, 4, 5, 3], [4, 7, 5, 7], [5, 6, 7, 4], [2, 4, 3, 2]],
	2: [[4, -1, 0, 2], [3, 5, 4, 2], [7, 6, 4, 5], [7, 5, 6, 7], [6, 4, 6, 4]],
}
const RHYTHMS := [
	[2, 2, 2, 2], [1, 1, 2, 4], [2, 1, 1, 2, -2], [4, 2, 1, 1], [1, 1, 1, 1, -4],
]

# Each pair is written as two diatonic offsets from C and their alterations.
# The tritone entries deliberately use both identities for the same MIDI pair.
const INTERVALS := [
	[[2, 0, 4, 0], [3, 0, 5, 0], [4, 0, 7, 0], [4, 0, 8, 0], [5, 0, 7, 0], [5, 0, 9, 0]],
	[[2, 0, 3, 0], [3, 1, 4, 0], [2, 0, 4, 0], [1, 0, 4, 0], [1, 0, 5, 0],
		[3, 0, 8, 0], [2, -1, 7, 0], [1, 0, 8, 0], [1, 0, 2, 0], [3, 0, 5, 0], [2, 0, 7, 0]],
	[[0, 0, 3, 1], [0, 0, 4, -1], [3, 1, 6, -1], [2, 0, 6, -1], [3, 1, 7, 0],
		[1, 0, 7, 0], [3, 1, 9, 0], [4, 1, 10, 1], [5, -1, 11, 0], [7, 0, 13, 0]],
]


class SpelledNote:
	var midi: int
	var letter: int
	var octave: int
	var accidental: int

	func _init(pitch: int, diatonic_letter: int) -> void:
		midi = pitch
		letter = diatonic_letter
		accidental = posmod(midi - Chords.WHITE_PITCHES[letter] + 6, 12) - 6
		octave = floori((midi - accidental) / 12.0) - 1

	func staff_step(clef := Notes.Clef.TREBLE) -> int:
		return Notes.diatonic_step(octave, letter, clef)

	func written_name() -> String:
		return "%s%d" % [Theory.Tonality.spell(letter, accidental), octave]


class Event:
	var duration: int
	var pitches: Array[SpelledNote] = []
	var attack: int

	func _init(units: int, notes: Array[SpelledNote], attack_index: int) -> void:
		duration = units
		pitches = notes
		attack = attack_index


class Measure:
	var events: Array[Event] = []


class Exercise:
	var kind: Kind
	var study := Study.MELODY
	var difficulty: Difficulty
	var selected_length: int
	var clef: Notes.Clef
	var measures: Array[Measure] = []
	var notes: Array[SpelledNote] = []
	var attack_count := 0
	var chord_symbol: String
	var interval_name: String
	var key_name: String
	var tonic_letter := -1
	var natural_minor := false
	var key_signature := 0
	var time_signature := TIME_SIGNATURE
	var template_id: String

	func _init(exercise_kind: Kind, level: Difficulty, length: int, notation_clef: Notes.Clef) -> void:
		kind = exercise_kind
		difficulty = level
		selected_length = 2 if kind == Kind.INTERVAL else length
		clef = notation_clef

	func add_event(measure: Measure, units: int, pitches: Array[SpelledNote]) -> void:
		measure.events.append(Event.new(units, pitches, -1 if pitches.is_empty() else attack_count))
		if not pitches.is_empty():
			attack_count += 1
			notes.append_array(pitches)


var _chord_bags: Array[ChordBag] = []
var _pattern_bags: Dictionary[Vector4i, Array] = {}
var _previous_patterns: Dictionary[Vector4i, int] = {}


func _init() -> void:
	for groups in [1, 2, Chords.ALL_GROUPS]:
		var bag := ChordBag.new()
		bag.use_groups(groups)
		_chord_bags.append(bag)


func next(kind: Kind, difficulty: Difficulty, length := DEFAULT_LENGTH, clef := Notes.Clef.TREBLE) -> Exercise:
	assert(length in LENGTHS)
	var exercise := Exercise.new(kind, difficulty, length, clef)
	match kind:
		Kind.PHRASE:
			var variants: int = PHRASES[difficulty].size()
			var pick := _draw_pattern(exercise, KEYS[difficulty].size() * variants)
			var key := floori(float(pick) / variants)
			_make_phrase(exercise, KEYS[difficulty][key], pick % variants)
		Kind.ARPEGGIO:
			_make_arpeggio(exercise, _chord_bags[difficulty].next())
		Kind.INTERVAL:
			_make_interval(exercise, _draw_pattern(exercise, INTERVALS[difficulty].size()))
	assert(is_valid(exercise))
	return exercise


func _draw_pattern(exercise: Exercise, count: int) -> int:
	var group := Vector4i(exercise.kind, exercise.difficulty, exercise.selected_length, exercise.clef)
	if not _pattern_bags.has(group) or _pattern_bags[group].is_empty():
		var shuffled := range(count)
		shuffled.shuffle()
		if shuffled.back() == _previous_patterns.get(group, -1):
			shuffled.push_front(shuffled.pop_back())
		_pattern_bags[group] = shuffled
	var pick: int = _pattern_bags[group].pop_back()
	_previous_patterns[group] = pick
	return pick


static func accidental_signs(measure: Measure, signature: int) -> Array[PackedInt32Array]:
	var active: Dictionary[int, int] = {}
	var signs: Array[PackedInt32Array] = []
	for event in measure.events:
		var event_signs := PackedInt32Array()
		for note in event.pitches:
			var position := note.octave * 7 + note.letter
			var implied: int = active.get(position, signature_alteration(signature, note.letter))
			event_signs.append(NO_SIGN if implied == note.accidental else note.accidental)
			active[position] = note.accidental
		signs.append(event_signs)
	return signs


static func is_valid(exercise: Exercise) -> bool:
	var first := first_midi(exercise.clef)
	var attacks := 0
	var pitches: Array[SpelledNote] = []
	var pulse_count := exercise.time_signature.x * 8.0 / exercise.time_signature.y
	for measure in exercise.measures:
		var units := 0
		for event in measure.events:
			if event.duration not in [EIGHTH, QUARTER, HALF, WHOLE]:
				return false
			units += event.duration
			if event.pitches.is_empty():
				if event.attack != -1 or event.duration not in [QUARTER, HALF]:
					return false
				continue
			if event.attack != attacks or event.pitches.size() != (2 if exercise.kind == Kind.INTERVAL else 1):
				return false
			attacks += 1
			for note in event.pitches:
				if note.midi < first or note.midi >= first + KEYBOARD_SIZE or absi(note.accidental) > 1:
					return false
				if note.midi != (note.octave + 1) * 12 + int(Chords.WHITE_PITCHES[note.letter]) + note.accidental:
					return false
				pitches.append(note)
		if units != pulse_count:
			return false
	if attacks != exercise.attack_count or pitches != exercise.notes or pitches.size() != exercise.selected_length or exercise.template_id.is_empty():
		return false
	match exercise.kind:
		Kind.PHRASE:
			if not _valid_phrase_key(exercise):
				return false
			for note in exercise.notes:
				if note.accidental != signature_alteration(exercise.key_signature, note.letter):
					return false
			return posmod(exercise.notes.back().letter - exercise.tonic_letter, 7) in [0, 2]
		Kind.ARPEGGIO:
			if exercise.key_signature != 0 or exercise.chord_symbol not in allowed_chords(exercise.difficulty):
				return false
			var chord := Chords.Triad.new(exercise.chord_symbol, Chords._root_pitch(exercise.chord_symbol))
			var root_letter := Notes.LETTERS.find(exercise.chord_symbol[0])
			for note in exercise.notes:
				var tone := chord.pitches.find(note.midi % 12)
				if tone == -1 or note.letter != (root_letter + tone * 2) % 7:
					return false
			return true
		Kind.INTERVAL:
			return exercise.key_signature == 0 and exercise.attack_count == 1 and not exercise.interval_name.is_empty() and (
				exercise.interval_name == name_interval(exercise.notes[0], exercise.notes[1]))
	return false


static func first_midi(clef: Notes.Clef) -> int:
	return FIRST_MIDI if clef == Notes.Clef.TREBLE else BASS_FIRST_MIDI


static func signature_alteration(signature: int, letter: int) -> int:
	return Theory.Tonality.signature_alteration(signature, letter)


static func signature_steps(signature: int, clef: Notes.Clef) -> Array[int]:
	return Theory.signature_steps(signature, clef)


static func allowed_chords(difficulty: Difficulty) -> Array:
	match difficulty:
		Difficulty.BEGINNER: return Chords.GROUPS[0]
		Difficulty.INTERMEDIATE: return Chords.GROUPS[1]
	return Chords.GROUPS[0] + Chords.GROUPS[1] + Chords.GROUPS[2] + Chords.GROUPS[3]


static func _phrase_key(choice: Array) -> Theory.Tonality:
	var major := Theory.major(choice[0])
	return major.relative_minor() if choice[1] else major


static func _valid_phrase_key(exercise: Exercise) -> bool:
	for choice: Array in KEYS[exercise.difficulty]:
		var key := _phrase_key(choice)
		if exercise.key_signature == key.signature and exercise.tonic_letter == key.tonic_letter and (
				exercise.natural_minor == key.minor and exercise.key_name == key.note_name(0).replace("♭", "b")):
			return true
	return false


static func _make_phrase(exercise: Exercise, choice: Array, variation: int) -> void:
	var key := _phrase_key(choice)
	exercise.key_name = key.note_name(0).replace("♭", "b")
	exercise.tonic_letter = key.tonic_letter
	exercise.natural_minor = key.minor
	exercise.key_signature = key.signature
	exercise.template_id = "phrase-%d-%d" % [exercise.difficulty, variation + 1]
	var form: Array = PHRASES[exercise.difficulty][variation]
	var count := exercise.selected_length >> 2
	var development := form.slice(1, -1)
	# The B and B-flat tonics use a narrower upper register within the two-octave keyboard.
	if exercise.difficulty == Difficulty.ADVANCED and exercise.tonic_letter == 6:
		development = UPPER_TONIC_DEVELOPMENT.get(variation, development)
	var bars := [form[0]] if count == 1 else development.slice(0, count - 1) + [form.back()]
	var offsets: Array[int] = []
	for bar: Array in bars:
		for degree: int in bar:
			offsets.append(key.semitones_at(degree))
	var low := first_midi(exercise.clef)
	var tonic: int = low + Chords.WHITE_PITCHES[exercise.tonic_letter] + signature_alteration(
		exercise.key_signature, exercise.tonic_letter)
	# Select the playable tonic octave that keeps the actual contour closest to staff center.
	var fitted := -1
	var best := INF
	var bottom_offset: int = offsets.min()
	var top_offset: int = offsets.max()
	for candidate in [tonic - 12, tonic, tonic + 12, tonic + 24]:
		if candidate + bottom_offset < low or candidate + top_offset >= low + KEYBOARD_SIZE:
			continue
		var score := 0.0
		for index in range(offsets.size()):
			var degree: int = bars[index >> 2][index % 4]
			var letter := posmod(exercise.tonic_letter + degree, 7)
			var note := SpelledNote.new(candidate + offsets[index], letter)
			score += absf(note.staff_step(exercise.clef) - 4.0)
		if score < best:
			fitted = candidate
			best = score
	assert(fitted >= 0)
	for index in range(count):
		var pitches: Array[SpelledNote] = []
		for beat in range(4):
			var degree: int = bars[index][beat]
			pitches.append(SpelledNote.new(fitted + offsets[index * 4 + beat], posmod(exercise.tonic_letter + degree, 7)))
		_add_bar(exercise, pitches, index, variation)


static func _make_arpeggio(exercise: Exercise, chord: Chords.Triad) -> void:
	exercise.chord_symbol = chord.symbol
	var root_letter := Notes.LETTERS.find(chord.symbol[0])
	var low := first_midi(exercise.clef)
	var tones: Array[SpelledNote] = []
	for midi in range(low, low + KEYBOARD_SIZE):
		var degree := chord.pitches.find(midi % 12)
		if degree >= 0:
			tones.append(SpelledNote.new(midi, (root_letter + 2 * degree) % 7))
	var variation := randi_range(0, 3)
	var root_index := 0
	match exercise.difficulty:
		Difficulty.BEGINNER:
			var best := INF
			for index in range(tones.size() - 2):
				if tones[index].midi % 12 != chord.root:
					continue
				var center := tones[index + 1].staff_step(exercise.clef)
				if absf(center - 4.0) < best:
					best = absf(center - 4.0)
					root_index = index
		Difficulty.INTERMEDIATE:
			root_index = randi_range(0, 2)
	exercise.template_id = "arpeggio-%d-%d" % [exercise.difficulty, variation + 1]
	for bar in range(exercise.selected_length >> 2):
		var shape_index := (variation + bar) % 4
		var shape: Array = ARPEGGIO_SHAPES[exercise.difficulty][shape_index]
		var pitches: Array[SpelledNote] = []
		for index: int in shape:
			pitches.append(tones[root_index + index])
		_add_bar(exercise, pitches, bar, variation)


static func _add_bar(exercise: Exercise, pitches: Array[SpelledNote], index: int, variation: int) -> void:
	var measure := Measure.new()
	exercise.measures.append(measure)
	var rhythm: Array = RHYTHMS[(index + variation) % RHYTHMS.size()]
	if index == (exercise.selected_length >> 2) - 1:
		rhythm = RHYTHMS[1]
	var tone := 0
	for value: int in rhythm:
		if value < 0:
			exercise.add_event(measure, -value, [])
		else:
			exercise.add_event(measure, value, [pitches[tone]])
			tone += 1


static func _make_interval(exercise: Exercise, index: int) -> void:
	var pair: Array = INTERVALS[exercise.difficulty][index]
	var low := first_midi(exercise.clef)
	var pitches: Array[SpelledNote] = []
	for offset in [0, 2]:
		var degree: int = pair[offset]
		var letter := degree % 7
		var midi: int = low + Chords.WHITE_PITCHES[letter] + pair[offset + 1] + 12 * floori(degree / 7.0)
		pitches.append(SpelledNote.new(midi, letter))
	if exercise.clef == Notes.Clef.BASS and pitches[1].midi + 12 < low + KEYBOARD_SIZE:
		var center := (pitches[0].staff_step(exercise.clef) + pitches[1].staff_step(exercise.clef)) * 0.5
		if center < 0.5:
			for slot in range(pitches.size()):
				pitches[slot] = SpelledNote.new(pitches[slot].midi + 12, pitches[slot].letter)
	exercise.interval_name = name_interval(pitches[0], pitches[1])
	exercise.template_id = "interval-%d-%d" % [exercise.difficulty, index + 1]
	var measure := Measure.new()
	exercise.measures.append(measure)
	exercise.add_event(measure, WHOLE, pitches)


static func name_interval(lower: SpelledNote, upper: SpelledNote) -> String:
	var size := upper.staff_step() - lower.staff_step()
	var chromatic := upper.midi - lower.midi
	var names := ["прима", "секунда", "терция", "кварта", "квинта", "секста", "септима", "октава"]
	var reference := [0, 2, 4, 5, 7, 9, 11, 12]
	if size < 0 or size >= names.size() or chromatic < 0:
		return ""
	var delta: int = chromatic - reference[size]
	var quality := ""
	if size in [0, 3, 4, 7]:
		quality = {0: "Чистая", 1: "Увеличенная", -1: "Уменьшённая"}.get(delta, "")
	else:
		quality = {0: "Большая", -1: "Малая", 1: "Увеличенная", -2: "Уменьшённая"}.get(delta, "")
	return "" if quality.is_empty() else "%s %s" % [quality, names[size]]
