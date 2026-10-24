// Command entry is the AppLoad backend of LSAT Falcon. AppLoad starts it as
// <app dir>/backend/entry with the path of a unix socket as its only argument
// (the desktop emulator passes "tcp:<host>:<port>" instead).
//
// It serves the question deck compiled into <app dir>/data (see
// tools/build_data.py) and keeps the settings and the reader's position in
// ~/.local/share/lsat-falcon/state.json.
package main

import (
	"fmt"
	"os"
	"path/filepath"
)

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[lsat-falcon] "+format+"\n", args...)
}

func appRoot() string {
	if root := os.Getenv("LSAT_FALCON_ROOT"); root != "" {
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

func statePath() string {
	dir := os.Getenv("LSAT_FALCON_DATA")
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			home = "/home/root"
		}
		dir = filepath.Join(home, ".local", "share", "lsat-falcon")
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
	app := newApp(filepath.Join(root, "data"), statePath())
	logf("started; data %s, state %s", app.dataDir, app.statePath)
	life := newLifecycle(executable(), nil)
	go life.watch()

	for {
		msgType, body, err := conn.recv()
		if err != nil {
			logf("connection closed: %v", err)
			return
		}
		life.seen(msgType, body)
		for _, r := range app.handle(msgType, body) {
			if err := sendChunked(conn, r); err != nil {
				logf("cannot send reply: %v", err)
				return
			}
		}
		if msgType == msgSystemTerminate {
			return
		}
	}
}
