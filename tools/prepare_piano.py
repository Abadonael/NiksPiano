"""Rebuild the bundled Salamander samples with Python and FFmpeg."""

from array import array
import argparse
from concurrent.futures import ThreadPoolExecutor
from math import cos, pi
from pathlib import Path
import re
import subprocess
from urllib.parse import quote
from urllib.request import urlretrieve
import wave


PROJECT = Path(__file__).resolve().parents[1]
SOURCE = "https://raw.githubusercontent.com/sfzinstruments/SalamanderGrandPiano/3382bf9496bba2486f5ab0de55a264d1dfc38404"
CACHE = PROJECT / ".godot" / "checks" / "piano-source"
OUTPUT = PROJECT / "assets" / "piano"
RATE = 44_100
FRAMES = round(2.4 * RATE)
CHANNELS = 2
ATTACK_FRAMES = round(0.002 * RATE)
TAIL_FRAMES = round(0.55 * RATE)
PEAK = 10 ** (-6 / 20)


def fetch(source_path):
    destination = CACHE / Path(source_path).name
    if not destination.exists():
        temporary = destination.with_suffix(".download")
        urlretrieve(f"{SOURCE}/{quote(source_path)}", temporary)
        temporary.replace(destination)
    return destination


def prepare(region):
    index, midi, name = region
    midi = int(midi)
    seconds = 7.0 if midi < 36 else 4.0 if midi > 84 else 2.4
    limit = round(seconds * RATE)
    tuning = round(48_000 * 2 ** (TUNING[index] / 1200))
    # Start just before the upstream layer's low-latency attack offset.
    offset = max(0, OFFSETS[index] - 144)
    original = fetch(f"Samples/{name}v8.flac")
    decoded = subprocess.check_output([
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(original),
        "-af", f"atrim=start_sample={offset},asetrate={tuning},aresample={RATE},atrim=end_sample={limit}",
        "-ac", str(CHANNELS), "-f", "f32le", "pipe:1",
    ])
    samples = array("f")
    samples.frombytes(decoded)
    frames = len(samples) // CHANNELS
    assert frames >= min(FRAMES, limit) or midi > 84 and frames > RATE, f"Unexpected sample length for {name}"
    gain = PEAK / max(map(abs, samples))
    pcm = array("h")
    for frame in range(frames):
        envelope = 1.0
        if frame < ATTACK_FRAMES:
            envelope = 0.5 - 0.5 * cos(pi * frame / ATTACK_FRAMES)
        elif frame >= frames - TAIL_FRAMES:
            remaining = (frames - 1 - frame) / (TAIL_FRAMES - 1)
            envelope = 0.5 - 0.5 * cos(pi * remaining)
        for channel in range(CHANNELS):
            pcm.append(round(samples[frame * CHANNELS + channel] * gain * envelope * 32767))
    with wave.open(str(OUTPUT / f"{midi}.wav"), "wb") as wav:
        wav.setparams((CHANNELS, 2, RATE, frames, "NONE", "not compressed"))
        wav.writeframes(pcm.tobytes())
    print(f"{name} v8 -> {midi}.wav ({TUNING[index]:+} cents)", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extended-only", action="store_true", help="Keep the original 17 WAVs as-is.")
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    TUNING = {i: int(value) for i, value in re.findall(
        r"\$TUNE(\d+) (-?\d+)", fetch("Data/tune_ret.txt").read_text()
    )}
    OFFSETS = {i: int(value) for i, value in re.findall(
        r"\$OFF(\d+) (\d+)", fetch("Data/vel_08.txt").read_text()
    )}
    regions = re.findall(
        r"region_label=(\d+) .*?pitch_keycenter=(\d+) sample=([^$]+)",
        fetch("Data/region.txt").read_text(),
    )
    with ThreadPoolExecutor(max_workers=6) as workers:
        list(workers.map(prepare, [r for r in regions if not args.extended_only or not 36 <= int(r[1]) <= 84]))
