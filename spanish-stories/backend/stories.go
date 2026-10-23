package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode"
)

// A story file is JSON, either
//
//	{"title": "...", "title_en": "...", "level": "A1", "description": "...",
//	 "content": [["Hola", "Hello"], [",", ""], ["me llamo", "my name is"], ...]}
//
// or just the bare "content" array. Every entry is a (spanish, english) pair.
// The english side may be a string ("has / owns" gives two alternatives), a
// list of strings, or empty for punctuation. A spanish "\n" starts a new
// paragraph.

type Token struct {
	Es string
	En []string
}

func (t Token) MarshalJSON() ([]byte, error) {
	en := t.En
	if en == nil {
		en = []string{}
	}
	return json.Marshal([]any{t.Es, en})
}

type Story struct {
	ID          string  `json:"id"`
	File        string  `json:"file"`
	Title       string  `json:"title"`
	TitleEn     string  `json:"title_en"`
	Level       string  `json:"level"`
	Description string  `json:"description"`
	Author      string  `json:"author,omitempty"`
	Words       int     `json:"words"`
	Tokens      []Token `json:"tokens"`
}

type StoryError struct {
	File  string `json:"file"`
	Error string `json:"error"`
}

type rawStory struct {
	ID          string            `json:"id"`
	Title       string            `json:"title"`
	TitleEn     string            `json:"title_en"`
	TitleEn2    string            `json:"titleEnglish"`
	Level       string            `json:"level"`
	Description string            `json:"description"`
	Author      string            `json:"author"`
	Content     []json.RawMessage `json:"content"`
}

func parseStory(path string, data []byte) (*Story, error) {
	base := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	story := &Story{ID: base, File: path, Title: prettifyName(base)}

	trimmed := strings.TrimPrefix(string(data), string(rune(0xFEFF)))
	trimmed = strings.TrimLeftFunc(trimmed, unicode.IsSpace)
	var entries []json.RawMessage
	switch {
	case strings.HasPrefix(trimmed, "["):
		if err := json.Unmarshal([]byte(trimmed), &entries); err != nil {
			return nil, fmt.Errorf("invalid JSON: %v", err)
		}
	case strings.HasPrefix(trimmed, "{"):
		var raw rawStory
		if err := json.Unmarshal([]byte(trimmed), &raw); err != nil {
			return nil, fmt.Errorf("invalid JSON: %v", err)
		}
		if raw.ID != "" {
			story.ID = raw.ID
		}
		if raw.Title != "" {
			story.Title = raw.Title
		}
		story.TitleEn = firstNonEmpty(raw.TitleEn, raw.TitleEn2)
		story.Level = raw.Level
		story.Description = raw.Description
		story.Author = raw.Author
		entries = raw.Content
	default:
		return nil, errors.New("file must contain a JSON object or array")
	}
	if len(entries) == 0 {
		return nil, errors.New("story has no content")
	}

	for i, entry := range entries {
		tok, err := parseToken(entry)
		if err != nil {
			return nil, fmt.Errorf("content entry %d: %v", i+1, err)
		}
		story.Tokens = append(story.Tokens, tok)
		if len(tok.En) > 0 {
			story.Words += countWords(tok.Es)
		}
	}
	return story, nil
}

func parseToken(raw json.RawMessage) (Token, error) {
	var pair []json.RawMessage
	if err := json.Unmarshal(raw, &pair); err != nil {
		// Also accept {"es": "...", "en": "..."} objects.
		var obj struct {
			Es json.RawMessage `json:"es"`
			En json.RawMessage `json:"en"`
		}
		if err2 := json.Unmarshal(raw, &obj); err2 != nil || obj.Es == nil {
			return Token{}, errors.New(`expected a ["spanish", "english"] pair`)
		}
		pair = []json.RawMessage{obj.Es, obj.En}
	}
	if len(pair) < 1 || len(pair) > 2 {
		return Token{}, fmt.Errorf("expected 2 items, found %d", len(pair))
	}
	var es string
	if err := json.Unmarshal(pair[0], &es); err != nil {
		return Token{}, errors.New("spanish text must be a string")
	}
	tok := Token{Es: es}
	if len(pair) == 2 {
		alts, err := parseEnglish(pair[1])
		if err != nil {
			return Token{}, err
		}
		tok.En = alts
	}
	if tok.Es == "" {
		return Token{}, errors.New("spanish text is empty")
	}
	return tok, nil
}

func parseEnglish(raw json.RawMessage) ([]string, error) {
	if raw == nil || string(raw) == "null" {
		return nil, nil
	}
	var single string
	if err := json.Unmarshal(raw, &single); err == nil {
		return splitAlternatives([]string{single}), nil
	}
	var list []string
	if err := json.Unmarshal(raw, &list); err == nil {
		return splitAlternatives(list), nil
	}
	return nil, errors.New("english must be a string or a list of strings")
}

func splitAlternatives(values []string) []string {
	var out []string
	for _, v := range values {
		for _, part := range strings.Split(v, " / ") {
			if part = strings.TrimSpace(part); part != "" {
				out = append(out, part)
			}
		}
	}
	return out
}

func countWords(s string) int {
	n := 0
	for _, f := range strings.Fields(s) {
		if strings.IndexFunc(f, unicode.IsLetter) >= 0 {
			n++
		}
	}
	return n
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

// "03-el-mercado" -> "El mercado"
func prettifyName(base string) string {
	name := strings.TrimLeftFunc(base, func(r rune) bool { return unicode.IsDigit(r) || r == '-' || r == '_' })
	name = strings.NewReplacer("-", " ", "_", " ").Replace(name)
	name = strings.TrimSpace(name)
	if name == "" {
		return base
	}
	r := []rune(name)
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

// loadStories reads every *.json story in the given directories (missing
// directories are skipped). Files that fail to parse are reported, not fatal.
func loadStories(dirs []string) ([]*Story, []StoryError) {
	var stories []*Story
	var problems []StoryError
	seen := map[string]bool{}
	for _, dir := range dirs {
		files, err := filepath.Glob(filepath.Join(dir, "*.json"))
		if err != nil {
			continue
		}
		sort.Strings(files)
		for _, file := range files {
			data, err := os.ReadFile(file)
			if err != nil {
				problems = append(problems, StoryError{File: filepath.Base(file), Error: err.Error()})
				continue
			}
			story, err := parseStory(file, data)
			if err != nil {
				problems = append(problems, StoryError{File: filepath.Base(file), Error: err.Error()})
				continue
			}
			id := story.ID
			for n := 2; seen[story.ID]; n++ {
				story.ID = fmt.Sprintf("%s-%d", id, n)
			}
			seen[story.ID] = true
			stories = append(stories, story)
		}
	}
	return stories, problems
}
