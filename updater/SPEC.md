# Updater

## Purpose

The Updater installs and updates every app in thooton/tablet on the user's
reMarkable 2, from the repository's rolling `latest` release. It is the only
way apps reach the tablet apart from SSH. The user opens it now and then with
a finger or pen, sees what has a newer version, taps UPDATE (or Update All),
closes it and taps Reload in AppLoad.

It must stay a single list with one detail box: quick to open, a few taps to
update, readable on e-ink. It must never become an app store with search,
categories, settings or accounts, never update anything by itself, and never
talk to anything but the release on GitHub.

## Not wanted

- A "Reload AppLoad to apply." notice or any reminder after an install
  (removed in 1.0.6). The user knows to Reload.
- Explanations, reassurance or instructions on screen ("Check that Wi-Fi is
  on, then try again", "Close the Updater, then ..."). Labels and facts only
  (1.0.2).
- `·` as a separator, or details set apart by bare spacing: details go in
  parentheses, independent facts are split with `|` (1.0.3, 1.0.4).
- A frame around the app's own icon (1.0.5).
- Calling `terminate()` or letting the backend exit while the window is open:
  it restarts the tablet's UI (1.0.1).
- A DONE that outlives the next check, or that hides a newer release (1.0.8).

## Screens

### The list (opens on launch)

**Header** (137 px, black 3 px rule under it): a ← icon and the title
"Updater" on the left, and on the right "Check Again", or "Checking…" while a
check runs or before the backend has answered.

- ← or the title closes the Updater. Closing never stops a download or an
  install (see Behaviour).
- Check Again fetches the release again. Tapping it while a check runs does
  nothing more. It works while apps install.

**Notice**: when the last check failed, a black-bordered box under the header
holds the error ("No connection." when offline). It goes away on the next
successful check. A failed check keeps the list from the last good one.

**Groups**, in this order, each shown only if it has apps, under a bold
capitals heading with a black rule:

- **UPDATES**: AppLoad has an older version of the app, or one with no
  version. "Update All" sits at the right of the heading while any app here is
  not already queued or installing; it queues all of those (not the Not
  Installed ones).
- **NOT INSTALLED**: AppLoad has no app with that id.
- **INSTALLED**: the same version as the release, or a newer one.

Within a group, apps are in alphabetical order of name, ignoring case.
An app that is waiting, downloading or installing stays in the group it was
in when queued, so rows don't move under the finger; once it finishes or
fails it moves to where its real status puts it (a finished update moves to
INSTALLED).

**Each row** (210 px, grey rule under it):

- The app's icon, 120 px; until the icon has been fetched, a black-bordered
  rounded tile with the name's first letter in capitals.
- The name (elided with … if too long).
- The version line:
  - Updates: `1.0.3 → 1.0.4 (24 Oct)`, or `1.0.4 (24 Oct)` when the installed
    copy has no version.
  - Not Installed: `1.0.4 (2.3 MB)`, the archive's size (KB below 1 MB,
    never less than 1 KB).
  - Installed: `1.0.4 (24 Oct)`; a newer copy than the release shows
    `1.1.0 (latest 1.0.4)`.
  - The date is that of the app's newest change, "24 Oct", with the year
    added when it isn't this year. No changes, no parentheses.
- One more line, elided to one line: the error of the last failed try (in
  semibold), else the newest change's text, else nothing.
- The capsule on the right:

| State | Capsule | Tapping it |
|---|---|---|
| Update available | UPDATE (black, white text) | queues it |
| Not installed | GET (black) | queues it |
| Queued | WAITING (outlined) | takes it out of the queue; the row goes back to UPDATE or GET |
| Downloading | `37%` (outlined, filling black from the left) | opens What's New |
| Unpacking and running install.sh | INSTALLING (outlined) | opens What's New |
| Just installed | DONE (outlined) | opens What's New |
| Last try failed | RETRY (black) | queues it again |
| Installed, nothing to do | no capsule | |

  The percentage moves in steps of at least 5 (and always shows 100), not
  every byte. DONE stays until the next check (Check Again, or reopening
  after a minute), then the row shows no capsule.

- Tapping anywhere else on a row opens What's New for that app.

**Paging**: the list is cut into pages that fit the screen; a group heading
never ends a page. With more than one page, the bottom 120 px show
`‹     2 / 3     ›`: tapping the left half goes back a page, the right half
forward. A sideways swipe of more than 110 px (more sideways than up or down)
turns the page: right to left goes forward. On the first page back does
nothing; on the last, forward does nothing. With one page the footer is not
drawn. If the list shrinks, the page shown is never past the last one.

**Empty and waiting**:

- Before the backend's first answer: "Checking…" in the header and in the
  list. The UI asks every 1.5 s; after about 9 s without an answer the list
  says "Backend not responding." and keeps asking; an answer replaces it.
- A check running with no list yet: "Checking…".
- A failed check with no list: only the notice, no text in the list.
- A release with no apps: "No apps."

### What's New (a box over the list)

Opened by tapping a row (or a busy capsule). A black-bordered box 58 px from
the sides and 200 px from the top, never taller than the screen less 400 px.

- Top: the app's name (elided) and × on the right, over a black rule.
- `Installed 1.0.3  |  Latest 1.0.4 (2.3 MB)`; when not installed, or
  installed with no version, just `Latest 1.0.4 (2.3 MB)`.
- If the last try failed: its error, in semibold, wrapped.
- WHAT'S NEW, then the app's newest changes, newest first, at most six: each
  a date line ("24 Oct (1.0.4)", the version only when the change has one) and
  the change's text, wrapped to at most three lines, then elided.
  No changes: no heading.
- A black capsule: GET (not installed), UPDATE (older version) or INSTALL
  AGAIN (installed, same or newer). It queues the app and closes the box.
  While the app is queued or installing there is no capsule.

× or a tap anywhere outside the box (header included) closes it. Taps inside
the box do nothing else; swipes don't turn the list's pages. The box follows
the app live: a download's progress, a failure, a finished install show as
they happen. If the app leaves the release, the box closes.

## Behaviour

**Where things are**: the release is
`https://github.com/thooton/tablet/releases/download/latest/`
(`manifest.json`, `<dir>.tar.gz`, `<dir>.png`). An app's installed version is
the `"version"` in `/home/root/xovi/exthome/appload/<id>/manifest.json`. The
Updater keeps nothing else: downloads, the unpacking folder, the lock and the
icon cache are under `/home/root/.cache/updater/`. Versions compare part by
part, numbers as numbers (1.2.10 is newer than 1.2.9).

**Checking**: opening the Updater checks, unless the backend checked under a
minute ago or is installing, in which case it shows the state it has. Every
fetch bypasses caches, so a release made a moment ago shows up. The manifest
gives up after 45 s. A manifest with a schema other than 1, or a bad entry,
is an error in the notice, and nothing is offered. Icons are fetched after
the list shows, only those not already cached, and appear when they arrive.

**Installing**: apps go one at a time in the order queued, the Updater itself
always last. For each: download (given up after a minute without data),
check size and SHA-256 against the manifest, unpack only plain files and
folders under `<dir>/` (it must contain `<dir>/install.sh`, and its
`app/manifest.json`, if any, must name the expected id), copy over
`/home/root/<dir>` keeping files the user added there, run
`sh /home/root/<dir>/install.sh`, then check AppLoad has the release's
version. Any failure gives RETRY and the reason; the app stays as it was
before the try unless install.sh itself failed partway. Downloads and
installs carry on with the window closed; reopening shows them where they
are. Two backends never install at once (a lock file).

**Failure states** are kept until retried, or until a newer release replaces
the version that failed. Nothing about jobs survives a tablet restart: after
one, the list is worked out afresh from the release and AppLoad.

**Updating itself**: the Updater installs its own update last. The running
backend keeps going; once the window has been closed for a few seconds and
nothing is installing, it exits, and the next open (after Reload in AppLoad)
starts the new one.

**Offline**: "No connection." in the notice; the last list, if any, stays and
its buttons still queue, and the downloads then fail with RETRY.

**Never**: updates on its own, on a timer, or in the background without a
tap; reminds the user to Reload.

## Look

What `../AGENTS.md` doesn't already say: Biblioteca's library look, IBM Plex
Sans (title 40 Medium, names 44 SemiBold, version and note lines 31, group
headings 32 Bold capitals spaced out). Black rules (3 px) under the header
and group headings, grey hairlines (2 px) between rows. Capsules are 236 by
84, fully rounded, bold capitals: filled black for an action, outlined for a
state. 60 px side margins.

## Open questions

1. What's New shows six changes, but the release carries ten per app, and with
   six long changes the box (capped at screen height less 400 px) cuts off
   its GET/UPDATE capsule at the bottom. Should it show fewer, scroll, or put
   the capsule at the top?
2. Errors on a row and in the notice are the backend's raw messages
   ("downloading x.tar.gz: unexpected EOF", "install.sh finished, but AppLoad
   has version ..."), long and technical next to the terse "No connection.".
   Should each failure get a short label?
3. The ← in the header closes the whole Updater (as does tapping the title).
   Is an × meant there, as Biblioteca and Flashcards now use for closing?
