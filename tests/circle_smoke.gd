extends SceneTree

const Main := preload("res://main.tscn")
const Settings := preload("res://scripts/settings.gd")
const Explorer := preload("res://scripts/circle_explorer.gd")
const Practice := preload("res://scripts/circle_practice.gd")
const TheoryChecks := preload("res://tests/circle_theory.gd")
const Piano := preload("res://scripts/chord_piano.gd")
const Chords := preload("res://scripts/chords.gd")
const Finish := preload("res://scripts/finish.gd")
const Theory := preload("res://scripts/key_theory.gd")
const OUTPUT := "res://builds/screenshots/0.7.2-regression/circle"

var failures := 0
var _headless: bool
var _run_id: String
var _app: Control
var _wheel_page: Explorer
var _practice: Practice
var _notes: Array[int] = []
var _triads: Array[Array] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		root.size = Vector2i(405, 720)
	_run_id = "%sx%s" % [root.size.x, root.size.y]
	var settings_path := "res://.godot/checks/circle/settings-%s-%s.cfg" % [_run_id, "headless" if _headless else "gui"]
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(settings_path)
	if not _headless:
		DirAccess.make_dir_recursive_absolute(OUTPUT)
		var marker := FileAccess.open(OUTPUT.path_join(".gdignore"), FileAccess.WRITE)
		marker.close()
	TheoryChecks.new().run(self)
	_app = Main.instantiate()
	_app.preferences = Settings.new(settings_path)
	root.add_child(_app)
	await _settle()
	_wheel_page = _app.get_node("CircleExplorer")
	_practice = _app.get_node("CirclePractice")
	_app._audio.note_started.connect(func(midi: int) -> void: _notes.append(midi))
	_app._audio.triad_started.connect(func(notes: Array[int]) -> void: _triads.append(notes))
	var menu: Control = _app._menu
	await _open_circle()
	await _settle()
	expect(_wheel_page.visible and not menu.visible and root.size.y > root.size.x, "menu opens the circle in portrait")
	expect(_wheel_page._title.text == "C major — До мажор" and _wheel_page._main_chords.text.contains("IV  F"),
		"C displays its tonic and main chords")
	_check_wheel_layout()
	await _capture("01-wheel-C")
	for sector in range(12):
		_sector_touch(sector, 0.82 if sector % 2 == 0 else 0.53)
		expect(_app.preferences.circle_sector == sector, "touch selects wheel sector %d in either ring" % sector)
	await _capture("03-wheel-F")
	_sector_touch(1)
	await _capture("02-wheel-G")
	_sector_touch(6)
	await _capture("04-wheel-F-sharp")
	_press(_wheel_page._enharmonic)
	await _settle()
	expect(_wheel_page._scale.text.contains("C♭") and _wheel_page._relative.text.contains("E♭ minor"),
		"enharmonic switch updates written pitches and relative minor")
	_check_wheel_layout()
	await _capture("05-wheel-G-flat")
	await _check_written_scale(-6, 3, "C♭5", "10-scale-G-flat")
	var persisted := Settings.new(settings_path)
	persisted.load_settings()
	expect(persisted.circle_sector == 6 and persisted.circle_flats and persisted.mode == Settings.Mode.CIRCLE,
		"selected sector, notation and mode persist")
	_press(_button_in(_wheel_page._content, "Сравнить тональности"))
	await _settle()
	_press(_button_in(_wheel_page._dialog_body, "↶  Против часовой"))
	await _settle()
	expect(_dialog_text().contains("Смена записи") and _dialog_text().contains("F → E"),
		"enharmonic boundary comparison separates notation from sounding difference")
	await _capture("09-comparison-enharmonic")
	_app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	expect(_wheel_page.visible and not _wheel_page._shade.visible, "system back closes the contextual detail")

	_sector_touch(0)
	_press(_button_in(_wheel_page._content, "Все трезвучия"))
	await _settle()
	expect(_dialog_text().contains("vii°") and _dialog_text().contains("Bdim"), "all triads include the diminished seventh degree")
	_press(_button_in(_wheel_page._dialog_body, "Закрыть"))
	_press(_wheel_page._content.get_child(0).get_node("Information"))
	await _settle()
	expect(_dialog_text().contains("семь полутонов"), "first lesson explains fifths")
	for index in range(6):
		_press(_button_in(_wheel_page._dialog_body, "Далее"))
		await _settle()
	expect(_dialog_text().contains("Энгармоническая запись"), "all seven lessons are navigable")
	_press(_button_in(_wheel_page._dialog_body, "Закрыть"))
	await _check_scale()
	await _check_chords(["C", "F", "G", "C"], true)

	_press(_button_in(_wheel_page._content, "Сравнить тональности"))
	await _settle()
	expect(_dialog_text().contains("B → B♭") and _dialog_text().contains("Новый ключевой знак: B♭"), "C to F shows the new flat")
	_press(_button_in(_wheel_page._dialog_body, "↻  По часовой"))
	await _settle()
	expect(_dialog_text().contains("F → F♯") and _dialog_text().contains("Общие звуки: 6 из 7"), "C to G shows the new sharp")
	await _capture("08-comparison-C-G")
	_press(_button_in(_wheel_page._dialog_body, "Выбрать G major"))
	expect(_app.preferences.circle_sector == 1, "comparison can open the neighboring key")
	await _check_written_scale(1, 6, "F♯5", "11-scale-G")
	await _check_chords(["G", "C", "D", "G"], false)
	_app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	expect(menu.visible and not _wheel_page.visible and root.size == Vector2i(_run_id.split("x")[0].to_int(), _run_id.split("x")[1].to_int()),
		"system back returns to the menu and restores the portrait window")
	await _open_circle()
	expect(_wheel_page._title.text.begins_with("G major") and _app.preferences.circle_flats, "reopening retains selection and enharmonic preference")
	_press(_wheel_page._content.get_child(0).get_node("BackToMenu"))
	expect(menu.visible, "menu button returns to main menu")
	persisted.load_settings()
	expect(not persisted.sound_enabled and persisted.circle_sector == 1, "sound and new selection survive reload")
	await _check_minor(settings_path)
	print("Circle checks (%s, %s): %d failure(s)" % [_run_id, "headless" if _headless else "graphics", failures])
	quit(0 if failures == 0 else 1)


func _check_minor(settings_path: String) -> void:
	await _open_circle()
	await _settle()
	for sector in range(12):
		_sector_touch(sector, 0.53)
		expect(_app.preferences.circle_sector == sector and _app.preferences.circle_minor and
			_wheel_page._key.minor and _wheel_page._wheel._minor, "inner touch selects minor sector %d" % sector)
		_sector_touch(sector, 0.83)
		expect(_app.preferences.circle_sector == sector and not _app.preferences.circle_minor and
			not _wheel_page._key.minor and not _wheel_page._wheel._minor, "outer touch selects major sector %d" % sector)
	_sector_touch(0, 0.70)
	expect(_wheel_page._key.short_name() == "C major", "touch just outside ring divider selects major")
	_sector_touch(0, 0.66)
	expect(_wheel_page._key.short_name() == "A minor", "touch just inside ring divider selects minor")
	_sector_touch(1, 0.0)
	_sector_touch(0, 1.01)
	expect(_wheel_page._key.short_name() == "A minor" and _app.preferences.circle_sector == 0,
		"center hole and outside edge leave selection unchanged")
	expect(_wheel_page._title.text == "A minor — Ля минор" and _wheel_page._relative.text.contains("C major") and
		_wheel_page._scale.text.ends_with("A  B  C  D  E  F  G") and _wheel_page._signature.text.ends_with("нет")
		and _wheel_page._main_chords.text.contains("V — E") and _wheel_page._dominant.text.contains("E–G♯–B"),
		"minor card distinguishes natural scale, key signature, and major dominant")
	await _settle()
	_check_wheel_layout()
	await _capture("minor-01-wheel-A")
	_sector_touch(1, 0.53)
	await _settle()
	await _capture("minor-02-wheel-E")
	_sector_touch(0, 0.53)
	await _settle()

	_press(_button_in(_wheel_page._content, "Все трезвучия"))
	await _settle()
	expect(_dialog_text().contains("Bdim") and _dialog_text().contains("Em") and not _dialog_text().contains("Caug"),
		"minor table starts with natural-minor triads")
	_check_dialog_layout()
	await _capture("minor-03-triads-natural-A")
	_press(_button_in(_wheel_page._dialog_body, "Гармонический"))
	await _settle()
	expect(_dialog_text().contains("III+") and _dialog_text().contains("Caug") and _dialog_text().contains("G♯dim"),
		"harmonic table shows augmented and leading-tone diminished triads")
	_check_dialog_layout()
	await _capture("minor-04-triads-harmonic-A")
	expect(_wheel_page.close_detail(), "triads close")

	_press(_button_in(_wheel_page._content, "Сравнить тональности"))
	await _settle()
	_press(_button_in(_wheel_page._dialog_body, "↻  По часовой"))
	await _settle()
	expect(_dialog_text().contains("A minor → E minor") and _dialog_text().contains("F → F♯") and
		_dialog_text().contains("Общие звуки: 6 из 7"), "minor neighbors compare natural scales and one changed pitch")
	_check_dialog_layout()
	await _capture("minor-05-comparison-A-E")
	_press(_button_in(_wheel_page._dialog_body, "Параллельный мажор"))
	await _settle()
	expect(_dialog_text().contains("A minor ↔ C major") and _dialog_text().contains("Общие звуки: 7 из 7") and
		_dialog_text().contains("Одинаковые ключевые знаки") and _dialog_text().contains("разные тоники") and
		not _dialog_text().contains("Изменение"), "relative comparison shows seven pitches, one signature and two tonics")
	_check_dialog_layout()
	await _capture("minor-06-comparison-A-C")
	expect(_wheel_page.close_detail(), "comparison closes")

	_press(_wheel_page._content.get_child(0).get_node("Information"))
	await _settle()
	expect(_dialog_text().contains("C major и A minor"), "minor lessons use the selected relative pair")
	for index in range(6):
		_press(_button_in(_wheel_page._dialog_body, "Далее"))
		await _settle()
		_check_dialog_layout()
	expect(_dialog_text().contains("Тональный центр"), "all seven minor lessons are navigable")
	expect(_wheel_page.close_detail(), "minor lessons close")
	await _check_minor_scales()
	await _check_chords(["Am", "Dm", "E", "Am"], false, true)

	_sector_touch(6, 0.53)
	await _settle()
	expect(_wheel_page._key.short_name() == "E♭ minor", "inner shared sector uses the remembered flat spelling")
	_check_wheel_layout()
	await _capture("minor-07-wheel-E-flat")
	await _check_shared_minor_score(-6, "D5", "E-flat")
	_press(_wheel_page._enharmonic)
	await _settle()
	expect(_wheel_page._key.short_name() == "D♯ minor" and _wheel_page._relative.text.contains("F♯ major") and
		_wheel_page._dominant.text.contains("C𝄪"), "switching spelling updates the inner tonic, relative major, and dominant")
	_check_wheel_layout()
	await _capture("minor-08-wheel-D-sharp")
	await _check_shared_minor_score(6, "C𝄪5", "D-sharp")
	_press(_wheel_page._enharmonic)
	await _settle()
	_app.free()
	_app = Main.instantiate()
	_app.preferences = Settings.new(settings_path)
	root.add_child(_app)
	await _settle()
	_wheel_page = _app.get_node("CircleExplorer")
	_practice = _app.get_node("CirclePractice")
	await _open_circle()
	await _settle()
	expect(_wheel_page.visible and _wheel_page._key.short_name() == "E♭ minor" and _app.preferences.circle_flats
		and _app.preferences.circle_minor and _app.preferences.circle_sector == 6,
		"fresh app instance reloads the selected minor sector and enharmonic spelling from disk")
	_sector_touch(0)
	await _settle()
	expect(_wheel_page._key.short_name() == "C major" and not _wheel_page._dominant.visible,
		"outer-ring selection restores major card")
	_press(_button_in(_wheel_page._content, "Сыграть гамму"))
	await _settle()
	expect(not _practice._form_picker.visible and _practice._scale.exercise.key_name == "C" and
		_practice._scale.exercise.notes[2].midi == 64, "switching back to major restores major exercise")


func _check_minor_scales() -> void:
	_press(_button_in(_wheel_page._content, "Сыграть гамму"))
	await _settle()
	expect(_practice._key.short_name() == "A minor" and _practice._form_picker.visible and
		_practice._natural_button.button_pressed, "minor scale opens with its selected key and defaults to natural")
	_check_practice_layout(_practice._scale_piano)
	await _capture("minor-scale-A-natural")
	_play_minor_scale([69, 71, 72, 74, 76, 77, 79, 81, 79, 77, 76, 74, 72, 71, 69])
	_press(_button_in(_practice._form_picker, "Гармонический"))
	await _settle()
	expect(_practice._scale.completed == 0 and _practice._staff.visible_measures() == Vector2i(0, 4)
		and _practice._status.text.contains("G → G♯"), "changing form resets progress and explains the leading tone")
	await _capture("minor-scale-A-harmonic")
	_play_minor_scale([69, 71, 72, 74, 76, 77, 80, 81, 80, 77, 76, 74, 72, 71, 69])
	_press(_practice._action)
	expect(_practice._scale.completed == 0 and _practice._scale.exercise.notes[6].midi == 80,
		"replay keeps the selected harmonic scale")
	_press(_practice._menu)
	await _settle()
	expect(_wheel_page.visible and _wheel_page._key.short_name() == "A minor", "back from scale restores minor selection")


func _play_minor_scale(pitches: Array[int]) -> void:
	for midi in pitches:
		_piano_key(_practice._scale_piano, midi)
	expect(_practice._scale.completed == pitches.size() and _practice._status.text == "Гамма сыграна",
		"both directions accept the expected written MIDI sequence")


func _check_shared_minor_score(signature: int, leading_tone: String, label: String) -> void:
	_press(_button_in(_wheel_page._content, "Сыграть гамму"))
	await _settle()
	expect(_practice._natural_button.button_pressed and not _button_in(_practice._form_picker, "Гармонический").button_pressed,
		"each new scale starts in natural minor")
	_press(_button_in(_practice._form_picker, "Гармонический"))
	await _settle()
	var score := _practice._scale.exercise
	expect(score.key_signature == signature and score.notes[6].written_name() == leading_tone
		and score.notes[8].written_name() == leading_tone and _practice._staff.visible_measures() == Vector2i(0, 4),
		"enharmonic harmonic scale renders the correct signature and leading tone in both directions")
	await _capture("minor-scale-%s-harmonic" % label)
	_press(_practice._menu)
	await _settle()
	_press(_button_in(_wheel_page._content, "Сыграть аккорды"))
	await _settle()
	for index in range(2):
		for note in _practice._scores[index].notes:
			_piano_key(_practice._piano, note.midi)
		await create_timer(0.52).timeout
	expect(_practice._chord_index == 2 and _practice._staff._exercise.notes[1].written_name() == leading_tone,
		"enharmonic dominant shows its correctly spelled third on the staff")
	await _capture("minor-progression-%s-V" % label)
	_press(_practice._menu)
	await _settle()


func _check_scale() -> void:
	_press(_button_in(_wheel_page._content, "Сыграть гамму"))
	await _settle()
	expect(_practice.visible and not _wheel_page.visible and root.size.x > root.size.y, "scale practice opens in landscape")
	expect(_practice._staff.visible_measures() == Vector2i(0, 4), "full ascending and descending score is visible")
	_check_practice_layout(_practice._scale_piano)
	await _capture("06-scale-C")
	_press(_practice._action)
	await create_timer(Practice.PREVIEW_STEP + 0.12).timeout
	expect(_notes.slice(-2) == [60, 62] and _practice._scale.completed == 0, "preview plays ordered MIDI without grading")
	_press(_practice._sound)
	expect(not _app._audio.enabled and _practice._preview.is_stopped() and _practice._action.disabled,
		"sound control cancels preview and disables Listen")
	_press(_practice._sound)
	_piano_key(_practice._scale_piano, 62)
	expect(_practice._scale.completed == 0, "out-of-order scale input does not advance")
	var score := _practice._scale.exercise
	for index in range(score.notes.size()):
		_piano_key(_practice._scale_piano, score.notes[index].midi)
		if index == 0:
			await create_timer(0.55).timeout
		expect(_practice._scale.completed == index + 1, "piano input advances only by written pitch order")
	expect(_practice._staff.note_ink(14) == Finish.SUCCESS_GREEN and _practice._action.text == "Повторить"
		and _practice._status.text == "Гамма сыграна", "scale completion remains visible until replay")
	_press(_practice._action)
	expect(_practice._scale.exercise == score and _practice._scale.completed == 0, "replay resets the same exercise")
	_press(_practice._menu)
	await _settle()
	expect(_wheel_page.visible and not _practice.visible and root.size.y > root.size.x, "scale back returns to original portrait selection")


func _check_written_scale(signature: int, index: int, written: String, label: String) -> void:
	_press(_button_in(_wheel_page._content, "Сыграть гамму"))
	await _settle()
	var score := _practice._scale.exercise
	expect(_practice._staff._exercise == score and score.key_signature == signature and
		score.notes[index].written_name() == written, "staff uses the selected signature and its written pitch")
	expect(_practice._staff.visible_measures() == Vector2i(0, 4), "signed scale fits in the landscape staff")
	await _capture(label)
	_press(_practice._menu)
	await _settle()


func _check_chords(symbols: Array[String], hear_first: bool, minor := false) -> void:
	_press(_button_in(_wheel_page._content, "Сыграть аккорды"))
	await _settle()
	expect(_practice.visible and root.size.x > root.size.y, "progression opens in landscape")
	_check_practice_layout(_practice._piano)
	if minor:
		await _capture("minor-progression-A-i")
	elif hear_first:
		await _capture("07-progression-C")
	else:
		await _capture("12-progression-G")
	for index in range(symbols.size()):
		var score := _practice._scores[index]
		expect(_practice._chord_index == index and score.chord_symbol == symbols[index] and
			_practice._symbol.text.contains("%d / 4" % (index + 1)), "progression shows the correct chord and index")
		if minor and index == 2:
			expect(_practice._status.text.contains("G♯ тяготеет к A") and _practice._status.text.contains("Em"),
				"major dominant explains the leading tone and natural minor v")
			await _capture("minor-progression-A-V")
		var pitches: Array[int] = []
		for note in score.notes:
			pitches.append(note.midi)
		_piano_key(_practice._piano, pitches[0] + 1)
		_piano_key(_practice._piano, pitches[0] + 12)
		expect(_practice._accepted.is_empty(), "wrong pitch or octave never advances a written chord")
		_piano_key(_practice._piano, pitches[2])
		_piano_key(_practice._piano, pitches[2])
		expect(_practice._accepted.size() == 1, "repeated chord tone counts once")
		_piano_key(_practice._piano, pitches[0])
		_piano_key(_practice._piano, pitches[1])
		expect(_practice._accepted.size() == 3 and _practice._staff.note_ink(0) == Finish.SUCCESS_GREEN,
			"all three pitches are accepted in any order and show completion")
		if hear_first and index == 0:
			await create_timer(2.60).timeout
			expect(_triads == [pitches], "audible completion plays the exact written root-position triad once")
			_press(_practice._sound)
		else:
			await create_timer(0.52).timeout
	expect(_practice._chord_index == 4 and _practice._action.visible and _practice._status.text == "Последовательность сыграна",
		"fourth chord leaves a repeatable completion state")
	_press(_practice._action)
	expect(_practice._chord_index == 0 and _practice._chord.symbol == symbols[0], "replay restores the tonic of the selected key")
	_app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	expect(_wheel_page.visible and _wheel_page._key.triad_name(0) == symbols[0] and
		_wheel_page._key.minor == minor and root.size.y > root.size.x,
		"system back restores the selected key in portrait")


func _check_wheel_layout() -> void:
	var wheel := _wheel_page._wheel
	var bounds := Finish.safe_bounds(_wheel_page)
	expect(is_equal_approx(wheel.size.x, wheel.size.y) and wheel.size.x / bounds.size.x >= 0.65 and
		wheel.size.x / bounds.size.x <= 0.85, "wheel stays circular and fills an appropriate width (%s in %s)" % [wheel.size, bounds.size])
	var final_row: Control = _wheel_page._content.get_child(4)
	expect(bounds.encloses(final_row.get_global_rect()), "all exploration actions fit inside the safe area")


func _check_practice_layout(piano: Piano) -> void:
	var bounds := Finish.safe_bounds(_practice)
	expect(bounds.encloses(piano.get_global_rect()) and piano.size.x / bounds.size.x > 0.93 and
		piano.size.y / bounds.size.y >= 0.6, "two-octave practice keyboard retains baseline dimensions")
	expect(_practice._staff.get_global_rect().end.y < piano.global_position.y and _practice._staff.staff_space() > 0.0,
		"staff fits above the keyboard")


func _check_dialog_layout() -> void:
	var bounds := Finish.safe_bounds(_wheel_page)
	expect(bounds.encloses(_wheel_page._dialog.get_global_rect()),
		"minor modal fits the safe area (%s in %s)" % [_wheel_page._dialog.size, bounds.size])


func _piano_key(piano: Piano, midi: int) -> void:
	var key := midi - 60
	var octave := key / 12.0
	var white_slot := Chords.WHITE_PITCHES.find(key % 12)
	var rect := piano.white_rect(floori(octave) * 7 + white_slot) if white_slot >= 0 else piano.black_rect(
		floori(octave) * 7 + piano.BLACK_BOUNDARIES[Chords.BLACK_PITCHES.find(key % 12)])
	var point := Vector2(rect.get_center().x, rect.end.y - rect.size.y * 0.12)
	expect(piano.key_at(point) == key, "visible piano key maps to test MIDI")
	_click(piano.global_position + point)


func _sector_touch(sector: int, radius_ratio := 0.83) -> void:
	var wheel := _wheel_page._wheel
	var point := wheel.get_global_rect().get_center() + Vector2.from_angle(sector * TAU / 12.0 - PI * 0.5) * (
		wheel._radius() * radius_ratio)
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = root.get_final_transform() * point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _dialog_text() -> String:
	var lines := PackedStringArray()
	for label in _wheel_page._dialog_body.find_children("*", "Label", true, false):
		lines.append(label.text)
	return "\n".join(lines)


func _button_in(parent: Node, caption: String) -> Button:
	for button in parent.find_children("*", "Button", true, false):
		if button.text == caption:
			return button
	expect(false, "button exists: " + caption)
	return null


func _open_circle() -> void:
	var button: Button = _app._menu._mode_buttons[Settings.Mode.CIRCLE]
	_app._menu._home_scroll.ensure_control_visible(button)
	await _settle()
	_press(button)


func _press(button: Button) -> void:
	if button != null:
		_click(button.get_global_rect().get_center())


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)


func _settle() -> void:
	await process_frame
	await process_frame


func _capture(label: String) -> void:
	if _headless:
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var dimensions := "%sx%s" % [image.get_width(), image.get_height()]
	expect(image.save_png(OUTPUT.path_join("%s-%s.png" % [dimensions, label])) == OK,
		"saved rendered screenshot " + label)


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
