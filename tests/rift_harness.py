"""Run: python rift_harness.py   (SYNTH_REPO, GODOT, RETROXR_PROJECT override the paths).
Drive the REAL Synth rift socket against the RetroXR mod's probe (Godot, headless).

Server side = core.vessel_retroxr_api + the real RetroXRConnector; only the Rift Vessel
plugin is faked (it needs the whole Synth runtime). Verbs go through connector.act().
"""
import asyncio, os, sys

SYNTH = os.environ.get("SYNTH_REPO", os.path.expanduser("~/gits/Synthetic_Heart"))
sys.path.insert(0, SYNTH); os.chdir(SYNTH)

import uvicorn
from fastapi import FastAPI
from core import core_initializer, vessel_retroxr_api
from core.vessel_registry import VESSEL_REGISTRY
import plugins.rift_vessel.retroxr.retroxr  # registers the connector
from plugins.rift_vessel.vessel_base import VesselActionResult

# WRONGPW=1: the server wants a token the probe does not type, so the rift must be refused.
vessel_retroxr_api.webui_auth.configured_token = (lambda: "the-real-token") if os.environ.get("WRONGPW") else (lambda: None)
PORT = 8765
# HOST=1 runs Godot on the host through flatpak-spawn (needed from a flatpak session).
# PROBE=summoner runs the Summoner OBJECT (needs the autoloads); default is the headless link+body.
PROBE_ARGS = (["res://mods/xenu.synth_rift/tests/summoner_probe.tscn"] if os.environ.get("PROBE") == "summoner"
              else ["--script", "res://mods/xenu.synth_rift/tests/e2e_probe.gd"])
GODOT = os.environ.get("GODOT", os.path.expanduser("~/Godot/Godot_v4.7.2-stable_linux.x86_64"))
PROJECT = os.environ.get("RETROXR_PROJECT", os.path.expanduser("~/gits/RetroXR-xargon/RetroXR"))


EVENTS = []


class FakePlugin:
    async def connect_world(self, connector_name=None, overrides=None):
        conn = VESSEL_REGISTRY.load_connector(connector_name)
        def on_event(e):
            EVENTS.append(e)
            print("[synth] event:", e.event_type, "|", e.summary)
        ok = await conn.connect({}, on_event)
        return VesselActionResult(ok=ok, data={"session_id": "harness-1"})

    async def disconnect_world(self, connector_name=None):
        await VESSEL_REGISTRY.load_connector(connector_name).disconnect()
        return VesselActionResult(ok=True)


core_initializer.PLUGIN_REGISTRY["vessel_plugin"] = FakePlugin()
app = FastAPI()
app.include_router(vessel_retroxr_api.create_retroxr_router())

# What the mod downloads her body from: the real Karada skin files and their hash manifest,
# served the way Synth does (/skins static, /api/karada/assets/manifest).
from pathlib import Path
from fastapi.staticfiles import StaticFiles
from core.karada_api import _build_asset_manifest
SKINS = Path(SYNTH) / "skins"
app.mount("/skins", StaticFiles(directory=str(SKINS)), name="skins")


# Her voice: a real WAV (a second of a rising tone) under /media, the way Vox's clips are served.
import math, struct, tempfile, wave
MEDIA = Path(tempfile.mkdtemp(prefix="rift_media_"))
with wave.open(str(MEDIA / "hello.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050)
    w.writeframes(b"".join(struct.pack("<h", int(9000 * math.sin(2 * math.pi * (300 + 400 * i / 22050) * i / 22050)))
                           for i in range(22050)))
app.mount("/media", StaticFiles(directory=str(MEDIA)), name="media")


@app.get("/api/karada/assets/manifest")
async def _manifest():
    return _build_asset_manifest(SKINS)


def show(label, res):
    print(f"[synth] {label}: ok={res.ok} detail={res.detail!r} data={res.data}")


async def drive():
    try:
        await _drive()
    except Exception:
        import traceback; print("[synth] DRIVE CRASHED"); traceback.print_exc()


async def _drive():
    conn = VESSEL_REGISTRY.load_connector("retroxr")
    for _ in range(900):
        if conn.is_connected:
            break
        await asyncio.sleep(0.1)
    else:
        print("[synth] NEVER CONNECTED"); return
    print("[synth] rift open; hello =", conn._hello)
    if os.environ.get("PROBE") == "summoner":
        # The Summoner brings her out of the capsule before anything else happens.
        for _ in range(300):
            if any(e.event_type == "summoned" for e in EVENTS):
                break
            await asyncio.sleep(0.1)
        else:
            print("[synth] CHECK FAIL: no 'summoned' event arrived"); return
        ev = next(e for e in EVENTS if e.event_type == "summoned")
        seen = (ev.data or {}).get("seen", [])
        checks = {
            "high salience": ev.salience == 1.0,
            "says she was summoned": "summoned" in ev.summary,
            "SEES the player (not 'cannot see')": "The player is " in ev.summary and "cannot see" not in ev.summary,
            "lists the crate in front": "Crate" in ev.summary,
            "player is in the data": any(e.get("type") == "player" for e in seen),
            "bearings are numbers": all(isinstance(e.get("bearing"), (int, float)) for e in seen),
        }
        for what, ok in checks.items():
            print(f"[synth] CHECK {'ok  ' if ok else 'FAIL'} summoned: {what}")
        # She is greeting the player: Karada's states wait until she is done (that is the point), so let her finish.
        await asyncio.sleep(7.0)
        # Karada: her avatar thinks, then speaks (a real clip from /media), then is idle again.
        await conn.send_frame({"type": "karada", "kind": "animation", "payload": {"type": "vrm_animation_v2", "state": "think"}})
        await asyncio.sleep(2.0)
        await conn.send_frame({"type": "karada", "kind": "audio", "payload": {
            "type": "tts-play", "url": "/media/hello.wav", "audio_duration_s": 1.0, "text": "Ciao dal server"}})
        await asyncio.sleep(2.5)
        await conn.send_frame({"type": "karada", "kind": "animation", "payload": {"type": "vrm_animation_v2", "state": "idle"}})
        # Her face (an emotion, by the logical name the persona maps), then a change of skin (the same one,
        # which is enough to see her body replaced).
        await conn.send_frame({"type": "karada", "kind": "face", "payload": {"type": "vrm_face", "values": {"mouth_smile": 0.7}}})
        await asyncio.sleep(1.0)
        await conn.send_frame({"type": "karada", "kind": "model", "payload": {"type": "vrm_model", "name": "Rei", "url": "/skins/Rei/model.vrm"}})
        await asyncio.sleep(4.0)
        # The probe types a line to her through the chat page: it must arrive as a player's chat.
        for _ in range(100):
            if any(e.event_type == "chat" for e in EVENTS):
                break
            await asyncio.sleep(0.1)
        chats = [e for e in EVENTS if e.event_type == "chat"]
        ok = bool(chats) and chats[0].actor == "player" and chats[0].summary == "player: ciao Rei, mi senti?" \
            and chats[0].salience == 1.0 and (chats[0].data or {}).get("addressed") is True
        print(f"[synth] CHECK {'ok  ' if ok else 'FAIL'} chat: a player's line, addressed to her ({chats[0].summary if chats else 'none'!r})")
        if os.environ.get("PROBE_EXPECT") == "dismiss":
            return  # the probe sends her back itself
    await asyncio.sleep(1.2)
    show("status", await conn.act("status", {}))
    show("say", await conn.act("say", {"text": "Ciao, sono entrata nella stanza."}))
    show("move to (2,0,2)", await conn.act("move", {"x": 2, "y": 0, "z": 2}))
    show("move through the wall", await conn.act("move", {"x": 0, "y": 0, "z": -6}))
    show("move 50 m away", await conn.act("move", {"x": 50, "y": 0, "z": 0}))
    show("look at (5,0,0)", await conn.act("look", {"x": 5, "y": 0, "z": 0}))
    show("pick_up (the mod never declared it)", await conn.act("pick_up", {"target": "cart"}))
    # What she is offered is what the mod said it can do, and nothing else.
    declared = conn.declared_verbs()
    want = {"say", "move", "look", "status", "follow", "unfollow", "look_at", "inspect", "emote"}
    print(f"[synth] CHECK {'ok  ' if declared == want else 'FAIL'} verbs: the mod declared {sorted(declared)}")
    offered = set(conn.get_world_actions()) | set(conn.core_verbs)
    print(f"[synth] CHECK {'ok  ' if offered == want and 'observe' not in offered and 'attack' not in offered else 'FAIL'} verbs: offered to her {sorted(offered)}")
    # Curiosity: she can look at things, go to them by name, and ask what they are.
    r = await conn.act("inspect", {"target": "Crate"})
    show("inspect Crate", r)
    print(f"[synth] CHECK {'ok  ' if r.ok and 'Crate' in (r.detail or '') and 'm away' in (r.detail or '') else 'FAIL'} inspect: told what it is and where")
    r = await conn.act("inspect", {"target": "no such thing"})
    print(f"[synth] CHECK {'ok  ' if not r.ok and 'nothing called' in (r.detail or '') else 'FAIL'} inspect: honest about what is not there ({r.detail!r})")
    r = await conn.act("look_at", {"target": "player"})
    print(f"[synth] CHECK {'ok  ' if r.ok else 'FAIL'} look_at: the player ({r.detail!r})")
    r = await conn.act("move", {"target": "Crate"})
    d = r.data.get("position") or {}
    near = ((d.get("x", 99) - 0.8) ** 2 + (d.get("z", 99) - 2.8) ** 2) ** 0.5
    print(f"[synth] CHECK {'ok  ' if r.ok and 0.4 < near < 1.4 else 'FAIL'} move: to a thing by its name, up to it and not into it ({near:.2f} m from it)")
    r1 = await conn.act("follow", {}); r2 = await conn.act("unfollow", {})
    print(f"[synth] CHECK {'ok  ' if r1.ok and r2.ok else 'FAIL'} follow / unfollow")
    show("press_button via connector", await conn.act("press_button", {}))
    # bypass the connector: a raw frame the MOD must refuse on its own
    fut = asyncio.get_running_loop().create_future()
    conn._pending[999] = fut
    await conn._ws.send_json({"type": "action", "id": 999, "action": "press_button", "payload": {}})
    show("press_button RAW to the mod", await asyncio.wait_for(fut, 5))
    show("state frame seen", VesselActionResult(ok=bool(conn._state), data=conn._state))
    if os.environ.get("PROBE") == "summoner":
        for _ in range(80):
            if any(e.event_type == "sighting" and "Vase" in e.summary for e in EVENTS):
                break
            await asyncio.sleep(0.1)
        sights = [e for e in EVENTS if e.event_type == "sighting"]
        ok = any("Vase" in e.summary and "appeared" in e.summary for e in sights)
        print(f"[synth] CHECK {'ok  ' if ok else 'FAIL'} sighting: a thing put down in the room is told to her ({[e.summary for e in sights]!r})")
        await asyncio.sleep(30)   # the probe looks at how she behaves when nobody is asking her anything
    await FakePlugin().disconnect_world("retroxr")


async def main():
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="warning"))
    st = asyncio.create_task(server.serve())
    await asyncio.sleep(1.0)
    env = dict(os.environ, XENU_SYNTH_URL=f"127.0.0.1:{PORT}")
    if os.environ.get("PROBE") == "summoner":
        # The Summoner probe types the server into the object's menu itself, in a
        # throw-away data dir so the player's real settings are never touched.
        import tempfile
        env.pop("XENU_SYNTH_URL")
        env["PROBE_SERVER"] = f"127.0.0.1:{PORT}"
        # In the home folder, not /tmp: a flatpak session's /tmp is private to it.
        env["XDG_DATA_HOME"] = tempfile.mkdtemp(prefix="rift_probe_", dir=os.path.expanduser("~/.cache"))
    # WINDOWED=1: a real window (the picture is drawn; SHOTS=<folder> saves frames of the summon). Never headless for a picture.
    head = ["--resolution", "640x480", "--position", "20,20"] if os.environ.get("WINDOWED") else ["--headless"]
    cmd = [GODOT, *head, "--path", PROJECT, *PROBE_ARGS]
    if os.environ.get("HOST"):
        # Run Godot on the host from inside a flatpak (the GDExtensions only load there;
        # loopback is shared). The probe's own variables go in with --env.
        keys = ("XENU_SYNTH_URL", "XENU_SYNTH_TOKEN", "PROBE_SERVER", "PROBE_EXPECT", "XDG_DATA_HOME", "SHOTS", "CHARGE")
        cmd = ["flatpak-spawn", "--host", *[f"--env={k}={env[k]}" for k in keys if k in env], *cmd]
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        env=env, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)

    async def pump():
        async for line in proc.stdout:
            t = line.decode(errors="replace").rstrip()
            if "[probe]" in t or "[Rift]" in t or "Parse Error" in t or ("SCRIPT ERROR" in t and "Libretro" not in t and "VerletRope" not in t) and "synth_rift" in t:
                print(t)
    pt = asyncio.create_task(pump())
    d = asyncio.create_task(asyncio.sleep(0) if os.environ.get("WRONGPW") else drive())
    try:
        await asyncio.wait_for(proc.wait(), 120)
    except asyncio.TimeoutError:
        proc.kill(); print("[harness] godot timeout")
    await pt
    d.cancel()
    server.should_exit = True
    await st

asyncio.run(main())
