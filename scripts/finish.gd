extends RefCounted

const MUSIC_FONT := preload("res://assets/Bravura.otf")
const WHITE := Color("#ebedf1")
const MUTED := Color("#a8adb5")
const SUCCESS_GREEN := Color("#60c687")
const TEAL := Color("#076b73")


static func metal(
		top: Color, bottom: Color, rim: Color, radius: float, brushed := false
) -> StyleBoxTexture:
	var image := Image.create_empty(88, 112, false, Image.FORMAT_RGBA8)
	var center := Vector2(image.get_size()) * 0.5
	for y in range(image.get_height()):
		var vertical := float(y) / float(image.get_height() - 1)
		var gradient := top.lerp(bottom, pow(vertical, 0.78))
		var bevel := rim.lerp(rim.darkened(0.42), vertical * 0.85)
		for x in range(image.get_width()):
			var point := (Vector2(x, y) + Vector2(0.5, 0.5) - center).abs()
			var corner := point - (center - Vector2.ONE * radius)
			var distance := corner.max(Vector2.ZERO).length() + minf(maxf(corner.x, corner.y), 0.0) - radius
			var face := gradient
			if brushed:
				var grain := 0.012 * sin(float(x + y) * 2.45) + 0.007 * sin(float(x + y) * 0.79)
				face = face.lightened(maxf(grain, 0.0)).darkened(maxf(-grain, 0.0))
			var pixel := bevel.lerp(face, smoothstep(1.0, 2.6, -distance))
			pixel.a = clampf(0.5 - distance, 0.0, 1.0)
			image.set_pixel(x, y, pixel)

	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, radius + 3.0)
		style.set_content_margin(side, 0.0)
	return style


static func flat(fill: Color, border: Color, radius: int, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border_width)
	return style


static func label(caption: String, points: int, color := WHITE, weight := 0.0) -> Label:
	var result := Label.new()
	result.text = caption
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", points)
	result.add_theme_color_override("font_color", color)
	if weight > 0.0:
		result.add_theme_font_override("font", weighted_font(weight))
	return result


static func weighted_font(weight: float) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = weight
	return font


static func menu_button() -> Button:
	var button := Button.new()
	button.name = "BackToMenu"
	button.text = "☰"
	button.accessibility_name = "Меню"
	button.add_theme_font_size_override("font_size", 34)
	var dark := metal(Color("#35393f"), Color("#1a1e21"), Color("#60666c"), 15.0)
	var bright := metal(Color("#484e55"), Color("#292d32"), Color("#a3aab2"), 15.0)
	button.add_theme_stylebox_override("normal", dark)
	button.add_theme_stylebox_override("hover", bright)
	button.add_theme_stylebox_override("pressed", bright)
	button.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT, WHITE, 15, 2))
	return button


static func action_button(caption: String, points: int, emphasized := false) -> Button:
	var button := Button.new()
	button.text = caption
	button.add_theme_font_size_override("font_size", points)
	var fill := TEAL if emphasized else Color("#252a30")
	var border := Color("#45949b") if emphasized else Color("#50575e")
	var normal := flat(fill, border, 13, 1)
	normal.set_content_margin_all(8.0)
	var active := normal.duplicate() as StyleBoxFlat
	active.bg_color = fill.lightened(0.12)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", active)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT, WHITE, 13, 2))
	return button


static func safe_bounds(control: Control) -> Rect2:
	var bounds := Rect2(Vector2.ZERO, control.size)
	if OS.get_name() != "Android":
		return bounds
	var viewport_to_canvas := control.get_viewport().get_final_transform().affine_inverse()
	return inset_bounds(bounds, viewport_to_canvas * Rect2(DisplayServer.get_display_safe_area()))


static func inset_bounds(bounds: Rect2, safe: Rect2) -> Rect2:
	var intersection := bounds.intersection(safe)
	# Android may briefly report the previous orientation while rotating the surface.
	if intersection.size.x >= bounds.size.x * 0.75 and intersection.size.y >= bounds.size.y * 0.75:
		return intersection
	return bounds
