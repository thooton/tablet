package main

import "time"

// One deck's queue, as ReviewSession on the phone has it, which is Anki's v3
// scheduler with FSRS and its default deck options:
//
//   - learning and relearning cards first once due (steps 1m 10m, and 10m),
//   - then the day's reviews, due before the next 4am rollover, oldest first,
//   - then new cards in deck order: with a number, that many a day, counting
//     every card first answered since the rollover on any device; on AUTO,
//     with no daily number, one at a time while fewer than autoWindow cards
//     are in learning or relearning (the only change from Anki, and only to
//     when a new card is introduced),
//   - then learning cards due within the 20-minute learn-ahead limit,
//   - then nothing: the deck is done for now; unless reviewing ahead (Anki's
//     "Review ahead"), which goes on to studied cards not yet due, the ones
//     most likely forgotten first (lowest predicted recall, then earliest
//     due, then deck order), never the card just answered twice running.
const (
	autoWindow   = 20 // ReviewSession.AUTO_WINDOW
	learnAhead   = 20 * 60
	rolloverHour = 4
)

type session struct {
	c       *collection
	deck    *deck
	current *card
	ahead   bool
	last    *card
}

func (s *session) cards() []*card { return s.c.inDeck[s.deck.ID] }

// dayEnd is the end of the Anki day now falls in: days run 4am to 4am.
func (s *session) dayEnd(now int64) int64 {
	loc := s.c.location()
	t := time.Unix(now, 0).In(loc).Add(-rolloverHour * time.Hour)
	y, m, d := t.Date()
	return time.Date(y, m, d+1, rolloverHour, 0, 0, 0, loc).Unix()
}

func (s *session) next(now int64) *card {
	end := s.dayEnd(now)
	var learning, rev, fresh *card
	for _, k := range s.cards() {
		if k.isNew() {
			if fresh == nil {
				fresh = k
			}
			continue
		}
		if k.learning() {
			if k.Due < end && (learning == nil || k.Due < learning.Due) {
				learning = k
			}
		} else if k.Due < end && (rev == nil || k.Due < rev.Due) {
			rev = k
		}
	}
	if fresh != nil && !s.wantsNew(now) {
		fresh = nil
	}
	switch {
	case learning != nil && learning.Due <= now:
		s.current = learning
	case rev != nil:
		s.current = rev
	case fresh != nil:
		s.current = fresh
	case learning != nil && learning.Due <= now+learnAhead:
		s.current = learning
	case s.ahead:
		s.current = s.earliest(now)
	default:
		s.current = nil
	}
	return s.current
}

// earliest is the studied card most likely forgotten, other than the one
// just answered, as ReviewSession.earliest on the phone.
func (s *session) earliest(now int64) *card {
	var best *card
	bestRecall := 0.0
	for _, k := range s.cards() {
		if k.isNew() || k == s.last {
			continue
		}
		r := retrievability(k.memory, now)
		if best == nil || r < bestRecall || r == bestRecall && k.Due < best.Due {
			best, bestRecall = k, r
		}
	}
	return best
}

// rate answers the current card and marks it for the next sync.
func (s *session) rate(rating int, now int64) {
	k := s.current
	if k == nil {
		return
	}
	if k.isNew() {
		k.Intro = now
	}
	k.memory = review(k.memory, k.javaID, rating, now)
	touch(&k.Mod, &k.Dirty, now*1000)
	s.last = k
	s.current = nil
}

// inLearning counts the cards in learning or relearning, due or not.
func (s *session) inLearning() int {
	n := 0
	for _, k := range s.cards() {
		if !k.isNew() && k.learning() {
			n++
		}
	}
	return n
}

func (s *session) wantsNew(now int64) bool {
	return s.newLeft(now) > 0
}

// newLeft is how many more new cards today's limit allows.
func (s *session) newLeft(now int64) int {
	if s.deck.NewPerDay < 0 {
		return max(0, autoWindow-s.inLearning())
	}
	start := s.dayEnd(now) - day
	today := 0
	for _, k := range s.cards() {
		if !k.isNew() && k.Intro >= start {
			today++
		}
	}
	return max(0, s.deck.NewPerDay-today)
}

// counts are Anki's: new cards on offer, learning cards due within
// learn-ahead, and reviews due today.
func (s *session) counts(now int64) [3]int {
	end := s.dayEnd(now)
	unseen, learning, reviews := 0, 0, 0
	for _, k := range s.cards() {
		switch {
		case k.isNew():
			unseen++
		case k.learning():
			if k.Due <= now+learnAhead {
				learning++
			}
		case k.Due < end:
			reviews++
		}
	}
	fresh := 0
	if s.wantsNew(now) {
		fresh = min(unseen, s.newLeft(now))
	}
	return [3]int{fresh, learning, reviews}
}

// nextLearningDue is when the next learning card due today comes up, or 0.
func (s *session) nextLearningDue(now int64) int64 {
	end := s.dayEnd(now)
	var next int64
	for _, k := range s.cards() {
		if k.isNew() || !k.learning() {
			continue
		}
		if k.Due < end && (next == 0 || k.Due < next) {
			next = k.Due
		}
	}
	return next
}

// studiedToday counts the cards answered since the rollover, in every deck.
func studiedToday(c *collection, now int64) int {
	if len(c.Decks) == 0 {
		return 0
	}
	start := (&session{c: c, deck: c.Decks[0]}).dayEnd(now) - day
	n := 0
	for _, k := range c.Cards {
		if !k.isNew() && k.Last >= start {
			n++
		}
	}
	return n
}
