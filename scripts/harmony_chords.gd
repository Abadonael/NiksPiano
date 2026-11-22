extends RefCounted

const Chords := preload("res://scripts/chords.gd")
const Audio := preload("res://scripts/piano_audio.gd")
const ROOTS := ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B",
	"Cb", "B#", "Fb", "E#"]
const LETTERS := "CDEFGAB"
const SUFFIXES := {"major": "", "minor": "m", "diminished": "dim", "augmented": "aug"}
const INTERVALS := {"major": [0, 4, 7], "minor": [0, 3, 7],
	"diminished": [0, 3, 6], "augmented": [0, 4, 8]}
const PITCH_NAMES := ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
const DEFAULT_ROOTS := ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
const INVERSIONS := ["Основной вид", "1-е обращение", "2-е обращение"]
const INVERSION_NAMES := ["основной вид", "первое обращение", "второе обращение"]
const ROOT_NAMES := ["До", "Ре", "Ми", "Фа", "Соль", "Ля", "Си"]
const ACCIDENTALS := ["bb", "b", "", "#", "##"]
const WRITTEN_ACCIDENTALS := ["𝄫", "♭", "", "♯", "𝄪"]


static func catalog(root: String, quality: String) -> Dictionary:
	if root not in ROOTS or not INTERVALS.has(quality):
		return {}
	var pitches: Array[int] = []
	for interval: int in INTERVALS[quality]:
		pitches.append(Audio.C4 + Chords._root_pitch(root) + interval)
	return {"kind": "catalog", "root": root, "quality": quality, "pitches": pitches}


static func custom(title: String, pitches: Array) -> Dictionary:
	return {"kind": "custom", "name": title.strip_edges(), "pitches": pitches.duplicate()}


static func title(definition: Dictionary) -> String:
	if definition.kind == "custom":
		return definition.name
	return definition.root + SUFFIXES[definition.quality]


static func event_title(event: Dictionary) -> String:
	var name := title(event.chord)
	if event.bass_midi != null:
		name += "/" + event.bass_spelling
	elif event.voicing.inversion in [1, 2]:
		name += "/" + tone_spelling(event.chord, int(event.sounding_pitches.min()))
	return name


static func identity(definition: Dictionary) -> String:
	if definition.kind == "custom":
		return definition.name
	var root: String = definition.root
	var ending := {"#": "-диез", "b": "-бемоль"}
	var note := "%s%s" % [ROOT_NAMES[LETTERS.find(root[0])], ending.get(root.substr(1), "")]
	match definition.quality:
		"major": return note + " мажор"
		"minor": return note + " минор"
		"diminished": return "Уменьшённое трезвучие от " + note.to_lower()
		_: return "Увеличенное трезвучие от " + note.to_lower()


static func bass_name(event: Dictionary, pitch: int) -> String:
	var spelling: String = event.bass_spelling if event.bass_midi != null else tone_spelling(event.chord, pitch)
	return written_pitch(pitch, spelling)


static func tone_spelling(definition: Dictionary, midi: int) -> String:
	var index: Variant = inversion(definition, midi)
	var spelling: String = PITCH_NAMES[midi % 12] if index == null else tone_names(definition)[int(index)]
	return spelling.replace("♯", "#").replace("♭", "b")


static func has_tone(definition: Dictionary, midi: int) -> bool:
	for pitch: int in definition.pitches:
		if pitch % 12 == midi % 12:
			return true
	return false


static func inversion(definition: Dictionary, lowest: int) -> Variant:
	if definition.kind != "catalog":
		return null
	var root := Chords._root_pitch(definition.root)
	var index: int = INTERVALS[definition.quality].find(posmod(lowest - root, 12))
	return index if index >= 0 else null


static func invert(definition: Dictionary, index: int) -> Dictionary:
	var result := catalog(definition.root, definition.quality)
	for rotation in range(index):
		result.pitches.append(int(result.pitches.pop_front()) + 12)
	return result


static func sounding(definition: Dictionary, bass: Variant) -> Array[int]:
	var pitches: Array[int] = []
	if bass != null:
		pitches.append(int(bass))
	for pitch: int in definition.pitches:
		# Move a catalog chord tone to the slash bass. Custom pitches stay as entered.
		if bass == null or (pitch != bass and (definition.kind == "custom" or pitch % 12 != int(bass) % 12)):
			pitches.append(pitch)
	return pitches


static func bass_pitches(definition: Dictionary, spelling: String) -> Array[int]:
	return bass_registers(definition, bass_pitch_class(spelling))


static func bass_for_replacement(definition: Dictionary, bass: Variant, spelling: String) -> Variant:
	if bass == null or bass < definition.pitches.min():
		return bass
	var available := bass_pitches(definition, spelling)
	return null if available.is_empty() else available[0]


static func root_spellings(pitch_class: int) -> PackedStringArray:
	var primary: String = DEFAULT_ROOTS[pitch_class]
	var spellings := PackedStringArray([primary])
	for root: String in ROOTS:
		if root != primary and Chords._root_pitch(root) == pitch_class:
			spellings.append(root)
	return spellings


static func bass_registers(definition: Dictionary, pitch_class: int) -> Array[int]:
	var lowest := int(definition.pitches.min())
	var pitches: Array[int] = []
	var nearest := lowest - 1 - posmod(lowest - 1 - pitch_class, 12)
	for midi in range(nearest, Audio.FREE_LOWEST - 1, -12):
		pitches.append(midi)
	return pitches


static func valid_bass_spelling(value: Variant) -> bool:
	return value is String and not value.is_empty() and value[0] in LETTERS and value.substr(1) in ACCIDENTALS


static func bass_pitch_class(spelling: String) -> int:
	var accidental := ACCIDENTALS.find(spelling.substr(1)) - 2
	return posmod(int(Chords.NATURALS[spelling[0]]) + accidental, 12)


static func bass_spellings(definition: Dictionary, pitch_class: int) -> PackedStringArray:
	var spellings := PackedStringArray([explicit_bass_spelling(definition, pitch_class)])
	for letter in LETTERS:
		for accidental: String in ACCIDENTALS:
			var spelling: String = letter + accidental
			if bass_pitch_class(spelling) == pitch_class and spelling not in spellings:
				spellings.append(spelling)
	return spellings


static func explicit_bass_spelling(definition: Dictionary, pitch_class: int) -> String:
	var spelling := tone_spelling(definition, pitch_class)
	return spelling if valid_bass_spelling(spelling) else DEFAULT_ROOTS[pitch_class]


static func written_pitch(midi: int, spelling: String) -> String:
	var accidental := spelling.count("#") - spelling.count("b")
	var octave := floori(float(midi - int(Chords.NATURALS[spelling[0]]) - accidental) / 12.0) - 1
	return written_pitch_class(spelling) + str(octave)


static func written_pitch_class(spelling: String) -> String:
	return spelling[0] + written_accidental(spelling.count("#") - spelling.count("b"))


static func written_accidental(accidental: int) -> String:
	match accidental:
		3: return "𝄪♯"
		-3: return "𝄫♭"
		_: return WRITTEN_ACCIDENTALS[accidental + 2]


static func tone_names(definition: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	if definition.kind == "custom":
		for pitch: int in definition.pitches:
			names.append(pitch_name(pitch))
		return names
	var letter_index := LETTERS.find(definition.root[0])
	var pitch_class := Chords._root_pitch(definition.root)
	var intervals: Array = INTERVALS[definition.quality]
	for index in range(3):
		var letter := LETTERS[(letter_index + index * 2) % LETTERS.length()]
		var accidental := posmod(pitch_class + intervals[index] - Chords.NATURALS[letter] + 6, 12) - 6
		names.append(letter + ("♯".repeat(accidental) if accidental > 0 else "♭".repeat(-accidental)))
	return names


static func pitch_name(midi: int) -> String:
	return PITCH_NAMES[midi % 12] + str(floori(midi / 12.0) - 1)


static func pitches_are_valid(value: Variant) -> bool:
	if not value is Array or value.size() < 2 or value.size() > 6:
		return false
	var seen := {}
	for pitch: Variant in value:
		if not integer_in(pitch, Audio.FREE_LOWEST, Audio.FREE_HIGHEST) or seen.has(int(pitch)):
			return false
		seen[int(pitch)] = true
	return true


static func integer_in(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and value >= low and value <= high and value == floorf(value)


static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or not pitches_are_valid(value.get("pitches")):
		return {}
	var pitches: Array[int] = []
	for pitch: int in value.pitches:
		pitches.append(pitch)
	match value.get("kind"):
		"custom":
			var name: Variant = value.get("name")
			if name is String and name.length() <= 48 and not name.strip_edges().is_empty() and not "\n" in name and not "\r" in name:
				return custom(name, pitches)
		"catalog":
			if value.get("root") is String and value.get("quality") is String:
				var result := catalog(value.root, value.quality)
				if not result.is_empty() and pitches.size() == 3:
					var expected: Array[int] = []
					var actual: Array[int] = []
					for pitch in result.pitches:
						expected.append(pitch % 12)
					for pitch in pitches:
						actual.append(pitch % 12)
					expected.sort()
					actual.sort()
					if actual == expected:
						result.pitches = pitches
						return result
	return {}
