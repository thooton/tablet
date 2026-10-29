// Command entry is the AppLoad backend of Flashcards. AppLoad starts it as
// <app dir>/backend/entry with the path of a unix socket as its only
// argument (the desktop emulator passes "tcp:<host>:<port>" instead).
//
// It keeps the tablet's copy of the flashcards (collection.go), schedules
// them with FSRS-6 as the phone does (fsrs.go, session.go), and syncs them
// with the command center, which it pairs with first (center.go).
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	_ "time/tzdata" // the tablet has no zoneinfo; the day rolls over in the phone's zone
)

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[flashcards] "+format+"\n", args...)
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

	dir := env("FLASHCARDS_DATA", filepath.Join(env("HOME", "/home/root"), ".local", "share", "flashcards"))
	if err := os.MkdirAll(dir, 0o700); err != nil {
		logf("cannot make %s: %v", dir, err)
	}
	col, err := loadCollection(filepath.Join(dir, "collection.json"))
	if err != nil {
		// Unreadable: keep it aside and start empty; the next sync refills it.
		logf("reading the collection: %v", err)
		os.Rename(filepath.Join(dir, "collection.json"), filepath.Join(dir, "collection.json.bad"))
		col = newCollection(filepath.Join(dir, "collection.json"))
		col.index()
	}

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
	a := newApp(col, newCenter(dir), send)
	a.prefsPath = filepath.Join(dir, "prefs.json")
	a.loadPrefs()
	logf("started; data in %s, %d cards", dir, len(col.Cards))
	life := newLifecycle(executable(), a.busy)
	go life.watch()

	for {
		msgType, body, err := conn.recv()
		if err != nil {
			logf("connection closed: %v", err)
			break
		}
		life.seen(msgType, body)
		if msgType == msgSystemTerminate {
			break
		}
		a.handle(msgType, body)
	}
	a.saveNow()
}
