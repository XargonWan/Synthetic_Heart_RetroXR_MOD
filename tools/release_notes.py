#!/usr/bin/env python3
"""Write the notes of a release from the commits made since the previous release.

Adapted from MOG-Server's scripts/release_notes.py. The version is computed from the history (--next-version): the previous release is
the highest vX.Y.Z tag reachable from HEAD (none: the whole history, and the version is the one in mod.json), and the
commits since it decide the bump: a breaking change raises the minor while the major is 0 and the major from 1 on, a
feat the minor, a fix, a perf or a subject that is not a conventional commit the patch. Only commits that appear in the
notes count, so chore, docs, ci and the like release nothing. Each commit becomes a line without its type, with its scope in
front and its hash, a link to the commit, at the end:

  ## Changes   feat, and a breaking change
  ## Fixes     fix, perf, and a subject that is not a conventional commit
  (left out)   chore, doc, docs, res, style, test, refactor, ci, build

  release_notes.py --next-version [--base 0.18.0]        # prints the version to release, or nothing if none is due
  release_notes.py --repo OWNER/NAME --version 0.15.0 [--header FILE] [--body OUT]

--body is the text of the GitHub release: the header file ({version} in it is the version), the sections and a link
to compare the two releases.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

SUBJECT = re.compile(r"^(?P<type>\w+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<text>.+)$")
BREAKING_FOOTER = re.compile(r"^BREAKING[ -]CHANGE:", re.MULTILINE)
RELEASE_TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
CHANGES = ("feat",)
FIXES = ("fix", "perf")
NOTHING = "Nothing worth noting in this version."


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def previous_release() -> str | None:
    """The highest vX.Y.Z tag reachable from HEAD."""
    tags = []
    for tag in git("tag", "--merged", "HEAD").split():
        if m := RELEASE_TAG.match(tag):
            tags.append((tuple(int(n) for n in m.groups()), tag))
    return max(tags)[1] if tags else None


def commits_since(tag: str | None) -> list[tuple[str, str]]:
    """(hash, whole message) of every non-merge commit since the tag, newest first."""
    log = git("log", "--no-merges", "--format=%H%x1f%B%x00", f"{tag}..HEAD" if tag else "HEAD")
    out = []
    for entry in filter(None, (e.strip() for e in log.split("\0"))):
        sha, _, message = entry.partition("\x1f")
        out.append((sha, message.strip()))
    return out


def sort(commits: list[tuple[str, str]]) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """The lines of Changes and of Fixes, each as (text, hash); the commits arrive newest first."""
    changes, fixes = [], []
    for sha, message in commits:
        subject = message.splitlines()[0] if message else ""
        m = SUBJECT.match(subject)
        if m is None:  # not a conventional commit: a patch, so listed as a fix
            fixes.append((subject, sha))
            continue
        text = f"{m['scope']}: {m['text']}" if m["scope"] else m["text"]
        if m["bang"] or BREAKING_FOOTER.search(message):
            changes.append((text, sha))
        elif m["type"] in CHANGES:
            changes.append((text, sha))
        elif m["type"] in FIXES:
            fixes.append((text, sha))
    return changes, fixes


def next_version(previous: str | None, commits: list[tuple[str, str]], base: str | None = None) -> str | None:
    """The version to release after `previous`, or None when no commit since it belongs in the notes.

    With no previous release the version is `base` (the first release is what mod.json says)."""
    if previous is None:
        return base if commits and base else None
    major, minor, patch = (int(n) for n in RELEASE_TAG.match(previous).groups())
    level = 0  # 0 nothing, 1 patch, 2 minor, 3 major
    for _sha, message in commits:
        subject = message.splitlines()[0] if message else ""
        m = SUBJECT.match(subject)
        if m is None:
            level = max(level, 1)
        elif m["bang"] or BREAKING_FOOTER.search(message):
            level = max(level, 3)
        elif m["type"] in CHANGES:
            level = max(level, 2)
        elif m["type"] in FIXES:
            level = max(level, 1)
    if level == 3 and major == 0:
        level = 2  # before 1.0 a breaking change raises the minor
    if level == 0:
        return None
    if level == 3:
        return f"{major + 1}.0.0"
    if level == 2:
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def line(text: str, sha: str, repo: str) -> str:
    return f"- {text} [[{sha[:7]}](https://github.com/{repo}/commit/{sha})]"


def sections(commits: list[tuple[str, str]], repo: str) -> str:
    changes, fixes = sort(commits)
    parts = []
    for title, found in (("Changes", changes), ("Fixes", fixes)):
        if found:
            parts.append(f"## {title}\n\n" + "\n".join(line(text, sha, repo) for text, sha in found))
    return "\n\n".join(parts)


def body(header: str, notes: str, repo: str, version: str, previous: str | None) -> str:
    notes = notes or NOTHING
    parts = [header.strip(), notes] if header.strip() else [notes]
    if previous:
        parts.append(f"**See changes**: https://github.com/{repo}/compare/{previous}...v{version}")
    return "\n\n".join(parts) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--next-version", action="store_true", help="print the version to release and exit (nothing: none due)")
    ap.add_argument("--base", help="with --next-version: the version of a first release, when there is no tag yet")
    ap.add_argument("--repo", help="OWNER/NAME, for the links")
    ap.add_argument("--version", help="the version being released, without the v")
    ap.add_argument("--header", type=Path, help="text put before the sections in the release body")
    ap.add_argument("--body", type=Path)
    args = ap.parse_args()

    previous = previous_release()
    if args.next_version:
        found = next_version(previous, commits_since(previous), args.base)
        if found:
            print(found)
        return 0
    if not args.repo or not args.version:
        ap.error("--repo and --version are required to write the notes")
    notes = sections(commits_since(previous), args.repo)
    header = ""
    if args.header and args.header.exists():
        header = args.header.read_text(encoding="utf-8").replace("{version}", args.version)
    text = body(header, notes, args.repo, args.version, previous)
    if args.body:
        args.body.write_text(text, encoding="utf-8")
        print(f"[notes] wrote {args.body} (previous release: {previous or 'none'})")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
