"""Fetch the game's recorded sounds from freesound.org (all CC0, public domain)
and write them, trimmed and levelled, to sfx/ as mono WAV.

    ~/personal/sfx-lab/.venv/bin/python tools/import_sounds.py <download_dir> [sound names...]

Needs numpy and soundfile (the sfx-lab environment has both) and macOS's
`afconvert` to decode the MP3 previews. Each sound's page is checked for the
CC0 licence before it is used. The game (sfx.gd) plays any file found in sfx/
in place of its synthesised version. The list below is the source for
CREDITS.md: run with `--credits` to print the table.
"""

import subprocess
import sys
import urllib.request
from pathlib import Path

import numpy as np
import soundfile as sf

OUT = Path(__file__).resolve().parent.parent / "sfx"
PREVIEW = "https://cdn.freesound.org/previews/{folder}/{sound}_{user}-hq.mp3"
PAGE = "https://freesound.org/s/{sound}/"
RATE = 32000
AGENT = {"User-Agent": "Mozilla/5.0 (Macintosh)"}

# game sound: (start at second, keep seconds, loop?, freesound id, uploader id, title, author)
SOURCES = {
    "roar": (0.0, 3.4, False, 546399, 2282212, "Angry Tiger Fantasy", "szegvari"),
    "growl": (0.0, 2.6, False, 439280, 954919, "Angry tiger.wav", "schots"),
    "snake": (0.0, 2.2, False, 540162, 7898982, "Snake hissing.mp3", "schreibsel"),
    "trumpet": (0.0, 2.6, False, 527845, 11431915, "Elephant Trumpets Growls.flac", "D.jones"),
    "monkey": (0.0, 2.6, False, 67355, 706955, "Gibbon Monkey.mp3", "Bidone"),
    "gorilla": (0.0, 2.8, False, 397054, 2884295, "Gorillaschrei.wav", "J0ck0"),
    "thunder": (0.0, 5.5, False, 672776, 1357949, "Thunder Clap", "DaniloSFX"),
    "punch": (0.0, 0.7, False, 439747, 3507073, "Punch Hit 1.wav", "joe_anderson22"),
    "crumble": (0.0, 3.2, False, 488660, 9395330, "Tumbling Rocks", "Fission9"),
    "boulder": (2.0, 3.2, False, 381645, 5486695, "RockFall1b.wav", "AlanCat"),
    "dice": (0.0, 1.0, False, 629982, 12715066, "Dice Rolling on Table", "Flem0527"),
    "step": (0.0, 0.3, False, 390764, 7350412, "FX_005_footstep_stone_l.wav", "d00121058"),
    "coin": (0.0, 0.45, False, 402067, 6142149, "Retro, Coin 01.wav", "LilMati"),
    "rain": (2.0, 14.0, True, 671409, 14660805, "forest heavy rain loop.wav", "Victormaa"),
    "amb_day": (5.0, 24.0, True, 644886, 3288322, "Jungle ambience. Nagarhole Wildlife Sanctuary..wav", "seventhsamurai"),
    "amb_night": (5.0, 22.0, True, 462889, 3902754, "Frogs croaking & crickets at night in jungle swamp Africa", "mycompasstv"),
}
# background music: (start at second, keep seconds, freesound id, uploader id, title, author) -> sfx/music.ogg, stereo
MUSIC = (1.0, 34.0, 608809, 2282212, "Tribal Jungle Beat Fast Ethno World Experimental Drums Flute Marimba Cinematic Music Surround.wav", "szegvari")
# loops are levelled by loudness rather than peak, so one stray bird call does not leave the bed too quiet
LOOP_RMS = 0.08


def fetch(url: str) -> bytes:
    return urllib.request.urlopen(urllib.request.Request(url, headers=AGENT), timeout=60).read()


def tidy(mono: np.ndarray, start: float, seconds: float, loop: bool) -> np.ndarray:
    mono = mono[int(start * RATE):]
    if not loop:  # trim leading silence
        loud = np.flatnonzero(np.abs(mono) > 0.03 * np.abs(mono).max())
        mono = mono[max(0, loud[0] - RATE // 200):]
    mono = mono[: int(seconds * RATE)].copy()
    if loop:  # blend the tail into the head so the loop has no click
        blend = RATE // 2
        ramp = np.linspace(0.0, 1.0, blend)
        mono = np.concatenate([mono[:blend] * ramp + mono[-blend:] * (1.0 - ramp), mono[blend:-blend]])
        rms = float(np.sqrt((mono ** 2).mean()))
        return np.tanh(mono * (LOOP_RMS / max(rms, 1e-6))) * 0.9
    fade = min(len(mono), RATE // 5)
    mono[-fade:] *= np.linspace(1.0, 0.0, fade)
    return mono / max(np.abs(mono).max(), 1e-6) * 0.9


def main() -> None:
    if "--credits" in sys.argv:
        print("| File | Original title | Author | Source |\n|---|---|---|---|")
        for name, (_s, _k, _l, sound, _u, title, author) in SOURCES.items():
            print(f"| `{name}.wav` | {title} | {author} | https://freesound.org/s/{sound}/ |")
        print(f"| `music.ogg` | {MUSIC[4]} | {MUSIC[5]} | https://freesound.org/s/{MUSIC[2]}/ |")
        return
    cache = Path(sys.argv[1])
    cache.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(exist_ok=True)
    only = sys.argv[2:]
    for name, (start, seconds, loop, sound, user, title, _author) in SOURCES.items():
        if only and name not in only:
            continue
        page = fetch(PAGE.format(sound=sound)).decode("utf-8", "replace")
        if "Creative Commons 0" not in page and "publicdomain/zero" not in page:
            print(f"SKIPPED {name}: sound {sound} is not CC0 on its page")
            continue
        mp3 = cache / f"{sound}.mp3"
        if not mp3.exists():
            mp3.write_bytes(fetch(PREVIEW.format(folder=sound // 1000, sound=sound, user=user)))
        wav = cache / f"{sound}.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1", str(mp3), str(wav)], check=True)
        data, rate = sf.read(wav)
        assert rate == RATE
        out = tidy(np.asarray(data, dtype=np.float64), start, seconds, loop)
        sf.write(OUT / f"{name}.wav", out, RATE, subtype="PCM_16")
        print(f"{name}.wav  {len(out) / RATE:.1f}s  CC0 ok  ({title})")
    if not only or "music" in only:
        start, seconds, sound, user, title, _author = MUSIC
        page = fetch(PAGE.format(sound=sound)).decode("utf-8", "replace")
        if "Creative Commons 0" not in page and "publicdomain/zero" not in page:
            print(f"SKIPPED music: sound {sound} is not CC0 on its page")
            return
        mp3 = cache / f"{sound}.mp3"
        if not mp3.exists():
            mp3.write_bytes(fetch(PREVIEW.format(folder=sound // 1000, sound=sound, user=user)))
        wav = cache / f"{sound}_st.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "2", str(mp3), str(wav)], check=True)
        data, rate = sf.read(wav)
        data = data[int(start * rate):][: int(seconds * rate)]
        blend = rate  # one second of tail folded into the head, so the loop is seamless
        ramp = np.linspace(0.0, 1.0, blend)[:, None]
        data = np.concatenate([data[:blend] * ramp + data[-blend:] * (1.0 - ramp), data[blend:-blend]])
        data = data / max(np.abs(data).max(), 1e-6) * 0.85
        sf.write(OUT / "music.ogg", data, rate, format="OGG", subtype="VORBIS")
        print(f"music.ogg  {len(data) / rate:.1f}s  CC0 ok  ({title})")


if __name__ == "__main__":
    main()
