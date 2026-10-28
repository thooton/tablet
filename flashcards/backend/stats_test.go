package main

import (
	"math"
	"testing"
	"time"
)

// The phone's StatsTests builds the same six cards and wants the same numbers.
func TestStatsMatchThePhone(t *testing.T) {
	const now, h, d = int64(1_000_036_800), int64(3600), int64(86400)
	mk := func(id string, state int, last, due int64, stability float64, intro int64) *card {
		k := &card{ID: "fixture:" + id, Intro: intro}
		if last != 0 {
			diff := 5.0
			k.memory = memory{State: state, Stability: &stability, Difficulty: &diff, Due: due, Last: last}
			if state != stateReview {
				zero := 0
				k.Step = &zero
			}
		} else {
			zero := 0
			k.memory = memory{State: stateLearning, Step: &zero, Due: now}
		}
		return k
	}
	cards := []*card{
		mk("new", 0, 0, 0, 0, 0),
		mk("learning", stateLearning, now-600, now+600, 2.3, now-600),
		mk("relearning", stateRelearning, now-h, now+60, 1.2, now-40*d),
		mk("young", stateReview, now-2*d, now+3*d, 5.1, now-9*d),
		mk("mature", stateReview, now-10*d, now+20*d, 31.0, now-90*d),
		mk("overdue", stateReview, now-10*d, now-d, 8.0, now-30*d),
	}
	s := statsOf(cards, now, time.UTC)
	if s.total != 6 || s.studied != 2 || s.introduced != 1 {
		t.Fatalf("total %d, studied %d, introduced %d", s.total, s.studied, s.introduced)
	}
	if s.counts != [5]int{1, 1, 1, 2, 1} {
		t.Fatalf("counts %v", s.counts)
	}
	var due [dueDays]int
	due[0], due[3], due[20] = 3, 1, 1
	if s.due != due {
		t.Fatalf("due %v", s.due)
	}
	if s.intervals != [9]int{0, 0, 1, 1, 1, 0, 0, 0, 0} || s.longestInterval != 30 ||
		math.Abs(s.averageInterval-44.0/3) > 1e-9 {
		t.Fatalf("intervals %v, longest %d, average %v", s.intervals, s.longestInterval, s.averageInterval)
	}
	if math.Abs(s.knowledge-4.7935417018) > 1e-6 {
		t.Fatalf("knowledge %v", s.knowledge)
	}
	binned := 0
	for _, n := range s.recall {
		binned += n
	}
	if binned != 5 {
		t.Fatalf("recall %v", s.recall)
	}
	if s.percent(2) != "33.3%" {
		t.Fatalf("percent %s", s.percent(2))
	}
	for in, want := range map[float64]string{1: "1 day", 13.94: "13.9 days", 45: "1.5 months", 730: "2 years"} {
		if got := span(in); got != want {
			t.Fatalf("span(%v) = %q, want %q", in, got, want)
		}
	}
}
