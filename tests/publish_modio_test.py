#!/usr/bin/env python3
"""Offline test of tools/publish_modio.py: the API is replaced by a fake, so nothing reaches mod.io.

  python3 -I tests/publish_modio_test.py

Checks the two rules that must never break: an existing mod only gets a file (no call touches its visibility), and a
mod that does not exist is created PRIVATE. Also that a failure is a warning with exit status 0. Prints
`[modio-tests] N cases, M failed` and exits non-zero on a failure or when it ran no case.
"""
import argparse
import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import publish_modio as p  # noqa: E402

calls: list = []
EXISTING = None


def fake(method, path, token, query=None, fields=None, files=None, base=p.API):
    calls.append((method, path, dict(fields or {}), list(files or {}), base))
    if path == "/games":
        return {"data": [{"id": 7}]}
    if method == "GET":
        return {"data": [EXISTING] if EXISTING else []}
    if path.endswith("/mods"):
        return {"id": 99, "profile_url": "u"}
    return {}


def args(zip_path: Path, **kw) -> argparse.Namespace:
    base = dict(zip=zip_path, version="1.2.3", notes=None, repo="X/some-mod", readme=None, thumbnail=None, dry_run=False)
    return argparse.Namespace(**{**base, **kw})


def main() -> int:
    global EXISTING
    failed = cases = 0

    def check(name: str, ok: bool) -> None:
        nonlocal failed, cases
        cases += 1
        if not ok:
            failed += 1
            print(f"[modio-tests] FAIL {name}")

    p.request = fake
    with tempfile.TemporaryDirectory() as d:
        z = Path(d) / "m.zip"
        z.write_bytes(b"PK")
        os.environ.pop("MODIO_MOD_SLUG", None)

        EXISTING = {"id": 5, "profile_url": "u"}
        calls.clear()
        p.publish(args(z), "t", [])
        posts = [c for c in calls if c[0] == "POST"]
        check("existing mod: one POST, the file", len(posts) == 1 and posts[0][1] == "/games/7/mods/5/files")
        check("existing mod: version sent", posts[0][2]["version"] == "1.2.3")
        check("existing mod: visibility never sent", all("visible" not in c[2] for c in calls))

        check("writes go to the game's own domain", posts[0][4] == "https://g-7.modapi.io/v1")
        check("the game lookup uses api.mod.io", calls[0][4] == p.API)

        EXISTING = None
        calls.clear()
        p.publish(args(z), "t", [])
        created = [c for c in calls if c[0] == "POST" and c[1] == "/games/7/mods"]
        check("new mod: created private", len(created) == 1 and created[0][2]["visible"] == "0")
        check("new mod: file added to it", any(c[1] == "/games/7/mods/99/files" for c in calls))
        check("new mod: named like the repo", created[0][2]["name_id"] == "some-mod")

        os.environ["MODIO_MOD_SLUG"] = "other-slug"
        calls.clear()
        p.publish(args(z), "t", [])
        check("MODIO_MOD_SLUG overrides the name_id", [c for c in calls if c[1] == "/games/7/mods" and c[0] == "POST"][0][2]["name_id"] == "other-slug")

        os.environ.pop("MODIO_PAT", None)
        sys.argv = ["x", "--zip", str(z), "--version", "1", "--repo", "X/y"]
        # main() prints the warning as a GitHub annotation; here it is expected, so it is kept out of the run's log
        # (and out of GITHUB_STEP_SUMMARY), where it would read as a real failure of the release.
        os.environ.pop("GITHUB_STEP_SUMMARY", None)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = p.main()
        check("no token: a warning, exit status 0", status == 0 and "MODIO_PAT is not set" in out.getvalue())
    print(f"[modio-tests] {cases} cases, {failed} failed")
    return 1 if failed or cases == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
