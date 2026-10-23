package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Reading progress, looked-up words and settings, kept in
// <data dir>/state.json.

type StoryProgress struct {
	Token    int            `json:"token"`
	Finished bool           `json:"finished"`
	Lookups  map[string]int `json:"lookups"`
	LastRead string         `json:"lastRead,omitempty"`
}

type State struct {
	Version  int                       `json:"version"`
	Settings map[string]any            `json:"settings"`
	Stories  map[string]*StoryProgress `json:"stories"`
}

func defaultSettings() map[string]any {
	return map[string]any{
		"textSize": 3.0, // index into the app's list of text sizes (40 px)
		"font":     "serif",
		"dots":     true,
		"footer":   false,
	}
}

func loadState(path string) *State {
	state := &State{Version: 1}
	if data, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(data, state)
	}
	if state.Settings == nil {
		state.Settings = map[string]any{}
	}
	for k, v := range defaultSettings() {
		if _, ok := state.Settings[k]; !ok {
			state.Settings[k] = v
		}
	}
	if state.Stories == nil {
		state.Stories = map[string]*StoryProgress{}
	}
	return state
}

func (s *State) progress(id string) *StoryProgress {
	p, ok := s.Stories[id]
	if !ok || p == nil {
		p = &StoryProgress{}
		s.Stories[id] = p
	}
	if p.Lookups == nil {
		p.Lookups = map[string]int{}
	}
	return p
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
