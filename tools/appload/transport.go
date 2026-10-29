// Package appload is what every app's backend shares: AppLoad's wire format
// (this file), staying alive across opens until an update replaces the
// binary (lifecycle.go), and the backend's main loop (serve.go).
package appload

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
)

// AppLoad wire format: every message is an 8 byte header
// (int32 type, int32 length, native/little endian) followed by the UTF-8 body.
// On the tablet the socket is AF_UNIX/SOCK_SEQPACKET and header and body are
// two separate packets. The desktop emulator uses TCP, where the same bytes
// travel as one plain stream.

const MaxMessageLength = 10 * 1024 * 1024

// System messages sent by AppLoad itself. The body of -2 and -3 is how many
// frontends are attached.
const (
	MsgTerminate       int32 = -1
	MsgNewCoordinator  int32 = -2
	MsgLostCoordinator int32 = -3
)

type transport interface {
	recv() (int32, []byte, error)
	send(msgType int32, body []byte) error
	close() error
}

// Conn is the backend's connection to AppLoad. One goroutine reads it; any
// may send.
type Conn struct {
	t  transport
	mu sync.Mutex
}

// Dial connects to the unix socket AppLoad gives a backend, or to
// "tcp:<host>:<port>", the desktop emulator's.
func Dial(address string) (*Conn, error) {
	if hostPort, ok := strings.CutPrefix(address, "tcp:"); ok {
		conn, err := net.Dial("tcp", hostPort)
		if err != nil {
			return nil, err
		}
		return &Conn{t: &streamTransport{conn: conn}}, nil
	}
	conn, err := net.DialUnix("unixpacket", nil, &net.UnixAddr{Name: address, Net: "unixpacket"})
	if err != nil {
		return nil, err
	}
	return &Conn{t: &packetTransport{conn: conn, buf: make([]byte, MaxMessageLength)}}, nil
}

func (c *Conn) Recv() (int32, []byte, error) { return c.t.recv() }

func (c *Conn) Send(msgType int32, body []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t.send(msgType, body)
}

// SendJSON sends body as JSON, logging what fails.
func (c *Conn) SendJSON(msgType int32, body any) {
	data, err := json.Marshal(body)
	if err != nil {
		Logf("encoding message %d: %v", msgType, err)
		return
	}
	if err := c.Send(msgType, data); err != nil {
		Logf("sending message %d (%d bytes): %v", msgType, len(data), err)
	}
}

func (c *Conn) Close() error { return c.t.close() }

func EncodeHeader(msgType int32, length int) []byte {
	header := make([]byte, 8)
	binary.LittleEndian.PutUint32(header[0:4], uint32(msgType))
	binary.LittleEndian.PutUint32(header[4:8], uint32(length))
	return header
}

func DecodeHeader(header []byte) (int32, int, error) {
	msgType := int32(binary.LittleEndian.Uint32(header[0:4]))
	length := int(int32(binary.LittleEndian.Uint32(header[4:8])))
	if length < 0 || length > MaxMessageLength {
		return 0, 0, fmt.Errorf("invalid message length %d", length)
	}
	return msgType, length, nil
}

type packetTransport struct {
	conn net.Conn
	buf  []byte
}

func (t *packetTransport) recv() (int32, []byte, error) {
	n, err := t.conn.Read(t.buf[:8])
	if err != nil {
		return 0, nil, err
	}
	if n == 0 {
		return 0, nil, io.EOF
	}
	if n != 8 {
		return 0, nil, fmt.Errorf("short header packet (%d bytes)", n)
	}
	msgType, length, err := DecodeHeader(t.buf[:8])
	if err != nil {
		return 0, nil, err
	}
	if length == 0 {
		return msgType, nil, nil
	}
	n, err = t.conn.Read(t.buf[:length])
	if err != nil {
		return 0, nil, err
	}
	body := make([]byte, n)
	copy(body, t.buf[:n])
	return msgType, body, nil
}

func (t *packetTransport) send(msgType int32, body []byte) error {
	if len(body) == 0 {
		// AppLoad cannot tell an empty packet from a closed socket.
		return errors.New("refusing to send an empty message")
	}
	if len(body) > MaxMessageLength {
		return fmt.Errorf("message too large (%d bytes)", len(body))
	}
	if _, err := t.conn.Write(EncodeHeader(msgType, len(body))); err != nil {
		return err
	}
	_, err := t.conn.Write(body)
	return err
}

func (t *packetTransport) close() error { return t.conn.Close() }

type streamTransport struct {
	conn net.Conn
}

func (t *streamTransport) recv() (int32, []byte, error) {
	header := make([]byte, 8)
	if _, err := io.ReadFull(t.conn, header); err != nil {
		return 0, nil, err
	}
	msgType, length, err := DecodeHeader(header)
	if err != nil {
		return 0, nil, err
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(t.conn, body); err != nil {
		return 0, nil, err
	}
	return msgType, body, nil
}

func (t *streamTransport) send(msgType int32, body []byte) error {
	if len(body) > MaxMessageLength {
		return fmt.Errorf("message too large (%d bytes)", len(body))
	}
	_, err := t.conn.Write(append(EncodeHeader(msgType, len(body)), body...))
	return err
}

func (t *streamTransport) close() error { return t.conn.Close() }
