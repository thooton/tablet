package main

import (
	"fmt"
	"math"
	"strconv"
	"time"
)

// Anki's Statistics window, cut to what the cards' own state can tell (no
// review log is kept): Today, Future Due, Card Counts, Review Intervals and
// Card Retrievability. It is the phone's algo/Stats; change them together.

var countNames = []string{"New", "Learning", "Relearning", "Young", "Mature"}

const (
	countNew = iota
	countLearning
	countRelearning
	countYoung
	countMature
)

const (
	matureDays = 21 // a review card is mature from this interval on, as in Anki
	dueDays    = 30 // Future Due: today and the 29 days after it
	recallBins = 10 // Card Retrievability: 0-10% ... 90-100%
)

// Review Intervals' bins: each holds intervals up to its bound, in days; the last, the rest.
var (
	intervalBounds = []int{1, 3, 7, 14, 30, 90, 180, 365}
	intervalLabels = []string{"1d", "3d", "1w", "2w", "1m", "3m", "6m", "1y", "1y+"}
)

type stats struct {
	total, studied, introduced int
	counts                     [5]int
	due                        [dueDays]int
	intervals                  [9]int
	averageInterval            float64
	longestInterval            int
	recall                     [recallBins]int
	averageRecall, knowledge   float64
}

func statsOf(cards []*card, now int64, loc *time.Location) stats {
	t := time.Unix(now, 0).In(loc).Add(-rolloverHour * time.Hour)
	y, m, d := t.Date()
	dayStart := time.Date(y, m, d, rolloverHour, 0, 0, 0, loc).Unix()
	dayEnd := time.Date(y, m, d+1, rolloverHour, 0, 0, 0, loc).Unix()

	var s stats
	var intervalSum int64
	reviewCards, seen := 0, 0
	for _, k := range cards {
		s.total++
		if k.isNew() {
			s.counts[countNew]++
			continue
		}
		seen++
		if k.Last >= dayStart {
			s.studied++
		}
		if k.Intro >= dayStart {
			s.introduced++
		}
		switch k.State {
		case stateLearning:
			s.counts[countLearning]++
		case stateRelearning:
			s.counts[countRelearning]++
		default:
			ivl := intervalDays(k.Last, k.Due)
			if ivl >= matureDays {
				s.counts[countMature]++
			} else {
				s.counts[countYoung]++
			}
			s.intervals[intervalBin(ivl)]++
			intervalSum += int64(ivl)
			s.longestInterval = max(s.longestInterval, ivl)
			reviewCards++
		}
		at := int64(0)
		if k.Due >= dayEnd {
			at = 1 + (k.Due-dayEnd)/day
		}
		if at < dueDays {
			s.due[at]++
		}
		r := math.Max(0, math.Min(1, retrievability(k.memory, now)))
		s.recall[min(recallBins-1, int(math.Floor(r*recallBins)))]++
		s.knowledge += r
	}
	if reviewCards > 0 {
		s.averageInterval = float64(intervalSum) / float64(reviewCards)
	}
	if seen > 0 {
		s.averageRecall = s.knowledge / float64(seen)
	}
	return s
}

// intervalDays is a review card's interval in whole days (Anki's ivl).
func intervalDays(last, due int64) int {
	return int(math.Floor(float64(due-last)/day + 0.5))
}

func intervalBin(days int) int {
	for i, b := range intervalBounds {
		if days <= b {
			return i
		}
	}
	return len(intervalBounds)
}

func (s stats) dueTotal() int {
	n := 0
	for _, v := range s.due {
		n += v
	}
	return n
}

// percent is a share of all cards: "12.5%".
func (s stats) percent(n int) string {
	if s.total == 0 {
		return "0%"
	}
	return fmt.Sprintf("%.1f%%", 100*float64(n)/float64(s.total))
}

// span is a length of time as Anki's statistics put it: "1 day", "13.9
// days", "1.5 months", "2 years".
func span(days float64) string {
	switch {
	case days < 30:
		return amount(days, "day")
	case days < 365:
		return amount(days/30, "month")
	}
	return amount(days/365, "year")
}

func amount(n float64, unit string) string {
	s := decimal(n) + " " + unit
	if math.Floor(n*10+0.5)/10 != 1 {
		s += "s"
	}
	return s
}

// decimal is one decimal, as Anki's footers give averages: "12.3", "4".
func decimal(n float64) string {
	r := math.Floor(n*10+0.5) / 10
	if r == math.Trunc(r) {
		return strconv.FormatInt(int64(r), 10)
	}
	return strconv.FormatFloat(r, 'f', 1, 64)
}

// message is the stats (103) as the screen draws them.
func (s stats) message() map[string]any {
	percents := make([]string, len(s.counts))
	for i, n := range s.counts {
		percents[i] = s.percent(n)
	}
	total := s.dueTotal()
	return map[string]any{
		"total":           s.total,
		"studied":         s.studied,
		"introduced":      s.introduced,
		"countNames":      countNames,
		"counts":          s.counts,
		"percents":        percents,
		"due":             s.due,
		"dueTotal":        total,
		"dueAverage":      decimal(float64(total) / dueDays),
		"intervals":       s.intervals,
		"intervalLabels":  intervalLabels,
		"averageInterval": span(s.averageInterval),
		"longestInterval": span(float64(s.longestInterval)),
		"recall":          s.recall,
		"averageRecall":   decimal(100*s.averageRecall) + "%",
		"knowledge":       int(math.Floor(s.knowledge + 0.5)),
	}
}
