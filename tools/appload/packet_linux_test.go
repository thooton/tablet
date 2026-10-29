package appload

import (
	"net"
	"path/filepath"
	"testing"
)

// Listen mirrors AppLoad: a SOCK_SEQPACKET socket a backend dials. It
// returns the backend's end and AppLoad's.
func listen(t *testing.T) (*Conn, *net.UnixConn) {
	sock := filepath.Join(t.TempDir(), "app.sock")
	ln, err := net.ListenUnix("unixpacket", &net.UnixAddr{Name: sock, Net: "unixpacket"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	accepted := make(chan *net.UnixConn)
	go func() {
		c, err := ln.AcceptUnix()
		if err != nil {
			t.Error(err)
		}
		accepted <- c
	}()
	client, err := Dial(sock)
	if err != nil {
		t.Fatal(err)
	}
	return client, <-accepted
}

// AppLoad writes the header and the body as two separate packets.
func TestPacketTransport(t *testing.T) {
	client, server := listen(t)

	server.Write(EncodeHeader(MsgNewCoordinator, 1))
	server.Write([]byte("1"))
	server.Write(EncodeHeader(2, 11))
	server.Write([]byte(`{"id":"ab"}`))

	if typ, body, err := client.Recv(); err != nil || typ != MsgNewCoordinator || string(body) != "1" {
		t.Fatalf("got %d %q %v", typ, body, err)
	}
	if typ, body, err := client.Recv(); err != nil || typ != 2 || string(body) != `{"id":"ab"}` {
		t.Fatalf("got %d %q %v", typ, body, err)
	}

	big := make([]byte, 200000)
	for i := range big {
		big[i] = 'x'
	}
	if err := client.Send(102, big); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, MaxMessageLength)
	n, _ := server.Read(buf)
	typ, length, _ := DecodeHeader(buf[:n])
	if n != 8 || typ != 102 || length != len(big) {
		t.Fatalf("header packet: n=%d type=%d len=%d", n, typ, length)
	}
	if n, _ = server.Read(buf); n != len(big) {
		t.Fatalf("body packet has %d bytes", n)
	}
	if err := client.Send(1, nil); err == nil {
		t.Fatal("empty message should be refused")
	}
}
