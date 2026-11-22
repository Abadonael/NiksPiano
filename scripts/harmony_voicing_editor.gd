extends VBoxContainer

signal voicing_changed(chord: Dictionary, bass: Variant, spelling: String)
signal bass_requested

const Chord := preload("res://scripts/harmony_chords.gd")
const UI := preload("res://scripts/harmony_style.gd")

var event: Dictionary
var _caption: Label
var _inversion: OptionButton
var _bass: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	if event.chord.kind == "catalog":
		_caption = UI.label(self, "", 24, true)
	var row := UI.row(self)
	if event.chord.kind == "catalog":
		_inversion = UI.selector(row, "Обращение трезвучия")
		for title: String in Chord.INVERSIONS:
			_inversion.add_item(title)
		_inversion.item_selected.connect(_change_inversion)
	_bass = UI.button(row, "", bass_requested.emit, 0, 78)
	_bass.size_flags_horizontal = SIZE_EXPAND_FILL
	_bass.accessibility_name = "Басовая нота"
	refresh()


func refresh() -> void:
	if _inversion != null:
		_caption.text = "Расположение трезвучия" if event.bass_midi == null else "Расположение без отдельного баса"
		_inversion.select(int(event.voicing.base_inversion))
	_bass.text = "Бас: %s  ›" % Chord.bass_name(event, int(event.sounding_pitches.min()))


func _change_inversion(index: int) -> void:
	if index == event.voicing.base_inversion:
		return
	var chord := Chord.invert(event.chord, index)
	var bass: Variant = event.bass_midi
	if bass != null and bass >= chord.pitches.min():
		bass = Chord.bass_pitches(chord, event.bass_spelling)[0]
	voicing_changed.emit(chord, bass, event.bass_spelling)
