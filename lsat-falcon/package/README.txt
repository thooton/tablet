LSAT Falcon for reMarkable
==========================

The LSAT Falcon drilling app on the reMarkable 2: every current-format
PrepTest question (Logical Reasoning and Reading Comprehension) with answer
statistics and explanations, plus timed practice tests.

This folder lives on the tablet at /home/root/lsat-falcon:

  install.sh     installs (or updates) the app in AppLoad
  uninstall.sh   removes it again (--purge also forgets settings and place)
  app/           the app and its question deck (install.sh copies it into AppLoad)

Needs xovi + AppLoad on the tablet:
  https://github.com/asivery/xovi  (guide: https://xovi.bearblog.dev/appload/)
  https://github.com/asivery/rm-appload


Install
-------
1. Copy lsat-falcon.zip (or .tar.gz) to the tablet, e.g.
       scp lsat-falcon.zip root@10.11.99.1:
2. On the tablet (ssh root@10.11.99.1):
       cd /home/root
       unzip -o lsat-falcon.zip        (or: tar -xzf lsat-falcon.tar.gz)
       sh lsat-falcon/install.sh
3. Open AppLoad and tap Reload, then tap LSAT Falcon.


Using the app
-------------
Swipe up or down on the page to turn it; the thin bar on the right shows
where you are. Tap a choice to answer; the explanation follows below.
Header: (i) credits, stopwatch = practice test, gear = filters and the
whole deck, X = close the app. Bottom bar: a passage's tabs (P, then its
questions), arrows to step through them, and Skip / Continue.

Settings and your place are saved in /home/root/.local/share/lsat-falcon.
