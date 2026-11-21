extends RefCounted

enum Clef { TREBLE, BASS }

const RANGES := [
	{"title": "Первая октава", "octave": 4, "clef": Clef.TREBLE},
	{"title": "Вторая октава", "octave": 5, "clef": Clef.TREBLE},
	{"title": "Большая октава", "octave": 2, "clef": Clef.BASS},
	{"title": "Малая октава", "octave": 3, "clef": Clef.BASS},
]
const RUSSIAN := ["До", "Ре", "Ми", "Фа", "Соль", "Ля", "Си"]
const LETTERS := ["C", "D", "E", "F", "G", "A", "B"]
const KEY_COUNT := 7
const ALL_RANGES := (1 << 4) - 1

# Diatonic pitch numbers count white notes from C0. The five lines are steps
# 0, 2, 4, 6 and 8 above the bottom line (E4 in treble, G2 in bass).
static func staff_step(range_index: int, pitch_class: int) -> int:
	var note: Dictionary = RANGES[range_index]
	return diatonic_step(note.octave, pitch_class, note.clef)


static func diatonic_step(octave: int, letter: int, clef: Clef) -> int:
	var bottom_pitch := 4 * KEY_COUNT + 2 if clef == Clef.TREBLE else 2 * KEY_COUNT + 4
	return octave * KEY_COUNT + letter - bottom_pitch


static func ledger_steps(step: int) -> Array[int]:
	var lines: Array[int] = []
	for line in range(-2, step - 1, -2):
		lines.append(line)
	for line in range(10, step + 1, 2):
		lines.append(line)
	return lines


static func enabled_ranges(mask: int) -> Array[int]:
	var enabled: Array[int] = []
	for index in range(RANGES.size()):
		if (mask & (1 << index)) != 0:
			enabled.append(index)
	return enabled
