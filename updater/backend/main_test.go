package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/thooton/tablet/tools/appload"
)

func TestCompareVersions(t *testing.T) {
	for _, c := range []struct {
		a, b string
		want int
	}{
		{"1.0.0", "1.0.0", 0},
		{"1.0", "1.0.0", 0},
		{"1.2.9", "1.2.10", -1},
		{"2.0.0", "1.9.9", 1},
		{"v1.1.0", "1.1.0", 0},
		{"1.0.0", "1.0.0-beta", -1},
	} {
		if got := compareVersions(c.a, c.b); got != c.want {
			t.Errorf("compareVersions(%q, %q) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

type file struct {
	name, body string
	mode       int64
	kind       byte
}

func tarGz(t *testing.T, files []file) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, f := range files {
		h := &tar.Header{Name: f.name, Mode: f.mode, Size: int64(len(f.body)), Typeflag: f.kind}
		if h.Typeflag == 0 {
			h.Typeflag = tar.TypeReg
		}
		if h.Mode == 0 {
			h.Mode = 0o644
		}
		if h.Typeflag == tar.TypeSymlink {
			h.Linkname, h.Size = f.body, 0
		}
		if err := tw.WriteHeader(h); err != nil {
			t.Fatal(err)
		}
		if h.Typeflag == tar.TypeReg {
			tw.Write([]byte(f.body))
		}
	}
	tw.Close()
	gz.Close()
	return buf.Bytes()
}

func TestUnpackRefusesEscapes(t *testing.T) {
	for name, files := range map[string][]file{
		"climbs out":    {{name: "demo/install.sh", body: "true"}, {name: "demo/../../evil", body: "x"}},
		"other folder":  {{name: "demo/install.sh", body: "true"}, {name: "other/x", body: "x"}},
		"symlink":       {{name: "demo/install.sh", body: "true"}, {name: "demo/link", body: "/etc", kind: tar.TypeSymlink}},
		"no install.sh": {{name: "demo/app/manifest.json", body: "{}"}},
	} {
		dir := t.TempDir()
		archive := filepath.Join(dir, "a.tar.gz")
		os.WriteFile(archive, tarGz(t, files), 0o644)
		if err := unpack(archive, "demo", filepath.Join(dir, "stage")); err == nil {
			t.Errorf("%s: unpacked", name)
		}
	}
}

func TestMergeKeepsOtherFiles(t *testing.T) {
	from, to := t.TempDir(), t.TempDir()
	os.MkdirAll(filepath.Join(from, "stories"), 0o755)
	os.WriteFile(filepath.Join(from, "stories", "a.json"), []byte("new"), 0o644)
	os.MkdirAll(filepath.Join(to, "stories"), 0o755)
	os.WriteFile(filepath.Join(to, "stories", "a.json"), []byte("old"), 0o644)
	os.WriteFile(filepath.Join(to, "stories", "mine.json"), []byte("mine"), 0o644)
	if err := merge(from, to); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(to, "stories", "a.json")); string(b) != "new" {
		t.Errorf("a.json = %q, want new", b)
	}
	if b, _ := os.ReadFile(filepath.Join(to, "stories", "mine.json")); string(b) != "mine" {
		t.Errorf("mine.json = %q, want it kept", b)
	}
}

// A fake release with two apps whose install.sh does what a real one does:
// copy app/ into AppLoad's folder.
const installScript = `#!/bin/sh
set -e
PKG="$(cd "$(dirname "$0")" && pwd)"
ID=$(sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' "$PKG/app/manifest.json")
rm -rf "$APPLOAD_DIR/$ID"
mkdir -p "$APPLOAD_DIR"
cp -r "$PKG/app" "$APPLOAD_DIR/$ID"
echo "installed $ID"
`

type fakeRelease struct {
	server  *httptest.Server
	mu      sync.Mutex
	assets  map[string][]byte
	fetched []string
}

func newFakeRelease(t *testing.T) *fakeRelease {
	f := &fakeRelease{assets: map[string][]byte{}}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, "/")
		f.mu.Lock()
		data, ok := f.assets[name]
		f.fetched = append(f.fetched, name)
		f.mu.Unlock()
		if !ok {
			http.NotFound(w, r)
			return
		}
		w.Write(data)
	}))
	t.Cleanup(f.server.Close)
	return f
}

func (f *fakeRelease) addApp(t *testing.T, m *Manifest, dir, id, version, extra string) {
	manifest := `{"id": "` + id + `", "name": "` + dir + `", "entry": "/ui/main.qml", "version": "` + version + `"}`
	files := []file{
		{name: dir + "/install.sh", body: installScript, mode: 0o755},
		{name: dir + "/app/manifest.json", body: manifest},
	}
	if extra != "" {
		files = append(files, file{name: dir + "/" + extra, body: "data"})
	}
	data := tarGz(t, files)
	sum := sha256.Sum256(data)
	f.assets[dir+".tar.gz"] = data
	m.Apps[dir] = Entry{ID: id, Name: dir, Version: version, Archive: dir + ".tar.gz",
		Size: int64(len(data)), SHA256: hex.EncodeToString(sum[:])}
}

func (f *fakeRelease) publish(m *Manifest) {
	data, _ := json.Marshal(m)
	f.mu.Lock()
	f.assets["manifest.json"] = data
	f.mu.Unlock()
}

type recorder struct {
	mu     sync.Mutex
	states []State
}

func (r *recorder) send(msgType int32, body any) {
	if msgType != msgStateReply {
		return
	}
	r.mu.Lock()
	r.states = append(r.states, body.(State))
	r.mu.Unlock()
}

func (r *recorder) last() State {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.states) == 0 {
		return State{}
	}
	return r.states[len(r.states)-1]
}

func (r *recorder) waitFor(t *testing.T, what string, ok func(State) bool) State {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if s := r.last(); ok(s) {
			return s
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s; last state %+v", what, r.last())
	return State{}
}

func find(s State, dir string) AppState {
	for _, a := range s.Apps {
		if a.Dir == dir {
			return a
		}
	}
	return AppState{}
}

func TestCheckAndInstall(t *testing.T) {
	if _, err := os.Stat("/bin/sh"); err != nil {
		t.Skip("needs /bin/sh")
	}
	f := newFakeRelease(t)
	m := &Manifest{Schema: 1, Apps: map[string]Entry{}}
	f.addApp(t, m, "updater", "updater", "1.0.1", "")
	f.addApp(t, m, "stories", "story-reader", "1.2.0", "stories/new.json")
	f.addApp(t, m, "fresh", "fresh-app", "0.1.0", "")
	f.publish(m)

	home := t.TempDir()
	appload := filepath.Join(home, "appload")
	// Installed already: the Updater (older), the reader (an old copy with
	// no version) with a story the user added.
	os.MkdirAll(filepath.Join(appload, "updater"), 0o755)
	os.WriteFile(filepath.Join(appload, "updater", "manifest.json"), []byte(`{"id":"updater","version":"1.0.0"}`), 0o644)
	os.MkdirAll(filepath.Join(appload, "story-reader"), 0o755)
	os.WriteFile(filepath.Join(appload, "story-reader", "manifest.json"), []byte(`{"id":"story-reader"}`), 0o644)
	os.MkdirAll(filepath.Join(home, "stories", "stories"), 0o755)
	os.WriteFile(filepath.Join(home, "stories", "stories", "mine.json"), []byte("mine"), 0o644)

	rec := &recorder{}
	app := newApp(newRelease(f.server.URL), appload, home, filepath.Join(home, ".cache", "updater"), rec.send)
	defer app.close()

	app.handle(msgCheck, nil)
	s := rec.waitFor(t, "the manifest", func(s State) bool { return !s.Checking && len(s.Apps) == 3 })
	if s.Error != "" {
		t.Fatalf("check failed: %s", s.Error)
	}
	for dir, want := range map[string]string{"updater": "update", "stories": "update", "fresh": "get"} {
		if got := find(s, dir).Status; got != want {
			t.Errorf("%s: status %q, want %q", dir, got, want)
		}
	}

	app.handle(msgInstall, []byte(`{"apps": ["updater", "stories", "fresh"]}`))
	s = rec.waitFor(t, "the installs", func(s State) bool { return !s.Busy && s.Reload })
	for _, dir := range []string{"updater", "stories", "fresh"} {
		a := find(s, dir)
		if a.Status != "current" || a.Job == nil || a.Job.Phase != "done" {
			t.Errorf("%s: status %q, job %+v", dir, a.Status, a.Job)
		}
	}
	if b, _ := os.ReadFile(filepath.Join(home, "stories", "stories", "mine.json")); string(b) != "mine" {
		t.Error("the user's own story was lost")
	}
	if _, err := os.Stat(filepath.Join(home, "stories", "stories", "new.json")); err != nil {
		t.Error("the new story wasn't unpacked")
	}

	// The Updater went last, though it was asked for first.
	var order []string
	f.mu.Lock()
	for _, name := range f.fetched {
		if strings.HasSuffix(name, ".tar.gz") {
			order = append(order, name)
		}
	}
	f.mu.Unlock()
	if len(order) != 3 || order[2] != "updater.tar.gz" {
		t.Errorf("downloads in order %v, want updater.tar.gz last", order)
	}
}

// After an install the row shows DONE, but that mark is transient: a new
// release turns the row back into an UPDATE (the done job is dropped), and a
// plain re-check with no new release clears it too. This is the bug where a
// just-updated app stayed stuck under UPDATES showing DONE and wouldn't offer
// the next version without being reopened by hand.
func TestDoneMarkClears(t *testing.T) {
	if _, err := os.Stat("/bin/sh"); err != nil {
		t.Skip("needs /bin/sh")
	}
	f := newFakeRelease(t)
	m := &Manifest{Schema: 1, Apps: map[string]Entry{}}
	f.addApp(t, m, "demo", "demo", "1.0.0", "")
	f.publish(m)

	home := t.TempDir()
	apploadDir := filepath.Join(home, "appload")
	rec := &recorder{}
	app := newApp(newRelease(f.server.URL), apploadDir, home, filepath.Join(home, "cache"), rec.send)
	defer app.close()

	app.handle(msgCheck, nil)
	rec.waitFor(t, "the manifest", func(s State) bool { return !s.Checking && len(s.Apps) == 1 })
	if got := find(rec.last(), "demo").Status; got != "get" {
		t.Fatalf("demo: status %q, want get", got)
	}

	app.handle(msgInstall, []byte(`{"apps": ["demo"]}`))
	rec.waitFor(t, "the install", func(s State) bool {
		a := find(s, "demo")
		return !s.Busy && a.Status == "current" && a.Job != nil && a.Job.Phase == "done"
	})

	// A new release: the done mark is dropped and the row offers the update.
	f.addApp(t, m, "demo", "demo", "1.1.0", "")
	f.publish(m)
	app.handle(msgCheck, nil)
	s := rec.waitFor(t, "the newer release", func(s State) bool {
		return !s.Checking && find(s, "demo").Version == "1.1.0"
	})
	if a := find(s, "demo"); a.Status != "update" || a.Job != nil {
		t.Fatalf("after a new release: status %q, job %+v; want update with no job", a.Status, a.Job)
	}

	// Install the newer one, then re-check with nothing new: DONE still clears.
	app.handle(msgInstall, []byte(`{"apps": ["demo"]}`))
	rec.waitFor(t, "the second install", func(s State) bool {
		a := find(s, "demo")
		return !s.Busy && a.Status == "current" && a.Job != nil && a.Job.Phase == "done"
	})

	// Reopening a moment later (what AppLoad and the UI send on opening)
	// shows the state as it is: DONE stays.
	app.handle(appload.MsgNewCoordinator, []byte("1"))
	app.handle(msgState, nil)
	time.Sleep(200 * time.Millisecond)
	if s := rec.last(); s.Checking || find(s, "demo").Job == nil || find(s, "demo").Job.Phase != "done" {
		t.Fatalf("after reopening: checking %v, job %+v; want DONE kept", s.Checking, find(s, "demo").Job)
	}

	app.handle(msgCheck, nil)
	s = rec.waitFor(t, "the re-check", func(s State) bool { return !s.Checking })
	if a := find(s, "demo"); a.Status != "current" || a.Job != nil {
		t.Fatalf("after a plain re-check: status %q, job %+v; want current with no job", a.Status, a.Job)
	}
}

// A failed install keeps its RETRY until a new release supersedes it.
func TestFailedMarkClearsOnNewRelease(t *testing.T) {
	f := newFakeRelease(t)
	m := &Manifest{Schema: 1, Apps: map[string]Entry{}}
	f.addApp(t, m, "demo", "demo", "1.0.0", "")
	e := m.Apps["demo"]
	e.SHA256 = strings.Repeat("0", 64) // wrong checksum: the install fails
	m.Apps["demo"] = e
	f.publish(m)

	home := t.TempDir()
	rec := &recorder{}
	app := newApp(newRelease(f.server.URL), filepath.Join(home, "appload"), home, filepath.Join(home, "cache"), rec.send)
	defer app.close()
	app.handle(msgCheck, nil)
	rec.waitFor(t, "the manifest", func(s State) bool { return len(s.Apps) == 1 })
	app.handle(msgInstall, []byte(`{"apps": ["demo"]}`))
	rec.waitFor(t, "the failure", func(s State) bool {
		a := find(s, "demo")
		return !s.Busy && a.Job != nil && a.Job.Phase == "failed"
	})

	// A re-check with the same release keeps the failure and its RETRY.
	app.handle(msgCheck, nil)
	s := rec.waitFor(t, "the re-check", func(s State) bool { return !s.Checking })
	if a := find(s, "demo"); a.Job == nil || a.Job.Phase != "failed" {
		t.Fatalf("same release: job %+v, want the failure kept", a.Job)
	}

	// A new release drops the stale failure so the fresh version shows plainly.
	f.addApp(t, m, "demo", "demo", "1.1.0", "") // a good archive this time
	f.publish(m)
	app.handle(msgCheck, nil)
	s = rec.waitFor(t, "the newer release", func(s State) bool {
		return !s.Checking && find(s, "demo").Version == "1.1.0"
	})
	if a := find(s, "demo"); a.Job != nil {
		t.Fatalf("new release: job %+v, want the stale failure gone", a.Job)
	}
}

func TestInstallRefusesBadChecksum(t *testing.T) {
	f := newFakeRelease(t)
	m := &Manifest{Schema: 1, Apps: map[string]Entry{}}
	f.addApp(t, m, "demo", "demo", "1.0.0", "")
	e := m.Apps["demo"]
	e.SHA256 = strings.Repeat("0", 64)
	m.Apps["demo"] = e
	f.publish(m)

	home := t.TempDir()
	rec := &recorder{}
	app := newApp(newRelease(f.server.URL), filepath.Join(home, "appload"), home, filepath.Join(home, "cache"), rec.send)
	defer app.close()
	app.handle(msgCheck, nil)
	rec.waitFor(t, "the manifest", func(s State) bool { return len(s.Apps) == 1 })
	app.handle(msgInstall, []byte(`{"apps": ["demo"]}`))
	s := rec.waitFor(t, "the failure", func(s State) bool {
		return !s.Busy && find(s, "demo").Job != nil && find(s, "demo").Job.Phase == "failed"
	})
	if msg := find(s, "demo").Job.Message; !strings.Contains(msg, "SHA-256") {
		t.Errorf("message %q doesn't mention the checksum", msg)
	}
	if _, err := os.Stat(filepath.Join(home, "demo")); err == nil {
		t.Error("a bad download was unpacked")
	}
}

func TestCheckOffline(t *testing.T) {
	rec := &recorder{}
	home := t.TempDir()
	app := newApp(newRelease("http://127.0.0.1:1/"), home, home, home, rec.send)
	defer app.close()
	app.handle(msgCheck, nil)
	s := rec.waitFor(t, "the error", func(s State) bool { return !s.Checking && s.Error != "" })
	if s.Error != "No connection." {
		t.Errorf("error %q", s.Error)
	}
}
