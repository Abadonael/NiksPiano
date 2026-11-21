extends Control

const Notes := preload("res://scripts/notes.gd")
const Finish := preload("res://scripts/finish.gd")
const SPACE := 32.0
const NOTE_WIDTH := 1.18
const STEM_THICKNESS := 0.12
const STEM_LENGTH := 3.5
const STEM_UP_BELOW_STEP := 4
const INK := Color("#f5f6f9")
const ERROR_INK := Color("#ff6068")

var range_index := 0
var target := 0
var mistake := -1
var target_ink := INK


func show_note(new_range: int, pitch_class: int) -> void:
	range_index = new_range
	target = pitch_class
	mistake = -1
	target_ink = INK
	queue_redraw()


func show_answer(pitch_class: int, correct: bool) -> void:
	mistake = -1 if correct else pitch_class
	target_ink = Finish.SUCCESS_GREEN if correct else INK
	queue_redraw()


func _draw() -> void:
	var left := 50.0
	var right := size.x - left
	var treble: bool = Notes.RANGES[range_index].clef == Notes.Clef.TREBLE
	_draw_staff(left, right, left + 22.0, _step_y(0), SPACE, treble)

	var target_x := lerpf(left, right, 0.63)
	_draw_note(target_x, Notes.staff_step(range_index, target), target_ink, false)
	if mistake >= 0:
		_draw_note(target_x + 2.25 * SPACE, Notes.staff_step(range_index, mistake), ERROR_INK, true)


func _step_y(step: int) -> float:
	return size.y - 34.0 - float(step) * SPACE / 2.0


func _draw_note(x: float, step: int, ink: Color, outlined: bool) -> void:
	_draw_note_at(x, step, ink, outlined, _step_y(0), SPACE)


func _draw_staff(left: float, right: float, clef_x: float, bottom: float, space: float, treble: bool) -> void:
	for step in range(0, 9, 2):
		var y := bottom - step * space * 0.5
		draw_line(Vector2(left, y), Vector2(right, y), INK, 2.2 * space / SPACE, true)
	var clef := "\uE050" if treble else "\uE062"
	var clef_step := 2 if treble else 6
	# SMuFL clefs sit on the line of their named pitch. One em is four spaces.
	draw_char(Finish.MUSIC_FONT, Vector2(clef_x, bottom - clef_step * space * 0.5), clef, int(space * 4.0), INK)


func _draw_note_at(x: float, step: int, ink: Color, outlined: bool, bottom: float, space: float, accidental := 0) -> void:
	var ledger_ink := ERROR_INK if outlined else INK
	for ledger in Notes.ledger_steps(step):
		var y := bottom - ledger * space * 0.5
		draw_line(Vector2(x - space * 0.88, y), Vector2(x + space * 0.88, y), ledger_ink, 2.6 * space / SPACE, true)

	var baseline := bottom - step * space * 0.5
	var left := x - space * NOTE_WIDTH * 0.5
	var stem_width := space * STEM_THICKNESS
	var stem_up := step < STEM_UP_BELOW_STEP
	var direction := -1.0 if stem_up else 1.0
	# Both Bravura noteheads share the same stem anchors in staff spaces.
	var stem_x := left + space * NOTE_WIDTH - stem_width * 0.5 if stem_up else left + stem_width * 0.5
	var root_y := baseline + direction * 0.168 * space
	var end_y := baseline + direction * STEM_LENGTH * space
	draw_line(Vector2(stem_x, root_y), Vector2(stem_x, end_y), ink, stem_width, true)
	var glyph := "\uE0A3" if outlined else "\uE0A4"
	draw_char(Finish.MUSIC_FONT, Vector2(left, baseline), glyph, int(space * 4.0), ink)
	if accidental != 0:
		var sign := "\uE262" if accidental > 0 else "\uE260"
		draw_char(Finish.MUSIC_FONT, Vector2(x - 2.05 * space, baseline), sign, int(space * 4.0), INK)
