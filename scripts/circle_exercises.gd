extends RefCounted

const Theory := preload("res://scripts/key_theory.gd")
const Exercises := preload("res://scripts/melody_exercises.gd")
const Notes := preload("res://scripts/notes.gd")

const PROGRESSION := [0, 3, 4, 0]
const FUNCTIONS := [
	"Тоника — центр устойчивости.",
	"Субдоминанта — движение от тоники.",
	"Доминанта — напряжение, которое тяготеет к тонике.",
	"Возвращение к тонике.",
]


static func scale(key: Theory.Tonality, form := Theory.ScaleForm.NATURAL) -> Exercises.Exercise:
	var exercise := _score(key, Exercises.Study.SCALE, 15)
	var tonic := Exercises.FIRST_MIDI + key.pitch_class(0)
	var rhythms := [[2, 2, 2, 2], [2, 2, 2, 2], [2, 2, 2, 2], [2, 2, 4]]
	for bar: Array in rhythms:
		var measure := Exercises.Measure.new()
		exercise.measures.append(measure)
		for duration: int in bar:
			var degree := mini(exercise.attack_count, 14 - exercise.attack_count)
			var note := Exercises.SpelledNote.new(tonic + key.semitones_at(degree, form), key.letter_at(degree))
			exercise.add_event(measure, duration, [note])
	return exercise


static func progression(key: Theory.Tonality) -> Array[Exercises.Exercise]:
	var scores: Array[Exercises.Exercise] = []
	var form := cadence_form(key)
	for degree: int in PROGRESSION:
		var exercise := _score(key, Exercises.Study.TRIAD, 3)
		exercise.chord_symbol = key.triad_name(degree, form)
		var measure := Exercises.Measure.new()
		exercise.measures.append(measure)
		var root_pitch := key.pitch_class(degree, form)
		var root := Exercises.FIRST_MIDI + root_pitch
		var pitches: Array[Exercises.SpelledNote] = []
		for tone in [0, 2, 4]:
			var offset := posmod(key.pitch_class(degree + tone, form) - root_pitch, 12)
			pitches.append(Exercises.SpelledNote.new(root + offset, key.letter_at(degree + tone)))
		exercise.add_event(measure, Exercises.WHOLE, pitches)
		scores.append(exercise)
	return scores


static func cadence_form(key: Theory.Tonality) -> Theory.ScaleForm:
	return Theory.ScaleForm.HARMONIC if key.minor else Theory.ScaleForm.NATURAL


static func _score(key: Theory.Tonality, study: Exercises.Study, length: int) -> Exercises.Exercise:
	var exercise := Exercises.Exercise.new(Exercises.Kind.PHRASE, Exercises.Difficulty.BEGINNER, length, Notes.Clef.TREBLE)
	exercise.study = study
	exercise.key_name = key.note_name(0)
	exercise.tonic_letter = key.tonic_letter
	exercise.key_signature = key.signature
	return exercise
