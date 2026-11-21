extends "res://scripts/piano.gd"

const Chords := preload("res://scripts/chords.gd")
const OCTAVES := 2
const WHITE_COUNT := OCTAVES * Notes.KEY_COUNT
const REPEAT_MS := 200
const WRONG_MS := 250

var _green_keys: Dictionary[int, bool] = {}
var _green_until: Dictionary[int, int] = {}
var _red_until: Dictionary[int, int] = {}


func _ready() -> void:
	super._ready()
	set_process(false)


func mark_correct(key: int) -> void:
	_green_keys[key] = true
	queue_redraw()


func flash_correct(key: int) -> void:
	if not _green_keys.has(key):
		_flash(_green_until, key, REPEAT_MS)


func mark_wrong(key: int) -> void:
	_flash(_red_until, key, WRONG_MS)


func _flash(expiry: Dictionary[int, int], key: int, duration_ms: int) -> void:
	expiry[key] = Time.get_ticks_msec() + duration_ms
	set_process(true)
	queue_redraw()


func clear_feedback() -> void:
	_green_keys.clear()
	_green_until.clear()
	_red_until.clear()
	set_process(false)
	queue_redraw()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for expiry in [_green_until, _red_until]:
		for key in expiry.keys():
			if expiry[key] <= now:
				expiry.erase(key)
				queue_redraw()
	if _green_until.is_empty() and _red_until.is_empty():
		set_process(false)


func _draw() -> void:
	if _white == null or size.x <= GAP * WHITE_COUNT or size.y <= 0.0:
		return
	draw_style_box(_shadow, Rect2(Vector2(-2.0, 2.0), size + Vector2(4.0, 5.0)))
	for index in range(WHITE_COUNT):
		_draw_key(white_rect(index), _key_style(_white_key(index), _white), 12.0, 0.58)
	for octave in range(OCTAVES):
		for index in range(BLACK_BOUNDARIES.size()):
			var boundary: int = octave * Chords.WHITE_PITCHES.size() + BLACK_BOUNDARIES[index]
			var key := _black_key(octave, index)
			_draw_key(black_rect(boundary), _key_style(key, _black), 11.0, 0.14)


func _key_style(key: int, normal: StyleBox) -> StyleBox:
	if _green_keys.has(key) or _green_until.has(key):
		return _green
	if _red_until.has(key):
		return _red
	return normal


func white_rect(index: int) -> Rect2:
	var width := size.x / WHITE_COUNT
	return Rect2(index * width + GAP * 0.5, 0.0, width - GAP, size.y)


func black_rect(boundary: int) -> Rect2:
	var white_width := size.x / WHITE_COUNT
	var black_width := white_width * 0.61
	return Rect2(boundary * white_width - black_width * 0.5, 0.0, black_width, size.y * 0.67)


func key_at(point: Vector2) -> int:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return -1
	for octave in range(OCTAVES):
		for index in range(BLACK_BOUNDARIES.size()):
			var boundary: int = octave * Chords.WHITE_PITCHES.size() + BLACK_BOUNDARIES[index]
			if _black_hit(boundary, point):
				return _black_key(octave, index)
	var index := floori(point.x / (size.x / WHITE_COUNT))
	if _rounded_contains(white_rect(index), WHITE_RADIUS, point):
		return _white_key(index)
	return -1


func _black_hit(boundary: int, point: Vector2) -> bool:
	return _rounded_contains(black_rect(boundary), BLACK_RADIUS, point)


static func _white_key(index: int) -> int:
	@warning_ignore("integer_division")
	var octave := index / Chords.WHITE_PITCHES.size()
	return octave * Chords.PITCH_CLASSES + Chords.WHITE_PITCHES[index % Chords.WHITE_PITCHES.size()]


static func _black_key(octave: int, index: int) -> int:
	return octave * Chords.PITCH_CLASSES + Chords.BLACK_PITCHES[index]
