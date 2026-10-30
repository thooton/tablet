# Lsat-falcon

LSAT Falcon (AppLoad id `lsat-falcon`, directory `lsat-falcon/`), version
1.0.3 when this was last updated.

## Purpose

The user's LSAT drilling web app (thooton's `demon`) on the reMarkable 2,
used with a finger or the pen. It has the whole deck (7,626 LR and RC
questions, 6,363 of them drilled, the held-out PrepTests kept for practice
tests), with answer statistics and explanations, filters, the deck outline
and timed practice tests with a scaled score.

It is a faithful port: the web app's screens, wording, fonts and phone-width
layout, at 2.25 screen pixels per CSS pixel (a 624 x 832 CSS viewport),
redrawn black on white for e-ink. New behaviour comes from the web app, not
from ideas made up here. It must stay quick, still (no animation, one
refresh per action), offline and self-contained. It must never become
networked (no accounts, sync or downloads), a tracker of answer history or
progress, or anything that redraws on its own except the practice-test
clock once a minute.

## Not wanted

- Left out of the web app on purpose: sound, dark mode, Ask AI (no
  clipboard), find in passage (no keyboard), the download button, the copy
  buttons in the credits.
- No scrolling or animation: panes turn a page at a time.
- No seconds on the practice-test clock (whole minutes only).
- Answers are not saved, as on the web: drilling answers last as long as the
  current group, practice-test answers as long as the test.
- No colour or grey state: anything that carries state is black on white.
- No network use; the deck is vendored in `deck/` and built into the app.
- No `·` separators.
- Never `terminate()` the AppLoad endpoint; the backend never exits while
  the app is open (either crashes the tablet's UI).

## Screens

Sizes below are CSS px (x 2.25 on screen). Panes that are taller than the
screen page: a vertical swipe of more than 30 px (more vertical than
horizontal) shows the next screenful (swipe up) or the previous one (swipe
down), keeping the last 32 px of the previous page at the top. No page
starts on half a line or half a row: it backs up to show it whole, or on
the last page starts just after it; the same goes for paging to the
question or to a quoted phrase. At the top a
swipe down stays; at the bottom a swipe up stays. A thin grey thumb on the
right shows the place, only when the pane pages. Sideways swipes do nothing.
Anything shorter than 30 px of movement is a tap.

### Loading

The falcon over a still twelve-spoke throbber, and an X at the top right
that closes the app. The app says hello to the backend every 1.5 s until
it answers. After about 9 s with no answer: "LSAT Falcon's question
service isn't answering." with what to do. A deck that can't be loaded
shows "The question deck could not be loaded: <reason>." under the
throbber (the reason in a few words, e.g. "meta.json is missing"), and the
backend tries loading it again on each hello. Then it opens drilling.

### Drilling

Header (56 px, rule below): the falcon, the title (the current question's
test label, e.g. its PrepTest; "LSAT Falcon" for questions without a
test and when nothing matches), elided if long, then four buttons: info, stopwatch, settings, close.

- info opens Credits.
- stopwatch clears the drill's answers, closes Settings and opens Practice
  test. Hidden when the deck has no exams.
- settings opens or closes Settings (shown pressed, black, while open).
- close closes the app.

The body pages as one pane: the heading in grey ("Section 3, Question 9",
"Section 3" alone over a reading passage, "Stimulus" without a section),
the passage or stimulus, then the stem and the choices A-E, with a bordered
tool card at the choices' top right holding strike (struck A).

- Tapping a choice answers: the answer is final for that question. The
  credited choice gets a heavy black border and a ✓; a wrong pick a grey
  border and ✗; behind each choice's text a bar shows the share of test
  takers who picked it. Below the stimulus a card shows the question's
  type, number and difficulty. The tools move to a row of their own above
  the stem. The Explanation follows the choices: an introduction, then a
  note per letter, the credited letter in bold black, the others faint.
- Strike turns strike mode on (button pressed: black, white icon): each choice shows a minus
  at its right; tapping a choice or its minus strikes it out (grey,
  struck through) or back. Tapping strike again leaves the mode. Tapping
  a struck choice outside strike mode answers it and un-strikes it. Strike
  mode ends on a new question.
- A phrase the stem quotes from the passage is a link: tapping it marks the
  phrase in the passage and pages so it is in the middle of the screen. Tapping the
  same link again goes to its next occurrence.
- A reading-comp question opens paged to the question, with its passage a
  swipe down. Other questions open at the top.

Bottom bar (64 px, rule above), hidden when nothing matches or the drill is
finished:

- When the question is part of a group (a reading passage, or several
  questions on one stimulus): tabs, P for the passage (RC only) then one
  per question in the deck with its printed number; the current one is
  black. The tabs shift so the current one is always visible, and only
  whole tabs are shown. Then ← and →,
  which step through the group's tabs (← disabled on P, or on the first
  question when there is no P; → disabled on the last question).
- The main button: on the passage, "Continue" (to the group's first
  question); unanswered, "Skip" (outlined); answered, "Continue", or
  "Finish" on the deck's last question. Skip and Continue go to the next
  question in the deck.
- A new group clears all answers and opens on its passage (P), which shows
  the passage alone, without the question. Struck choices stay for the
  session.

End of the deck (Finish, or Skip on the last question): "Session complete",
"You reached the end of this N-question drill." and "Start over", which
clears answers and struck choices and goes back to the deck's first question.

Nothing matches the filters: header only, and in the middle "No questions
match logical reasoning; difficulty 4, 5; type Flaw; test 101, 102." (only
the parts set) with "Clear filter", which clears section, type, difficulty
and test (not the held-out switch or shuffle).

### Settings

Covers the whole screen. Heading "Settings" with an X (closes). The filters
page on their own (up to 62% of the screen, ending under the last whole
row, a rule under them when they do), the deck outline pages below them.

- Section: Logical Reasoning, Reading Comprehension chips (toggle; both
  off means all), Clear at the right while any is on.
- Type: a dropdown row with the summary ("Any", or the chosen types); the
  chevron row opens or closes the chips, grouped "Logical Reasoning | Open",
  "Logical Reasoning | Closed", "Reading Comprehension". Clear while any is on.
- Difficulty: chips 1-5, Clear while any is on.
- Test: dropdown, summary "Any" or numbers with runs collapsed ("108-109,
  113"). The drilled tests' chips, then "Held out" with an "Include" link
  (while the switch is off) and the held-out tests' chips, disabled until
  the switch is on.
- "Drill held-out tests" switch. Turning it off also drops held-out tests
  from the test filter.
- "Shuffle" switch (on by default). The shuffle is fixed for the session,
  with passage groups kept together; a new order each time the app opens.
- "N questions" or "N questions (filtered from M)"; "1 question".

Every change applies at once. The current question stays if it still
matches; otherwise the deck's first question is shown and becomes current.

Deck outline, in test order whatever the shuffle: each test with its count
(and a "Held out" badge), then its sections with counts. One section is
open at a time, at first the one holding the current question; tapping a
section header opens it, or closes it if open. Rows: number tile, type,
difficulty meter, and a black dot if answered right or a ring if wrong (this
group's answers only). The current row is shaded and paged into view on
opening. Tapping a row goes to that question and closes Settings. Nothing
left: "Nothing matches these filters."

### Credits

Full screen, paging, X at the top right closes it: the falcon, "LSAT
Falcon", "Created by kitten2910", the source and copyright paragraphs, and
the donation rows (BTC, LTC, ETH, SOL, XMR; long addresses elided in the
middle, nothing to tap).

### Practice test

Header: "Practice test" (setup) or the test's label, then while a section
runs the clock, then "End test" during a test or "Done" on setup, results
and review. Done goes back to drilling. End test asks "End this practice
test? Your answers will be lost." (Cancel, OK; a tap outside cancels); OK
goes back to drilling. There is no close button here.

Setup: test chips under "Held out" then "Drilled" (the first held-out test
picked), "Timing" Timed | Untimed (Timed by default; the chosen one filled black), "Start".

Brief, before each section: "Section 2 of 4", the section name (or
"Questions"), "26 questions (35 minutes)" or "(untimed)", "Begin section".

Section: the passage and question as in drilling, plus a bookmark tool, and
under a passage "Passage questions" chips to jump between them. Answers can
be changed freely; nothing is marked. Footer (68 px): "Back" (disabled on
the first), the palette (one chip per question: current black, answered
grey, others outlined, a dot on bookmarked ones; only whole chips shown;
tap to jump; swipe sideways to turn a page of chips, so every question is
reachable), "Finish
section" (hidden on the last question), "Next", which on the last question
reads "Finish section" or, in the last section, "Finish test". Finishing
with blanks asks "3 questions are unanswered. Finish section?" ("1 question
is"). Finishing is final.

Clock: timed counts down in whole minutes, rounded up ("35 min" at the
start ... "2 min", then "<1 min" in the last minute); with 5 minutes or less left it gets a border and bold. At 35 minutes
the section ends by itself, without asking. Untimed counts up ("0 min",
"1 min", ...) and never ends the section.

Results: "<test> complete", the scaled score (120-180, from the test's
conversion chart when it has one, otherwise a curve), correct and incorrect
counts, then "61 of 75 right (81%)  |  2 left blank (counted wrong)  |
timed  |  1h 52m". Experimental sections are left out of the score.
"By section" (experimental ones marked "(experimental)") and "By question
type" (most questions first), right out of total; a type both sections
have says which ("Weaken (LR)", "Weaken (RC)"). Buttons "Review answers",
"Another test" (back to setup), "Back to drilling".

Review: every question of the test, experimental too, answered and with its
explanation. Footer: "Score report" (back to results), one bar per question
(filled black if right, open if wrong, the current one outlined; tap to jump; swipe
sideways to turn a page of bars), "Back" and "Next", disabled at the ends.

### Messages

A backend error shows a bordered box with the message and "OK"; OK or a tap
anywhere closes it. (A deck that can't be loaded is said on the Loading
screen instead.)

## Behaviour

- The deck is built into the app (`build/data/meta.json` sent at startup;
  question text read one at a time from `content.dat`). Each question shown
  is fetched with its group's siblings and the next question in the deck,
  and kept in memory while the app is open.
- Saved in `~/.local/share/lsat-falcon/state.json` (written atomically):
  the filters, the held-out switch, shuffle, and the place, as the web
  app's key (`PT141-S4-Q9`, `-P` on a passage, `I<index>` without
  coordinates). Reopening lands on the same question or passage; a place in
  a held-out test turns held-out drilling on. Unknown saved values are
  dropped; a place no longer in the deck opens at the deck's first question.
- Not saved: answers, struck choices, bookmarks, a practice test in
  progress (closing the app loses it), the shuffle order.
- No network use and no permissions.
- The backend keeps running after the app closes and is reused; it exits
  only once an update has replaced it and the app is closed.
  `uninstall.sh` keeps state.json; `--purge` removes it.

## Look

From README.md and the root AGENTS.md: Falcon Roboto (reading text 36
screen px on a 1.5 line, weight 400), → ← ↑ ↓ ≠ ✓ from Noto Sans Math,
black on white, greys only for decoration (headings, hints, the share
bars, the scrollbar thumb). Selected chips, the current tab and pressed
buttons (strike, bookmark, settings) are filled black with white text or
icon.

## Open questions

1. The donation addresses in Credits look like well-known placeholders
   (the BTC one is the standard example address, the SOL one is all 1s).
   Are they really the author's, or should the donation rows be fixed or
   removed?
2. Skip on the deck's last question ends the drill ("Session complete")
   just as Finish does. Intended, or should Skip there stay put?
3. A practice test is lost if the app is closed, and the section clock
   (a 1 s timer in the UI) likely stops while the tablet sleeps, so a
   timed section can run longer than 35 real minutes. Should a test in
   progress survive closing the app, and should the clock follow real time?
