# xenu.synth_rift

Synthetic Heart Rift for RetroXR: the **Synthetic Heart Rift Summoner** object. Switch it on
and Synthetic Heart (SyntH) steps into the room through the Rift Vessel on her server.

Authored in a RetroXR checkout (`RetroXR/mods/xenu.synth_rift/`, which RetroXR's `.gitignore`
excludes), so this folder is its own git repository. The Synth half lives in
`Synthetic_Heart` (`plugins/rift_vessel/retroxr/`, `core/vessel_retroxr_api.py`).

- `scripts/rift_protocol.gd` the frames (pure)
- `scripts/rift_link.gd` the WebSocket client
- `scripts/rift_dispatch.gd` one verb: socket -> body -> socket (refuses what is not a verb)
- `scripts/synth_body.gd` the body (capsule for now; walks in straight lines)
- `scripts/summoner_model.gd` the pod (built in code, 2.2 m, the screen 12 x 7 cm at chest height)
- `scripts/summoner_sounds.gd` the teleport sounds, synthesised; `tests/sound_tests.gd -- --write=DIR` writes them as wav
- `scripts/summoner_view.gd` what Synth sees when she steps out (bearing, distance, side)
- `scripts/rift_summoner.gd` the pickable and the summoning sequence (its own menu: point + left stick / Tab; server and password live there)
- `scripts/rift_options_panel.gd`, `rift_options_2d.gd`, `rift_settings.gd` that menu and the file behind it
- `tests/protocol_tests.gd` run with `godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/protocol_tests.gd`
- `tests/rift_harness.py` + `tests/e2e_probe.gd` the mod against Synth's real rift socket

Phase 0 is done: socket, handshake, say, walk, look, status, refusal of anything that is not a
verb. Not built: VRM body and animations, objects, screens, touch, voice, chat input.
