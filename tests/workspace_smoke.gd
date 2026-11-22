extends SceneTree

const Main := preload("res://main.tscn")
const Settings := preload("res://scripts/settings.gd")
const Exercises := preload("res://scripts/melody_exercises.gd")
const Notes := preload("res://scripts/notes.gd")
const Chords := preload("res://scripts/chords.gd")
const Store := preload("res://scripts/harmony_store.gd")
const OUTPUT := "res://builds/screenshots/0.7.2-workspace"

var _app: Control
var _menu: Control
var _settings_path: String
var _headless: bool
var _size: Vector2i
var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		root.size = Vector2i(320, 640)
	_size = root.size
	var folder := "res://.godot/checks/workspace/" + "%dx%d-%d" % [_size.x, _size.y, OS.get_process_id()]
	_check(DirAccess.make_dir_recursive_absolute(folder) == OK, "isolated fixture directory")
	_settings_path = folder.path_join("settings.cfg")
	var preferences := Settings.new(_settings_path)
	# A previously chosen direct mode must still open to the workspace on relaunch.
	preferences.mode = Settings.Mode.HARMONY_LAB
	preferences.save()
	_app = Main.instantiate()
	_app.preferences = preferences
	root.add_child(_app)
	_menu = _app.get_node("Menu")
	_app._harmony_lab.store = Store.new(folder.path_join("compositions"))
	if not _headless:
		_check(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "screenshot directory")
	await _settle()
	var initial_count := _menu.get_child_count(true)
	var descendants := _menu.find_children("*", "", true, false).size()
	await _check_home()
	await _check_melodies()
	await _check_notes_and_chords()
	await _check_direct_modes()
	_check(_menu.get_child_count(true) == initial_count and _menu.find_children("*", "", true, false).size() == descendants
		and _app.find_children("PianoAudio", "", true, false).size() == 1, "navigation reuses menu controls and shared audio")
	_check(root.size == _size, "navigation restores the original portrait size")
	if not _headless and _size == Vector2i(360, 732):
		await _measure_frames()
	print("Workspace %dx%d (%s): %d checks, %d failures" % [
		_size.x, _size.y, "headless" if _headless else "graphical", _checks, _failures])
	quit(int(_failures > 0))


func _check_home() -> void:
	_check(_menu._home_scroll.visible and not _menu._scroll.visible and not _menu._start.visible
		and _menu._title.text == "Nik's Piano" and root.title == "Nik's Piano", "relaunch shows branded workspace")
	_check(_menu._toolbar.get_child_count() == 2, "home toolbar has Info and Sound")
	var buttons: Array[Button] = _menu._mode_buttons
	var titles := [
		"По нотному стану", "По названию", "Аккорды", "Свободная клавиатура",
		"Мелодии", "Квинтовый круг", "Гармоническая лаборатория",
	]
	_check(buttons.size() == titles.size(), "seven entries")
	for index in range(buttons.size()):
		var card := buttons[index]
		_check(card.accessibility_name == titles[index] and card.is_visible_in_tree(), "module present: " + titles[index])
		_check_control_width(card, _menu._home_scroll.get_global_rect())
		_check_text(card)
		for other in buttons.slice(index + 1):
			_check(not card.get_global_rect().intersects(other.get_global_rect()), "module targets do not overlap")
	_check(buttons[0].global_position.y == buttons[1].global_position.y
		and buttons[2].global_position.y == buttons[4].global_position.y
		and buttons[2].global_position.y > buttons[0].global_position.y, "practice occupies a two-column grid")
	_check(buttons[5].size.x == buttons[6].size.x and buttons[6].size.x == buttons[3].size.x
		and buttons[6].global_position.y < buttons[3].global_position.y, "theory and tools occupy full-width rows")
	await _capture("01-workspace")
	var scroll: ScrollContainer = _menu._home_scroll
	var bar := scroll.get_v_scroll_bar()
	if bar.max_value > bar.page:
		var wheel := InputEventMouseButton.new()
		wheel.position = scroll.get_global_rect().get_center()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		for down in [true, false]:
			wheel.pressed = down
			root.push_input(wheel, true)
		await _settle()
		_check(scroll.scroll_vertical > 0, "home scroll responds to input")
		scroll.ensure_control_visible(buttons[Settings.Mode.FREE_PIANO])
		await _settle()
		_check(scroll.get_global_rect().encloses(buttons[Settings.Mode.FREE_PIANO].get_global_rect()),
			"scroll exposes the full Free Piano card")
		await _capture("02-workspace-bottom")
	scroll.scroll_vertical = 0
	await _settle()


func _check_melodies() -> void:
	await _open_mode(Settings.Mode.MELODIES)
	_check_settings(Settings.Mode.MELODIES)
	await _capture("03-melodies")
	var titles := ["Арпеджио", "Музыкальные фразы", "Гармонические интервалы"]
	var names := ["04-arpeggio", "05-musical-phrases", "06-harmonic-intervals"]
	for kind: Exercises.Kind in Exercises.Kind.values():
		await _activate(_menu._exercise_buttons[kind])
		_check(_menu._exercise_buttons[kind].accessibility_name == titles[kind]
			and _menu._length_section.is_visible_in_tree() == (kind != Exercises.Kind.INTERVAL), "conditional length for " + titles[kind])
		for button: Button in _menu._exercise_buttons + _menu._difficulty_buttons + _menu._clef_buttons:
			_check_control_width(button, _menu._scroll.get_global_rect())
			_check_text(button)
		for level: Exercises.Difficulty in Exercises.Difficulty.values():
			await _activate(_menu._difficulty_buttons[level])
			_check(_app.preferences.melody_difficulty == level, "chooses difficulty")
		if kind != Exercises.Kind.INTERVAL:
			for index in range(Exercises.LENGTHS.size()):
				await _activate(_menu._length_buttons[index])
				_check(_app.preferences.melody_length == Exercises.LENGTHS[index], "chooses length independently")
		for clef: Notes.Clef in Notes.Clef.values():
			await _activate(_menu._clef_buttons[clef])
			_check(_app.preferences.melody_clef == clef, "chooses clef")
		_menu._scroll.scroll_vertical = 0
		await _settle()
		await _capture(names[kind])
		_click(_menu._start)
		await _settle()
		var game: Control = _app._melody_game
		var exercise: Exercises.Exercise = game._progress.exercise
		_check(_only_visible(game) and root.size.x > root.size.y and exercise != null, "melody opens its real landscape game")
		if exercise != null:
			_check(exercise.kind == kind and exercise.clef == Notes.Clef.BASS and exercise.difficulty == Exercises.Difficulty.ADVANCED,
				"exercise receives the selected type, clef and difficulty")
			_check(kind == Exercises.Kind.INTERVAL or exercise.notes.size() == 24, "exercise receives the selected note count")
		_system_back()
		await _settle()
		_check_settings(Settings.Mode.MELODIES)
		_check(_menu._exercise_buttons[kind].button_pressed and _menu._clef_buttons[Notes.Clef.BASS].button_pressed,
			"exercise and clef survive system Back")
		_check(root.size == _size, "melody Back restores portrait")
	var saved := Settings.new(_settings_path)
	saved.load_settings()
	_check(saved.melody_kind == Exercises.Kind.INTERVAL and saved.melody_length == 24
		and saved.melody_clef == Notes.Clef.BASS and saved.melody_difficulty == Exercises.Difficulty.ADVANCED,
		"reload retains all four melody preferences including hidden length")
	_click(_menu._back)
	await _settle()
	await _open_mode(Settings.Mode.MELODIES)
	_check(_menu._exercise_buttons[Exercises.Kind.INTERVAL].button_pressed, "on-screen Back and reentry preserve selections")
	_system_back()
	await _settle()


func _check_notes_and_chords() -> void:
	await _open_mode(Settings.Mode.STAFF)
	_check_settings(Settings.Mode.STAFF)
	await _capture("07-staff-settings")
	for button: Button in _menu._range_buttons:
		_check_text(button)
	await _activate(_menu._range_buttons[0])
	_check(_app.preferences.range_mask == 1 and _menu._range_buttons[0].button_pressed, "last octave stays enabled")
	await _activate(_menu._range_buttons[3])
	await _activate(_menu._range_buttons[0])
	_click(_menu._start)
	await _settle()
	_check(_only_visible(_app._game) and _app._game._staff_mode and _app._game._staff.range_index == 3
		and root.size == _size, "staff exercise uses selected bass octave in portrait")
	_system_back()
	await _settle()
	_check_settings(Settings.Mode.STAFF)
	_system_back()
	await _settle()
	await _open_mode(Settings.Mode.NAMES)
	_check_settings(Settings.Mode.NAMES)
	await _activate(_menu._naming_buttons[1])
	_click(_menu._start)
	await _settle()
	_check(_only_visible(_app._game) and not _app._game._staff_mode and _app._game._letter_names
		and root.size == _size and _app.preferences.range_mask == 8, "name exercise uses letters and retains staff ranges")
	_system_back()
	await _settle()
	_check_settings(Settings.Mode.NAMES)
	_system_back()
	await _settle()
	await _open_mode(Settings.Mode.CHORDS)
	_check_settings(Settings.Mode.CHORDS)
	_check(_app.preferences.chord_mask == Chords.DEFAULT_GROUPS, "existing chord groups")
	await _activate(_menu._chord_buttons[3])
	_click(_menu._start)
	await _settle()
	_check(_only_visible(_app._chord_game) and root.size.x > root.size.y, "chord training launches in landscape")
	_system_back()
	await _settle()
	_check_settings(Settings.Mode.CHORDS)
	_check(_menu._chord_buttons[3].button_pressed, "chord group selection survives Back")
	_system_back()
	await _settle()


func _check_direct_modes() -> void:
	await _open_mode(Settings.Mode.FREE_PIANO)
	var piano: Control = _app._free_piano
	_check(_only_visible(piano) and root.size.x > root.size.y
		and piano._keyboard.white_keys.size() == 52, "Free Piano opens directly with its 88-note keyboard")
	await _capture("08-free-piano")
	_system_back()
	await _settle()
	await _open_mode(Settings.Mode.CIRCLE)
	_check(_only_visible(_app._circle) and root.size == _size, "Circle opens directly in portrait")
	_system_back()
	await _settle()
	_check(_only_visible(_menu) and _menu._home_scroll.visible, "Circle Back returns to workspace")
	_menu._home_scroll.scroll_vertical = 0
	await _capture("09-return-from-circle")
	await _open_mode(Settings.Mode.HARMONY_LAB)
	_check(_only_visible(_app._harmony_lab) and root.size == _size, "Harmony Lab opens its real library in portrait")
	_system_back()
	await _settle()
	_check(_only_visible(_menu) and _menu._home_scroll.visible, "Harmony Lab Back returns to workspace")
	_menu._home_scroll.scroll_vertical = 0
	await _capture("10-return-from-harmony-lab")


func _check_settings(mode: Settings.Mode) -> void:
	_check(_only_visible(_menu) and _menu._scroll.visible and not _menu._home_scroll.visible
		and _menu._settings_pages[mode].visible and _menu._start.text == "Начать", "dedicated settings for mode %d" % mode)
	var start: Rect2 = _menu._start.get_global_rect()
	_check(_menu.get_global_rect().encloses(start) and start.position.y >= _menu._scroll.get_global_rect().end.y,
		"Start stays inside the viewport below settings")
	_check(_menu.get_global_rect().encloses(_menu._back.get_global_rect()), "Back stays inside the viewport")
	_check(_menu._headline.get_global_rect().end.x <= _menu._sound.get_global_rect().position.x,
		"settings heading and sound target do not overlap")


func _check_control_width(control: Control, bounds: Rect2) -> void:
	var rect := control.get_global_rect()
	_check(rect.position.x >= bounds.position.x and rect.end.x <= bounds.end.x + 1.0, "control fits horizontally")
	_check((root.get_final_transform() * rect).size.y >= 44.0, "comfortable touch target")


func _check_text(button: Button) -> void:
	for control: Node in button.find_children("*", "Label", true, false):
		var label := control as Label
		_check(button.get_global_rect().encloses(label.get_global_rect())
			and label.get_visible_line_count() == label.get_line_count(), "card text fits: " + label.text)
	if not button.text.is_empty():
		var font := button.get_theme_font("font")
		_check(font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
			+ button.get_theme_stylebox("normal").get_minimum_size().x <= button.size.x, "chip text fits: " + button.text)


func _only_visible(screen: Control) -> bool:
	for current: Control in [_menu, _app._game, _app._chord_game, _app._melody_game, _app._free_piano,
			_app._circle, _app._circle_practice, _app._harmony_lab]:
		if current.visible != (current == screen):
			return false
	return true


func _open_mode(mode: Settings.Mode) -> void:
	await _activate(_menu._mode_buttons[mode])


func _activate(button: Button) -> void:
	var scroll: ScrollContainer = _menu._home_scroll if _menu._home_scroll.visible else _menu._scroll
	scroll.ensure_control_visible(button)
	await _settle()
	_click(button)
	await _settle()


func _click(button: Button) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = down
		root.push_input(event, true)


func _system_back() -> void:
	if _menu.visible and not _menu._scroll.visible and not _menu._credits.visible:
		_check(false, "Back was expected to return from an open page")
		return
	_app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)


func _settle() -> void:
	for frame in range(3):
		await process_frame


func _capture(label: String) -> void:
	if _headless:
		return
	var focused := root.gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	await _settle()
	await RenderingServer.frame_post_draw
	var snapshot := root.get_texture().get_image()
	var path := OUTPUT.path_join("%dx%d-%s.png" % [_size.x, _size.y, label])
	_check(snapshot.save_png(path) == OK, "screenshot saved: " + path)


func _measure_frames() -> void:
	await _settle()
	var idle := PackedFloat32Array()
	var previous_frame := Time.get_ticks_usec()
	for frame in range(120):
		await process_frame
		var current_frame := Time.get_ticks_usec()
		idle.append((current_frame - previous_frame) / 1000.0)
		previous_frame = current_frame
	idle.sort()
	var switching := PackedFloat32Array()
	for cycle in range(20):
		previous_frame = Time.get_ticks_usec()
		_click(_menu._mode_buttons[Settings.Mode.MELODIES])
		await process_frame
		var current_frame := Time.get_ticks_usec()
		switching.append((current_frame - previous_frame) / 1000.0)
		_system_back()
		await process_frame
		switching.append((Time.get_ticks_usec() - current_frame) / 1000.0)
	switching.sort()
	print("Desktop frame intervals in ms, idle p50/p95/max %.2f/%.2f/%.2f, navigation %.2f/%.2f/%.2f" % [
		idle[59], idle[113], idle[-1], switching[19], switching[37], switching[-1]])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
