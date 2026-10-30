// Command entry is the AppLoad backend of the Updater app. AppLoad starts it
// as <app dir>/backend/entry with the path of a unix socket as its only
// argument (the desktop emulator passes "tcp:<host>:<port>" instead).
//
// It reads manifest.json from the "latest" release of thooton/tablet,
// compares each app's version with the one AppLoad has, and installs the
// chosen ones: download <dir>.tar.gz, check its size and SHA-256, unpack it
// over /home/root/<dir>, and run its install.sh.
package main

import (
	"path/filepath"

	"tablet/appload"
)

var logf = appload.Logger("updater")

func main() {
	conn := appload.Connect(logf)
	defer conn.Close()

	home := appload.Env("UPDATER_HOME", "/home/root")
	apps := appload.Env("UPDATER_APPLOAD", filepath.Join(home, "xovi", "exthome", "appload"))
	cache := filepath.Join(home, ".cache", "updater")
	rel := newRelease(appload.Env("UPDATER_RELEASE", defaultRelease))

	app := newApp(rel, apps, home, cache, appload.JSONSender(conn, logf))
	logf("started; AppLoad %s, packages in %s, release %s", apps, home, rel.base)
	appload.Serve(conn, logf, app.busy, app.handle)
	app.close()
}
