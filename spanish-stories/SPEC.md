# Spanish-stories

Biblioteca (AppLoad id `spanish-reader`, directory `spanish-stories/`),
version 1.4.0 when this was written.

## Purpose

A reader of graded Spanish stories for the reMarkable 2, read with a finger
or the pen on e-ink. Pick a story from the library, read justified,
paginated text, and tap any dotted word or phrase to see its English, like
Duolingo's stories. Every translation comes from the story file, written for
that context ("tiene cinco años" -> "is five years old").

It must stay a quiet book: black on white, nothing moving, one refresh per
action, large tap targets, the text filling the page and the controls out of
sight until asked for. It works entirely offline. It must never become a
dictionary, a course, a flashcard or quiz app, or something that talks to
the network; anything that clutters the page or makes it refresh more often
is wrong for it.

## Not wanted

- No dictionary or downloaded data: translations come only from the story
  files.
- No network use of any kind (Flashcards is the only tablet app that talks
  to the command center).
- No tinted paper or grey text: white paper, black text (greys wash out on
  e-ink). The one grey left is the library's unread progress dots.
- No tap flash on buttons (removed in 1.4.0: it cost two refreshes per tap).
- No animation, no per-frame updates.
- No `·` separators: facts are set apart with `|`, details go in
  parentheses.
- No stories written for the app: the bundled ones are real public-domain
  texts reproduced word for word (the user's own Harry Potter file aside).
- Never `terminate()` the AppLoad endpoint, and the backend never exits
  while the app is open: either restarts the tablet's UI.

## Screens

The UI is in Spanish. Coordinates are on the 1404x1872 screen.

### Library

- Header (137 px, black rule under it): X at the left, "Biblioteca" centred,
  ⋮ at the right.
- Level tabs under it: TODOS | A1 | A2 | B1 | B2 | C1, always all six, plus
  one tab per other level found in the stories (upper-cased). The chosen tab
  is bold; the others regular.
- Up to eight story rows per page, each 188 px with a thin rule under it:
  title (one line, elided with …), the description (one line, elided), then
  a bordered level tag (absent if the story has no level), a row of progress
  dots (one per ~70 words, 6 to 60 dots, filled black up to the reading
  position, all filled once finished) and, once the story has been opened
  and read past its start or finished, its percent ("37%", "100%").
- Bottom right: "1 de 3" (page of pages). Hidden when the list is empty.
- Order: most recently opened or read first; stories never opened follow in
  file-name order.

Taps:

- X closes the app.
- ⋮ opens or closes the menu: "Recargar cuentos", and, only when some files
  failed to load, "Archivos con errores (N)". Tapping outside the menu
  closes it.
- Recargar cuentos re-reads the stories folder; added files appear, removed
  ones go, edited ones show their new text.
- Archivos con errores opens a box titled "Archivos con errores" listing
  each `file: reason`, separated by blank lines. X or a tap outside the box
  closes it.
- A tab shows only that level and goes back to page 1. TODOS shows all.
- A row opens that story in the reader. A tap below the last row of a page
  does nothing.
- A sideways swipe (more than 110 px, more horizontal than vertical) over
  the list goes to the next page (swipe left) or previous (swipe right).
  On the first page a right swipe stays; on the last a left swipe stays.
- The chosen tab and page are kept while the app is open, including after
  coming back from a story; they reset to TODOS, page 1, when the app is
  reopened.

Messages in the list area:

- Before the backend answers: "Cargando…"; after about 9 s with no answer,
  "El servicio de cuentos no responde." with what to do.
- No story files at all: "No hay cuentos." with where to copy them.
- A level tab with no stories: "No hay cuentos de nivel C1."

### Reader

Nothing but the text: the title centred and larger at the top of the first
page, then justified paragraphs (first line indented, except the story's
first paragraph) in the chosen font and size. Each word or
phrase that has a translation is dotted underneath; punctuation is not.
Spacing follows Spanish: no space before `. , ; : ! ? » …`, none after
`¿ ¡ « —`; a closing dialogue dash hugs the word before it. A word too wide
for a line breaks after a hyphen if it has one.

The page shows the story while its text loads; the library stays on screen
until the first page is ready. A story reopens on the page where it was
left, in every font and size (the page starting at or just before the saved
word).

Taps (in this order of precedence):

- With a translation open: a tap on another phrase moves to it; any other
  tap only closes the translation (it does not also turn the page or open
  the toolbar). A swipe closes it and turns the page.
- A dotted phrase, anywhere including the top strip: the phrase turns white
  on black (its dots go) and a white bordered card shows every English
  alternative, one per line, in 44 px sans. The card sits below the phrase
  when it fits above the bottom 140 px, otherwise above it, with a pointer to
  the phrase, and stays 58 px from the screen sides. Tapping the card does
  nothing. A phrase that wraps onto two lines highlights both parts; the
  card points at the first.
- Top strip (top 150 px), missing every word: opens the toolbar.
- Bottom strip (bottom 146 px): shows or hides the page footer.
- Left margin (x < 96): previous page. Right margin (x >= 1308): next page.
- A swipe left anywhere: next page; right: previous page.
- On the first page "previous" stays; on the last, "next" stays.
- Turning onto the last page marks the story finished.

Footer (when on, and the toolbar closed): "Pág. 3 de 11" at the left, "27%"
at the right, in the bottom strip. A story too long to hold whole (Harry
Potter) shows only the percent. The last page shows 100%.

### Toolbar

Opened from the top strip; covers the top and bottom of the page.

- Top bar: a grab handle (˅) at the top centre, then ← at the left, the
  story's title and level tag centred (title elided if long), Aa and ⋮ at
  the right, a black rule under it.
- Bottom bar: "Página 2 de 11", under it "16 min restantes  |  9%" (minutes
  at 120 words a minute, "1 min restante" when one or less), then a slider
  with a round knob. For a long book: "9%" and "N min restantes" alone, and
  the slider goes 0-100%.

Taps:

- ← returns to the library, which is re-read (the
  story just read moves to the top).
- The grab handle, or a tap on the page between the bars, closes the
  toolbar (if the ⋮ menu is open, the first tap only closes the menu).
- Aa closes the toolbar and opens the Texto box.
- ⋮ opens or closes the menu: "Ir al principio", "Marcar como leído",
  "Reiniciar progreso". Each closes the menu and the toolbar.
  - Ir al principio: page 1, saved as the position.
  - Marcar como leído: the story is finished (100% and all dots in the
    library); the page doesn't move.
  - Reiniciar progreso: back to page 1, not finished, and the library shows
    the story as never opened (no percent, empty dots, back in file order).
- Slider: while dragging, the page label follows the knob ("Página 7 de
  11"); the page changes only on release, to the page under the knob. For a
  long book, release jumps to that percent, at the start of its paragraph,
  and that is saved as the position. Releasing on the current value does
  nothing.

### Texto box (Aa)

A bordered box: "Texto" title bar with X, then:

- Font: three radio buttons, each label in its own font: Noto Serif, IBM
  Plex Sans, Atkinson. Default Noto Serif.
- Size: seven "Aa" samples, small to large, the chosen one white on black
  (text sizes 28, 32, 36, 40, 46, 54, 64 px; default 40).
- Puntos: Visibles | Ocultos (dots on or off). Default Visibles.

Each tap applies at once: the page behind re-flows and keeps the word it
started with on screen. X or a tap outside the box closes it. The settings
apply to every story.

### Error box

When the backend rejects a request (a story file deleted after the library
was shown, say), a box titled "Error" shows the message; X or a tap outside
closes it, and if a story was opening, the library stays.

## Behaviour

- Stories: every `*.json` in `/home/root/spanish-stories/stories` (linked
  into the app's folder by install.sh), read in file-name order. The format
  is in AGENTS.md. A file that can't be parsed is listed under Archivos con
  errores, never fatal. Two files with the same id: the second gets `-2`.
  A story without a title takes it from the file name ("03-el-oso" -> "El
  oso").
- Bundled: 23 stories, A1 to B2: 22 public-domain texts and Harry Potter y
  la piedra filosofal (B2, about 64,000 tokens), which the user added.
- State: `/home/root/.local/share/spanish-reader/state.json`, written
  atomically: per story the first word of the page last shown, finished,
  and when last read; and the settings (font, size, dots, footer). Every
  page turn saves. All of it survives closing the app, a restart and an
  update; `uninstall.sh` keeps it, `--purge` deletes it.
- Finished is sticky: reading back from the end doesn't clear it; only
  Reiniciar progreso does.
- Long stories (over 6000 tokens) are fetched a chunk at a time while
  reading; page turns must not wait visibly except right after a slider
  jump. Shorter stories are laid out whole and have page numbers.
- No network, no permissions, nothing timed except the library request,
  repeated every 1.5 s until the backend answers.
- Closing the app leaves the backend running; reopening is instant and
  shows the library. After an update, the new backend starts on the next
  open (AppLoad needs Reload for new QML).

## Look

See the repository's AGENTS.md for the e-ink rules. In addition:

- Text in the reader: 96 px side margins, 70 px top, line pitch 1.8x the
  text size, justified, Noto Serif by default.
- UI text is IBM Plex Sans; headings 44 px semibold.
- Menus are Kindle-style: a bordered white box under ⋮, 142 px rows, no
  dividers. Boxes (Texto, errors, Error) are 58 px from the screen sides
  with a 3 px black border.

## Open questions

1. The library's "service not responding" and "no stories" messages tell
   the user what to do (reinstall, copy files, use the menu), which the
   repository's rule against on-screen instructions forbids. Shorten them
   to facts ("Sin respuesta.", "No hay cuentos.")?
2. Backend errors reach the Error box in English ("story \"x\" not
   found") in an otherwise Spanish UI. Translate them, or keep them as they
   are since they are rare?
3. The backend can count looked-up words (message 4, `lookups` in
   state.json), but the reader never sends it, so nothing is counted.
   Should taps be recorded (for a future review list), or the dead code go?
4. Opening a finished story returns to its last page. Should a finished
   story open at the start instead?
5. The screenshots in docs/screens/ predate 1.1.1 (they show `·` and an
   uncentred toolbar title), and AGENTS.md still says 22 stories and "all
   texts are in the public domain", which Harry Potter is not. Update them?
6. The level tab and library page reset each time the app opens. Should
   they be remembered like the text settings?
