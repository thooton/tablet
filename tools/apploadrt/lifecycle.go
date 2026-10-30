package apploadrt

import (
	"os"
	"strconv"
	"sync"
	"time"
)

// AppLoad starts a backend when its app opens and leaves it running when the
// app closes; the next open reuses it (AppLoad sends -2 again). The frontend
// must never stop it: a backend that exits, or terminate() called from QML,
// makes AppLoad unload the app from its socket thread, off the GUI thread,
// and with a frontend still being torn down that crashes the tablet's UI
// (it restarts). So a backend lives until the tablet restarts, with one
// exception: once install.sh has replaced its binary (an update), it exits
// by itself when no frontend has been attached for a while, so the next
// open starts the new one. With no frontend left, AppLoad has nothing to
// unload.

const idleBeforeExit = 5 * time.Second

// Lifecycle tracks the attached frontends and exits the process after an
// update.
type Lifecycle struct {
	mu        sync.Mutex
	frontends int
	idleSince time.Time
	exe       string
	start     os.FileInfo
	busy      func() bool // work that must finish first, such as an install
	logf      func(format string, args ...any)
}

// NewLifecycle watches the running binary; busy (may be nil) says whether
// work that must finish first is going on.
func NewLifecycle(busy func() bool, logf func(string, ...any)) *Lifecycle {
	exe, _ := os.Executable()
	l := &Lifecycle{frontends: 1, exe: exe, busy: busy, logf: logf}
	if exe != "" {
		l.start, _ = os.Stat(exe)
	}
	return l
}

// Seen notes AppLoad's -2 and -3, whose body is how many frontends remain.
func (l *Lifecycle) Seen(msgType int32, body []byte) {
	if msgType != MsgNewCoordinator && msgType != MsgLostCoordinator {
		return
	}
	n, err := strconv.Atoi(string(body))
	if err != nil {
		return
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	if n == 0 && l.frontends != 0 {
		l.idleSince = time.Now()
	}
	l.frontends = n
}

// replaced is whether the file the backend started from is gone or is now
// another file.
func (l *Lifecycle) replaced() bool {
	if l.start == nil {
		return false
	}
	now, err := os.Stat(l.exe)
	return err != nil || !os.SameFile(l.start, now)
}

func (l *Lifecycle) shouldExit(now time.Time) bool {
	l.mu.Lock()
	idle := l.frontends == 0 && now.Sub(l.idleSince) >= idleBeforeExit
	l.mu.Unlock()
	return idle && (l.busy == nil || !l.busy()) && l.replaced()
}

// Watch exits the process once shouldExit says so.
func (l *Lifecycle) Watch() {
	for range time.Tick(2 * time.Second) {
		if l.shouldExit(time.Now()) {
			l.logf("updated on disk and no frontend attached: exiting so the next open starts the new version")
			os.Exit(0)
		}
	}
}
