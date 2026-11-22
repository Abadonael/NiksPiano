extends ScrollContainer

signal preview_requested(index: int)
signal edit_requested(index: int)
signal reorder_requested(from: int, to: int)
signal gesture_changed(reordering: bool)

const UI := preload("res://scripts/harmony_style.gd")
const Finish := preload("res://scripts/finish.gd")
const Chord := preload("res://scripts/harmony_chords.gd")
const Model := preload("res://scripts/harmony_composition.gd")
const BEATS := Model.BEATS_PER_MEASURE
const HOLD_USEC := 450000
const EDGE := 100.0
const MAX_SCROLL_SPEED := 720.0
const NO_POINTER := -2
const MOUSE_POINTER := -1
enum Phase { PENDING, SCROLLING, REORDERING }

class Part:
	var index: int
	var panel: PanelContainer
	var edit: Button
	var continuation: bool

var by_measure := true
var _locked := false
var _events: Array
var _rows: Array[PanelContainer] = []
var _groups: Array[Array] = []
var _parts: Array[Part] = []
var _bars: Array[Control] = []
var _tracks: Array[Control] = []
var _beat_tiles: Array[Array] = []
var _list: VBoxContainer
var _overlay: Control
var _pointer := NO_POINTER
var _phase := Phase.PENDING
var _from := -1
var _slot := -1
var _held_at := 0
var _origin := Vector2.ZERO
var _point := Vector2.ZERO
var _scroll_position := 0.0
var _active := -1
var _beat := -1
var _normal := UI.card_style(false)
var _continued := UI.card_style(false)
var _playing := UI.card_style(true)
var _grabbed := UI.card_style(false)
var _beat_default := Finish.flat(Color("#23292f"), Color.TRANSPARENT, 5)
var _beat_playing := Finish.flat(UI.TEAL, Color("#83d4d7"), 5, 1)


func _ready() -> void:
	_grabbed.bg_color = Color("#224449")
	_grabbed.border_color = Color("#83d4d7")
	_continued.bg_color = Color("#172327")
	_continued.border_color = Color("#395259")
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	vertical_scroll_mode = SCROLL_MODE_RESERVE
	size_flags_vertical = SIZE_EXPAND_FILL
	_list = UI.column(self, 7)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_overlay = Control.new()
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.set_as_top_level(true)
	_overlay.draw.connect(_draw_drag)
	add_child(_overlay)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			cancel_gesture())
	set_process(false)


static func measure_slices(events: Array) -> Array[Array]:
	var result: Array[Array] = []
	for index in range(events.size()):
		var event: Dictionary = events[index]
		var beat := int(event.start_beat)
		var end := beat + int(event.duration_beats)
		while beat < end:
			var bar := Model.measure(beat) - 1
			if bar == result.size():
				result.append([])
			var offset := beat % BEATS
			var length := mini(end - beat, BEATS - offset)
			result[bar].append({"index": index, "offset": offset, "length": length, "attack": beat == event.start_beat})
			beat += length
	return result


func render(events: Array) -> void:
	cancel_gesture()
	var old_scroll := scroll_vertical
	_active = -1
	_beat = -1
	_events = events
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_groups.clear()
	_parts.clear()
	_bars.clear()
	_tracks.clear()
	_beat_tiles.clear()
	for event in events:
		_groups.append([])
	if events.is_empty():
		var hint := UI.label(_list, "Добавьте первый аккорд, чтобы начать.", 31, true)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.y = 152
	elif by_measure:
		for slices in measure_slices(events):
			_add_measure(slices)
	else:
		for index in range(events.size()):
			_add_row(index)
	set_deferred("scroll_vertical", old_scroll)


func _add_measure(slices: Array) -> void:
	var bar := UI.column(_list, 4)
	_bars.append(bar)
	var heading := UI.row(bar, 12)
	UI.label(heading, "Такт %d" % _bars.size(), 24)
	var line := HSeparator.new()
	line.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(line)
	var numbers := UI.row(bar, 0)
	var tiles := []
	var last: Dictionary = slices.back()
	var used := int(last.offset) + int(last.length)
	for column in range(BEATS):
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = SIZE_EXPAND_FILL
		tile.add_theme_stylebox_override("panel", _beat_default)
		numbers.add_child(tile)
		var number := UI.label(tile, str(column + 1), 22, column >= used)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if column >= used:
			number.modulate.a = 0.36
		tiles.append(tile)
	_beat_tiles.append(tiles)
	var track := Control.new()
	track.custom_minimum_size.y = 86
	track.draw.connect(_draw_track.bind(track, used))
	track.resized.connect(track.queue_redraw)
	bar.add_child(track)
	_tracks.append(track)
	for slice: Dictionary in slices:
		var part := _make_part(track, slice.index, not slice.attack)
		part.panel.anchor_right = float(slice.offset + slice.length) / BEATS
		part.panel.anchor_left = float(slice.offset) / BEATS
		part.panel.anchor_bottom = 1.0
		part.panel.offset_left = 2.0
		part.panel.offset_right = -2.0
		var content := UI.row(part.panel, 2)
		content.size_flags_vertical = SIZE_EXPAND_FILL
		var title := UI.label(content, _title(slice.index), 25)
		UI.ellipsis(title)
		if part.continuation:
			title.text = "↪ " + title.text
			title.add_theme_color_override("font_color", Color("#b8d8da"))
		_add_pencil(content, part, 64, 66)


func _draw_track(track: Control, used: int) -> void:
	var width := track.size.x / BEATS
	for column in range(BEATS + 1):
		var x := column * width
		if column >= used and column < BEATS:
			var dim := Rect2(x + 2.0, 1.0, width - 4.0, track.size.y - 2.0)
			track.draw_rect(dim, Color("#12191d"))
			var center := dim.get_center()
			track.draw_line(center - Vector2(7, 0), center + Vector2(7, 0), Color("#57616a"), 2.0)
		track.draw_line(Vector2(x, 0), Vector2(x, track.size.y), Color("#46505a"), 1.0)


func _add_row(index: int) -> void:
	var part := _make_part(_list, index, false)
	var content := UI.row(part.panel, 9)
	var title := UI.label(content, _title(index), 31)
	UI.ellipsis(title)
	var event: Dictionary = _events[index]
	var duration := UI.label(content, Model.beat_label(event.duration_beats), 24)
	duration.custom_minimum_size.x = 104
	var location := UI.label(content, Model.position_label(event.start_beat), 23, true)
	location.custom_minimum_size.x = 204
	_add_pencil(content, part, 76, 62)


func _title(index: int) -> String:
	return Chord.event_title(_events[index])


func _make_part(parent: Control, index: int, continuation: bool) -> Part:
	var part := Part.new()
	part.index = index
	part.continuation = continuation
	part.panel = PanelContainer.new()
	part.panel.focus_mode = FOCUS_ALL
	part.panel.accessibility_name = _title(index) + " · " + Model.position_label(_events[index].start_beat)
	part.panel.gui_input.connect(func(event: InputEvent) -> void:
		if not _locked and event is InputEventKey and event.is_action_pressed("ui_accept", false):
			preview_requested.emit(index)
			part.panel.accept_event())
	parent.add_child(part.panel)
	_parts.append(part)
	_groups[index].append(part)
	if not continuation:
		_rows.append(part.panel)
	_style_part(part)
	return part


func _add_pencil(parent: Control, part: Part, width: int, height: int) -> void:
	var edit := UI.button(parent, "✎", edit_requested.emit.bind(part.index), width, height)
	edit.add_theme_font_size_override("font_size", 24 if by_measure else 29)
	edit.size_flags_vertical = SIZE_SHRINK_CENTER
	edit.accessibility_name = "Правка аккорда " + _title(part.index)
	edit.tooltip_text = edit.accessibility_name
	edit.disabled = _locked
	part.edit = edit


func set_locked(locked: bool) -> void:
	if _locked == locked:
		return
	cancel_gesture()
	_locked = locked
	for part in _parts:
		part.edit.disabled = locked


func show_position(index: int, beat: int) -> void:
	var last_index := _active
	var last_beat := _beat
	if last_index == index and last_beat == beat:
		return
	_active = index
	_beat = beat
	if last_index != index:
		_style_event(last_index)
		_style_event(index)
	if by_measure:
		_style_beat(last_beat, _beat_default)
		_style_beat(beat, _beat_playing)
		if beat >= 0 and _pointer == NO_POINTER and (last_beat < 0 or Model.measure(last_beat) != Model.measure(beat)):
			_reveal_active_measure.call_deferred()
	elif index >= 0 and last_index != index and _pointer == NO_POINTER:
		reveal.call_deferred(index)


func _style_beat(beat: int, style: StyleBox) -> void:
	if beat < 0 or _beat_tiles.is_empty():
		return
	var tile: PanelContainer = _beat_tiles[Model.measure(beat) - 1][beat % BEATS]
	tile.add_theme_stylebox_override("panel", style)


func _style_event(index: int) -> void:
	if index >= 0 and index < _groups.size():
		for part: Part in _groups[index]:
			_style_part(part)


func _style_part(part: Part) -> void:
	var style := _continued if part.continuation else _normal
	if part.index == _active:
		style = _playing
	if _pointer != NO_POINTER and _phase == Phase.REORDERING and part.index == _from:
		style = _grabbed
	part.panel.add_theme_stylebox_override("panel", style)


func reveal(index: int) -> void:
	if not is_inside_tree() or index < 0 or index >= _rows.size():
		return
	if by_measure:
		ensure_control_visible(_bars[Model.measure(_events[index].start_beat) - 1])
	else:
		ensure_control_visible(_rows[index])


func _reveal_active_measure() -> void:
	if is_inside_tree() and by_measure and _beat >= 0 and _pointer == NO_POINTER:
		ensure_control_visible(_bars[Model.measure(_beat) - 1])


func cancel_gesture() -> void:
	var was_dragging := _pointer != NO_POINTER and _phase == Phase.REORDERING
	_pointer = NO_POINTER
	_phase = Phase.PENDING
	_slot = -1
	set_process(false)
	if _overlay != null:
		_overlay.queue_redraw()
	if was_dragging:
		_style_event(_from)
		gesture_changed.emit(false)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.is_action_pressed("ui_cancel") and _pointer != NO_POINTER:
		cancel_gesture()
		get_viewport().set_input_as_handled()
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		if _pointer != NO_POINTER or (event is InputEventMouseButton and
				event.button_index == MOUSE_BUTTON_LEFT and _hit_part(event.position) != null):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed, event.is_canceled())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch(MOUSE_POINTER, event.position, event.pressed, event.is_canceled())
	elif event is InputEventScreenDrag:
		_motion(event.index, event.position)
	elif event is InputEventMouseMotion:
		_motion(MOUSE_POINTER, event.position)


func _hit_part(point: Vector2) -> Part:
	if not _viewport_bounds().has_point(point):
		return null
	for part in _parts:
		if part.panel.get_global_rect().has_point(point):
			return null if not _locked and part.edit.get_global_rect().has_point(point) else part
	return null


func _touch(pointer: int, point: Vector2, pressed: bool, canceled: bool) -> void:
	if pressed and not canceled:
		if _pointer != NO_POINTER:
			if get_global_rect().has_point(point):
				get_viewport().set_input_as_handled()
			return
		var hit := _hit_part(point)
		if hit == null:
			return
		_begin_gesture(pointer, hit.index, point, Time.get_ticks_usec())
	elif _pointer == pointer:
		if not canceled:
			_move(point, Time.get_ticks_usec())
		_end_gesture(canceled or not _viewport_bounds().grow(24).has_point(point))
	else:
		return
	get_viewport().set_input_as_handled()


func _motion(pointer: int, point: Vector2) -> void:
	if _pointer == pointer:
		_move(point, Time.get_ticks_usec())
		get_viewport().set_input_as_handled()


func _begin_gesture(pointer: int, index: int, point: Vector2, now: int) -> void:
	_pointer = pointer
	_phase = Phase.PENDING
	_from = index
	_origin = point
	_point = point
	_held_at = now
	_scroll_position = scroll_vertical
	set_process(not _locked)


func _slop() -> float:
	if OS.get_name() != "Android":
		return 16.0
	var physical_per_dp := maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	return 8.0 * physical_per_dp / get_viewport().get_final_transform().get_scale().x


func _move(point: Vector2, now: int) -> void:
	if _phase == Phase.PENDING:
		_activate_drag(now)
		if _phase == Phase.PENDING and (point - _origin).length() >= _slop():
			_phase = Phase.SCROLLING
			set_process(false)
	if _phase == Phase.SCROLLING:
		_scroll_by(_point.y - point.y)
	_point = point
	if _phase == Phase.REORDERING:
		_update_slot()


func _activate_drag(now: int) -> void:
	if not _locked and _phase == Phase.PENDING and now >= _held_at + HOLD_USEC:
		_phase = Phase.REORDERING
		_style_event(_from)
		gesture_changed.emit(true)
		_update_slot()


func _process(delta: float) -> void:
	_activate_drag(Time.get_ticks_usec())
	if _phase != Phase.REORDERING:
		return
	var bounds := _viewport_bounds()
	if bounds.grow(24.0).has_point(_point):
		var top := clampf(1.0 - (_point.y - bounds.position.y) / EDGE, 0.0, 1.0)
		var bottom := clampf(1.0 - (bounds.end.y - _point.y) / EDGE, 0.0, 1.0)
		_scroll_by((bottom - top) * MAX_SCROLL_SPEED * minf(delta, 0.05))
		_update_slot()


func _viewport_bounds() -> Rect2:
	var bounds := get_global_rect()
	bounds.size.x = _list.size.x
	return bounds


func _scroll_by(pixels: float) -> void:
	var bar := get_v_scroll_bar()
	_scroll_position = clampf(_scroll_position + pixels, 0.0, maxf(0.0, bar.max_value - bar.page))
	scroll_vertical = roundi(_scroll_position)


func _update_slot() -> void:
	_slot = -1
	if _viewport_bounds().grow(24).has_point(_point):
		_slot = _measure_slot(_point) if by_measure else _list_slot(_point.y)
	_overlay.queue_redraw()


func _list_slot(y: float) -> int:
	for index in range(_rows.size()):
		if y < _rows[index].get_global_rect().get_center().y:
			return index
	return _rows.size()


func _measure_slot(point: Vector2) -> int:
	var bar := 0
	while bar + 1 < _bars.size() and point.y > _bars[bar].get_global_rect().end.y:
		bar += 1
	var bounds := _tracks[bar].get_global_rect()
	var beat := bar * BEATS + clampf((point.x - bounds.position.x) / bounds.size.x, 0.0, 1.0) * BEATS
	for index in range(_events.size()):
		var event: Dictionary = _events[index]
		if beat < float(event.start_beat) + float(event.duration_beats) * 0.5:
			return index
	return _events.size()


func _end_gesture(canceled: bool) -> void:
	var from := _from
	var to := _slot
	var should_preview := not _locked and not canceled and _phase == Phase.PENDING
	var should_move := not _locked and not canceled and _phase == Phase.REORDERING and to >= 0
	cancel_gesture()
	if should_move:
		if to > from:
			to -= 1
		if to != from:
			reorder_requested.emit(from, to)
	elif should_preview:
		preview_requested.emit(from)


func _draw_drag() -> void:
	if _pointer == NO_POINTER or _phase != Phase.REORDERING or _slot < 0:
		return
	var viewport := _viewport_bounds()
	var last := _slot == _rows.size()
	var start: Vector2
	var end: Vector2
	if by_measure:
		var last_event: Dictionary = _events.back()
		var beat := int(last_event.start_beat) + int(last_event.duration_beats) if last else int(_events[_slot].start_beat)
		var bar := mini(_tracks.size() - 1, Model.measure(beat) - 1)
		var track := _tracks[bar].get_global_rect()
		var x := track.position.x + float(beat - bar * BEATS) / BEATS * track.size.x
		start = Vector2(x, clampf(track.position.y, viewport.position.y + 4, viewport.end.y - 4))
		end = Vector2(x, clampf(track.end.y, viewport.position.y + 4, viewport.end.y - 4))
	else:
		var row := _rows[mini(_slot, _rows.size() - 1)].get_global_rect()
		var y := clampf(row.end.y + 3.0 if last else row.position.y - 3.0, viewport.position.y + 4, viewport.end.y - 4)
		start = Vector2(viewport.position.x + 6, y)
		end = Vector2(viewport.end.x - 6, y)
	var transform_inverse := _overlay.get_global_transform().affine_inverse()
	var ink := Color("#83d4d7")
	_overlay.draw_line(transform_inverse * start, transform_inverse * end, ink, 5.0, true)
	_overlay.draw_circle(transform_inverse * start, 5.0, ink)
