extends RefCounted

const Notes := preload("res://scripts/notes.gd")
const NO_RANGE := -1

class Question:
	var range_index: int
	var pitch_class: int

	func _init(note_range: int, pitch: int) -> void:
		range_index = note_range
		pitch_class = pitch


var _ranges: Array[int] = []
var _questions: Array[Question] = []
var _last_pitch := -1


func use_ranges(ranges: Array[int], restart_cycle := false) -> void:
	if ranges != _ranges or restart_cycle:
		_ranges = ranges.duplicate()
		_questions.clear()


func next() -> Question:
	if _questions.is_empty():
		_fill()
	var question: Question = _questions.pop_front()
	_last_pitch = question.pitch_class
	return question


func _fill() -> void:
	var variants_by_pitch: Array[Array] = []
	for _pitch in range(Notes.KEY_COUNT):
		var variants := _ranges.duplicate()
		variants.shuffle()
		variants_by_pitch.append(variants)

	var previous := _last_pitch
	var total := _ranges.size() * Notes.KEY_COUNT
	for remaining in range(total, 0, -1):
		var choices: Array[int] = []
		for pitch in range(Notes.KEY_COUNT):
			var count := variants_by_pitch[pitch].size()
			if count == 0 or pitch == previous:
				continue
			if count * 2 > remaining:
				# This pitch needs both ends of the remaining sequence. In
				# every other case, any available non-repeating pitch fits.
				choices = [pitch]
				break
			choices.append(pitch)
		var pitch: int = choices.pick_random()
		var note_range: int = variants_by_pitch[pitch].pop_back()
		_questions.append(Question.new(note_range, pitch))
		previous = pitch
