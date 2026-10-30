// Command entry is the AppLoad backend of Flashcards. AppLoad starts it as
// <app dir>/backend/entry with the path of a unix socket as its only
// argument (the desktop emulator passes "tcp:<host>:<port>" instead).
//
// It keeps the tablet's copy of the flashcards (collection.go), schedules
// them with FSRS-6 as the phone does (fsrs.go, session.go), and syncs them
// with the command center, which it pairs with first (center.go).
package main

import (
	"apploadrt"
	"os"
	"path/filepath"
	_ "time/tzdata" // the tablet has no zoneinfo; the day rolls over in the phone's zone
)

var logf = apploadrt.Logger("flashcards")

func main() {
	conn := apploadrt.Connect(logf)
	defer conn.Close()

	dir := apploadrt.Env("FLASHCARDS_DATA", filepath.Join(apploadrt.Env("HOME", "/home/root"), ".local", "share", "flashcards"))
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

	send := apploadrt.Sender(conn, logf)
	a := newApp(col, newCenter(dir), send)
	a.prefsPath = filepath.Join(dir, "prefs.json")
	a.loadPrefs()
	logf("started; data in %s, %d cards", dir, len(col.Cards))
	apploadrt.Serve(conn, a.busy, logf, func(msgType int32, body []byte) error {
		a.handle(msgType, body)
		return nil
	})
	a.saveNow()
}
