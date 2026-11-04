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
- `scripts/vrm_budget.gd`, `body_cache.gd` what a body may cost (textures, morph targets, triangles per tier) and the finished body kept under user://
- `scripts/vrm_face.gd` her face: the WebUI's FacialDriver (blink, emotion layers, mouth from her voice's loudness)
- `scripts/world_view.gd` what a thing in the room is called for a person (`unknown item`, never empty) and what is in her view (180 degrees, not hidden)
- `scripts/synth_routines.gd` what she does on her own once asked: search, explore, watch, fetch; the model is told afterwards
- `scripts/karada_puppet.gd` her VRM + Mixamo clips retargeted by hand, her gaze, the crossfade between clips, a descriptor's loop window and the upper-body layer (`mask`)
- `assets/` the Synth logo (no text) for the pod's flanks, and its glow map
- `scripts/voice_recorder.gd` the player's voice for Synth: joins the `Microphone` service's consumers only while the chat page's mic is on, sends a WAV (`audio` frame), gets the words back (`transcript`)
- `scripts/rift_summoner.gd` the pickable and the summoning sequence (its own menu: point + left stick / Tab; server and password live there)
- `scripts/rift_options_panel.gd`, `rift_options_2d.gd`, `rift_settings.gd` that menu and the file behind it
- `tests/protocol_tests.gd` run with `godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/protocol_tests.gd`
- `tests/rift_harness.py` + `tests/e2e_probe.gd` the mod against Synth's real rift socket

Built: socket, handshake, her own body from the Karada skin, voice and lip movement, blink and
face, a chat page, looking at things, walking to them, sightings of what changes in the room, sitting / crouching / playing with her hands, looking for things, carrying them to you, watching the TV (with a picture, which can be switched off in the pod's menu), speaking to her with the chat page's mic (Synth transcribes it with Auris), and room changes told quietly (what merely leaves her view, and cords, are not news).
Not built: picking up objects, screens, touch.
