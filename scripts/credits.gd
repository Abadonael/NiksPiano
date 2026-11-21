extends Control

signal closed

const Finish := preload("res://scripts/finish.gd")
const HeaderButton := preload("res://scripts/header_button.gd")
const PADDING := 42.0

var _card: Panel
var _scroll: ScrollContainer
var _body: VBoxContainer
var _close: HeaderButton


func _ready() -> void:
	name = "Credits"
	var shade := ColorRect.new()
	shade.color = Color("#080a0ed9")
	add_child(shade)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	_card = Panel.new()
	_card.add_theme_stylebox_override("panel", Finish.flat(Color("#1b1f24"), Color("#575e68"), 24, 2))
	add_child(_card)

	var title := Finish.label("Об игре", 40, Finish.WHITE, 0.85)
	_card.add_child(title)
	title.position = Vector2(PADDING, 20.0)
	title.size.y = 76.0
	_close = HeaderButton.new()
	_close.symbol = HeaderButton.Icon.CLOSE
	_close.pressed.connect(func() -> void: closed.emit())
	_card.add_child(_close)
	_close.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	_close.offset_left = -HeaderButton.TARGET - 10.0
	_close.offset_right = -10.0
	_close.offset_top = 10.0
	_close.offset_bottom = HeaderButton.TARGET + 10.0

	_scroll = ScrollContainer.new()
	_scroll.name = "Notices"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card.add_child(_scroll)
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scroll.offset_left = PADDING
	_scroll.offset_right = -PADDING
	_scroll.offset_top = 118.0
	_scroll.offset_bottom = -32.0
	_scroll.add_theme_stylebox_override("scroll_focus", StyleBoxEmpty.new())
	_scroll.get_v_scroll_bar().add_theme_stylebox_override("grabber",
		Finish.flat(Color("#616976"), Color.TRANSPARENT, 4))

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	_scroll.add_child(_body)
	_add_line("Niks Piano", 42, Finish.WHITE, 0.85)
	_add_line("Версия %s" % ProjectSettings.get_setting("application/config/version"), 26, Finish.MUTED)
	_add_heading("ЗВУК")
	_add_line("Salamander Grand Piano V3", 31, Finish.WHITE, 0.75)
	_add_line("Автор — Alexander Holm. Репак FLAC, настройки строя и смещения начала семплов — ремап kinwie.")
	_add_line("Creative Commons Attribution 3.0 Unported (CC BY 3.0)", 24)
	_add_line("Исходные семплы", 23, Finish.MUTED)
	_add_line("https://github.com/sfzinstruments/SalamanderGrandPiano", 22)
	_add_line("Лицензия", 23, Finish.MUTED)
	_add_line("https://creativecommons.org/licenses/by/3.0/", 22)
	_add_line("Для Niks Piano отобраны записи одного слоя динамики. Семплы подстроены, обрезаны, нормализованы по пику, обработаны плавным нарастанием и затуханием и преобразованы в стерео PCM (44,1 кГц, 16 бит). Промежуточные ноты воспроизводятся со сдвигом высоты.")
	_add_heading("НОТНЫЙ ШРИФТ")
	_add_line("Bravura", 31, Finish.WHITE, 0.75)
	_add_line("© 2026 Steinberg Media Technologies GmbH. Reserved Font Name «Bravura». SIL Open Font License 1.1.")
	_add_heading("ИГРОВОЙ ДВИЖОК")
	_add_line("Godot Engine", 31, Finish.WHITE, 0.75)
	_add_line("© 2014–н. в. Godot Engine contributors. © 2007–2014 Juan Linietsky, Ariel Manzur. Лицензия MIT.")
	_add_line("https://godotengine.org/license/", 22)

	resized.connect(_layout)
	_layout()


func open() -> void:
	_layout()
	show()
	_scroll.scroll_vertical = 0
	_close.grab_focus()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
	elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		get_viewport().set_input_as_handled()


func _layout() -> void:
	var bounds := Finish.safe_bounds(self)
	_card.size = Vector2(minf(640.0, bounds.size.x - 64.0), bounds.size.y * 0.76)
	_card.position = bounds.get_center() - _card.size * 0.5


func _add_heading(caption: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 14.0
	_body.add_child(spacer)
	_add_line(caption, 22, Finish.MUTED, 0.75)


func _add_line(caption: String, points := 26, color := Finish.WHITE, weight := 0.0) -> void:
	var label := Finish.label(caption, points, color, weight)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)
