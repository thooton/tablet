// Package appload is what every backend here shares: AppLoad's wire
// format (transport.go), the rule for when a backend may exit
// (lifecycle.go), and the start-up and message loop around them
// (backend.go).
package appload

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
)

// AppLoad wire format: every message is an 8 byte header
// (int32 type, int32 length, native/little endian) followed by the UTF-8 body.
// On the tablet the socket is AF_UNIX/SOCK_SEQPACKET and header and body are
// two separate packets. The desktop emulator uses TCP, where the same bytes
// travel as one plain stream.

const MaxMessageLength = 10 * 1024 * 1024

// System messages sent by AppLoad itself.
const (
	MsgTerminate       int32 = -1
	MsgNewCoordinator  int32 = -2
	MsgLostCoordinator int32 = -3
)

type Conn interface {
	Recv() (int32, []byte, error)
	Send(msgType int32, body []byte) error
	Close() error
}

// Dial connects to AppLoad's unix socket, or to "tcp:<host>:<port>" (the
// emulator).
func Dial(address string) (Conn, error) {
	if hostPort, ok := strings.CutPrefix(address, "tcp:"); ok {
		conn, err := net.Dial("tcp", hostPort)
		if err != nil {
			return nil, err
		}
		return &streamConn{conn: conn}, nil
	}
	conn, err := net.DialUnix("unixpacket", nil, &net.UnixAddr{Name: address, Net: "unixpacket"})
	if err != nil {
		return nil, err
	}
	return &packetConn{conn: conn, buf: make([]byte, MaxMessageLength)}, nil
}

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

type packetConn struct {
	conn net.Conn
	buf  []byte
}

func (t *packetConn) Recv() (int32, []byte, error) {
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

func (t *packetConn) Send(msgType int32, body []byte) error {
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

func (t *packetConn) Close() error { return t.conn.Close() }

type streamConn struct {
	conn net.Conn
}

func (t *streamConn) Recv() (int32, []byte, error) {
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

func (t *streamConn) Send(msgType int32, body []byte) error {
	if len(body) > MaxMessageLength {
		return fmt.Errorf("message too large (%d bytes)", len(body))
	}
	_, err := t.conn.Write(append(EncodeHeader(msgType, len(body)), body...))
	return err
}

func (t *streamConn) Close() error { return t.conn.Close() }
