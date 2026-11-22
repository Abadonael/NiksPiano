extends RefCounted

const Model := preload("res://scripts/harmony_composition.gd")
const Chord := preload("res://scripts/harmony_chords.gd")

# Each chord specifies its root, quality and beats, with optional voicing settings.
const ENTRIES := [
	{"title": "Тоника и доминанта", "key_label": "До мажор", "key": "C major", "roman": "I–V–I",
		"bpm": 84, "pattern": "attack",
		"harmony": [["C", "major", 4], ["G", "major", 4], ["C", "major", 4]],
		"explanation": "C — тоника, G — доминанта. Доминанта создаёт ожидание возвращения к тонике.",
		"listen": "Прислушайтесь к тому, как последний C завершает фразу."},
	{"title": "Три гармонические функции", "key_label": "До мажор", "key": "C major", "roman": "I–IV–V–I",
		"bpm": 88, "pattern": "repeated",
		"harmony": [["C", "major", 4], ["F", "major", 4], ["G", "major", 4], ["C", "major", 4]],
		"explanation": "В этой последовательности C — тоника, F — субдоминанта, G — доминанта.",
		"listen": "Прислушайтесь к переходам C → F и G → C. Как возвращается начальный аккорд?"},
	{"title": "Четыре аккорда в мажоре", "key_label": "До мажор", "key": "C major", "roman": "I–V–vi–IV",
		"bpm": 96, "pattern": "attack",
		"harmony": [["C", "major", 4], ["G", "major", 4], ["A", "minor", 4], ["F", "major", 4]],
		"explanation": "Мажорные C, G и F и минорный Am используют ноты до мажора.",
		"listen": "Прислушайтесь к переходу с G на Am. После доминанты звучит минорный аккорд шестой ступени."},
	{"title": "Каденция в миноре", "key_label": "Ля минор", "key": "A minor", "roman": "i–iv–V–i",
		"bpm": 76, "pattern": "bass_chord",
		"harmony": [["A", "minor", 4], ["D", "minor", 4], ["E", "major", 4], ["A", "minor", 4]],
		"explanation": "В мажорной доминанте E звучит соль-диез, повышенная VII ступень ля минора.",
		"listen": "Услышьте, как соль-диез тяготеет к ля в заключительном Am."},
	{"title": "Плавное движение баса", "key_label": "До мажор", "key": "C major", "roman": "I–V⁶–vi–IV",
		"comparison_roman": "I–V–vi–IV", "comparison": "Соль в басу",
		"compare_listen": "Во втором такте меняется только бас: си в версии А, соль в версии Б. Верхние звуки аккорда G те же.", "bpm": 80, "pattern": "bass_chord",
		"harmony": [["C", "major", 4], ["G", "major", 4, {"bass_midi": 47, "bass_spelling": "B", "keep_upper": true}],
			["A", "minor", 4, {"octave_shift": -12}], ["F", "major", 4]],
		"explanation": "G/B — соль мажор с си в басу. Первые три басовые ноты идут вниз: до, си, ля.",
		"listen": "Обратите внимание, как бас спускается по ступеням: до → си → ля."},
	{"title": "Мажорная и минорная окраска", "key_label": "До мажор", "key": "C major", "roman": "I–IV–iv–I",
		"comparison_roman": "I–IV–IV–I", "comparison": "Фа мажор в третьем такте",
		"compare_listen": "В третьем такте у Fm звучит ля-бемоль, а у F — ля. Остальные звуки совпадают.",
		"comparison_qualities": {2: "major"}, "bpm": 78, "pattern": "attack",
		"harmony": [["C", "major", 4], ["F", "major", 4], ["F", "minor", 4], ["C", "major", 4]],
		"explanation": "Fm заимствован из параллельного до минора. В до мажоре IV ступень обычно звучит как F.",
		"listen": "При переходе от F к Fm ля понижается на полутон до ля-бемоля."},
	{"title": "Два способа исполнения", "key_label": "Фа мажор", "key": "F major", "roman": "I–V–vi–IV",
		"comparison": "Перебор восьмыми", "comparison_pattern": "broken", "bpm": 90, "pattern": "attack",
		"compare_listen": "Аккорды, темп и длительность совпадают. Сравните одновременные удары с движением отдельных нот.",
		"harmony": [["F", "major", 4], ["C", "major", 4], ["D", "minor", 4], ["Bb", "major", 4]],
		"explanation": "В обеих версиях звучат F, C, Dm и B♭ с одинаковыми длительностями.",
		"listen": "Сравните одновременные удары и перебор восьмыми. Проследите, где начинаются новые аккорды."},
]


static func arrangement(index: int, comparison := false) -> Dictionary:
	var entry: Dictionary = ENTRIES[index]
	var roman: String = entry.get("comparison_roman", entry.roman) if comparison else entry.roman
	var project := Model.create(roman + " · " + entry.title)
	project.key_context = entry.key
	project.bpm = entry.bpm
	project.default_pattern = entry.get("comparison_pattern", entry.pattern) if comparison else entry.pattern
	for item: Array in entry.harmony:
		var position: int = project.events.size()
		var quality: String = entry.get("comparison_qualities", {}).get(position, item[1]) if comparison else item[1]
		var definition := Chord.catalog(item[0], quality)
		var voicing: Dictionary = item[3] if item.size() == 4 else {}
		var shift: int = voicing.get("octave_shift", 0)
		if shift != 0:
			for note in range(definition.pitches.size()):
				definition.pitches[note] += shift
		# Fix the upper G triad in both bass variants, including the intentionally doubled B.
		if voicing.get("keep_upper", false):
			definition = Chord.custom(Chord.title(definition), definition.pitches)
		Model.insert(project, position, definition, item[2])
		if voicing.has("bass_midi") and not comparison:
			Model.set_voicing(project.events[position], definition, voicing.bass_midi, voicing.bass_spelling)
	return project


static func progression(project: Dictionary) -> String:
	var labels := PackedStringArray()
	for event: Dictionary in project.events:
		labels.append(Chord.event_title(event))
	return " → ".join(labels)
