package main

import (
	"apploadrt"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

// Message types exchanged with the QML frontend (bodies are JSON).
const (
	reqHello    int32 = 1 // {}                     -> respState, respMeta
	reqQuestion int32 = 2 // {"i"}                  -> respQuestion
	reqSettings int32 = 3 // {"key": value, ...}    -> (nothing)
	reqPosition int32 = 4 // {"position"}           -> (nothing)

	respState    int32 = 100
	respMeta     int32 = 101
	respQuestion int32 = 102
	respError    int32 = 199
)

type reply struct {
	Type int32
	Body any
}

type App struct {
	dataDir   string
	statePath string
	state     *State

	meta    json.RawMessage // build/data/meta.json, sent as it is
	content *os.File
	offsets struct {
		Q [][2]int64 `json:"q"` // question records
		G [][2]int64 `json:"g"` // group passages
	}
	groupOf []int // question index -> group index
	loadErr error
}

func newApp(dataDir, statePath string) *App {
	a := &App{dataDir: dataDir, statePath: statePath, state: loadState(statePath)}
	a.loadErr = a.load()
	if a.loadErr != nil {
		logf("cannot load the deck: %v", a.loadErr)
	}
	return a
}

func (a *App) load() error {
	meta, err := os.ReadFile(filepath.Join(a.dataDir, "meta.json"))
	if err != nil {
		return err
	}
	var index struct {
		Q [][]json.RawMessage `json:"q"`
	}
	if err := json.Unmarshal(meta, &index); err != nil {
		return fmt.Errorf("meta.json: %w", err)
	}
	a.groupOf = make([]int, len(index.Q))
	for i, row := range index.Q {
		if len(row) < 6 {
			return fmt.Errorf("meta.json: question %d is malformed", i)
		}
		if err := json.Unmarshal(row[5], &a.groupOf[i]); err != nil {
			return fmt.Errorf("meta.json: question %d: %w", i, err)
		}
	}
	a.meta = meta

	idx, err := os.ReadFile(filepath.Join(a.dataDir, "content.idx"))
	if err != nil {
		return err
	}
	if err := json.Unmarshal(idx, &a.offsets); err != nil {
		return fmt.Errorf("content.idx: %w", err)
	}
	if len(a.offsets.Q) != len(a.groupOf) {
		return fmt.Errorf("content.idx has %d questions, meta.json %d", len(a.offsets.Q), len(a.groupOf))
	}
	a.content, err = os.Open(filepath.Join(a.dataDir, "content.dat"))
	return err
}

// reason is a load error in a few plain words: Go's wording, without the
// full path, which means nothing on the tablet's screen.
func reason(err error) string {
	var pathErr *fs.PathError
	if errors.As(err, &pathErr) {
		name := filepath.Base(pathErr.Path)
		if errors.Is(err, fs.ErrNotExist) {
			return name + " is missing"
		}
		if errors.Is(err, fs.ErrPermission) {
			return name + " can't be read"
		}
		return name + ": " + pathErr.Err.Error()
	}
	return err.Error()
}

func (a *App) read(span [2]int64) (json.RawMessage, error) {
	buf := make([]byte, span[1])
	if _, err := a.content.ReadAt(buf, span[0]); err != nil {
		return nil, err
	}
	return buf, nil
}

// question is one question's text together with its group's passage.
func (a *App) question(i int) (map[string]any, error) {
	if i < 0 || i >= len(a.offsets.Q) {
		return nil, fmt.Errorf("no question %d", i)
	}
	g := a.groupOf[i]
	if g < 0 || g >= len(a.offsets.G) {
		return nil, fmt.Errorf("question %d has no group", i)
	}
	record, err := a.read(a.offsets.Q[i])
	if err != nil {
		return nil, err
	}
	passage, err := a.read(a.offsets.G[g])
	if err != nil {
		return nil, err
	}
	var body map[string]any
	if err := json.Unmarshal(record, &body); err != nil {
		return nil, fmt.Errorf("question %d: %w", i, err)
	}
	body["i"] = i
	body["g"] = g
	body["passage"] = passage
	return body, nil
}

func (a *App) save() {
	if err := a.state.save(a.statePath); err != nil {
		logf("could not save state: %v", err)
	}
}

// handle processes one message and returns the replies to send back.
func (a *App) handle(msgType int32, body []byte) []reply {
	switch msgType {
	case reqHello:
		if a.loadErr != nil {
			// The frontend keeps saying hello while it waits, so a deck
			// that turns up (an install finishing) is picked up.
			a.loadErr = a.load()
		}
		if a.loadErr != nil {
			return []reply{errorReply(msgType, "The question deck could not be loaded: "+reason(a.loadErr)+".")}
		}
		return []reply{
			{respState, map[string]any{"settings": a.state.Settings, "position": a.state.Position}},
			{respMeta, a.meta},
		}

	case reqQuestion:
		var req struct {
			I int `json:"i"`
		}
		if err := json.Unmarshal(body, &req); err != nil {
			return []reply{errorReply(msgType, "bad request: "+err.Error())}
		}
		if a.loadErr != nil {
			return []reply{errorReply(msgType, a.loadErr.Error())}
		}
		q, err := a.question(req.I)
		if err != nil {
			return []reply{errorReply(msgType, err.Error())}
		}
		return []reply{{respQuestion, q}}

	case reqSettings:
		var settings map[string]any
		if err := json.Unmarshal(body, &settings); err != nil {
			return []reply{errorReply(msgType, "bad settings: "+err.Error())}
		}
		for k, v := range settings {
			a.state.Settings[k] = v
		}
		a.save()
		return nil

	case reqPosition:
		var req struct {
			Position string `json:"position"`
		}
		if err := json.Unmarshal(body, &req); err != nil {
			return []reply{errorReply(msgType, "bad position: "+err.Error())}
		}
		if req.Position != a.state.Position {
			a.state.Position = req.Position
			a.save()
		}
		return nil

	case apploadrt.MsgNewCoordinator, apploadrt.MsgLostCoordinator, apploadrt.MsgTerminate:
		return nil
	}
	return []reply{errorReply(msgType, fmt.Sprintf("unknown message type %d", msgType))}
}

func errorReply(request int32, message string) reply {
	return reply{respError, map[string]any{"request": request, "message": message}}
}
