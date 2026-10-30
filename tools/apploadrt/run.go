package apploadrt

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"
)

// Logger writes "[tag] ..." lines to stderr, which AppLoad keeps in its log.
func Logger(tag string) func(format string, args ...any) {
	return func(format string, args ...any) {
		fmt.Fprintf(os.Stderr, "["+tag+"] "+format+"\n", args...)
	}
}

// Env is the environment variable name, or fallback when it is empty.
func Env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

// Connect dials the address AppLoad passes as the first argument, exiting
// when there is none or it cannot be reached.
func Connect(logf func(string, ...any)) Transport {
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

// Sender sends a JSON body as a message of the given type from any
// goroutine, logging what fails.
func Sender(conn Transport, logf func(string, ...any)) func(msgType int32, body any) {
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

// Serve hands each message to handle until the connection closes, AppLoad
// terminates the backend, or handle fails. Its Lifecycle watches for an
// update on disk meanwhile; busy (may be nil) holds off the exit.
func Serve(conn Transport, busy func() bool, logf func(string, ...any), handle func(msgType int32, body []byte) error) {
	life := NewLifecycle(busy, logf)
	go life.Watch()
	for {
		msgType, body, err := conn.Recv()
		if err != nil {
			logf("connection closed: %v", err)
			return
		}
		life.Seen(msgType, body)
		if msgType == MsgTerminate || handle(msgType, body) != nil {
			return
		}
	}
}
