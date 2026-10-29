// Command entry is the AppLoad backend of Flashcards (see tools/appload for
// how AppLoad runs it).
//
// It keeps the tablet's copy of the flashcards (collection.go), schedules
// them with FSRS-6 as the phone does (fsrs.go, session.go), and syncs them
// with the command center, which it pairs with first (center.go).
package main

import (
	"os"
	"path/filepath"
	_ "time/tzdata" // the tablet has no zoneinfo; the day rolls over in the phone's zone

	"github.com/thooton/tablet/tools/appload"
)

var logf = appload.Logf

func main() {
	conn := appload.Connect("flashcards")
	defer conn.Close()

	dir := appload.DataDir("FLASHCARDS_DATA", "flashcards")
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

	a := newApp(col, newCenter(dir), conn.SendJSON)
	logf("started; data in %s, %d cards", dir, len(col.Cards))
	appload.Serve(conn, a.busy, a.handle)
	a.saveNow()
}
