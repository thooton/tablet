#!/usr/bin/env python3
"""Writes manifest.json for the "latest" release: everything the Updater needs.

    python3 .github/manifest.py <release dir>

For each <dir>.tar.gz in the release directory (an app's build, named for
its directory in the repository), read from the archive itself, so it can't
drift from the build: the AppLoad id, name and version in
<dir>/app/manifest.json, and the icon, <dir>/app/icon.png, which is written
beside it as <dir>.png. Then the archive's size and SHA-256, and what's new,
from the newest commits that touched the app's directory (git log, so CI
needs the history: checkout with fetch-depth 0).

A commit subject leads with the apps it changes ("Spanish Reader 1.0.1: fix
the page count"). That lead is cut off, leaving the sentence ("Fix the page
count."), and a version in it is kept beside the text.
"""

import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tarfile

NOTES = 10

NAME = r"[A-Za-z][\w-]*(?: [A-Za-z][\w-]*)*(?: v?\d+(?:\.\d+)*)?"
LEAD = re.compile(r"^(%s(?:\s*(?:,|&|/|\band\b)\s*%s)*):\s*(.+)$" % (NAME, NAME))
NAMED_VERSION = re.compile(r"^(.*?) v?(\d+(?:\.\d+)*)$")


def read_app(path, app):
    """The app's manifest.json and icon from inside its archive."""
    with tarfile.open(path, "r:gz") as t:
        names = set(t.getnames())
        if f"{app}/install.sh" not in names:
            sys.exit(f"{path} has no {app}/install.sh")
        try:
            manifest = json.load(t.extractfile(f"{app}/app/manifest.json"))
        except KeyError:
            sys.exit(f"{path} has no {app}/app/manifest.json")
        icon = t.extractfile(f"{app}/app/icon.png").read() if f"{app}/app/icon.png" in names else None
    for key in ("id", "name", "version"):
        if not manifest.get(key):
            sys.exit(f"{app}/app/manifest.json has no {key!r}; every app needs one (see AGENTS.md)")
    return manifest, icon


def lead_of(subject, known):
    """The subject's lead, if every name in it is an app's (its directory or
    its name, any case), else None."""
    lead = LEAD.match(subject)
    if not lead:
        return None
    for part in re.split(r"\s*(?:,|&|/|\band\b)\s*", lead.group(1)):
        m = NAMED_VERSION.match(part)
        if (m.group(1) if m else part).lower() not in known:
            return None
    return lead


def note(names, known, sha, time, subject):
    """One commit as the Updater shows it."""
    out = {"commit": sha, "time": time}
    lead = lead_of(subject, known)
    text = lead.group(2).strip() if lead else subject
    text = text[:1].upper() + text[1:]
    if text and text[-1:] not in ".!?…":
        text += "."
    out["text"] = text
    if lead:
        for part in re.split(r"\s*(?:,|&|/|\band\b)\s*", lead.group(1)):
            m = NAMED_VERSION.match(part)
            if m and m.group(1).lower() in names:
                out["version"] = m.group(2)
    return out


def notes(app, label, known):
    if not os.path.isdir(app):
        return []
    log = subprocess.run(
        ["git", "log", "--no-merges", "-n", str(NOTES), "--format=%h%x00%cI%x00%s", "--", app],
        check=True, capture_output=True, text=True).stdout
    names = {app.lower(), (label or "").lower()}
    out = []
    for line in log.splitlines():
        sha, time, subject = line.split("\0", 2)
        out.append(note(names, known, sha, time, subject.strip()))
    return out


def main():
    release = sys.argv[1]
    apps = {}
    read = {}
    for file in sorted(os.listdir(release), key=str.lower):
        if file.endswith(".tar.gz"):
            app = file[: -len(".tar.gz")]
            read[app] = read_app(os.path.join(release, file), app)
    known = {app.lower() for app in read} | {m["name"].lower() for m, _ in read.values()}

    for app, (manifest, icon) in read.items():
        file = app + ".tar.gz"
        path = os.path.join(release, file)
        with open(path, "rb") as f:
            data = f.read()
        entry = {
            "id": manifest["id"],
            "name": manifest["name"],
            "version": manifest["version"],
            "archive": file,
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
        if icon:
            with open(os.path.join(release, app + ".png"), "wb") as f:
                f.write(icon)
            entry["icon"] = app + ".png"
            entry["iconSha256"] = hashlib.sha256(icon).hexdigest()
        entry["notes"] = notes(app, manifest["name"], known)
        apps[app] = entry

    commit = subprocess.run(["git", "rev-parse", "HEAD"], check=True,
                            capture_output=True, text=True).stdout.strip()
    manifest = {
        "schema": 1,
        "built": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "commit": commit,
        "apps": apps,
    }
    with open(os.path.join(release, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    main()
