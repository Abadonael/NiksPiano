extends "res://scripts/melody_staff.gd"

const Chord := preload("res://scripts/harmony_chords.gd")
const MAX_SPACE := 28.0
const ABOVE_CLEF := 5.8
const BELOW_CLEF := 2.0

var chord_notes: Array[Exercises.SpelledNote] = []
var _treble: Array[Exercises.SpelledNote] = []
var _bass: Array[Exercises.SpelledNote] = []


func _ready() -> void:
	resized.connect(queue_redraw)


func show_chord(definition: Dictionary, sounding: Array = [], bass: Variant = null, bass_spelling := "") -> void:
	chord_notes.clear()
	_treble.clear()
	_bass.clear()
	if not definition.is_empty():
		var spellings := {}
		if definition.kind == "catalog":
			var root := Chord.Chords._root_pitch(definition.root)
			var names := Chord.tone_names(definition)
			var intervals: Array = Chord.INTERVALS[definition.quality]
			for index in range(intervals.size()):
				spellings[(root + int(intervals[index])) % 12] = names[index]
		var pitches: Array = definition.pitches if sounding.is_empty() else sounding
		for midi: int in pitches:
			var spelling: String = spellings.get(midi % 12, Chord.PITCH_NAMES[midi % 12])
			if bass == midi:
				spelling = bass_spelling
			var note := Exercises.SpelledNote.new(midi, Notes.LETTERS.find(spelling.left(1)))
			chord_notes.append(note)
		chord_notes.sort_custom(func(a: Exercises.SpelledNote, b: Exercises.SpelledNote) -> bool:
			return a.staff_step() < b.staff_step() if a.staff_step() != b.staff_step() else a.midi < b.midi)
	for note in chord_notes:
		var staff_notes := _bass if note.midi < Chord.Audio.C4 else _treble
		staff_notes.append(note)
	var rise := _staff_height(_treble, Notes.Clef.TREBLE)
	var fall := _staff_height(_bass, Notes.Clef.BASS)
	custom_minimum_size.y = 172
	var clefs := "Скрипичный ключ"
	if not _bass.is_empty():
		clefs = "Басовый ключ"
		if not _treble.is_empty():
			clefs = "Скрипичный и басовый ключи"
			custom_minimum_size.y = 305
	if rise.x + rise.y > 10.0 or fall.x + fall.y > 10.0:
		custom_minimum_size.y += 65
	accessibility_name = clefs + ". " + " — ".join(written_names(true))
	queue_redraw()


func written_names(with_octaves: bool) -> PackedStringArray:
	var names := PackedStringArray()
	for note in chord_notes:
		var name: String = Notes.LETTERS[note.letter] + Chord.written_accidental(note.accidental)
		names.append(name + str(note.octave) if with_octaves else name)
	return names


func _draw() -> void:
	var treble := _bass.is_empty() or not _treble.is_empty()
	var rise := _staff_height(_treble, Notes.Clef.TREBLE) if treble else Vector2.ZERO
	var fall := _staff_height(_bass, Notes.Clef.BASS) if not _bass.is_empty() else Vector2.ZERO
	var total := rise.x + rise.y + fall.x + fall.y
	var space := minf(MAX_SPACE, minf(size.x / 19.0, size.y / total))
	if space <= 0.0:
		return
	var width := minf(size.x - 12.0, 18.0 * space)
	var left := (size.x - width) * 0.5
	var top := (size.y - total * space) * 0.5
	if treble:
		_draw_harmony_staff(_treble, Notes.Clef.TREBLE, left, width, top + rise.x * space, space)
	if not _bass.is_empty():
		var bass_bottom := top + (rise.x + rise.y + fall.x) * space
		_draw_harmony_staff(_bass, Notes.Clef.BASS, left, width, bass_bottom, space)


func _staff_height(notes: Array[Exercises.SpelledNote], clef: Notes.Clef) -> Vector2:
	var height := Vector2(ABOVE_CLEF if clef == Notes.Clef.TREBLE else 4.9, BELOW_CLEF)
	for note in notes:
		var step := note.staff_step(clef)
		height.x = maxf(height.x, step * 0.5 + 1.8)
		height.y = maxf(height.y, -step * 0.5 + 1.7)
	return height


func _draw_harmony_staff(notes: Array[Exercises.SpelledNote], clef: Notes.Clef,
		left: float, width: float, bottom: float, space: float) -> void:
	_draw_staff(left, left + width, left + 0.42 * space, bottom, space, clef == Notes.Clef.TREBLE)
	var head_x := left + width * 0.68
	var last_step := -100
	var displaced := false
	var columns: Array[int] = []
	var has_wide_sign := notes.any(func(note: Exercises.SpelledNote) -> bool: return absi(note.accidental) == 3)
	var accidental_offset := 3.0 if has_wide_sign else 2.28
	var column_width := 2.12 if has_wide_sign else 1.35
	for note in notes:
		var step := note.staff_step(clef)
		# Adjacent or unison spellings need alternating notehead positions.
		displaced = step - last_step <= 1 and not displaced
		last_step = step
		_draw_head(head_x + (1.72 * space if displaced else 0.0), step, Exercises.WHOLE, bottom, space, INK)
		if note.accidental == 0 and not _has_altered_unison(notes, step, clef):
			continue
		var column := 0
		while column < columns.size() and step - columns[column] < 7:
			column += 1
		if column == columns.size():
			columns.append(step)
		else:
			columns[column] = step
		_draw_symbol(_chord_accidental(note.accidental), head_x - (accidental_offset + column_width * column) * space, step, bottom, space)


static func _chord_accidental(sign: int) -> String:
	match sign:
		3: return "\uE265"
		-3: return "\uE266"
		_: return _accidental(sign)


func _has_altered_unison(notes: Array[Exercises.SpelledNote], step: int, clef: Notes.Clef) -> bool:
	for note in notes:
		if note.staff_step(clef) == step and note.accidental != 0:
			return true
	return false
