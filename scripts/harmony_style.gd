extends RefCounted

const Finish := preload("res://scripts/finish.gd")
const TEAL := Color("#076B73")
const PANEL := Color("#1c2025")
const LINE := Color("#373e46")


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 27
	for type in [&"Button", &"OptionButton", &"CheckButton"]:
		theme.set_stylebox("normal", type, _control(Color("#292e34"), Color("#4a525a")))
		theme.set_stylebox("hover", type, _control(Color("#333b42"), Color("#63717b")))
		theme.set_stylebox("pressed", type, _control(TEAL, Color("#6ab5ba")))
		theme.set_stylebox("disabled", type, _control(Color("#191c21"), Color("#2f3439")))
		theme.set_stylebox("focus", type, Finish.flat(Color.TRANSPARENT, Color("#79c0c3"), 15, 2))
		theme.set_color("font_color", type, Finish.WHITE)
		theme.set_color("font_disabled_color", type, Color("#858d96"))
	theme.set_stylebox("normal", &"LineEdit", _control(Color("#171b20"), Color("#56636d")))
	theme.set_stylebox("focus", &"LineEdit", _control(Color("#171b20"), Color("#79c0c3")))
	theme.set_color("font_placeholder_color", &"LineEdit", Finish.MUTED)
	theme.set_color("font_color", &"LineEdit", Finish.WHITE)
	theme.set_stylebox("panel", &"PopupMenu", _control(PANEL, LINE))
	theme.set_stylebox("hover", &"PopupMenu", Finish.flat(TEAL, Color("#6ab5ba"), 8, 1))
	theme.set_color("font_color", &"PopupMenu", Finish.WHITE)
	return theme


static func _control(color: Color, border: Color) -> StyleBoxFlat:
	var style := Finish.flat(color, border, 15, 1)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


static func card_style(active: bool) -> StyleBoxFlat:
	var style := Finish.flat(TEAL if active else PANEL, Color("#6ab5ba") if active else LINE, 15, 1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


static func row(parent: Control, gap := 10) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box


static func column(parent: Control, gap := 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box


static func label(parent: Control, caption: String, points := 27, muted := false) -> Label:
	var item := Label.new()
	item.text = caption
	item.add_theme_font_size_override("font_size", points)
	item.add_theme_color_override("font_color", Finish.MUTED if muted else Finish.WHITE)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item


static func ellipsis(item: Label) -> void:
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


static func button(parent: Control, caption: String, action: Callable, width := 0, height := 86,
		primary := false) -> Button:
	var item := Button.new()
	item.text = caption
	item.clip_text = true
	item.custom_minimum_size = Vector2(width, height)
	if primary:
		item.add_theme_stylebox_override("normal", _control(TEAL, Color("#46898e")))
		item.add_theme_stylebox_override("hover", _control(Color("#0a7d86"), Color("#79c0c3")))
	parent.add_child(item)
	if action.is_valid():
		item.pressed.connect(action)
	return item


static func line_edit(parent: Control, value: String, placeholder: String, limit: int) -> LineEdit:
	var item := LineEdit.new()
	item.text = value
	item.placeholder_text = placeholder
	item.max_length = limit
	item.custom_minimum_size.y = 86
	item.clear_button_enabled = true
	parent.add_child(item)
	return item


static func selector(parent: Control, caption: String, height := 78) -> OptionButton:
	var item := OptionButton.new()
	item.custom_minimum_size.y = height
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.accessibility_name = caption
	item.clip_text = true
	item.fit_to_longest_item = false
	item.get_popup().add_theme_font_size_override("font_size", 26)
	item.get_popup().add_theme_constant_override("v_separation", 34)
	parent.add_child(item)
	return item


static func scroll(parent: Control) -> ScrollContainer:
	var scroll_view := ScrollContainer.new()
	scroll_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	parent.add_child(scroll_view)
	return scroll_view
