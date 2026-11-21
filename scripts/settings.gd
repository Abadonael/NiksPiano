extends RefCounted

const Notes := preload("res://scripts/notes.gd")
const Chords := preload("res://scripts/chords.gd")
const Exercises := preload("res://scripts/melody_exercises.gd")

enum Mode { STAFF, NAMES, CHORDS, FREE_PIANO, MELODIES }

var mode := Mode.STAFF
var letter_names := false
var range_mask := 1
var chord_mask := Chords.DEFAULT_GROUPS
var sound_enabled := true
var free_locked := true
var free_zoom := 1.0
var free_center := -1.0
var melody_kind := Exercises.Kind.ARPEGGIO
var melody_difficulty := Exercises.Difficulty.BEGINNER
var melody_length := Exercises.DEFAULT_LENGTH
var melody_clef := Notes.Clef.TREBLE

var _path: String


func _init(path := "") -> void:
	_path = path
	if _path.is_empty():
		if OS.get_name() == "Windows" and OS.has_feature("editor"):
			_path = "res://.piano_settings.cfg"
		else:
			_path = "user://settings.cfg"


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(_path) != OK:
		return

	var legacy_mode: Variant = config.get_value("menu", "staff_mode", true)
	var fallback := Mode.NAMES if legacy_mode is bool and not legacy_mode else Mode.STAFF
	var saved_mode: Variant = config.get_value("menu", "mode", fallback)
	var naming: Variant = config.get_value("menu", "letter_names", false)
	var sound: Variant = config.get_value("menu", "sound_enabled", true)
	mode = saved_mode as Mode if saved_mode is int and saved_mode in Mode.values() else fallback
	letter_names = naming if naming is bool else false
	sound_enabled = sound if sound is bool else true
	range_mask = _load_mask(config, "range_mask", Notes.ALL_RANGES, 1)
	chord_mask = _load_mask(config, "chord_mask", Chords.ALL_GROUPS, Chords.DEFAULT_GROUPS)
	var locked: Variant = config.get_value("free_piano", "locked", true)
	free_locked = locked if locked is bool else true
	free_zoom = _free_number(config, "zoom", 1.0, 0.01, 100.0)
	free_center = _free_number(config, "center", -1.0, 0.0, 52.0)
	var saved_kind: Variant = config.get_value("melodies", "kind", Exercises.Kind.ARPEGGIO)
	var saved_difficulty: Variant = config.get_value("melodies", "difficulty", Exercises.Difficulty.BEGINNER)
	melody_kind = (saved_kind as Exercises.Kind
		if saved_kind is int and saved_kind in Exercises.Kind.values() else Exercises.Kind.ARPEGGIO)
	melody_difficulty = (saved_difficulty as Exercises.Difficulty
		if saved_difficulty is int and saved_difficulty in Exercises.Difficulty.values() else Exercises.Difficulty.BEGINNER)
	var saved_length: Variant = config.get_value("melodies", "length", Exercises.DEFAULT_LENGTH)
	var saved_clef: Variant = config.get_value("melodies", "clef", Notes.Clef.TREBLE)
	melody_length = saved_length if saved_length is int and saved_length in Exercises.LENGTHS else Exercises.DEFAULT_LENGTH
	melody_clef = saved_clef as Notes.Clef if saved_clef is int and saved_clef in Notes.Clef.values() else Notes.Clef.TREBLE


static func _free_number(config: ConfigFile, key: String, fallback: float, low: float, high: float) -> float:
	var value: Variant = config.get_value("free_piano", key, fallback)
	if (value is float or value is int) and is_finite(float(value)) and float(value) >= low:
		return minf(float(value), high)
	return fallback


static func _load_mask(config: ConfigFile, key: String, flags: int, fallback: int) -> int:
	var stored: Variant = config.get_value("menu", key, fallback)
	var mask := (int(stored) & flags) if stored is int else 0
	return mask if mask != 0 else fallback


func toggle_range(index: int) -> void:
	var updated := range_mask ^ (1 << index)
	if updated != 0:
		range_mask = updated


func toggle_chord_group(index: int) -> void:
	var updated := chord_mask ^ (1 << index)
	if updated != 0:
		chord_mask = updated


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("menu", "mode", mode)
	config.set_value("menu", "letter_names", letter_names)
	config.set_value("menu", "range_mask", range_mask)
	config.set_value("menu", "chord_mask", chord_mask)
	config.set_value("menu", "sound_enabled", sound_enabled)
	config.set_value("free_piano", "locked", free_locked)
	config.set_value("free_piano", "zoom", free_zoom)
	config.set_value("free_piano", "center", free_center)
	config.set_value("melodies", "kind", melody_kind)
	config.set_value("melodies", "difficulty", melody_difficulty)
	config.set_value("melodies", "length", melody_length)
	config.set_value("melodies", "clef", melody_clef)
	var temporary := _path + ".tmp"
	var result := config.save(temporary)
	if result == OK:
		result = DirAccess.rename_absolute(temporary, _path)
	if result != OK:
		push_warning("Could not save Niks Piano menu settings (%s)." % error_string(result))
