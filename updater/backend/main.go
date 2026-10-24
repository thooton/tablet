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
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[updater] "+format+"\n", args...)
}

func env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
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

	home := env("UPDATER_HOME", "/home/root")
	appload := env("UPDATER_APPLOAD", filepath.Join(home, "xovi", "exthome", "appload"))
	cache := filepath.Join(home, ".cache", "updater")
	rel := newRelease(env("UPDATER_RELEASE", defaultRelease))

	var sendMu sync.Mutex
	send := func(msgType int32, body any) {
		data, err := json.Marshal(body)
		if err != nil {
			logf("encoding message %d: %v", msgType, err)
			return
		}
		sendMu.Lock()
		defer sendMu.Unlock()
		if err := conn.send(msgType, data); err != nil {
			logf("sending message %d: %v", msgType, err)
		}
	}
	app := newApp(rel, appload, home, cache, send)
	logf("started; AppLoad %s, packages in %s, release %s", appload, home, rel.base)

	for {
		msgType, body, err := conn.recv()
		if err != nil {
			logf("connection closed: %v", err)
			break
		}
		if msgType == msgSystemTerminate {
			break
		}
		app.handle(msgType, body)
	}
	app.close()
}
