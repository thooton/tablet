// Command entry is the AppLoad backend of the Biblioteca app (see
// tools/appload for how AppLoad runs it).
//
// It reads story files from <app dir>/stories (install.sh links that to
// /home/root/spanish-stories/stories) and keeps progress in
// ~/.local/share/spanish-reader/state.json.
package main

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/thooton/tablet/tools/appload"
)

var logf = appload.Logf

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
	conn := appload.Connect("spanish-reader")
	defer conn.Close()

	root := appload.AppDir("SPANISH_READER_ROOT")
	app := newApp(storyDirs(root), filepath.Join(appload.DataDir("SPANISH_READER_DATA", "spanish-reader"), "state.json"))
	logf("started; app root %s, state %s", root, app.statePath)
	appload.Serve(conn, nil, func(msgType int32, body []byte) {
		for _, r := range app.handle(msgType, body) {
			conn.SendJSON(r.Type, r.Body)
		}
	})
}
