// Command entry is the AppLoad backend of the Spanish Reader app. AppLoad
// starts it as <app dir>/backend/entry with the path of a unix socket as its
// only argument (the desktop emulator passes "tcp:<host>:<port>" instead).
//
// It reads story files from <app dir>/stories (install.sh links that to
// /home/root/spanish-stories/stories) and keeps progress in
// ~/.local/share/spanish-reader/state.json.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[spanish-reader] "+format+"\n", args...)
}

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
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: entry <unix socket path | tcp:host:port>")
		os.Exit(2)
	}
	conn, err := dial(os.Args[1])
	if err != nil {
		logf("cannot connect to %s: %v", os.Args[1], err)
		os.Exit(1)
	}
	defer conn.close()

	root := appRoot()
	app := newApp(storyDirs(root), statePath())
	logf("started; app root %s, state %s", root, app.statePath)

	for {
		msgType, body, err := conn.recv()
		if err != nil {
			logf("connection closed: %v", err)
			return
		}
		for _, r := range app.handle(msgType, body) {
			data, err := json.Marshal(r.Body)
			if err != nil {
				logf("cannot encode reply: %v", err)
				continue
			}
			if err := conn.send(r.Type, data); err != nil {
				logf("cannot send reply: %v", err)
				return
			}
		}
		if msgType == msgSystemTerminate {
			return
		}
	}
}
