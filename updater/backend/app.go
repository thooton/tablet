package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Messages from the UI. Every answer is the whole state, as message 101.
const (
	msgCheck   int32 = 1 // fetch manifest.json again
	msgInstall int32 = 2 // {"apps": [dir, ...]}: queue them
	msgState   int32 = 3 // just send the state
	msgCancel  int32 = 4 // {"app": dir}: take a waiting app out of the queue

	msgStateReply int32 = 101
)

const selfDir = "updater"

// Job is one app on its way to the tablet.
type Job struct {
	Phase   string `json:"phase"` // waiting | downloading | installing | done | failed
	Percent int    `json:"percent"`
	Message string `json:"message,omitempty"` // why it failed
	From    string `json:"from"`              // the app's status when it was queued, which keeps its group in the list
}

// AppState is one row of the list.
type AppState struct {
	Dir              string `json:"dir"`
	ID               string `json:"id"`
	Name             string `json:"name"`
	Version          string `json:"version"`
	Installed        bool   `json:"installed"`
	InstalledVersion string `json:"installedVersion"`
	Status           string `json:"status"` // update | get | current | newer
	Size             int64  `json:"size"`
	Notes            []Note `json:"notes"`
	Icon             string `json:"icon"` // file:// URL, or "" before it has been fetched
	Job              *Job   `json:"job"`
}

// State is everything the UI shows.
type State struct {
	Checking bool       `json:"checking"`
	Checked  string     `json:"checked"` // when the manifest last arrived, RFC 3339
	Error    string     `json:"error"`
	Built    string     `json:"built"`
	Apps     []AppState `json:"apps"`
	Busy     bool       `json:"busy"`
	Reload   bool       `json:"reload"` // something was installed: AppLoad needs a Reload
}

type App struct {
	rel     *release
	appload string // AppLoad's app folder
	home    string // where packages unpack: <home>/<dir>
	cache   string
	send    func(int32, any)

	ctx    context.Context
	cancel context.CancelFunc

	mu       sync.Mutex
	manifest *Manifest
	checking bool
	checked  time.Time
	checkErr string
	icons    map[string]string // dir -> file URL
	jobs     map[string]*Job
	queue    []string
	working  bool
	reload   bool
	closing  bool
	lastSent map[string]int // dir -> percent last sent, to spare the e-ink
	idle     chan struct{}  // closed when the worker has stopped
}

func newApp(rel *release, appload, home, cache string, send func(int32, any)) *App {
	ctx, cancel := context.WithCancel(context.Background())
	return &App{
		rel: rel, appload: appload, home: home, cache: cache, send: send,
		ctx: ctx, cancel: cancel,
		icons: map[string]string{}, jobs: map[string]*Job{}, lastSent: map[string]int{},
	}
}

func (a *App) handle(msgType int32, body []byte) {
	switch msgType {
	case msgCheck:
		a.check()
	case msgInstall:
		var req struct {
			Apps []string `json:"apps"`
		}
		json.Unmarshal(body, &req)
		a.install(req.Apps)
	case msgCancel:
		var req struct {
			App string `json:"app"`
		}
		json.Unmarshal(body, &req)
		a.cancelQueued(req.App)
	case msgState, msgSystemNewCoordinator:
		// Opening the Updater checks for updates. The backend outlives the
		// window (see lifecycle.go), so a reopened one checks again unless
		// it checked a moment ago or is installing.
		a.mu.Lock()
		stale := !a.working && time.Since(a.checked) > time.Minute
		a.mu.Unlock()
		if stale {
			a.check()
		} else {
			a.publish()
		}
	}
}

// check fetches the manifest (and any icon not yet cached) in the
// background. A check already under way is not started again.
func (a *App) check() {
	a.mu.Lock()
	if a.checking || a.closing {
		a.mu.Unlock()
		a.publish()
		return
	}
	a.checking = true
	a.mu.Unlock()
	a.publish()

	go func() {
		m, err := a.rel.manifest(a.ctx)
		a.mu.Lock()
		a.checking = false
		if err != nil {
			a.checkErr = friendly(err)
			logf("check: %v", err)
		} else {
			a.manifest, a.checkErr, a.checked = m, "", time.Now()
		}
		a.mu.Unlock()
		a.publish()
		if m != nil {
			a.fetchIcons(m)
		}
	}()
}

func friendly(err error) string {
	s := err.Error()
	for _, offline := range []string{"no such host", "network is unreachable", "connection refused", "i/o timeout", "dial tcp"} {
		if strings.Contains(s, offline) {
			return "No connection."
		}
	}
	if strings.Contains(s, "certificate") {
		return "Certificate error: " + s
	}
	return s
}

func (a *App) fetchIcons(m *Manifest) {
	dir := filepath.Join(a.cache, "icons")
	os.MkdirAll(dir, 0o755)
	for app, e := range m.Apps {
		if e.Icon == "" || e.IconSHA256 == "" {
			continue
		}
		file := filepath.Join(dir, strings.ToLower(e.IconSHA256)+".png")
		if _, err := os.Stat(file); err != nil {
			if err := a.rel.download(a.ctx, e.Icon, file, 0, e.IconSHA256, nil); err != nil {
				logf("icon %s: %v", app, err)
				continue
			}
		}
		a.mu.Lock()
		a.icons[app] = "file://" + file
		a.mu.Unlock()
	}
	a.publish()
}

// install queues apps. The Updater itself always goes last: its install.sh
// replaces the program doing the installing.
func (a *App) install(apps []string) {
	a.mu.Lock()
	if a.manifest == nil || a.closing {
		a.mu.Unlock()
		return
	}
	for _, dir := range apps {
		if _, ok := a.manifest.Apps[dir]; !ok {
			continue
		}
		if j := a.jobs[dir]; j != nil && (j.Phase == "waiting" || j.Phase == "downloading" || j.Phase == "installing") {
			continue
		}
		a.jobs[dir] = &Job{Phase: "waiting", From: a.status(a.manifest.Apps[dir])}
		a.queue = append(a.queue, dir)
	}
	sort.SliceStable(a.queue, func(i, j int) bool { return a.queue[j] == selfDir && a.queue[i] != selfDir })
	start := !a.working && len(a.queue) > 0
	if start {
		a.working = true
		a.idle = make(chan struct{})
	}
	a.mu.Unlock()
	a.publish()
	if start {
		go a.work()
	}
}

func (a *App) cancelQueued(dir string) {
	a.mu.Lock()
	for i, d := range a.queue {
		if d == dir {
			a.queue = append(a.queue[:i], a.queue[i+1:]...)
			delete(a.jobs, dir)
			break
		}
	}
	a.mu.Unlock()
	a.publish()
}

func (a *App) work() {
	defer close(a.idle)
	for {
		a.mu.Lock()
		if len(a.queue) == 0 || a.closing {
			a.queue = nil
			a.working = false
			a.mu.Unlock()
			a.publish()
			return
		}
		dir := a.queue[0]
		a.queue = a.queue[1:]
		e := a.manifest.Apps[dir]
		a.mu.Unlock()

		err := a.installOne(dir, e)
		a.mu.Lock()
		j := a.jobs[dir]
		if err != nil {
			logf("install %s: %v", dir, err)
			a.jobs[dir] = &Job{Phase: "failed", Message: friendly(err), From: j.From}
		} else {
			a.jobs[dir] = &Job{Phase: "done", Percent: 100, From: j.From}
			a.reload = true
		}
		a.mu.Unlock()
		a.publish()
	}
}

func (a *App) setJob(dir, phase string, percent int) {
	a.mu.Lock()
	a.jobs[dir] = &Job{Phase: phase, Percent: percent, From: a.jobs[dir].From}
	last, seen := a.lastSent[dir]
	quiet := phase == "downloading" && seen && percent-last < 5 && percent < 100
	if !quiet {
		a.lastSent[dir] = percent
	}
	a.mu.Unlock()
	if !quiet {
		a.publish()
	}
}

func (a *App) installOne(dir string, e Entry) error {
	if err := os.MkdirAll(a.cache, 0o755); err != nil {
		return err
	}
	// One install at a time, even across a backend still finishing an
	// update after the Updater was closed and a new one opened.
	unlock, err := lockFile(filepath.Join(a.cache, "lock"))
	if err != nil {
		return err
	}
	defer unlock()

	a.setJob(dir, "downloading", 0)
	archive := filepath.Join(a.cache, dir+".tar.gz")
	defer os.Remove(archive)
	err = a.rel.download(a.ctx, e.Archive, archive, e.Size, e.SHA256, func(done, total int64) {
		if total > 0 {
			a.setJob(dir, "downloading", int(done*100/total))
		}
	})
	if err != nil {
		if a.ctx.Err() != nil {
			return errClosing
		}
		return err
	}

	// From here on, finish even if the Updater is closed: stopping halfway
	// would leave the app half replaced.
	a.setJob(dir, "installing", 100)
	stage := filepath.Join(a.cache, "stage")
	os.RemoveAll(stage)
	defer os.RemoveAll(stage)
	if err := unpack(archive, dir, stage); err != nil {
		return err
	}
	if data, err := os.ReadFile(filepath.Join(stage, dir, "app", "manifest.json")); err == nil {
		var m struct {
			ID string `json:"id"`
		}
		json.Unmarshal(data, &m)
		if m.ID != e.ID {
			return fmt.Errorf("the archive is AppLoad app %q, not %q", m.ID, e.ID)
		}
	}
	pkg := filepath.Join(a.home, dir)
	if err := os.MkdirAll(pkg, 0o755); err != nil {
		return err
	}
	if err := merge(filepath.Join(stage, dir), pkg); err != nil {
		return err
	}
	out, err := runInstall(context.Background(), pkg, a.appload)
	if out != "" {
		logf("%s/install.sh: %s", dir, out)
	}
	if err != nil {
		if tail := lastLines(out, 4); tail != "" {
			return fmt.Errorf("%v: %s", err, tail)
		}
		return err
	}
	if v, ok := installedVersion(a.appload, e.ID); !ok || v != e.Version {
		return fmt.Errorf("install.sh finished, but AppLoad has version %q, not %s", v, e.Version)
	}
	return nil
}

func (a *App) state() State {
	a.mu.Lock()
	defer a.mu.Unlock()
	s := State{Checking: a.checking, Error: a.checkErr, Busy: a.working, Reload: a.reload, Apps: []AppState{}}
	if !a.checked.IsZero() {
		s.Checked = a.checked.Format(time.RFC3339)
	}
	if a.manifest == nil {
		return s
	}
	s.Built = a.manifest.Built
	for dir, e := range a.manifest.Apps {
		v, ok := installedVersion(a.appload, e.ID)
		st := AppState{
			Dir: dir, ID: e.ID, Name: e.Name, Version: e.Version, Size: e.Size, Notes: e.Notes,
			Installed: ok, InstalledVersion: v, Icon: a.icons[dir], Job: a.jobs[dir],
		}
		if st.Name == "" {
			st.Name = dir
		}
		if st.Notes == nil {
			st.Notes = []Note{}
		}
		st.Status = a.status(e)
		s.Apps = append(s.Apps, st)
	}
	sort.Slice(s.Apps, func(i, j int) bool { return strings.ToLower(s.Apps[i].Name) < strings.ToLower(s.Apps[j].Name) })
	return s
}

// status is what the tablet has of an app, next to the release.
func (a *App) status(e Entry) string {
	v, ok := installedVersion(a.appload, e.ID)
	switch {
	case !ok:
		return "get"
	case v == "" || compareVersions(v, e.Version) < 0:
		return "update"
	case compareVersions(v, e.Version) == 0:
		return "current"
	default:
		return "newer"
	}
}

func (a *App) busy() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.working || a.checking
}

func (a *App) publish() {
	a.send(msgStateReply, a.state())
}

// close is AppLoad stopping the backend (-1, or the socket closing), which
// only happens if something calls terminate(): closing the window leaves the
// backend running, installs and all. Apps still waiting are dropped and a
// download stops; an install already unpacking finishes. It returns once
// nothing is left running.
func (a *App) close() {
	a.mu.Lock()
	a.closing = true
	a.queue = nil
	idle := a.idle
	a.mu.Unlock()
	a.cancel()
	if idle != nil {
		<-idle
	}
}
