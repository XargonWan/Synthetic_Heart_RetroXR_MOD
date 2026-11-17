# xenu.synth_rift

Synthetic Heart Rift for RetroXR: the **Synthetic Heart Rift Summoner** object. Switch it on
and Synthetic Heart (SyntH) steps into the room through the Rift Vessel on their server.

Authored in a RetroXR checkout (`RetroXR/mods/xenu.synth_rift/`, which RetroXR's `.gitignore`
excludes), so this folder is its own git repository. The Synth half lives in
`Synthetic_Heart` (`plugins/rift_vessel/retroxr/`, `core/vessel_retroxr_api.py`).

- `scripts/rift_protocol.gd` the frames (pure)
- `scripts/rift_link.gd` the WebSocket client
- `scripts/rift_dispatch.gd` one verb: socket -> body -> socket (refuses what is not a verb)
- `scripts/synth_body.gd` the body (capsule for now; walks in straight lines)
- `scripts/summoner_model.gd` the pod (built in code, 2.2 m, the screen 12 x 7 cm at chest height)
- `scripts/summoner_sounds.gd` the teleport sounds, synthesised; `tests/sound_tests.gd -- --write=DIR` writes them as wav
- `scripts/summoner_view.gd` what Synth sees when they step out (bearing, distance, side)
- `scripts/vrm_budget.gd`, `body_cache.gd` what a body may cost (textures, morph targets, triangles per tier) and the finished body kept under user://
- `scripts/vrm_face.gd` their face: the WebUI's FacialDriver (blink, emotion layers, mouth from their voice's loudness)
- `scripts/world_view.gd` what a thing in the room is called for a person (`unknown item`, never empty) and what is in their view (180 degrees, not hidden)
- `scripts/synth_routines.gd` what they do on their own once asked: search, explore, watch, fetch; the model is told afterwards
- `scripts/synth_use.gd` what they may do to a machine with their hands (`operate`: power, volume, rewind, eject, cartridge or tape in) and the words that ask for it; a request for a game is refused with the reason
- `scripts/synth_watching.gd` what they know of a screen in front of them (a Jellyfin Decoder's `now_playing()`: title, season, episode, the line just said), told to the server as rare quiet events; the body joins the group `companion_viewer`, which makes the decoder load a hearing-impaired subtitle track for them (never drawn into the room; `tests/watching_tests.gd`)
- `scripts/karada_puppet.gd` their VRM + Mixamo clips retargeted by hand, their gaze, the crossfade between clips, a descriptor's loop window and the upper-body layer (`mask`)
- `assets/` the Synth logo (no text) for the pod's flanks, and its glow map
- `scripts/voice_recorder.gd` the player's voice for Synth: joins the `Microphone` service's consumers only while the chat page's mic is on, sends a WAV (`audio` frame), gets the words back (`transcript`)
- `scripts/rift_summoner.gd` the pickable and the summoning sequence (its own menu: point + left stick / Tab; server and password live there)
- `scripts/rift_options_panel.gd`, `rift_options_2d.gd`, `rift_settings.gd` that menu and the file behind it
- `scripts/rift_follow.gd` + the SceneManager signals watched in `rift_summoner.gd` "follow me" across ANY map change: on `scene_changed` the pod (or the invisible host already carrying them) and their body are moved onto the root with the link still open, and on `scene_content_ready` they are put beside the player at the spawn at once, with no sound (`tests/carry_e2e_probe.tscn`, `PROBE=carry python tests/rift_harness.py`); when the rift was not up to carry (charging, a failed carry) the old way is the fallback: the call left in RiftFollow is answered by the next room's pod, else by an invisible host that reconnects; the chat page's "Send back" closes the rift where there is no pod
- `scripts/follow_spot.gd` "follow me": where Synth appears beside the player after a room change (right hand first, then left, shoulders, behind, ahead; nearest ring first); `tests/follow_tests.gd` (the order) and `tests/follow_probe.tscn` (the same over real physics, and the room-change hand-over between pods); `tests/follow_e2e_probe.tscn` the same through the real link (`PROBE=follow python tests/rift_harness.py`, also with the server starting a NEW session, which it does after its idle timeout)
- `tests/protocol_tests.gd` run with `godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/protocol_tests.gd`
- `tests/rift_harness.py` + `tests/e2e_probe.gd` the mod against Synth's real rift socket

Built: "follow me" (on by default, switched in the pod's menu: change room with Synth out and the next room's pod opens the rift by itself and Synth appears beside the player; Synth is told the option in the hello and the first prompt), socket, handshake, their own body from the Karada skin, voice and lip movement, blink and
face, a chat page, looking at things, walking to them, sightings of what changes in the room, sitting / crouching / playing with their hands, looking for things, carrying them to you and holding them out (both hands, for as long as she chooses; if you do not take it she keeps it), setting them down on a table or the floor, putting one thing into another (`combine`), following you (and telling Synth when she cannot keep up), working machines (switch a TV or console on or off, volume, rewind, eject, a cartridge or tape put in or taken out; never playing), every turn on the spot as the skin's turn clip, watching the TV (with a picture, which can be switched off in the pod's menu), knowing what a Jellyfin Decoder is playing (series, season, episode, and what was just said, read from its hearing-impaired subtitle track), speaking to them with the chat page's mic (Synth transcribes it with Auris), and room changes told quietly (what merely leaves their view, and cords, are not news).
Not built: screens, touch, sitting on a chosen seat. Without a pod, "follow me" and "Send back" are only on the chat page (point at Synth, Tab): the pod's menu is not there.
