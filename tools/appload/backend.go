package appload

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

type Logf func(format string, args ...any)

// Logger logs to stderr, each line led by [name].
func Logger(name string) Logf {
	return func(format string, args ...any) {
		fmt.Fprintf(os.Stderr, "["+name+"] "+format+"\n", args...)
	}
}

// Env is $name, or fallback when that is unset or empty.
func Env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

// AppRoot is $env, or the app's folder in AppLoad (the binary runs as
// <app dir>/backend/entry), or failing that the working directory.
func AppRoot(env string) string {
	if root := os.Getenv(env); root != "" {
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

// DataDir is $env, or ~/.local/share/<name>.
func DataDir(env, name string) string {
	return Env(env, filepath.Join(Env("HOME", "/home/root"), ".local", "share", name))
}

// Connect dials what AppLoad starts the backend with: the path of a unix
// socket as its only argument (the emulator passes "tcp:<host>:<port>").
// It exits when there is none or it can't connect.
func Connect(logf Logf) Conn {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: entry <unix socket path | tcp:host:port>")
		os.Exit(2)
	}
	conn, err := Dial(os.Args[1])
	if err != nil {
		logf("cannot connect to %s: %v", os.Args[1], err)
		os.Exit(1)
	}
	return conn
}

// Serve hands handle every message from AppLoad, Terminate included, until
// the connection closes or AppLoad sends Terminate, and meanwhile exits the
// process when Lifecycle says so (busy may be nil). It never exits while
// the app is open: a backend that quits then crashes the tablet's UI.
func Serve(conn Conn, logf Logf, busy func() bool, handle func(msgType int32, body []byte)) {
	life := NewLifecycle(Executable(), busy)
	go life.Watch(logf)
	for {
		msgType, body, err := conn.Recv()
		if err != nil {
			logf("connection closed: %v", err)
			return
		}
		life.Seen(msgType, body)
		handle(msgType, body)
		if msgType == MsgTerminate {
			return
		}
	}
}

// JSONSender sends body as JSON, safely from any goroutine, and logs what
// fails.
func JSONSender(conn Conn, logf Logf) func(msgType int32, body any) {
	var mu sync.Mutex
	return func(msgType int32, body any) {
		data, err := json.Marshal(body)
		if err != nil {
			logf("encoding message %d: %v", msgType, err)
			return
		}
		mu.Lock()
		defer mu.Unlock()
		if err := conn.Send(msgType, data); err != nil {
			logf("sending message %d: %v", msgType, err)
		}
	}
}
