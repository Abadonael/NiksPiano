# Niks Piano — approved carbon UI references

- `menu_carbon.png`: settings/start menu; preserve dark monochrome carbon palette, compact selection cards and bottom Start button. No extra explanatory text.
- `game_staff_carbon.png`: staff-reading gameplay; preserve layout, white staff and one note, full-width 7-white/5-black-key piano, octave label under piano. Top-right 'НОТНЫЙ СТАН' label is absent.
- These are **design references**, not game textures or UI backgrounds. Recreate controls as interactive Godot nodes and vector drawing so layouts adapt to phone sizes.
- `.gdignore` prevents Godot from importing reference files as game assets.

Product logic: staff mode has four independently toggled seven-note ranges (treble C4-B4 / C5-B5, bass C2-B2 / C3-B3), naming mode has seven note names with Russian/letter choice and no octaves. Correct answers highlight key green for 0.4s; wrong staff-mode answers show one red outlined note at the chosen pitch (replace previous), and let the user retry.
