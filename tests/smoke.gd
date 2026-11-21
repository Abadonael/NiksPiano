extends SceneTree

const Main := preload("res://main.tscn")
const Notes := preload("res://scripts/notes.gd")
const Settings := preload("res://scripts/settings.gd")
const Finish := preload("res://scripts/finish.gd")
const Staff := preload("res://scripts/staff.gd")
const Chords := preload("res://scripts/chords.gd")
const ChordBag := preload("res://scripts/chord_bag.gd")
const ChordGame := preload("res://scripts/chord_game.gd")
const ChordPiano := preload("res://scripts/chord_piano.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const HeaderButton := preload("res://scripts/header_button.gd")
const MixedAudio := preload("res://tests/mixed_audio.gd")
const FreePianoSmoke := preload("res://tests/free_piano_smoke.gd")
const MelodySmoke := preload("res://tests/melody_smoke.gd")
const CYCLES := 100
const OUTPUT_DIR := "res://.godot/checks/smoke/0.5.1"
const CANCELED_COMPLETION_WATCH_SECONDS := 2.43

var failures := 0
var app: Control
var menu: Control
var game: Control
var piano: Control
var audio: PianoAudio
var note_events: Array[int] = []
var triad_events: Array[Array] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DirAccess.make_dir_recursive_absolute(OUTPUT_DIR) != OK:
		printerr("Could not create smoke test output directory.")
		quit(1)
		return
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		root.size = Vector2i(405, 720)
	var run_id := "headless" if headless else "%sx%s" % [root.size.x, root.size.y]
	var settings_path := OUTPUT_DIR.path_join("settings-%s.cfg" % run_id)
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(settings_path)
	_check_pitch_mapping()
	_check_chord_catalog()
	_check_chord_cycles()
	app = Main.instantiate()
	app.preferences = Settings.new(settings_path)
	root.add_child(app)
	await process_frame
	menu = app.get_node("Menu")
	game = app.get_node("Game")
	piano = game.get_node("Piano")
	audio = app.get_node("PianoAudio")
	audio.note_started.connect(func(midi: int) -> void: note_events.append(midi))
	audio.triad_started.connect(func(notes: Array[int]) -> void: triad_events.append(notes))

	expect(menu.visible and not game.visible, "startup shows menu")
	expect(app.preferences.mode == Settings.Mode.STAFF and not app.preferences.letter_names and app.preferences.range_mask == 1,
		"first-run settings")
	expect(app.preferences.chord_mask == 3 and not menu._chord_heading.visible, "first-run chord settings are hidden")
	expect(root.size.y > root.size.x, "launches in portrait")
	expect(menu._staff_rows[0].is_visible_in_tree() and not menu._naming_rows[0].is_visible_in_tree(), "staff options visible")
	expect(menu._start.get_global_rect().end.y <= menu.size.y, "start fits")
	expect(menu._range_buttons[3].get_global_rect().end.y < menu._start.position.y, "all staff ranges fit above Start")
	expect(ThemeDB.fallback_font.has_char("Й".unicode_at(0)), "bundled UI font includes Cyrillic")
	if OS.get_name() == "Windows":
		expect(Settings.new()._path == "res://.piano_settings.cfg", "Windows editor run uses project-local settings")
	if DisplayServer.get_name() != "headless":
		await capture("menu")
	await _check_credits()
	await _check_audio_engine(settings_path)

	click(menu._range_buttons[0].get_global_rect().get_center())
	expect(app.preferences.range_mask == 1 and menu._range_buttons[0].button_pressed, "cannot disable last staff range")
	click(menu._range_buttons[3].get_global_rect().get_center())
	click(menu._range_buttons[0].get_global_rect().get_center())
	expect(app.preferences.range_mask == 8, "can enable one range and disable another")

	click(menu._start.get_global_rect().get_center())
	expect(game.visible and not menu.visible and game._staff.visible, "staff mode launches from Start")
	expect(root.size.y > root.size.x, "staff mode stays in portrait")
	expect(game._staff.range_index == 3 and game._octave.text == "Малая октава", "game uses enabled range")
	expect(game._octave.get_global_rect().end.y <= game.size.y, "octave label fits below the keyboard")
	expect(game._staff.get_global_rect().end.y < piano.position.y, "staff is above keyboard")
	expect(piano.get_global_rect().end.x < game.size.x and piano.position.x < game.size.x * 0.03, "keyboard spans screen")
	_check_gameplay_layout()
	_check_game_sound(game, [game._staff, piano], settings_path)
	if DisplayServer.get_name() != "headless":
		await capture("staff-sound")

	var expected: int = game._answer
	var wrong := (expected + 1) % 7
	var other_wrong := (expected + 2) % 7
	for boundary in piano_boundaries():
		var black: Rect2 = piano.black_rect(boundary)
		expect(piano.key_at(black.get_center()) == -1, "black key masks the white key beneath it")
		click(piano.global_position + black.get_center())
	expect(piano.highlighted_key == -1 and game._staff.mistake == -1, "all five black key clicks ignored")
	var black_center: Vector2 = piano.black_rect(1).get_center()
	tap(piano.global_position + black_center)
	expect(piano.highlighted_key == -1 and note_events.is_empty(), "black keys are silent in note training")
	for pitch in range(7):
		var rect: Rect2 = piano.white_rect(pitch)
		expect(piano.key_at(Vector2(rect.get_center().x, rect.end.y - 20.0)) == pitch, "white key %s matches visible area" % pitch)
	tap(white_key_point(wrong))
	expect(piano.highlighted_key == wrong and not piano.correct and game._staff.mistake == wrong,
		"incorrect staff tap displays key and ghost note")
	expect(game._staff.target_ink == Staff.INK, "target stays white after a wrong answer")
	click_key(other_wrong)
	expect(piano.highlighted_key == other_wrong and game._staff.mistake == other_wrong, "incorrect response replaces ghost note")
	expect(note_events == [48 + Chords.WHITE_PITCHES[wrong], 48 + Chords.WHITE_PITCHES[other_wrong]],
		"staff touches sound once, with the pressed pitch in the written octave")
	if DisplayServer.get_name() != "headless":
		await capture("bass-feedback")
	click_key(expected)
	expect(piano.highlighted_key == expected and piano.correct and game._staff.mistake == -1,
		"correct staff response is green and clears ghost note")
	expect(game._staff.target_ink == Finish.SUCCESS_GREEN, "target note switches to the shared green")
	expect(is_equal_approx(game._feedback.wait_time, 0.4), "feedback timer is 0.4 seconds")
	click_key(other_wrong)
	expect(game._answer == expected and piano.highlighted_key == expected and piano.correct
		and game._staff.mistake == -1, "pending transition ignores additional input")
	expect(note_events.slice(2) == [48 + Chords.WHITE_PITCHES[expected], 48 + Chords.WHITE_PITCHES[other_wrong]],
		"correct answers and taps during note feedback still sound")
	var midpoint := create_timer(0.2)
	if DisplayServer.get_name() != "headless":
		var success_frame := await capture("staff-success")
		_check_rendered_green(success_frame, expected)
	if midpoint.time_left > 0.0:
		await midpoint.timeout
	expect(piano.highlighted_key == expected and game._staff.target_ink == Finish.SUCCESS_GREEN,
		"key and note remain green mid-transition")
	await create_timer(0.25).timeout
	expect(piano.highlighted_key == -1 and not piano.correct and game._staff.target_ink == Staff.INK
		and game._staff.mistake == -1, "the next question clears both feedback colors")
	expect(game._answer != expected, "timer advances to a different white key")

	_check_staff_cycles()
	_check_resume_same_pool()

	var last_staff_key: int = game._answer
	click(game._menu.get_global_rect().get_center())
	expect(menu.visible and not game.visible and game._answer == -1, "in-game menu returns to settings")
	tap(menu._mode_buttons[1].get_global_rect().get_center())
	expect(menu._naming_rows[0].is_visible_in_tree() and not menu._staff_rows[0].is_visible_in_tree(),
		"naming settings replace range controls")
	_check_menu_radios()
	if DisplayServer.get_name() != "headless":
		var selection_frame := await capture("naming-options")
		_check_selection_borders(selection_frame)
	click(menu._start.get_global_rect().get_center())
	expect(game._note_name.text == Notes.RUSSIAN[game._answer], "Russian named game starts with matching solfege")
	expect(root.size.y > root.size.x, "name mode stays in portrait")
	expect(not game._staff.visible and not game._octave.visible, "name mode hides all staff elements")
	_check_game_sound(game, [game._note_name, piano], settings_path)
	_check_cycles("Russian", _named_pitch_ids(), last_staff_key, Notes.RUSSIAN)
	if DisplayServer.get_name() != "headless":
		await capture("named-note")
	expected = game._answer
	wrong = (expected + 1) % 7
	note_events.clear()
	tap(white_key_point(wrong))
	expect(piano.highlighted_key == wrong and not piano.correct and game._feedback.is_stopped(), "name mode incorrect response allows retry")
	click_key(expected)
	expect(piano.highlighted_key == expected and piano.correct and not game._feedback.is_stopped(), "name mode correct response starts timer")
	expect(note_events == [60 + Chords.WHITE_PITCHES[wrong], 60 + Chords.WHITE_PITCHES[expected]],
		"both correct and incorrect named notes sound once in octave 4")
	await create_timer(0.46).timeout
	expect(piano.highlighted_key == -1 and game._note_name.text == Notes.RUSSIAN[game._answer], "name mode advances after feedback")
	var last_russian_key: int = game._answer
	click(game._menu.get_global_rect().get_center())
	click(menu._naming_buttons[1].get_global_rect().get_center())
	click(menu._start.get_global_rect().get_center())
	expect(game._note_name.text == Notes.LETTERS[game._answer], "letter game starts with matching letter")
	_check_cycles("letters", _named_pitch_ids(), last_russian_key, Notes.LETTERS)
	var last_letter_key: int = game._answer
	click_key(game._answer)
	click(game._menu.get_global_rect().get_center())
	expect(game._feedback.is_stopped(), "returning to menu cancels pending transition")

	click(menu._mode_buttons[0].get_global_rect().get_center())
	click(menu._start.get_global_rect().get_center())
	expect(game._staff.visible and game._staff.range_index == 3 and game._answer != last_letter_key,
		"switching back to staff rebuilds the enabled pool without repeating the key")
	click(game._menu.get_global_rect().get_center())
	click(menu._mode_buttons[1].get_global_rect().get_center())

	var loaded := Settings.new(settings_path)
	loaded.load_settings()
	expect(loaded.mode == Settings.Mode.NAMES and loaded.letter_names and loaded.range_mask == 8,
		"fresh settings instance loads all note menu choices")
	var saved := ConfigFile.new()
	expect(saved.load(settings_path) == OK and saved.get_section_keys("menu").size() == 5,
		"settings store the mode and four options")
	saved.set_value("menu", "range_mask", 0)
	saved.set_value("menu", "chord_mask", 0)
	saved.save(settings_path)
	loaded.load_settings()
	expect(loaded.range_mask == 1, "invalid empty mask recovers to first octave")
	expect(loaded.chord_mask == 3, "invalid empty chord mask recovers to default groups")
	saved.erase_section_key("menu", "mode")
	saved.erase_section_key("menu", "chord_mask")
	saved.erase_section_key("menu", "sound_enabled")
	saved.set_value("menu", "staff_mode", false)
	saved.save(settings_path)
	loaded.load_settings()
	expect(loaded.mode == Settings.Mode.NAMES and loaded.chord_mask == 3, "0.1 settings migrate to the equivalent mode")
	expect(loaded.sound_enabled, "older settings default to sound on")

	if DisplayServer.get_name() != "headless":
		menu.hide()
		game.start(true, false, Notes.ALL_RANGES)
		game.show()
		game._staff.show_note(1, 6)
		game._octave.text = Notes.RANGES[1].title
		await capture("treble-ledger")
		game._staff.show_note(2, 0)
		game._octave.text = Notes.RANGES[2].title
		await capture("bass-ledger")
		app._show_menu()

	await _check_chord_game(settings_path)
	await FreePianoSmoke.new().run(self, settings_path, not headless and run_id == "405x900")
	await MelodySmoke.new().run(self, settings_path, not headless and run_id == "405x900")
	# Let the mixer release the last exercise's sample references before shutdown.
	audio.fade_keys(PianoAudio.STOP_FADE_SECONDS)
	await create_timer(0.15).timeout

	print("Checked %s cycles per pool for all %s staff masks and both naming styles." % [CYCLES, Notes.ALL_RANGES])
	print("Checked %s cycles per pool for all %s chord group masks." % [CYCLES, Chords.ALL_GROUPS])
	print("Checked sample loading, playback events, sound persistence and chord transition timing.")
	print("Smoke checks: %s failures at %s (%s logical)" % [failures, root.size, app.size])
	quit(1 if failures > 0 else 0)


func _check_menu_radios() -> void:
	var russian: Button = menu._naming_buttons[0]
	var letters: Button = menu._naming_buttons[1]
	var names: Button = menu._mode_buttons[Settings.Mode.NAMES]
	var staff: Button = menu._mode_buttons[Settings.Mode.STAFF]
	var russian_point := russian.get_global_rect().get_center()
	var letters_point := letters.get_global_rect().get_center()
	expect(names.button_group != null and russian.button_group != null and names.button_group != russian.button_group,
		"mode and naming have independent radio groups")
	for index in range(8):
		var select_letters := index % 2 == 0
		tap(letters_point if select_letters else russian_point)
		expect(app.preferences.letter_names == select_letters, "rapid touch selects the requested naming option")
		_check_radio_group(menu._naming_buttons, letters if select_letters else russian)
	_touch(letters_point, 0, true)
	_touch(russian_point, 1, true)
	_touch(letters_point, 0, false)
	_touch(russian_point, 1, false)
	_check_radio_group(menu._naming_buttons, letters if app.preferences.letter_names else russian)
	var selected_naming: Button = letters if app.preferences.letter_names else russian
	var staff_point := staff.get_global_rect().get_center()
	var names_point := names.get_global_rect().get_center()
	_touch(staff_point, 0, true)
	_touch(names_point, 1, true)
	_touch(names_point, 1, false)
	_touch(staff_point, 0, false)
	_check_radio_group(menu._mode_buttons, menu._mode_buttons[app.preferences.mode])
	_check_radio_group(menu._naming_buttons, selected_naming)
	tap(names_point)
	tap(russian_point)
	letters.grab_focus()
	var motion := InputEventMouseMotion.new()
	motion.position = letters_point
	motion.global_position = letters_point
	root.push_input(motion, true)
	expect(letters.has_focus() and letters.is_hovered(), "an unselected radio row can hold keyboard focus and hover")
	_check_radio_group(menu._mode_buttons, names)
	_check_radio_group(menu._naming_buttons, russian)


func _check_radio_group(rows: Array[Button], selected: Button) -> void:
	expect(selected.button_group != null and selected.button_group.get_pressed_button() == selected,
		"radio group points to the selected row")
	for row in rows:
		var active := row == selected
		var normal := row.get_theme_stylebox("normal") as StyleBoxTexture
		var hover := row.get_theme_stylebox("hover") as StyleBoxTexture
		expect(row.button_group == selected.button_group and row.button_pressed == active
			and row.get_node("Radio/Dot").visible == active, "radio dot and pressed state agree for " + row.text)
		expect(normal.texture == (menu._selected.texture if active else menu._dark.texture)
			and hover.texture == (menu._radio_selected_hover.texture if active else menu._radio_hover.texture)
			and row.get_theme_stylebox("pressed") == normal and row.get_theme_stylebox("hover_pressed") == hover,
			"all interaction states keep the correct selection border for " + row.text)


func _check_selection_borders(frame: Image) -> void:
	for row: Button in menu._mode_buttons + menu._naming_buttons:
		var rect := row.get_global_rect()
		var rim := Vector2i(root.get_final_transform() * Vector2(rect.position.x, rect.get_center().y))
		var brightest := 0.0
		for dx in range(3):
			brightest = maxf(brightest, frame.get_pixel(rim.x + dx, rim.y).r)
		expect((brightest > 0.55) == row.get_node("Radio/Dot").visible,
			"rendered border matches the radio indicator for " + row.text)


func _check_audio_engine(settings_path: String) -> void:
	_check_sound_layout()
	expect(audio.enabled and menu._sound.button_pressed, "sound defaults to on")
	expect(AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter, "mix has clipping protection")
	expect(PianoAudio.SAMPLES.size() == 17, "17 sampled anchors are preloaded")
	for sample in PianoAudio.SAMPLES:
		expect(sample != null and sample.stereo and sample.mix_rate == 44100
			and sample.format == AudioStreamWAV.FORMAT_16_BITS and is_equal_approx(sample.get_length(), 2.4),
			"every anchor is stereo 44.1 kHz PCM with a 2.4-second tail")
	for midi in range(60, 84):
		audio.play_note(midi)
		var voice := audio._keys[posmod(audio._next_key - 1, PianoAudio.KEY_VOICES)]
		var anchor := voice.stream.resource_path.get_file().get_basename().to_int()
		var played := anchor + 12.0 * log(voice.pitch_scale) / log(2.0)
		expect(voice.playing and absf(played - midi) < 0.001 and absi(midi - anchor) <= 1,
			"native voice for MIDI %s uses the correct anchor and pitch" % midi)
	expect(note_events.size() == 24 and note_events[12] - note_events[0] == 12,
		"all 24 notes played, with C4 and C5 an octave apart")
	expect(_playing_count(audio._keys) == PianoAudio.KEY_VOICES, "key voices stay within the pool under rapid input")
	audio.set_enabled(false)
	await create_timer(0.08).timeout
	await process_frame
	audio.set_enabled(true)
	audio.play_note(60)
	audio.play_note(60)
	expect(note_events.slice(-2) == [60, 60] and _playing_count(audio._keys) == 2,
		"repeating a note starts an independent native voice")
	tap(menu._sound.get_global_rect().get_center())
	expect(not audio.enabled and not menu._sound.button_pressed and not audio._fades.is_empty(),
		"touching the speaker blocks new playback immediately and fades existing voices")
	var event_count := note_events.size()
	audio.play_note(60)
	audio.play_triad([60, 64, 67])
	expect(note_events.size() == event_count and triad_events.is_empty() and _playing_count(audio._triads) == 0,
		"muted engine starts neither notes nor triads")
	var relaunched := Main.instantiate()
	relaunched.preferences = Settings.new(settings_path)
	root.add_child(relaunched)
	expect(not relaunched.preferences.sound_enabled and not relaunched._audio.enabled
		and not relaunched._menu._sound.button_pressed, "a fresh application restores mute and its icon state")
	relaunched.free()
	var mute_deadline := create_timer(0.18)
	while _playing_count(audio._keys) > 0 and mute_deadline.time_left > 0.0:
		await process_frame
	expect(_playing_count(audio._keys) == 0, "the short mute fade stops all active key voices")
	if DisplayServer.get_name() != "headless":
		await capture("sound-muted")
	click(menu._sound.get_global_rect().get_center())
	audio.play_note(60)
	expect(audio.enabled and menu._sound.button_pressed and note_events.size() == event_count + 1,
		"unmuting restores playback immediately")
	var settings := Settings.new(settings_path)
	settings.load_settings()
	expect(settings.sound_enabled, "unmuting saves the new setting")
	note_events.clear()


func _playing_count(voices: Array[AudioStreamPlayer]) -> int:
	var count := 0
	for voice in voices:
		count += int(voice.playing)
	return count


func _check_sound_layout() -> void:
	var menu_rect := menu.get_global_rect()
	var toolbar: HBoxContainer = menu._toolbar
	var title: Label = menu._title
	var title_rect := title.get_global_rect()
	expect(menu_rect.encloses(title_rect) and title_rect.size.x >= title.get_minimum_size().x,
		"the portrait title fits without clipping")
	expect(title.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT
		and is_equal_approx(title.position.x, menu._headline.position.x),
		"the title is left-aligned with the menu content")
	expect(is_equal_approx(menu_rect.end.x - toolbar.get_global_rect().end.x, menu._headline.position.x),
		"the toolbar retains its right margin")
	var previous_x := title_rect.end.x
	for button: Button in toolbar.get_children():
		var rect := button.get_global_rect()
		expect(menu_rect.encloses(rect) and rect.position.x >= previous_x
			and rect.end.y <= menu._headline.position.y, "header icons fit beside the title above settings")
		expect(rect.size == Vector2.ONE * HeaderButton.TARGET, "toolbar has consistent touch targets")
		previous_x = rect.end.x
	var inset := Rect2(Vector2(42, 72), menu_rect.size - Vector2(92, 116))
	expect(Finish.inset_bounds(menu_rect, inset) == inset, "safe insets constrain the header canvas")
	expect(Finish.inset_bounds(menu_rect, Rect2(Vector2.ZERO, Vector2(1280, 720))) == menu_rect,
		"stale landscape insets do not constrain the portrait canvas")


func _check_game_sound(screen: Control, protected: Array, settings_path: String) -> void:
	var sound: Button = screen._sound
	var rect := sound.get_global_rect()
	expect(screen.get_global_rect().encloses(rect) and rect.position.x > screen.size.x * 0.5,
		"gameplay sound control fits in the upper-right corner")
	for control: Control in protected + [screen._menu]:
		expect(not rect.intersects(control.get_global_rect()),
			"gameplay sound %s avoids %s %s" % [rect, control.name, control.get_global_rect()])
	var loaded := Settings.new(settings_path)
	tap(rect.get_center())
	loaded.load_settings()
	expect(not sound.button_pressed and not menu._sound.button_pressed and not loaded.sound_enabled,
		"gameplay touch mutes the shared sound and saves it")
	click(rect.get_center())
	loaded.load_settings()
	expect(audio.enabled and menu._sound.button_pressed and sound.button_pressed and loaded.sound_enabled,
		"gameplay unmutes the shared sound and saves it")


func _check_credits() -> void:
	var credits: Control = menu._credits
	var flag: Button = menu._toolbar.get_node("Language")
	click(flag.get_global_rect().get_center())
	expect(flag.disabled and not credits.visible and menu.visible, "the flag is display-only")
	tap(menu._info.get_global_rect().get_center())
	await process_frame
	expect(credits.visible and menu.visible and root.size.y > root.size.x, "info opens a portrait overlay")
	var copy := ""
	for child in credits._body.get_children():
		if child is Label:
			copy += child.text + "\n"
	for name in ["Niks Piano", ProjectSettings.get_setting("application/config/version"), "Salamander Grand Piano V3", "Alexander Holm", "kinwie",
			"CC BY 3.0", "https://github.com/sfzinstruments/SalamanderGrandPiano",
			"https://creativecommons.org/licenses/by/3.0/", "Bravura", "SIL Open Font License 1.1", "Godot Engine"]:
		expect(copy.contains(name), "offline credits include %s" % name)
	click(menu._start.get_global_rect().get_center())
	expect(menu.visible and not game.visible, "modal blocks menu controls beneath it")
	if DisplayServer.get_name() != "headless":
		await capture("credits")
	var scroll: ScrollContainer = credits._scroll
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = scroll.get_global_rect().get_center()
	for pressed in [true, false]:
		wheel.pressed = pressed
		root.push_input(wheel, true)
	await process_frame
	expect(scroll.scroll_vertical > 0, "credits respond to scrolling")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	if DisplayServer.get_name() != "headless":
		await capture("credits-scrolled")
	click(credits._close.get_global_rect().get_center())
	expect(not credits.visible and menu.visible, "close icon returns to menu")
	click(menu._info.get_global_rect().get_center())
	expect(scroll.scroll_vertical == 0, "reopening credits resets scroll position")
	var back := InputEventAction.new()
	back.action = "ui_cancel"
	back.pressed = true
	root.push_input(back, true)
	expect(not credits.visible and menu.visible, "Back action closes credits")
	click(menu._info.get_global_rect().get_center())
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	expect(not credits.visible and menu.visible, "Android Back notification closes credits")


func _check_chord_catalog() -> void:
	# Expected physical root pitches by group and quality.
	var major_roots := [[0, 5, 7], [2, 4, 9, 10], [1, 3, 8, 11], [6]]
	var minor_roots := [[2, 4, 9], [0, 5, 7, 11], [1, 6, 8, 10], [3]]
	var black_pitches := [1, 3, 6, 8, 10]
	var black_roots := {1: "Db", 3: "Eb", 6: "F#", 8: "Ab", 10: "Bb"}
	var sharp_minor_roots := {1: "C#", 8: "G#"}
	var found_symbols := {}
	for group in range(4):
		var found_major: Array[int] = []
		var found_minor: Array[int] = []
		for chord in Chords.enabled_chords(1 << group):
			var minor := chord.symbol.ends_with("m")
			var roots := found_minor if minor else found_major
			roots.append(chord.root)
			var third := 3 if minor else 4
			expect(chord.pitches == [chord.root, (chord.root + third) % 12, (chord.root + 7) % 12],
				chord.symbol + " has three distinct pitch classes at the expected intervals")
			var midi_root := 60 + chord.root
			expect(chord.root_position(60) == [midi_root, midi_root + third, midi_root + 7],
				chord.symbol + " plays in root position above its root in octave 4")
			var count_black := 0
			for pitch in chord.pitches:
				count_black += int(pitch in black_pitches)
			expect(count_black == group, chord.symbol + " belongs to its black-key group")
			expect(not found_symbols.has(chord.symbol), chord.symbol + " is unique")
			found_symbols[chord.symbol] = true
			var root_name: String
			if chord.root in black_pitches:
				root_name = sharp_minor_roots.get(chord.root, black_roots[chord.root]) if minor else black_roots[chord.root]
			else:
				root_name = Notes.LETTERS[Chords.WHITE_PITCHES.find(chord.root)]
			expect(chord.symbol == root_name + ("m" if minor else ""), chord.symbol + " uses the required international spelling")
		found_major.sort()
		found_minor.sort()
		expect(found_major == major_roots[group] and found_minor == minor_roots[group],
			"expected major and minor membership for chord group %s" % group)
	expect(found_symbols.size() == 24, "catalog has 24 unique chords")


func _check_chord_cycles() -> void:
	var bag := ChordBag.new()
	var previous: Chords.Triad
	for mask in range(1, Chords.ALL_GROUPS + 1):
		# Leave the old cycle unfinished before changing groups.
		if previous != null:
			previous = bag.next()
		bag.use_groups(mask)
		var active := Chords.enabled_chords(mask)
		var first_order: Array[String] = []
		var changed_order := false
		for cycle in range(CYCLES):
			var drawn: Array[String] = []
			for _index in range(active.size()):
				var chord := bag.next()
				expect(chord.symbol not in drawn, "each active chord appears once per cycle")
				if previous != null:
					expect(chord.symbol != previous.symbol, "no repeated chord across draws or cycle boundaries")
					expect(chord.root != previous.root, "no adjacent chords share a root")
				drawn.append(chord.symbol)
				previous = chord
			for chord in active:
				expect(chord.symbol in drawn, "cycle contains the active chord " + chord.symbol)
			if cycle == 0:
				first_order = drawn
			elif drawn != first_order:
				changed_order = true
		# The two-chord pool must alternate, so its cycle order cannot change.
		expect(changed_order or active.size() == 2, "new cycles shuffle when multiple orders are possible")


func _check_chord_game(settings_path: String) -> void:
	var portrait_size := root.size
	var chord_game := app.get_node("ChordGame") as ChordGame
	var keyboard: ChordPiano = chord_game._piano
	var graphical := DisplayServer.get_name() != "headless"
	click(menu._mode_buttons[Settings.Mode.CHORDS].get_global_rect().get_center())
	_check_sound_layout()
	expect(menu._chord_heading.visible and not menu._staff_rows[0].visible and not menu._naming_rows[0].visible,
		"chord options replace both note option sections")
	for index in range(4):
		var button: Button = menu._chord_buttons[index]
		expect(button.visible and button.button_pressed == (index < 2), "default chord checkbox state")
		expect(button.get_global_rect().end.y < menu._start.position.y, "chord row fits above Start")
	if graphical:
		await capture("chord-menu")

	for index in [3, 0, 1, 3]:
		click(menu._chord_buttons[index].get_global_rect().get_center())
	expect(app.preferences.chord_mask == 8 and menu._chord_buttons[3].button_pressed,
		"chord groups are independent and the last group stays enabled")
	var reloaded := Settings.new(settings_path)
	reloaded.load_settings()
	expect(reloaded.mode == Settings.Mode.CHORDS and reloaded.chord_mask == 8,
		"chord selection persists across settings instances")

	click(menu._start.get_global_rect().get_center())
	await process_frame
	expect(chord_game.visible and not menu.visible and not game.visible, "Start opens the chord screen")
	expect(root.size.x > root.size.y and app.size.x > app.size.y, "chord mode switches to landscape")
	expect(root.size == Vector2i(portrait_size.y, portrait_size.x), "landscape dimensions match the test window")
	var screen := chord_game.get_global_rect()
	for control in [chord_game._menu, chord_game._symbol, keyboard]:
		expect(screen.encloses(control.get_global_rect()), "landscape controls fit on screen")
	expect(keyboard.size.x >= screen.size.x * 0.94, "keyboard spans nearly the full width")
	expect(chord_game._symbol.text in Chords.GROUPS[3], "symbol uses the enabled group")
	_check_game_sound(chord_game, [chord_game._symbol, keyboard], settings_path)
	_check_chord_keys(keyboard)
	if graphical:
		await capture("chord-gameplay")

	var emitted: Array[int] = []
	keyboard.key_pressed.connect(func(key: int) -> void: emitted.append(key))
	note_events.clear()
	triad_events.clear()
	var chord := chord_game._chord
	var first := chord.pitches[2] + 12
	var second := chord.pitches[0]
	var last := chord.pitches[1] + 12
	var alternate := first - 12
	tap(_chord_key_point(keyboard, first))
	expect(emitted == [first] and keyboard._green_keys.has(first), "touch highlights the physical key once")
	click(_chord_key_point(keyboard, first))
	tap(_chord_key_point(keyboard, alternate))
	expect(note_events == [60 + first, 60 + first, 60 + alternate],
		"both repeats retrigger at their physical pitches, with no emulated duplicate")
	expect(chord_game._accepted.size() == 1 and keyboard._green_keys.keys() == [first]
		and keyboard._green_until.has(alternate) and not keyboard._green_until.has(first),
		"only the first key stays green and the other octave flashes green")
	var original_expiry := int(keyboard._green_until.get(alternate, 0))
	await create_timer(0.10).timeout
	tap(_chord_key_point(keyboard, alternate))
	expect(int(keyboard._green_until.get(alternate, 0)) > original_expiry and chord_game._accepted.size() == 1,
		"another rapid tap refreshes temporary feedback without changing acceptance")
	click(_chord_key_point(keyboard, 0))
	expect(keyboard._red_until.has(0) and keyboard._green_keys.has(first) and note_events.back() == 60,
		"a wrong key sounds, becomes red immediately, and leaves the correct key green")
	click(_chord_key_point(keyboard, second))
	expect(chord_game._accepted.size() == 2 and keyboard._green_keys.has(second) and keyboard._red_until.has(0),
		"red feedback does not block correct input")
	if graphical:
		var frame := await capture("chord-feedback")
		expect(_pixel(frame, _chord_key_point(keyboard, first)).to_rgba32() == Finish.SUCCESS_GREEN.to_rgba32(),
			"played black key renders green")
		expect(_pixel(frame, _chord_key_point(keyboard, alternate)).to_rgba32() == Finish.SUCCESS_GREEN.to_rgba32(),
			"alternate-octave repeat renders green")
		var wrong_color := _pixel(frame, _chord_key_point(keyboard, 0))
		expect(wrong_color.r > wrong_color.g * 1.3, "wrong white key renders red")
	await create_timer(0.12).timeout
	expect(keyboard._green_until.has(alternate), "the original flash deadline cannot clear the refreshed flash")
	await create_timer(0.16).timeout
	expect(keyboard._red_until.is_empty() and keyboard._green_until.is_empty() and keyboard._green_keys.size() == 2,
		"red and temporary green expire without clearing either accepted key")

	click(_chord_key_point(keyboard, last))
	var completed_at := Time.get_ticks_usec()
	expect(keyboard._green_keys.size() == 3 and chord_game._completion != null,
		"three distinct correct pitches in any order start the transition")
	expect(note_events.back() == 60 + last and triad_events.is_empty(), "the final key plays before the triad")
	var completion_notes := note_events.size()
	tap(_chord_key_point(keyboard, 0))
	expect(keyboard._red_until.is_empty() and chord_game._chord == chord and note_events.size() == completion_notes,
		"transition blocks both audio and scoring for additional key presses")
	await create_timer(0.195).timeout
	expect(audio._fades.is_empty() and _playing_count(audio._keys) > 0 and triad_events.is_empty(),
		"the keys retain their attack before the 260 ms hold ends")
	var watch := create_timer(0.15)
	while audio._fades.is_empty() and watch.time_left > 0.0:
		await process_frame
	var fade_started := Time.get_ticks_usec()
	var hold_ms := (fade_started - completed_at) / 1000.0
	expect(hold_ms >= 222.0 and hold_ms <= 307.0, "observed key hold near 260 ms (%.1f ms)" % hold_ms)
	expect(audio._fades.size() == _playing_count(audio._keys), "every lingering key gets a fade")
	await create_timer(0.11).timeout
	var key_gain := audio._keys[posmod(audio._next_key - 1, PianoAudio.KEY_VOICES)].volume_linear
	expect(key_gain > 0.0 and key_gain < db_to_linear(PianoAudio.KEY_DB) and triad_events.is_empty(),
		"the key fade passes through intermediate gain before the demonstration")
	watch = create_timer(0.31)
	while _playing_count(audio._keys) > 0 and watch.time_left > 0.0:
		await process_frame
	var fade_ms := (Time.get_ticks_usec() - fade_started) / 1000.0
	expect(fade_ms >= 303.0 and fade_ms <= 400.0, "observed key release near 350 ms (%.1f ms)" % fade_ms)
	await create_timer(0.09).timeout
	expect(_playing_count(audio._keys) == 0 and triad_events.is_empty(),
		"all key voices have stopped during the silent interval")
	watch = create_timer(0.36)
	while triad_events.is_empty() and watch.time_left > 0.0:
		await process_frame
	var expected_triad := chord.root_position(60)
	expect(triad_events == [expected_triad] and _playing_count(audio._triads) == 3
		and _playing_count(audio._keys) == 0, "the root-position triad starts three voices after the keys release")
	for index in range(3):
		var voice := audio._triads[index]
		if voice.stream == null:
			continue
		var anchor := voice.stream.resource_path.get_file().get_basename().to_int()
		expect(absf(anchor + 12.0 * log(voice.pitch_scale) / log(2.0) - expected_triad[index]) < 0.001,
			"each active triad voice has its expected pitch")
	await create_timer(0.92).timeout
	expect(chord_game._chord == chord and keyboard._green_keys.size() == 3, "all selected keys stay green past 0.4 seconds")
	watch = create_timer(0.48)
	while chord_game._chord == chord and watch.time_left > 0.0:
		await process_frame
	var completion_ms := (Time.get_ticks_usec() - completed_at) / 1000.0
	expect(completion_ms >= 2120.0 and completion_ms <= 2400.0,
		"observed automatic advance near 2.2 seconds (%.1f ms)" % completion_ms)
	print("Observed automatic advance: %.1f ms after the final key." % completion_ms)
	expect(chord_game._chord != chord and keyboard._green_keys.is_empty()
		and keyboard._red_until.is_empty() and keyboard._green_until.is_empty() and _playing_count(audio._triads) == 0,
		"next chord appears after the demonstration fades and resets the keyboard")

	emitted.clear()
	note_events.clear()
	var simultaneous: Array[int] = []
	for index in range(3):
		var key := chord_game._chord.pitches[index] + (index % 2) * 12
		simultaneous.append(key)
		_touch(_chord_key_point(keyboard, key), index, true)
	expect(emitted == simultaneous and keyboard._green_keys.size() == 3 and chord_game._completion != null,
		"three held fingers complete the chord without duplicate mouse events")
	expect(note_events.size() == 3, "simultaneous fingers trigger exactly three individual notes")
	for index in range(3):
		_touch(_chord_key_point(keyboard, simultaneous[index]), index, false)
	click(chord_game._menu.get_global_rect().get_center())
	await process_frame
	expect(menu.visible and not chord_game.visible and chord_game._success.is_stopped() and chord_game._completion == null,
		"landscape back button opens the menu and cancels the transition")
	expect(root.size == portrait_size and root.size.y > root.size.x and app.size.y > app.size.x,
		"returning to menu restores the portrait window and canvas")
	await create_timer(1.06).timeout
	expect(triad_events.size() == 1, "leaving a chord cancels its pending triad")

	click(menu._start.get_global_rect().get_center())
	await process_frame
	chord = chord_game._chord
	note_events.clear()
	triad_events.clear()
	var sound := chord_game._sound.get_global_rect().get_center()
	click(_chord_key_point(keyboard, chord.pitches[0]))
	click(_chord_key_point(keyboard, chord.pitches[1]))
	tap(sound)
	click(_chord_key_point(keyboard, chord.pitches[2]))
	expect(is_equal_approx(chord_game._success.wait_time, 0.4) and chord_game._completion == null
		and keyboard._green_keys.size() == 3, "muting before the final note uses the 0.4-second feedback")
	tap(sound)
	await create_timer(0.22).timeout
	expect(chord_game._chord == chord and keyboard._green_keys.size() == 3, "muted feedback survives until its deadline")
	await create_timer(0.24).timeout
	expect(chord_game._chord != chord and keyboard._green_keys.is_empty() and note_events.size() == 2 and triad_events.is_empty(),
		"a muted completion advances after 0.4 seconds without a final key sound or later demonstration")

	await _check_chord_mute(chord_game, 0.34, "key fade", false)
	await _check_chord_mute(chord_game, 0.76, "silent gap", false)
	await _check_chord_mute(chord_game, 1.17, "demonstration", true)
	if graphical:
		await _check_mixed_audio(chord_game)
	click(chord_game._menu.get_global_rect().get_center())


func _check_chord_mute(chord_game: ChordGame, delay: float, stage: String, demo_started: bool) -> void:
	var chord := chord_game._chord
	triad_events.clear()
	for pitch in chord.pitches:
		click(_chord_key_point(chord_game._piano, pitch))
	await create_timer(delay).timeout
	expect(chord_game._completion != null and (triad_events.size() == 1) == demo_started,
		"reached %s before toggling" % stage)
	if stage == "key fade":
		expect(_playing_count(audio._keys) > 0 and not audio._fades.is_empty(), "key voices are fading")
	elif stage == "silent gap":
		expect(_playing_count(audio._keys) == 0, "the silent gap begins after the keys stop")
	var sound := chord_game._sound.get_global_rect().get_center()
	tap(sound)
	expect(not audio.enabled and chord_game._completion == null, "mute cancels the sequence during %s" % stage)
	tap(sound)
	var advance_check := maxf(0.08, ChordGame.SUCCESS_SECONDS + 0.08 - delay)
	await create_timer(advance_check).timeout
	var next_chord := chord_game._chord
	expect(next_chord != chord and chord_game._accepted.is_empty()
		and _playing_count(audio._keys) == 0 and _playing_count(audio._triads) == 0,
		"mute during %s releases audio and advances on the fast path" % stage)
	await create_timer(CANCELED_COMPLETION_WATCH_SECONDS - delay - advance_check).timeout
	expect(chord_game._chord == next_chord and triad_events.size() == int(demo_started),
		"unmuting after %s cannot revive the demo or move the next question" % stage)


func _check_mixed_audio(chord_game: ChordGame) -> void:
	var probe := await _start_mixed_chord(chord_game)
	await create_timer(2.36).timeout
	audio.set_enabled(false)
	audio.play_note(72)
	audio.play_triad([60, 64, 67])
	await create_timer(0.13).timeout
	var recording := probe.take(audio)
	audio.set_enabled(true)
	for problem in probe.verify(recording, OUTPUT_DIR.path_join("%sx%s-transition.wav" % [root.size.x, root.size.y])):
		expect(false, problem)

	triad_events.clear()
	probe = await _start_mixed_chord(chord_game)
	var interrupted := chord_game._chord
	var mute_at := 0.34
	await create_timer(mute_at).timeout
	expect(chord_game._completion != null and not audio._fades.is_empty(), "mixer probe reaches the active key fade")
	tap(chord_game._sound.get_global_rect().get_center())
	tap(chord_game._sound.get_global_rect().get_center())
	var advance_check := 0.14
	await create_timer(advance_check).timeout
	var next := chord_game._chord
	expect(next != interrupted and chord_game._accepted.is_empty(), "mixer probe advances once on the 400 ms mute path")
	await create_timer(CANCELED_COMPLETION_WATCH_SECONDS - mute_at - advance_check).timeout
	expect(chord_game._chord == next and triad_events.is_empty(), "mixer probe stays on the next question after unmuting")
	for problem in probe.verify_canceled(probe.take(audio)):
		expect(false, problem)


func _start_mixed_chord(chord_game: ChordGame) -> MixedAudio:
	var probe := MixedAudio.new()
	probe.attach(audio)
	await create_timer(0.10).timeout
	probe.clear()
	await create_timer(0.06).timeout
	chord_game._chord = Chords.Triad.new("C", 0)
	chord_game._symbol.text = "C"
	var keyboard := chord_game._piano
	for _index in range(PianoAudio.KEY_VOICES - 2):
		click(_chord_key_point(keyboard, 12))
	click(_chord_key_point(keyboard, 16))
	click(_chord_key_point(keyboard, 19))
	expect(_playing_count(audio._keys) == PianoAudio.KEY_VOICES, "the mixed-audio burst fills the key pool")
	probe.play_reference()
	return probe


func _check_chord_keys(keyboard: ChordPiano) -> void:
	for key in range(24):
		var local := _chord_key_point(keyboard, key) - keyboard.global_position
		expect(keyboard.key_at(local) == key, "key %s is clickable in both octaves" % key)


func _chord_key_point(keyboard: ChordPiano, key: int) -> Vector2:
	@warning_ignore("integer_division")
	var octave := key / 12
	var pitch := key % 12
	var white_index := [0, 2, 4, 5, 7, 9, 11].find(pitch)
	if white_index >= 0:
		var rect := keyboard.white_rect(octave * 7 + white_index)
		return keyboard.global_position + Vector2(rect.get_center().x, rect.end.y - 20.0)
	var boundary: int = [1, 2, 4, 5, 6][[1, 3, 6, 8, 10].find(pitch)]
	return keyboard.global_position + keyboard.black_rect(octave * 7 + boundary).get_center()


func _check_pitch_mapping() -> void:
	var steps := [
		[-2, -1, 0, 1, 2, 3, 4],
		[5, 6, 7, 8, 9, 10, 11],
		[-4, -3, -2, -1, 0, 1, 2],
		[3, 4, 5, 6, 7, 8, 9],
	]
	var ledger := [
		[[-2], [], [], [], [], [], []],
		[[], [], [], [], [], [10], [10]],
		[[-2, -4], [-2], [-2], [], [], [], []],
		[[], [], [], [], [], [], []],
	]
	for range_index in range(4):
		for key in range(7):
			var step := Notes.staff_step(range_index, key)
			expect(step == steps[range_index][key], "staff position %s/%s" % [range_index, key])
			expect(Notes.ledger_steps(step) == ledger[range_index][key], "ledger lines %s/%s" % [range_index, key])


func _check_staff_cycles() -> void:
	for mask in range(1, Notes.ALL_RANGES + 1):
		var expected: Array[int] = []
		for range_index in range(Notes.RANGES.size()):
			if (mask & (1 << range_index)) != 0:
				for pitch in range(Notes.KEY_COUNT):
					expected.append(range_index * Notes.KEY_COUNT + pitch)
		var previous: int = game._answer
		game.start(true, false, mask)
		_check_cycles("staff mask %s" % mask, expected, previous)


func _check_cycles(context: String, expected: Array[int], previous: int, names: Array = []) -> void:
	var different_order := false
	var first_order: Array[int] = []
	for cycle in range(CYCLES):
		var drawn: Array[int] = []
		for index in range(expected.size()):
			if cycle != 0 or index != 0:
				game._next_note()
			var pitch: int = game._answer
			var location := "%s cycle %s question %s" % [context, cycle + 1, index + 1]
			expect(pitch >= 0 and pitch < Notes.KEY_COUNT, location + " must use a white key")
			expect(pitch != previous, location + " repeats the preceding key")
			previous = pitch
			if names.is_empty():
				drawn.append(game._staff.range_index * Notes.KEY_COUNT + pitch)
			else:
				drawn.append(pitch)
				expect(pitch >= 0 and pitch < names.size() and game._note_name.text == names[pitch],
					location + " must display the scheduled name")
		if cycle == 0:
			first_order = drawn.duplicate()
		elif drawn != first_order:
			different_order = true
		drawn.sort()
		expect(drawn == expected, "%s cycle %s must contain each active variant exactly once" % [context, cycle + 1])
	expect(different_order, context + " uses different orders across cycles")


func _check_resume_same_pool() -> void:
	game.start(true, false, 2)
	var scheduled: Array[int] = [game._answer]
	game._next_note()
	scheduled.append(game._answer)
	game.stop()
	game.start(true, false, 2)
	for index in range(2, Notes.KEY_COUNT):
		expect(game._answer != scheduled.back(), "resuming an unfinished cycle does not repeat the key")
		scheduled.append(game._answer)
		if index < Notes.KEY_COUNT - 1:
			game._next_note()
	scheduled.sort()
	expect(scheduled == _named_pitch_ids(), "reopening the same settings keeps the unfinished cycle")


func _named_pitch_ids() -> Array[int]:
	var pitches: Array[int] = []
	for pitch in range(Notes.KEY_COUNT):
		pitches.append(pitch)
	return pitches


func _check_gameplay_layout() -> void:
	var piano_y: float = game.size.y * 0.673
	var header_bottom: float = game._menu.get_rect().end.y
	var lift := (piano_y - header_bottom) * 0.1
	var staff: Control = game._staff
	expect(is_equal_approx(staff.position.y, piano_y - 335.0 - lift), "staff rises by 10 percent of header-to-keyboard space")
	expect(is_equal_approx(piano.position.y, piano_y)
		and is_equal_approx(game._octave.position.y, piano_y + piano.size.y + 27.0),
		"piano and octave label keep their vertical positions")
	var half_space := Staff.SPACE / 2.0
	expect(staff.position.y + staff._step_y(11) - half_space > header_bottom
		and staff.position.y + staff._step_y(-4) + half_space < piano_y,
		"highest and lowest notes fit above the piano and below the header")
	for child in game.get_children():
		if child is Label and child.visible:
			expect(child == game._octave, "the octave name is the only visible staff-mode label")


func _check_rendered_green(frame: Image, pitch: int) -> void:
	var staff: Control = game._staff
	var step := Notes.staff_step(staff.range_index, pitch)
	var note_x := lerpf(50.0, staff.size.x - 50.0, 0.63)
	var note_y: float = staff._step_y(step)
	var stem_side := 1.0 if step < 4 else -1.0
	var stem_x := note_x + stem_side * Staff.SPACE * (Staff.NOTE_WIDTH - Staff.STEM_THICKNESS) * 0.5
	var stem_y := note_y - stem_side * Staff.SPACE * 2.0
	var key: Rect2 = piano.white_rect(pitch)
	var key_face := Vector2(key.get_center().x, key.position.y + key.size.y * 0.8)
	var green := Finish.SUCCESS_GREEN.to_rgba32()
	expect(_pixel(frame, staff.global_position + Vector2(note_x, note_y)).to_rgba32() == green, "rendered notehead uses exact green")
	expect(_pixel(frame, staff.global_position + Vector2(stem_x, stem_y)).to_rgba32() == green, "rendered stem uses exact green")
	expect(_pixel(frame, piano.global_position + key_face).to_rgba32() == green, "rendered piano key uses exact green")


func _pixel(frame: Image, logical_position: Vector2) -> Color:
	var pixel := Vector2i(root.get_final_transform() * logical_position)
	return frame.get_pixelv(pixel)


func piano_boundaries() -> Array:
	return [1, 2, 4, 5, 6]


func click_key(pitch: int) -> void:
	click(white_key_point(pitch))


func white_key_point(pitch: int) -> Vector2:
	var rect: Rect2 = piano.white_rect(pitch)
	return piano.global_position + Vector2(rect.get_center().x, rect.end.y - 20.0)


func click(at: Vector2) -> void:
	for is_pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = is_pressed
		root.push_input(event, true)


func tap(at: Vector2) -> void:
	for is_pressed in [true, false]:
		_touch(at, 0, is_pressed)


func _touch(at: Vector2, index: int, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = root.get_final_transform() * at
	event.index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func capture(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUTPUT_DIR.path_join("%sx%s-%s.png" % [root.size.x, root.size.y, label])
	expect(image != null and image.save_png(path) == OK, "rendered %s" % label)
	return image


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures <= 20:
			printerr("FAIL: ", message)
