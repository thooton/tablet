package apploadrt

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLifecycleExitsOnlyWhenReplacedAndIdle(t *testing.T) {
	exe := filepath.Join(t.TempDir(), "entry")
	os.WriteFile(exe, []byte("old"), 0o755)
	busy := false
	l := NewLifecycle(func() bool { return busy }, t.Logf)
	l.exe = exe
	l.start, _ = os.Stat(exe)
	now := time.Now()

	if l.shouldExit(now.Add(time.Minute)) {
		t.Fatal("exits with a frontend attached and nothing replaced")
	}
	l.Seen(MsgLostCoordinator, []byte("0"))
	if l.shouldExit(time.Now().Add(time.Minute)) {
		t.Fatal("exits though its binary is unchanged")
	}

	// install.sh replaces the folder: a new file at the same path.
	os.WriteFile(exe+".new", []byte("new"), 0o755)
	os.Rename(exe+".new", exe)
	if l.shouldExit(time.Now()) {
		t.Fatal("exits the moment the last frontend went")
	}
	if !l.shouldExit(time.Now().Add(time.Minute)) {
		t.Fatal("doesn't exit once replaced and idle")
	}
	busy = true
	if l.shouldExit(time.Now().Add(time.Minute)) {
		t.Fatal("exits while busy")
	}
	busy = false
	l.Seen(MsgNewCoordinator, []byte("1"))
	if l.shouldExit(time.Now().Add(time.Minute)) {
		t.Fatal("exits with a frontend attached again")
	}
}
