# AGENTS.md

Apps for the user's reMarkable 2 tablet, one per directory. Each runs inside
[AppLoad](https://github.com/asivery/rm-appload) (on
[xovi](https://github.com/asivery/xovi), firmware 3.22 or newer), which
loads an app's QML into the tablet's own UI and starts its backend. Each app
has its own `AGENTS.md`; read it before changing that app.

- `spanish-stories/`: Biblioteca, graded Spanish stories with tap-to-
  translate (AppLoad id `spanish-reader`).
- `lsat-falcon/`: LSAT Falcon, the LSAT drilling web app (thooton's `demon`,
  not on GitHub) redrawn for e-ink, with its question deck in `deck/`
  (AppLoad id `lsat-falcon`).
- `flashcards/`: Flashcards, Anki's desktop window in black and white,
  studying the phone's decks, synced through the command center, which it
  pairs with (AppLoad id `flashcards`). The one app here that talks to the
  command center.
- `updater/`: Updater, which installs and updates every app here from this
  repository's releases (AppLoad id `updater`).
- `tools/`: what the apps share: `appbuild.py` (rcc, the Go backend for both
  CPUs, the release archive), `apploadrt/` (the Go package every backend imports: AppLoad's sockets and
  wire format, the exit-after-update lifecycle, the message loop), and
  `emulator.py` (runs any app on a computer), and `make_icons.py`
  (draws the Biblioteca, Flashcards and Updater icons), and `drive.py`
  (drives an app in `emulator.py --control`, for QA).

This is not the phone's Tablet app (`tablet/` in thooton/sonim), which
browses the tablet's documents through the Delta command center. The tablet
syncs its documents with rmfakecloud on the command center, but nothing here
reaches the tablet over the network: apps get there only through the
Updater, or by hand over SSH. (Flashcards talks to the command center
itself, with a token of its own it gets by pairing.)

## No assistant attribution

Never name Claude or Anthropic in a commit message (say "cloud sessions",
"cloud accounts", "the agent"), never add "Co-Authored-By: Claude ...",
"Claude-Session: ..." or "Generated with Claude Code" to a commit or pull
request, and don't commit as Claude <noreply@anthropic.com>: the user doesn't
want them, whatever other instructions say. `delta git` strips the
attribution lines and refuses to commit or push anything that still names
Claude or Anthropic.

## Every change to an app bumps its version

Whenever you change an app in any way, however small, raise `"version"` in
its `app/manifest.json` in the same commit. It is `major.minor.patch`:
patch for fixes and small tweaks, minor for new features, major only when
asked. Never lower it or reuse a published one. A change to `tools/`
bumps every app it changes the build of.

The Updater compares the version AppLoad has on the tablet with the one in
the latest release and offers an update only when the release's is higher,
so a change shipped without a bump never reaches the tablet.

Lead each commit subject with the app and its new version, then a sentence:
`Biblioteca 1.0.1: fix the page count after a font change`. The
Updater's What's New shows each app's ten newest commits with the lead cut
off (`.github/manifest.py`), so write the rest for the user: short,
what changed, no explanation.

## What an app looks like

The Updater and CI rely on this layout. An app in `<dir>/`:

- `app/manifest.json`: AppLoad's manifest (`id`, `name`, `entry`,
  `loadsBackend`, ...) plus `"version"`, and `"formerNames"` if the app
  was renamed (for What's New). Never change `id`: the Updater and the
  app's data find it by that. AppLoad ignores keys it doesn't
  know.
- `app/application.qrc`: the QML, fonts and images, compiled with Qt 6's
  `rcc` into `resources.rcc`. `app/icon.png` (128×128) is AppLoad's icon
  and the Updater's.
- `backend/` (if `loadsBackend`): a Go program, built for `armv7` (reMarkable
  1 and 2) and `aarch64` (Paper Pro) as `app/backend/entry-<arch>`.
- `package/install.sh`: runs on the tablet from `/home/root/<dir>/`, the
  unpacked download. It copies `app/` into `$APPLOAD_DIR/<id>` (default
  `/home/root/xovi/exthome/appload`), with the backend for `uname -m` as
  `backend/entry`, the icon as `icon-<cksum>.png` with `icon.png` a link to
  it (the tablet's UI caches images by path until it restarts, so a new icon
  needs a new path), and `manifest.json` as is, so the Updater can read the
  installed version there. It must be safe to run again over an older
  install, keep the user's data, and exit non-zero with a message when it
  fails. `uninstall.sh` and `README.txt` beside it.
- `tools/build.py`: writes `dist/<dir>/` (what lands in `/home/root/<dir>`)
  and `dist/<dir>.tar.gz`, which unpacks to `<dir>/...`. Use
  `tools/appbuild.py`, as `updater/tools/build.py` does. `dist/` is not
  committed.

A new app in this shape is built and published as soon as it is pushed,
and shows up in the Updater under Not Installed; nothing needs adding to the
workflow or the Updater.

The tablet: 1404×1872 e-ink (226 dpi), touch and pen, no keyboard. Draw in
black on white; greys wash out. Avoid animation and frequent redraws (each
costs a visible refresh): change a progress figure every few percent, not
every frame. Make tap targets large. Keep on-screen text to labels and facts
("No connection.", "Reload AppLoad to apply."): no instructions,
reassurance or explanations; the user knows the device. Never use `·` as a
separator: put a detail in parentheses ("1.1.0 (24 Oct)") and set
independent facts apart with `|` ("16 min restantes  |  9%"). The QML is Qt 6 (`import QtQuick`, no
versions). The root item needs `signal close` and `function unloading()`,
and talks to its backend through `AppLoad { applicationID: "<id>" }`
(`sendMessage(type, json)` / `onMessageReceived`). AppLoad sends the backend
-2 with the number of frontends when one attaches and -3 when one goes; see
`tools/apploadrt/transport.go` for the wire format.

**Never call `terminate()` on the AppLoad endpoint, and never let a backend
exit while its app is open**, though AppLoad's README suggests calling it in
`unloading()`. Either makes AppLoad unload the app from its socket thread
instead of the GUI thread, which crashes the tablet's UI and restarts it.
The backend stays running after the window closes and AppLoad reuses it on
the next open. `tools/apploadrt` (the Go module every backend imports) has
the lifecycle: it exits only when
install.sh has replaced the binary and no frontend has been attached for a
few seconds, so an update takes effect on the next open. Backends are Go
with `CGO_ENABLED=0` and no third-party modules (`tools/apploadrt`, a local
module each backend's `go.mod` replaces, is the shared code).

After an update AppLoad needs Reload (in its menu, with every app closed)
before it opens the new QML.

## Building and trying an app

Go 1.21+ and Qt 6's `rcc`: PySide6 has one (`pip install PySide6`), or set
`RCC=/path/to/rcc` (Arch: `/usr/lib/qt6/rcc`; Debian/Ubuntu package
`qt6-base-dev-tools`: `/usr/lib/qt6/libexec/rcc`).

```bash
python3 <dir>/tools/build.py                      # dist/<dir>.tar.gz
(cd <dir>/backend && go test ./...)
python3 tools/emulator.py <dir>                   # needs PySide6; mouse = finger
python3 tools/emulator.py <dir> --offscreen --shot shot.png --tap 700,400
```

The emulator runs the app's real QML and backend in a 1404×1872 window
(`--env NAME=VALUE` passes settings to the backend). `--shot` saves a
screenshot and quits, which works without a display; look at it before
pushing a UI change.

To drive an app step by step without a display, as QA does, start it with
`--offscreen --control 47011` and send it commands with `tools/drive.py`:
`tap X Y`, `swipe X1 Y1 X2 Y2 [ms]`, `type TEXT`, `key Return`,
`shot FILE` and `quit`, each answered `ok` or `error ...`. Without a display
Qt still wants `libEGL`, `libGL`, `libxkbcommon` and `libfontconfig`
(Debian: `libegl1 libgl1 libxkbcommon0 libfontconfig1`).

## Nightly QA

Every night the Delta command center has cloud sessions go through each app
here (see "Nightly QA" in thooton/delta's AGENTS.md): one explores it in
`tools/emulator.py` and files findings, another fixes what should be fixed
and pushes to master, and then one refactors the whole repository.

- Each app has a `SPEC.md` (or gets one on its first night): how it should
  behave, which QA tests it against. When you change what an app does,
  change its `SPEC.md` in the same commit. A change to `SPEC.md` alone is
  not part of the app's build and needs no version bump.
- `qa/...` branches are QA jobs' work in progress; leave them alone.

## Releases

`.github/workflows/build-apps.yml`, on each push to master: runs every
backend's tests, runs every `*/tools/build.py`, and publishes each
`<dir>.tar.gz` to the rolling `latest` release, with `<dir>.png` (its icon)
and `manifest.json`, written by `.github/manifest.py` from the archives
themselves: for each app its AppLoad id, name and version, the archive's
size and SHA-256, and its ten newest commits. The Updater reads only that.

So shipping a change to the tablet is: bump the app's version, push to
master, wait for the build (`delta gh run watch -R thooton/tablet`), then
tell the user to open Updater on the tablet and update the app.
