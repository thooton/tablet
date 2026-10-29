package appload

import (
	"fmt"
	"os"
	"path/filepath"
)

var tag = "backend"

// Logf logs to stderr, each line tagged with the app's AppLoad id.
func Logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "["+tag+"] "+format+"\n", args...)
}

// Connect dials what AppLoad starts a backend with: the path of a unix
// socket as its only argument (the desktop emulator passes
// "tcp:<host>:<port>" instead). It exits when it can't. id is the app's
// AppLoad id, for Logf.
func Connect(id string) *Conn {
	tag = id
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: entry <unix socket path | tcp:host:port>")
		os.Exit(2)
	}
	conn, err := Dial(os.Args[1])
	if err != nil {
		Logf("cannot connect to %s: %v", os.Args[1], err)
		os.Exit(1)
	}
	return conn
}

// Serve hands every message to handle until the connection closes or AppLoad
// sends MsgTerminate, and meanwhile exits the process once an update has
// replaced it and no frontend is attached (see lifecycle.go). busy, if not
// nil, holds that exit back, as an install under way should.
//
// Never exit while a frontend is attached: a backend that quits while its
// app is open crashes the tablet's UI.
func Serve(conn *Conn, busy func() bool, handle func(msgType int32, body []byte)) {
	life := newLifecycle(executable(), busy)
	go life.watch()
	for {
		msgType, body, err := conn.Recv()
		if err != nil {
			Logf("connection closed: %v", err)
			return
		}
		life.seen(msgType, body)
		if msgType == MsgTerminate {
			return
		}
		handle(msgType, body)
	}
}

func executable() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	return exe
}

// Env is $name, or fallback when that is unset or empty.
func Env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

// DataDir is where an app keeps the user's data: $envName, or
// ~/.local/share/<name>.
func DataDir(envName, name string) string {
	return Env(envName, filepath.Join(Env("HOME", "/home/root"), ".local", "share", name))
}

// AppDir is $envName, or the app's folder in AppLoad, the one holding
// backend/entry.
func AppDir(envName string) string {
	if root := os.Getenv(envName); root != "" {
		return root
	}
	if exe, err := os.Executable(); err == nil {
		if exe, err = filepath.EvalSymlinks(exe); err == nil {
			return filepath.Dir(filepath.Dir(exe))
		}
	}
	wd, _ := os.Getwd()
	return wd
}

// WriteFile replaces path with data atomically, so a crash or power loss
// never leaves a torn file, making its folder first if need be (with perm's
// read bits as search bits too).
func WriteFile(path string, data []byte, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), perm|(perm&0o444)>>2); err != nil {
		return err
	}
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}
