Spanish Reader for reMarkable
=============================

Short Spanish stories. Every word or phrase has a dotted underline; tap it
to see the English.

This folder lives on the tablet at /home/root/spanish-stories:

  install.sh     installs (or updates) the app in AppLoad
  uninstall.sh   removes it again (--purge also forgets reading progress)
  stories/       the stories: add or delete .json files here any time
  app/           the app itself (install.sh copies it into AppLoad)

Needs xovi + AppLoad on the tablet:
  https://github.com/asivery/xovi  (guide: https://xovi.bearblog.dev/appload/)
  https://github.com/asivery/rm-appload


Install
-------
1. Copy spanish-stories.zip (or .tar.gz) to the tablet, e.g.
       scp spanish-stories.zip root@10.11.99.1:
2. On the tablet (ssh root@10.11.99.1):
       cd /home/root
       unzip -o spanish-stories.zip        (or: tar -xzf spanish-stories.tar.gz)
       sh spanish-stories/install.sh
3. Open AppLoad and tap Reload.

To update, unpack a newer download over the same folder and run install.sh
again. Your own stories in stories/ and your reading progress are kept.


Adding stories
--------------
Put .json files in /home/root/spanish-stories/stories, then in the app tap
⋮ › Recargar cuentos. A story looks like this:

  {
    "title": "El gato de Luna",
    "title_en": "Luna's cat",
    "level": "A1",
    "description": "One morning Luna's black cat, Sol, has disappeared.",
    "content": [
      ["Luna", "Luna"],
      ["tiene", "has"],
      ["ocho años", "eight years old / is eight"],
      [".", ""],
      ["\n", ""],
      ...
    ]
  }

Each pair is (Spanish, English). Pairs with no English (punctuation) are
not underlined. " / " separates alternative translations. "\n" starts a
new paragraph.


Uninstall
---------
    sh /home/root/spanish-stories/uninstall.sh            keeps your progress
    sh /home/root/spanish-stories/uninstall.sh --purge    forgets it too
    rm -r /home/root/spanish-stories                      deletes the stories


Using the app
-------------
Library:  tap a story to read it; tap TODOS / A1 / A2 ... to filter by
          level; swipe sideways for more stories; ← closes the app.
Reading:  tap a dotted word or phrase for its English, tap anywhere else to
          close it. Tap the left or right margin, or swipe, to turn the
          page. Tap the top of the page for the toolbar (Aa: font, text
          size, dots; ⋮: go to start, mark as read, reset). Tap the bottom
          of the page to show or hide the page number.

Progress is saved in /home/root/.local/share/spanish-reader/state.json.
