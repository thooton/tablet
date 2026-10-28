# AGENTS.md

Flashcards: Anki's desktop window on the reMarkable, in black and white,
studying the same decks as Flashcards on the phone (`flashcards/` in
thooton/sonim). Read `../AGENTS.md` first.

## How it works

The decks live on the Delta command center (`/flashcards/sync`, see
`flashcards.go` in thooton/delta), as AnkiWeb keeps Anki's. The backend
keeps the tablet's copy in `~/.local/share/flashcards/collection.json`,
studies from it offline, and syncs when the app opens (if the last sync is
over a minute old), 20 seconds after the last answer, after an options
change, when the app closes, and from Sync in the toolbar. Each record
carries `mod` (device milliseconds) and the collection a `usn`; where the
phone and the tablet both changed a card, the later answer wins.

**Pairing.** The tablet can't type the delta token, so it pairs: unpaired,
the backend asks `POST /flashcards/pair` for a code and the app shows it;
the user types it on the website's Tablet page; the backend polls
`GET /flashcards/pair/{secret}` and keeps the token it gets (which reaches
only the flashcards) in `login.json` beside the collection. A 401 later
(unpaired on the website) forgets it and shows a new code. The command
center's address is `defaultServer` in `backend/center.go`
(`FLASHCARDS_SERVER` overrides it, for the emulator).

**Scheduling** is the phone's, ported: `backend/fsrs.go` is java-fsrs's
`Scheduler` line for line (FSRS-6 defaults, steps 1m 10m and 10m, fuzz
seeded with java.util.Random from the card's id and last review, as the
phone seeds it), and `backend/session.go` is `ReviewSession` (learning,
then today's reviews with new cards mixed in among them, then learn-ahead;
new cards a number a day, or on AUTO enough to bring New + Learning + Due
up to 20, which only decides when a new card comes in;
`TestNewCardsMixIntoReviews` pins the order the phone gives). `testdata/java-fsrs.json`
is 720 answers made by the phone's own scheduler, and
`TestReviewMatchesThePhone` replays them: any change to the scheduling on
either side must keep it passing (regenerate it from the phone's core when
the phone's scheduler changes on purpose). The day rolls over at 4am in
the phone's time zone, which the phone syncs as `zone` (the tablet keeps
UTC); `time/tzdata` is embedded since the tablet has no zoneinfo. Review
Ahead (from a finished deck's congratulations) goes on to studied cards
not yet due, likeliest forgotten first (`session.earliest`, the phone's
`ReviewSession.earliest`).

## The look

Anki's desktop window under one header: X on the deck list (it closes the
app) or ← in a deck (up a level) on the left; the screen's name centred,
semibold (Flashcards, Overview, the deck's name while studying, Options,
Statistics;
Overview because the overview names the deck large itself); Sync on the
right, smaller;
the deck table (Deck, New, Learn, Due) with "Studied N cards today." under
it; the overview (the deck's name, New / Learning / To Review, Study Now,
Options in the bottom bar); the reviewer (the card centred, the answer
under a rule, Anki's bottom bar with the counts over Show Answer, then
Again Hard Good Easy, each under its interval); the options (a Daily
Limits card, New cards/day as Auto or a number, Save); the statistics
(Stats beside Options: Anki's Statistics window on one screen, no
scrolling: the deck or Collection as radio buttons, then Today, Future
Due, Card Counts, Review Intervals and Card Retrievability, each on an
outlined card under its name; `stats.go` is the phone's `algo/Stats`, and
`TestStatsMatchThePhone` its test's numbers). Histograms are black bars
(`components/Bars.qml`); Card Counts' pie (`components/Pie.qml`) tells its
kinds apart as old DOS charts did, by fill (`js/hatch.js`): New dots,
Learning `+`, Relearning `x`, Young diagonal lines, Mature solid. What Anki tells
apart by colour a shape does (`components/Mark.qml`): New a triangle,
Learning a square, To Review a circle; a queue with nothing in it is
faint; the current card's count is bold and underlined. Anki's blue focus
ring, which marks what Enter presses (Study Now, Show Answer, Good), is a
heavier outline (`AnkiButton.preferred`). Card text is plain, its newlines
kept and its ends trimmed. Long cards shrink to fit; there is no scrolling. IBM Plex Sans, as the Updater has it.

## Messages

| Type | Direction | Meaning |
|---|---|---|
| 1 | UI → backend | send the state (and sync if the last one is over a minute old) |
| 2 | | `{"deck", "ahead"?}`: send the deck's next card; `ahead` turns Review Ahead on (or, absent, off) |
| 3 | | `{"deck", "card", "rating"}`: answer it (1 to 4), then send the next |
| 4 | | `{"deck", "new_per_day"}`: -1 for Auto, else a number |
| 5 | | sync now |
| 6 | | ask for a new pairing code |
| 7 | | `{"deck", "whole"?}`: send the deck's statistics, or with `whole` the collection's |
| 101 | backend → UI | the state: `decks` (`id`, `name`, `newPerDay`, `counts`), `studied`, `paired`, `host`, `syncing`, `error`, `code`, `pairing`, `pairErr` |
| 102 | | `{"deck", "name", "counts", "queue", "card": {"id", "front", "back", "aux", "intervals"}}`, or `{"deck", "counts", "done": true, "nextMinutes"?, "recheck"?}`; each also `ahead` and `studied` (whether Review Ahead has anything) |
| 103 | | the statistics: `deck`, `whole`, `total`, `studied`, `introduced`, `countNames`, `counts`, `percents`, `due` (30 days from today), `dueTotal`, `dueAverage`, `intervals`, `intervalLabels`, `averageInterval`, `longestInterval`, `recall` (10 bins), `averageRecall`, `knowledge` |

## Layout

- `backend/`: `fsrs.go`, `session.go`, `collection.go` (the copy and its
  merge), `center.go` (sync and pairing), `stats.go` (the statistics),
  `app.go` (the messages),
  `main.go`; `transport.go` and `lifecycle.go` are the Updater's.
- `app/ui/`: `main.qml` (every screen), `components/` (`AnkiButton`,
  `Mark`, `Bars`, `Pie`, `Hatch`), `js/theme.js`, `js/hatch.js`.
- `package/`, `tools/build.py`, the icon comes from the repository's `tools/make_icons.py` (Pillow).

## Testing

```bash
(cd backend && go test ./...)
python3 tools/build.py
python3 ../tools/emulator.py . --env FLASHCARDS_SERVER=http://127.0.0.1:8080 --env FLASHCARDS_DATA=/tmp/fc
```

Against a local `delta-cc` (`delta-cc gen-token -data D`, then `delta-cc
-data D -addr 127.0.0.1:8080`), approve the code the emulator shows with
`curl -H "Authorization: Bearer $TOKEN" -d '{"code":"..."}'
http://127.0.0.1:8080/flashcards/pair/approve`.
