# Credits

Treasure Seeker (project folder `vault-run`).

## Font

`fonts/LilitaOne-Regular.ttf`

- Lilita One, by Juan Montoreano
- Licence: SIL Open Font License 1.1 (`fonts/LilitaOne-OFL.txt`)
- Source: https://github.com/google/fonts/tree/main/ofl/lilitaone

## UI art

`ui/logo.png`, `ui/panel.png`, `ui/btn_*.png`, `ui/heart.png`, `ui/heart_empty.png`,
`ui/coin.png`, `ui/shield.png`, `ui/trophy.png`, `ui/ankh.png`, `ui/token.png`, `ui/scroll.png`,
`ui/die.png`, `ui/bar_dark.png`, `ui/s_*.png` (slab signs), `ui/banana.png`

- Generated for this game on OpenArt with GPT Image 2, 2026-11-16
- Background removed, cut and recoloured with `tools/make_ui.py`

## Sound

`sfx/*.wav`, from freesound.org. Every one is licensed CC0 1.0 (public domain
dedication); the licence is checked on each sound's own page when it is
fetched (last run 2026-11-16). Fetched as the site's high-quality MP3
previews, then trimmed, levelled and converted to mono WAV by
`tools/import_sounds.py`.

| File | Original title | Author | Source |
|---|---|---|---|
| `roar.wav` | Tiger Roar | lauramellis | https://freesound.org/s/263115/ |
| `growl.wav` | Angry tiger.wav | schots | https://freesound.org/s/439280/ |
| `snake.wav` | Snake hissing.mp3 | schreibsel | https://freesound.org/s/540162/ |
| `trumpet.wav` | Elephant Trumpets Growls.flac | D.jones | https://freesound.org/s/527845/ |
| `monkey.wav` | Gibbon Monkey.mp3 | Bidone | https://freesound.org/s/67355/ |
| `gorilla.wav` | Gorillaschrei.wav | J0ck0 | https://freesound.org/s/397054/ |
| `thunder.wav` | Thunder Clap | DaniloSFX | https://freesound.org/s/672776/ |
| `punch.wav` | Punch Hit 1.wav | joe_anderson22 | https://freesound.org/s/439747/ |
| `crumble.wav` | Tumbling Rocks | Fission9 | https://freesound.org/s/488660/ |
| `boulder.wav` | RockFall1b.wav | AlanCat | https://freesound.org/s/381645/ |
| `dice.wav` | Dice Rolling on Table | Flem0527 | https://freesound.org/s/629982/ |
| `step.wav` | FX_005_footstep_stone_l.wav | d00121058 | https://freesound.org/s/390764/ |
| `coin.wav` | Retro, Coin 01.wav | LilMati | https://freesound.org/s/402067/ |
| `rain.wav` | forest heavy rain loop.wav | Victormaa | https://freesound.org/s/671409/ |
| `amb_day.wav` | Jungle ambience. Nagarhole Wildlife Sanctuary..wav | seventhsamurai | https://freesound.org/s/644886/ |
| `amb_night.wav` | Frogs croaking & crickets at night in jungle swamp Africa | mycompasstv | https://freesound.org/s/462889/ |

All other sounds (jumps, landings, chimes, rope, fire) are synthesised in code (`sfx.gd`).

## Everything else

3D world, characters, animals, effects and code: built procedurally in this project.
