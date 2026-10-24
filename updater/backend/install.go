package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// compareVersions compares "1.2.10" with "1.2.9" part by part, numbers as
// numbers (so 1.2.10 is newer). A missing part counts as 0, and a part that
// isn't a number compares as text after every number.
func compareVersions(a, b string) int {
	pa, pb := strings.Split(strings.TrimPrefix(a, "v"), "."), strings.Split(strings.TrimPrefix(b, "v"), ".")
	for i := 0; i < len(pa) || i < len(pb); i++ {
		x, y := "0", "0"
		if i < len(pa) {
			x = pa[i]
		}
		if i < len(pb) {
			y = pb[i]
		}
		nx, ex := strconv.Atoi(x)
		ny, ey := strconv.Atoi(y)
		switch {
		case ex == nil && ey == nil:
			if nx != ny {
				if nx < ny {
					return -1
				}
				return 1
			}
		case ex == nil:
			return -1
		case ey == nil:
			return 1
		default:
			if c := strings.Compare(x, y); c != 0 {
				return c
			}
		}
	}
	return 0
}

// installedVersion reads the version from the manifest.json AppLoad has for
// the app (install.sh copies it there). ok is false when AppLoad doesn't
// have the app; version is "" for a copy installed before apps had versions.
func installedVersion(appload, id string) (version string, ok bool) {
	data, err := os.ReadFile(filepath.Join(appload, id, "manifest.json"))
	if err != nil {
		return "", false
	}
	var m struct {
		Version string `json:"version"`
	}
	json.Unmarshal(data, &m)
	return m.Version, true
}

const maxUnpacked = 512 << 20

// unpack extracts a release archive into stage. Every entry must sit under
// dir/ and be a plain file or folder: no links, devices or paths that climb
// out. The archive must hold dir/install.sh.
func unpack(archive, dir, stage string) error {
	f, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("%s isn't a .tar.gz: %v", filepath.Base(archive), err)
	}
	tr := tar.NewReader(gz)
	var total int64
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading %s: %v", filepath.Base(archive), err)
		}
		name := path.Clean(h.Name)
		if name != dir && !strings.HasPrefix(name, dir+"/") {
			return fmt.Errorf("%s holds %q, outside %s/", filepath.Base(archive), h.Name, dir)
		}
		target := filepath.Join(stage, filepath.FromSlash(name))
		switch h.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
		case tar.TypeReg:
			total += h.Size
			if total > maxUnpacked {
				return fmt.Errorf("%s unpacks to more than %d MB", filepath.Base(archive), maxUnpacked>>20)
			}
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			mode := os.FileMode(0o644)
			if h.Mode&0o111 != 0 {
				mode = 0o755
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
			if err != nil {
				return err
			}
			_, err = io.Copy(out, io.LimitReader(tr, h.Size))
			if cerr := out.Close(); err == nil {
				err = cerr
			}
			if err != nil {
				return err
			}
		default:
			return fmt.Errorf("%s holds %q, which isn't a plain file or folder", filepath.Base(archive), h.Name)
		}
	}
	if _, err := os.Stat(filepath.Join(stage, dir, "install.sh")); err != nil {
		return fmt.Errorf("%s has no %s/install.sh", filepath.Base(archive), dir)
	}
	return nil
}

// merge moves everything in from over into to, replacing files of the same
// name and leaving the rest of to alone (such as stories the user added),
// as unpacking the archive over the folder by hand would.
func merge(from, to string) error {
	return filepath.Walk(from, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(from, p)
		dest := filepath.Join(to, rel)
		if info.IsDir() {
			if st, err := os.Lstat(dest); err == nil && !st.IsDir() {
				if err := os.Remove(dest); err != nil {
					return err
				}
			}
			return os.MkdirAll(dest, 0o755)
		}
		if st, err := os.Lstat(dest); err == nil && st.IsDir() {
			if err := os.RemoveAll(dest); err != nil {
				return err
			}
		}
		if err := os.Rename(p, dest); err == nil {
			return nil
		}
		return copyFile(p, dest, info.Mode())
	})
}

func copyFile(from, to string, mode os.FileMode) error {
	in, err := os.Open(from)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := to + ".updater-new"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(tmp)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, to)
}

// runInstall runs the package's install.sh as the user would over SSH, and
// returns what it printed.
func runInstall(ctx context.Context, pkg, appload string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "/bin/sh", filepath.Join(pkg, "install.sh"))
	cmd.Dir = pkg
	cmd.Env = append(os.Environ(), "APPLOAD_DIR="+appload)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	text := strings.TrimSpace(out.String())
	if ctx.Err() == context.DeadlineExceeded {
		return text, errors.New("install.sh took more than 3 minutes")
	}
	if err != nil {
		return text, fmt.Errorf("install.sh failed (%v)", err)
	}
	return text, nil
}

// lastLines is the end of a script's output, for an error message.
func lastLines(s string, n int) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}
