#!/usr/bin/env python3
"""Put the packed mod on mod.io as a new file of the mod, with the release's version and notes.

  publish_modio.py --zip dist/xenu.synth_rift-0.18.0.zip --version 0.18.0 --notes RELEASE.md --repo OWNER/NAME
                   [--readme README.md] [--thumbnail res/thumbnail.png] [--dry-run]

Environment:
  MODIO_PAT      the OAuth2 access token (Read + Write) of an account that manages the mod. Required.
  MODIO_MOD_SLUG   the mod's name_id, the last part of mod.io/g/retroxr/m/<name_id>. Default: the repository's name.

The rules this follows (they are the same for every RetroXR mod):

  - The game is RetroXR, https://mod.io/g/retroxr/ (name_id "retroxr"), set statically; its numeric id is looked up.
  - The mod exists: a modfile is added with the version and the changelog (the release notes, so mod.io and GitHub
    say the same thing). Nothing else about the mod is touched; above all not `visible`, so a public mod stays public
    and a private one stays private.
  - The mod does not exist: it is created PRIVATE (visible=0), named like the repository, with the README as its
    description and res/thumbnail.png as its logo, then the file is added. These are placeholders for the author to
    fill in, which is why it is private. Only on creation; an existing mod's page is never rewritten.
  - A failure never fails the workflow: it is printed as a warning and written to the run's summary, and the exit
    status is 0. A failed logo is a warning too, and the mod is still created.

Only the standard library, so the workflow needs no install step.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import uuid
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.mod.io/v1"
GAME_NAME_ID = "retroxr"
SUMMARY_MAX = 250  # mod.io's limit on the one-line summary


class ModioError(Exception):
    pass


def multipart(fields: dict[str, str], files: dict[str, Path]) -> tuple[bytes, str]:
    """A multipart/form-data body and its content type."""
    boundary = uuid.uuid4().hex
    out = bytearray()
    for key, value in fields.items():
        out += f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode()
    for key, path in files.items():
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        out += (f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"; filename="{path.name}"\r\n'
                f"Content-Type: {mime}\r\n\r\n").encode()
        out += path.read_bytes() + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={boundary}"


def request(method: str, path: str, token: str, query: dict | None = None,
            fields: dict[str, str] | None = None, files: dict[str, Path] | None = None) -> dict:
    """One call to the API; returns the parsed JSON, raises ModioError with mod.io's own message."""
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    data = None
    if fields is not None or files:
        data, headers["Content-Type"] = multipart(fields or {}, files or {})
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            err = json.loads(body).get("error", {})
            body = f"{err.get('message', body)} {err.get('errors', '')}".strip()
        except ValueError:
            pass
        raise ModioError(f"{method} {path} -> HTTP {e.code}: {body[:600]}") from None
    except urllib.error.URLError as e:
        raise ModioError(f"{method} {path} -> {e.reason}") from None


def find_game(token: str) -> int:
    found = request("GET", "/games", token, {"name_id": GAME_NAME_ID}).get("data", [])
    if not found:
        raise ModioError(f"no game with name_id {GAME_NAME_ID!r} (is the token's account allowed to see it?)")
    return int(found[0]["id"])


def find_mod(token: str, game_id: int, name_id: str) -> dict | None:
    """The mod, or None. A private mod is not in the public listing, so the account's own mods are looked at too."""
    for path, query in ((f"/games/{game_id}/mods", {"name_id": name_id}),
                        ("/me/mods", {"game_id": game_id, "name_id": name_id})):
        try:
            found = request("GET", path, token, query).get("data", [])
        except ModioError:
            continue
        if found:
            return found[0]
    return None


def create_mod(token: str, game_id: int, name: str, name_id: str, summary: str, description: str,
               thumbnail: Path | None, warnings: list[str]) -> dict:
    """A private mod with placeholders. The logo is tried with the mod and, if mod.io refuses it, the mod is made
    without it (mod.io wants a logo, so that is a warning and the author adds one by hand)."""
    fields = {"name": name, "name_id": name_id, "summary": summary[:SUMMARY_MAX],
              "description": description, "visible": "0"}
    if thumbnail and thumbnail.is_file():
        try:
            return request("POST", f"/games/{game_id}/mods", token, fields=fields, files={"logo": thumbnail})
        except ModioError as e:
            warnings.append(f"the logo was refused, creating the mod without it: {e}")
    return request("POST", f"/games/{game_id}/mods", token, fields=fields)


def publish(args: argparse.Namespace, token: str, warnings: list[str]) -> str:
    name = args.repo.split("/")[-1]
    name_id = os.environ.get("MODIO_MOD_SLUG") or name
    notes = args.notes.read_text(encoding="utf-8") if args.notes and args.notes.exists() else ""
    if args.dry_run:
        return f"dry run: would add {args.zip.name} (version {args.version}) to mod {name_id!r} of game {GAME_NAME_ID!r}"

    game_id = find_game(token)
    mod = find_mod(token, game_id, name_id)
    created = mod is None
    if created:
        readme = args.readme.read_text(encoding="utf-8") if args.readme and args.readme.exists() else name
        manifest = json.loads(Path("mod.json").read_text(encoding="utf-8")) if Path("mod.json").exists() else {}
        mod = create_mod(token, game_id, name, name_id, manifest.get("description", name), readme,
                         args.thumbnail, warnings)
    mod_id = int(mod["id"])
    request("POST", f"/games/{game_id}/mods/{mod_id}/files", token,
            fields={"version": args.version, "changelog": notes, "active": "1"}, files={"filedata": args.zip})
    where = mod.get("profile_url") or f"mod {mod_id}"
    visibility = "" if created else f" (visibility left as it was)"
    return f"{'created PRIVATE mod and ' if created else ''}added {args.zip.name} as version {args.version} to {where}{visibility}"


def report(lines: list[str]) -> None:
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### mod.io\n\n" + "\n".join(f"- {line}" for line in lines) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zip", type=Path, required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--notes", type=Path, help="the release notes, used as the changelog")
    ap.add_argument("--repo", required=True, help="OWNER/NAME; NAME is the mod's name and, by default, its name_id")
    ap.add_argument("--readme", type=Path, help="description of a mod created now (never of an existing one)")
    ap.add_argument("--thumbnail", type=Path, help="logo of a mod created now")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    warnings: list[str] = []
    token = os.environ.get("MODIO_PAT", "")
    try:
        if not token and not args.dry_run:
            raise ModioError("MODIO_PAT is not set: nothing was published")
        if not args.zip.is_file():
            raise ModioError(f"{args.zip} does not exist")
        result = publish(args, token, warnings)
        lines = [result, *warnings]
        print(f"[modio] {result}")
    except ModioError as e:
        lines = [f"NOT published: {e}", *warnings]
        print(f"::warning title=mod.io::{e}")
    for w in warnings:
        print(f"::warning title=mod.io::{w}")
    report(lines)
    return 0  # a mod.io failure is a warning, never a failed release


if __name__ == "__main__":
    sys.exit(main())
