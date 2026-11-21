extends RefCounted

const Exercises := preload("res://scripts/melody_exercises.gd")

enum Result { IGNORED, WRONG, CORRECT, COMPLETE }

var exercise: Exercises.Exercise
var completed := 0


func reset(next_exercise: Exercises.Exercise) -> void:
	exercise = next_exercise
	completed = 0


func press(midi: int, held: Array[int] = []) -> Result:
	if exercise == null or completed == exercise.attack_count:
		return Result.IGNORED
	if exercise.kind == Exercises.Kind.INTERVAL:
		var lower := exercise.notes[0].midi
		var upper := exercise.notes[1].midi
		if midi != lower and midi != upper:
			return Result.WRONG
		if lower in held and upper in held:
			completed = 1
			return Result.COMPLETE
		return Result.CORRECT
	if midi != exercise.notes[completed].midi:
		return Result.WRONG
	completed += 1
	return Result.COMPLETE if completed == exercise.attack_count else Result.CORRECT
