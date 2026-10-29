package main

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// testdata/java-fsrs.json is the phone's scheduler (ReviewSession.preview
// in thooton/sonim's flashcards core) walking cards through random answers,
// at all hours in the phone's time zone (written by the core's
// TabletVectors). The tablet must give every answer the same state and the
// same due date, fuzz, Anki days and the rollover included.
func TestReviewMatchesThePhone(t *testing.T) {
	data, err := os.ReadFile("testdata/java-fsrs.json")
	if err != nil {
		t.Fatal(err)
	}
	var steps []struct {
		ID      string
		Zone    string
		Now     int64
		Rating  int
		In, Out memory
	}
	if err := json.Unmarshal(data, &steps); err != nil {
		t.Fatal(err)
	}
	if len(steps) < 500 {
		t.Fatalf("only %d steps", len(steps))
	}
	for i, s := range steps {
		sess := &session{c: &collection{Zone: s.Zone}}
		got := sess.preview(s.In, javaStringHash(s.ID), s.Rating, s.Now)
		want := s.Out
		if got.State != want.State || got.Due != want.Due || got.Last != want.Last ||
			!sameInt(got.Step, want.Step) || !sameFloat(got.Stability, want.Stability) || !sameFloat(got.Difficulty, want.Difficulty) {
			t.Fatalf("step %d (%s, rating %d): got %+v %v %v %v, want %+v %v %v %v", i, s.ID, s.Rating,
				got, deref(got.Step), derefF(got.Stability), derefF(got.Difficulty),
				want, deref(want.Step), derefF(want.Stability), derefF(want.Difficulty))
		}
	}
}

func sameInt(a, b *int) bool { return (a == nil) == (b == nil) && (a == nil || *a == *b) }

func sameFloat(a, b *float64) bool {
	return (a == nil) == (b == nil) && (a == nil || math.Abs(*a-*b) <= 1e-9*math.Max(1, math.Abs(*b)))
}

func deref(p *int) any {
	if p == nil {
		return nil
	}
	return *p
}

func derefF(p *float64) any {
	if p == nil {
		return nil
	}
	return *p
}

func TestJavaHashes(t *testing.T) {
	if got := javaStringHash("hello"); got != 99162322 {
		t.Fatalf("hash of hello: %d", got)
	}
	if got := javaLongHash(1700000000); got != 1700000000 {
		t.Fatalf("long hash: %d", got)
	}
	// new Random(42).nextDouble()
	if got := newJavaRandom(42).nextDouble(); math.Abs(got-0.7275636800328681) > 1e-16 {
		t.Fatalf("random: %v", got)
	}
}

// round2 rounds as the script's +x.toFixed(2) does: the double's exact value.
func TestRound2(t *testing.T) {
	for in, want := range map[float64]float64{2.125: 2.13, 1.005: 1, 0.005000000000000001: 0.01, 39.215: 39.22, 1.2931: 1.29} {
		if got := round2(in); got != want {
			t.Errorf("round2(%v) = %v, want %v", in, got, want)
		}
	}
}

const noon = int64(1_700_049_600)

func testCollection(n int, newPerDay int) *collection {
	c := newCollection(filepath.Join(os.TempDir(), "unused.json"))
	c.Zone = "UTC"
	c.Decks = []*deck{{ID: "d", Name: "Deck", NewPerDay: newPerDay}}
	for i := 0; i < n; i++ {
		zero := 0
		c.Cards = append(c.Cards, &card{ID: string(rune('a' + i)), Deck: "d", Ord: i, Front: "f", Back: "b",
			memory: memory{State: stateLearning, Step: &zero, Due: noon}})
	}
	c.index()
	return c
}

func TestDailyLimit(t *testing.T) {
	c := testCollection(10, 3)
	s := &session{c: c, deck: c.Decks[0]}
	if got := s.counts(noon)[0]; got != 3 {
		t.Fatalf("new on offer: %d", got)
	}
	now, introduced := noon, 0
	for k := s.next(now); k != nil; k = s.next(now) {
		if k.isNew() {
			introduced++
		}
		s.rate(easy, now)
		now += 10
	}
	if introduced != 3 {
		t.Fatalf("introduced %d", introduced)
	}
	if got := s.counts(noon + day)[0]; got != 3 {
		t.Fatalf("tomorrow: %d", got)
	}
}

func TestAutoTopsUpToTheTarget(t *testing.T) {
	c := testCollection(25, auto)
	s := &session{c: c, deck: c.Decks[0]}
	if got := s.counts(noon)[0]; got != autoTarget {
		t.Fatalf("new on offer: %d", got)
	}
	stab, diff := 10.0, 5.0
	for _, k := range c.inDeck["d"][:12] {
		k.memory = memory{State: stateReview, Stability: &stab, Difficulty: &diff, Due: noon - 3600, Last: noon - 3600 - 10*day}
	}
	n := s.counts(noon)
	if n != [3]int{8, 0, 12} {
		t.Fatalf("counts %v, want 8 new to make 20 with 12 due", n)
	}
}

// mixOrder is the order new (n) and review (r) cards come in, ten reviews
// due and the rest new, every card answered Easy. The phone's ReviewSession
// gives the same (AlgoTests: new cards mixed in among reviews).
func mixOrder(steps int) string {
	c := testCollection(25, auto)
	stab, diff := 10.0, 5.0
	for _, k := range c.inDeck["d"][:10] {
		k.memory = memory{State: stateReview, Stability: &stab, Difficulty: &diff, Due: noon - 3600, Last: noon - 3600 - 10*day}
	}
	s := &session{c: c, deck: c.Decks[0]}
	out := []byte{}
	now := noon
	for i := 0; i < steps; i++ {
		k := s.next(now)
		if k.isNew() {
			out = append(out, 'n')
		} else {
			out = append(out, 'r')
		}
		s.rate(easy, now)
		now += 10
	}
	return string(out)
}

func TestNewCardsMixIntoReviews(t *testing.T) {
	if got := mixOrder(12); got != "rnnrnrnnrnrn" {
		t.Fatalf("order %s", got)
	}
}

func TestSyncMerge(t *testing.T) {
	c := testCollection(2, auto)
	s := &session{c: c, deck: c.Decks[0]}
	s.next(noon)
	s.rate(good, noon)
	body, sent := c.outgoing()
	var out syncBody
	json.Unmarshal(body, &out)
	if len(out.Cards) != 1 || out.Cards[0].Intro != noon {
		t.Fatalf("outgoing: %s", body)
	}
	first := c.inDeck["d"][0]
	// Answered again before the reply came: that stays to send.
	touch(&first.Mod, &first.Dirty, noon*1000+5000)
	stab := 20.0
	diff := 5.0
	older := &card{ID: "a", Deck: "d", memory: memory{State: stateReview, Stability: &stab, Difficulty: &diff, Due: noon + 20*day, Last: noon - 60}, Mod: (noon - 60) * 1000}
	newer := &card{ID: "b", Deck: "d", Ord: 1, memory: memory{State: stateReview, Stability: &stab, Difficulty: &diff, Due: noon + 20*day, Last: noon + 60}, Mod: (noon + 60) * 1000}
	reply, _ := json.Marshal(map[string]any{"usn": 5, "zone": "America/Phoenix", "decks": []any{}, "cards": []any{older, newer}})
	if err := c.apply(reply, sent); err != nil {
		t.Fatal(err)
	}
	if first.State != stateLearning || !first.Dirty {
		t.Fatalf("ours was overwritten: %+v", first)
	}
	if b := c.cards["b"]; b.State != stateReview || b.Dirty {
		t.Fatalf("theirs wasn't taken: %+v", b)
	}
	if c.USN != 5 || c.location().String() != "America/Phoenix" {
		t.Fatalf("usn %d zone %s", c.USN, c.location())
	}
}

func TestCollectionFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "collection.json")
	c := testCollection(3, 7)
	c.path = path
	s := &session{c: c, deck: c.Decks[0]}
	s.next(noon)
	s.rate(again, noon)
	if err := c.save(); err != nil {
		t.Fatal(err)
	}
	back, err := loadCollection(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(back.Cards) != 3 || back.Decks[0].NewPerDay != 7 || !back.dirty() || back.cards["a"].Intro != noon {
		t.Fatalf("round trip: %+v", back)
	}
}

func TestDayEndUsesThePhonesZone(t *testing.T) {
	c := testCollection(1, auto)
	c.Zone = "America/Phoenix" // UTC-7, no DST
	s := &session{c: c, deck: c.Decks[0]}
	// 10:00 UTC is 03:00 in Phoenix: still the previous Anki day, which ends at 04:00 there.
	at := time.Date(2026, 3, 1, 10, 0, 0, 0, time.UTC).Unix()
	want := time.Date(2026, 3, 1, 11, 0, 0, 0, time.UTC).Unix()
	if got := s.dayEnd(at); got != want {
		t.Fatalf("day end %v, want %v", time.Unix(got, 0).UTC(), time.Unix(want, 0).UTC())
	}
}

func TestInterval(t *testing.T) {
	for in, want := range map[int64]string{30: "<1m", 600: "10m", 7200: "2h", 4 * day: "4d", 45 * day: "1.5mo", 800 * day: "2.2y"} {
		if got := interval(in); got != want {
			t.Errorf("interval(%d) = %s, want %s", in, got, want)
		}
	}
}

func TestReviewAhead(t *testing.T) {
	c := testCollection(3, 0)
	stab30, stab5, diff := 30.0, 5.0, 5.0
	soon, later := c.inDeck["d"][0], c.inDeck["d"][1]
	soon.memory = memory{State: stateReview, Stability: &stab30, Difficulty: &diff, Due: noon + 10*day, Last: noon - 20*day}
	later.memory = memory{State: stateReview, Stability: &stab5, Difficulty: &diff, Due: noon + 40*day, Last: noon - 2*day}
	s := &session{c: c, deck: c.Decks[0]}
	if s.next(noon) != nil {
		t.Fatal("something is due")
	}
	s.ahead = true
	first := s.next(noon)
	other := later
	if first == later {
		other = soon
	}
	if first == nil || s.recall(first.memory, noon) > s.recall(other.memory, noon) {
		t.Fatalf("not the likeliest forgotten first: %+v", first)
	}
	s.rate(good, noon)
	if second := s.next(noon + 10); second == nil || second == first || second.isNew() {
		t.Fatalf("second: %+v", second)
	}
}

func TestSyncDropsRemovedCards(t *testing.T) {
	c := testCollection(2, auto)
	s := &session{c: c, deck: c.Decks[0]}
	s.next(noon)
	s.rate(good, noon)
	_, sent := c.outgoing()
	answered := *c.inDeck["d"][0]
	answered.Deleted, answered.Dirty = true, false
	reply, _ := json.Marshal(map[string]any{"usn": 6, "decks": []any{}, "cards": []any{&answered}})
	if err := c.apply(reply, sent); err != nil {
		t.Fatal(err)
	}
	if c.cards[answered.ID] != nil || len(c.inDeck["d"]) != 1 || len(c.Cards) != 1 || c.dirty() {
		t.Fatalf("the removed card stayed: %d in the deck, %d kept", len(c.inDeck["d"]), len(c.Cards))
	}
}

func TestSyncDropsRemovedCardWithWeakMemory(t *testing.T) {
	c := testCollection(2, auto)
	_, sent := c.outgoing()
	gone := *c.inDeck["d"][0]
	zero, ten := 0.0, 5.0
	gone.State, gone.Last, gone.Stability, gone.Difficulty = stateReview, 1, &zero, &ten
	gone.Step = nil
	gone.Deleted = true
	reply, _ := json.Marshal(map[string]any{"usn": 7, "decks": []any{}, "cards": []any{&gone}})
	if err := c.apply(reply, sent); err != nil {
		t.Fatal(err)
	}
	if c.cards[gone.ID] != nil || len(c.inDeck["d"]) != 1 {
		t.Fatalf("the removed card stayed: %d in the deck", len(c.inDeck["d"]))
	}
}
