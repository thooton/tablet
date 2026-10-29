// Command entry is the AppLoad backend of LSAT Falcon (see tools/appload for
// how AppLoad runs it).
//
// It serves the question deck compiled into <app dir>/data (see
// tools/build_data.py) and keeps the settings and the reader's position in
// ~/.local/share/lsat-falcon/state.json.
package main

import (
	"path/filepath"

	"github.com/thooton/tablet/tools/appload"
)

var logf = appload.Logf

func main() {
	conn := appload.Connect("lsat-falcon")
	defer conn.Close()

	root := appload.AppDir("LSAT_FALCON_ROOT")
	app := newApp(filepath.Join(root, "data"), filepath.Join(appload.DataDir("LSAT_FALCON_DATA", "lsat-falcon"), "state.json"))
	logf("started; data %s, state %s", app.dataDir, app.statePath)
	appload.Serve(conn, nil, func(msgType int32, body []byte) {
		for _, r := range app.handle(msgType, body) {
			if err := sendChunked(conn.Send, r); err != nil {
				logf("cannot send reply: %v", err)
			}
		}
	})
}
