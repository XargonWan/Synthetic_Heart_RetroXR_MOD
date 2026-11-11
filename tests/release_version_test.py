#!/usr/bin/env python3
"""Test of the version tools/release_notes.py computes from the commits since the previous release.

  python3 -I tests/release_version_test.py

Prints `[version-tests] N cases, M failed`; exits non-zero on a failure or when it ran no case.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
from release_notes import next_version as nv  # noqa: E402


def c(*subjects: str) -> list:
    return [("0" * 40, s) for s in subjects]


CASES = [
    ("feat raises the minor", nv("v0.18.0", c("feat(x): a", "fix: b")), "0.19.0"),
    ("fix raises the patch", nv("v0.18.0", c("fix(x): a", "chore: b")), "0.18.1"),
    ("perf raises the patch", nv("v0.18.0", c("perf: a")), "0.18.1"),
    ("a subject that is not conventional is a patch", nv("v0.18.0", c("tweak the thing")), "0.18.1"),
    ("chore, docs and ci release nothing", nv("v0.18.0", c("chore: a", "docs: b", "ci: c")), None),
    ("no commits release nothing", nv("v0.18.0", []), None),
    ("breaking under 1.0 raises the minor", nv("v0.18.0", c("fix!: a")), "0.19.0"),
    ("breaking footer from 1.0 raises the major", nv("v1.2.3", c("fix: a\n\nBREAKING CHANGE: b")), "2.0.0"),
    ("first release is the base", nv(None, c("feat: a"), "0.18.0"), "0.18.0"),
    ("first release with no commits is nothing", nv(None, [], "0.18.0"), None),
]


def main() -> int:
    failed = 0
    for name, got, want in CASES:
        if got != want:
            failed += 1
            print(f"[version-tests] FAIL {name}: got {got!r}, want {want!r}")
    print(f"[version-tests] {len(CASES)} cases, {failed} failed")
    return 1 if failed or not CASES else 0


if __name__ == "__main__":
    sys.exit(main())
