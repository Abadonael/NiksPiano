extends RefCounted

const PITCH_CLASSES := 12
const WHITE_PITCHES := [0, 2, 4, 5, 7, 9, 11]
const BLACK_PITCHES := [1, 3, 6, 8, 10]
const GROUPS := [
	["C", "Dm", "Em", "F", "G", "Am"],
	["Cm", "D", "E", "Fm", "Gm", "A", "Bb", "Bm"],
	["Db", "Eb", "Ab", "B", "F#m", "C#m", "G#m", "Bbm"],
	["F#", "Ebm"],
]
const GROUP_TITLES := [
	"0 чёрных клавиш", "1 чёрная клавиша", "2 чёрные клавиши", "3 чёрные клавиши",
]
const ALL_GROUPS := 0b1111
const DEFAULT_GROUPS := 0b0011
const NATURALS := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


class Triad:
	var symbol: String
	var root: int
	var pitches: Array[int]

	func _init(chord_symbol: String, root_pitch: int) -> void:
		symbol = chord_symbol
		root = root_pitch
		var third := 3 if symbol.ends_with("m") else 4
		pitches = [root, (root + third) % PITCH_CLASSES, (root + 7) % PITCH_CLASSES]

	func root_position(first_octave_c: int) -> Array[int]:
		var bass := first_octave_c + root
		return [bass, bass + posmod(pitches[1] - root, PITCH_CLASSES), bass + 7]


static func enabled_chords(mask: int) -> Array[Triad]:
	var pool: Array[Triad] = []
	for group in range(GROUPS.size()):
		if mask & (1 << group):
			for symbol: String in GROUPS[group]:
				pool.append(Triad.new(symbol, _root_pitch(symbol)))
	return pool


static func _root_pitch(symbol: String) -> int:
	var pitch: int = NATURALS[symbol[0]]
	if symbol.substr(1, 1) == "#":
		pitch += 1
	elif symbol.substr(1, 1) == "b":
		pitch -= 1
	return posmod(pitch, PITCH_CLASSES)
