package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/url"
	"sync"
	"time"
)

// Messages between the QML and the backend.
const (
	msgHello   = 1 // UI → backend: send the state (and sync, if it has been a while)
	msgStudy   = 2 // {"deck", "ahead"?}: the deck's next card; ahead: Review Ahead
	msgAnswer  = 3 // {"deck", "card", "rating"}: answer it, then the next card
	msgOptions = 4 // {"deck", "new_per_day"}: change a deck's setting
	msgSync    = 5 // sync now
	msgPair    = 6 // ask the command center for a pairing code
	msgStats   = 7 // {"deck", "whole"?}: the deck's statistics, or the collection's

	msgState = 101 // backend → UI: the decks and how sync stands
	msgCard  = 102 // the card to show, or that the deck is done for now
	msgStat  = 103 // the statistics
)

const (
	saveAfter      = 2 * time.Second
	syncAfter      = 20 * time.Second
	syncOnOpenWait = time.Minute
)

type app struct {
	mu      sync.Mutex
	col     *collection
	center  *center
	send    func(int32, any)
	session map[string]*session

	syncing  bool
	again    bool
	syncErr  string
	lastSync time.Time
	saveT    *time.Timer
	syncT    *time.Timer

	pair    *pairing
	pairErr string
	pairing bool
}

func newApp(col *collection, c *center, send func(int32, any)) *app {
	return &app{col: col, center: c, send: send, session: map[string]*session{}}
}

func (a *app) busy() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.syncing
}

func (a *app) handle(msgType int32, body []byte) {
	var in struct {
		Deck      string `json:"deck"`
		Card      string `json:"card"`
		Rating    int    `json:"rating"`
		Ahead     bool   `json:"ahead"`
		Whole     bool   `json:"whole"`
		NewPerDay *int   `json:"new_per_day"`
	}
	if len(body) > 0 {
		json.Unmarshal(body, &in)
	}
	switch msgType {
	case msgSystemNewCoordinator, msgHello:
		a.sendState()
		a.mu.Lock()
		stale := time.Since(a.lastSync) > syncOnOpenWait
		a.mu.Unlock()
		if stale {
			go a.sync()
		}
		if a.center.login().Token == "" {
			go a.startPairing()
		}
	case msgSystemLostCoordinator:
		a.saveNow()
		go a.sync()
	case msgStudy:
		a.mu.Lock()
		if s := a.sessionFor(in.Deck); s != nil && s.ahead != in.Ahead {
			s.ahead, s.last, s.current = in.Ahead, nil, nil
		}
		a.mu.Unlock()
		a.sendCard(in.Deck, false)
	case msgAnswer:
		a.answer(in.Deck, in.Card, in.Rating)
	case msgOptions:
		if in.NewPerDay != nil {
			a.setOption(in.Deck, *in.NewPerDay)
		}
	case msgSync:
		go a.sync()
	case msgPair:
		go a.startPairing()
	case msgStats:
		a.sendStats(in.Deck, in.Whole)
	}
}

func (a *app) sessionFor(id string) *session {
	d := a.col.decks[id]
	if d == nil {
		return nil
	}
	s := a.session[id]
	if s == nil || s.deck != d {
		s = &session{c: a.col, deck: d}
		a.session[id] = s
	}
	return s
}

// ---- studying

func (a *app) sendCard(deckID string, fresh bool) {
	a.mu.Lock()
	s := a.sessionFor(deckID)
	if s == nil {
		a.mu.Unlock()
		a.send(msgCard, map[string]any{"deck": deckID, "done": true, "missing": true})
		return
	}
	now := time.Now().Unix()
	k := s.current
	// The same card stays up until it is answered, unless what is due changed.
	if fresh || k == nil || a.col.cards[k.ID] != k {
		k = s.next(now)
	}
	out := map[string]any{"deck": deckID, "name": s.deck.Name, "counts": s.counts(now), "ahead": s.ahead, "studied": studiedIn(s)}
	if k == nil {
		out["done"] = true
		if next := s.nextLearningDue(now); next > 0 {
			out["nextMinutes"] = max(1, (next-now+59)/60)
			out["recheck"] = max(1, next-learnAhead-now)
		}
	} else {
		queue := 2
		if k.isNew() {
			queue = 0
		} else if k.learning() {
			queue = 1
		}
		var ivls [4]string
		for r := again; r <= easy; r++ {
			ivls[r-1] = interval(s.preview(k.memory, k.javaID, r, now).Due - now)
		}
		out["queue"] = queue
		out["card"] = map[string]any{"id": k.ID, "front": k.Front, "back": k.Back, "aux": k.Aux, "intervals": ivls}
	}
	a.mu.Unlock()
	a.send(msgCard, out)
}

func (a *app) answer(deckID, cardID string, rating int) {
	if rating < again || rating > easy {
		return
	}
	a.mu.Lock()
	s := a.sessionFor(deckID)
	if s != nil && s.current != nil && s.current.ID == cardID {
		s.rate(rating, time.Now().Unix())
		a.saveSoon()
		a.syncSoon()
	}
	a.mu.Unlock()
	a.sendCard(deckID, true)
}

func (a *app) setOption(deckID string, newPerDay int) {
	if newPerDay < auto || newPerDay > 9999 {
		return
	}
	a.mu.Lock()
	d := a.col.decks[deckID]
	if d != nil && d.NewPerDay != newPerDay {
		d.NewPerDay = newPerDay
		touch(&d.Mod, &d.Dirty, time.Now().UnixMilli())
		a.saveSoon()
	}
	a.mu.Unlock()
	a.sendState()
	go a.sync()
}

// ---- saving (callers hold mu, but saveNow)

func (a *app) saveSoon() {
	if a.saveT != nil {
		a.saveT.Stop()
	}
	a.saveT = time.AfterFunc(saveAfter, a.saveNow)
}

func (a *app) saveNow() {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.saveT != nil {
		a.saveT.Stop()
	}
	if err := a.col.save(); err != nil {
		logf("saving: %v", err)
	}
}

func (a *app) syncSoon() {
	if a.syncT != nil {
		a.syncT.Stop()
	}
	a.syncT = time.AfterFunc(syncAfter, a.sync)
}

// ---- sync

func (a *app) sync() {
	a.mu.Lock()
	if a.syncing {
		a.again = true
		a.mu.Unlock()
		return
	}
	if a.center.login().Token == "" {
		a.mu.Unlock()
		return
	}
	a.syncing, a.again = true, false
	body, sent := a.col.outgoing()
	a.mu.Unlock()
	a.sendState()

	reply, err := a.center.sync(body)
	a.mu.Lock()
	a.syncing = false
	a.lastSync = time.Now()
	a.syncErr = ""
	if err == nil {
		if err = a.col.apply(reply, sent); err != nil {
			err = errors.New("The command center's answer was unreadable.")
		} else if serr := a.col.save(); serr != nil {
			logf("saving: %v", serr)
		}
	}
	if errors.Is(err, errUnpaired) {
		a.center.forget()
		err = nil
	}
	if err != nil {
		a.syncErr = err.Error()
	}
	again := a.again && err == nil
	unpaired := a.center.login().Token == ""
	a.mu.Unlock()
	a.sendState()
	if unpaired {
		go a.startPairing()
	}
	if again {
		a.sync()
	}
}

// ---- pairing

func (a *app) startPairing() {
	a.mu.Lock()
	if a.pairing || a.center.login().Token != "" {
		a.mu.Unlock()
		return
	}
	a.pairing, a.pairErr, a.pair = true, "", nil
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		a.pairing = false
		a.mu.Unlock()
		a.sendState()
	}()

	p, err := a.center.startPairing()
	if err != nil {
		a.mu.Lock()
		a.pairErr = err.Error()
		a.mu.Unlock()
		return
	}
	a.mu.Lock()
	a.pair = &p
	a.mu.Unlock()
	a.sendState()
	for time.Now().Before(p.Expires) {
		time.Sleep(3 * time.Second)
		token, err := a.center.pollPairing(p)
		if err != nil && err.Error() != "No connection." {
			a.mu.Lock()
			a.pair, a.pairErr = nil, err.Error()
			a.mu.Unlock()
			return
		}
		if token != "" {
			l := a.center.login()
			l.Token = token
			if err := a.center.save(l); err != nil {
				a.mu.Lock()
				a.pair, a.pairErr = nil, err.Error()
				a.mu.Unlock()
				return
			}
			a.mu.Lock()
			a.pair = nil
			a.mu.Unlock()
			go a.sync()
			return
		}
	}
	a.mu.Lock()
	a.pair, a.pairErr = nil, "The code expired."
	a.mu.Unlock()
}

// ---- the state

func (a *app) sendState() {
	a.mu.Lock()
	now := time.Now().Unix()
	decks := []map[string]any{}
	for _, d := range a.col.Decks {
		s := a.sessionFor(d.ID)
		decks = append(decks, map[string]any{"id": d.ID, "name": d.Name, "newPerDay": d.NewPerDay, "counts": s.counts(now)})
	}
	l := a.center.login()
	host := l.Server
	if u, err := url.Parse(l.Server); err == nil && u.Host != "" {
		host = u.Host
	}
	state := map[string]any{
		"decks":   decks,
		"studied": studiedToday(a.col, now),
		"paired":  l.Token != "",
		"host":    host,
		"syncing": a.syncing,
		"error":   a.syncErr,
		"dirty":   a.col.dirty(),
		"synced":  !a.lastSync.IsZero(),
		"pairing": a.pairing,
		"pairErr": a.pairErr,
	}
	if a.pair != nil {
		state["code"] = a.pair.Code
	}
	a.mu.Unlock()
	a.send(msgState, state)
}

// sendStats sends a deck's statistics, or with whole the collection's.
func (a *app) sendStats(deckID string, whole bool) {
	a.mu.Lock()
	cards := a.col.Cards
	if !whole {
		cards = a.col.inDeck[deckID]
	}
	out := statsOf(cards, time.Now().Unix(), a.col.location()).message()
	a.mu.Unlock()
	out["deck"] = deckID
	out["whole"] = whole
	a.send(msgStat, out)
}

// studiedIn is whether the deck has a card ever answered, which Review
// Ahead needs.
func studiedIn(s *session) bool {
	for _, k := range s.cards() {
		if !k.isNew() {
			return true
		}
	}
	return false
}

// interval is how Anki's answer buttons put a wait: <1m, 10m, 3h, 4d, 1.5mo, 2.1y.
func interval(seconds int64) string {
	switch {
	case seconds < 60:
		return "<1m"
	case seconds < 3600:
		return fmt.Sprintf("%dm", seconds/60)
	case seconds < day:
		return fmt.Sprintf("%dh", seconds/3600)
	}
	days := float64(seconds) / day
	switch {
	case days < 30:
		return fmt.Sprintf("%d", int64(math.Floor(days+0.5))) + "d"
	case days < 365:
		return fmt.Sprintf("%.1fmo", days/30)
	}
	return fmt.Sprintf("%.1fy", days/365)
}
