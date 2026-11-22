extends RefCounted

const Finish := preload("res://scripts/finish.gd")

const INK := Color("#e4f4f2")
const MUTED := Color("#93aab3")
const SECTION := Color("#a3c3c5")
const ICON := Color("#7fc6c3")
const LINE := Color("#2c454b")
const SURFACE := Color("#17242a")
const ACCENT := Color("#267d81")

const SYMBOLS := {
	"staff": '<path d="M3 4h18M3 8h18M3 12h18M3 16h18M3 20h18" stroke-opacity=".6"/><path d="M14 3v12a2.5 2.5 0 1 1-2.5-2.5H14m0-9 4 2"/>',
	"names": '<path d="M15.5 6.5a6 6 0 1 0 0 11M19.5 8v8m-2-4h4"/>',
	"chords": '<path d="M4 6h16M4 12h16M4 18h16" stroke-opacity=".5"/><ellipse cx="9" cy="18" rx="2.3" ry="1.5"/><ellipse cx="9" cy="12" rx="2.3" ry="1.5"/><ellipse cx="9" cy="6" rx="2.3" ry="1.5"/><path d="M11.3 18V3"/>',
	"note": '<path d="M9 18V5l12-2v13M9 9l12-2"/><ellipse cx="6" cy="18" rx="3" ry="2.5"/><ellipse cx="18" cy="16" rx="3" ry="2.5"/>',
	"circle": '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.5"/><path d="M12 3v5.5M12 15.5V21M3 12h5.5m7 0H21"/>',
	"layers": '<path d="m12 3 9 5.5-9 5.5-9-5.5 9-5.5Zm-9 9 9 5.5 9-5.5M3 16l9 5.5 9-5.5"/>',
	"piano": '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16m6-16v16M7 4v9m10-9v9"/>',
	"arpeggio": '<path d="M4 18h4m2-6h4m2-6h4" stroke-width="2.5"/>',
	"interval": '<ellipse cx="9" cy="7" rx="3" ry="2"/><ellipse cx="9" cy="17" rx="3" ry="2"/><path d="M12 17V4m5 2h2v12h-2"/>',
	"info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v5m0-8v.1"/>',
	"sound": '<path d="M3 9h4l5-4v14l-5-4H3zm12 0a4 4 0 0 1 0 6m3-9a8 8 0 0 1 0 12"/>',
	"muted": '<path d="M3 9h4l5-4v14l-5-4H3zm13 1 5 5m0-5-5 5"/>',
	"back": '<path d="m14 6-6 6 6 6m-5-6h12"/>',
	"arrow": '<path d="m10 6 6 6-6 6m5-6H3"/>',
	"check": '<path d="m5 12 4 4L19 6"/>',
}

var _icons: Dictionary[String, Texture2D]
var strong_font := Finish.weighted_font(0.63)
var title_font := Finish.weighted_font(0.95)


func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 28
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		result.set_color(state, &"Button", INK)
	for state in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_hover_pressed_color", &"icon_focus_color"]:
		result.set_color(state, &"Button", INK)
	result.set_font(&"font", &"Button", strong_font)
	result.set_constant(&"icon_max_width", &"Button", 42)
	result.set_stylebox(&"focus", &"Button", Finish.flat(Color.TRANSPARENT, Color("#91d6d0"), 19, 2))
	_button_styles(result, &"Tile", Color("#15262d"), LINE)
	_button_styles(result, &"Navigation", Color("#15252b"), LINE)
	_button_styles(result, &"HeaderAction", Color("#142229"), Color("#263d43"))
	_button_styles(result, &"Choice", SURFACE, LINE)
	_button_styles(result, &"Primary", Color("#206e73"), Color("#428c8d"))
	return result


static func _button_styles(result: Theme, type: StringName, fill: Color, border: Color) -> void:
	result.set_type_variation(type, &"Button")
	var normal := Finish.flat(fill, border, 19, 2)
	var hover := Finish.flat(fill.lightened(0.045), border.lightened(0.10), 19, 2)
	var pressed := Finish.flat(Color("#21575c"), Color("#5ca6a6"), 19, 2)
	var hover_pressed := Finish.flat(Color("#27646a"), Color("#77bab7"), 19, 2)
	if type == &"Primary":
		pressed.bg_color = ACCENT
		pressed.border_color = Color("#70bab7")
	elif type == &"HeaderAction":
		pressed.bg_color = Color("#192b32")
		pressed.border_color = Color("#34535a")
		hover_pressed.bg_color = Color("#213c43")
		hover_pressed.border_color = Color("#456a70")
	for style: StyleBoxFlat in [normal, hover, pressed, hover_pressed]:
		style.set_content_margin_all(6)
	result.set_stylebox(&"normal", type, normal)
	result.set_stylebox(&"hover", type, hover)
	result.set_stylebox(&"pressed", type, pressed)
	result.set_stylebox(&"hover_pressed", type, hover_pressed)


static func background() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("#102129"), Color("#0c151b"), Color("#071218")])
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 128
	texture.fill_to = Vector2(0.4, 0.84)
	return texture


func icon(symbol: String) -> Texture2D:
	if not _icons.has(symbol):
		var source := '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">%s</svg>'
		var image := Image.new()
		image.load_svg_from_string(source % SYMBOLS[symbol])
		_icons[symbol] = ImageTexture.create_from_image(image)
	return _icons[symbol]
