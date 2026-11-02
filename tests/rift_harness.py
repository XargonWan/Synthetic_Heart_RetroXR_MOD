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

vessel_retroxr_api.webui_auth.configured_token = lambda: None
PORT = 8765
# PROBE=summoner runs the Summoner OBJECT (needs the autoloads); default is the headless link+body.
PROBE_ARGS = (["res://mods/xenu.synth_rift/tests/summoner_probe.tscn"] if os.environ.get("PROBE") == "summoner"
              else ["--script", "res://mods/xenu.synth_rift/tests/e2e_probe.gd"])
GODOT = os.environ.get("GODOT", os.path.expanduser("~/Godot/Godot_v4.7.2-stable_linux.x86_64"))
PROJECT = os.environ.get("RETROXR_PROJECT", os.path.expanduser("~/gits/RetroXR-xargon/RetroXR"))


class FakePlugin:
    async def connect_world(self, connector_name=None, overrides=None):
        conn = VESSEL_REGISTRY.load_connector(connector_name)
        ok = await conn.connect({}, lambda e: print("[synth] event:", e.event_type, e.summary))
        return VesselActionResult(ok=ok, data={"session_id": "harness-1"})

    async def disconnect_world(self, connector_name=None):
        await VESSEL_REGISTRY.load_connector(connector_name).disconnect()
        return VesselActionResult(ok=True)


core_initializer.PLUGIN_REGISTRY["vessel_plugin"] = FakePlugin()
app = FastAPI()
app.include_router(vessel_retroxr_api.create_retroxr_router())


def show(label, res):
    print(f"[synth] {label}: ok={res.ok} detail={res.detail!r} data={res.data}")


async def drive():
    conn = VESSEL_REGISTRY.load_connector("retroxr")
    for _ in range(300):
        if conn.is_connected:
            break
        await asyncio.sleep(0.1)
    else:
        print("[synth] NEVER CONNECTED"); return
    print("[synth] rift open; hello =", conn._hello)
    await asyncio.sleep(1.2)
    show("status", await conn.act("status", {}))
    show("say", await conn.act("say", {"text": "Ciao, sono entrata nella stanza."}))
    show("move to (2,0,2)", await conn.act("move", {"x": 2, "y": 0, "z": 2}))
    show("move through the wall", await conn.act("move", {"x": 0, "y": 0, "z": -6}))
    show("move 50 m away", await conn.act("move", {"x": 50, "y": 0, "z": 0}))
    show("look at (5,0,0)", await conn.act("look", {"x": 5, "y": 0, "z": 0}))
    show("pick_up (not built)", await conn.act("pick_up", {"target": "cart"}))
    show("press_button via connector", await conn.act("press_button", {}))
    # bypass the connector: a raw frame the MOD must refuse on its own
    fut = asyncio.get_running_loop().create_future()
    conn._pending[999] = fut
    await conn._ws.send_json({"type": "action", "id": 999, "action": "press_button", "payload": {}})
    show("press_button RAW to the mod", await asyncio.wait_for(fut, 5))
    show("state frame seen", VesselActionResult(ok=bool(conn._state), data=conn._state))
    await FakePlugin().disconnect_world("retroxr")


async def main():
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="warning"))
    st = asyncio.create_task(server.serve())
    await asyncio.sleep(1.0)
    env = dict(os.environ, XENU_SYNTH_URL=f"127.0.0.1:{PORT}")
    proc = await asyncio.create_subprocess_exec(
        GODOT, "--headless", "--path", PROJECT,
        *PROBE_ARGS,
        env=env, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)

    async def pump():
        async for line in proc.stdout:
            t = line.decode(errors="replace").rstrip()
            if "[probe]" in t or "[Rift]" in t or "SCRIPT ERROR" in t and "synth_rift" in t:
                print(t)
    pt = asyncio.create_task(pump())
    d = asyncio.create_task(drive())
    try:
        await asyncio.wait_for(proc.wait(), 120)
    except asyncio.TimeoutError:
        proc.kill(); print("[harness] godot timeout")
    await pt
    d.cancel()
    server.should_exit = True
    await st

asyncio.run(main())
