extends PanelContainer

signal audition_requested

const Staff := preload("res://scripts/harmony_staff.gd")
const Chord := preload("res://scripts/harmony_chords.gd")
const UI := preload("res://scripts/harmony_style.gd")

var staff: Staff
var _title: Label
var _caption: Label
var audition_enabled := false
var _audition: Button


func _ready() -> void:
	var card := UI.card_style(false)
	add_theme_stylebox_override("panel", card)
	var content := UI.column(self, 2)
	_title = UI.label(content, "", 32)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.ellipsis(_title)
	staff = Staff.new()
	staff.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(staff)
	_caption = UI.label(content, "", 25, true)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if audition_enabled:
		_add_audition_target(card)
	show_chord({})


func _add_audition_target(card: StyleBox) -> void:
	# The overlay uses normal Button handling, including ScrollContainer drag cancellation.
	var layer := Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(layer)
	_audition = Button.new()
	_audition.accessibility_name = "Прослушать аккорд"
	var clear := StyleBoxEmpty.new()
	for state in [&"normal", &"hover", &"disabled"]:
		_audition.add_theme_stylebox_override(state, clear)
	var pressed := UI.Finish.flat(Color(UI.TEAL, 0.14), UI.TEAL, 15, 2)
	_audition.add_theme_stylebox_override("pressed", pressed)
	_audition.add_theme_stylebox_override("hover_pressed", pressed)
	_audition.add_theme_stylebox_override("focus", UI.Finish.flat(Color.TRANSPARENT, UI.TEAL, 15, 2))
	layer.add_child(_audition)
	_audition.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_audition.offset_left = -card.get_margin(SIDE_LEFT)
	_audition.offset_top = -card.get_margin(SIDE_TOP)
	_audition.offset_right = card.get_margin(SIDE_RIGHT)
	_audition.offset_bottom = card.get_margin(SIDE_BOTTOM)
	_audition.pressed.connect(audition_requested.emit)


func show_chord(definition: Dictionary, hint := "Выберите основной тон.", bass: Variant = null, spelling := "") -> void:
	var sounding: Array = [] if definition.is_empty() else Chord.sounding(definition, bass)
	staff.show_chord(definition, sounding, bass, spelling)
	_title.text = "" if definition.is_empty() else Chord.title(definition)
	if definition.get("kind") == "catalog":
		_title.text = Chord.written_pitch_class(definition.root) + Chord.SUFFIXES[definition.quality]
	if bass != null:
		_title.text += "/" + Chord.written_pitch_class(spelling)
	_title.visible = not _title.text.is_empty()
	_caption.text = hint if definition.is_empty() else " – ".join(staff.written_names(definition.kind == "custom"))
	if _audition != null:
		_audition.disabled = definition.is_empty() or not Chord.pitches_are_valid(definition.pitches)
		_audition.mouse_filter = MOUSE_FILTER_IGNORE if _audition.disabled else MOUSE_FILTER_STOP


func show_event(event: Dictionary) -> void:
	staff.show_chord(event.chord, event.sounding_pitches, event.bass_midi, event.bass_spelling)
	_title.text = Chord.event_title(event)
	_title.hide()
	_caption.text = "Звуки: " + " – ".join(staff.written_names(true))
