package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// What the web app keeps in localStorage and the URL, kept in
// <data dir>/state.json instead: the settings panel (filters, held-out,
// shuffle) and where the reader is (the ?q value). Answers are not saved,
// as in the web app.
type State struct {
	Version  int            `json:"version"`
	Settings map[string]any `json:"settings"`
	Position string         `json:"position"`
}

func loadState(path string) *State {
	state := &State{Version: 1}
	if data, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(data, state)
	}
	if state.Settings == nil {
		state.Settings = map[string]any{}
	}
	return state
}

// save writes atomically so a crash or power loss never leaves a torn file.
func (s *State) save(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
