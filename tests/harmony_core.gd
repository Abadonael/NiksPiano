extends RefCounted

const Model := preload("res://scripts/harmony_composition.gd")
const Chord := preload("res://scripts/harmony_chords.gd")
const Store := preload("res://scripts/harmony_store.gd")
const Clock := preload("res://scripts/harmony_transport.gd")
const Patterns := preload("res://scripts/harmony_patterns.gd")
const Examples := preload("res://scripts/harmony_examples.gd")
const Theory := preload("res://scripts/key_theory.gd")
const Staff := preload("res://scripts/harmony_staff.gd")
const EXAMPLE_ID := "00000000000000000000000000000001"


func run(suite: SceneTree, folder: String) -> void:
	_check_spelling(suite)
	_check_root_picker(suite, folder)
	_check_timeline(suite)
	_check_accompaniment(suite)
	_check_voicings(suite)
	_check_bass_selection(suite, folder)
	_check_examples(suite)
	_check_storage(suite, folder)
	_check_version_two(suite, folder)


static func example_fixture() -> Dictionary:
	var project := Examples.arrangement(6)
	project.id = EXAMPLE_ID
	project.title = "Пример — четыре аккорда"
	project.repeat = 2
	return project


static func refined_document() -> Dictionary:
	return {"format": Model.FORMAT, "schema_version": 1, "id": "a0486ca842eb4d8899ca088d489529ed",
		"title": "Последовательность из 0.7.0 UX", "created_at": 1795305600, "modified_at": 1795305610,
		"bpm": 92, "time_signature": [4, 4], "repeat": 2, "key_context": "F major", "events": [
			{"id": "216be5b486ce4e74a6f1ba1cc5d2c9b1", "chord": Chord.catalog("F", "major"),
				"start_beat": 0, "duration_beats": 1, "pattern": "attack", "voicing": null, "bass_midi": null},
			{"id": "54c9483e2c9e49dfab96df50188024b4", "chord": Chord.catalog("C", "major"),
				"start_beat": 1, "duration_beats": 4, "pattern": "attack", "voicing": null, "bass_midi": null},
			{"id": "aadf9515d1b5417c889ed17d16d0e5d9", "chord": Chord.custom("Мои ноты", [72, 47, 63]),
				"start_beat": 5, "duration_beats": 2, "pattern": "attack", "voicing": null, "bass_midi": null},
		]}


func _check_spelling(suite: SceneTree) -> void:
	var roots := Chord.ROOTS
	var cover := {}
	for root: String in roots:
		for quality: String in Chord.INTERVALS:
			var chord := Chord.catalog(root, quality)
			var pitches: Array = chord.pitches
			var notes := Chord.tone_names(chord)
			suite.expect(Chord.validate(chord) == chord and notes.size() == 3, "valid catalog triad: " + Chord.title(chord))
			cover[pitches[0] % 12 * 4 + Chord.INTERVALS.keys().find(quality)] = true
			for index in range(3):
				var name := notes[index]
				var letter := Chord.LETTERS[(Chord.LETTERS.find(root[0]) + 2 * index) % 7]
				var accidental := name.count("♯") - name.count("♭")
				suite.expect(name[0] == letter and posmod(Chord.Chords.NATURALS[letter] + accidental, 12) == pitches[index] % 12,
					"diatonic spelling reconstructs " + Chord.title(chord) + " tone " + str(index))
	suite.expect(cover.size() == 48, "all twelve pitch classes support four qualities")
	for fixture in [
		["Db", "major", ["D♭", "F", "A♭"]], ["C#", "major", ["C♯", "E♯", "G♯"]],
		["D", "minor", ["D", "F", "A"]], ["Bb", "minor", ["B♭", "D♭", "F"]],
		["B", "diminished", ["B", "D", "F"]], ["A#", "diminished", ["A♯", "C♯", "E"]],
		["Eb", "augmented", ["E♭", "G", "B"]], ["G#", "augmented", ["G♯", "B♯", "D♯♯"]],
	]:
		suite.expect(Array(Chord.tone_names(Chord.catalog(fixture[0], fixture[1]))) == fixture[2], "spelling fixture %s %s" % [fixture[0], fixture[1]])
	for invalid: Variant in [[20, 60], [60, 109], [64, 64], [64, 67.5], [true, 64], ["60", 64], [60], [60, 61, 62, 63, 64, 65, 66]]:
		suite.expect(not Chord.pitches_are_valid(invalid), "reject unsupported piano MIDI pitches %s" % [invalid])
	var custom := Chord.custom("Мой звук", [108, 21, 67, 65, 64, 60])
	suite.expect(Chord.validate(custom) == custom, "preserve custom name, octave and exact MIDI pitches")
	var voiced := Chord.catalog("C", "major")
	voiced.pitches = [67, 72, 76]
	suite.expect(Chord.validate(voiced) == voiced, "catalog reader preserves exact compatible pitches")
	voiced.pitches = [60, 62, 67]
	suite.expect(Chord.validate(voiced).is_empty(), "reject pitches that contradict catalog identity")


func _check_root_picker(suite: SceneTree, folder: String) -> void:
	var staff := Staff.new()
	var project := Model.create("21 написание")
	var seen := {}
	for pitch_class in range(12):
		var spellings := Chord.root_spellings(pitch_class)
		suite.expect(Chord.Chords._root_pitch(spellings[0]) == pitch_class, "each canonical button maps to its pitch class")
		for spelling in spellings:
			seen[spelling] = true
			for quality: String in Chord.INTERVALS:
				var definition := Chord.catalog(spelling, quality)
				var canonical := Chord.catalog(spellings[0], quality)
				staff.show_chord(definition)
				var names := Chord.tone_names(definition)
				for index in range(names.size()):
					names[index] = names[index].replace("♯♯", "𝄪").replace("♭♭", "𝄫")
				suite.expect(definition.pitches == canonical.pitches and staff.written_names(false) == names and
					staff.chord_notes.map(func(note: RefCounted) -> int: return note.midi) == canonical.pitches,
					"exact pitches and diatonic staff for %s %s" % [spelling, quality])
			Model.insert(project, project.events.size(), Chord.catalog(spelling, "major"))
	suite.expect(seen.size() == 21 and Chord.ROOTS.all(func(root: String) -> bool: return seen.has(root)),
		"sorted alternatives cover every supported spelling")
	suite.expect(Chord.written_pitch(68, "F###") == "F𝄪♯4" and Staff.Finish.MUSIC_FONT.has_char(0xE265),
		"the triple-sharp bass name and bundled staff glyph are available")
	var store := Store.new(folder.path_join("roots"))
	suite.expect(store.save(project) == OK and store.load_project(project.id) == project, "all twenty-one root spellings survive a saved round trip")
	for fixture in [
		["C#", "Db", [61, 65, 68], ["C♯4", "E♯4", "G♯4"], ["D♭4", "F4", "A♭4"]],
		["F#", "Gb", [66, 70, 73], ["F♯4", "A♯4", "C♯5"], ["G♭4", "B♭4", "D♭5"]],
		["B", "Cb", [71, 75, 78], ["B4", "D♯5", "F♯5"], ["C♭5", "E♭5", "G♭5"]],
		["C", "B#", [60, 64, 67], ["C4", "E4", "G4"], ["B♯3", "D𝄪4", "F𝄪4"]],
		["E", "Fb", [64, 68, 71], ["E4", "G♯4", "B4"], ["F♭4", "A♭4", "C♭5"]],
		["F", "E#", [65, 69, 72], ["F4", "A4", "C5"], ["E♯4", "G𝄪4", "B♯4"]],
	]:
		for index in range(2):
			var chord := Chord.catalog(fixture[index], "major")
			staff.show_chord(chord)
			suite.expect(chord.pitches == fixture[2] and Array(staff.written_names(true)) == fixture[index + 3],
				"independent MIDI and written-octave fixture for " + fixture[index])
	staff.free()


func _check_accompaniment(suite: SceneTree) -> void:
	var project := Model.create()
	project.bpm = 120
	var tonic := Chord.catalog("C", "major")
	Model.insert(project, 0, tonic, 4)
	var event: Dictionary = project.events[0]
	var block := [60, 64, 67]
	for fixture in [
		["attack", [0], [block]],
		["repeated", [0, 2, 4, 6], [block, block, block, block]],
		["broken", [0, 1, 2, 3, 4, 5, 6, 7], [[60], [64], [67], [64], [60], [64], [67], [64]]],
		["bass_chord", [0, 2, 4, 6], [[48], block, [48], block]],
		["alberti", [0, 1, 2, 3, 4, 5, 6, 7], [[48], [55], [52], [55], [48], [55], [52], [55]]],
	]:
		project.default_pattern = fixture[0]
		var attacks := Patterns.attacks(event, fixture[0])
		suite.expect(attacks.map(func(a: Dictionary) -> int: return a.offset) == fixture[1] and
			attacks.map(func(a: Dictionary) -> Array: return a.pitches) == fixture[2], "four beats use the expected pattern " + fixture[0])
		var clock := Clock.new()
		var origin := 909000
		clock.start(project, origin)
		for eighth in range(8):
			var deadline := origin + Clock.time_at_beat(eighth * 0.5, 120)
			if eighth > 0:
				suite.expect(clock.tick(deadline - 1).is_empty(), "attack waits for its subdivision")
			var attack := clock.tick(deadline)
			var position: int = fixture[1].find(eighth)
			suite.expect(attack.get("attack_pitches", []) == (fixture[2][position] if position >= 0 else []),
				"transport schedules %s at eighth %d" % [fixture[0], eighth])
		suite.expect(clock.tick(origin + 2000000).is_empty() and clock.state == Clock.State.STOPPED, "no attack at the end of event")
		for beats in [1, 2]:
			event.duration_beats = beats
			var short_attacks := Patterns.attacks(event, fixture[0])
			suite.expect(short_attacks.size() == fixture[1].filter(func(offset: int) -> bool: return offset < beats * 2).size() and
				short_attacks.back().offset < beats * 2, "short event truncates %s to %d beats" % [fixture[0], beats])
		event.duration_beats = 4

	project = Model.create()
	project.bpm = 137
	project.repeat = 2
	project.default_pattern = "broken"
	for beats in [1, 4, 2]:
		Model.insert(project, project.events.size(), tonic, beats)
	project.events[1].pattern = "repeated"
	var clock := Clock.new()
	var origin := 705123
	clock.start(project, origin)
	for slot in range(28):
		var at := origin + Clock.time_at_beat(slot * 0.5, 137)
		if slot > 0:
			suite.expect(clock.tick(at - 1).is_empty(), "fractional subdivisions never round down")
		var attack := clock.tick(at)
		var within := slot % 14
		var ought_to_attack := within not in [3, 5, 7, 9]
		suite.expect(not attack.is_empty() == ought_to_attack and clock.pass_index == floori(slot / 14.0) and
			clock.beat == floori(within / 2.0), "override, cross-bar event and partial repeat at slot %d" % slot)
	suite.expect(clock.tick(origin + Clock.time_at_beat(14, 137)).is_empty() and clock.state == Clock.State.STOPPED,
		"repeated patterns preserve exact partial-measure length")

	clock.start(project, origin)
	clock.tick(origin)
	var half := Clock.time_at_beat(0.5, 137)
	clock.pause(origin + half - 20)
	suite.expect(clock.tick(origin + half * 20).is_empty(), "paused subdivision stays silent")
	clock.resume(10000000)
	suite.expect(clock.tick(10000019).is_empty() and clock.tick(10000020).get("attack_pitches") == [64],
		"resume retains the remainder of the eighth-note interval")
	clock.stop()
	suite.expect(clock.tick(20000000).is_empty(), "stopped accompaniment leaves no pending attacks")
	clock.start(project, origin)
	clock.tick(origin)
	clock.pause(origin + half + 5)
	clock.resume(20000000)
	suite.expect(clock.tick(20000000).is_empty(), "pause drops any attack that was due before the pause")
	clock.stop()


func _check_voicings(suite: SceneTree) -> void:
	for root: String in Chord.ROOTS:
		for quality: String in Chord.INTERVALS:
			var chord := Chord.catalog(root, quality)
			var expected: Array = chord.pitches.duplicate()
			for inversion in range(3):
				var voiced := Chord.invert(chord, inversion)
				suite.expect(voiced.pitches == expected and Chord.inversion(voiced, expected[0]) == inversion and
					Chord.validate(voiced) == voiced, "inversion %d for %s" % [inversion, Chord.title(chord)])
				expected.append(int(expected.pop_front()) + 12)
	var chord := Chord.catalog("C", "major")
	var event := {"duration_beats": 2}
	Model.set_voicing(event, Chord.invert(chord, 1))
	var alberti := Patterns.attacks(event, "alberti")
	suite.expect(event.sounding_pitches == [64, 67, 72] and alberti.map(func(a: Dictionary) -> Array: return a.pitches) ==
		[[52], [60], [55], [60]], "Alberti keeps the selected first inversion and spacing")
	Model.set_voicing(event, chord, 52, "E")
	suite.expect(Chord.event_title(event) == "C/E" and event.voicing.inversion == 1 and event.voicing.base_inversion == 0 and
		event.sounding_pitches == [52, 60, 67], "C/E moves E to the bass without accidental doubling")
	suite.expect(Patterns.attacks(event, "bass_chord") == [{"offset": 0, "pitches": [52]}, {"offset": 2, "pitches": [60, 67]}],
		"explicit E3 is the separate bass attack")
	Model.set_voicing(event, chord, 49, "Db")
	suite.expect(Chord.event_title(event) == "C/Db" and event.voicing.inversion == null and
		event.sounding_pitches == [49, 60, 64, 67] and Chord.written_pitch(49, "Db") == "D♭3",
		"non-chord slash bass retains written spelling and exact pitch")
	suite.expect(not Patterns.alberti_available(event) and Patterns.attacks(event, "alberti") == Patterns.attacks(event, "attack"),
		"non-triadic voicing uses the declared Alberti fallback")
	var custom := Chord.custom("Октавы", [21, 60, 72, 108])
	Model.set_voicing(event, custom)
	suite.expect(event.voicing.inversion == null and event.sounding_pitches == custom.pitches, "custom pitches remain literal")
	custom = Chord.custom("Трезвучие", [60, 64, 67])
	Model.set_voicing(event, custom)
	suite.expect(event.voicing.inversion == null and Patterns.alberti_available(event) and
		Patterns.attacks(event, "alberti").map(func(a: Dictionary) -> Array: return a.pitches) == [[60], [67], [64], [67]],
		"Alberti recognizes a literal custom triad and retains its register")
	suite.expect(Chord.written_pitch(59, "Cb") == "C♭4" and Chord.written_pitch(60, "B#") == "B♯3",
		"written octave follows the letter across the B–C boundary")


func _check_examples(suite: SceneTree) -> void:
	var romans := ["I–V–I", "I–IV–V–I", "I–V–vi–IV", "i–iv–V–i", "I–V⁶–vi–IV", "I–IV–iv–I", "I–V–vi–IV"]
	var progressions := ["C → G → C", "C → F → G → C", "C → G → Am → F", "Am → Dm → E → Am",
		"C → G/B → Am → F", "C → F → Fm → C", "F → C → Dm → Bb"]
	var c_major := Theory.Tonality.new(0, 0)
	var c_minor := Theory.Tonality.new(0, -3, true)
	for index in range(Examples.ENTRIES.size()):
		var project := Examples.arrangement(index)
		var entry: Dictionary = Examples.ENTRIES[index]
		suite.expect(Model.validate(project) == project and entry.roman == romans[index] and
			Examples.progression(project) == progressions[index] and not entry.listen.is_empty(), "example metadata: " + entry.title)
		var key := c_major
		if index == 3:
			key = Theory.Tonality.new(5, 0, true)
		elif index == 6:
			key = Theory.Tonality.new(3, -1)
		for step in range(project.events.size()):
			var event: Dictionary = project.events[step]
			var chord: Dictionary = event.chord
			if index == 4 and step == 1:
				chord = Chord.catalog("G", "major")
				suite.expect(event.chord.pitches == chord.pitches and Chord.title(event.chord) == "G",
					"the bass comparison explicitly keeps all three upper G major tones")
			var context := c_minor if index == 5 and step == 2 else key
			var degree := posmod(Chord.LETTERS.find(chord.root[0]) - context.tonic_letter, 7)
			var scale_form := Theory.ScaleForm.HARMONIC if index == 3 else Theory.ScaleForm.NATURAL
			var expected_roman := context.triad_roman(degree, scale_form) + ("⁶" if index == 4 and step == 1 else "")
			suite.expect(Chord.tone_names(chord) == context.triad_names(degree, scale_form) and
				entry.roman.split("–")[step] == expected_roman, "example tones and numerals: %d/%d" % [index, step])
	suite.expect("соль-диез" in Examples.ENTRIES[3].explanation and "параллельного до минора" in Examples.ENTRIES[5].explanation,
		"minor dominant and borrowed IV explanations match the harmony")
	var smooth := Examples.arrangement(4)
	var bass_line := []
	for event: Dictionary in smooth.events.slice(0, 3):
		bass_line.append(Patterns.attacks(event, smooth.default_pattern)[0].pitches[0])
	suite.expect(bass_line == [48, 47, 45] and Examples.progression(Examples.arrangement(4, true)) == "C → G → Am → F",
		"smooth-bass example descends in the actual sounding register")
	var block := Examples.arrangement(6)
	var broken := Examples.arrangement(6, true)
	suite.expect(Examples.progression(block) == Examples.progression(broken) and block.default_pattern == "attack" and
		broken.default_pattern == "broken" and Model.length_beats(block) == Model.length_beats(broken), "comparison changes only performance")
	for index in [4, 5, 6]:
		var original := Examples.arrangement(index)
		var comparison := Examples.arrangement(index, true)
		suite.expect(Model.validate(comparison) == comparison and original.bpm == comparison.bpm and
			original.time_signature == comparison.time_signature and original.repeat == comparison.repeat and original.key_context == comparison.key_context,
			"comparison keeps tempo, meter, key and repeats")
		var expected_diff := [] if index == 6 else [1 if index == 4 else 2]
		var actual_diff := []
		for step in range(original.events.size()):
			var left: Dictionary = original.events[step]
			var right: Dictionary = comparison.events[step]
			suite.expect(left.start_beat == right.start_beat and left.duration_beats == right.duration_beats, "comparison preserves event timing")
			if left.sounding_pitches != right.sounding_pitches:
				actual_diff.append(step)
		suite.expect(actual_diff == expected_diff, "only the taught chord changes voicing in the comparison")
	var alternate := Examples.arrangement(4, true)
	var left := Patterns.attacks(smooth.events[1], smooth.default_pattern)
	var right := Patterns.attacks(alternate.events[1], alternate.default_pattern)
	suite.expect(smooth.default_pattern == alternate.default_pattern and left[1] == right[1] and left[3] == right[3] and
		left[0].pitches == [47] and right[0].pitches == [55] and left[2].pitches == [47] and right[2].pitches == [55],
		"smooth comparison changes only the bass attacks, retaining exact chord attacks")
	left = Patterns.attacks(Examples.arrangement(5).events[2], "attack")
	right = Patterns.attacks(Examples.arrangement(5, true).events[2], "attack")
	suite.expect(Examples.progression(Examples.arrangement(5, true)) == "C → F → F → C" and
		left[0].pitches == [65, 68, 72] and right[0].pitches == [65, 69, 72], "colour comparison changes only A-flat to A natural")


func _check_bass_selection(suite: SceneTree, folder: String) -> void:
	var staff := Staff.new()
	var project := Model.create("Бас и запись")
	var tonic := Chord.catalog("C", "major")
	Model.insert(project, 0, tonic)
	var event: Dictionary = project.events[0]
	for fixture in [
		[tonic, null, "", "C", 0, [60, 64, 67], ["C4", "E4", "G4"]],
		[Chord.invert(tonic, 1), null, "", "C/E", 1, [64, 67, 72], ["E4", "G4", "C5"]],
		[Chord.invert(tonic, 2), null, "", "C/G", 2, [67, 72, 76], ["G4", "C5", "E5"]],
		[Chord.catalog("G", "major"), 59, "B", "G/B", 1, [59, 67, 74], ["B3", "G4", "D5"]],
		[Chord.catalog("A", "minor"), 60, "C", "Am/C", 1, [60, 69, 76], ["C4", "A4", "E5"]],
		[Chord.catalog("F", "major"), 57, "A", "F/A", 1, [57, 65, 72], ["A3", "F4", "C5"]],
		[tonic, 50, "D", "C/D", null, [50, 60, 64, 67], ["D3", "C4", "E4", "G4"]],
		[tonic, 59, "Cb", "C/Cb", null, [59, 60, 64, 67], ["C♭4", "C4", "E4", "G4"]],
		[Chord.catalog("G#", "augmented"), 52, "D##", "G#aug/D##", 2, [52, 68, 72], ["D𝄪3", "G♯4", "B♯4"]],
	]:
		Model.set_voicing(event, fixture[0], fixture[1], fixture[2])
		staff.show_chord(event.chord, event.sounding_pitches, event.bass_midi, event.bass_spelling)
		suite.expect(Chord.event_title(event) == fixture[3] and event.voicing.inversion == fixture[4] and
			event.sounding_pitches == fixture[5] and Array(staff.written_names(true)) == fixture[6],
			"bass symbol, exact MIDI and written staff agree for " + fixture[3])
		suite.expect(Model.validate(project) == project, "voicing is serializable: " + fixture[3])
	staff.free()
	for pitch_class in range(12):
		var registers := Chord.bass_registers(tonic, pitch_class)
		suite.expect(not registers.is_empty() and registers.all(func(midi: int) -> bool:
			return midi >= Chord.Audio.FREE_LOWEST and midi < 60 and midi % 12 == pitch_class), "playable lower octaves exist for class %d" % pitch_class)
		for spelling in Chord.bass_spellings(tonic, pitch_class):
			suite.expect(Chord.bass_pitch_class(spelling) == pitch_class, "enharmonic spellings retain class: " + spelling)
	suite.expect(Chord.bass_registers(Chord.custom("У края", [21, 22]), 9).is_empty(), "a bass at the piano floor cannot be lowered")
	suite.expect(Chord.bass_pitches(tonic, "C#") == Chord.bass_pitches(tonic, "Db") and
		Chord.bass_pitches(tonic, "B") == Chord.bass_pitches(tonic, "Cb") and
		Chord.bass_pitches(tonic, "F") == Chord.bass_pitches(tonic, "E#"), "enharmonic changes preserve the MIDI register set")
	var store := Store.new(folder.path_join("ux"))
	suite.expect(store.save(project) == OK and store.load_project(project.id) == project,
		"schema 2 preserves literal double accidental through JSON")
	Model.set_voicing(event, tonic, 59, "Cb")
	suite.expect(store.save(project) == OK and store.load_project(project.id) == project,
		"existing C-flat slash data retains exact pitches and spelling")
	var hint := Patterns.event_hint(event, "bass_chord")
	suite.expect(not "Нижний звук исполнения" in hint and Patterns.attacks(event, "bass_chord")[0].pitches == [59],
		"the explicit C-flat is the actual accompaniment bass")
	Model.set_voicing(event, tonic)
	suite.expect("C3" in Patterns.event_hint(event, "bass_chord") and "C3" in Patterns.event_hint(event, "alberti"),
		"the app identifies the generated lower register for both patterns")


func _check_timeline(suite: SceneTree) -> void:
	var empty := Model.create()
	var clock := Clock.new()
	suite.expect(not clock.start(empty, 0) and Model.measures(empty) == 0 and clock.tick(10).is_empty(), "empty project stays stopped")
	var project := Model.create()
	var definition := Chord.catalog("F", "major")
	Model.insert(project, 0, definition, 1)
	Model.insert(project, 1, definition, 4)
	Model.insert(project, 1, Chord.catalog("D", "minor"), 2)
	var events: Array = project.events
	suite.expect(events.map(func(item: Dictionary) -> int: return item.start_beat) == [0, 1, 3], "insertion recalculates positions")
	suite.expect(Model.length_beats(project) == 7 and Model.measures(project) == 2 and Model.measure(6) == 2,
		"a four-beat chord crosses the bar without changing duration")
	var original: Dictionary = events[2]
	suite.expect(Model.move(project, 2, 0) and events[0].id == original.id and events[0].duration_beats == 4 and events[1].start_beat == 4,
		"reorder preserves identity and duration")
	suite.expect(Model.duplicate_event(project, 0) and events[1].id != events[0].id and events[1].chord == events[0].chord,
		"duplicate creates a distinct event")
	Model.remove(project, 0)
	suite.expect(events[0].start_beat == 0 and events.size() == 3, "remove closes the timeline gap")

	project = Model.create()
	project.bpm = 120
	project.repeat = 2
	for duration in [1, 2, 4]:
		Model.insert(project, project.events.size(), definition, duration)
	events = project.events
	suite.expect(Clock.time_at_beat(1, 120) == 500000 and Clock.time_at_beat(2, 120) == 1000000 and Clock.time_at_beat(4, 120) == 2000000,
		"at 120 BPM one, two and four beats are exactly 0.5, 1 and 2 seconds")
	var origin := 752011
	suite.expect(clock.start(project, origin), "nonempty transport starts")
	var starts := [0, 500000, 1500000, 3500000, 4000000, 5000000]
	for index in range(starts.size()):
		var deadline: int = origin + starts[index]
		if index > 0:
			suite.expect(clock.tick(deadline - 1).is_empty(), "event never attacks before deadline %d" % index)
		var event := clock.tick(deadline)
		suite.expect(event.get("id") == events[index % 3].id and clock.tick(deadline).is_empty(),
			"each occurrence of the same chord attacks once, including repeat %d" % index)
	suite.expect(clock.tick(origin + 6999999).is_empty() and clock.state == Clock.State.PLAYING, "last event holds until pass ends")
	suite.expect(clock.tick(origin + 7000000).is_empty() and clock.state == Clock.State.STOPPED, "two passes stop exactly on the end")
	project.repeat = 4
	clock.start(project, origin)
	for pass_index in range(4):
		suite.expect(clock.tick(origin + pass_index * 3500000).get("id") == events[0].id, "four-repeat pass %d" % (pass_index + 1))
	suite.expect(clock.tick(origin + 14000000).is_empty() and clock.state == Clock.State.STOPPED, "four repeats terminate")
	project.repeat = 0
	project.bpm = 137
	clock.start(project, origin)
	suite.expect(clock.tick(origin).get("id") == events[0].id, "loop starts at chosen BPM")
	var first_deadline := Clock.time_at_beat(1, 137)
	suite.expect(clock.tick(origin + first_deadline - 1).is_empty(), "fractional deadline rounds forward")
	suite.expect(clock.tick(origin + first_deadline).get("id") == events[1].id, "new tempo is applied")
	var late_deadline := Clock.time_at_beat(70000, 137)
	suite.expect(clock.tick(origin + late_deadline).get("id") == events[0].id and clock.pass_index == 10000,
		"absolute timing does not accumulate drift and skips stalled events")
	clock.stop()
	suite.expect(clock.tick(origin + late_deadline * 3).is_empty(), "stop disarms the clock")

	project.bpm = 120
	clock.start(project, 100)
	clock.tick(100)
	clock.pause(250100)
	suite.expect(clock.tick(9000000).is_empty() and clock.state == Clock.State.PAUSED, "pause blocks pending attacks")
	clock.resume(9000000)
	suite.expect(clock.tick(9000000).is_empty() and clock.tick(9249999).is_empty(),
		"resume does not retrigger held chord and keeps remaining time")
	suite.expect(clock.tick(9250000).get("id") == events[1].id, "resume produces the next attack at the correct position")


func _check_storage(suite: SceneTree, folder: String) -> void:
	var store := Store.new(folder)
	var example := example_fixture()
	var id: String = example.id
	var path := folder.path_join(id + Store.SUFFIX)
	suite.expect(store.save(example) == OK and store.load_project(id) == example, "save and load example exactly")
	example.title = "Переименованный пример"
	example.bpm = 120
	suite.expect(store.save(example) == OK and store.load_project(id) == example, "rename keeps ID and updates primary")
	var copy := Model.copy_project(example, "Новая копия")
	suite.expect(copy.id != id and store.save(copy) == OK and store.library().projects.size() == 2, "multiple projects and duplicate remain separate")
	suite.expect(store.remember(id) == OK and store.remember(copy.id) == OK and store.last_id() == copy.id,
		"continue points to the last opened project, including replacement")

	suite.expect(DirAccess.rename_absolute(path, path + ".tmp") == OK, "simulate interruption before temporary is promoted")
	suite.expect(store.load_project(id) == example, "verified temporary is recovered when primary is missing")
	suite.expect(store.save(example) == OK, "recover temporary and replace safely")
	_write_fixture(path, "{ broken")
	suite.expect(not store.load_project(id).is_empty(), "recover valid backup when primary is corrupt")
	suite.expect(store.save(example) == OK and store.load_project(id) == example, "save after recovery")
	var archived := false
	for filename in DirAccess.get_files_at(folder):
		if filename.begins_with(id + Store.SUFFIX + ".corrupt-"):
			archived = FileAccess.get_file_as_string(folder.path_join(filename)) == "{ broken"
	suite.expect(archived, "corrupt primary remains available for recovery")
	_write_fixture(path + ".tmp", "{ interrupted")
	suite.expect(store.load_project(id) == example and store.save(example) == OK, "partial pending write leaves valid primary intact")

	var file := folder.path_join("round-trip" + Store.SUFFIX)
	Model.insert(example, 2, Chord.custom("Точный набор", [21, 39, 58, 108]), 1)
	suite.expect(Store.export_project(file, example) == OK and Store.read_document(file).project == example, "export is written and read back exactly")
	var collision := store.import_project(file)
	suite.expect(collision.error == OK and collision.project.id != id and store.load_project(id).events.size() == 4,
		"import collision creates a separate project and keeps the original")
	suite.expect(store.delete_project(id) == OK and store.load_project(id).is_empty(), "delete removes every valid recovery candidate")
	var imported := store.import_project(file)
	suite.expect(imported.error == OK and imported.project.id != collision.project.id and imported.project.events == example.events and
		imported.project.bpm == example.bpm and imported.project.repeat == example.repeat and imported.project.key_context == "F major",
		"export, delete and import reconstruct equivalent musical content")
	_write_fixture(file, "{ bad")
	suite.expect(store.import_project(file).error == ERR_FILE_CORRUPT, "corrupted JSON fails gracefully")
	var unsupported := example.duplicate(true)
	unsupported.schema_version = Model.SCHEMA + 1
	_write_fixture(file, JSON.stringify(unsupported))
	suite.expect(store.import_project(file).error == ERR_UNAVAILABLE, "unsupported schema is rejected")
	_write_fixture(file, "x".repeat(Store.MAX_BYTES + 1))
	suite.expect(store.import_project(file).error == ERR_INVALID_DATA, "oversized documents fail before parsing")
	for field: String in ["bpm", "repeat", "id", "time_signature"]:
		var invalid := example.duplicate(true)
		invalid[field] = {"bpm": 201, "repeat": 3, "id": "../escape", "time_signature": [3, 4]}[field]
		suite.expect(Model.validate(invalid).is_empty(), "reject invalid project field " + field)
	for field: String in ["duration_beats", "start_beat", "pattern", "bass_midi", "voicing"]:
		var invalid := example.duplicate(true)
		invalid.events[0][field] = {"duration_beats": 3, "start_beat": 1, "pattern": "arp", "bass_midi": 36, "voicing": {}}[field]
		suite.expect(Model.validate(invalid).is_empty(), "reject unsupported event field " + field)
	var invalid := example.duplicate(true)
	invalid.events[1].id = invalid.events[0].id
	suite.expect(Model.validate(invalid).is_empty(), "reject duplicate event IDs")
	invalid = example.duplicate(true)
	invalid.events.resize(Model.MAX_EVENTS + 1)
	suite.expect(Model.validate(invalid).is_empty(), "reject more than 512 events")
	_check_original_document(suite, store, folder)


func _check_original_document(suite: SceneTree, store: Store, folder: String) -> void:
	var id := "a21273592b1d4c8dbbc2aa500920076a"
	var path := folder.path_join(id + Store.SUFFIX)
	var source := """
	{"format":"nikspiano-composition","schema_version":1,"id":"a21273592b1d4c8dbbc2aa500920076a",
	"title":"Из 0.7.0","created_at":1795305600,"modified_at":1795305620,"bpm":83,
	"time_signature":[4,4],"repeat":4,"key_context":"","events":[
		{"id":"216be5b486ce4e74a6f1ba1cc5d2c9b1","chord":{"kind":"catalog","root":"C","quality":"major",
		"pitches":[67,72,76]},"start_beat":0,"duration_beats":4,"voicing":null,"bass_midi":null,"pattern":"attack"},
		{"id":"54c9483e2c9e49dfab96df50188024b4","chord":{"kind":"custom","name":"Мои ноты",
		"pitches":[21,61,108]},"start_beat":4,"duration_beats":2,"voicing":null,"bass_midi":null,"pattern":"attack"}]}
	"""
	_write_fixture(path, source)
	var project := store.load_project(id)
	suite.expect(not project.is_empty() and project.id == id and project.created_at == 1795305600 and
		project.modified_at == 1795305620 and project.bpm == 83 and project.repeat == 4 and
		project.events[0].chord.pitches == [67, 72, 76] and project.events[1].chord.pitches == [21, 61, 108],
		"original 0.7.0 schema opens with the same IDs, metadata and voiced MIDI")
	suite.expect(FileAccess.get_file_as_string(path) == source, "reading original 0.7.0 does not rewrite it")
	var imported := store.import_project(path)
	suite.expect(imported.error == OK and imported.project.id != id and imported.project.events == project.events,
		"original 0.7.0 imports with identical event IDs, order, durations and MIDI")


func _check_version_two(suite: SceneTree, folder: String) -> void:
	var store := Store.new(folder)
	var path := folder.path_join("refined-070.nikspiano.json")
	var refined := refined_document()
	_write_fixture(path, JSON.stringify(refined))
	var imported := store.import_project(path)
	var project: Dictionary = imported.project
	suite.expect(imported.error == OK and project.schema_version == Model.SCHEMA and project.default_pattern == Patterns.BLOCK and
		project.id != refined.id and project.events[2].sounding_pitches == [72, 47, 63] and Model.length_beats(project) == 7,
		"refined 0.7.0 imports as exact block voicings with its partial measure")
	var clock := Clock.new()
	clock.start(project, 0)
	for event: Dictionary in project.events:
		var time := Clock.time_at_beat(event.start_beat, project.bpm)
		suite.expect(clock.tick(time).get("attack_pitches") == event.sounding_pitches and clock.tick(time + 100).is_empty(),
			"migrated chords keep a single attack and exact MIDI")
	var event: Dictionary = project.events[0]
	Model.set_voicing(event, Chord.invert(event.chord, 1), 53, "F")
	event.pattern = "bass_chord"
	var custom: Dictionary = project.events[2]
	Model.set_voicing(custom, Chord.custom("Две октавы", [36, 48, 59, 60, 73, 108]), 25, "Db")
	project.default_pattern = "broken"
	path = folder.path_join("voicings-v2.nikspiano.json")
	suite.expect(store.save(project) == OK and store.load_project(project.id) == project, "reopen exact custom and slash voicings")
	suite.expect(Store.export_project(path, project) == OK and Store.read_document(path).project == project,
		"schema 2 exports and reimports both inversion fields, spelling, bass MIDI and override")
	var copy := store.import_project(path)
	suite.expect(copy.error == OK and copy.project.id != project.id and copy.project.events == project.events and
		copy.project.default_pattern == "broken", "round trip keeps the pattern inheritance and exact notes")
	for invalid_fields: Dictionary in [{"bass_spelling": "G"}, {"bass_midi": 92}, {"sounding_pitches": [53, 69, 72, 77]},
			{"voicing": {"base_inversion": 1, "inversion": 2}}, {"pattern": "bogus"}]:
		var bad := project.duplicate(true)
		bad.events[0].merge(invalid_fields, true)
		suite.expect(Model.validate(bad).is_empty(), "reject contradictory voicing or unknown override: " + str(invalid_fields))
	var bad := project.duplicate(true)
	bad.default_pattern = "bogus"
	suite.expect(Model.validate(bad).is_empty(), "reject unknown composition default")


func _write_fixture(path: String, source: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source)
	file.close()
