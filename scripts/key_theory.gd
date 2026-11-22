extends RefCounted

const Chords := preload("res://scripts/chords.gd")
const Notes := preload("res://scripts/notes.gd")

const SHARP_ORDER := [3, 0, 4, 1, 5, 2, 6]
const FLAT_ORDER := [6, 2, 5, 1, 4, 0, 3]
const RUSSIAN_LETTERS := ["До", "Ре", "Ми", "Фа", "Соль", "Ля", "Си"]
const ROMANS := ["I", "II", "III", "IV", "V", "VI", "VII"]
const QUALITIES := ["мажорное", "минорное", "уменьшённое", "увеличенное"]
const SUFFIXES := ["", "m", "dim", "aug"]
const ACCIDENTALS := ["𝄫", "♭", "", "♯", "𝄪"]
# Each sector stores its tonic letter in C–B order and a signed signature count.
const WHEEL := [Vector2i(0, 0), Vector2i(4, 1), Vector2i(1, 2), Vector2i(5, 3),
	Vector2i(2, 4), Vector2i(6, 5), Vector2i(3, 6), Vector2i(1, -5),
	Vector2i(5, -4), Vector2i(2, -3), Vector2i(6, -2), Vector2i(3, -1)]
const ENHARMONIC_SECTOR := 6
const G_FLAT := Vector2i(4, -6)

enum ScaleForm { NATURAL, HARMONIC }
enum TriadQuality { MAJOR, MINOR, DIMINISHED, AUGMENTED }


class Tonality:
	var tonic_letter: int
	var signature: int
	var minor: bool

	func _init(letter: int, signs: int, is_minor := false) -> void:
		tonic_letter = letter
		signature = signs
		minor = is_minor

	func letter_at(degree: int) -> int:
		return posmod(tonic_letter + degree, 7)

	func alteration_at(degree: int, form := ScaleForm.NATURAL) -> int:
		var raised := minor and form == ScaleForm.HARMONIC and posmod(degree, 7) == 6
		return signature_alteration(signature, letter_at(degree)) + int(raised)

	func pitch_class(degree: int, form := ScaleForm.NATURAL) -> int:
		var letter := letter_at(degree)
		return posmod(Chords.WHITE_PITCHES[letter] + alteration_at(degree, form), 12)

	func note_name(degree: int, form := ScaleForm.NATURAL) -> String:
		return spell(letter_at(degree), alteration_at(degree, form))

	func semitones_at(degree: int, form := ScaleForm.NATURAL) -> int:
		return posmod(pitch_class(degree, form) - pitch_class(0), 12) + 12 * floori(degree / 7.0)

	func short_name() -> String:
		return note_name(0) + (" minor" if minor else " major")

	func russian_name() -> String:
		var suffix := ["-бемоль", "", "-диез"][alteration_at(0) + 1] as String
		return RUSSIAN_LETTERS[tonic_letter] + suffix + (" минор" if minor else " мажор")

	func name() -> String:
		return "%s — %s" % [short_name(), russian_name()]

	func relative_minor() -> Tonality:
		return Tonality.new(letter_at(5), signature, true)

	func relative_major() -> Tonality:
		return Tonality.new(letter_at(2), signature)

	func scale_names(form := ScaleForm.NATURAL) -> PackedStringArray:
		var names := PackedStringArray()
		for degree in range(7):
			names.append(note_name(degree, form))
		return names

	func signature_names() -> PackedStringArray:
		var names := PackedStringArray()
		var order := signature_order(signature)
		for slot in range(absi(signature)):
			names.append(spell(order[slot], signi(signature)))
		return names

	func triad_quality(degree: int, form := ScaleForm.NATURAL) -> TriadQuality:
		var root := pitch_class(degree, form)
		var third := posmod(pitch_class(degree + 2, form) - root, 12)
		var fifth := posmod(pitch_class(degree + 4, form) - root, 12)
		if fifth == 6:
			return TriadQuality.DIMINISHED
		if fifth == 8:
			return TriadQuality.AUGMENTED
		return TriadQuality.MINOR if third == 3 else TriadQuality.MAJOR

	func triad_roman(degree: int, form := ScaleForm.NATURAL) -> String:
		var roman: String = ROMANS[degree]
		match triad_quality(degree, form):
			TriadQuality.MINOR: return roman.to_lower()
			TriadQuality.DIMINISHED: return roman.to_lower() + "°"
			TriadQuality.AUGMENTED: return roman + "+"
		return roman

	func triad_name(degree: int, form := ScaleForm.NATURAL) -> String:
		return note_name(degree, form) + SUFFIXES[triad_quality(degree, form)]

	func triad_names(degree: int, form := ScaleForm.NATURAL) -> PackedStringArray:
		return PackedStringArray([note_name(degree, form), note_name(degree + 2, form), note_name(degree + 4, form)])

	static func signature_order(signs: int) -> Array:
		return SHARP_ORDER if signs > 0 else FLAT_ORDER

	static func signature_alteration(signs: int, letter: int) -> int:
		var rank := signature_order(signs).find(letter)
		return signi(signs) if rank < absi(signs) else 0

	static func spell(letter: int, accidental: int) -> String:
		return Notes.LETTERS[letter] + ACCIDENTALS[accidental + 2]


static func major(sector: int, prefer_flats := false) -> Tonality:
	var data: Vector2i = G_FLAT if sector == ENHARMONIC_SECTOR and prefer_flats else WHEEL[sector]
	return Tonality.new(data.x, data.y)


static func at_sector(sector: int, prefer_flats: bool, minor: bool) -> Tonality:
	var key := major(sector, prefer_flats)
	return key.relative_minor() if minor else key


static func signature_steps(signature: int, clef: Notes.Clef) -> Array[int]:
	var treble := [8, 5, 9, 6, 3, 7, 4] if signature > 0 else [4, 7, 3, 6, 2, 5, 1]
	var shift := 2 if clef == Notes.Clef.BASS else 0
	var steps: Array[int] = []
	for index in range(absi(signature)):
		steps.append(int(treble[index]) - shift)
	return steps
