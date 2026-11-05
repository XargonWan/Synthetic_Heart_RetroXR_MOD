#!/usr/bin/env python3
"""Pack this mod into the zip RetroXR loads from <data root>/mods/, and check it the way the loader will.

  python3 tools/pack_mod.py                       # writes dist/xenu.synth_rift-<version>.zip
  python3 tools/pack_mod.py --out some/where.zip

It mirrors RetroXR/Tools/mods/pack_mod.gd, which needs a whole RetroXR checkout and a Godot binary: a pack is
source files only (.gd, .tscn, .json, .png and the like, the same list), laid out as mods/<id>/... and read back
before this exits. The rules that matter, from the loader:

  - mod.json must parse, its id must be the folder's, and its entry script must be in the pack
  - thumbnail.png must be a readable PNG, 16:9, at least 512x288 (the Mods page and the mod.io logo)
  - nothing may be the game's own file (project.godot, uid_cache.bin, ...)

Exit status is non-zero, and no zip is left behind, if any check fails.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THUMBNAIL = "thumbnail.png"
THUMBNAIL_MIN = (512, 288)
THUMBNAIL_ASPECT = 16.0 / 9.0
SOURCE_EXTS = {"gd", "tscn", "tres", "json", "txt", "md", "gdshader", "gdshaderinc", "uid", "png", "svg"}
FORBIDDEN_NAMES = {"project.binary", "project.godot", "global_script_class_cache.cfg", "uid_cache.bin"}
# The repository's own machinery is not part of the mod.
SKIP_TOP = {".git", ".github", ".godot", "tools", "dist"}


def fail(message: str) -> None:
    print(f"[pack] {message}", file=sys.stderr)
    sys.exit(1)


def png_size(data: bytes) -> tuple[int, int]:
    """Width and height from the IHDR chunk; fails on anything that is not a PNG."""
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        fail(f"{THUMBNAIL} is not a readable PNG")
    return struct.unpack(">II", data[16:24])


def thumbnail_error(data: bytes) -> str:
    width, height = png_size(data)
    if width < THUMBNAIL_MIN[0] or height < THUMBNAIL_MIN[1]:
        return f"{THUMBNAIL} is {width}x{height}; it must be at least {THUMBNAIL_MIN[0]}x{THUMBNAIL_MIN[1]}"
    if abs(width / height - THUMBNAIL_ASPECT) > 0.02:
        return f"{THUMBNAIL} is {width}x{height}; it must be 16:9 (1280x720 is the usual size)"
    return ""


def collect() -> list[Path]:
    """Every file under the mod's folder that the packer takes, relative to ROOT."""
    picked = []
    for path in sorted(ROOT.rglob("*")):
        rel = path.relative_to(ROOT)
        if not path.is_file() or rel.parts[0] in SKIP_TOP:
            continue
        if path.name in FORBIDDEN_NAMES:
            print(f"[pack] skipped {rel} (would replace the game's own)")
            continue
        if path.suffix.lower().lstrip(".") not in SOURCE_EXTS:
            print(f"[pack] skipped {rel} (needs an export to carry its imported form)")
            continue
        picked.append(rel)
    return picked


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, help="zip to write (default: dist/xenu.synth_rift-<version>.zip)")
    args = ap.parse_args()

    manifest = json.loads((ROOT / "mod.json").read_text(encoding="utf-8"))
    mod_id = manifest.get("id", "")
    version = manifest.get("version", "")
    if not mod_id or not version:
        fail("mod.json needs an id and a version")
    thumb = ROOT / THUMBNAIL
    if not thumb.is_file():
        fail(f"no {THUMBNAIL}: every pack needs a preview image")
    err = thumbnail_error(thumb.read_bytes())
    if err:
        fail(err)

    out = args.out or ROOT / "dist" / f"{mod_id}-{version}.zip"
    out.parent.mkdir(parents=True, exist_ok=True)
    prefix = f"mods/{mod_id}/"
    members = collect()
    if not members:
        fail("nothing to pack")
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for rel in members:
            z.write(ROOT / rel, prefix + rel.as_posix())
    print(f"[pack] wrote {out} ({len(members)} files)")

    # Read it back the way the loader does, and fail loudly rather than ship a pack the Mods page cannot show.
    with zipfile.ZipFile(out) as z:
        names = set(z.namelist())
        try:
            found = json.loads(z.read(prefix + "mod.json"))
        except KeyError:
            out.unlink()
            fail(f"no {prefix}mod.json in the pack")
        if found.get("id") != mod_id or found.get("version") != version:
            out.unlink()
            fail("the manifest in the pack does not match mod.json")
        entry = str(found.get("entry", "")).removeprefix("res://")
        if entry not in names:
            out.unlink()
            fail(f"entry script {entry} is not in the pack")
        if prefix + THUMBNAIL not in names:
            out.unlink()
            fail(f"{THUMBNAIL} is not in the pack")
        err = thumbnail_error(z.read(prefix + THUMBNAIL))
        if err:
            out.unlink()
            fail(err)
    print(f"[pack] verified: {mod_id} {version}")
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
