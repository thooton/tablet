# AGENTS.md

The Updater: an AppLoad app that installs and updates every app in this
repository on the tablet, from the rolling `latest` release. The tablet's
counterpart of the Updater in thooton/sonim, drawn like Biblioteca's
library (white paper, black ink, IBM Plex Sans).

## How it works

CI publishes each app as `<dir>.tar.gz` and `<dir>.png` beside
`manifest.json` (see `../AGENTS.md` and `../.github/manifest.py`). On
opening, the backend fetches `manifest.json` from
`https://github.com/thooton/tablet/releases/download/latest/` (with a query
never used before and `Cache-Control: no-cache`, so Check Again sees a
release made a moment ago) and the icons it hasn't cached, and compares each
app's version with the `"version"` in AppLoad's copy of its manifest,
`/home/root/xovi/exthome/appload/<id>/manifest.json` (`App.status` in
`backend/app.go`; versions compare part by part, numbers as numbers):

- **Updates**: AppLoad has an older version, or a copy with no version
  (installed before apps had one).
- **Not Installed**: AppLoad has no app with that id.
- **Installed**: the same version, or newer than the release.

An app keeps its group while it installs (`Job.from`), so rows don't move
under the finger. UPDATE, GET and Update All queue apps; they go one at a
time, the Updater itself last since its install.sh replaces it. For each:
download to `~/.cache/updater/`, check the size and SHA-256 against the
manifest, unpack into a staging folder (only plain files and folders under
`<dir>/`; it must hold `<dir>/install.sh` and, if it has
`app/manifest.json`, the id the manifest names), move the files over
`/home/root/<dir>` (replacing files of the same name, leaving the rest, such
as the user's own stories), run `sh /home/root/<dir>/install.sh` with
`APPLOAD_DIR` set, and check that AppLoad now has the release's version.
Then the list asks the user to close the Updater and tap Reload in
AppLoad, which AppLoad refuses while any app is open, and which it needs
before it opens new QML.

Tapping a row opens What's New (the versions, the newest commits, why the
last try failed, and GET, UPDATE or INSTALL AGAIN). WAITING cancels a
queued app.

Closing the Updater leaves the backend running (AppLoad reuses it; see
`backend/lifecycle.go` and "Never call terminate()" in `../AGENTS.md`), so
installs carry on, and reopening shows them; it checks again if the last
check is over a minute old and nothing is installing. Once the Updater has
updated itself, its old backend exits when the window has been closed for a
few seconds and nothing is running, and the next open starts the new one.
A flock on `~/.cache/updater/lock` keeps two backends from installing at
once.

## Messages

| Type | Direction | Meaning |
|---|---|---|
| 1 | UI → backend | check for updates (ignored while one runs) |
| 2 | | `{"apps": [dir, ...]}`: install them |
| 3 | | send the state |
| 4 | | `{"app": dir}`: take a waiting app out of the queue |
| 101 | backend → UI | the whole state (`State` in `backend/app.go`), after every change |

The backend also checks when a frontend attaches (-2), as above.

## Layout

- `backend/`: `release.go` (manifest.json, downloads), `install.go`
  (versions, unpacking, merging, running install.sh), `app.go` (the state,
  the queue), `main.go`, `lifecycle.go` (when to exit after an update),
  `transport.go` (AppLoad's protocol). The last two are the same as Spanish
  Reader's. `UPDATER_HOME`, `UPDATER_APPLOAD` and `UPDATER_RELEASE`
  override `/home/root`, the AppLoad folder and the release URL, for tests
  and the emulator.
- `app/ui/`: `main.qml` (header, notices, the paged list), `components/`
  (`AppRow`, `Capsule`, `NotesBox`, `IconButton`), `js/format.js` (what
  each row says), `js/theme.js`.
- `package/`: install.sh, uninstall.sh, README.txt (also the first,
  by-hand install).
- `tools/build.py`, `tools/generate_assets.py` (the icon; needs PySide6).

## Testing

```bash
(cd backend && go test ./...)    # versions, unpacking, a full check and install against a local release
python3 tools/build.py
```

To try it end to end, serve a release folder (CI's `release/`, or one made
with `python3 .github/manifest.py` from built archives) and point the
emulator at it with a fake home:

```bash
python3 -m http.server 18931 --directory release &
UPDATER_MACHINE=armv7 SPANISH_READER_MACHINE=armv7 python3 tools/emulator.py updater \
    --env UPDATER_HOME=/tmp/fake-home --env UPDATER_RELEASE=http://127.0.0.1:18931/
```

(`*_MACHINE` makes install.sh pick a tablet backend on a PC.) The real
tablet differences, TLS to GitHub and the SEQPACKET socket, are covered by
Go's own TLS (it reads `/etc/ssl/certs`) and `packet_linux_test.go`.
