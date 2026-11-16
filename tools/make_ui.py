"""Turn raw generated UI art (flat magenta background) into the game's UI textures.

  ~/personal/sfx-lab/.venv/bin/python -I tools/make_ui.py <raw_dir>

<raw_dir> may hold any of: button.png, icons.png, panel.png. Writes into ui/:
  btn_orange/green/wood/grey.png  one button recoloured four ways (ends are 9-sliced in game)
  heart, heart_empty, coin, shield, trophy, ankh .png   cut from the icon row, left to right
  panel.png                       the carved panel frame (9-sliced in game)
  token.png, scroll.png, die.png  HUD player card, message scroll, blank die face
  btn_dark.png                    dark bar frame for the stats strip, race track and timers
"""

import colorsys
import sys
from pathlib import Path

import numpy as np
from PIL import Image

UI = Path(__file__).resolve().parent.parent / "ui"
ICONS = ["heart", "heart_empty", "coin", "shield", "trophy", "ankh"]
SIGNS = ["s_snake", "s_rope", "s_crumble", "s_tiger", "s_spike", "s_mystery"]


def key(path: Path) -> np.ndarray:
    """RGBA array with the magenta background made transparent."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    magenta = np.minimum(r, b) - g
    alpha = np.clip((150 - magenta) * 255 // 70, 0, 255).astype(np.uint8)
    out = np.dstack([im.astype(np.uint8), alpha])
    rim = alpha < 255  # pull pink spill out of the soft edge
    out[..., 0][rim] = np.minimum(out[..., 0][rim], out[..., 1][rim] + 40)
    out[..., 2][rim] = np.minimum(out[..., 2][rim], out[..., 1][rim] + 40)
    return out


def crop(a: np.ndarray) -> np.ndarray:
    ys, xs = np.where(a[..., 3] > 40)
    return a[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]


def fit_height(a: np.ndarray, h: int) -> Image.Image:
    im = Image.fromarray(a, "RGBA")
    return im.resize((round(im.width * h / im.height), h), Image.LANCZOS)


def recolour(im: Image.Image, mode: str) -> Image.Image:
    """Repaint the orange face; the gold rim (yellower hue) is left alone except for grey."""
    a = np.asarray(im).astype(np.float32) / 255.0
    out = a.copy()
    for y in range(a.shape[0]):
        for x in range(a.shape[1]):
            r, g, b, al = a[y, x]
            if al == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            face = (h < 0.105 or h > 0.97) and s > 0.4
            if mode == "grey":
                s, v = s * 0.12, v * 0.62
            elif face and mode == "green":
                h, s, v = 0.37, s * 0.85, v * 0.82
            elif face and mode == "wood":
                h, s, v = 0.075, s * 0.7, v * 0.5
            elif face and mode == "dark":
                h, s, v = 0.07, s * 0.6, v * 0.26
            out[y, x, :3] = colorsys.hsv_to_rgb(h, s, v)
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def main() -> None:
    raw = Path(sys.argv[1])
    UI.mkdir(exist_ok=True)
    if (raw / "button.png").exists():
        base = fit_height(crop(key(raw / "button.png")), 128)
        base.save(UI / "btn_orange.png")
        for mode in ("green", "wood", "grey", "dark"):
            recolour(base, mode).save(UI / f"btn_{mode}.png")
        dark = Image.open(UI / "btn_dark.png")
        dark.resize((round(dark.width * 56 / dark.height), 56), Image.LANCZOS).save(UI / "bar_dark.png")
        print("button", base.size)
    for sheet, names, size in (("icons.png", ICONS, 96), ("signs.png", SIGNS, 160)):
        if not (raw / sheet).exists():
            continue
        a = key(raw / sheet)
        cols = (a[..., 3] > 40).sum(axis=0) > 3
        runs, start = [], None
        for x, on in enumerate(cols):
            if on and start is None:
                start = x
            elif not on and start is not None:
                runs.append((start, x))
                start = None
        if start is not None:
            runs.append((start, len(cols)))
        runs = [r for r in runs if r[1] - r[0] > 40]
        print(sheet, "found", len(runs))
        for name, (x0, x1) in zip(names, runs):
            icon = Image.fromarray(crop(a[:, x0:x1]), "RGBA")
            side = max(icon.size)
            sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            sq.paste(icon, ((side - icon.width) // 2, (side - icon.height) // 2))
            sq.resize((size, size), Image.LANCZOS).save(UI / f"{name}.png")
    for name in ("banana",):  # one icon per image
        if (raw / f"{name}.png").exists():
            icon = Image.fromarray(crop(key(raw / f"{name}.png")), "RGBA")
            side = max(icon.size)
            sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            sq.paste(icon, ((side - icon.width) // 2, (side - icon.height) // 2))
            sq.resize((96, 96), Image.LANCZOS).save(UI / f"{name}.png")
            print(name, "icon")
    for name, width in (("token", 220), ("die", 256)):
        if (raw / f"{name}.png").exists():
            im = Image.fromarray(crop(key(raw / f"{name}.png")), "RGBA")
            im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
            im.save(UI / f"{name}.png")
            print(name, im.size)
    if (raw / "scroll.png").exists():
        im = fit_height(crop(key(raw / "scroll.png")), 120)
        im.save(UI / "scroll.png")
        print("scroll", im.size)
    if (raw / "panel.png").exists():
        im = Image.fromarray(crop(key(raw / "panel.png")), "RGBA")
        im = im.resize((560, round(im.height * 560 / im.width)), Image.LANCZOS)
        im.save(UI / "panel.png")
        print("panel", im.size)


if __name__ == "__main__":
    main()
