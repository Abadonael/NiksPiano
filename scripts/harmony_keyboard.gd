extends "res://scripts/free_keyboard.gd"

var selected: Array[int] = []
var octave := 4


func _ready() -> void:
	super._ready()
	locked = false
	resized.connect(_fit)
	set_octave(octave)


func set_octave(value: int) -> void:
	octave = clampi(value, 1, 7)
	var first := PianoAudio.FREE_LOWEST if octave == 1 else 12 * (octave + 1)
	var last := PianoAudio.FREE_HIGHEST if octave == 7 else first + (14 if octave == 1 else 11)
	white_keys.clear()
	black_keys.clear()
	for midi in range(first, last + 1):
		if midi % 12 in Chords.WHITE_PITCHES:
			white_keys.append(midi)
		else:
			black_keys[white_keys.size()] = midi
	_fit()


func _fit() -> void:
	key_width = maxf(1.0, size.x / white_keys.size())
	queue_redraw()


func _draw() -> void:
	super._draw()
	for index in range(white_keys.size()):
		if white_keys[index] in selected:
			_mark(white_rect(index), 0.83)
	for boundary in black_keys:
		if black_keys[boundary] in selected:
			_mark(black_rect(boundary), 0.74)


func _mark(rect: Rect2, vertical: float) -> void:
	var center := Vector2(rect.get_center().x, rect.size.y * vertical)
	draw_circle(center, minf(rect.size.x * 0.24, 16.0), C4_MARKER_COLOR, true, -1.0, true)
