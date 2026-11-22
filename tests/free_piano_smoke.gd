extends RefCounted

const Finish := preload("res://scripts/finish.gd")
const Settings := preload("res://scripts/settings.gd")
const FreePiano := preload("res://scripts/free_piano.gd")
const FreeKeyboard := preload("res://scripts/free_keyboard.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const MixedAudio := preload("res://tests/mixed_audio.gd")
const MARKER_COLOR := Color("#076B73")

var _suite: SceneTree
var _free: FreePiano
var _keys: FreeKeyboard
var _audio: PianoAudio
var _root: Window


func run(suite: SceneTree, settings_path: String, capture_all: bool) -> void:
	_suite = suite
	_free = suite.app.get_node("FreePiano")
	_keys = _free._keyboard
	_audio = suite.audio
	_root = suite.root
	var portrait := _root.size
	var menu: Control = suite.menu
	var free_row: Button = menu._mode_buttons[Settings.Mode.FREE_PIANO]
	expect(free_row.accessibility_name == "Свободная клавиатура", "Free Piano uses its full name")
	await suite.open_mode(Settings.Mode.FREE_PIANO)
	expect(not menu._start.visible and not menu._scroll.visible, "Free Piano has no setup page")
	await suite.process_frame
	expect(_free.visible and not menu.visible and _root.size.x > _root.size.y
		and suite.app.size.x > suite.app.size.y, "the module card opens Free Piano in landscape")
	expect(_keys.locked and _free._lock.button_pressed and not _free._plus.visible and not _free._minus.visible,
		"Free Piano defaults to a locked viewport")
	expect(is_equal_approx(_free._center(), _keys.white_keys.find(60) + 0.5), "Free Piano defaults to middle C")
	expect(_free._sound.button_pressed == _audio.enabled, "Free Piano uses the global Sound preference")
	_check_header_layout()
	if capture_all:
		var locked_frame: Image = await suite.capture("free-locked")
		await _check_c4_markers(locked_frame)
	_check_geometry()
	_check_touches()
	await _check_glissando()
	await _check_glissando_pointers()
	_check_navigation()
	var center := _free._center()
	var zoom := _free.preferences.free_zoom
	_click(_free._menu)
	await suite.process_frame
	expect(menu.visible and not _free.visible and _root.size == portrait
		and suite.app.size.y > suite.app.size.x, "Free Piano returns to the portrait menu")
	if capture_all:
		await suite.capture("free-menu-return")
	var loaded := Settings.new(settings_path)
	loaded.load_settings()
	expect(loaded.mode == Settings.Mode.FREE_PIANO and not loaded.free_locked
		and is_equal_approx(loaded.free_zoom, zoom) and is_equal_approx(loaded.free_center, center),
		"a settings reload restores Free Piano mode, lock, zoom and center")
	await suite.open_mode(Settings.Mode.FREE_PIANO)
	await suite.process_frame
	expect(not _keys.locked and is_equal_approx(_free._center(), center)
		and is_equal_approx(_keys.key_width, _free._default_width * zoom), "reopening restores the same viewport")
	await _check_resizing(capture_all, center, zoom)
	await _check_audio()
	expect(suite.triad_events.is_empty(), "Free Piano never triggers a chord demonstration")
	var c := _keys.white_keys.find(60)
	_suite._touch(_white_point(c), 0, true)
	_drag(_white_point(c + 3), 0)
	_click(_free._menu)
	var stopped_count: int = _suite.note_events.size()
	await _wait_for_attacks()
	expect(_keys._pressed_notes().is_empty() and _audio._free_held.is_empty()
		and _suite.note_events.size() == stopped_count, "returning to the menu clears gestures and pending attacks")
	print("Free Piano: verified 88 notes, ordered touch glissando, bounded playback, viewport navigation and settings.")


func _check_header_layout() -> void:
	var bounds := Finish.safe_bounds(_free)
	var keyboard := _free._clip.get_rect()
	var map := _free._overview.get_rect()
	var menu_rect := _free._menu.get_rect()
	var lock_rect := _free._lock.get_rect()
	var minus_rect := _free._minus.get_rect()
	var plus_rect := _free._plus.get_rect()
	var sound_rect := _free._sound.get_rect()
	expect(_free._menu.visible and _free._lock.visible and _free._sound.visible,
		"Menu, Lock and Sound stay visible in both lock states")
	expect(_free._minus.visible == not _keys.locked and _free._plus.visible == not _keys.locked,
		"both zoom controls are visible only when unlocked")
	expect(lock_rect.position.is_equal_approx(Vector2(menu_rect.end.x, menu_rect.position.y))
		and minus_rect.position.is_equal_approx(Vector2(lock_rect.end.x, lock_rect.position.y))
		and plus_rect.position.is_equal_approx(Vector2(minus_rect.end.x, minus_rect.position.y))
		and minus_rect.size.is_equal_approx(menu_rect.size) and plus_rect.size.is_equal_approx(menu_rect.size)
		and plus_rect.end.x <= sound_rect.position.x + 0.01, "the four left controls fit side by side before Sound")
	for rect in [menu_rect, lock_rect, minus_rect, plus_rect, sound_rect]:
		expect(bounds.grow(0.1).encloses(rect) and rect.end.y <= keyboard.position.y,
			"header controls stay within safe bounds and above the keyboard")
	expect(map.position.is_equal_approx(Vector2(keyboard.position.x, keyboard.end.y))
		and is_equal_approx(map.size.x, keyboard.size.x), "the mini-map spans the keyboard width in both lock states")


func _check_c4_markers(frame: Image) -> void:
	_check_main_marker(frame)
	_check_minimap_marker(frame)
	var map_pixels: Rect2 = _root.get_final_transform() * _free._overview.get_global_rect()
	var crop := frame.get_region(Rect2i(map_pixels).intersection(Rect2i(Vector2i.ZERO, frame.get_size())))
	var path: String = _suite.OUTPUT_DIR.path_join("%sx%s-free-mini-map.png" % [_root.size.x, _root.size.y])
	expect(crop.save_png(path) == OK, "captured full mini-map with its C4 reference")
	var saved_center := _free._center()
	for index in range(_keys.white_keys.size()):
		var midi := _keys.white_keys[index]
		if midi % 12 != 0 or midi == PianoAudio.C4:
			continue
		_free._set_center(index + 0.5)
		await RenderingServer.frame_post_draw
		var octave_frame := _root.get_texture().get_image()
		expect(not _has_key_marker(octave_frame, index), "main keyboard omits a marker on MIDI %s" % midi)
	_free._set_center(saved_center)
	var marked: Array[int] = []
	for index in range(_keys.white_keys.size()):
		var rect := _keys.white_rect(index)
		if rect.position.x >= 0.0 and rect.end.x <= _keys.size.x and _has_key_marker(frame, index):
			marked.append(_keys.white_keys[index])
	expect(marked == [60], "the rendered main keyboard marks only Middle C (MIDI 60)")


func _has_key_marker(frame: Image, index: int) -> bool:
	var rect := _keys.white_rect(index)
	var center := _keys.global_position + Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.91)
	var pixel: Color = _suite._pixel(frame, center)
	return pixel.to_rgba32() == MARKER_COLOR.to_rgba32()


func _check_main_marker(frame: Image) -> void:
	var index := _keys.white_keys.find(60)
	var rect := _keys.white_rect(index)
	var center := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.91)
	expect(_keys.key_at(center) == 60 and _has_key_marker(frame, index),
		"the main marker center hits MIDI 60 at 91 percent of the rendered key height")
	var transform := _root.get_final_transform()
	var key_pixels: Rect2 = transform * Rect2(_keys.global_position + rect.position, rect.size)
	var center_pixels: Vector2 = transform * (_keys.global_position + center)
	var diameter := key_pixels.size.x * 0.19
	var origin := Vector2i(center_pixels)
	var extent := ceili(diameter * 0.5) + 2
	var bounds := Rect2i()
	for y in range(origin.y - extent, origin.y + extent + 1):
		for x in range(origin.x - extent, origin.x + extent + 1):
			if frame.get_pixel(x, y).to_rgba32() == MARKER_COLOR.to_rgba32():
				var pixel := Vector2i(x, y)
				bounds = bounds.expand(pixel).expand(pixel + Vector2i.ONE) if bounds.has_area() else Rect2i(pixel, Vector2i.ONE)
	expect(bounds.has_area() and Vector2(bounds.get_center()).distance_to(center_pixels) <= 1.5
		and absf(bounds.size.x - diameter) <= 2.0 and absf(bounds.size.y - diameter) <= 2.0
		and absi(bounds.size.x - bounds.size.y) <= 1,
		"the rasterized circle is centered and 19 percent of the actual white key width on both axes")
	print("C4 at %sx%s: rendered white key %.2f px, circle diameter %.2f px (solid pixels %sx%s)."
		% [_root.size.x, _root.size.y, key_pixels.size.x, diameter, bounds.size.x, bounds.size.y])


func _check_minimap_marker(frame: Image) -> void:
	var face := _free._map_face()
	var unit := face.size.x / FreeKeyboard.WHITE_COUNT
	var marked: Array[int] = []
	for index in range(FreeKeyboard.WHITE_COUNT):
		var center := Vector2((index + 0.5) * unit, face.position.y + face.size.y * 0.82)
		var pixel: Color = _suite._pixel(frame, _free._overview.global_position + center)
		if pixel.to_rgba32() == MARKER_COLOR.to_rgba32():
			marked.append(_keys.white_keys[index])
	expect(marked == [60], "the rendered mini-map highlights only MIDI 60")
	var middle_c_x := (_keys.white_keys.find(60) + 0.5) * unit
	for point in [Vector2(0.0, 0.2), Vector2(-0.32, 0.88), Vector2(0.32, 0.88)]:
		var sample := Vector2(middle_c_x + point.x * unit, face.position.y + point.y * face.size.y)
		var pixel: Color = _suite._pixel(frame, _free._overview.global_position + sample)
		expect(pixel.to_rgba32() == MARKER_COLOR.to_rgba32(), "teal fills the visible miniature C4 key face")


func _check_geometry() -> void:
	var midi_keys: Array[int] = _keys.white_keys.duplicate()
	midi_keys.append_array(_keys.black_keys.values())
	midi_keys.sort()
	expect(_keys.white_keys.size() == 52 and _keys.black_keys.size() == 36 and midi_keys == range(21, 109),
		"52 white and 36 black keys cover MIDI 21–108 exactly once")
	expect(_keys.white_keys.slice(0, 3) == [21, 23, 24] and _keys.black_keys[1] == 22
		and _keys.white_keys[-2] == 107 and _keys.white_keys[-1] == 108, "A0 and C8 boundaries are standard")
	var saved_center := _free._center()
	var white_index := 0
	for midi in range(21, 109):
		var white := midi % 12 in [0, 2, 4, 5, 7, 9, 11]
		if white:
			expect(_keys.white_keys[white_index] == midi, "MIDI %s has the expected white position" % midi)
			_free._set_center(white_index + 0.5)
			expect(_keys.key_at(_keys.white_rect(white_index).get_center()) == midi,
				"white MIDI %s remains hittable after scrolling" % midi)
			white_index += 1
		else:
			_free._set_center(white_index)
			expect(_keys.black_keys.get(white_index) == midi
				and _keys.key_at(_keys.black_rect(white_index).get_center()) == midi,
				"black MIDI %s is centered between its neighboring white keys and has hit priority" % midi)
	_free._set_center(saved_center)


func _check_touches() -> void:
	var notes: Array[int] = _suite.note_events
	notes.clear()
	_suite.triad_events.clear()
	var c := _keys.white_keys.find(60)
	var first := _white_point(c)
	var second := _keys.global_position + _keys.black_rect(c + 1).get_center()
	var initial_offset := _keys.offset
	var initial_width := _keys.key_width
	_free._scroll(200.0)
	_free._zoom(FreePiano.ZOOM_STEP)
	_suite.tap(_free._overview.global_position + Vector2(3.0, _free._overview.size.y * 0.5))
	_suite._touch(first, 0, true)
	expect(notes == [60], "locked touch sounds on press immediately and only once")
	_suite._touch(second, 1, true)
	_suite._touch(first, 2, true)
	expect(notes == [60, 61, 60] and _keys._pressed_notes().size() == 3, "multi-touch and held-key retriggering work independently")
	_suite._touch(first, 0, false)
	expect(60 in _keys._pressed_notes() and 61 in _keys._pressed_notes(), "releasing one finger preserves both other fingers")
	_suite._touch(first, 2, false)
	expect(_keys._pressed_notes() == [61], "release clears only that pointer")
	_suite._touch(second, 1, false)
	expect(_keys._pressed_notes().is_empty() and notes == [60, 61, 60]
		and _keys.offset == initial_offset and _keys.key_width == initial_width, "lock prevents swipe, map and zoom changes")
	_suite.click(first)
	expect(notes == [60, 61, 60, 60], "desktop mouse produces a single note")
	_suite._touch(first, 0, true)
	_keyboard_cancel(first, 0)
	expect(_keys._pressed_notes().is_empty() and _audio._free_held.is_empty(), "an Android cancel clears the held key and voice")


func _check_glissando() -> void:
	var notes: Array[int] = _suite.note_events
	var c := _keys.white_keys.find(60)
	var center := _free._center()
	_free._set_center(c + 4.0)
	var first := _white_point(c)
	var last := _white_point(c + 7)
	var offset := _keys.offset
	notes.clear()
	_suite._touch(first, 0, true)
	for distance in [1.0, 3.0, 2.0, 0.0]:
		_drag(first + Vector2(distance, 0.0), 0)
	await _wait_for_attacks()
	expect(notes == [60] and _keys._pressed_notes() == [60], "holding and moving slightly inside C4 attacks once")

	for index in range(c + 1, c + 3):
		var point := _white_point(index)
		_drag(point, 0)
		_drag(point + Vector2(2.0, 0.0), 0)
		await _wait_for_attacks()
	expect(notes == [60, 62, 64], "closely sampled lower glissando attacks once per key boundary")
	_drag(last, 0)
	expect(_keys._pressed_notes() == [72], "sparse drag highlights the destination key immediately")
	await _wait_for_attacks()
	expect(notes == [60, 62, 64, 65, 67, 69, 71, 72], "a sparse lower sweep completes C4 to C5 without black keys")
	_drag(first, 0)
	await _wait_for_attacks()
	expect(notes.slice(8) == [71, 69, 67, 65, 64, 62, 60], "reversing the same touch plays the white keys in reverse")
	_suite._touch(first, 0, false)
	expect(_keys.offset == offset and _audio._free_held.is_empty() and _keys._pressed_notes().is_empty(),
		"a locked lower glissando leaves the viewport fixed and releases cleanly")

	await _check_slide(_white_point(c + 4), first, [67, 65, 64, 62, 60])
	await _check_slide(_white_point(c, 0.3), _white_point(c + 4, 0.3), [60, 61, 62, 63, 64, 65, 66, 67])
	await _check_slide(_white_point(c, 0.3), _white_point(c + 4), [60, 61, 62, 63, 64, 65, 67])
	var black := _keys.black_rect(c + 1)
	var black_point := _keys.global_position + black.get_center() - Vector2(black.size.x * 0.2, 0.0)
	await _check_slide(black_point, Vector2(black_point.x, first.y), [61, 60])
	var outside := Vector2(first.x, _keys.global_position.y + _keys.size.y + 15.0)
	notes.clear()
	_suite._touch(first, 0, true)
	_drag(outside, 0)
	await _wait_for_attacks()
	expect(notes == [60] and _keys._pressed_notes().is_empty() and _audio._free_held.is_empty(),
		"dragging outside the keyboard releases the current key")
	_drag(first, 0)
	await _wait_for_attacks()
	expect(notes == [60, 60] and _keys._pressed_notes() == [60], "re-entering the keyboard attacks the crossed key again")
	_suite._touch(first, 0, false)
	await _check_sparse_timing(c)
	_free._set_center(center)


func _check_slide(start: Vector2, end: Vector2, expected: Array[int]) -> void:
	var notes: Array[int] = _suite.note_events
	notes.clear()
	_suite._touch(start, 0, true)
	_drag(end, 0)
	await _wait_for_attacks()
	expect(notes == expected, "sparse segment plays %s in spatial order, got %s" % [expected, notes])
	_suite._touch(end, 0, false)
	expect(_keys._pressed_notes().is_empty() and _audio._free_held.is_empty(), "sparse segment releases the pointer")


func _check_sparse_timing(c: int) -> void:
	var attacks: Array[int] = []
	var record := func(_midi: int) -> void: attacks.append(Time.get_ticks_usec())
	var notes: Array[int] = _suite.note_events
	notes.clear()
	var first := _white_point(c)
	var last := _white_point(c + 7)
	_suite._touch(first, 0, true)
	await _suite.create_timer(0.025).timeout
	_audio.note_started.connect(record)
	var moved := Time.get_ticks_usec()
	_drag(last, 0)
	expect(notes.size() < 8, "a single sparse octave event does not start every voice in one input callback")
	await _wait_for_attacks()
	_audio.note_started.disconnect(record)
	expect(notes == [60, 62, 64, 65, 67, 69, 71, 72] and attacks.size() == 7,
		"a single sparse octave event plays exactly the seven crossed regions")
	if not attacks.is_empty():
		expect(attacks[-1] - attacks[0] >= FreeKeyboard.ATTACK_SPACING_USEC
			and attacks[-1] - moved <= FreeKeyboard.ATTACK_WINDOW_USEC + 50000,
			"sparse attacks are spread across updates and finish within the window plus frame overhead")
	_suite._touch(last, 0, false)
	await _wait_for_attacks()
	expect(notes.size() == 8 and _audio._free_held.is_empty(), "no attacks or held voices remain after completing a rapid sweep")


func _check_glissando_pointers() -> void:
	var c := _keys.white_keys.find(60)
	var first := _white_point(c)
	var last := _white_point(c + 4)
	var notes: Array[int] = _suite.note_events
	notes.clear()
	_suite._touch(first, 0, true)
	_suite._touch(first, 1, true)
	_suite._touch(last, 2, true)
	var held_voice: AudioStreamPlayer = _audio._free_held.get(0)
	expect(notes == [60, 60, 67] and held_voice != null and _audio._free_held.get(1) != held_voice,
		"two fingers on the same key get separate attacks and voices")
	_drag(_white_point(c + 1), 1)
	_drag(_white_point(c + 3), 2)
	await _wait_for_attacks()
	expect(notes == [60, 60, 67, 62, 65] and _audio._free_held.get(0) == held_voice
		and _keys._pressed_notes() == [60, 62, 65], "two independent drags preserve the third finger and all highlights")
	_drag(last, 1)
	_keyboard_cancel(last, 1)
	var canceled_count := notes.size()
	await _wait_for_attacks()
	expect(notes.size() == canceled_count and _keys._pressed_notes() == [60, 65]
		and not _audio._free_held.has(1) and _audio._free_held.get(0) == held_voice and _audio._free_held.has(2),
		"canceling a glissando discards its pending attacks and preserves other fingers")
	_suite._touch(first, 0, false)
	_suite._touch(_white_point(c + 3), 2, false)
	expect(_audio._free_held.is_empty() and _keys._pressed_notes().is_empty(), "lifting all fingers clears their voices")

	_suite._touch(first, 0, true)
	_drag(last, 0)
	_suite._touch(last, 0, false)
	var lifted_count := notes.size()
	await _wait_for_attacks()
	expect(notes.size() == lifted_count and _audio._free_held.is_empty(), "lifting during a sparse batch stops deferred attacks")
	_suite._touch(first, 0, true)
	_drag(last, 0)
	_root.focus_exited.emit()
	await _wait_for_attacks()
	expect(_audio._free_held.is_empty() and _keys._pressed_notes().is_empty(), "focus loss clears the glissando")
	_suite._touch(last, 0, false)
	_suite._touch(first, 0, true)
	_drag(last, 0)
	_free.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var paused_count := notes.size()
	await _wait_for_attacks()
	expect(notes.size() == paused_count and _keys._pressed_notes().is_empty() and _audio._free_held.is_empty(),
		"application pause clears the glissando and suppresses pending attacks")
	_suite._touch(last, 0, false)
	_free.notification(Node.NOTIFICATION_APPLICATION_RESUMED)


func _wait_for_attacks() -> void:
	var deadline := Time.get_ticks_usec() + 85000
	var remaining := deadline - Time.get_ticks_usec()
	while remaining > 0:
		await _suite.create_timer(float(remaining) / 1000000.0).timeout
		remaining = deadline - Time.get_ticks_usec()


func _check_navigation() -> void:
	var notes: Array[int] = _suite.note_events
	var before := _free._center()
	_click(_free._lock)
	expect(not _keys.locked and _free._plus.visible and _free._minus.visible
		and is_equal_approx(_free._center(), before), "unlock reveals zoom and keeps the keyboard in place")
	_check_header_layout()
	var first := _white_point(_keys.white_keys.find(60))
	notes.clear()
	_suite._touch(first, 0, true)
	expect(notes.is_empty(), "unlocked gesture waits until it knows the touch is a tap")
	_drag(first - Vector2(105.0, 0.0), 0)
	_suite._touch(first - Vector2(135.0, 0.0), 0, false)
	expect(_free._center() > before and notes.is_empty() and _keys._pressed_notes().is_empty(),
		"an unlocked swipe scrolls without playing a note or leaving key feedback")
	_free._set_center(before)
	_suite._touch(first, 0, true)
	_drag(first + Vector2(3.0, 0.0), 0)
	_suite._touch(first + Vector2(3.0, 0.0), 0, false)
	expect(notes == [60], "an unlocked tap with slight movement still plays exactly once")
	var width := _keys.key_width
	_click(_free._plus)
	expect(is_equal_approx(_keys.key_width, width * FreePiano.ZOOM_STEP) and is_equal_approx(_free._center(), before),
		"zoom increases by 12 percent around the current center")
	_click(_free._minus)
	expect(is_equal_approx(_keys.key_width, width), "minus reverses one zoom step")
	var map := _free._overview
	var map_y := map.size.y * 0.5
	var scale := map.size.x / FreeKeyboard.WHITE_COUNT
	_suite.tap(map.global_position + Vector2(36.0 * scale, map_y))
	expect(is_equal_approx(_free._center(), 36.0), "tapping the map centers that part of the keyboard")
	var grab := map.global_position + Vector2(37.0 * scale, map_y)
	_suite._touch(grab, 0, true)
	expect(is_equal_approx(_free._center(), 36.0), "grabbing the map rectangle does not jump")
	_drag(grab - Vector2(7.0 * scale, 0.0), 0)
	_suite._touch(grab - Vector2(7.0 * scale, 0.0), 0, false)
	expect(is_equal_approx(_free._center(), 29.0), "dragging the map rectangle moves the main viewport")
	expect(is_equal_approx(_free._map_viewport().get_center().x, 29.0 * scale)
		and is_equal_approx(_free._map_viewport().size.x, _free._visible_keys() * scale),
		"map indicator reflects the scroll and zoom")
	_suite.tap(map.global_position + Vector2(30.0 * scale, map_y))
	expect(is_equal_approx(_free._center(), 30.0), "a tap inside the indicator also centers on the tapped location")
	_free._scroll(-100000.0)
	expect(is_zero_approx(_keys.offset) and is_zero_approx(_free._map_viewport().position.x)
		and _keys.key_at(Vector2(1.0, _keys.size.y * 0.9)) == 21, "left boundary clamps to A0")
	_free._scroll(100000.0)
	expect(is_equal_approx(_keys.offset + _keys.size.x, _keys.key_width * 52)
		and is_equal_approx(_free._map_viewport().end.x, map.size.x)
		and _keys.key_at(Vector2(_keys.size.x - 1.0, _keys.size.y * 0.9)) == 108, "right boundary clamps to C8")
	_suite.tap(map.global_position + Vector2(25.0 * scale, map_y))
	_click(_free._plus)


func _check_resizing(capture_all: bool, center: float, zoom: float) -> void:
	var original := _root.size
	var original_visible := _free._visible_keys()
	# The same saved zoom may clamp to different effective widths when the window changes.
	for resolution in [Vector2i(1280, 800), Vector2i(1600, 1000)]:
		_root.size = resolution
		await _suite.process_frame
		expect(_root.size == resolution, "test window uses the requested landscape dimensions")
		expect(is_equal_approx(_free._center(), center) and _keys.key_width >= _free._min_width
			and _keys.key_width <= _free._max_width and _keys.offset >= 0.0
			and is_equal_approx(_free.preferences.free_zoom, zoom), "resize adapts the keyboard and preserves the saved zoom")
		expect(not is_equal_approx(original_visible, _free._visible_keys()),
			"tablet and phone show a different number of white keys")
		_check_header_layout()
		if capture_all:
			var resized_frame: Image = await _suite.capture("free-unlocked")
			_check_main_marker(resized_frame)
			_check_minimap_marker(resized_frame)
			await _check_rendered_glissando(resized_frame)
	_root.size = original
	await _suite.process_frame
	if capture_all:
		await _suite.capture("free-unlocked")
	for step in range(20):
		_free._zoom(1.0 / FreePiano.ZOOM_STEP)
	expect(_free._minus.disabled and is_equal_approx(_keys.key_width, _free._min_width), "zoom stops at the minimum")
	_free._scroll(-100000.0)
	_click(_free._lock)
	await _check_slide(_white_point(0), _white_point(3), [21, 23, 24, 26])
	_click(_free._lock)
	if capture_all:
		var left_frame: Image = await _suite.capture("free-min-left")
		_check_minimap_marker(left_frame)
		var center_c := _keys.white_keys.find(60) + 0.5
		_free._set_center(center_c)
		var min_frame: Image = await _suite.capture("free-min-middle-c")
		_check_main_marker(min_frame)
		_check_minimap_marker(min_frame)
	for step in range(20):
		_free._zoom(FreePiano.ZOOM_STEP)
	expect(_free._plus.disabled and is_equal_approx(_keys.key_width, _free._max_width), "zoom stops at the maximum")
	_free._scroll(100000.0)
	_click(_free._lock)
	await _check_slide(_white_point(48, 0.3), _white_point(51, 0.3), [103, 104, 105, 106, 107, 108])
	_click(_free._lock)
	if capture_all:
		var right_frame: Image = await _suite.capture("free-max-right")
		_check_minimap_marker(right_frame)
		_free._scroll((_keys.white_keys.find(60) + 1.75 - _free._center()) * _keys.key_width)
		var max_frame: Image = await _suite.capture("free-max-scrolled-c4")
		_check_main_marker(max_frame)
		_check_minimap_marker(max_frame)
	_click(_free._minus)
	expect(_keys.key_width < _free._max_width, "one click recovers from maximum zoom")
	var c := _keys.white_keys.find(PianoAudio.C4)
	_free._scroll((c + 0.5 - _free._center()) * _keys.key_width)
	_click(_free._lock)
	if capture_all:
		var c4_frame: Image = await _suite.capture("free-middle-c")
		_check_main_marker(c4_frame)
		_check_minimap_marker(c4_frame)
		var first := _white_point(c)
		var second := _keys.global_position + _keys.black_rect(c + 1).get_center()
		_suite._touch(first, 0, true)
		_suite._touch(second, 1, true)
		expect(_keys._pressed_notes() == [60, 61], "visual capture contains a held white and black key")
		var pressed_frame: Image = await _suite.capture("free-pressed")
		_check_main_marker(pressed_frame)
		var rest_pixel: Color = _suite._pixel(c4_frame, first)
		var pressed_pixel: Color = _suite._pixel(pressed_frame, first)
		expect(pressed_pixel.r < rest_pixel.r, "the C4 key face still darkens while pressed")
		_suite._touch(first, 0, false)
		_suite._touch(second, 1, false)
		_click(_free._lock)
		await _check_rendered_glissando(c4_frame)
		_click(_free._lock)


func _check_rendered_glissando(rest: Image) -> void:
	var offset := _keys.offset
	var width := _keys.key_width
	_click(_free._lock)
	expect(is_equal_approx(_keys.offset, offset) and is_equal_approx(_keys.key_width, width),
		"locking preserves the existing viewport position and zoom")
	var c := _keys.white_keys.find(60)
	var first := _white_point(c)
	var last := _white_point(c + 2)
	var held := _keys.global_position + _keys.black_rect(c + 1).get_center()
	_suite._touch(first, 0, true)
	_suite._touch(held, 1, true)
	_drag(last, 0)
	await _wait_for_attacks()
	var frame: Image = await _suite.capture("free-glissando")
	var rest_first: Color = _suite._pixel(rest, first)
	var rest_last: Color = _suite._pixel(rest, last)
	var rest_held: Color = _suite._pixel(rest, held)
	var gliss_first: Color = _suite._pixel(frame, first)
	var gliss_last: Color = _suite._pixel(frame, last)
	var gliss_held: Color = _suite._pixel(frame, held)
	expect(gliss_first == rest_first and gliss_last.r < rest_last.r and gliss_held.r > rest_held.r,
		"rendered glissando restores the old key, darkens the new white key and keeps the held black key pressed")
	_check_main_marker(frame)
	_check_minimap_marker(frame)
	_suite._touch(last, 0, false)
	_suite._touch(held, 1, false)
	_click(_free._lock)


func _check_audio() -> void:
	var notes: Array[int] = _suite.note_events
	notes.clear()
	var frequencies: Dictionary[int, float] = {}
	for midi in range(21, 109):
		_audio.play_free_note(midi, 0)
		var voice: AudioStreamPlayer = _audio._free_held.get(0)
		var sample: AudioStreamWAV = voice.stream if voice != null else null
		var anchor := PianoAudio.free_sample_midi(midi)
		var measured_hz := 440.0 * pow(2.0, (anchor - 69) / 12.0 - PianoAudio.free_tuning_cents(anchor) / 1200.0)
		var hz := 0.0
		if sample != null:
			hz = measured_hz * voice.pitch_scale
		frequencies[midi] = hz
		expect(sample != null and sample.stereo and sample.mix_rate == 44100 and sample.get_length() > 1.0
			and sample.resource_path.get_file() == "%s.wav" % anchor and absi(midi - anchor) <= 1
			and is_equal_approx(hz, 440.0 * pow(2.0, (midi - 69) / 12.0)), "MIDI %s plays a correctly pitched recording" % midi)
		if frequencies.has(midi - 12):
			expect(is_equal_approx(hz, 2.0 * frequencies[midi - 12]),
				"MIDI %s is an octave above MIDI %s" % [midi, midi - 12])
		_audio.release_free_note(0)
	expect(notes == range(21, 109), "all 88 notes start playback, including both endpoints")
	_audio.fade_free_notes()
	await _suite.create_timer(0.10).timeout

	var graphical := DisplayServer.get_name() != "headless"
	var capture := AudioEffectCapture.new()
	var capture_index := AudioServer.get_bus_effect_count(0)
	if graphical:
		capture.buffer_length = 2.0
		AudioServer.add_bus_effect(0, capture)
	notes.clear()
	for index in range(10):
		_audio.play_free_note([21, 24, 33, 48, 55, 60, 64, 69, 81, 108][index], index)
	var held := _audio._free_held.duplicate()
	for batch in range(8):
		for index in range(3):
			_audio.play_free_note([60, 60, 61][index], 10 + index)
			_audio.release_free_note(10 + index)
		await _suite.create_timer(0.026).timeout
	expect(notes.size() == 34 and _audio._free_held == held and _audio._free_keys.size() == 64,
		"ten simultaneous voices survive rapid repeated notes in the 64-voice pool")
	if graphical:
		var frames := capture.get_buffer(capture.get_frames_available())
		var peak := MixedAudio._peak(frames)
		expect(capture.get_discarded_frames() == 0 and peak > 0.04 and peak <= db_to_linear(-0.95),
			"real mixed Free Piano audio stays below clipping (%.2f dBFS)" % linear_to_db(peak))
		print("Free Piano mixed output (%s): ten held voices, 24 repeats, peak %.2f dBFS."
			% [AudioServer.get_driver_name(), linear_to_db(peak)])
	_click(_free._sound)
	_audio.play_free_note(60, 100)
	expect(not _audio.enabled and not _free._sound.button_pressed and notes.size() == 34 and _audio._free_held.is_empty(),
		"global mute releases active Free Piano voices and blocks new playback")
	var c := _keys.white_keys.find(60)
	var end := _white_point(c + 3)
	_suite._touch(_white_point(c), 0, true)
	_drag(end, 0)
	await _suite.create_timer(0.11).timeout
	expect(notes.size() == 34 and _keys._pressed_notes() == [65] and _audio._free_held.is_empty(),
		"muted glissando keeps the key feedback and starts no audio")
	_suite._touch(end, 0, false)
	expect(_audio._free_keys.all(func(voice: AudioStreamPlayer) -> bool: return not voice.playing),
		"all Free Piano voices stop after mute")
	if graphical:
		capture.clear_buffer()
		await _suite.create_timer(0.08).timeout
		var quiet := capture.get_buffer(capture.get_frames_available())
		expect(not quiet.is_empty() and MixedAudio._peak(quiet) == 0.0, "muted Free Piano mix is digitally silent")
		AudioServer.remove_bus_effect(0, capture_index)
	_click(_free._sound)


func _white_point(index: int, height_fraction := 0.85) -> Vector2:
	var visible_face := _keys.white_rect(index).intersection(Rect2(Vector2.ZERO, _keys.size))
	return _keys.global_position + Vector2(visible_face.get_center().x, _keys.size.y * height_fraction)


func _drag(at: Vector2, index: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = _root.get_final_transform() * at
	event.index = index
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _keyboard_cancel(at: Vector2, index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.position = _root.get_final_transform() * at
	event.index = index
	event.canceled = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(button: Control) -> void:
	_suite.click(button.get_global_rect().get_center())


func expect(condition: bool, message: String) -> void:
	_suite.expect(condition, message)
