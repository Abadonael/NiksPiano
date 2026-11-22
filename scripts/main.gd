extends Control

const Settings := preload("res://scripts/settings.gd")
const Menu := preload("res://scripts/menu.gd")
const Game := preload("res://scripts/game.gd")
const ChordGame := preload("res://scripts/chord_game.gd")
const MelodyGame := preload("res://scripts/melody_game.gd")
const CircleExplorer := preload("res://scripts/circle_explorer.gd")
const CirclePractice := preload("res://scripts/circle_practice.gd")
const Theory := preload("res://scripts/key_theory.gd")
const FreePiano := preload("res://scripts/free_piano.gd")
const FREE_SCENE := preload("res://free_piano.tscn")
const PianoAudio := preload("res://scripts/piano_audio.gd")
const HarmonyLab := preload("res://scripts/harmony_lab.gd")
const CARBON := preload("res://assets/carbon.gdshader")
const PRODUCT_TITLE := "Nik's Piano"

var preferences := Settings.new()
var _audio: PianoAudio
var _menu: Menu
var _game: Game
var _chord_game: ChordGame
var _melody_game: MelodyGame
var _circle: CircleExplorer
var _circle_practice: CirclePractice
var _free_piano: FreePiano
var _harmony_lab: HarmonyLab
var _carbon: ShaderMaterial
var _portrait_scale: Vector2i
var _portrait_window: Rect2i
var _android_window_mode: DisplayServer.WindowMode


func _ready() -> void:
	get_window().title = PRODUCT_TITLE
	_portrait_scale = get_window().content_scale_size
	var background := ColorRect.new()
	background.mouse_filter = MOUSE_FILTER_IGNORE
	_carbon = ShaderMaterial.new()
	_carbon.shader = CARBON
	background.material = _carbon
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_resize_carbon)
	_resize_carbon()

	preferences.load_settings()
	_audio = PianoAudio.new()
	_audio.name = "PianoAudio"
	add_child(_audio)
	_audio.set_enabled(preferences.sound_enabled)
	_audio.enabled_changed.connect(_save_sound)
	_menu = Menu.new()
	_menu.name = "Menu"
	_menu.preferences = preferences
	_menu.audio = _audio
	_menu.start_requested.connect(_show_game)
	add_child(_menu)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.hide()
	_menu.visibility_changed.connect(func() -> void: background.visible = not _menu.visible)

	_game = Game.new()
	_game.name = "Game"
	_game.audio = _audio
	_game.menu_requested.connect(_show_menu)
	_game.hide()
	add_child(_game)
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_chord_game = ChordGame.new()
	_chord_game.name = "ChordGame"
	_chord_game.audio = _audio
	_chord_game.menu_requested.connect(_show_menu)
	_chord_game.hide()
	add_child(_chord_game)
	_chord_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_melody_game = MelodyGame.new()
	_melody_game.name = "MelodyGame"
	_melody_game.audio = _audio
	_melody_game.menu_requested.connect(_show_menu)
	_melody_game.hide()
	add_child(_melody_game)
	_melody_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_circle = CircleExplorer.new()
	_circle.name = "CircleExplorer"
	_circle.preferences = preferences
	_circle.audio = _audio
	_circle.menu_requested.connect(_show_menu)
	_circle.practice_requested.connect(_show_circle_practice)
	_circle.hide()
	add_child(_circle)
	_circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_circle_practice = CirclePractice.new()
	_circle_practice.name = "CirclePractice"
	_circle_practice.audio = _audio
	_circle_practice.menu_requested.connect(_return_to_circle)
	_circle_practice.hide()
	add_child(_circle_practice)
	_circle_practice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_free_piano = FREE_SCENE.instantiate()
	_free_piano.audio = _audio
	_free_piano.preferences = preferences
	_free_piano.menu_requested.connect(_show_menu)
	_free_piano.hide()
	add_child(_free_piano)
	_harmony_lab = HarmonyLab.new()
	_harmony_lab.name = "HarmonyLab"
	_harmony_lab.audio = _audio
	_harmony_lab.preferences = preferences
	_harmony_lab.menu_requested.connect(_menu.show)
	_harmony_lab.hide()
	add_child(_harmony_lab)
	_harmony_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().quit_on_go_back = false


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _harmony_lab != null and _harmony_lab.visible:
		_harmony_lab.close_page()
	elif _circle_practice != null and _circle_practice.visible:
		_return_to_circle()
	elif _circle != null and _circle.visible:
		if not _circle.close_detail():
			_show_menu()
	elif not _menu.visible:
		_show_menu()
	elif not _menu.close_credits() and not _menu.close_settings():
		get_tree().quit()


func _save_sound(enabled: bool) -> void:
	preferences.sound_enabled = enabled
	preferences.save()


func _show_game() -> void:
	if not _menu.visible:
		return
	_menu.hide()
	if preferences.mode == Settings.Mode.HARMONY_LAB:
		_harmony_lab.enter()
		return
	if preferences.mode == Settings.Mode.CIRCLE:
		_circle.show()
		return
	if preferences.mode == Settings.Mode.FREE_PIANO:
		_set_landscape(true)
		if OS.get_name() == "Android":
			_android_window_mode = DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_free_piano.start()
		_free_piano.show()
		return
	if preferences.mode == Settings.Mode.CHORDS:
		_set_landscape(true)
		_chord_game.start(preferences.chord_mask)
		_chord_game.show()
		return
	if preferences.mode == Settings.Mode.MELODIES:
		_set_landscape(true)
		_melody_game.start(preferences.melody_kind, preferences.melody_difficulty,
			preferences.melody_length, preferences.melody_clef)
		_melody_game.show()
		return
	_game.start(preferences.mode == Settings.Mode.STAFF, preferences.letter_names, preferences.range_mask)
	_game.show()


func _show_menu() -> void:
	if _circle.visible:
		_circle.hide()
	elif _free_piano.visible:
		_free_piano.stop()
		_free_piano.hide()
		if OS.get_name() == "Android":
			DisplayServer.window_set_mode(_android_window_mode)
		_set_landscape(false)
	elif _chord_game.visible:
		_chord_game.stop()
		_chord_game.hide()
		_set_landscape(false)
	elif _melody_game.visible:
		_melody_game.stop()
		_melody_game.hide()
		_set_landscape(false)
	else:
		_game.stop()
		_game.hide()
	_menu.show()


func _show_circle_practice(key: Theory.Tonality, scale_mode: bool) -> void:
	_circle.hide()
	_set_landscape(true)
	_circle_practice.study(key, scale_mode)
	_circle_practice.show()


func _return_to_circle() -> void:
	_circle_practice.stop()
	_circle_practice.hide()
	_set_landscape(false)
	_circle.show()


func _set_landscape(landscape: bool) -> void:
	var window := get_window()
	window.content_scale_size = Vector2i(_portrait_scale.y, _portrait_scale.x) if landscape else _portrait_scale
	if OS.get_name() == "Android":
		var orientation := DisplayServer.SCREEN_LANDSCAPE if landscape else DisplayServer.SCREEN_PORTRAIT
		DisplayServer.screen_set_orientation(orientation)
	elif landscape:
		_portrait_window = Rect2i(window.position, window.size)
		var landscape_size := Vector2i(maxi(window.size.x, window.size.y), mini(window.size.x, window.size.y))
		if DisplayServer.get_name() != "headless":
			var screen := DisplayServer.screen_get_usable_rect(window.current_screen).grow(-32)
			var fit := minf(float(screen.size.x) / landscape_size.x, float(screen.size.y) / landscape_size.y)
			landscape_size = Vector2i(Vector2(landscape_size) * minf(1.0, fit))
			var centered := _portrait_window.get_center() - landscape_size / 2
			window.position = centered.clamp(screen.position, screen.end - landscape_size)
		window.size = landscape_size
	else:
		window.size = _portrait_window.size
		window.position = _portrait_window.position


func _resize_carbon() -> void:
	_carbon.set_shader_parameter("canvas_size", size)
