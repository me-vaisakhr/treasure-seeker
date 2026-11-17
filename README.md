# Treasure Seeker

Extended game with snake and ladder mechanics.

A dice race through a jungle to a temple's treasure, for mobile (portrait).
One die, players take turns, first to the gate wins. The classic board is
turned into a winding stone path over a misty forest: ropes carry you ahead,
cobras throw you back, and a boulder rolls after whoever is last.

Built with Godot 4.7. Everything in the 3D world is made from boxes in code;
there are no model files.

## Run

Open the folder in Godot 4.7 and press Play, or from a terminal:

    godot --path .

## How it plays

- Roll the die (tap anywhere). You have 8 seconds, or the turn is lost.
- After the roll you see where it leads. Tap to move, or spend coins first:
  reroll (3), run 3 further (5), shield (5), life (10). Coins are kept
  between races.
- Special slabs: rope (swing ahead), cobra (thrown back), tiger ambush,
  spikes, cracked slab, and "?" (an animal or a chest).
- Obstacles on the path need a timed input: spikes, log, wall, low beam and
  swinging blade. Tap controls: one tap. Swipe controls (Settings): up to
  jump, down to slide, sideways to dodge. Missing a hurdle ends your move;
  missing spikes costs a life.
- A setback never throws you more than 6 slabs, or past the last torch.
- 3 lives. Lose them all and you spend a respawn at the last torch. No
  respawns left and you are out.
- After any hit you are wounded for 2 of your own turns, and fight worse.
- Land on an occupied slab and you choose: fight for it, or share it. The
  newcomer has the edge, but can lose.
- Chests can hold a shield, a life or a respawn.

Play against 1 to 5 bots, on a path of 50 to 80 slabs (picked with the
rivals; the lobby shows the expected race time). Bots take their turns
faster than you do. Online multiplayer is planned.

## Play in a browser

https://me-vaisakhr.github.io/treasure-seeker/

The web build is made with

    godot --headless --path . --export-release Web build/web/index.html

and published from the `gh-pages` branch. It is built without threads, which
GitHub Pages requires. On a wide window the world fills the view and the
menus and HUD keep to a centred portrait column.

## Android build

Needs Godot's export templates, an Android SDK and Java 17 set in the editor
settings. Then:

    godot --headless --path . --export-debug Android build/android/treasure-seeker.apk

The app runs in immersive full screen, portrait. The HUD keeps clear of
notches and the home bar.

## Files

| File | What it holds |
|---|---|
| `main.gd` | Game rules, turn flow, world building, camera, HUD and menus |
| `actor.gd` | The runner: jointed limbs, stride, spring physics, cloth |
| `animal.gd`, `animals.gd` | Elephant, tiger, cobra, monkey, birds and their motion |
| `nature.gd` | Terrain, forest, mountains, lake, waterfalls, mist |
| `strand.gd` | Chain simulation used for cloth and ropes |
| `sfx.gd` | Sound: synthesised effects, plus the CC0 recordings in `sfx/` |
| `ui/` | Logo, panels, buttons and icons |
| `tools/` | Scripts that fetch the sound recordings and cut the UI art |

## Developer switches

Environment variables for testing:

| Variable | Effect |
|---|---|
| `VAULT_AUTOPLAY=1` | A bot plays your seat |
| `VAULT_BOTS=n` | Number of bots with autoplay |
| `VAULT_TOD=0..1` | Time of day: 0 dawn, 0.25 noon, 0.5 sunset, 0.75 night |
| `VAULT_RAIN=1` | Start in rain (with `VAULT_TOD`) |
| `VAULT_MENU=page` | Open a lobby page: `main`, `bots`, `shop`, `help`, `ranks`, `settings` |
| `VAULT_SHOT=file` | Save a screenshot after `VAULT_SHOT_AT` seconds (default 3) and quit |
| `VAULT_SAFE=top,bottom` | Preview a notch / home-bar inset on desktop |
| `VAULT_GFX=0`, `1` or `2` | Force the graphics level: low, medium, high |
| `VAULT_LEN=n` | Force the path length (20 to 80 slabs) |
| `VAULT_HURDLE=kind` | Every hurdle is this kind: `log`, `block`, `beam`, `blade` |
| `VAULT_NOSAVE=1` | Never write settings or the leaderboard (always on with autoplay) |
| `VAULT_ZOO=a,b` | Line animals up for inspection: `monkey`, `gorilla`, `tiger`, `elephant`, `cobra` |

## Support

If you enjoy the game: https://buymeacoffee.com/vrkrishna9e

## Credits

See [CREDITS.md](CREDITS.md).
