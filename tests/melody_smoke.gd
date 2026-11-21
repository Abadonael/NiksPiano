extends RefCounted

const Exercises := preload("res://scripts/melody_exercises.gd")
const MelodyGame := preload("res://scripts/melody_game.gd")
const MelodyPiano := preload("res://scripts/melody_piano.gd")
const Settings := preload("res://scripts/settings.gd")
const Notes := preload("res://scripts/notes.gd")
const Chords := preload("res://scripts/chords.gd")
const Finish := preload("res://scripts/finish.gd")
const Theory := preload("res://tests/melody_theory.gd")
const CAPTURES := "res://builds/screenshots/0.5.1"
const RESOLUTIONS := [Vector2i(720, 405), Vector2i(900, 405), Vector2i(1280, 800), Vector2i(1600, 1000)]
const LEVEL_NAMES := ["beginner", "intermediate", "advanced"]
const KIND_NAMES := ["Arpeggio", "Musical phrase", "Harmonic interval"]
const WHITE_PITCHES := Chords.WHITE_PITCHES
const BLACK_PITCHES := Chords.BLACK_PITCHES
const BOUNDARIES := [1, 2, 4, 5, 6]

var _suite: SceneTree
var _root: Window
var _game: MelodyGame
var _piano: MelodyPiano


func run(suite: SceneTree, settings_path: String, screenshots: bool) -> void:
	_suite = suite
	_root = suite.root
	_game = suite.app.get_node("MelodyGame")
	_piano = _game._piano
	Theory.new().run(suite)
	var portrait := _root.size
	var menu: Control = suite.menu
	suite.click(menu._mode_buttons[Settings.Mode.MELODIES].get_global_rect().get_center())
	_check_menu(menu, settings_path)
	if screenshots:
		_expect(DirAccess.make_dir_recursive_absolute(CAPTURES) == OK, "screenshot directory is writable")
		await _capture("melodies-menu")
		_suite.tap(menu._exercise_buttons[Exercises.Kind.INTERVAL].get_global_rect().get_center())
		await _capture("interval-menu")
		_suite.tap(menu._exercise_buttons[Exercises.Kind.PHRASE].get_global_rect().get_center())
	suite.click(menu._start.get_global_rect().get_center())
	await suite.process_frame
	_expect(_game.visible and not menu.visible and _root.size.x > _root.size.y and _game.size.x > _game.size.y,
		"Melodies starts in landscape")
	var short := _game._progress.exercise
	_expect(short.kind == Exercises.Kind.PHRASE and short.difficulty == Exercises.Difficulty.ADVANCED
		and short.clef == Notes.Clef.BASS and short.notes.size() == 4 and _game._symbol.text.is_empty(),
		"Start honors advanced + four notes + bass clef")
	await _check_progress()
	await _check_held_interval()
	_check_pagination()
	if screenshots:
		await _check_landscape()
	suite.click(_game._menu.get_global_rect().get_center())
	await suite.process_frame
	_expect(menu.visible and not _game.visible and _root.size == portrait and suite.app.size.y > suite.app.size.x
		and _game._success.is_stopped() and _game._progress.exercise == null and _game._staff.visible_measures() == Vector2i.ZERO,
		"Melodies restores portrait and clears the pending exercise")
	_suite.tap(menu._difficulty_buttons[0].get_global_rect().get_center())
	_suite.tap(menu._length_buttons[3].get_global_rect().get_center())
	_suite.tap(menu._clef_buttons[0].get_global_rect().get_center())
	_suite.tap(menu._start.get_global_rect().get_center())
	await suite.process_frame
	var long := _game._progress.exercise
	_expect(long.kind == Exercises.Kind.PHRASE and long.difficulty == Exercises.Difficulty.BEGINNER
		and long.clef == Notes.Clef.TREBLE and long.notes.size() == 16
		and long.notes.all(func(note: Exercises.SpelledNote) -> bool: return note.midi % 12 in WHITE_PITCHES),
		"Start honors beginner + sixteen notes + treble clef with white keys")
	_suite.click(_game._menu.get_global_rect().get_center())
	await suite.process_frame


func _check_menu(menu: Control, settings_path: String) -> void:
	var exercises: Array[Button] = menu._exercise_buttons
	var levels: Array[Button] = menu._difficulty_buttons
	var lengths: Array[Button] = menu._length_buttons
	var clefs: Array[Button] = menu._clef_buttons
	_expect(exercises[0].button_pressed and levels[0].button_pressed and lengths[0].button_pressed
		and clefs[0].button_pressed, "Melodies defaults to beginner four-note treble arpeggios")
	for row: Button in exercises + levels + lengths + clefs:
		_expect(row.visible and row.get_rect().end.y < menu._start.position.y
			and row.get_rect().end.x <= menu.size.x, "Melodies options fit above Start")
	for group: Array in [levels, lengths, clefs]:
		for index in range(group.size() - 1):
			_expect(group[index].get_rect().end.x < group[index + 1].position.x, "choices do not overlap")
		for row: Button in group:
			_suite.tap(row.get_global_rect().get_center())
			_suite._check_radio_group(group, row)
	_suite.tap(exercises[2].get_global_rect().get_center())
	_expect(not menu._length_heading.visible and lengths.all(func(row: Button) -> bool: return not row.visible)
		and clefs[1].visible, "only length is hidden for intervals")
	var loaded := Settings.new(settings_path)
	loaded.load_settings()
	_expect(loaded.mode == Settings.Mode.MELODIES and loaded.melody_kind == Exercises.Kind.INTERVAL
		and loaded.melody_difficulty == Exercises.Difficulty.ADVANCED and loaded.melody_length == 24
		and loaded.melody_clef == Notes.Clef.BASS, "all four exercise options persist independently")
	_suite.tap(exercises[1].get_global_rect().get_center())
	_expect(lengths[4].visible and lengths[4].button_pressed, "stored length returns when switching exercise type")
	_suite.tap(lengths[0].get_global_rect().get_center())
	var config := ConfigFile.new()
	config.load(settings_path)
	config.erase_section_key("melodies", "length")
	config.erase_section_key("melodies", "clef")
	config.save(settings_path)
	loaded.load_settings()
	_expect(loaded.melody_kind == Exercises.Kind.PHRASE and loaded.melody_difficulty == Exercises.Difficulty.ADVANCED
		and loaded.melody_length == 4 and loaded.melody_clef == Notes.Clef.TREBLE,
		"0.5.0 settings retain previous selections and get length/clef defaults")
	config.set_value("melodies", "kind", "unrecognized")
	config.set_value("melodies", "difficulty", 3)
	config.set_value("melodies", "length", 7)
	config.set_value("melodies", "clef", "bass")
	config.save(settings_path)
	loaded.load_settings()
	_expect(loaded.melody_kind == Exercises.Kind.ARPEGGIO and loaded.melody_difficulty == Exercises.Difficulty.BEGINNER
		and loaded.melody_length == 4 and loaded.melody_clef == Notes.Clef.TREBLE, "invalid settings recover independently")
	_suite.app.preferences.save()


func _check_progress() -> void:
	var exercise := Exercises.Exercise.new(Exercises.Kind.PHRASE, Exercises.Difficulty.BEGINNER, 4, Notes.Clef.TREBLE)
	var measure := Exercises.Measure.new()
	exercise.measures.append(measure)
	for pitch: Vector2i in [Vector2i(76, 2), Vector2i(76, 2), Vector2i(74, 1), Vector2i(72, 0)]:
		exercise.add_event(measure, Exercises.EIGHTH, [Exercises.SpelledNote.new(pitch.x, pitch.y)])
	exercise.add_event(measure, Exercises.HALF, [])
	_game._show_exercise(exercise)
	var audio := _game.audio
	var repeated := 76
	var neighboring := 74
	var last := 72
	var wrong_octave := 64
	audio.set_enabled(true)
	_suite.note_events.clear()
	_suite.triad_events.clear()
	_expect(_game._staff.note_ink(0) == _game._staff.TARGET_INK and _game._staff.note_ink(1) == _game._staff.INK,
		"first note is active with later notes neutral")
	_suite.tap(_key_point(wrong_octave))
	_expect(_game._progress.completed == 0, "a matching pitch class in the other octave is wrong")
	_suite._touch(_key_point(neighboring), 1, true)
	_expect(_game._progress.completed == 0 and _piano._red_until.has(neighboring - 60)
		and _suite.note_events == [wrong_octave, neighboring],
		"wrong touch sounds and flashes red without moving the staff")
	_suite._touch(_key_point(repeated), 0, true)
	_suite._touch(_key_point(repeated), 0, true)
	_expect(_game._progress.completed == 1 and _suite.note_events == [wrong_octave, neighboring, repeated]
		and _game._staff.note_ink(0) == Finish.SUCCESS_GREEN and _game._staff.note_ink(1) == _game._staff.TARGET_INK,
		"a held touch sounds the written octave once and leaves the completed note green")
	await _suite.create_timer(0.84).timeout
	_expect(_game._progress.exercise == exercise and _game._progress.completed == 1,
		"holding a written eighth note indefinitely never changes progression")
	_suite._touch(_key_point(repeated), 0, false)
	_suite.tap(_key_point(repeated))
	_expect(_game._progress.completed == 2, "a rapid new press can play the same note again")
	_suite._touch(_key_point(neighboring), 1, true)
	_expect(_game._progress.completed == 2, "a held wrong finger cannot advance a later matching note")
	_suite._touch(_key_point(neighboring), 1, false)
	_suite.tap(_key_point(neighboring))
	_suite.tap(_key_point(last))
	_expect(_suite.note_events == [wrong_octave, neighboring, repeated, repeated, neighboring, last]
		and _game._progress.completed == 4
		and _game._staff.note_ink(3) == Finish.SUCCESS_GREEN, "two fingers and rapid taps advance in press order")
	_suite.tap(_key_point(83))
	_expect(_suite.note_events.back() == 83 and _game._progress.completed == 4, "keys still sound during completion")
	await _suite.create_timer(0.42).timeout
	_expect(_game._progress.exercise == exercise and audio._fades.is_empty(), "completion keeps the staff green and sample tails playing")
	await _suite.create_timer(0.45).timeout
	_expect(_game._progress.exercise != exercise and _game._progress.completed == 0
		and _suite.triad_events.is_empty() and audio._fades.is_empty()
		and audio._keys[posmod(audio._next_key - 2, audio.KEY_VOICES)].playing,
		"exercise advances around 800 ms with no triad or sample cutoff")
	_suite.tap(_game._sound.get_global_rect().get_center())
	_expect(not audio.enabled, "Melodies uses the shared sound toggle")
	_suite.note_events.clear()
	_game._show_exercise(exercise)
	for note in exercise.notes:
		_suite.tap(_key_point(note.midi))
	await _suite.create_timer(0.87).timeout
	_expect(_suite.note_events.is_empty() and _game._progress.exercise != exercise, "muted exercise also advances")
	_suite.tap(_game._sound.get_global_rect().get_center())


func _check_held_interval() -> void:
	_game.start(Exercises.Kind.INTERVAL, Exercises.Difficulty.ADVANCED, 24, Notes.Clef.BASS)
	var exercise := _interval(Exercises.Difficulty.ADVANCED, Notes.Clef.BASS, 0)
	_game._show_exercise(exercise)
	var first := exercise.notes[0].midi
	var second := exercise.notes[1].midi
	var wrong := first + 1
	_suite.note_events.clear()
	_suite.tap(_key_point(first))
	_suite.tap(_key_point(second))
	_expect(_game._progress.completed == 0 and _game._interval_answer.text.is_empty()
		and _piano.held_pitches(36).is_empty(), "success and interval name stay hidden after separate taps")
	_suite._touch(_key_point(second), 2, true)
	_suite._touch(_key_point(wrong), 3, true)
	_expect(_game._progress.completed == 0 and _piano._red_until.has(wrong - 36), "wrong held key flashes red")
	_suite._touch(_key_point(wrong), 3, false)
	_suite._touch(_key_point(second), 2, false)
	_suite._touch(_key_point(first), 1, true)
	_suite._touch(_key_point(first), 4, true)
	_suite._touch(_key_point(first), 1, false)
	await _suite.create_timer(0.92).timeout
	_expect(_game._progress.exercise == exercise and _game._progress.completed == 0 and _game._interval_answer.text.is_empty(),
		"holding one pitch has no timing window and never completes")
	_suite._touch(_key_point(second), 2, true)
	_expect(_game._progress.completed == 1 and _game._interval_answer.text == "Увеличенная кварта"
		and _piano._green_keys.has(first - 36) and _piano._green_keys.has(second - 36),
		"both correct held pitches complete the interval and reveal its name")
	_expect(_suite.note_events == [first, second, second, wrong, first, first, second],
		"physical attacks sound the original bass MIDI pitches")
	_suite._touch(_key_point(second), 2, false)
	_suite._touch(_key_point(first), 4, false)
	await _suite.create_timer(0.87).timeout
	_expect(_game._progress.exercise != exercise and _game._progress.exercise.kind == Exercises.Kind.INTERVAL
		and _game._progress.exercise.clef == Notes.Clef.BASS and _game._progress.completed == 0 and _game._interval_answer.text.is_empty(),
		"interval rotates automatically and hides the next name")


func _check_pagination() -> void:
	var exercise := _phrase(Exercises.Difficulty.BEGINNER, 24, Notes.Clef.TREBLE, 0, 0)
	_game._show_exercise(exercise)
	var page := _game._staff.visible_measures()
	var first_page := page
	_expect(page.x == 0 and page.y < exercise.measures.size(), "long exercise starts with whole measures on the first page")
	var audio_enabled := _game.audio.enabled
	_game.audio.set_enabled(false)
	for index in range(exercise.notes.size()):
		var measure := index >> 2
		_expect(measure >= page.x and measure < page.y, "the current attack is on the visible page")
		_suite.tap(_key_point(exercise.notes[index].midi))
		page = _game._staff.visible_measures()
	_expect(page.x > first_page.x and page.y == exercise.measures.size() and _game._progress.completed == 24,
		"all 24 attacks advance through the final page without an interruption")
	_game._success.stop()
	_game.audio.set_enabled(audio_enabled)


func _check_landscape() -> void:
	var samples := {
		"beginner-12-phrase": _phrase(0, 12, Notes.Clef.TREBLE, 0, 1),
		"beginner-24-phrase": _phrase(0, 24, Notes.Clef.TREBLE, 0, 0),
		"intermediate-g-major": _phrase(1, 12, Notes.Clef.TREBLE, 0, 2),
		"advanced-d-major": _phrase(2, 16, Notes.Clef.TREBLE, 0, 1),
		"beginner-arpeggio": _arpeggio(0, 16, Notes.Clef.TREBLE, "C"),
		"advanced-arpeggio": _arpeggio(2, 16, Notes.Clef.TREBLE, "F#"),
		"bass-clef-phrase": _phrase(1, 12, Notes.Clef.BASS, 1, 2),
		"treble-harmonic-interval": _interval(1, Notes.Clef.TREBLE, 1),
		"bass-harmonic-interval": _interval(2, Notes.Clef.BASS, 2),
	}
	_export_samples(samples)
	for resolution: Vector2i in RESOLUTIONS:
		_root.size = resolution
		await _suite.process_frame
		_expect(_root.size == resolution, "graphical window uses the requested resolution")
		_check_touch_targets()
		_print_metrics()
		for label: String in samples:
			var exercise: Exercises.Exercise = samples[label]
			_game._show_exercise(exercise)
			var space := _game._staff.staff_space() * _root.get_final_transform().x.length()
			_expect(space >= 11.0, "readable staff spacing for %s at %s" % [label, resolution])
			await _capture(label)
			if label == "beginner-24-phrase" or label == "advanced-d-major":
				# Show the last bar and verify its repeat clef/key context and final double bar.
				_game._staff.show_progress(exercise.attack_count - 1)
				var page := _game._staff.visible_measures()
				_expect(page.x > 0 and page.y == exercise.measures.size(), "long exercise ends on the final page")
				await _capture(label + "-last-page")
			if label == "beginner-24-phrase" and resolution == RESOLUTIONS[0]:
				_game._staff.show_progress(8)
				await _capture("quarter-rest-and-eighths")
				_game._staff.show_progress(16)
				await _capture("half-rest-and-eighths")
		if resolution == RESOLUTIONS[0]:
			var interval: Exercises.Exercise = samples["bass-harmonic-interval"]
			_game._show_exercise(interval)
			_suite._touch(_key_point(interval.notes[0].midi), 0, true)
			_suite._touch(_key_point(interval.notes[1].midi), 1, true)
			await _capture("bass-interval-answer")
			_suite._touch(_key_point(interval.notes[0].midi), 0, false)
			_suite._touch(_key_point(interval.notes[1].midi), 1, false)
			_game._success.stop()


func _export_samples(captures: Dictionary) -> void:
	var path := "res://builds/0.5.1-exercise-examples.md"
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "human-readable exercise examples are writable")
	if file == null:
		return
	file.store_string("# Niks Piano 0.5.1 exercise examples\n\n")
	file.store_string("Pitch names use C4 for MIDI 60. Durations are shown after each event. Parentheses group pitches played together. Vertical bars divide measures. Natural-minor phrases use the unaltered scale. Patterns are original to Niks Piano.\n\n")
	for label: String in captures:
		_write_example(file, label.replace("-", " ").capitalize(), captures[label])
	_write_example(file, "Beginner 16-note C-major phrase", _phrase(0, 16, Notes.Clef.TREBLE, 0, 0))
	_write_example(file, "Advanced four-note D-major bass phrase", _phrase(2, 4, Notes.Clef.BASS, 0, 0))
	seed(50112)
	var generator := Exercises.new()
	for clef: Notes.Clef in Notes.Clef.values():
		for level: Exercises.Difficulty in Exercises.Difficulty.values():
			for kind: Exercises.Kind in Exercises.Kind.values():
				var length: int = [16, 12, 4][level]
				var exercise := generator.next(kind, level, length, clef)
				var title := "%s %s %s" % ["Treble" if clef == Notes.Clef.TREBLE else "Bass", LEVEL_NAMES[level], KIND_NAMES[kind].to_lower()]
				_write_example(file, title, exercise)


func _write_example(file: FileAccess, title: String, exercise: Exercises.Exercise) -> void:
	var harmony := exercise.chord_symbol
	if exercise.kind == Exercises.Kind.PHRASE:
		harmony = "%s %s" % [exercise.key_name.replace("b", "♭"), "natural minor" if exercise.natural_minor else "major"]
	elif exercise.kind == Exercises.Kind.INTERVAL:
		harmony = exercise.interval_name
	var accidental := "no key signature"
	if exercise.kind == Exercises.Kind.PHRASE:
		accidental = "key signature without sharps or flats"
	if exercise.key_signature != 0:
		var count := absi(exercise.key_signature)
		var sign := "sharp" if exercise.key_signature > 0 else "flat"
		accidental = "key signature with %d %s%s" % [count, sign, "s" if count > 1 else ""]
	file.store_string("## %s\n\n" % title)
	file.store_string("%s · %s · %s · 4/4 · %s · %d physical note %s · %s\n\n" % [
		"Treble" if exercise.clef == Notes.Clef.TREBLE else "Bass", LEVEL_NAMES[exercise.difficulty].capitalize(),
		harmony, accidental, exercise.notes.size(), "presses together" if exercise.kind == Exercises.Kind.INTERVAL else "attacks",
		exercise.template_id])
	var measures := PackedStringArray()
	var midi := PackedStringArray()
	for measure in exercise.measures:
		var events := PackedStringArray()
		for event in measure.events:
			var pitches := PackedStringArray()
			for note in event.pitches:
				pitches.append(note.written_name())
				midi.append(str(note.midi))
			var text := "rest" if pitches.is_empty() else pitches[0]
			if pitches.size() == 2:
				text = "(%s)" % "+".join(pitches)
			events.append("%s %s" % [text, {1: "⅛", 2: "¼", 4: "½", 8: "whole"}[event.duration]])
		measures.append(" · ".join(events))
	file.store_string("**Measures** %s\n\n**MIDI** %s\n\n" % [" | ".join(measures), " ".join(midi)])


static func _phrase(level: Exercises.Difficulty, length: int, clef: Notes.Clef, key: int, variation: int) -> Exercises.Exercise:
	var exercise := Exercises.Exercise.new(Exercises.Kind.PHRASE, level, length, clef)
	Exercises._make_phrase(exercise, Exercises.KEYS[level][key], variation)
	return exercise


static func _arpeggio(level: Exercises.Difficulty, length: int, clef: Notes.Clef, symbol: String) -> Exercises.Exercise:
	var exercise := Exercises.Exercise.new(Exercises.Kind.ARPEGGIO, level, length, clef)
	Exercises._make_arpeggio(exercise, Chords.Triad.new(symbol, Chords._root_pitch(symbol)))
	return exercise


static func _interval(level: Exercises.Difficulty, clef: Notes.Clef, pattern: int) -> Exercises.Exercise:
	var exercise := Exercises.Exercise.new(Exercises.Kind.INTERVAL, level, 4, clef)
	Exercises._make_interval(exercise, pattern)
	return exercise


func _check_touch_targets() -> void:
	for octave in range(2):
		for index in range(7):
			var white := _piano.white_rect(index + 7 * octave)
			var key: int = WHITE_PITCHES[index] + 12 * octave
			_expect(_piano.key_at(Vector2(white.get_center().x, white.size.y * 0.3)) == key
				and _piano.key_at(Vector2(white.get_center().x, white.size.y * 0.82)) == key,
				"white key center is reachable above and below black key tips")
		for index in range(5):
			var boundary: int = BOUNDARIES[index] + 7 * octave
			var touch := _piano.black_touch_rect(boundary)
			var face := _piano.black_rect(boundary)
			var key: int = BLACK_PITCHES[index] + 12 * octave
			_expect(touch.encloses(face) and touch.size.x > face.size.x, "black hit box covers its visible key and touch halo")
			for x in [touch.position.x + 0.1, touch.get_center().x, touch.end.x - 0.1]:
				_expect(_piano.key_at(Vector2(x, touch.size.y * 0.5)) == key, "black hit box takes priority over underlying whites")
				_expect(_piano.key_at(Vector2(x, touch.end.y + 15.0)) != key, "black hit box ends at its visible tip")
	_expect(_piano.key_at(Vector2(-1.0, 50.0)) == -1 and _piano.key_at(Vector2(_piano.size.x, 50.0)) == -1,
		"touches outside the keyboard are ignored")
	var white_span := _piano.size.x / 14.0
	_piano.fit_black_touch_width(0.88 * white_span)
	_expect(is_equal_approx(_piano.black_touch_rect(1).size.x, 0.88 * white_span)
		and _piano.key_at(Vector2(white_span * 1.5, 30.0)) == 2, "density adjustment widens black hit boxes without reaching white centers")
	_piano.fit_black_touch_width(0.0)


func _print_metrics() -> void:
	var scale := _root.get_final_transform().get_scale()
	var white := _piano.white_rect(0).size * scale
	var black := _piano.black_rect(1).size * scale
	var touch := _piano.black_touch_rect(1).size * scale
	var staff := _game._staff.size.y * scale.y
	_expect(touch.x >= 40.0 and white.y / _root.size.y >= 0.64, "phone layout preserves touch width and keyboard height")
	print("Melodies %sx%s px: white %.1fx%.1f, black %.1fx%.1f, black hit %.1fx%.1f, staff %.1f, piano %.1f"
		% [_root.size.x, _root.size.y, white.x, white.y, black.x, black.y, touch.x, touch.y, staff, white.y])


func _key_point(midi: int) -> Vector2:
	return _suite._chord_key_point(_piano, midi - Exercises.first_midi(_game._progress.exercise.clef))


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := _root.get_texture().get_image()
	var path := CAPTURES.path_join("%sx%s-%s.png" % [_root.size.x, _root.size.y, label])
	_expect(image != null and image.get_size() == _root.size and image.save_png(path) == OK, "captured " + path)
	if image != null and _game.visible:
		var staff: Rect2 = _root.get_final_transform() * _game._staff.get_global_rect()
		var box := Rect2i(Vector2i(staff.position.ceil()), Vector2i(staff.end.floor() - staff.position.ceil()))
		var clear := true
		for x in range(box.position.x, box.end.x):
			clear = clear and image.get_pixel(x, box.position.y).r < 0.45 and image.get_pixel(x, box.end.y - 1).r < 0.45
		for y in range(box.position.y, box.end.y):
			clear = clear and image.get_pixel(box.position.x, y).r < 0.45 and image.get_pixel(box.end.x - 1, y).r < 0.45
		_expect(clear, "notation remains inside its panel in " + label)
		if label != "bass-interval-answer":
			_expect(_has_active_ink(image, box), "active notehead renders in " + label)
		if label in ["quarter-rest-and-eighths", "half-rest-and-eighths"]:
			_expect(_has_rest_ink(image, box), "rest glyph renders separately from the staff in " + label)


static func _has_active_ink(image: Image, box: Rect2i) -> bool:
	for y in range(box.position.y, box.end.y, 3):
		for x in range(box.position.x, box.end.x, 3):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.80 and pixel.g > 0.60 and pixel.b < 0.65:
				return true
	return false


func _has_rest_ink(image: Image, box: Rect2i) -> bool:
	var staff := _game._staff
	var scale := _root.get_final_transform().x.length()
	var space := staff.staff_space() * scale
	var page := staff.visible_measures()
	var width := (staff._header_width() + (page.y - page.x) * staff._bar_width()) * space
	var right := box.get_center().x + width * 0.5
	var bottom := box.position.y + (staff.size.y * scale + (staff._rise - staff._drop) * space) * 0.5
	for y in range(ceili(bottom - 3.4 * space), floori(bottom - 0.6 * space)):
		var lines := (bottom - y) / space
		if absf(lines - roundf(lines)) * space < 2.0:
			continue
		for x in range(ceili(right - 3.2 * space), floori(right - 0.9 * space)):
			if image.get_pixel(x, y).r > 0.75:
				return true
	return false


func _expect(condition: bool, message: String) -> void:
	_suite.expect(condition, message)
