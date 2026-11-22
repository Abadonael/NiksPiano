extends Control

signal menu_requested
signal practice_requested(key: Theory.Tonality, scale_mode: bool)

const Theory := preload("res://scripts/key_theory.gd")
const Comparison := preload("res://scripts/circle_comparison.gd")
const Wheel := preload("res://scripts/circle_wheel.gd")
const Settings := preload("res://scripts/settings.gd")
const Finish := preload("res://scripts/finish.gd")
const HeaderButton := preload("res://scripts/header_button.gd")
const PianoAudio := preload("res://scripts/piano_audio.gd")

enum Detail { TRIADS, COMPARE, HELP }

var preferences: Settings
var audio: PianoAudio
var _key: Theory.Tonality
var _content: VBoxContainer
var _wheel: Wheel
var _title: Label
var _signature: Label
var _relative: Label
var _scale: Label
var _main_chords: Label
var _dominant: Label
var _enharmonic: Button
var _dialog: PanelContainer
var _dialog_body: VBoxContainer
var _shade: ColorRect
var _detail: Detail
var _direction := 1
var _lesson := 0
var _triad_form := Theory.ScaleForm.NATURAL
var _restore_focus: Control


func _ready() -> void:
	_content = _vertical(12)
	add_child(_content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	_content.add_child(header)
	var menu := Finish.menu_button()
	menu.custom_minimum_size = Vector2(75, 74)
	menu.pressed.connect(func() -> void: menu_requested.emit())
	header.add_child(menu)
	var heading := Finish.label("Квинтовый круг", 31, Finish.WHITE, 0.75)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var info := HeaderButton.new()
	info.symbol = HeaderButton.Icon.INFO
	info.pressed.connect(_open_detail.bind(Detail.HELP))
	header.add_child(info)
	info.set_metrics(72, 55)
	var sound := HeaderButton.new()
	sound.audio = audio
	header.add_child(sound)
	sound.set_metrics(72, 55)
	_wheel = Wheel.new()
	_wheel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wheel.sector_selected.connect(_select)
	_content.add_child(_wheel)

	var card := _panel(Color("#20252a"), Color("#454c52"), 20, 16)
	_content.add_child(card)
	var lines := _vertical(4)
	card.add_child(lines)
	_title = _line(lines, "", 30, Finish.WHITE, 0.7)
	_signature = _line(lines, "", 25, Finish.MUTED)
	_relative = _line(lines, "", 25, Finish.MUTED)
	_scale = _line(lines, "", 27)
	_main_chords = _line(lines, "", 25)
	_dominant = _line(lines, "", 23, Finish.MUTED)
	_enharmonic = _button(lines, "", _toggle_spelling)
	_enharmonic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var actions := _row(_content)
	_button(actions, "Сыграть гамму", _practice.bind(true), true)
	_button(actions, "Сыграть аккорды", _practice.bind(false), true)
	var details := _row(_content)
	_button(details, "Все трезвучия", _open_detail.bind(Detail.TRIADS))
	_button(details, "Сравнить тональности", _open_detail.bind(Detail.COMPARE))

	_shade = ColorRect.new()
	_shade.color = Color(0.027, 0.033, 0.041, 0.87)
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog = _panel(Color("#20262c"), Color("#55646c"), 22, 24)
	_shade.add_child(_dialog)
	_dialog_body = _vertical(12)
	_dialog.add_child(_dialog_body)
	_dialog.resized.connect(_center_dialog)
	_shade.hide()
	resized.connect(_layout)
	_content.minimum_size_changed.connect(_layout)
	get_window().size_changed.connect(_layout)
	visibility_changed.connect(_layout)
	_refresh()
	_layout()


func _select(index: int, minor: bool) -> void:
	if preferences.circle_minor != minor:
		_lesson = 0
		if not minor and _direction == 0:
			_direction = 1
	preferences.circle_sector = index
	preferences.circle_minor = minor
	preferences.save()
	_refresh()


func _toggle_spelling() -> void:
	preferences.circle_flats = not preferences.circle_flats
	preferences.save()
	_refresh()


func _refresh() -> void:
	var sector := preferences.circle_sector
	_key = Theory.at_sector(sector, preferences.circle_flats, preferences.circle_minor)
	_wheel.show_selection(sector, preferences.circle_flats, _key.minor)
	_title.text = _key.name()
	var signs := _key.signature_names()
	_signature.text = "Знаки при ключе: " + ("нет" if signs.is_empty() else "  ".join(signs))
	if _key.minor:
		var harmonic := Theory.ScaleForm.HARMONIC
		_relative.text = "Параллельный мажор: " + _key.relative_major().name()
		_scale.text = "Натуральный минор:  " + "  ".join(_key.scale_names())
		_main_chords.text = "Основные аккорды:  i — %s    iv — %s    V — %s" % [
			_key.triad_name(0), _key.triad_name(3), _key.triad_name(4, harmonic)]
		_dominant.text = "В гармоническом миноре VII ступень повышается (%s → %s). Мажорная V: %s." % [
			_key.note_name(6), _key.note_name(6, harmonic), "–".join(_key.triad_names(4, harmonic))]
	else:
		_relative.text = "Параллельный минор: " + _key.relative_minor().name()
		_scale.text = "Гамма:  " + "  ".join(_key.scale_names())
		_main_chords.text = "I  %s     IV  %s     V  %s" % [_key.triad_name(0), _key.triad_name(3), _key.triad_name(4)]
	_dominant.visible = _key.minor
	_enharmonic.visible = sector == Theory.ENHARMONIC_SECTOR
	if _enharmonic.visible:
		var alternate := Theory.at_sector(sector, not preferences.circle_flats, _key.minor)
		_enharmonic.text = "Записать как " + alternate.short_name()


func _practice(scale_mode: bool) -> void:
	practice_requested.emit(_key, scale_mode)


func _open_detail(detail: Detail) -> void:
	_detail = detail
	if detail == Detail.TRIADS:
		_triad_form = Theory.ScaleForm.NATURAL
	_restore_focus = get_viewport().gui_get_focus_owner()
	_content.hide()
	_shade.show()
	_show_detail()


func close_detail() -> bool:
	if not _shade.visible:
		return false
	_shade.hide()
	_content.show()
	if is_instance_valid(_restore_focus):
		_restore_focus.grab_focus()
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel") and close_detail():
		get_viewport().set_input_as_handled()


func _show_detail() -> void:
	for child in _dialog_body.get_children():
		_dialog_body.remove_child(child)
		child.queue_free()
	match _detail:
		Detail.TRIADS: _triads()
		Detail.COMPARE: _comparison()
		Detail.HELP: _explanation()
	var close := _button(_dialog_body, "Закрыть", close_detail)
	close.grab_focus()
	_center_dialog.call_deferred()


func _triads() -> void:
	_line(_dialog_body, "Трезвучия · " + _key.short_name(), 33, Finish.WHITE, 0.7)
	if _key.minor:
		var forms := _row(_dialog_body)
		_button(forms, "Натуральный", _show_triad_form.bind(Theory.ScaleForm.NATURAL),
			_triad_form == Theory.ScaleForm.NATURAL)
		_button(forms, "Гармонический", _show_triad_form.bind(Theory.ScaleForm.HARMONIC),
			_triad_form == Theory.ScaleForm.HARMONIC)
	var table := GridContainer.new()
	table.columns = 4
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 6)
	_dialog_body.add_child(table)
	for degree in range(7):
		_line(table, _key.triad_roman(degree, _triad_form), 23, Finish.MUTED)
		_line(table, _key.triad_name(degree, _triad_form), 26, Finish.WHITE, 0.6)
		_line(table, " ".join(_key.triad_names(degree, _triad_form)), 23)
		_line(table, Theory.QUALITIES[_key.triad_quality(degree, _triad_form)], 22, Finish.MUTED)


func _show_triad_form(form: Theory.ScaleForm) -> void:
	_triad_form = form
	_show_detail()


func _comparison() -> void:
	var result := Comparison.new(preferences.circle_sector, _direction, preferences.circle_flats, _key.minor)
	var relative := _direction == 0
	var source_name := _key.short_name()
	var target_name := result.target.short_name()
	_line(_dialog_body, "%s %s %s" % [source_name, "↔" if relative else "→", target_name], 35, Finish.WHITE, 0.7)
	if not relative:
		_line(_dialog_body, "По часовой — чистая квинта вверх.\nПротив часовой — чистая квинта вниз.", 25, Finish.MUTED)
	var directions := _row(_dialog_body)
	_button(directions, "↶  Против часовой", _compare_direction.bind(-1), _direction < 0)
	_button(directions, "↻  По часовой", _compare_direction.bind(1), _direction > 0)
	if _key.minor:
		_button(_dialog_body, "Параллельный мажор", _compare_direction.bind(0), relative)
	var source_label := source_name + " (нат.)" if _key.minor else source_name
	var target_label := target_name + " (нат.)" if result.target.minor else target_name
	_line(_dialog_body, "%s  ·  %s" % [source_label, "  ".join(_key.scale_names())], 26)
	_line(_dialog_body, "%s  ·  %s" % [target_label, "  ".join(result.target.scale_names())], 26)
	_line(_dialog_body, "Общие звуки: %d из 7" % result.common, 29, Color("#a8e0e3"), 0.7)
	if relative:
		_line(_dialog_body, result.signature_change, 25, Finish.MUTED)
		_line(_dialog_body, "%s и %s используют одни звуки, но имеют разные тоники. Меняются интервалы от тоники и характер звучания." % [
			result.target.russian_name(), _key.russian_name()], 25)
		return
	_line(_dialog_body, "Изменение: %s → %s" % [result.removed, result.added], 27)
	_line(_dialog_body, result.signature_change, 25, Finish.MUTED)
	if _key.signature * result.target.signature < 0:
		_line(_dialog_body, "Общие звуки посчитаны по звучанию. При смене записи их названия могут отличаться.", 25, Finish.MUTED)
	_button(_dialog_body, "Выбрать " + target_name, _open_neighbor, true)


func _compare_direction(direction: int) -> void:
	_direction = direction
	_show_detail()


func _open_neighbor() -> void:
	_select(posmod(preferences.circle_sector + _direction, Theory.WHEEL.size()), _key.minor)
	close_detail()


func _explanation() -> void:
	var tonic := _key.note_name(0)
	var minor := _key.relative_minor()
	var lessons := [
		["Почему круг квинтовый", "Чистая квинта — семь полутонов. От C до G — квинта вверх, от C до F — квинта вниз. Соседние мажорные гаммы имеют шесть общих звуков."],
		["Откуда берутся диезы", "От C двигайтесь по часовой стрелке: G получает F♯, затем D получает ещё C♯. Повышение VII ступени создаёт полутон до новой тоники."],
		["Откуда берутся бемоли", "От C двигайтесь против часовой стрелке: F получает B♭, затем B♭ получает ещё E♭. Понижение IV ступени сохраняет полутон между III и IV."],
		["Параллельные тональности", "%s major и %s minor используют одни и те же ключевые знаки. В мажоре точка опоры — %s, в параллельном миноре — %s. У одноимённых тональностей общая тоника, как у C major и C minor." % [tonic, minor.note_name(0), tonic, minor.note_name(0)]],
		["Как строятся трезвучия", "Сложите три звука гаммы через ступень. На I ступени %s major получается %s. Повторите это для каждой из семи ступеней." % [tonic, "–".join(_key.triad_names(0))]],
		["Тоника, субдоминанта, доминанта", "В %s major последовательность %s → %s → %s → %s показывает, как можно уйти от тоники, создать напряжение и вернуться к ней. Это один из основных примеров тональной гармонии." % [tonic, _key.triad_name(0), _key.triad_name(3), _key.triad_name(4), _key.triad_name(0)]],
		["Энгармоническая запись", "F♯ и G♭ звучат одинаково на фортепиано в равномерной темперации. У F♯ major шесть диезов, включая E♯. У G♭ major шесть бемолей, включая C♭. Попробуйте обе записи в одном секторе."],
	]
	if _key.minor:
		lessons = _minor_lessons()
	_line(_dialog_body, "%d / %d" % [_lesson + 1, lessons.size()], 22, Finish.MUTED)
	_line(_dialog_body, lessons[_lesson][0], 33, Finish.WHITE, 0.7)
	var explanation := _line(_dialog_body, lessons[_lesson][1], 29)
	explanation.custom_minimum_size.y = 185.0
	var navigation := _row(_dialog_body)
	_button(navigation, "Назад", _lesson_step.bind(-1)).disabled = _lesson == 0
	_button(navigation, "Далее", _lesson_step.bind(1), true).disabled = _lesson == lessons.size() - 1


func _minor_lessons() -> Array:
	var tonic := _key.note_name(0)
	var major := _key.relative_major()
	var harmonic := Theory.ScaleForm.HARMONIC
	return [
		["Параллельные тональности", "%s и %s — параллельные тональности: у них разные тоники и один набор звуков. У одноимённых тональностей общая тоника: например, C major и C minor." % [major.short_name(), _key.short_name()]],
		["Общие ключевые знаки", "%s — те же звуки, что и в %s. Натуральный минор начинает их с VI ступени параллельного мажора, поэтому ключевые знаки совпадают." % ["  ".join(_key.scale_names()), major.short_name()]],
		["Натуральный минор", "От %s до III ступени (%s) — малая терция, три полутона. В %s от %s до %s — большая терция, четыре полутона." % [tonic, _key.note_name(2), major.short_name(), major.note_name(0), major.note_name(2)]],
		["Гармонический минор", "В %s VII ступень можно повысить: %s → %s. Теперь до %s остаётся полутон. Такой вводный тон тяготеет к тонике. Ключевые знаки сохраняются." % [_key.short_name(), _key.note_name(6), _key.note_name(6, harmonic), tonic]],
		["Мажорная доминанта", "Натуральный минор даёт минорную v: %s. Повышенная VII ступень превращает её в мажорную V: %s. Послушайте, как %s разрешается в %s." % [_key.triad_name(4), _key.triad_name(4, harmonic), _key.triad_name(4, harmonic), _key.triad_name(0)]],
		["Энгармоническая запись", "D♯ minor и E♭ minor звучат одинаково на фортепиано. В первой записи вводный тон — C𝄪, во второй — D. Буква показывает ступень гаммы и её положение на нотном стане."],
		["Тональный центр", "Сыграйте %s и %s. Звуки совпадают, но в первой гамме точка опоры — %s, во второй — %s. Смена тоники меняет интервалы от неё и характер музыки." % [major.short_name(), _key.short_name(), major.note_name(0), tonic]],
	]


func _lesson_step(direction: int) -> void:
	_lesson += direction
	_show_detail()


func _layout() -> void:
	var bounds := Finish.safe_bounds(self)
	var width := minf(bounds.size.x * 0.91, 820.0)
	var diameter := minf(bounds.size.x * 0.82, bounds.size.y * 0.49)
	if _key != null and _key.minor:
		var surrounding_height := _content.get_combined_minimum_size().y - _wheel.custom_minimum_size.y
		diameter = minf(diameter, bounds.size.y - surrounding_height - 44.0)
	_content.position = Vector2(bounds.get_center().x - width * 0.5, bounds.position.y + 22.0)
	_content.size.x = width
	_wheel.custom_minimum_size = Vector2.ONE * maxf(1.0, floorf(diameter))
	_center_dialog()


func _center_dialog() -> void:
	if not _shade.visible:
		return
	var bounds := Finish.safe_bounds(self)
	var width := minf(bounds.size.x * 0.92, 760.0)
	_dialog.size = Vector2(width, 0.0)
	_dialog.position = bounds.get_center() - _dialog.size * 0.5


static func _vertical(gap: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	return box


static func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	return row


static func _panel(fill: Color, border: Color, radius: int, padding: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := Finish.flat(fill, border, radius, 1)
	style.set_content_margin_all(padding)
	panel.add_theme_stylebox_override("panel", style)
	return panel


static func _line(parent: Control, caption: String, points: int, ink := Finish.WHITE, weight := 0.0) -> Label:
	var label := Finish.label(caption, points, ink, weight)
	if parent is VBoxContainer:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


static func _button(parent: Control, caption: String, action: Callable, emphasized := false) -> Button:
	var button := Finish.action_button(caption, 25, emphasized)
	button.custom_minimum_size.y = 76.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button
