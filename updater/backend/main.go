// Command entry is the AppLoad backend of the Updater app (see tools/appload
// for how AppLoad runs it).
//
// It reads manifest.json from the "latest" release of thooton/tablet,
// compares each app's version with the one AppLoad has, and installs the
// chosen ones: download <dir>.tar.gz, check its size and SHA-256, unpack it
// over /home/root/<dir>, and run its install.sh.
package main

import (
	"path/filepath"

	"github.com/thooton/tablet/tools/appload"
)

var logf = appload.Logf

func main() {
	conn := appload.Connect("updater")
	defer conn.Close()

	home := appload.Env("UPDATER_HOME", "/home/root")
	apploadDir := appload.Env("UPDATER_APPLOAD", filepath.Join(home, "xovi", "exthome", "appload"))
	cache := filepath.Join(home, ".cache", "updater")
	rel := newRelease(appload.Env("UPDATER_RELEASE", defaultRelease))

	app := newApp(rel, apploadDir, home, cache, conn.SendJSON)
	logf("started; AppLoad %s, packages in %s, release %s", apploadDir, home, rel.base)
	appload.Serve(conn, app.busy, app.handle)
	app.close()
}
