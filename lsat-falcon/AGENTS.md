# LSAT Falcon for reMarkable

The [LSAT Falcon](../demon) drilling app on a reMarkable 2: the same screens,
fonts and layout as the web app open in portrait, redrawn for e-ink. It has
every question in the deck (7,626 LR and RC questions; 6,363 drilled, with
the held-out tests reserved for practice tests), with answer statistics and
explanations, the filters and deck outline, and timed practice tests with a
scaled score.

## What changed for the tablet

* **Size.** Everything is the web app's CSS pixels × 2.25 (`app/ui/js/theme.js`),
  so the tablet is a 624 × 832 px viewport: the web app's stacked, phone-width
  layout. The reading text is 16 px → 36 px on a 1.5 line.
* **Fonts.** Roboto, cut from the web app's own variable font into static
  weights ("Falcon Roboto", see `tools/generate_assets.py`). The reading
  weight is 400 instead of 375: e-ink thins strokes. → ← ↑ ↓ ≠ ✓ are added
  from Noto Sans Math, because Roboto doesn't have them and the explanations use them.
* **Black and white.** Navy and green become black. Anything that carries
  state is black against white: selected chips, the credited answer (heavy
  border and ✓), a wrong pick (grey border and ✗), and in the deck list a
  dot for right and a ring for wrong. Greys are only decoration.
* **No scrolling, no animation.** Panes turn a page at a time: swipe up or
  down. The thin bar on the right is the web app's scrollbar. A
  reading-comp question opens on the question, with its passage a swipe
  back. Tapping a quoted phrase in the stem centres it in the passage.
* **Left out:** sound, dark mode, Ask AI (no clipboard), find in passage
  (no keyboard), the download button, and the copy buttons in the credits.
  The header's last button closes the app. The practice-test clock shows
  whole minutes, so the screen doesn't redraw every second.
* **Saved:** the filters, shuffle, the held-out switch and your place (the
  web app's `?q=`), in `~/.local/share/lsat-falcon/state.json`. As on the
  web, answers are not saved.

## Install

With the Updater on the tablet (`../updater`), tap **GET** beside LSAT
Falcon. By hand: download `lsat-falcon.tar.gz` from the
[latest release](https://github.com/thooton/tablet/releases/tag/latest), then

```bash
scp lsat-falcon.tar.gz root@10.11.99.1:
ssh root@10.11.99.1
cd /home/root && tar -xzf lsat-falcon.tar.gz && sh lsat-falcon/install.sh
```

Then open AppLoad, tap **Reload**, and tap **LSAT Falcon**.
`sh /home/root/lsat-falcon/uninstall.sh [--purge]` removes it.

## Building

CI builds `dist/lsat-falcon.tar.gz` on every push to master and publishes it
to the `latest` release. **Raise `"version"` in `app/manifest.json` with
every change** (see `../AGENTS.md`). The deck is vendored in `deck/`
(`questions.json.gz`, `conversion.js`, `held-out.js`, copied from the web
app), so the build needs only Go 1.21+ and Qt 6's `rcc`:

```bash
python tools/build.py             # -> dist/lsat-falcon/, .tar.gz, .zip
python tools/update_deck.py ../demon   # after `npm run build:questions` in the web app; then bump the version
python tools/generate_assets.py   # fonts and icons into app/ui (needs PySide6, fontTools and ../demon; already generated)
```

`build.py` runs `tools/build_data.py`, which turns the deck into
`build/data/`: `meta.json`, a compact index the UI gets at startup, and
`content.dat`/`content.idx`, which hold the question text and are read one
question at a time.

The backend keeps running after the app closes and AppLoad reuses it; the
app never calls `terminate()`, which crashes the tablet's UI (see
`../AGENTS.md`). `../tools/appload/lifecycle.go` makes it exit once an update has
replaced it and the app is closed.

## Emulator and tests

```bash
python3 ../tools/emulator.py .      # the app in a 1404 × 1872 window (see ../AGENTS.md), after build.py
python3 emulator/test_app.py        # end-to-end UI test, screenshots in build/emulator/test-shots/
cd backend && go test ./...         # backend: deck, state, chunking
python3 emulator/fake_appload.py APP_DIR DATA_DIR   # the real unix-socket protocol
```

## How it works

```
app/ui/main.qml            root: AppLoad messages, question cache, routing
app/ui/DrillView.qml       drilling (App.jsx)
app/ui/PracticeTest.qml    practice tests (PracticeTest.jsx and its screens)
app/ui/components/         the web app's components, one QML file each
app/ui/js/deck.js          filters, shuffle, keys, scoring (data.js, filters.js, …)
app/ui/js/format.js        prose, emphasis, quotes, explanations → rich text
backend/                   Go: serves the deck, saves settings and position
```

| Type | Direction | Meaning |
|---|---|---|
| 1 → 100, 101 | UI → backend → UI | hello: saved state, then the index |
| 2 → 102 | | one question's text and its passage |
| 3 | | save settings |
| 4 | | save position |
| 190 | backend → UI | a piece of a reply too big for one socket packet |
| 199 | backend → UI | error |
