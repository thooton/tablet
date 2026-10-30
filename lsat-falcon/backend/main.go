// Command entry is the AppLoad backend of LSAT Falcon. AppLoad starts it as
// <app dir>/backend/entry with the path of a unix socket as its only argument
// (the desktop emulator passes "tcp:<host>:<port>" instead).
//
// It serves the question deck compiled into <app dir>/data (see
// tools/build_data.py) and keeps the settings and the reader's position in
// ~/.local/share/lsat-falcon/state.json.
package main

import (
	"path/filepath"

	"tablet/appload"
)

var logf = appload.Logger("lsat-falcon")

func main() {
	conn := appload.Connect(logf)
	defer conn.Close()

	root := appload.AppRoot("LSAT_FALCON_ROOT")
	app := newApp(filepath.Join(root, "data"), filepath.Join(appload.DataDir("LSAT_FALCON_DATA", "lsat-falcon"), "state.json"))
	logf("started; data %s, state %s", app.dataDir, app.statePath)
	appload.Serve(conn, logf, nil, func(msgType int32, body []byte) {
		for _, r := range app.handle(msgType, body) {
			if err := sendChunked(conn, r); err != nil {
				// A broken connection ends Serve at the next Recv.
				logf("cannot send reply: %v", err)
				return
			}
		}
	})
}
