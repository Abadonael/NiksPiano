extends RefCounted

const Chord := preload("res://scripts/harmony_chords.gd")
const Patterns := preload("res://scripts/harmony_patterns.gd")
const FORMAT := "nikspiano-composition"
const SCHEMA := 2
const OLDEST_SCHEMA := 1
const MAX_EVENTS := 512
const DURATIONS := [1, 2, 4]
const REPEATS := [1, 2, 4, 0]
const MIN_BPM := 40
const MAX_BPM := 200
const BEATS_PER_MEASURE := 4
const MAX_TITLE := 80
const MAX_TIMESTAMP := 253402300799


static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


static func now() -> int:
	return int(Time.get_unix_time_from_system())


static func create(title := "Новая композиция") -> Dictionary:
	var timestamp := now()
	return {"format": FORMAT, "schema_version": SCHEMA, "id": new_id(), "title": title,
		"created_at": timestamp, "modified_at": timestamp, "bpm": 90, "time_signature": [4, 4],
		"repeat": 1, "key_context": "", "default_pattern": Patterns.BLOCK, "events": []}


static func copy_project(project: Dictionary, title: String) -> Dictionary:
	var copy := project.duplicate(true)
	copy.id = new_id()
	copy.title = title
	copy.created_at = now()
	copy.modified_at = copy.created_at
	return copy


static func insert(project: Dictionary, index: int, definition: Dictionary, beats := 4) -> bool:
	var events: Array = project.events
	if events.size() >= MAX_EVENTS or index < 0 or index > events.size() or beats not in DURATIONS:
		return false
	var chord := Chord.validate(definition)
	if chord.is_empty():
		return false
	var event := {"id": new_id(), "start_beat": 0, "duration_beats": beats, "pattern": null}
	set_voicing(event, chord)
	events.insert(index, event)
	recalculate(project)
	return true


static func set_voicing(event: Dictionary, chord: Dictionary, bass: Variant = null, spelling := "") -> void:
	event.chord = chord
	event.bass_midi = bass
	event.bass_spelling = spelling
	event.sounding_pitches = Chord.sounding(chord, bass)
	event.voicing = {"base_inversion": Chord.inversion(chord, int(chord.pitches.min())),
		"inversion": Chord.inversion(chord, int(event.sounding_pitches.min()))}


static func remove(project: Dictionary, index: int) -> void:
	project.events.remove_at(index)
	recalculate(project)


static func duplicate_event(project: Dictionary, index: int) -> bool:
	if project.events.size() >= MAX_EVENTS:
		return false
	var copy: Dictionary = project.events[index].duplicate(true)
	copy.id = new_id()
	project.events.insert(index + 1, copy)
	recalculate(project)
	return true


static func move(project: Dictionary, from: int, to: int) -> bool:
	var events: Array = project.events
	if from == to or from < 0 or from >= events.size() or to < 0 or to >= events.size():
		return false
	var event: Dictionary = events.pop_at(from)
	events.insert(to, event)
	recalculate(project)
	return true


static func recalculate(project: Dictionary) -> void:
	var beat := 0
	for event: Dictionary in project.events:
		event.start_beat = beat
		beat += int(event.duration_beats)


static func length_beats(project: Dictionary) -> int:
	var events: Array = project.events
	if events.is_empty():
		return 0
	var last: Dictionary = events.back()
	return int(last.start_beat) + int(last.duration_beats)


static func measure(beat: int) -> int:
	return floori(float(beat) / BEATS_PER_MEASURE) + 1


static func measures(project: Dictionary) -> int:
	return ceili(float(length_beats(project)) / BEATS_PER_MEASURE)


static func position_label(beat: int) -> String:
	return "Такт %d · доля %d" % [measure(beat), beat % BEATS_PER_MEASURE + 1]


static func beat_label(beats: int) -> String:
	return "%d %s" % [beats, "доля" if beats == 1 else "доли"]


static func duration_label(beats: int) -> String:
	@warning_ignore("integer_division")
	var bars := beats / BEATS_PER_MEASURE
	var remainder := beats % BEATS_PER_MEASURE
	if bars == 0:
		return "0 долей" if remainder == 0 else beat_label(remainder)
	var wording := "тактов"
	if bars % 100 not in range(11, 15):
		if bars % 10 == 1:
			wording = "такт"
		elif bars % 10 in range(2, 5):
			wording = "такта"
	if remainder == 0:
		return "%d %s" % [bars, wording]
	return "%d %s %s + %s" % [bars, "полный" if wording == "такт" else "полных", wording, beat_label(remainder)]


static func valid_id(value: Variant) -> bool:
	if not value is String or value.length() != 32:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("format") != FORMAT or not Chord.integer_in(value.get("schema_version"), OLDEST_SCHEMA, SCHEMA):
		return {}
	var legacy: bool = value.schema_version == OLDEST_SCHEMA
	var default_pattern: Variant = Patterns.BLOCK if legacy else value.get("default_pattern")
	if not Patterns.valid(default_pattern):
		return {}
	if not valid_id(value.get("id")) or not _valid_text(value.get("title"), MAX_TITLE):
		return {}
	if not Chord.integer_in(value.get("created_at"), 0, MAX_TIMESTAMP) or not Chord.integer_in(value.get("modified_at"), int(value.created_at), MAX_TIMESTAMP):
		return {}
	if not Chord.integer_in(value.get("bpm"), MIN_BPM, MAX_BPM):
		return {}
	var signature: Variant = value.get("time_signature")
	if not signature is Array or signature.size() != 2 or not Chord.integer_in(signature[0], 4, 4) or not Chord.integer_in(signature[1], 4, 4):
		return {}
	if not Chord.integer_in(value.get("repeat"), 0, 4) or int(value.repeat) not in REPEATS:
		return {}
	var key: Variant = value.get("key_context", "")
	var source: Variant = value.get("events")
	if not key is String or key.length() > 48 or not source is Array or source.size() > MAX_EVENTS:
		return {}
	var events := []
	var ids := {}
	var beat := 0
	for entry: Variant in source:
		if not entry is Dictionary or not valid_id(entry.get("id")) or ids.has(entry.id):
			return {}
		var beats: Variant = entry.get("duration_beats")
		if not Chord.integer_in(beats, 1, 4) or int(beats) not in DURATIONS:
			return {}
		if not Chord.integer_in(entry.get("start_beat"), beat, beat):
			return {}
		var chord := Chord.validate(entry.get("chord"))
		if chord.is_empty():
			return {}
		var event := _read_event(entry, chord, legacy)
		if event.is_empty():
			return {}
		ids[entry.id] = true
		events.append(event)
		beat += int(beats)
	return {"format": FORMAT, "schema_version": SCHEMA, "id": value.id, "title": value.title.strip_edges(),
		"created_at": int(value.created_at), "modified_at": int(value.modified_at), "bpm": int(value.bpm),
		"time_signature": [4, 4], "repeat": int(value.repeat), "key_context": key,
		"default_pattern": default_pattern, "events": events}


static func _read_event(entry: Dictionary, chord: Dictionary, legacy: bool) -> Dictionary:
	var event := {"id": entry.id, "start_beat": int(entry.start_beat),
		"duration_beats": int(entry.duration_beats), "pattern": null}
	if legacy:
		if entry.get("pattern", Patterns.BLOCK) != Patterns.BLOCK or entry.get("voicing") != null or entry.get("bass_midi") != null:
			return {}
		set_voicing(event, chord)
		return event
	var pattern: Variant = entry.get("pattern")
	var bass: Variant = entry.get("bass_midi")
	var spelling: Variant = entry.get("bass_spelling", "")
	if pattern != null and not Patterns.valid(pattern):
		return {}
	if bass == null:
		if spelling != "":
			return {}
	else:
		if not Chord.integer_in(bass, Chord.Audio.FREE_LOWEST, int(chord.pitches.min()) - 1):
			return {}
		if not Chord.valid_bass_spelling(spelling) or Chord.bass_pitch_class(spelling) != int(bass) % 12:
			return {}
		bass = int(bass)
	event.pattern = pattern
	set_voicing(event, chord, bass, spelling)
	var voicing: Variant = entry.get("voicing")
	if not voicing is Dictionary or voicing.size() != event.voicing.size():
		return {}
	for key: String in event.voicing:
		if not voicing.has(key):
			return {}
		var expected: Variant = event.voicing[key]
		if expected == null:
			if voicing[key] != null:
				return {}
		elif not Chord.integer_in(voicing[key], expected, expected):
			return {}
	var sounding: Variant = entry.get("sounding_pitches")
	if not sounding is Array or sounding.size() != event.sounding_pitches.size():
		return {}
	for index in range(sounding.size()):
		var pitch: int = event.sounding_pitches[index]
		if not Chord.integer_in(sounding[index], pitch, pitch):
			return {}
	return event


static func _valid_text(value: Variant, limit: int) -> bool:
	return value is String and value.length() <= limit and not value.strip_edges().is_empty() and not "\n" in value and not "\r" in value
