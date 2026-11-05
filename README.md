# Synthetic Heart Rift (`xenu.synth_rift`)

A mod for [RetroXR](https://github.com/RetroXR/RetroXR): the **Rift Summoner**, an object that brings Synthetic Heart
into the room. Switch it on and Synthetic Heart steps out of a pod. They walk, turn, talk, look at things and carry
them, sit, watch the TV and listen through the chat page's microphone. They never play a game: a verb that is not on
the protocol's list is refused, and nothing is written to a core.

It needs a **Synthetic Heart server** (the Rift Vessel socket, `/api/vessel/retroxr/ws`).

## Install

Get `xenu.synth_rift-<version>.zip` from the [releases](../../releases) and put it in your RetroXR data folder,
under `mods/` (`~/retroxr/mods/` on desktop). Then enable it in the MODS tab.

## Build the pack

    python3 tools/pack_mod.py            # writes dist/xenu.synth_rift-<version>.zip and reads it back

The pack holds source files only. The body's model and animations come from the Synthetic Heart server's skin,
never from this repository.

## Releases

A push to `main` publishes the release `v<version>` (the version in `mod.json`) with the zip attached. The notes are
the commits since the previous release: `feat` under Changes, `fix` under Fixes. A push that leaves the version as it
was publishes nothing. See [`.github/workflows/release.yml`](.github/workflows/release.yml).

## Layout

[`README.txt`](README.txt) has the file-by-file map and the test commands. In short:

- `mod_main.gd` the entry point; `mod.json` the manifest
- `scripts/` the protocol, the socket, the body, the pod, the menu and the tests' targets
- `scenes/` the pod, its menu and the chat page
- `tests/` probes and unit tests, run against a RetroXR checkout
- `tools/` the pack and release scripts, which are not part of the mod
