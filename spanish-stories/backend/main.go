// Command entry is the AppLoad backend of the Biblioteca app. AppLoad
// starts it as <app dir>/backend/entry with the path of a unix socket as its
// only argument (the desktop emulator passes "tcp:<host>:<port>" instead).
//
// It reads story files from <app dir>/stories (install.sh links that to
// /home/root/spanish-stories/stories) and keeps progress in
// ~/.local/share/spanish-reader/state.json.
package main

import (
	"os"
	"path/filepath"
	"strings"

	"tablet/appload"
)

var logf = appload.Logger("spanish-reader")

func storyDirs(root string) []string {
	dirs := []string{filepath.Join(root, "stories")}
	for _, d := range filepath.SplitList(os.Getenv("SPANISH_READER_EXTRA_STORIES")) {
		if d = strings.TrimSpace(d); d != "" {
			dirs = append(dirs, d)
		}
	}
	return dirs
}

func main() {
	conn := appload.Connect(logf)
	defer conn.Close()

	root := appload.AppRoot("SPANISH_READER_ROOT")
	app := newApp(storyDirs(root), filepath.Join(appload.DataDir("SPANISH_READER_DATA", "spanish-reader"), "state.json"))
	logf("started; app root %s, state %s", root, app.statePath)
	send := appload.JSONSender(conn, logf)
	appload.Serve(conn, logf, nil, func(msgType int32, body []byte) {
		for _, r := range app.handle(msgType, body) {
			send(r.Type, r.Body)
		}
	})
}
