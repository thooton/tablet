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
	"apploadrt"
	"path/filepath"
)

var logf = apploadrt.Logger("updater")

func main() {
	conn := apploadrt.Connect(logf)
	defer conn.Close()

	home := apploadrt.Env("UPDATER_HOME", "/home/root")
	appload := apploadrt.Env("UPDATER_APPLOAD", filepath.Join(home, "xovi", "exthome", "appload"))
	cache := filepath.Join(home, ".cache", "updater")
	rel := newRelease(apploadrt.Env("UPDATER_RELEASE", defaultRelease))

	send := apploadrt.Sender(conn, logf)
	app := newApp(rel, appload, home, cache, send)
	logf("started; AppLoad %s, packages in %s, release %s", appload, home, rel.base)
	apploadrt.Serve(conn, app.busy, logf, func(msgType int32, body []byte) error {
		app.handle(msgType, body)
		return nil
	})
	app.close()
}
