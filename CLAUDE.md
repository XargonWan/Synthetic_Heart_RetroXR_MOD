# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`xenu.synth_rift` is a **RetroXR mod** written in GDScript (Godot 4.7). It adds one object, the *Synthetic Heart Rift Summoner*: switch it on and Synthetic Heart ("Synth", "SyntH") steps into the room as a body, driven over a WebSocket by a Synthetic Heart server. The mod is a **client only**; it never hosts a server. The server half lives in the separate `~/gits/Synthetic_Heart` repo (`plugins/rift_vessel/retroxr/`, `core/vessel_retroxr_api.py`).

This repo is not a Godot project on its own. It is the folder `RetroXR/mods/xenu.synth_rift/` of a RetroXR checkout (RetroXR's `.gitignore` excludes it, so it has its own git repo). Every `res://mods/xenu.synth_rift/...` path assumes that location. The usual checkout is `~/gits/RetroXR-xargon/RetroXR`, and `RetroXR/mods/xenu.synth_rift` is where this code runs from.

`README.txt` has the per-script one-line index. It also lists what is built and what is not (picking up objects, screens and touch are not built).

## Commands

All commands run from outside this folder against the RetroXR project. Godot is `~/Godot/Godot_v4.7.2-stable_linux.x86_64`; the examples write it as `godot`. `<mod>` stands for `res://mods/xenu.synth_rift`.

```sh
# Pure unit suites: no room, headset or server needed
godot --headless --path RetroXR --script <mod>/tests/protocol_tests.gd     # also audio_tests, sound_tests, voice_tests, world_view_tests
# Suites that need a Karada skin folder (they FAIL, not skip, without it)
SKIN=$HOME/gits/Synthetic_Heart/skins/Rei godot --headless --path RetroXR --script <mod>/tests/puppet_tests.gd
SKINS=$HOME/gits/Synthetic_Heart/skins godot --headless --path RetroXR --script <mod>/tests/budget_tests.gd
# Scene probes (a .tscn run by path)
godot --headless --path RetroXR <mod>/tests/nav_probe.tscn                 # also routine_probe, button_ray_probe
# End-to-end against a REAL Synth rift socket (starts the server side itself)
python tests/rift_harness.py              # PROBE=summoner runs the Summoner object; WRONGPW=1 tests a refused token; HOST=1 for flatpak
python tests/fetch_probe.py               # AssetFetcher against a deliberately slow HTTP server
# Write the synthesised teleport sounds as wav
godot --headless --path RetroXR --script <mod>/tests/sound_tests.gd -- --write=DIR
```

- To run a single suite, run its `--script` file. Each suite is a `SceneTree` script, and the cases are the `_xxx()` functions called from `_init()`. There is no per-case filter.
- A suite prints `[rift-tests] N cases, M failed` and exits non-zero on any failure **or when it ran zero cases**. A script that fails to compile must not count as a pass. Keep that rule in new suites.
- Python harnesses read `SYNTH_REPO` (default `~/gits/Synthetic_Heart`), `GODOT` and `RETROXR_PROJECT` from the environment.
- Tests named `*_tests.gd` assert. Tests named `*_probe.*` print `[probe]` lines for a human to read. Probes with `OUT=dir` and a window (no `--headless`) write screenshots.
- `tests/loop_scan.gd -- <clip.fbx>` is a measuring tool, not a test. It is how an animation descriptor's `loop` window is chosen.
- There is no linter or build step.

## Architecture

**Entry and registration.** `mod.json` points at `mod_main.gd`, which `extends RetroMod` and registers one object type with `api.register_object`. The type string `xenu.synth_rift:rift_summoner` is written into save slots, so it is permanent. Never rename it. `mod.json` declares `api_version: 1`.

**Wire flow.** `RiftSummoner` (the pickable and its charge/arrive/leave state machine) owns one `RiftLink` per summon.

- `rift_protocol.gd` is pure: frames, the verb lists, and `socket_url()`, which normalises any spelling of the server address. It is the one file both sides of the protocol must agree on, and `plugins/rift_vessel/retroxr/guide.md` in Synthetic_Heart documents it from the server's side.
- `rift_link.gd` is the WebSocket client, with states CLOSED → CONNECTING → HELLO → OPEN. It never reconnects by itself. The Summoner being on *is* the rift being open.
- `rift_dispatch.gd` carries one verb from socket to body and back. A verb not in `RiftProtocol` never reaches the body, and the server gets `unknown_verb`.
- `synth_body.gd` is the body (a `CharacterBody3D`). `act(verb, payload)` is a coroutine returning `{ok, detail, data}`. It is the single place where verbs become behaviour.

**Verb rule (easy to get wrong).** `IMPLEMENTED_VERBS` in `rift_protocol.gd` is what the `hello` frame offers Synth. Add a verb there only when `SynthBody.act` really does it. A verb that is offered but not implemented wastes a model turn on an error. Verbs in `CORE_VERBS`/`WORLD_VERBS` but not implemented are accepted and answered with a failure. The body never plays, and nothing here writes input to a console.

**The body.** Several layers sit on top of `synth_body.gd`:

- Download and cache: `asset_fetcher.gd` pulls the Karada skin (`model.vrm` plus Mixamo animation clips) from the same host as the socket. Files are cached under `user://mods/xenu.synth_rift/cache/` by sha256 from the server's manifest. A download is abandoned on *stall*, not on total time. `vrm_budget.gd` brings the VRM inside a per-tier cost budget (textures, morph targets, triangles). `body_cache.gd` saves the finished body as a `.scn` keyed by `<sha256>_<tier>_v<BUDGET_VERSION>`. **Bump `BUDGET_VERSION` when the budget logic changes**, or old bodies keep being served.
- Animation: `karada_puppet.gd` retargets Mixamo clips onto the VRM by hand (Mixamo faces +Z, VRoid faces -Z). It handles gaze, clip crossfade, loop windows and an upper-body `mask` layer. `vrm_face.gd` handles blink, emotion layers and a mouth driven by loudness. Until the skin arrives the body is a capsule.
- Perception: `world_view.gd` names things for a person (`unknown item`, never empty) and decides what is in view (180°, not hidden). `summoner_view.gd` gives bearing, distance and side. Synth finds things by *seeing* them (`SynthBody.sight`), never by looking them up.
- Movement: `synth_nav.gd` is a lazy A* on a floor grid. It asks the physics world about a cell only when the search reaches it, because rooms have no navmesh and change as the player moves things. `blocked_fn` can be swapped, which is how `nav_probe` tests it.
- Autonomy: `synth_routines.gd` runs search/explore/watch/fetch on the body's own. Synth is told the result *afterwards* as an event, not asked in between. A new routine, `stop` or `move` replaces the running one.

**Player-side UI and I/O.** `rift_options_panel.gd`/`rift_options_2d.gd` is the pod's own menu, and `rift_settings.gd` is the file behind it (`user://mods/xenu.synth_rift/settings.json`; server address and password live there). `chat_panel.gd`/`chat_2d.gd` is the chat page, with `chat_store.gd` as its log. The panel/2d pairs exist as a 3D panel and a desktop version of the same page, each with its own scene under `scenes/`. `voice_recorder.gd` joins RetroXR's `Microphone` service only while the chat mic is on. It sends a WAV (`audio` frame) and receives `transcript`. `audio_bytes.gd` and `summoner_sounds.gd` (sounds are synthesised in code, with no audio assets) are the audio helpers. The pod's mesh is built in code in `summoner_model.gd`.

## Conventions worth knowing

- Scripts use `preload("res://mods/xenu.synth_rift/scripts/...")` with absolute `res://` paths. Pure logic is kept in static, node-free classes (protocol, dispatch, view, nav, budget) so the headless suites can drive exactly what the room runs.
- The `.uid` files next to scripts are Godot-generated. Commit them together with new scripts.
- Comments are long `##` doc blocks that explain *why* (often the failure that prompted the design). Keep that style, and update the header when behaviour changes.
- Bump `version` in `mod.json` for releases, and keep the README's "Built / Not built" lines current.
