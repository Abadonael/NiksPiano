# Niks Piano

Niks Piano 0.5.1 is an offline piano and music trainer built with Godot 4.7.2 and GDScript. It uses the Compatibility renderer, with portrait note training and landscape Free Piano, chord, and melody modes.

## Run on Windows

In the Godot 4.7.2 Project Manager, import `project.godot` from your checkout. Open the project and press **F5**. Choose a mode and press **СТАРТ**.

You can also run the game directly from PowerShell after the initial resource import.

```powershell
$godot = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
& $godot --path .
```

## Practice modes

**Свободная клавиатура** opens an 88-key piano from A0 to C8. It starts near middle C with the viewport locked for immediate multi-touch playing. Unlock it to swipe the keyboard, tap or drag the mini-map, or resize the keys with − and +. The app remembers the lock, zoom, and viewport position.

**По нотному стану** uses the checked treble and bass ranges. **По названию** uses Russian solfege or letter names. Each shuffled cycle presents every active note once, with a different piano key on each consecutive question. The menu remembers its choices in `.piano_settings.cfg` in the Windows project folder.

**Аккорды** lets you practice 24 major and minor triads grouped by the number of black keys. Play each chord's three notes in any order across either octave. The next chord appears automatically. The menu button restores portrait orientation.

**Мелодии** offers **Арпеджио**, **Музыкальные фразы**, and **Гармонические интервалы**. Choose a difficulty and either treble (C4–B5) or bass (C2–B3). Arpeggios and phrases have a separate length choice of 4, 8, 12, 16, or 24 notes. The menu remembers all four choices, including length while it is hidden for intervals.

Read each complete measure and play the written pitches in order. Longer exercises turn pages automatically. The score uses 4/4 with quarter, half, and flagged eighth notes and quarter and half rests. Play at your own pace. Intervals succeed when both written keys are held together and briefly show their Russian name. The active target is amber, completed notes are green, and a wrong key sounds and briefly flashes red.

The speaker button in the upper-right corner of every screen remembers whether sound is enabled. The note modes play the written octave in staff mode and octave 4 in name mode. In chord practice, repeated keys still sound. Playing the same pitch class in the other octave briefly highlights that key without adding to the chord. The final key gets 260 ms to ring. The key voices then release over 350 ms with gradually applied damping and a short taper to silence. After at least 350 ms of silence, a simultaneous root-position triad rooted in octave 4 plays for 1.25 seconds, including a 250 ms fade. Muted chord practice advances after 0.4 seconds.

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
& $godot --headless --path . --export-debug Android builds/android/NiksPiano-0.5.1-debug.apk
```

Copy the resulting APK to the phone and open it in the file manager. If prompted, allow installation from that file manager, then tap **Install**. Open **Niks Piano** from the launcher.

## Run regression checks

For 0.5.1, a fresh Windows import and startup check passed. The smoke suite reported zero failures headlessly and at 320×640, 405×720, and 405×900, including mixed-audio checks in the graphical runs.

Run these commands from the project directory in PowerShell. The smoke script covers the practice modes, seeded music-theory checks, held-key input, pagination, settings, and Free Piano. Graphical runs also test mixed audio and save a stereo WAV of the chord transition under `.godot/checks/smoke/0.5.1/`. The 405×900 run exports written exercises to `builds/0.5.1-exercise-examples.md` and saves Melodies screenshots at 720×405, 900×405, 1280×800, and 1600×1000 under `builds/screenshots/0.5.1/`.

```powershell
$godot = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --editor --import --path .
& $godot --headless --path . --quit-after 10
& $godot --headless --path . --script tests/smoke.gd
& $godot --path . --resolution 320x640 --script tests/smoke.gd
& $godot --path . --resolution 405x720 --script tests/smoke.gd
& $godot --path . --resolution 405x900 --script tests/smoke.gd
```

## Known limitations

The interface is in Russian. Melody exercises check pitch order and held key pairs at the player's pace. They do not score rhythmic timing. Android touch, rotation, and audio still need physical-device verification for 0.5.1.
