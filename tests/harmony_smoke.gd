extends SceneTree

const Main := preload("res://main.tscn")
const Settings := preload("res://scripts/settings.gd")
const Lab := preload("res://scripts/harmony_lab.gd")
const Model := preload("res://scripts/harmony_composition.gd")
const Chord := preload("res://scripts/harmony_chords.gd")
const Store := preload("res://scripts/harmony_store.gd")
const Sequence := preload("res://scripts/harmony_sequence.gd")
const Picker := preload("res://scripts/harmony_picker.gd")
const Core := preload("res://tests/harmony_core.gd")
const OUTPUT := "res://builds/screenshots/0.7.2-regression/harmony"
const Notation := preload("res://scripts/harmony_notation.gd")
const Examples := preload("res://scripts/harmony_examples.gd")

var failures := 0
var checks := 0
var _app: Control
var _lab: Lab
var _headless := false
var _workspace: String
var _attacks: Array[Array] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(60).timeout.connect(func() -> void:
		printerr("Harmony Lab smoke timed out")
		quit(1))
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		root.size = Vector2i(405, 720)
	_workspace = "res://.godot/checks/harmony/" + Model.new_id()
	expect(DirAccess.make_dir_recursive_absolute(_workspace) == OK, "test fixture folder is writable")
	if not _headless:
		DirAccess.make_dir_recursive_absolute(OUTPUT)
		var marker := FileAccess.open(OUTPUT.path_join(".gdignore"), FileAccess.WRITE)
		marker.close()
	Core.new().run(self, _workspace.path_join("core"))
	await _make_app()
	var landscape := root.size.x > root.size.y
	var menu: Control = _app._menu
	await _press_visible(menu._mode_buttons[Settings.Mode.HARMONY_LAB])
	await _settle()
	expect(_lab.visible and not menu.visible and (landscape or root.size.y > root.size.x), "Harmony Lab opens directly from the workspace")
	if not _lab.visible:
		quit(1)
		return
	await _capture("01-library")
	_press(_button("+ Новая композиция"))
	await _settle()
	expect(_lab.project.events.is_empty() and _lab._play.disabled, "create an empty saved project with inactive transport")
	await _capture("02-empty-editor")
	await _check_picker()
	await _check_compact_picker()
	if landscape:
		await _check_measure_view(false)
	else:
		await _fill_progression()
		await _check_drag_and_edit()
		await _check_transport()
		await _check_save_and_transfer()
		await _check_measure_view(true)
	await _check_learning_workflow()
	await _check_refined_editor()
	print("Harmony Lab %sx%s (%s): %d checks, %d failures" % [root.size.x, root.size.y,
		"headless" if _headless else "graphical", checks, failures])
	quit(1 if failures else 0)


func _make_app() -> void:
	if root.size.x > root.size.y:
		root.content_scale_size = Vector2i(1280, 720)
	_app = Main.instantiate()
	_app.preferences = Settings.new(_workspace.path_join("settings.cfg"))
	root.add_child(_app)
	_lab = _app.get_node("HarmonyLab")
	_lab.store = Store.new(_workspace.path_join("library"))
	_app._audio.harmony_started.connect(func(notes: Array[int]) -> void: _attacks.append(notes))
	await _settle()


func _check_picker() -> void:
	_press(_button("+ Добавить аккорд"))
	await _settle()
	var picker := _picker()
	expect(not picker._listen.is_visible_in_tree(), "catalog has no separate Listen action")
	await _press_visible(_button("C"))
	expect(_attacks.is_empty() and picker._notation.staff.written_names(true) == PackedStringArray(["C4", "E4", "G4"]),
		"first root tap silently selects C major in the exact octave")
	var steps := picker._notation.staff.chord_notes.map(func(note: RefCounted) -> int: return note.staff_step())
	expect(steps == [-2, 0, 2], "treble staff places middle C on its ledger and E4 on the first line")
	await _settle()
	picker._body_scroll.ensure_control_visible(picker._notation)
	await _settle()
	await _capture("03-chord-picker-c-major")
	await _press_visible(_button("C"))
	expect(_attacks == [[60, 64, 67]], "second root tap plays the selected triad")
	await _press_visible(_button("Минор"))
	expect(_attacks.size() == 1 and picker._notation.staff.written_names(true) == PackedStringArray(["C4", "E♭4", "G4"]),
		"first quality tap silently updates the accidental")
	await _press_visible(_button("Минор"))
	expect(_attacks.size() == 2 and _attacks.back() == [60, 63, 67], "second quality tap previews the current chord")
	await _press_visible(_button("D"))
	expect(_attacks.size() == 2 and picker._notation.staff.written_names(true) == PackedStringArray(["D4", "F4", "A4"]),
		"switching roots updates all three written notes")
	await _press_visible(_button("Мажор"))
	await _press_visible(_button("F♯"))
	expect(_attacks.size() == 2 and picker._notation.staff.written_names(true) == PackedStringArray(["F♯4", "A♯4", "C♯5"]),
		"F sharp spells every pitch and octave correctly")
	await _settle()
	picker._body_scroll.ensure_control_visible(picker._notation)
	await _settle()
	await _capture("03b-chord-picker-f-sharp")
	await _show_spellings(picker)
	await _press_visible(picker._spelling_row.get_child(1) as Button)
	expect(picker._notation.staff.written_names(true) == PackedStringArray(["G♭4", "B♭4", "D♭5"]),
		"enharmonic alternative draws flats in their own staff positions")
	await _press_visible(_button("Уменьш."))
	expect(picker._notation.staff.written_names(true) == PackedStringArray(["G♭4", "B𝄫4", "D𝄫5"]), "diminished chord supports both double flats")
	await _press_visible(_button("Увелич."))
	expect(picker._notation.staff.written_names(true) == PackedStringArray(["G♭4", "B♭4", "D5"]), "augmented chord preserves diatonic spelling")
	_app._audio.set_enabled(false)
	await _press_visible(_button("Увелич."))
	expect(_attacks.size() == 2, "repeat tap respects mute")
	_app._audio.set_enabled(true)
	picker._option.select(Model.DURATIONS.find(2))
	_press(_button("Добавить"))
	await _settle()
	expect(_lab.project.events.size() == 1 and _lab.project.events[0].duration_beats == 2 and
		Chord.title(_lab.project.events[0].chord) == "Gbaug", "Add uses the selected chord and duration")
	_lab._create(Model.create("Новая последовательность"))
	await _settle()
	_attacks.clear()


func _check_compact_picker() -> void:
	_press(_button("+ Добавить аккорд"))
	await _settle()
	var picker := _picker()
	var roots := picker._root_buttons
	var grid := roots[0].get_parent() as GridContainer
	expect(grid.columns == 4 and roots.size() == 12 and not picker._spelling_toggle.visible,
		"empty picker shows a four-by-three grid and hides contextual spelling")
	expect(roots.map(func(button: Button) -> String: return button.text) == Chord.PITCH_NAMES,
		"each of the twelve piano pitch classes has one labelled root button")
	await _capture("root-01-grid")
	await _press_visible(roots[0])
	await _settle()
	var notation := picker._notation
	var selection := picker._selected.duplicate(true)
	picker._body_scroll.ensure_control_visible(notation)
	await _settle()
	expect(notation._audition.get_global_rect().is_equal_approx(notation.get_global_rect()), "audition target covers the full staff card")
	var targets := [notation._title.get_global_rect().get_center(), notation.staff.get_global_rect().get_center(),
		notation._caption.get_global_rect().get_center(), notation.get_global_rect().position + Vector2(3, 3)]
	for index in range(targets.size()):
		var point: Vector2 = targets[index]
		_touch(point, true)
		expect(_attacks.size() == index, "press alone does not trigger audition")
		if index == 1:
			await _capture("root-05-staff-press")
		_touch(point, false)
		expect(_attacks.size() == index + 1 and _attacks.back() == [60, 64, 67],
			"the title, staff, caption and card margin each give one exact attack")
	expect(picker._selected == selection and _lab.project.events.is_empty(), "card taps preserve the selection and never add a chord")
	await _press_visible(roots[0])
	expect(_attacks.size() == 5 and _attacks.back() == [60, 64, 67], "selected root still previews the same pitches")
	_app._audio.set_enabled(false)
	picker._body_scroll.ensure_control_visible(notation.staff)
	await _settle()
	_click(notation.staff.get_global_rect().get_center())
	expect(_attacks.size() == 5, "staff-card audition honors global mute")
	_app._audio.set_enabled(true)
	_attacks.clear()

	var reached := []
	for pitch_class in range(roots.size()):
		await _press_visible(roots[pitch_class])
		expect(roots[pitch_class].button_pressed, "selected root class stays highlighted")
		var spellings := Chord.root_spellings(pitch_class)
		var first: String = spellings[0]
		expect(picker._selected.root == first, "a different pitch class uses its default written root")
		reached.append(first)
		if spellings.size() > 1:
			await _show_spellings(picker)
			var choices := picker._spelling_row.get_children()
			expect(choices.size() == spellings.size(), "context lists only spellings for the active class")
			for index in range(1, spellings.size()):
				await _press_visible(choices[index] as Button)
				expect(picker._selected.root == spellings[index] and
					roots[pitch_class].text == Chord.written_pitch_class(spellings[index]), "alternate root is selected and visible")
				reached.append(spellings[index])
		else:
			expect(not picker._spelling_toggle.visible, "natural root with no alternative hides the spelling control")
	reached.sort()
	var all_roots := Chord.ROOTS.duplicate()
	all_roots.sort()
	expect(reached == all_roots and _attacks.size() == 1, "all 21 roots are reachable and each changed selection is silent")
	_attacks.clear()
	await _press_visible(roots[1])
	await _settle()
	if root.size.x < root.size.y:
		var body_bounds := picker._body_scroll.get_global_rect()
		expect(body_bounds.encloses(grid.get_global_rect()) and body_bounds.encloses(notation.get_global_rect()) and
			picker.get_global_rect().encloses(picker._submit.get_global_rect()), "the root grid, full staff and Add button fit in portrait")
	await _capture("root-02-c-sharp-major")
	await _capture("root-06-small-screen-picker")
	picker._option.select(Model.DURATIONS.find(2))
	await _press_visible(_button("Минор"))
	var minor_pitches: Array = picker._selected.pitches.duplicate()
	await _show_spellings(picker)
	await _press_visible(picker._spelling_row.get_child(1) as Button)
	expect(picker._selected.root == "Db" and picker._selected.quality == "minor" and picker._selected.pitches == minor_pitches and
		picker._option.get_selected_id() == 2 and _attacks.is_empty(), "spelling changes preserve quality, MIDI and duration")
	await _press_visible(_button("Мажор"))
	expect(notation.staff.written_names(true) == PackedStringArray(["D♭4", "F4", "A♭4"]), "D-flat major staff uses its diatonic names")
	await _capture("root-03-d-flat-major")
	await _press_visible(roots[0])
	await _show_spellings(picker)
	await _press_visible(picker._spelling_row.get_child(1) as Button)
	expect(notation.staff.written_names(true) == PackedStringArray(["B♯3", "D𝄪4", "F𝄪4"]) and
		picker._selected.pitches == [60, 64, 67], "B-sharp major retains MIDI and writes both double sharps")
	await _capture("root-04-b-sharp")
	await _press_visible(_button("Увелич."))
	expect(notation.staff.written_names(true) == PackedStringArray(["B♯3", "D𝄪4", "F𝄪♯4"]),
		"B-sharp augmented shows the correctly spelled triple sharp")
	await _capture("root-04b-triple-sharp")
	await _press_visible(_button("Мажор"))
	await _press_visible(roots[1])
	await _show_spellings(picker)
	await _press_visible(picker._spelling_row.get_child(1) as Button)
	_press(_button("Добавить"))
	await _settle()
	var project_id: String = _lab.project.id
	var event: Dictionary = _lab.project.events[0]
	expect(event.chord.root == "Db" and event.duration_beats == 2, "adding D-flat retains its written root and duration")
	Model.set_voicing(event, Chord.invert(event.chord, 2), 47, "Cb")
	_lab._mark_dirty()
	_lab._flush()
	_lab._open(project_id)
	var saved := _lab.project.duplicate(true)
	_lab._show_event(0)
	await _settle()
	await _event_action(0)
	picker = _picker()
	notation = picker._notation
	var pitches: Array = saved.events[0].sounding_pitches
	expect(_lab.project == saved and picker._root_buttons[1].text == "D♭" and picker._root_buttons[1].button_pressed and
		picker._option.get_selected_id() == 2 and picker._quality == "major", "replacing a saved chord restores spelling, quality, duration and voicing")
	await _capture("root-07-existing-enharmonic-edit")
	await _press_visible(notation._audition)
	expect(_attacks == [pitches], "editing staff auditions the saved inversion and slash bass together once")
	await _show_spellings(picker)
	await _press_visible(picker._spelling_row.get_child(0) as Button)
	_press(_button("Применить"))
	await _settle()
	event = _lab.project.events[0]
	expect(event.chord.root == "C#" and event.sounding_pitches == pitches and event.voicing == saved.events[0].voicing and
		event.bass_spelling == "Cb" and event.id == saved.events[0].id and _attacks.size() == 1,
		"applying an enharmonic respelling preserves the saved inversion, slash bass, exact pitches and ID")
	_lab._create(Model.create("Новая последовательность"))
	await _settle()
	_attacks.clear()


func _show_spellings(picker: Picker) -> void:
	if not picker._spelling_row.visible:
		await _press_visible(picker._spelling_toggle)
		await _settle()


func _check_measure_view(full: bool) -> void:
	var example := Model.create("Аккорды через тактовую черту")
	example.bpm = 120
	example.repeat = 2
	for pair in [["C", 1], ["Bb", 2], ["F", 2], ["G", 1], ["C", 4]]:
		Model.insert(example, example.events.size(), Chord.catalog(pair[0], "major"), pair[1])
	_lab._create(example)
	await _settle()
	_press(_button("По тактам"))
	await _settle()
	var sequence := _lab._sequence
	var slices := Sequence.measure_slices(example.events)
	expect(slices.map(func(bar: Array) -> int: return bar.size()) == [3, 3, 1], "measures contain attack and continuation slices")
	expect(slices[0][2] == {"index": 2, "offset": 3, "length": 1, "attack": true} and
		slices[1][0] == {"index": 2, "offset": 0, "length": 1, "attack": false} and
		slices[2][0] == {"index": 4, "offset": 0, "length": 2, "attack": false}, "crossings reuse event indices and partial measure has two beats")
	expect(sequence._groups[2].size() == 2 and sequence._groups[4].size() == 2 and
		"2 полных такта + 2 доли" in _lab._run_details.text, "both sides render from the same event and duration states partial bar")
	var first_track := sequence._tracks[0].get_global_rect()
	var fragment: PanelContainer = sequence._groups[2][0].panel
	expect(is_equal_approx(fragment.anchor_left, 0.75) and is_equal_approx(fragment.anchor_right, 1.0) and first_track.size.x > 0,
		"timeline places the F attack in beat four at proportional width")
	await _capture("13-measure-crossing")

	if full:
		var first := _part_point(sequence._rows[0])
		var continuation := _part_point(sequence._groups[2][1].panel)
		var ids: Array = example.events.map(func(event: Dictionary) -> String: return event.id)
		_touch(continuation, true)
		await _hold()
		_drag(first)
		expect(sequence._from == 2 and sequence._phase == Sequence.Phase.REORDERING,
			"long press on continuation picks up the whole event")
		_touch(first, false, true)
		expect(_lab.project.events.map(func(event: Dictionary) -> String: return event.id) == ids and not _lab._dirty,
			"cancel leaves the exact sequence and save state untouched")
		_touch(continuation, true)
		await _hold()
		_drag(first)
		_touch(first, false)
		await _settle()
		expect(example.events.size() == 5 and example.events[0].id == ids[2] and
			example.events[1].start_beat == 2, "move of a split event recalculates timing without duplicating")
		_press(_button("Отменить"))
		await _settle()
		sequence = _lab._sequence
	var contents := _lab.project.duplicate(true)
	_press(_button("Список"))
	await _settle()
	expect(not sequence.by_measure and sequence._rows.size() == 5 and _lab.project == contents,
		"compact view changes representation without changing dates, events or ordering")
	_press(_button("По тактам"))
	await _settle()
	_attacks.clear()
	_press(_lab._play)
	_lab.set_process(false)
	var origin: int = _lab._transport._origin
	_lab._tick(origin + 1500000)
	var attack_count := _attacks.size()
	_lab._tick(origin + 2000000)
	await _settle()
	expect(_attacks.size() == attack_count and sequence._active == 2 and sequence._beat == 4 and
		_lab._position.text == "Такт 2 / 3 · доля 1 / 4", "playback crosses the bar without retrigger and highlights the scheduler position")
	expect(sequence._beat_tiles[1][0].get_theme_stylebox("panel") == sequence._beat_playing and
		sequence._groups[2][0].panel.get_theme_stylebox("panel") == sequence._playing and
		sequence._groups[2][1].panel.get_theme_stylebox("panel") == sequence._playing,
		"both event fragments and only the current beat receive active styling")
	await _capture("14-measure-playback")
	if full:
		var play_point := _part_point(sequence._groups[2][1].panel)
		_touch(play_point, true)
		await _hold()
		_touch(play_point, false)
		expect(sequence._active == 2 and _attacks.size() == attack_count and
			sequence._groups[2][1].edit.disabled and _lab.project == contents,
			"playback prevents preview, editing and long-press movement")
	_lab._tick(origin + 5000000)
	expect(_lab._transport.pass_index == 1 and sequence._beat == 0, "second pass starts after ten real beats")
	_lab._tick(origin + 9999999)
	expect(sequence._beat == 9, "second pass sustains through its final partial measure")
	_lab._tick(origin + 10000000)
	expect(sequence._active == -1 and _lab._stop.disabled, "two passes end at twenty beats without measure padding")

	_lab._show_event(2)
	await _settle()
	var notation: Notation
	for item in _lab._frame.find_children("*", "PanelContainer", true, false):
		if item is Notation:
			notation = item
	expect(notation != null and notation.staff.written_names(true) == PackedStringArray(["F4", "A4", "C5"]),
		"Edit renders the current saved voicing")
	await _capture("15-edit-notation")
	var edit_id: String = _lab.project.events[2].id
	await _event_action(0)
	await _settle()
	var picker := _picker()
	expect(picker._option.get_selected_id() == 2, "picker inherits the saved duration")
	await _press_visible(_button("C"))
	_press(_button("Применить"))
	await _settle()
	expect(_lab._page == Lab.Page.EVENT and _lab.project.events[2].id == edit_id and
		_lab.project.events[2].duration_beats == 2 and Chord.title(_lab.project.events[2].chord) == "C",
		"replacement returns to Edit with unchanged duration and event ID")
	_lab.close_page()
	var long := Model.create("Двенадцать аккордов")
	for index in range(12):
		Model.insert(long, index, Chord.catalog("C" if index % 2 == 0 else "Bb", "major"), Model.DURATIONS[index % 3])
	_lab._create(long)
	await _settle()
	_press(_button("Список"))
	await _settle()
	expect(_lab._sequence._rows.size() == 12, "compact list renders all twelve chord events")
	await _capture("16-compact-list")


func _part_point(panel: Control) -> Vector2:
	var rect := panel.get_global_rect()
	return Vector2(rect.position.x + 18, rect.get_center().y)


func _press_visible(button: Button) -> void:
	if button == null:
		return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			await _settle()
			break
		parent = parent.get_parent()
	_press(button)



func _fill_progression() -> void:
	for index in range(4):
		_press(_button("+ Добавить аккорд"))
		await _settle()
		var picker := _picker()
		if index == 2:
			_press(_button("Минор"))
		var symbol: String = ["F", "C", "Dm", "Bb"][index]
		_press(_button(["F", "C", "D", "B♭"][index]))
		expect(Chord.title(picker._selected) == symbol, "catalog chooses " + symbol)
		_press(_button("Добавить"))
		await _settle()
	expect(_titles() == ["F", "C", "Dm", "Bb"] and Model.measures(_lab.project) == 4,
		"phone actions build four four-beat chords")
	await _capture("04-four-chords")
	var sequence := _lab._sequence
	var chord_point := _part_point(sequence._rows[0])
	_touch(chord_point, true)
	expect(_attacks.is_empty(), "preview waits until touch release")
	_touch(chord_point, false)
	expect(_attacks == [[65, 69, 72]], "one touch produces a single F preview")
	_click(_part_point(sequence._rows[1]))
	expect(_attacks.size() == 2 and _attacks.back() == [60, 64, 67], "mouse click previews C")
	_touch(chord_point, true)
	_drag(chord_point - Vector2(0, 75))
	_touch(chord_point - Vector2(0, 75), false)
	expect(_attacks.size() == 2 and _titles()[0] == "F", "swiping card bodies neither previews nor reorders")
	for tap_index in range(3):
		_touch(chord_point, true)
		_touch(chord_point, false)
	expect(_attacks.size() == 5 and sequence._pointer == Sequence.NO_POINTER and _titles()[0] == "F",
		"rapid taps each preview and never start a reorder")
	_attacks.resize(2)


func _check_drag_and_edit() -> void:
	_press(_button("Список"))
	await _settle()
	var sequence := _lab._sequence
	var start := _part_point(sequence._rows[0])
	var destination := sequence._rows[2].get_global_rect().get_center() + Vector2(0, 24)
	_touch(start, true)
	_drag(start + Vector2(0, 65))
	_touch(start + Vector2(0, 65), false)
	expect(_titles() == ["F", "C", "Dm", "Bb"], "quick swipe on a handle scrolls instead of moving")
	_touch(start, true)
	await _hold()
	_drag(destination)
	expect(sequence._pointer == 0 and sequence._phase == Sequence.Phase.REORDERING and _titles()[0] == "F",
		"long press previews insertion (pointer %d, phase %d, index %d, scroll %d)" %
			[sequence._pointer, sequence._phase, sequence._from, sequence.scroll_vertical])
	await _capture("05-drag-reorder")
	_touch(destination, false, true)
	expect(_titles() == ["F", "C", "Dm", "Bb"] and _attacks.size() == 2 and sequence._pointer == Sequence.NO_POINTER,
		"canceled drag leaves order and audio unchanged")
	await _settle()
	start = _part_point(sequence._rows[0])
	destination = sequence._rows[2].get_global_rect().get_center() + Vector2(0, 24)
	_touch(start, true)
	await _hold()
	_drag(destination)
	var dropped_slot := sequence._slot
	_touch(destination, false)
	await _settle()
	expect(_titles() == ["C", "Dm", "F", "Bb"] and _lab.project.events[2].start_beat == 8,
		"drop moves the correct card by touch (slot %d, order %s)" % [dropped_slot, _titles()])
	_press(_button("Отменить"))
	await _settle()
	expect(_titles() == ["F", "C", "Dm", "Bb"], "Undo restores the old sequence")
	var pencil: Button = _lab._sequence._groups[0][0].edit
	var pencil_point := pencil.get_global_rect().get_center()
	_touch(pencil_point, true)
	await _hold()
	expect(_lab._sequence._pointer == Sequence.NO_POINTER, "holding the pencil never picks up the card")
	_touch(pencil_point, false)
	await _settle()
	expect(_lab._page == Lab.Page.EVENT, "pencil opens the event editor through touch")
	_press(_button("2 дол."))
	expect(_lab.project.events[0].duration_beats == 2 and _lab.project.events[1].start_beat == 2,
		"edit duration recalculates positions with sustained cross-bar event")
	await _event_action(1)
	await _settle()
	_press(_button("Свой аккорд"))
	await _settle()
	var picker := _picker()
	var keys := picker._keyboard
	var name: LineEdit = picker._name_edit
	name.text = "Три звука"
	name.text_changed.emit(name.text)
	for midi in [60, 64, 67]:
		var rectangle := keys.white_rect(keys.white_keys.find(midi))
		var point := keys.global_position + Vector2(rectangle.get_center().x, rectangle.end.y - 18)
		_touch(point, true)
		_touch(point, false)
	await _settle()
	expect(keys.selected == [60, 64, 67], "keyboard taps toggle exact pitches")
	expect(picker._notation.staff.chord_notes.map(func(note: RefCounted) -> int: return note.midi) == [60, 64, 67] and
		picker._notation._title.text == "Три звука", "custom notation preserves selected pitches and the user's name")
	await _capture("06-custom-chord")
	_press(_button("Прослушать"))
	expect(_attacks.back() == [60, 64, 67], "custom preview attacks the complete selection")
	_press(_button("E4  ×"))
	expect(keys.selected == [60, 67], "selected note chip removes an individual pitch")
	_press(_button("Добавить"))
	await _settle()
	expect(_titles() == ["F", "Три звука", "C", "Dm", "Bb"] and _lab.project.events[1].chord.pitches == [60, 67],
		"custom chord is inserted after the chosen chord")
	_lab._show_event(1)
	await _settle()
	await _event_action(2)
	await _settle()
	expect(_lab.project.events[1].chord == _lab.project.events[2].chord and _lab.project.events[1].id != _lab.project.events[2].id,
		"Duplicate creates a distinct sounding event")
	_lab._show_event(2)
	await _settle()
	await _event_action(3)
	expect(_lab._page == Lab.Page.EVENT_DELETE and _titles().count("Три звука") == 2, "delete asks for confirmation")
	_press(_button("Отмена"))
	await _settle()
	expect(_lab._page == Lab.Page.EVENT and _titles().count("Три звука") == 2, "cancel keeps the event")
	await _event_action(3)
	_press(_button("Удалить аккорд"))
	await _settle()
	expect(_titles().count("Три звука") == 1, "Delete removes a card")
	_press(_button("Отменить"))
	await _settle()
	expect(_titles().count("Три звука") == 2, "Undo restores a deleted card")
	await _check_long_drag()


func _check_long_drag() -> void:
	var long := Model.create("Длинная композиция")
	for index in range(96):
		Model.insert(long, index, Chord.catalog("C", "major"), 4)
	var id: String = long.events[0].id
	_lab._create(long)
	await _settle()
	var sequence := _lab._sequence
	expect(sequence.get_v_scroll_bar().max_value > sequence.get_v_scroll_bar().page, "long sequence scrolls")
	var start := _part_point(sequence._rows[0])
	var swipe_start := _part_point(sequence._rows[2])
	_touch(swipe_start, true)
	_drag(swipe_start - Vector2(0, 124))
	_touch(swipe_start - Vector2(0, 124), false)
	await _settle()
	expect(sequence.scroll_vertical > 90 and _lab.project.events[0].id == id, "ordinary drag scrolls without changing order")
	sequence.scroll_vertical = 0
	await _settle()
	var bounds := sequence.get_global_rect()
	var edge := Vector2(start.x + 8, bounds.end.y - 8)
	_touch(start, true)
	await _hold()
	_drag(edge)
	await create_timer(0.36).timeout
	var scrolled := sequence.scroll_vertical
	var slot := sequence._slot
	_touch(edge, false)
	await _settle()
	expect(scrolled > 100 and slot > 3 and _lab.project.events[slot - 1].id == id,
		"edge auto-scroll drops the original event at the displayed insertion slot (scroll %d, slot %d)" % [scrolled, slot])
	_press(_button("Отменить"))
	await _settle()
	expect(_lab.project.events[0].id == id, "undo long-range reorder")
	_lab._create(Core.example_fixture())
	await _settle()
	await _capture("04b-four-chord-example")


func _check_transport() -> void:
	_press(_button("90 BPM"))
	await _settle()
	_press(_button("+"))
	_press(_button("Цикл"))
	await _capture("07-tempo-repeat")
	_press(_button("Применить"))
	await _settle()
	expect(_lab.project.bpm == 95 and _lab.project.repeat == 0, "tempo and continuous loop apply")
	_press(_button("95 BPM"))
	await _settle()
	_press(_button("−"))
	_press(_button("2×"))
	_press(_button("Применить"))
	await _settle()
	expect(_lab.project.bpm == 90 and _lab.project.repeat == 2, "restore 90 BPM and two passes")
	_attacks.clear()
	_press(_lab._play)
	await _settle()
	expect(_attacks == [[65, 69, 72]] and _lab._sequence._active == 0 and "Такт 1" in _lab._position.text,
		"play attacks and highlights first card")
	await _capture("08-playback")
	_press(_lab._play)
	expect("Продолжить" in _lab._play.text, "pause exposes resume")
	_press(_lab._play)
	await _settle()
	expect(_attacks.size() == 1, "resume does not replay attack")
	_press(_lab._stop)
	await _settle()
	expect(_lab._stop.disabled and _lab._sequence._active == -1, "stop clears active card")
	_app._audio.set_enabled(false)
	_press(_lab._play)
	expect(_attacks.size() == 1 and _lab._sequence._active == 0, "mute silences attacks while leaving transport running")
	_lab.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	expect(_lab._stop.disabled and _lab._sequence._active == -1, "app background stops transport")
	_app._audio.set_enabled(true)
	_press(_lab._play)
	_press(_button("90 BPM"))
	expect(_lab._page == Lab.Page.EDITOR and _lab.is_processing() and _lab._add_button.disabled,
		"editing entry points stay locked during playback")
	_press(_lab._stop)
	await _settle()
	if not _headless:
		await _check_mixed_audio()


func _check_mixed_audio() -> void:
	var monitor := AudioEffectCapture.new()
	var slot := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, monitor, slot)
	_app._audio.fade_harmony()
	await create_timer(0.12).timeout
	monitor.clear_buffer()
	_lab._preview_event(0)
	await create_timer(0.22).timeout
	var first := monitor.get_buffer(monitor.get_frames_available())
	monitor.clear_buffer()
	_lab._preview_event(0)
	await create_timer(0.22).timeout
	var second := monitor.get_buffer(monitor.get_frames_available())
	AudioServer.remove_bus_effect(0, slot)
	expect(_peak(first) > 0.01 and _peak(second) > 0.01 and _app._audio._harmony_keys.size() == 64,
		"WASAPI mix contains both repeated attacks with bounded polyphony")
	var active := 0
	for voice in _app._audio._harmony_keys:
		if voice.playing:
			active += 1
	expect(active >= 6, "same chord uses independent simultaneous voices while previous tails ring")


func _check_learning_workflow() -> void:
	_lab._show_library()
	await _settle()
	_press(_button("Примеры"))
	await _settle()
	var saved_count: int = _lab.store.library().projects.size()
	expect(_lab._page == Lab.Page.EXAMPLES, "library exposes the offline examples")
	await _capture("071-01-examples")
	await _press_visible(_button("I–V–vi–IV  ·  Четыре аккорда в мажоре"))
	await _settle()
	await _capture("071-02-example-detail")
	_attacks.clear()
	_press(_lab._preview_play)
	expect(_attacks == [[60, 64, 67]] and _lab.project.is_empty() and _lab.store.library().projects.size() == saved_count,
		"listening to the pop example opens no personal project")
	_lab.set_process(false)
	var origin := _lab._transport._origin
	for index in range(1, 4):
		_lab._tick(origin + Lab.Transport.time_at_beat(index * 4.0, 96))
	expect(_attacks == [[60, 64, 67], [67, 71, 74], [69, 72, 76], [65, 69, 72]], "example audibly dispatches C G Am F")
	_press(_lab._preview_stop)
	_press(_button("Открыть копию"))
	await _settle()
	var copy_id: String = _lab.project.id
	expect(_lab.store.library().projects.size() == saved_count + 1 and _titles() == ["C", "G", "Am", "F"],
		"opening a copy saves a separate editable composition")
	_press(_button("По тактам"))
	await _settle()
	await _capture("071-03-copied-example")
	if root.size == Vector2i(320, 640):
		await _capture("071-10-small-screen")
	_attacks.clear()
	_press(_lab._play)
	await _settle()
	expect(_attacks == [[60, 64, 67]] and _lab._sequence._active == 0, "block playback highlights and attacks the first chord")
	await _capture("071-04-block-playback")
	_press(_lab._stop)
	var selector := _selector("Способ исполнения")
	if not _headless:
		_press(selector)
		await _settle()
		expect(selector.get_popup().visible, "the accompaniment dropdown opens through the editor")
		await _capture("071-05-accompaniment-selector")
		selector.get_popup().hide()
		await _settle()
	_choose(selector, "Перебор")
	expect(_lab.project.default_pattern == "broken" and _lab.project.events[0].pattern == null,
		"pattern choice changes the project default without writing event overrides")
	_lab._sequence.preview_requested.emit(0)
	expect(_attacks.back() == [60, 64, 67], "quick audition still plays the complete chord")
	_attacks.clear()
	_press(_lab._play)
	_lab.set_process(false)
	origin = _lab._transport._origin
	_lab._tick(origin + Lab.Transport.time_at_beat(0.5, 96))
	expect(_attacks == [[60], [64]] and _lab._sequence._active == 0, "broken playback dispatches independent eighth notes")
	await _capture("071-06-broken-playback")
	_lab.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_lab._tick(origin + Lab.Transport.time_at_beat(3.5, 96))
	expect(_attacks == [[60], [64]] and not _lab.is_processing(), "backgrounding cancels scheduled eighth notes")

	_lab._show_event(0)
	await _settle()
	_choose(_selector("Обращение трезвучия"), "1-е обращение")
	var notation := _event_notation()
	expect(notation.staff.written_names(true) == PackedStringArray(["E4", "G4", "C5"]) and
		_lab.project.events[0].sounding_pitches == [64, 67, 72], "first inversion updates the exact notes and staff immediately")
	_press(_button("Аккорд"))
	expect(_attacks.back() == [64, 67, 72], "quick preview uses the selected inversion")
	await _settle()
	await _capture("071-07-first-inversion")
	_choose(_selector("Обращение трезвучия"), "Основной вид")
	await _pick_bass("E")
	notation = _event_notation()
	await _settle()
	expect(notation._title.text == "C/E" and notation.staff.written_names(true) == PackedStringArray(["E3", "C4", "G4"]) and
		notation.staff._bass.size() == 1 and notation.staff._treble.size() == 2, "C/E shows E3 in bass clef and plays literal notes")
	await _capture("071-08-slash-chord")
	_attacks.clear()
	await _press_visible(_lab._preview_play)
	_lab.set_process(false)
	origin = _lab._transport._origin
	_lab._tick(origin + Lab.Transport.time_at_beat(0.5, 96))
	expect(_attacks == [[52], [60]], "event audition uses the chosen pattern and explicit bass")
	_lab.close_page()
	await _settle()
	_lab._tick(origin + Lab.Transport.time_at_beat(1.0, 96))
	expect(_attacks == [[52], [60]], "leaving the chord editor stops the pattern audition")

	_lab._show_event(1)
	await _settle()
	await _pick_bass("B")
	expect(_event_notation().staff.written_names(true) == PackedStringArray(["B3", "G4", "D5"]),
		"the copied G chord becomes G/B with B3 as actual bass")
	_lab.close_page()
	await _settle()
	expect(Examples.progression(_lab.project) == "C/E → G/B → Am → F" and
		Examples.progression(Examples.arrangement(2)) == "C → G → Am → F" and Examples.arrangement(2).default_pattern == "attack",
		"changing a copied progression leaves the authored example intact")
	_lab.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var expected := _lab.project.duplicate(true)
	_lab.close_page()
	_lab.enter()
	await _settle()
	_press(_button("Продолжить  ·  " + expected.title))
	await _settle()
	expect(_lab.project == expected and _lab.project.id == copy_id, "after leaving and re-entering, Continue reloads the saved voicings")
	var path := _workspace.path_join("demo-export.nikspiano.json")
	_lab._interchange._selected(true, PackedStringArray([path]), 0, "export", _lab.project)
	_lab._interchange._selected(true, PackedStringArray([path]), 0, "import", {})
	await _settle()
	expect(_lab.project.id != copy_id and _lab.project.events == expected.events and _lab.project.default_pattern == "broken",
		"export and import preserve the edited progression in another project")

	var legacy_path := _workspace.path_join("from-070-ux.nikspiano.json")
	var fixture := FileAccess.open(legacy_path, FileAccess.WRITE)
	fixture.store_string(JSON.stringify(Core.refined_document()))
	fixture.close()
	_lab._interchange._selected(true, PackedStringArray([legacy_path]), 0, "import", {})
	await _settle()
	_attacks.clear()
	_press(_lab._play)
	expect(_attacks == [[65, 69, 72]] and _lab.project.default_pattern == "attack" and Model.length_beats(_lab.project) == 7,
		"opening a 0.7.0 UX project produces its original block attack and partial measure")
	await _capture("071-09-migrated-project")
	await _settle()
	_press(_lab._stop)
	expect(_lab._transport.state == Lab.Transport.State.STOPPED, "Stop immediately disarms the transport")
	await create_timer(0.15).timeout
	await _settle()
	if not _headless:
		expect(_app._audio._harmony_keys.all(func(voice: AudioStreamPlayer) -> bool: return not voice.playing),
			"Stop releases Harmony Lab voices")


func _check_refined_editor() -> void:
	var project := Model.create("Проверка редактора")
	project.bpm = 120
	Model.insert(project, 0, Chord.catalog("C", "major"), 2)
	_lab._create(project)
	await _settle()
	_lab._show_event(0)
	await _settle()
	expect(_label_exists("Исполнение: Одновременно (из проекта)") and _label_exists(Lab.Patterns.HINTS.attack),
		"block audition identifies its project default")
	await _capture("ux-01-block-editor")
	_lab.close_page()
	await _settle()
	_choose(_selector("Способ исполнения"), "Удары по долям")
	_lab._show_event(0)
	await _settle()
	expect(_label_exists("Исполнение: Удары по долям (из проекта)") and _label_exists(Lab.Patterns.HINTS.repeated),
		"the active inherited pattern and its actual rhythm are shown")
	await _capture("ux-02-repeated-editor")
	_attacks.clear()
	_press(_button("Аккорд"))
	expect(_attacks == [[60, 64, 67]] and not _lab.is_processing(), "Аккорд plays one isolated block under a repeated default")
	_attacks.clear()
	_press(_lab._preview_play)
	_lab.set_process(false)
	var origin := _lab._transport._origin
	_lab._tick(origin + 499999)
	expect(_attacks.size() == 1, "inherited repetition waits until the beat")
	_lab._tick(origin + 500000)
	_lab._tick(origin + 1000000)
	_lab._tick(origin + 1000001)
	expect(_attacks == [[60, 64, 67], [60, 64, 67]] and _lab._transport.state == Lab.Transport.State.STOPPED,
		"the two-beat event inherits repetition and ends exactly at the boundary")

	project.events[0].pattern = "attack"
	_lab._mark_dirty()
	_lab._flush()
	_lab._open(project.id)
	await _settle()
	_lab._show_event(0)
	await _settle()
	expect(_label_exists("Для аккорда: Одновременно\nВ проекте: Удары по долям") and _label_exists(Lab.Patterns.HINTS.attack),
		"a saved block override explains why the project default differs")
	_attacks.clear()
	_press(_lab._preview_play)
	_lab.set_process(false)
	origin = _lab._transport._origin
	_lab._tick(origin + 500000)
	_lab._tick(origin + 1000000)
	expect(_attacks == [[60, 64, 67]], "accompaniment preview obeys the explicit block override")
	_attacks.clear()
	_app._audio.set_enabled(false)
	_press(_button("Аккорд"))
	_press(_lab._preview_play)
	expect(_attacks.is_empty() and _lab._transport.state == Lab.Transport.State.PLAYING, "both audition buttons honor mute")
	_lab._stop_playback()
	_app._audio.set_enabled(true)
	_choose(_selector("Обращение трезвучия"), "2-е обращение")
	var notation := _event_notation()
	expect(notation._title.text == "C/G" and notation.staff.written_names(true) == PackedStringArray(["G4", "C5", "E5"]) and
		_label_exists("До мажор — второе обращение"), "automatic second inversion names the real G4 bass and C/G symbol")
	await _capture("ux-03-second-inversion")
	await _capture("ux-09-editor-footer")
	expect(_lab._frame.get_global_rect().encloses(_button("Готово").get_global_rect()), "the fixed Done button is visible")

	var bass := await _open_bass()
	expect(_label_exists("Использовать нижний звук выбранного обращения.\nСейчас в басу: G4"),
		"automatic bass is explained using the actual inversion")
	var grid := bass.find_children("*", "GridContainer", true, false)[0] as GridContainer
	expect(grid.columns == 4 and grid.get_child_count() == 12 and
		grid.get_children().all(func(button: Button) -> bool: return not button.disabled),
		"all twelve pitch classes have enabled grid targets for the triad")
	await _capture("ux-04-bass-grid")
	await _press_visible(_button("C♯"))
	var midi: int = bass._midi
	_choose(_selector("Написание басовой ноты"), "Запись: D♭")
	expect(bass._midi == midi and bass._spelling == "Db", "enharmonic spelling keeps the exact MIDI pitch")
	await _press_visible(_button("E"))
	expect(bass._midi == 64 and bass._higher.disabled, "the selector only offers bass registers below the other pitches")
	await _press_visible(bass._lower)
	expect(bass._midi == 52 and bass._summary.text == "Выбрано: E3  ·  Аккорд: C/E", "one octave down selects E3")
	if root.size.x <= root.size.y:
		var scroll := bass.get_child(0) as ScrollContainer
		expect(scroll.get_v_scroll_bar().max_value <= scroll.get_v_scroll_bar().page + 1.0, "the bass grid and register fit in portrait")
	await _capture("ux-04b-bass-register")
	await _settle()
	_press(_button("Применить бас"))
	await _settle()
	notation = _event_notation()
	expect(notation.staff.written_names(true) == PackedStringArray(["E3", "G4", "C5"]) and
		_label_exists("До мажор — первое обращение") and _label_exists("Расположение без отдельного баса"),
		"independent E3 changes the audible inversion while keeping the underlying placement legible")
	await _capture("ux-05-custom-bass")
	await _event_action(0, "ux-06-event-menu")
	expect(_lab._page == Lab.Page.PICKER, "replace action opens the existing chord picker")
	_lab.close_page()
	await _settle()
	_lab._flush()
	var saved := _lab.store.load_project(project.id)
	expect(saved.events[0].bass_midi == 52 and saved.events[0].bass_spelling == "E" and saved.events[0].pattern == "attack",
		"save and reopen keep the custom bass, actual voicing and explicit pattern")
	bass = await _open_bass()
	expect(bass._midi == 52 and bass._spelling == "E", "bass selector reopens the saved MIDI and spelling")
	_lab.close_page()

	_lab._show_library()
	await _settle()
	_press(_button("Примеры"))
	await _settle()
	await _press_visible(_button("I–V⁶–vi–IV  ·  Плавное движение баса"))
	await _settle()
	var count: int = _lab.store.library().projects.size()
	await _capture("ux-07-example-detail")
	_press(_button("Сравнить звучание"))
	await _settle()
	expect(_label_exists("C → G/B → Am → F") and _label_exists("C → G → Am → F"), "both versions are visible for comparison")
	await _capture("ux-08-example-comparison")
	for variant in range(2):
		_attacks.clear()
		await _press_visible(_lab._comparison_buttons[variant])
		_lab.set_process(false)
		origin = _lab._transport._origin
		_lab._tick(origin + 3000000)
		_lab._tick(origin + 3750000)
		var second_bass := 47 if variant == 0 else 55
		expect(_attacks == [[48], [second_bass], [67, 71, 74]], "A/B playback uses identical accompaniment and only changes bass")
	expect(_lab.project.is_empty() and _lab.store.library().projects.size() == count,
		"comparison playback persists no personal composition")
	_lab.close_page()
	expect(_lab._transport.state == Lab.Transport.State.STOPPED, "leaving comparison cancels playback")
	await create_timer(0.15).timeout
	await _settle()


func _event_action(index: int, capture := "") -> void:
	var menu := _button("⋯") as MenuButton
	var popup := menu.get_popup()
	if not _headless:
		_press(menu)
		await _settle()
		expect(popup.visible and popup.item_count == 4, "secondary event menu opens with four actions")
		if not capture.is_empty():
			await _capture(capture)
		popup.hide()
		await _settle()
	popup.id_pressed.emit(index)
	await _settle()


func _open_bass() -> Lab.BassSelector:
	for button: Button in _lab._frame.find_children("*", "Button", true, false):
		if button.accessibility_name == "Басовая нота":
			await _press_visible(button)
			break
	await _settle()
	for child in _lab._frame.get_children():
		if child is Lab.BassSelector:
			return child
	expect(false, "the bass selector is present")
	return null


func _pick_bass(caption: String) -> void:
	await _open_bass()
	await _press_visible(_button(caption))
	_press(_button("Применить бас"))
	await _settle()


func _label_exists(caption: String) -> bool:
	for label: Label in _lab._frame.find_children("*", "Label", true, false):
		if label.text == caption:
			return true
	return false


func _selector(accessible_name: String) -> OptionButton:
	for option: OptionButton in _lab._frame.find_children("*", "OptionButton", true, false):
		if option.accessibility_name == accessible_name:
			return option
	expect(false, "selector exists: " + accessible_name)
	return null


func _choose(option: OptionButton, caption: String) -> void:
	for index in range(option.item_count):
		if option.get_item_text(index) == caption:
			option.select(index)
			option.item_selected.emit(index)
			return
	expect(false, "selector item exists: " + caption)


func _event_notation() -> Notation:
	for panel in _lab._frame.find_children("*", "PanelContainer", true, false):
		if panel is Notation:
			return panel
	expect(false, "event notation exists")
	return null


func _peak(frames: PackedVector2Array) -> float:
	var peak := 0.0
	for sample: Vector2 in frames:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	return peak


func _check_save_and_transfer() -> void:
	var id: String = _lab.project.id
	_press(_button("Проект"))
	await _settle()
	_press(_button("Переименовать"))
	await _settle()
	var field: LineEdit = _lab._frame.find_children("*", "LineEdit", true, false)[0]
	field.text = "Моя последовательность"
	_press(_button("Сохранить название"))
	await _settle()
	await create_timer(0.45).timeout
	var expected := _lab.store.load_project(id)
	expect(expected == _lab.project and not _lab._dirty, "debounced autosave persists rename and edited content")
	_lab._settings_changed(100, 4)
	_lab.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	expected = _lab.store.load_project(id)
	expect(expected.bpm == 100 and expected.repeat == 4 and not _lab._dirty, "background flushes pending autosave")
	_app.queue_free()
	await _settle()
	await _make_app()
	await _press_visible(_app._menu._mode_buttons[Settings.Mode.HARMONY_LAB])
	await _settle()
	expect(_lab.visible and _lab._page == Lab.Page.LIBRARY, "relaunch restores last selected mode")
	await _capture("09-library-saved")
	var resume := _button("Продолжить  ·  Моя последовательность")
	_press(resume)
	await _settle()
	expect(_lab.project == expected, "Continue reopens the exact same saved sequence")
	expect(not _lab._sequence.by_measure, "compact view persists independently of the composition")
	_press(_button("Проект"))
	await _settle()
	await _capture("10-export-project-menu")
	var path := _workspace.path_join("test" + Store.SUFFIX)
	# The native picker is outside the Godot viewport. Exercise its callback and file IO.
	_lab._interchange._selected(true, [path], 0, "export", _lab.project)
	expect(_lab._message == "Композиция экспортирована." and FileAccess.file_exists(path), "export callback writes and verifies the actual document")
	await _capture("11-export-complete")
	_press(_button("Удалить композицию…"))
	await _settle()
	_press(_button("Удалить композицию"))
	await _settle()
	expect(_lab.store.load_project(id).is_empty(), "confirmed library deletion removes saved copy")
	_lab._interchange._selected(true, [path], 0, "import", {})
	await _settle()
	expect(_lab.project.id != id and _lab.project.events == expected.events and _lab.project.bpm == 100,
		"import callback opens a distinct project with equivalent content")
	await _capture("12-import-complete")


func _titles() -> Array:
	return _lab.project.events.map(func(event: Dictionary) -> String: return Chord.title(event.chord))


func _picker() -> Picker:
	for child in _lab._frame.get_children():
		if child is Picker:
			return child
	expect(false, "picker is present")
	return null


func _button(text: String) -> Button:
	for button: Button in _lab._frame.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	expect(false, "button exists: " + text)
	return null


func _press(button: Button) -> void:
	if button != null:
		_click(button.get_global_rect().get_center())


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func _touch(point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = root.get_final_transform() * point
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _drag(point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = root.get_final_transform() * point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _hold() -> void:
	var until := Time.get_ticks_usec() + Sequence.HOLD_USEC + 30000
	while Time.get_ticks_usec() < until:
		await process_frame


func _capture(label: String) -> void:
	expect(_lab.get_global_rect().encloses(_lab._frame.get_global_rect()), "screen fits viewport: " + label)
	await _capture_image(label)


func _capture_image(label: String) -> void:
	if _headless:
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUTPUT.path_join("%dx%d-%s.png" % [image.get_width(), image.get_height(), label])
	expect(image.save_png(path) == OK, "screenshot captured: " + label)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
