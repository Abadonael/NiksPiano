extends RefCounted

const Chord := preload("res://scripts/harmony_chords.gd")
const BLOCK := "attack"
const LABELS := {
	BLOCK: "Одновременно",
	"repeated": "Удары по долям",
	"broken": "Перебор",
	"bass_chord": "Бас + аккорд",
	"alberti": "Бас Альберти",
}
const HINTS := {
	BLOCK: "Все ноты звучат вместе в начале аккорда.",
	"repeated": "Аккорд повторяется на каждой доле.",
	"broken": "Ноты идут вверх и обратно восьмыми.",
	"bass_chord": "На нечётных долях звучит бас, на чётных — аккорд.",
	"alberti": "Перебор восьмыми: нижний — верхний — средний — верхний.",
}
const ALBERTI_FALLBACK := "Бас Альберти требует трёх нот трезвучия. Здесь ноты прозвучат одновременно."
const SUBDIVISIONS := 2


static func valid(value: Variant) -> bool:
	return value is String and LABELS.has(value)


static func effective(default_pattern: String, event: Dictionary) -> String:
	var override: Variant = event.get("pattern")
	return default_pattern if override == null else str(override)


static func event_hint(event: Dictionary, pattern: String) -> String:
	if pattern == "alberti" and not alberti_available(event):
		return ALBERTI_FALLBACK
	if pattern in ["bass_chord", "alberti"]:
		var bass: int = attacks(event, pattern)[0].pitches[0]
		var name := Chord.bass_name(event, bass)
		if pattern == "bass_chord" and event.duration_beats == 1:
			return "Одна доля: звучит только бас %s." % name
		if bass != int(event.sounding_pitches.min()):
			return HINTS[pattern] + " Нижний звук исполнения — %s." % name
	return HINTS[pattern]


static func alberti_available(event: Dictionary) -> bool:
	var pitches: Array = event.sounding_pitches
	if pitches.size() != 3:
		return false
	if event.chord.kind == "catalog":
		return event.bass_midi == null or Chord.has_tone(event.chord, int(event.bass_midi))
	var classes := []
	for pitch: int in pitches:
		classes.append(pitch % 12)
	classes.sort()
	for root: int in classes:
		for intervals: Array in Chord.INTERVALS.values():
			var expected := []
			for interval: int in intervals:
				expected.append((root + interval) % 12)
			expected.sort()
			if expected == classes:
				return true
	return false


# One entry per attack with a zero-based eighth-note offset.
static func attacks(event: Dictionary, pattern: String) -> Array[Dictionary]:
	var exact: Array = event.sounding_pitches
	var pitches := exact.duplicate()
	pitches.sort()
	var count := int(event.duration_beats)
	var result: Array[Dictionary] = []
	match pattern:
		"repeated":
			for beat in range(count):
				result.append({"offset": beat * SUBDIVISIONS, "pitches": exact})
		"broken":
			var cycle := pitches.size() * 2 - 2
			for eighth in range(count * SUBDIVISIONS):
				var step := eighth % cycle
				result.append({"offset": eighth, "pitches": [pitches[mini(step, cycle - step)]]})
		"bass_chord":
			var bass := int(pitches[0])
			var accompaniment := exact.duplicate()
			if event.bass_midi != null:
				accompaniment.erase(bass)
			else:
				# Lower the selected voicing's bass an octave where the piano allows it.
				if bass - 12 >= Chord.Audio.FREE_LOWEST:
					bass -= 12
			for beat in range(count):
				result.append({"offset": beat * SUBDIVISIONS, "pitches": [bass] if beat % 2 == 0 else accompaniment})
		"alberti":
			if alberti_available(event):
				# Transpose the whole figure together, keeping the inversion and spacing.
				var shift := 0
				if event.chord.kind == "catalog" and event.bass_midi == null and pitches[0] >= Chord.Audio.C4:
					shift = 12
				var order := [0, 2, 1, 2]
				for eighth in range(count * SUBDIVISIONS):
					result.append({"offset": eighth, "pitches": [int(pitches[order[eighth % 4]]) - shift]})
			else:
				result.append({"offset": 0, "pitches": exact})
		_:
			result.append({"offset": 0, "pitches": exact})
	return result
