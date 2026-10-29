# Flashcards

## Purpose

Anki's desktop window on the reMarkable 2, in black and white, for studying
the same decks as Flashcards on the phone (thooton/sonim). The user studies
with a finger or the pen on the e-ink screen. Decks are made and cards are
removed on the phone; the tablet only studies them, looks at their
statistics and sets how many new cards come in each day. Scheduling is the
phone's (Anki with the FSRS4Anki scheduler), so an answer on either device
schedules a card the same way, and the two stay in step through the Delta
command center.

It must stay small, quick and calm on e-ink: one screen at a time, nothing
moves, nothing scrolls, and a tap redraws the screen once. It should look
like Anki, so the user's Anki habits carry over. It must never become a card
editor, a deck manager, a second scheduler that differs from the phone's, or
an app that needs a keyboard.

## Not wanted

- Tapping the card to show the answer. Only Show Answer shows it (1.3.2).
- A grey fill or flash on press for any button, X or ← (1.4.3 to 1.4.5):
  each costs an extra e-ink refresh. The result of the tap is the feedback.
- The deck's name twice on the overview: the top bar says Overview there,
  since the page itself names the deck large (1.4.1, 1.4.2).
- Scrolling. Long cards shrink to fit; Statistics fits on one screen.
- Typing the delta token. The tablet pairs with a code instead.
- Colour, animation, greys beyond "less" (a zero count, an interval, a
  label), on-screen instructions or reassurance.
- Its own scheduling. Any change must keep `TestReviewMatchesThePhone` and
  `TestStatsMatchThePhone` passing.

## Screens

Every screen but pairing has the top bar: X (on the deck list) or ← (in a
deck) on the left, the screen's name centred and semibold, and Sync on the
right, smaller. Sync reads "Syncing…" while a sync runs; tapping it starts
one (tapping during one runs another straight after). There are no hardware
keys; the tablet's own swipe gestures are not the app's.

Until the backend first answers, the screen is blank white (it asks again
every 1.5 s).

### Pairing (shown whenever the tablet is not paired)

- No top bar; only X at the top left, which closes the app.
- Centred: "PAIRING CODE" (small, spaced capitals), the code very large,
  then "Delta (<host>), Tablet", where host is the command center's
  (edit.mimilearn.org by default).
- While a code is being fetched the code reads "…".
- Typing the code on the website's Tablet page pairs the tablet within a few
  seconds (the backend polls every 3 s) and the deck list appears, with a
  sync started.
- If the code expires: "The code expired." and a Try Again button, which
  fetches a new code. Offline: "No connection." and Try Again. While
  either shows, the code line is empty. A short
  network blip while polling is ignored.
- If the website unpairs the tablet, the next sync forgets the token and
  this screen comes back with a new code. The cards stay on the tablet.

### Deck list (title Flashcards)

- A table: Deck, then New (triangle), Learn (square), Due (circle), with a
  row per deck, in the collection's order: the name (elided with … when too
  long) and its three counts, right-aligned. A zero count is faint; others
  are medium weight.
- Tapping anywhere on a row opens that deck's overview.
- Under the table, centred: "Studied N cards today." (N across every deck,
  since the 4am rollover; "1 card" singular).
- No decks: "Syncing…" while the first sync runs (or before any sync has
  finished), then "No decks."
- After a failed sync: "Not synced: <reason>" under that, e.g. "Not synced:
  No connection.", "Not synced: The command center needs updating.". It
  goes away after the next good sync.
- X closes the app.

### Overview (title Overview)

- The deck's name large and centred (wrapping if long), then, as Anki's
  table: "New:", "Learning:", "To Review:", each with its shape and count
  (faint when 0), and Study Now (the heavier outline).
- When all three counts are 0: no table or Study Now, but "Congratulations!
  You have finished this deck for now." and, if a learning card is still due
  today, "The next learning card will be ready in N minutes." (1 minute
  singular). The overview refreshes by itself when that card comes within
  20 minutes (the learn-ahead limit) of being due, and Study Now comes back.
- On the finished deck, Review Ahead appears if the deck has any card ever
  answered; it studies cards not yet due, likeliest forgotten first, never
  the same card twice running, until the user leaves.
- Bottom bar: Options and Stats.
- ← goes to the deck list.

### Reviewer (title: the deck's name, elided if long)

- The front centred near the top, plain text, newlines and blank lines kept,
  leading and trailing whitespace trimmed.
- Bottom bar: the three counts with their shapes (zeros faint; the queue the
  current card is from bold and underlined), and under them Show Answer
  (heavier outline).
- Show Answer: a rule, then the back, then the extra notes (aux, smaller
  and grey) if the card has any. The bar then shows Again, Hard, Good
  (heavier outline), Easy, each under its interval as Anki writes it: "<1m",
  "10m", "3h", "4d", "1.5mo", "2.1y".
- Tapping an answer shows the next card. Taps on the answer buttons are
  ignored until it arrives (no double answers), and Show Answer is
  ignored for a moment after a card arrives, so the second tap of a
  double tap on an answer doesn't show the next card's answer.
- The order is Anki's: learning cards once due, then today's reviews with
  new cards spread evenly among them, then learning cards due within 20
  minutes; then the deck is finished and the app returns to the overview
  (with the congratulations).
- A card too long to fit shrinks (front, back and notes together) until it
  fits, down to about 45% of the normal size. Nothing scrolls.
- The same card stays up across leaving and coming back, until answered,
  unless what is due changed meanwhile.
- ← goes to the overview without answering.

### Options (title Options)

- The deck's name (grey, small), then a "Daily Limits" card: "New
  cards/day" with Auto | Number (the chosen one filled black).
- Number shows −10, −, the number, +, +10. Choosing Number from Auto starts
  at 20. The number stays between 0 and 9999 (−10 at 5 gives 0).
- Auto: new cards come in while New + Learning + Due is under 20.
- A number: at most that many new cards first answered today, on any
  device, in that deck.
- A second card, "Display": "Show progress" with Off | On (off by default).
  It applies at once, is kept on this tablet for every deck (prefs.json),
  and is not synced or undone by Cancel. When on, the reviewer shows `N%`
  in small grey at the right of the counts: 100% minus the share of the
  deck's cards still New.
- Bottom bar: Cancel (back to the overview, nothing changed) and Save
  (heavier outline: saves, syncs, back to the overview with the new New
  count). ← is Cancel.

### Statistics (title Statistics)

On one screen, no scrolling, each part on an outlined card under its name:

- Radio buttons: the deck's name (elided if long) and Collection. Tapping
  one shows that set's numbers; the deck is chosen on opening.
- Today: "Studied N cards today." or "No cards have been studied today.",
  and when some were: "New: X  |  Review: Y".
- Future Due: 30 bars, labelled 0, 5, … 25 (days from today; overdue cards
  count as today), the tallest bar's count at the top of the axis; "Due
  today: N reviews  |  Due tomorrow: N reviews" and "Average: N
  reviews/day  |  Total: N reviews" (singular "review" for 1).
- Card Counts: a pie by fill (New dots, Learning +, Relearning x, Young
  diagonal lines, Mature solid; mature from a 21-day interval), and a table
  of each kind's count and share ("12.5%"), then Total.
- Review Intervals (left half): bars 1d, 3d, 1w, 2w, 1m, 3m, 6m, 1y, 1y+;
  "Average: 13.9 days" and "Longest: 2 months" style spans.
- Card Retrievability (right half): 10 bars, 0% to 100%; "Average: 87.3%"
  and "Total knowledge: N cards".
- An empty deck shows zeros and empty axes, not an error.
- ← goes to the overview.

## Behaviour

- Data: `~/.local/share/flashcards/collection.json` (the tablet's copy:
  decks, cards, the phone's time zone) and `login.json` (server and pairing
  token, mode 600). Both survive restarts, updates and uninstalling
  (`uninstall.sh --purge` removes them). An unreadable collection
  is moved aside to `collection.json.bad` and refilled by the next sync.
- Studying works fully offline. Answers are saved to disk 2 s after the
  last one, and when the app closes.
- Sync (`POST /flashcards/sync` with the pairing token) runs when the app
  opens if the last sync is over a minute old, 20 s after the last answer,
  after Save in Options, when the app closes, and from Sync. Only changed
  records go up. Where both devices changed a card, the later change wins.
  A card removed on the phone disappears from the tablet at the next sync,
  even if it was answered here meanwhile. New decks and cards from the phone
  appear after a sync without reopening.
- Errors never block studying; they show only as "Not synced: …" on the
  deck list, or on the pairing screen.
- The day rolls over at 4am in the phone's time zone (synced from the
  phone), not the tablet's UTC: counts, "today", the daily new-card limit
  and Future Due all follow it.
- The backend keeps running after the window closes and is reused on the
  next open; after an update it is replaced on the next open. Closing the
  app never restarts the tablet's UI.

## Look

The rules are in `../AGENTS.md` and `AGENTS.md` ("The look"). Beyond
those: buttons are rounded and outlined, 104 px tall, with no pressed
state; the preferred one (what Enter presses in Anki: Study Now, Show
Answer, Good, Save, Try Again) has a 5 px outline instead of 2 px. Facts set
apart use `  |  `, never `·`.

## Open questions

1. The deck list doesn't scroll: past about 13 decks the rest run off the
   bottom of the screen and can't be opened. Page buttons, smaller rows, or
   is that never going to happen?
2. A deck deleted or renamed on the phone: renames come through, but
   nothing removes a deck from the tablet's copy. Should it disappear?
3. The deck list's counts don't refresh by themselves when a learning card
   comes due (only the overview rechecks); they update on the next sync or
   screen change. Is that fine?
4. A card that is still too tall at the smallest size runs under the bottom
   bar. Should there be a smaller floor, or is clipping acceptable for such
   rare cards?
5. While the reviewer or Statistics waits for the backend, the area under
   the top bar is blank. It is usually instant; is a "…" wanted?
