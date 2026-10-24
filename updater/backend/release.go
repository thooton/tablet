package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// CI publishes every app in the repository to the rolling "latest" release
// of thooton/tablet as <dir>.tar.gz and <dir>.png, beside manifest.json,
// which describes them all (see .github/manifest.py at the repository root).
const defaultRelease = "https://github.com/thooton/tablet/releases/download/latest/"

// Manifest is manifest.json as CI writes it.
type Manifest struct {
	Schema int              `json:"schema"`
	Built  string           `json:"built"`
	Commit string           `json:"commit"`
	Apps   map[string]Entry `json:"apps"`
}

// Entry is one app: its directory in the repository is the key in Apps, the
// folder it unpacks to under /home/root, and the name of its release assets.
type Entry struct {
	ID         string `json:"id"` // AppLoad's id: its folder under the AppLoad root
	Name       string `json:"name"`
	Version    string `json:"version"`
	Archive    string `json:"archive"`
	Size       int64  `json:"size"`
	SHA256     string `json:"sha256"`
	Icon       string `json:"icon"`
	IconSHA256 string `json:"iconSha256"`
	Notes      []Note `json:"notes"`
}

// Note is one commit that touched the app, newest first.
type Note struct {
	Commit  string `json:"commit"`
	Time    string `json:"time"`
	Text    string `json:"text"`
	Version string `json:"version,omitempty"`
}

type release struct {
	base   string
	client *http.Client
}

func newRelease(base string) *release {
	if !strings.HasSuffix(base, "/") {
		base += "/"
	}
	return &release{base: base, client: &http.Client{}}
}

// fresh adds a query never used before, so that a release made a moment ago
// isn't hidden behind a cached copy of the last one.
func (r *release) fresh(name string) string {
	return r.base + name + "?t=" + strconv.FormatInt(time.Now().UnixNano(), 36)
}

func (r *release) get(ctx context.Context, name string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, r.fresh(name), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Cache-Control", "no-cache")
	resp, err := r.client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		if resp.StatusCode == http.StatusNotFound {
			return nil, fmt.Errorf("%s isn't in the release", name)
		}
		return nil, fmt.Errorf("%s: %s", name, resp.Status)
	}
	return resp, nil
}

func (r *release) manifest(ctx context.Context) (*Manifest, error) {
	ctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	resp, err := r.get(ctx, "manifest.json")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var m Manifest
	if err := json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(&m); err != nil {
		return nil, fmt.Errorf("manifest.json: %v", err)
	}
	if m.Schema != 1 {
		return nil, fmt.Errorf("unsupported manifest schema %d", m.Schema)
	}
	for dir, e := range m.Apps {
		if !validDir(dir) || e.ID == "" || !validDir(e.ID) || e.Version == "" || e.Archive == "" {
			return nil, fmt.Errorf("manifest.json: bad entry %q", dir)
		}
	}
	return &m, nil
}

// validDir is a plain file name: no slashes, no dot names.
func validDir(s string) bool {
	if s == "" || s == "." || s == ".." || strings.HasPrefix(s, ".") {
		return false
	}
	for _, c := range s {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.') {
			return false
		}
	}
	return true
}

// download saves the release's file name to dest, checking it against size
// and sha256 (either may be empty or 0 to skip). progress is called as the
// bytes arrive.
func (r *release) download(ctx context.Context, name, dest string, size int64, sum string, progress func(done, total int64)) error {
	resp, err := r.get(ctx, name)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	total := size
	if total <= 0 {
		total = resp.ContentLength
	}

	part := dest + ".part"
	f, err := os.Create(part)
	if err != nil {
		return err
	}
	defer os.Remove(part)
	h := sha256.New()
	var done int64
	buf := make([]byte, 64<<10)
	for {
		// A stalled connection is given up after a minute without data.
		timer := time.AfterFunc(time.Minute, func() { resp.Body.Close() })
		n, rerr := resp.Body.Read(buf)
		timer.Stop()
		if n > 0 {
			if _, err := f.Write(buf[:n]); err != nil {
				f.Close()
				return err
			}
			h.Write(buf[:n])
			done += int64(n)
			if size > 0 && done > size {
				f.Close()
				return fmt.Errorf("%s is bigger than the manifest says", name)
			}
			if progress != nil {
				progress(done, total)
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			f.Close()
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return fmt.Errorf("downloading %s: %v", name, rerr)
		}
	}
	if err := f.Close(); err != nil {
		return err
	}
	if size > 0 && done != size {
		return fmt.Errorf("%s arrived incomplete (%d of %d bytes)", name, done, size)
	}
	if sum != "" && !strings.EqualFold(hex.EncodeToString(h.Sum(nil)), sum) {
		return fmt.Errorf("%s doesn't match the manifest's SHA-256", name)
	}
	return os.Rename(part, dest)
}

var errClosing = errors.New("the Updater was closed")
