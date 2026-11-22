# Nik's Piano

Nik's Piano 0.7.2 is an offline piano, music trainer, and chord progression editor built with Godot 4.7.2 and GDScript. It uses the Compatibility renderer, with portrait note training, Circle of Fifths, and Harmony Lab, and landscape piano practice.

## Run on Windows

In the Godot 4.7.2 Project Manager, import `project.godot` from your checkout. Open the project and press **F5**. Choose a practice mode, set its options, and press **Начать**. Circle of Fifths, Harmony Lab, and Free Piano open from their cards.

You can also run the game directly from PowerShell after the initial resource import.

```powershell
$godot = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
& $godot --path .
```

## Practice modes

**Свободная клавиатура** opens an 88-key piano from A0 to C8. It starts near middle C with the viewport locked for immediate multi-touch playing. Slide a finger across the keys to play a glissando. The bottom of the keyboard plays white keys, while the upper area also plays the black keys you cross. Unlock it to swipe the keyboard, tap or drag the mini-map, or resize the keys with − and +. The app remembers the lock, zoom, and viewport position.

**По нотному стану** uses the checked treble and bass ranges. **По названию** uses Russian solfege or letter names. Each shuffled cycle presents every active note once, with a different piano key on each consecutive question. The menu remembers its choices in `.piano_settings.cfg` in the Windows project folder.

**Аккорды** lets you practice 24 major and minor triads grouped by the number of black keys. Play each chord's three notes in any order across either octave. The next chord appears automatically. The menu button restores portrait orientation.

**Мелодии** offers **Арпеджио**, **Музыкальные фразы**, and **Гармонические интервалы**. Choose a difficulty and either treble (C4–B5) or bass (C2–B3). Arpeggios and phrases have a separate length choice of 4, 8, 12, 16, or 24 notes. The menu remembers all four choices, including length while it is hidden for intervals.

Read each complete measure and play the written pitches in order. Longer exercises turn pages automatically. The score uses 4/4 with quarter, half, and flagged eighth notes and quarter and half rests. Play at your own pace. Intervals succeed when both written keys are held together and briefly show their Russian name. The active target is amber, completed notes are green, and a wrong key sounds and briefly flashes red.

**Квинтовый круг** lets you select major keys on the outer ring and relative minor keys on the inner ring. Compare neighboring keys on either ring to see six shared pitches and the one pitch that changes. From a minor key you can also compare its natural scale with the relative major and see how the same seven pitches work around a different tonic. The shared F♯/G♭ and D♯m/E♭m sector lets you switch notation. The app remembers the sector, ring and spelling.

From a selected key, **Сыграть гамму** opens an ascending and descending scale with an optional **Слушать** preview. In minor, switch from **Натуральный** to **Гармонический** to see and hear the raised seventh in both directions under the same key signature. **Сыграть аккорды** opens I–IV–V–I in major or i–iv–V–i in minor. Play each chord's three written pitches in any order to hear the root-position chord played together. Both exercises use C4–B5 and can be repeated at your own pace. **Все трезвучия** shows the natural- and harmonic-minor collections separately.

The speaker button in the main menu remembers whether sound is enabled. The note modes play the written octave in staff mode and octave 4 in name mode. In chord practice, repeated keys still sound. Playing the same pitch class in the other octave briefly highlights that key without adding to the chord. The final key gets 260 ms to ring. The key voices then release over 350 ms with gradually applied damping and a short taper to silence. After at least 350 ms of silence, a simultaneous root-position triad rooted in octave 4 plays for 1.25 seconds, including a 250 ms fade. Muted chord practice advances after 0.4 seconds.

## Harmony Lab

Choose **Гармоническая лаборатория** and press **СТАРТ**. Create a composition, reopen one from the library, or browse **Примеры** for seven short listening exercises. Play an example from its detail screen or use **Открыть копию** to save an editable arrangement. **Сравнить звучание** plays the two variants of the bass-motion, major/minor colour, and accompaniment lessons. Each pair uses the same tempo and chord durations.

The editor remembers your choice between **По тактам** and **Список**. Tap a chord to hear its voicing together. Hold and drag any part of a chord, including its continuation across a bar line, to move the event. Tap the pencil to edit the voicing. **Аккорд** plays the written notes once. **С аккомпанементом** uses the displayed effective pattern and event duration. The editor shows whether that pattern comes from the project or the individual event.

The staff shows the actual voicing and adds a bass staff for low pitches when upper notes are present. The chord symbol reflects the sounding inversion. For example, second-inversion C major is **C/G**. Open **Бас** to follow the voicing or select a pitch class, a playable lower octave, and an optional enharmonic spelling. The **⋯** menu contains replacement, insertion, duplication, and confirmed deletion. **Отменить** restores the previous edit.

The picker offers major, minor, diminished, and augmented triads on a twelve-note grid. **Другое написание** offers the alternate spellings of the selected pitch class, such as C♯ and D♭. Tap the staff card, or tap the current root or chord quality again, to hear the selected voicing. **Свой аккорд** lets you name and select two to six exact piano pitches from A0 to C8. A catalog chord tone chosen as a slash bass moves to the lower register. The pitches selected for a custom chord are kept as entered.

The performance selector sets the composition default. Chord events occupy one, two, or four beats in 4/4. Tempo ranges from 40 to 200 BPM. Each of the one, two, or four passes ends at the exact composition boundary, including a partial final measure. Loop playback starts the next pass at that same boundary.

| Performance | Attacks within each event |
| --- | --- |
| Одновременно | One block attack at the start. |
| Удары по долям | The complete voicing on every beat. |
| Перебор | The voicing ascending and descending in eighth notes. |
| Бас + аккорд | Bass on odd beats and accompaniment on even beats. An explicit bass keeps its register. Otherwise the lowest voicing note moves down an octave when available. |
| Бас Альберти | Low–high–middle–high in eighth notes, using the selected spacing and inversion. Catalog triads without a separate bass move down an octave when their lowest note is at or above C4. Other voicings that lack three distinct triad tones display a message and sound as a block. |

The app saves to `user://compositions/` after a short delay and flushes pending edits when leaving the editor or backgrounding. It verifies a temporary file before replacing the saved file, keeps a backup, and preserves damaged files that it encounters during replacement. **Проект** contains manual save, rename, duplication, export, and confirmed deletion. **Импорт** in the library creates a separate local composition.

### Composition file format

The interchange extension is `.nikspiano.json`. The reader accepts up to 512 KiB of UTF-8 JSON and 512 events per composition. This example shows one event with its chord definition embedded.

```json
{
  "format": "nikspiano-composition",
  "schema_version": 2,
  "id": "2a620e886a5b488b92d0289de87ed401",
  "title": "One chord",
  "created_at": 1795305600,
  "modified_at": 1795305600,
  "bpm": 90,
  "time_signature": [4, 4],
  "repeat": 2,
  "key_context": "F major",
  "default_pattern": "broken",
  "events": [
    {
      "id": "7aa5899028854a44af3f05ce3374d36a",
      "chord": {
        "kind": "catalog",
        "root": "F",
        "quality": "major",
        "pitches": [65, 69, 72]
      },
      "start_beat": 0,
      "duration_beats": 4,
      "voicing": {"base_inversion": 0, "inversion": 1},
      "bass_midi": 57,
      "bass_spelling": "A",
      "sounding_pitches": [57, 65, 72],
      "pattern": null
    }
  ]
}
```

- Composition and event IDs use 32 lowercase hexadecimal digits. Event IDs are unique within a composition. Timestamps are Unix seconds in UTC. Titles have 1–80 characters and optional `key_context` has up to 48 characters.
- `bpm` is an integer from 40 to 200. The time signature is `[4, 4]`. `repeat` is `1`, `2`, `4`, or `0` for continuous looping.
- The ordered `events` start at beat zero. Each `start_beat` equals the sum of preceding `duration_beats`, with allowed durations of 1, 2, and 4. The supported patterns are `attack`, `repeated`, `broken`, `bass_chord`, and `alberti`. A null event pattern inherits `default_pattern`.
- `voicing.base_inversion` describes the selected catalog voicing and `voicing.inversion` describes the actual bass of the resulting catalog chord. Use null for custom chords and for the actual inversion when the explicit bass is outside the triad. `bass_midi` is null with an empty `bass_spelling` for automatic bass, or the exact lower MIDI pitch with its ASCII spelling. `sounding_pitches` records the complete voicing used for block playback and quick audition.
- Catalog definitions use a letter root with an optional ASCII `b` or `#`, one of `major`, `minor`, `diminished`, and `augmented`, and three exact MIDI pitches that match the triad. A custom definition uses `"kind": "custom"`, a name of 1–48 characters, and two to six exact MIDI pitches. All pitches are unique integers from 21 to 108.
- Schema 1 documents migrate in memory to block playback with the same saved pitches, timing, and IDs. The existing file updates when the composition is saved.
- Import assigns a new composition ID and timestamps. It preserves event IDs, musical settings, spellings, durations, and sounding pitches.

Android uses the Storage Access Framework. Choose a local destination such as Downloads and reopen the exported file through **Импорт**. Godot 4.7.2 passes the selected document URI directly to `FileAccess`. If the system picker or a provider fails, the app reports the error and keeps the local project. The APK requires no broad storage access.

## Project structure and credits

- `project.godot`, `main.tscn`, and `free_piano.tscn` define the project and entry scenes.
- `scripts/` contains the trainers, piano, audio, and settings code. `assets/` contains the samples, font, shader, and icons. `default_bus_layout.tres` defines the audio buses.
- `tests/` contains the regression suite, `tools/` contains the sample preparation script, and `design_refs/` contains the approved UI references. Godot excludes the tests and references from the exported app.

The acoustic recordings are adapted from [Salamander Grand Piano V3](https://github.com/sfzinstruments/SalamanderGrandPiano) by Alexander Holm, under [CC BY 3.0 Unported](assets/piano/LICENSE.txt). See the [full attribution](assets/piano/ATTRIBUTION.txt). Each of the 88 keys uses one of 30 recordings within one nominal semitone, with fine tuning based on the recorded pitch. The WAV files are included. To regenerate them from the pinned source with Python and FFmpeg, run `python tools/prepare_piano.py`. Pass `--extended-only` to rebuild only the 13 added recordings. Source downloads are cached in the ignored `.godot/checks/piano-source/` directory.

The [Bravura music font](https://github.com/steinbergmedia/bravura) is bundled under the [SIL Open Font License 1.1](assets/Bravura-LICENSE.txt). The information button in the menu opens the offline credits. Android exports include the original [Godot license](assets/Godot-LICENSE.txt) and [copyright notices](assets/Godot-COPYRIGHT.txt) from the engine revision used for 0.5.1.

## Build and install the Android debug APK

The debug build supports ARM64 phones with OpenGL ES 3.0 running Android 7.0 (API 24) or newer.

Install the Android export templates matching Godot 4.7.2, OpenJDK 17, and the Android SDK. Set the JDK and SDK paths in **Editor Settings → Export → Android** and configure a local debug keystore if needed. See [Godot's Android export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html). Run from the checkout root in PowerShell.

```powershell
$godot = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
New-Item -ItemType Directory -Force -Path builds/android | Out-Null
& $godot --headless --editor --import --path .
& $godot --headless --path . --export-debug Android builds/android/NiksPiano-0.7.2-workspace-debug.apk
```

Copy the resulting APK to the phone and open it in the file manager. If prompted, allow installation from that file manager, then tap **Install**. Open **Nik's Piano** from the launcher.

## Run regression checks

For 0.5.1, a fresh Windows import and startup check passed. The smoke suite reported zero failures headlessly and at 320×640, 405×720, and 405×900, including mixed-audio checks in the graphical runs.

Run these commands from the project directory in PowerShell. The smoke script covers the practice modes, seeded music-theory checks, held-key input, pagination, settings, and Free Piano. Graphical runs also test mixed audio and save a stereo WAV of the chord transition under `.godot/checks/smoke/0.7.2/`. The 405×900 run exports written exercises to `builds/0.7.2-exercise-examples.md` and captures landscape exercise screenshots.

```powershell
$godot = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --editor --import --path .
& $godot --headless --path . --quit-after 10
& $godot --headless --path . --script tests/workspace_smoke.gd
foreach ($size in '320x640', '360x732', '360x800', '405x720', '405x900', '800x1060') {
    & $godot --path . --resolution $size --script tests/workspace_smoke.gd
}
& $godot --headless --path . --script tests/smoke.gd
& $godot --path . --resolution 320x640 --script tests/smoke.gd
& $godot --path . --resolution 405x720 --script tests/smoke.gd
& $godot --path . --resolution 405x900 --script tests/smoke.gd
& $godot --headless --path . --script tests/circle_smoke.gd
& $godot --path . --resolution 320x640 --script tests/circle_smoke.gd
& $godot --path . --resolution 405x720 --script tests/circle_smoke.gd
& $godot --path . --resolution 405x900 --script tests/circle_smoke.gd
& $godot --headless --path . --script tests/harmony_smoke.gd
& $godot --path . --resolution 320x640 --script tests/harmony_smoke.gd
& $godot --path . --resolution 405x720 --script tests/harmony_smoke.gd
& $godot --path . --resolution 405x900 --script tests/harmony_smoke.gd
& $godot --path . --resolution 720x405 --script tests/harmony_smoke.gd
& $godot --path . --resolution 1280x800 --script tests/harmony_smoke.gd
& $godot --path . --resolution 800x1060 --script tests/harmony_smoke.gd
```

Workspace checks cover the seven modules, practice settings, Back navigation, portrait and landscape changes, and responsive layout. The 360×732 window models the usable portrait area of the tested display configuration reported by a Samsung S23. Workspace captures go to `builds/screenshots/0.7.2-workspace/`.

Circle checks cover every written major and minor key, both enharmonic spellings, minor scales and triads, accidental cancellation, key comparisons, touch on both rings, settings, navigation, and both exercises.

Harmony Lab checks cover root selection, enharmonic spelling, staff-card auditions, voicings and both clefs, both sequence views, effective pattern inheritance, deterministic accompaniment timing, A/B playback and example copies, touch gestures, project recovery, and schema 1 and 2 import and export. The interchange test exercises the system picker callback with a Windows path. The actual Android picker is part of on-device testing. The Melodies, Circle, and Harmony Lab regression captures go to `builds/screenshots/0.7.2-regression/`.

## Known limitations

The interface is in Russian. Harmony Lab supports one ordered chord sequence per composition in fixed 4/4. The editor exposes the composition-wide performance style. An event override supplied in a valid file is preserved and played.
