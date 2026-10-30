package main

import "time"

// One deck's queue, as ReviewSession on the phone has it, which is Anki's v3
// scheduler with FSRS and its default deck options:
//
//   - learning and relearning cards first once due (steps 1m 10m, and 10m),
//   - then the day's reviews, due before the next 4am rollover, oldest first,
//     with new cards mixed in among them, spread evenly, as Anki's default
//     "Mix with reviews" does; new cards come in deck order, and how many:
//     with a number, that many a day, counting every card first answered
//     since the rollover on any device; on AUTO, enough to bring New +
//     Learning + Due up to autoTarget, so none while Learning + Due is at it
//     or over (the only change from Anki, and only to when a new card is
//     introduced),
//   - then learning cards due within the 20-minute learn-ahead limit,
//   - then nothing: the deck is done for now; unless reviewing ahead (Anki's
//     "Review ahead"), which goes on to studied cards not yet due, the ones
//     most likely forgotten first (lowest predicted recall, then earliest
//     due, then deck order), never the card just answered twice running.
const (
	autoTarget   = 20 // ReviewSession.AUTO_TARGET
	learnAhead   = 20 * 60
	rolloverHour = 4
)

type session struct {
	c       *collection
	deck    *deck
	current *card
	ahead   bool
	last    *card
	// New cards and reviews shown this session, to spread one among the other.
	newShown, reviewsShown int
}

func (s *session) cards() []*card { return s.c.inDeck[s.deck.ID] }

// preview is what rating r would make of card m (java-fsrs id cardID) at
// now, as ReviewSession.preview on the phone: Anki days and the rollover
// counted in the phone's time zone.
func (s *session) preview(m memory, cardID int32, r int, now int64) memory {
	last := m.Last
	if last == 0 {
		last = now
	}
	now = max(now, last)
	return review(m, cardID, r, now, s.daysSince(last, now), s.dayEnd(now)-now)
}

// recall is the probability card m is recalled at now (0 when unseen).
func (s *session) recall(m memory, now int64) float64 {
	if m.Last == 0 {
		return 0
	}
	return retrievability(m, s.daysSince(m.Last, now))
}

// daysSince is the Anki days from then to now: how many 4am rollovers lie between.
func (s *session) daysSince(then, now int64) int64 {
	return max(0, s.day(now)-s.day(then))
}

// day is the Anki day t falls in, as days since 1970-01-01.
func (s *session) day(t int64) int64 {
	y, m, d := time.Unix(t, 0).In(s.c.location()).Add(-rolloverHour * time.Hour).Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC).Unix() / day
}

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
	counts := s.counts(now)
	if counts[0] == 0 {
		fresh = nil
	}
	switch {
	case learning != nil && learning.Due <= now:
		s.current = learning
	case rev != nil && fresh != nil:
		s.current = rev
		if s.newTurn(counts[0], counts[2]) {
			s.current = fresh
		}
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

// newTurn is whether a new card's turn has come among the reviews: so far
// this session new cards have had less than their share of what is left, as
// Anki's intersperser spreads them. A review goes first.
func (s *session) newTurn(fresh, reviews int) bool {
	return int64(s.newShown)*int64(reviews) < int64(s.reviewsShown)*int64(fresh)
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
		r := s.recall(k.memory, now)
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
		s.newShown++
	} else if !k.learning() {
		s.reviewsShown++
	}
	k.memory = s.preview(k.memory, k.javaID, rating, now)
	touch(&k.Mod, &k.Dirty, now*1000)
	s.last = k
	s.current = nil
}

// newLeft is how many more new cards may come in: today's limit, less those
// already introduced; on AUTO, what brings New + Learning + Due up to the target.
func (s *session) newLeft(now int64) int {
	if s.deck.NewPerDay < 0 {
		learning, reviews := s.oldCounts(now)
		return max(0, autoTarget-learning-reviews)
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
	unseen := 0
	for _, k := range s.cards() {
		if k.isNew() {
			unseen++
		}
	}
	learning, reviews := s.oldCounts(now)
	return [3]int{min(unseen, s.newLeft(now)), learning, reviews}
}

// oldCounts are learning cards due within learn-ahead, and reviews due today.
func (s *session) oldCounts(now int64) (learning, reviews int) {
	end := s.dayEnd(now)
	for _, k := range s.cards() {
		switch {
		case k.isNew():
		case k.learning():
			if k.Due <= now+learnAhead {
				learning++
			}
		case k.Due < end:
			reviews++
		}
	}
	return learning, reviews
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
