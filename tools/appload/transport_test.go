package appload

import (
	"net"
	"reflect"
	"testing"
)

// End to end over the TCP framing used by the emulator.
func TestStreamTransport(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	done := make(chan Conn)
	go func() {
		c, err := Dial("tcp:" + ln.Addr().String())
		if err != nil {
			t.Error(err)
		}
		done <- c
	}()
	server, err := ln.Accept()
	if err != nil {
		t.Fatal(err)
	}
	client := <-done
	srv := &streamConn{conn: server}
	if err := srv.Send(1, []byte(`{"a":1}`)); err != nil {
		t.Fatal(err)
	}
	typ, body, err := client.Recv()
	if err != nil || typ != 1 || string(body) != `{"a":1}` {
		t.Fatalf("got %d %q %v", typ, body, err)
	}
	if err := client.Send(MsgTerminate, []byte("close")); err != nil {
		t.Fatal(err)
	}
	typ, body, err = srv.Recv()
	if err != nil || typ != -1 || string(body) != "close" {
		t.Fatalf("got %d %q %v", typ, body, err)
	}
}

func TestHeaderEncoding(t *testing.T) {
	h := EncodeHeader(-2, 300)
	if !reflect.DeepEqual(h, []byte{0xfe, 0xff, 0xff, 0xff, 0x2c, 0x01, 0, 0}) {
		t.Fatalf("header bytes %v", h)
	}
	typ, n, err := DecodeHeader(h)
	if err != nil || typ != -2 || n != 300 {
		t.Fatal("decode mismatch")
	}
	if _, _, err := DecodeHeader(EncodeHeader(1, MaxMessageLength+1)); err == nil {
		t.Fatal("oversized message accepted")
	}
}
