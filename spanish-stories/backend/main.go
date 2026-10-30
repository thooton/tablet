// Command entry is the AppLoad backend of the Biblioteca app. AppLoad
// starts it as <app dir>/backend/entry with the path of a unix socket as its
// only argument (the desktop emulator passes "tcp:<host>:<port>" instead).
//
// It reads story files from <app dir>/stories (install.sh links that to
// /home/root/spanish-stories/stories) and keeps progress in
// ~/.local/share/spanish-reader/state.json.
package main

import (
	"apploadrt"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

var logf = apploadrt.Logger("spanish-reader")

func appRoot() string {
	if root := os.Getenv("SPANISH_READER_ROOT"); root != "" {
		return root
	}
	if exe, err := os.Executable(); err == nil {
		if exe, err = filepath.EvalSymlinks(exe); err == nil {
			return filepath.Dir(filepath.Dir(exe))
		}
	}
	wd, _ := os.Getwd()
	return wd
}

func storyDirs(root string) []string {
	dirs := []string{filepath.Join(root, "stories")}
	for _, d := range filepath.SplitList(os.Getenv("SPANISH_READER_EXTRA_STORIES")) {
		if d = strings.TrimSpace(d); d != "" {
			dirs = append(dirs, d)
		}
	}
	return dirs
}

func statePath() string {
	dir := os.Getenv("SPANISH_READER_DATA")
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			home = "/home/root"
		}
		dir = filepath.Join(home, ".local", "share", "spanish-reader")
	}
	return filepath.Join(dir, "state.json")
}

func main() {
	conn := apploadrt.Connect(logf)
	defer conn.Close()

	root := appRoot()
	app := newApp(storyDirs(root), statePath())
	logf("started; app root %s, state %s", root, app.statePath)
	apploadrt.Serve(conn, nil, logf, func(msgType int32, body []byte) error {
		for _, r := range app.handle(msgType, body) {
			data, err := json.Marshal(r.Body)
			if err != nil {
				logf("cannot encode reply: %v", err)
				continue
			}
			// Never exit here: a backend that quits while its app is
			// open crashes the tablet's UI. A broken connection ends the
			// loop at the next recv.
			if err := conn.Send(r.Type, data); err != nil {
				logf("cannot send reply %d (%d bytes): %v", r.Type, len(data), err)
				break
			}
		}
		return nil
	})
}
