package main

import (
	"encoding/json"
	"fmt"
	"unicode/utf8"
)

// A SOCK_SEQPACKET datagram can't be larger than the socket's send buffer
// (wmem_default, about 200 KB on the tablet), whatever AppLoad's own 10 MiB
// limit says, and the startup index is bigger than that. So any reply over
// chunkSize goes as a run of msgChunk messages instead, each one
//
//	"<type> <seq> <count>\n<piece of the JSON text>"
//
// which the QML joins back together and handles as one message of <type>.
// Pieces are cut on UTF-8 boundaries so each body is valid text on its own.
const (
	msgChunk  int32 = 190
	chunkSize       = 48 * 1024
)

func chunks(data []byte, size int) [][]byte {
	var out [][]byte
	for len(data) > size {
		cut := size
		for cut > 0 && !utf8.RuneStart(data[cut]) {
			cut--
		}
		out = append(out, data[:cut])
		data = data[cut:]
	}
	return append(out, data)
}

func sendChunked(conn transport, r reply) error {
	data, err := json.Marshal(r.Body)
	if err != nil {
		return fmt.Errorf("cannot encode reply %d: %w", r.Type, err)
	}
	if len(data) <= chunkSize {
		return conn.send(r.Type, data)
	}
	pieces := chunks(data, chunkSize)
	for i, piece := range pieces {
		head := fmt.Sprintf("%d %d %d\n", r.Type, i, len(pieces))
		if err := conn.send(msgChunk, append([]byte(head), piece...)); err != nil {
			return err
		}
	}
	return nil
}
