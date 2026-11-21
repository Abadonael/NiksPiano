extends "res://scripts/staff.gd"

const Exercises := preload("res://scripts/melody_exercises.gd")
const TARGET_INK := Color("#ffd480")
const VERTICAL_PAD := 0.48
const BAR_SPACE := 19.4
const INTERVAL_SPACE := 8.2
const ANSWER_HEIGHT := 32.0
const ANSWER_BOTTOM_MARGIN := 7.0

var _exercise: Exercises.Exercise
var _signs: Array[Array] = []
var _attack_measures: Array[int] = []
var _completed := 0
var _rise := 0.0
var _drop := 0.0


func show_phrase(exercise: Exercises.Exercise) -> void:
	_exercise = exercise
	_signs.clear()
	_attack_measures.clear()
	if exercise != null:
		var treble := exercise.clef == Notes.Clef.TREBLE
		_rise = 5.50 if treble else 4.55
		_drop = 1.70 if treble else 0.50
		for step in Exercises.signature_steps(exercise.key_signature, exercise.clef):
			_fit_height(step, 1.90, 1.65)
		for index in range(exercise.measures.size()):
			var measure := exercise.measures[index]
			var signs := Exercises.accidental_signs(measure, exercise.key_signature)
			_signs.append(signs)
			for slot in range(measure.events.size()):
				var event := measure.events[slot]
				if event.attack >= 0:
					_attack_measures.append(index)
				for voice in range(event.pitches.size()):
					var step := event.pitches[voice].staff_step(exercise.clef)
					var stem_up := step < STEM_UP_BELOW_STEP
					if event.duration != Exercises.WHOLE:
						_fit_height(step, STEM_LENGTH if stem_up else 0.55, 0.55 if stem_up else STEM_LENGTH)
					_fit_height(step, 1.95 if signs[slot][voice] != Exercises.NO_SIGN else 0.6,
						1.65 if signs[slot][voice] != Exercises.NO_SIGN else 0.6)
	show_progress(0)


func _fit_height(step: int, rise: float, drop: float) -> void:
	_rise = maxf(_rise, step * 0.5 + rise)
	_drop = maxf(_drop, -step * 0.5 + drop)


func show_progress(completed: int) -> void:
	_completed = completed
	queue_redraw()


func note_ink(index: int) -> Color:
	if index < _completed:
		return Finish.SUCCESS_GREEN
	return TARGET_INK if index == _completed else INK


func _header_width() -> float:
	return 5.25 + 0.98 * absi(_exercise.key_signature)


func _bar_width() -> float:
	return INTERVAL_SPACE if _exercise.kind == Exercises.Kind.INTERVAL else BAR_SPACE


func _notation_height() -> float:
	return size.y - (ANSWER_HEIGHT + ANSWER_BOTTOM_MARGIN if _exercise.kind == Exercises.Kind.INTERVAL else 0.0)


func staff_space() -> float:
	if _exercise == null:
		return 0.0
	return maxf(0.0, minf(_notation_height() / (_rise + _drop + 2.0 * VERTICAL_PAD),
		(size.x - 4.0) / (_header_width() + _bar_width())))


func visible_measures() -> Vector2i:
	var space := staff_space()
	if space <= 0.0 or _attack_measures.is_empty():
		return Vector2i.ZERO
	var per_page := maxi(1, floori(((size.x - 4.0) / space - _header_width()) / _bar_width() + 0.0001))
	var measure := _attack_measures[mini(_completed, _attack_measures.size() - 1)]
	var first := floori(float(measure) / per_page) * per_page
	return Vector2i(first, mini(first + per_page, _exercise.measures.size()))


func _draw() -> void:
	var space := staff_space()
	if space <= 0.0:
		return
	var page := visible_measures()
	var width := (_header_width() + (page.y - page.x) * _bar_width()) * space
	var left := (size.x - width) * 0.5
	var bottom := (_notation_height() + (_rise - _drop) * space) * 0.5
	var right := left + width
	_draw_staff(left, right, left + 0.25 * space, bottom, space, _exercise.clef == Notes.Clef.TREBLE)
	_draw_header(left, bottom, space, page.x == 0)
	var bar_x := left + _header_width() * space
	for index in range(page.x, page.y):
		_draw_measure(index, bar_x, bottom, space)
		bar_x += _bar_width() * space
		_draw_bar_line(bar_x, bottom, space, index == _exercise.measures.size() - 1)


func _draw_header(left: float, bottom: float, space: float, first_page: bool) -> void:
	var steps := Exercises.signature_steps(_exercise.key_signature, _exercise.clef)
	for index in range(steps.size()):
		_draw_symbol(_accidental(signi(_exercise.key_signature)), left + (2.95 + 0.98 * index) * space,
			steps[index], bottom, space)
	if first_page:
		var x := left + (3.47 + 0.98 * steps.size()) * space
		_draw_symbol(char(0xE080 + _exercise.time_signature.x), x, 6, bottom, space)
		_draw_symbol(char(0xE080 + _exercise.time_signature.y), x, 2, bottom, space)


func _draw_measure(index: int, left: float, bottom: float, space: float) -> void:
	var measure := _exercise.measures[index]
	var elapsed := 0
	for slot in range(measure.events.size()):
		var event := measure.events[slot]
		var x := left + (2.35 + slot * 3.45 + elapsed * 0.25) * space
		if event.pitches.is_empty():
			var rest := "\uE4E4" if event.duration == Exercises.HALF else "\uE4E5"
			_draw_symbol(rest, x - 0.5 * space, 4, bottom, space)
		elif event.pitches.size() == 2:
			_draw_interval(event, _signs[index][slot], left + 3.75 * space, bottom, space)
		else:
			var step := event.pitches[0].staff_step(_exercise.clef)
			var ink := note_ink(event.attack)
			var sign: int = _signs[index][slot][0]
			_draw_head(x, step, event.duration, bottom, space, ink)
			_draw_stem(x, step, event.duration, bottom, space, ink)
			if sign != Exercises.NO_SIGN:
				_draw_symbol(_accidental(sign), x - 2.04 * space, step, bottom, space)
		elapsed += event.duration


func _draw_interval(event: Exercises.Event, signs: PackedInt32Array, x: float, bottom: float, space: float) -> void:
	var lower := event.pitches[0].staff_step(_exercise.clef)
	var upper := event.pitches[1].staff_step(_exercise.clef)
	var upper_x := x + (1.45 * space if upper == lower + 1 else 0.0)
	var ink := note_ink(event.attack)
	_draw_head(x, lower, event.duration, bottom, space, ink)
	_draw_head(upper_x, upper, event.duration, bottom, space, ink)
	if signs[0] != Exercises.NO_SIGN:
		var column := 3.16 if signs[1] != Exercises.NO_SIGN and upper - lower < 7 else 2.15
		_draw_symbol(_accidental(signs[0]), x - column * space, lower, bottom, space)
	if signs[1] != Exercises.NO_SIGN:
		_draw_symbol(_accidental(signs[1]), x - 2.15 * space, upper, bottom, space)


func _draw_head(x: float, step: int, duration: int, bottom: float, space: float, ink: Color) -> void:
	var whole := duration == Exercises.WHOLE
	var ledger_half := (1.13 if whole else 0.88) * space
	for ledger in Notes.ledger_steps(step):
		var y := bottom - ledger * space * 0.5
		draw_line(Vector2(x - ledger_half, y), Vector2(x + ledger_half, y), INK, 2.6 * space / SPACE, true)
	var glyph := "\uE0A4"
	if duration == Exercises.HALF:
		glyph = "\uE0A3"
	elif whole:
		glyph = "\uE0A2"
	_draw_symbol(glyph, x - (0.85 if whole else NOTE_WIDTH * 0.5) * space, step, bottom, space, ink)


func _draw_stem(x: float, step: int, duration: int, bottom: float, space: float, ink: Color) -> void:
	var stem_up := step < STEM_UP_BELOW_STEP
	var direction := -1.0 if stem_up else 1.0
	var width := STEM_THICKNESS * space
	var stem_x := x - direction * (NOTE_WIDTH * space - width) * 0.5
	var y := bottom - step * space * 0.5
	var tip := Vector2(stem_x, y + direction * STEM_LENGTH * space)
	draw_line(Vector2(stem_x, y + direction * 0.168 * space), tip, ink, width, true)
	if duration == Exercises.EIGHTH:
		var flag := "\uE240" if stem_up else "\uE241"
		draw_char(Finish.MUSIC_FONT, tip - Vector2(width * 0.5, 0.0), flag, int(space * 4.0), ink)


func _draw_bar_line(x: float, bottom: float, space: float, final: bool) -> void:
	var top := bottom - 4.0 * space
	var line := maxf(1.0, space * 0.085)
	if final:
		draw_line(Vector2(x - 0.41 * space, bottom), Vector2(x - 0.41 * space, top), INK, line, true)
		x -= 0.10 * space
		line = space * 0.20
	draw_line(Vector2(x, bottom), Vector2(x, top), INK, line, true)


func _draw_symbol(glyph: String, x: float, step: int, bottom: float, space: float, ink := INK) -> void:
	draw_char(Finish.MUSIC_FONT, Vector2(x, bottom - step * space * 0.5), glyph, int(space * 4.0), ink)


static func _accidental(sign: int) -> String:
	return ["\uE260", "\uE261", "\uE262"][sign + 1]
