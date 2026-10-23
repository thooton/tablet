package main

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"
)

// Message types exchanged with the QML frontend (bodies are JSON).
const (
	reqList     int32 = 1 // {}                              -> respLibrary
	reqOpen     int32 = 2 // {"id"}                          -> respStory
	reqProgress int32 = 3 // {"id","token","finished"}       -> (nothing)
	reqLookup   int32 = 4 // {"id","es"}                     -> (nothing)
	reqSettings int32 = 5 // {"textSize","font",...}        -> respSettings
	reqReset    int32 = 6 // {"id"}                          -> respLibrary

	respLibrary  int32 = 101
	respStory    int32 = 102
	respSettings int32 = 105
	respError    int32 = 199
)

type reply struct {
	Type int32
	Body any
}

type App struct {
	storyDirs []string
	statePath string
	state     *State
	stories   map[string]*Story
	now       func() time.Time
}

func newApp(storyDirs []string, statePath string) *App {
	return &App{
		storyDirs: storyDirs,
		statePath: statePath,
		state:     loadState(statePath),
		stories:   map[string]*Story{},
		now:       time.Now,
	}
}

type storySummary struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	TitleEn     string  `json:"title_en"`
	Level       string  `json:"level"`
	Description string  `json:"description"`
	Words       int     `json:"words"`
	Tokens      int     `json:"tokens"`
	Progress    float64 `json:"progress"`
	Finished    bool    `json:"finished"`
	Started     bool    `json:"started"`
	Lookups     int     `json:"lookups"`
	LastRead    string  `json:"lastRead"`
}

func (a *App) library() map[string]any {
	stories, problems := loadStories(a.storyDirs)
	a.stories = map[string]*Story{}
	summaries := []storySummary{}
	for _, s := range stories {
		a.stories[s.ID] = s
		sum := storySummary{
			ID: s.ID, Title: s.Title, TitleEn: s.TitleEn, Level: s.Level,
			Description: s.Description, Words: s.Words, Tokens: len(s.Tokens),
		}
		if p, ok := a.state.Stories[s.ID]; ok && p != nil {
			sum.Finished = p.Finished
			sum.Started = p.Token > 0 || p.Finished
			sum.Lookups = len(p.Lookups)
			sum.LastRead = p.LastRead
			if len(s.Tokens) > 0 {
				sum.Progress = float64(p.Token) / float64(len(s.Tokens))
			}
			if p.Finished {
				sum.Progress = 1
			}
		}
		summaries = append(summaries, sum)
	}
	// Most recently read first; stories never opened keep file order after them.
	sort.SliceStable(summaries, func(i, j int) bool {
		ti, ei := time.Parse(time.RFC3339, summaries[i].LastRead)
		tj, ej := time.Parse(time.RFC3339, summaries[j].LastRead)
		if ei != nil || ej != nil {
			return ei == nil && ej != nil
		}
		return ti.After(tj)
	})
	if problems == nil {
		problems = []StoryError{}
	}
	return map[string]any{
		"stories":  summaries,
		"errors":   problems,
		"settings": a.state.Settings,
		"dirs":     a.storyDirs,
	}
}

func (a *App) save() {
	if err := a.state.save(a.statePath); err != nil {
		logf("could not save state: %v", err)
	}
}

func (a *App) story(id string) (*Story, error) {
	if s, ok := a.stories[id]; ok {
		return s, nil
	}
	a.library()
	if s, ok := a.stories[id]; ok {
		return s, nil
	}
	return nil, fmt.Errorf("story %q not found", id)
}

// handle processes one message and returns the replies to send back.
func (a *App) handle(msgType int32, body []byte) []reply {
	var req struct {
		ID       string `json:"id"`
		Token    *int   `json:"token"`
		Finished *bool  `json:"finished"`
		Es       string `json:"es"`
	}
	if msgType > 0 && len(body) > 0 {
		if err := json.Unmarshal(body, &req); err != nil {
			return []reply{errorReply(msgType, "bad request: "+err.Error())}
		}
	}

	switch msgType {
	case msgSystemNewCoordinator, reqList:
		return []reply{{respLibrary, a.library()}}

	case reqOpen:
		s, err := a.story(req.ID)
		if err != nil {
			return []reply{errorReply(msgType, err.Error())}
		}
		p := a.state.progress(s.ID)
		p.LastRead = a.now().Format(time.RFC3339)
		if p.Token >= len(s.Tokens) {
			p.Token = 0
		}
		a.save()
		return []reply{{respStory, map[string]any{
			"story":    s,
			"progress": p,
			"settings": a.state.Settings,
		}}}

	case reqProgress:
		if _, err := a.story(req.ID); err != nil {
			return []reply{errorReply(msgType, err.Error())}
		}
		p := a.state.progress(req.ID)
		if req.Token != nil {
			p.Token = max(*req.Token, 0)
		}
		if req.Finished != nil {
			p.Finished = p.Finished || *req.Finished
		}
		p.LastRead = a.now().Format(time.RFC3339)
		a.save()
		return nil

	case reqLookup:
		es := strings.ToLower(strings.TrimSpace(req.Es))
		if req.ID == "" || es == "" {
			return nil
		}
		a.state.progress(req.ID).Lookups[es]++
		a.save()
		return nil

	case reqSettings:
		var settings map[string]any
		if err := json.Unmarshal(body, &settings); err != nil {
			return []reply{errorReply(msgType, "bad settings: "+err.Error())}
		}
		for k, v := range settings {
			a.state.Settings[k] = v
		}
		a.save()
		return []reply{{respSettings, a.state.Settings}}

	case reqReset:
		delete(a.state.Stories, req.ID)
		a.save()
		return []reply{{respLibrary, a.library()}}

	case msgSystemLostCoordinator, msgSystemTerminate:
		return nil
	}
	return []reply{errorReply(msgType, fmt.Sprintf("unknown message type %d", msgType))}
}

func errorReply(request int32, message string) reply {
	return reply{respError, map[string]any{"request": request, "message": message}}
}
