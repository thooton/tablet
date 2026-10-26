package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"time"
)

// The decks, as this tablet has them: a copy of the command center's
// collection, studied offline and synced (center.go). It is the shape
// /flashcards/sync speaks, kept in collection.json with a dirty flag on
// whatever changed here since the last sync. Where both sides changed a
// record, the later mod (device milliseconds) wins, as on the command
// center and the phone.

// auto is a deck's newPerDay when new cards come in while recall allows,
// with no daily number.
const auto = -1

type deck struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	NewPerDay int    `json:"new_per_day"`
	Mod       int64  `json:"mod"`
	Dirty     bool   `json:"dirty,omitempty"`
}

type card struct {
	ID    string `json:"id"`
	Deck  string `json:"deck"`
	Ord   int    `json:"ord"`
	Front string `json:"front"`
	Back  string `json:"back"`
	Aux   string `json:"aux"`
	memory
	Intro int64 `json:"intro"`
	Mod   int64 `json:"mod"`
	Dirty bool  `json:"dirty,omitempty"`

	javaID int32 // the java-fsrs card id: String.hashCode of ID
}

func (c *card) isNew() bool { return c.Last == 0 }

func (c *card) learning() bool { return c.State == stateLearning || c.State == stateRelearning }

type collection struct {
	USN   int64   `json:"usn"`
	Zone  string  `json:"zone,omitempty"`
	Decks []*deck `json:"decks"`
	Cards []*card `json:"cards"`

	path   string
	decks  map[string]*deck
	cards  map[string]*card
	inDeck map[string][]*card // each deck's cards, in order
}

func newCollection(path string) *collection {
	return &collection{path: path, Decks: []*deck{}, Cards: []*card{}}
}

// load reads the file; a missing one is an empty collection.
func loadCollection(path string) (*collection, error) {
	c := newCollection(path)
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		c.index()
		return c, nil
	} else if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(data, c); err != nil {
		return nil, err
	}
	c.path = path
	c.index()
	return c, nil
}

func (c *collection) index() {
	c.decks = map[string]*deck{}
	c.cards = map[string]*card{}
	c.inDeck = map[string][]*card{}
	kept := c.Cards[:0]
	for _, d := range c.Decks {
		c.decks[d.ID] = d
	}
	for _, k := range c.Cards {
		if c.decks[k.Deck] == nil || c.cards[k.ID] != nil {
			continue
		}
		k.javaID = javaStringHash(k.ID)
		c.cards[k.ID] = k
		c.inDeck[k.Deck] = append(c.inDeck[k.Deck], k)
		kept = append(kept, k)
	}
	c.Cards = kept
	for _, list := range c.inDeck {
		sort.SliceStable(list, func(i, j int) bool { return list[i].Ord < list[j].Ord })
	}
}

func (c *collection) save() error {
	data, err := json.Marshal(c)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(c.path), 0o700); err != nil {
		return err
	}
	tmp := c.path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, c.path)
}

func (c *collection) dirty() bool {
	for _, d := range c.Decks {
		if d.Dirty {
			return true
		}
	}
	for _, k := range c.Cards {
		if k.Dirty {
			return true
		}
	}
	return false
}

// location is the day's clock for the 4am rollover: the phone's time zone,
// which the command center passes on, since the tablet keeps UTC.
func (c *collection) location() *time.Location {
	if c.Zone != "" {
		if loc, err := time.LoadLocation(c.Zone); err == nil {
			return loc
		}
	}
	return time.Local
}

func touch(mod *int64, dirty *bool, nowMillis int64) {
	*mod = max(nowMillis, *mod+1)
	*dirty = true
}

// syncBody is what one sync sends: every dirty record, and the usn last
// seen. sent remembers each one's mod, to tell later changes apart.
type syncBody struct {
	USN   int64   `json:"usn"`
	Decks []*deck `json:"decks"`
	Cards []*card `json:"cards"`
}

type sentMods struct {
	decks map[string]int64
	cards map[string]int64
}

func (c *collection) outgoing() ([]byte, sentMods) {
	body := syncBody{USN: c.USN, Decks: []*deck{}, Cards: []*card{}}
	sent := sentMods{decks: map[string]int64{}, cards: map[string]int64{}}
	for _, d := range c.Decks {
		if d.Dirty {
			copy := *d
			copy.Dirty = false
			body.Decks = append(body.Decks, &copy)
			sent.decks[d.ID] = d.Mod
		}
	}
	for _, k := range c.Cards {
		if k.Dirty {
			copy := *k
			copy.Dirty = false
			body.Cards = append(body.Cards, &copy)
			sent.cards[k.ID] = k.Mod
		}
	}
	data, _ := json.Marshal(body)
	return data, sent
}

// apply takes the command center's answer to a sync: what was sent is clean
// unless it changed again meanwhile, and every record that came back
// replaces this copy's, unless this copy changed it later.
func (c *collection) apply(reply []byte, sent sentMods) error {
	var got struct {
		USN   int64   `json:"usn"`
		Zone  string  `json:"zone"`
		Decks []*deck `json:"decks"`
		Cards []*card `json:"cards"`
	}
	if err := json.Unmarshal(reply, &got); err != nil {
		return err
	}
	for id, mod := range sent.decks {
		if d := c.decks[id]; d != nil && d.Mod == mod {
			d.Dirty = false
		}
	}
	for id, mod := range sent.cards {
		if k := c.cards[id]; k != nil && k.Mod == mod {
			k.Dirty = false
		}
	}
	for _, d := range got.Decks {
		if d == nil || d.ID == "" {
			continue
		}
		d.Dirty = false
		have := c.decks[d.ID]
		if have == nil {
			c.Decks = append(c.Decks, d)
		} else if !(have.Dirty && have.Mod > d.Mod) {
			*have = *d
		}
	}
	for _, k := range got.Cards {
		if k == nil || k.ID == "" || !validMemory(k.memory) {
			continue
		}
		k.Dirty = false
		have := c.cards[k.ID]
		if have == nil {
			c.Cards = append(c.Cards, k)
		} else if !(have.Dirty && have.Mod > k.Mod) {
			*have = *k
		}
	}
	if got.Zone != "" {
		c.Zone = got.Zone
	}
	c.USN = got.USN
	c.index()
	return nil
}

// validMemory is whether java-fsrs could hold this state (Store.valid on the phone).
func validMemory(m memory) bool {
	if m.State < stateLearning || m.State > stateRelearning {
		return false
	}
	if m.State == stateReview {
		if m.Step != nil {
			return false
		}
	} else if m.Step == nil || *m.Step < 0 {
		return false
	}
	if m.Last == 0 {
		return m.State == stateLearning && m.Stability == nil && m.Difficulty == nil
	}
	return m.Stability != nil && *m.Stability > 0 && *m.Stability < 1e300 &&
		m.Difficulty != nil && *m.Difficulty >= 1 && *m.Difficulty <= 10
}
