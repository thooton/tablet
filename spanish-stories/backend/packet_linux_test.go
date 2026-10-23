package main

import (
	"net"
	"path/filepath"
	"testing"
)

// Mirrors AppLoad: a SOCK_SEQPACKET listener that writes the header and the
// body as two separate packets.
func TestPacketTransport(t *testing.T) {
	sock := filepath.Join(t.TempDir(), "app.sock")
	ln, err := net.ListenUnix("unixpacket", &net.UnixAddr{Name: sock, Net: "unixpacket"})
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	accepted := make(chan *net.UnixConn)
	go func() {
		c, err := ln.AcceptUnix()
		if err != nil {
			t.Error(err)
		}
		accepted <- c
	}()
	client, err := dial(sock)
	if err != nil {
		t.Fatal(err)
	}
	server := <-accepted

	server.Write(encodeHeader(msgSystemNewCoordinator, 1))
	server.Write([]byte("1"))
	server.Write(encodeHeader(reqOpen, 11))
	server.Write([]byte(`{"id":"ab"}`))

	if typ, body, err := client.recv(); err != nil || typ != msgSystemNewCoordinator || string(body) != "1" {
		t.Fatalf("got %d %q %v", typ, body, err)
	}
	if typ, body, err := client.recv(); err != nil || typ != reqOpen || string(body) != `{"id":"ab"}` {
		t.Fatalf("got %d %q %v", typ, body, err)
	}

	big := make([]byte, 200000)
	for i := range big {
		big[i] = 'x'
	}
	if err := client.send(respStory, big); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, maxMessageLength)
	n, _ := server.Read(buf)
	typ, length, _ := decodeHeader(buf[:n])
	if n != 8 || typ != respStory || length != len(big) {
		t.Fatalf("header packet: n=%d type=%d len=%d", n, typ, length)
	}
	if n, _ = server.Read(buf); n != len(big) {
		t.Fatalf("body packet has %d bytes", n)
	}
	if err := client.send(1, nil); err == nil {
		t.Fatal("empty message should be refused")
	}
}
