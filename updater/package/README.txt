Updater for reMarkable
======================

Keeps the reMarkable apps from https://github.com/thooton/tablet up to
date. It lists every app in the repository's latest release, says which
ones have a newer version than the tablet, and installs the ones you tap.

This folder lives on the tablet at /home/root/updater:

  install.sh     installs (or updates) the Updater in AppLoad
  uninstall.sh   removes it again (the apps it installed stay)
  app/           the app itself (install.sh copies it into AppLoad)

Needs xovi + AppLoad on the tablet, and Wi-Fi:
  https://github.com/asivery/xovi  (guide: https://xovi.bearblog.dev/appload/)
  https://github.com/asivery/rm-appload


Install (once; after that it updates itself)
-------
1. On a computer, download updater.tar.gz from
       https://github.com/thooton/tablet/releases/tag/latest
   and copy it to the tablet:
       scp updater.tar.gz root@10.11.99.1:
2. On the tablet (ssh root@10.11.99.1):
       cd /home/root
       tar -xzf updater.tar.gz
       sh updater/install.sh
3. Open AppLoad and tap Reload, then tap Updater.


Using it
--------
Tap UPDATE or GET beside an app, or Update All. Each app is downloaded,
checked against the release's SHA-256, unpacked into /home/root/<app>
(files you added there, such as your own stories, are kept) and installed
with that folder's install.sh. When it has finished, close the Updater and
tap Reload in AppLoad so the new versions open.

Tap an app's name for what's new in it, or to install it again.
