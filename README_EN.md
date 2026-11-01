# Snow Shelter Challenge — Quick Start (English)

> *Read the Land. Make a Plan. Survive the Night.*
> A winter-survival game about reading the terrain, building the right shelter before dark, and finding out — honestly — why you lived or didn't.
> Full design docs are in Chinese (`VISION.md`, `CORE_GAMEPLAY.md`, `PRODUCTION_PLAN.md`, …); this page is the English entry point.

## Run it

Requires **Godot 4.3 stable** (Forward+, Vulkan).

```bash
godot --path .            # play (or open the project in the Godot editor and press F5)
```

The game starts on a briefing screen. There are **5 chapters × 10 stages** (stage 1 easy → stage 10 hard), then free play. Each chapter teaches one thing and uses its own kind of terrain (ridge valley, flat basin, lakeshore, cliff band) and gear; each stage keeps the same map until you ask for a new one. **←/→** = chapter, **↑/↓** = stage (gamepad LB/RB, d-pad), **N** = new map for this stage (gamepad Y), **Enter** = begin, **L** = English / 中文; in free play, **2** = full day. A night that ends **COLD** or **SAFE** opens the next stage; passing stage 5 opens the next chapter. On the report, **Enter** = next stage, **R** = same place again. Surviving a night in a shelter teaches it for every chapter (new players know the trench).

| Chapter | Lesson |
| :-- | :-- |
| 1 | Read the wind and dig a snow cave (deep drifts, full kit, starts 10:00 at stage 1) |
| 2 | Deep snow hides in a few pockets: probe before you dig |
| 3 | Blowdown, little light: a root plate is half a shelter (lean-to + fire) |
| 4 | Open flat ground or a lakeshore, shallow snow: dig a trench |
| 5 | A storm, no extra layer: read the land and pick the shelter it allows |

Developer flags (after `--`): `--level=N|free` (chapter), `--stage=S`, `--seed=S`, `--unlock-all`, `--shape=basin|lakeshore|cliff_band`.

## How a game goes

It is January 14, −17 °C (free play and most levels: 14:20 start, wind from the west in the base layout — levels turn the whole map so the wind can come from any side); the sun sets at 16:18 and night is forced at 17:50.

1. **Find deep snow.** Hold **Space** to probe. Leeward (east) slopes collect the deepest snow; wind-shaped snow tongues mark the deepest spots. "Deeper snow" labels appear only where you have probed.
2. **Gather.** Hold **E** near: standing dead trees (dry wood), birches (bark = tinder), dry grass and low spruce boughs (bedding). Fallen logs are wet and won't burn.
3. **Build.** Press **B** for build mode: **Tab** shelter type (raised snow cave / basic cave / snow trench / rootball lean-to), **R** rotate the entrance (keep it leeward), **T** roof thickness, **2** one or two vents, **E** place. Then hold **E** at the site to dig five visible stages.
4. **Fire.** Hold **F** to light a fire (needs bark + wood, out of the wind, not under a snowy tree, never inside a snow shelter). Hold **E** at a fire to melt snow for a hot drink. Fires also dry damp clothing.
5. **Sleep.** Press **N** (twice to confirm). You get a six-axis night report — site & wind, structure, insulation, cold-air isolation, air, heat — each with a one-line reason, plus one lesson. **R** tries again in the next of four valleys.

**Read the land:** trees have short branches on the windward side; drifts show where snow is deep; standing dead trees mean fuel; rootballs and thick forest break the wind; **shadows tell time** — the sun follows its real January path, so long shadows mean less than an hour of light.

## Controls

| Key | Action |
| :--- | :--- |
| WASD / arrows | move (relative to the camera) |
| Space (hold) | probe snow depth |
| E (hold) | gather / build / drink |
| B | build mode (Tab, R, T, 2, E inside it) |
| F (hold) | light fire · tap near a fire = add wood |
| N | sleep |
| H | field guide |
| Esc | pause (R restart, Q quit, C credits) |
| V / mouse wheel | tilt-shift ⇄ orthographic camera / zoom |
| L | English / 中文 |
| F9 | hold assist (one tap starts any hold action) |
| F10 / F11 / M / − = | graphics preset / fullscreen / mute / UI size |
| F3 | developer snow-depth heatmap |

Gamepad: left stick move, A interact, X probe, Y build, B fire (cancel in build mode), Start pause, Back field guide, LB/RB rotate/type, D-pad roof/vents/sleep/language.

## Develop and test

```bash
tools/ci.sh [--quick]     # everything below in one go (~6 min, --quick ~2 min); keeps your saves
godot --headless --path . -s res://tests/run_all.gd                 # 453 logic assertions
godot --path . -s res://tools/input_smoke_test.gd                   # real keyboard/gamepad input, start to report
godot --path . -s res://tools/playtest_bot.gd -- --s=deep_stick     # strategy bots for balance
godot --path . -s res://tools/fuzz_test.gd -- --seconds=60 --seed=1 # random-input fuzzing
tools/build.sh linux|windows|all    # standalone builds (needs Godot 4.3 export templates installed)
```

All gameplay numbers live in `resources/tuning.tres` (tagged `[REAL]` / `[GAME]` / `[TUNE]`). Assets are procedural; the hiker and rock outcrops are generated by `tools/blender/*.py` (Blender 4.x).

## Running a playtest

Each game writes a local event log to `user://sessions/` (nothing leaves the machine). After testers play:

```bash
python3 tools/playtest_report.py      # gate metrics: first probe leeward?, time to first probe, finished?, length, entrance, outcomes
```

Fill in `playtests/PT_TEMPLATE.md` (copy to `PT01.md` / `PT02.md`) with the questions the logs can't answer — wind direction at 30 s, "why did that happen?", "play again?".

## Status (November 2026)

The full loop is playable and covered by automated tests, bots and screenshots, but **has not yet been playtested by people**. Open items and decisions are in `todo.md`; the roadmap is `PRODUCTION_PLAN.md` (§4.V for the recent visual/gameplay track). Known issue: a rare engine-level crash (~3 % of random-input fuzz runs) that needs a debug build of Godot to diagnose.
