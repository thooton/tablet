package main

import (
	"math"
	"unicode/utf16"
)

// FSRS-6, ported line for line from the java-fsrs 1.0.0 adaptation that
// Flashcards on the phone vendors (thooton/sonim, flashcards/android/core,
// io/github/openspacedrepetition/Scheduler.java), with its defaults: desired
// retention 0.9, learning steps 1m 10m, relearning step 10m, maximum
// interval 36500 days, fuzz on. The fuzz is drawn from java.util.Random
// seeded as the phone seeds it (the card's id and its last review), so a
// card answered on either device gets the same interval, and the interval
// shown over a button is the one it gives.

// Card states, as java-fsrs numbers them.
const (
	stateLearning   = 1
	stateReview     = 2
	stateRelearning = 3
)

// Ratings.
const (
	again = 1
	hard  = 2
	good  = 3
	easy  = 4
)

var fsrsParams = [21]float64{
	0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
	1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
}

const (
	desiredRetention = 0.9
	maximumInterval  = 36500
	stabilityMin     = 0.001
	day              = 86400
)

var (
	learningSteps   = []int64{60, 600} // seconds
	relearningSteps = []int64{600}
	decay           = -fsrsParams[20]
	factor          = math.Pow(0.9, 1.0/decay) - 1
)

// memory is a card's FSRS state. Step is nil in review; Stability and
// Difficulty are nil before the first answer; Last is 0 then too. Times are
// Unix seconds.
type memory struct {
	State      int      `json:"state"`
	Step       *int     `json:"step"`
	Stability  *float64 `json:"stability"`
	Difficulty *float64 `json:"difficulty"`
	Due        int64    `json:"due"`
	Last       int64    `json:"last"`
}

// javaRound is Java's Math.round: the nearest whole number, halves up.
func javaRound(x float64) int64 { return int64(math.Floor(x + 0.5)) }

// daysBetween is ChronoUnit.DAYS.between on instants: whole days, toward zero.
func daysBetween(from, to int64) int64 { return (to - from) / day }

func retrievability(m memory, now int64) float64 {
	if m.Last == 0 || m.Stability == nil {
		return 0
	}
	elapsed := float64(max(0, daysBetween(m.Last, now)))
	return math.Pow(1+factor*elapsed/(*m.Stability), decay)
}

func clampStability(s float64) float64 { return math.Max(s, stabilityMin) }

func clampDifficulty(d float64) float64 { return math.Min(math.Max(d, 1), 10) }

func initialStability(r int) float64 { return clampStability(fsrsParams[r-1]) }

func initialDifficulty(r int) float64 {
	return clampDifficulty(fsrsParams[4] - math.Pow(math.E, fsrsParams[5]*float64(r-1)) + 1)
}

func shortTermStability(s float64, r int) float64 {
	inc := math.Exp(fsrsParams[17]*(float64(r)-3+fsrsParams[18])) * math.Pow(s, -fsrsParams[19])
	if r >= hard {
		inc = math.Max(inc, 1)
	}
	return clampStability(s * inc)
}

func nextDifficulty(d float64, r int) float64 {
	arg1 := initialDifficulty(easy)
	delta := -(fsrsParams[6] * float64(r-3))
	arg2 := d + (10.0-d)*delta/9.0
	return clampDifficulty(fsrsParams[7]*arg1 + (1-fsrsParams[7])*arg2)
}

func nextStability(d, s, ret float64, r int) float64 {
	var next float64
	if r == again {
		long := fsrsParams[11] * math.Pow(d, -fsrsParams[12]) * (math.Pow(s+1, fsrsParams[13]) - 1) *
			math.Exp((1-ret)*fsrsParams[14])
		short := s / math.Exp(fsrsParams[17]*fsrsParams[18])
		next = math.Min(long, short)
	} else {
		hardPenalty, easyBonus := 1.0, 1.0
		if r == hard {
			hardPenalty = fsrsParams[15]
		}
		if r == easy {
			easyBonus = fsrsParams[16]
		}
		next = s * (1 + math.Exp(fsrsParams[8])*(11-d)*math.Pow(s, -fsrsParams[9])*
			(math.Exp((1-ret)*fsrsParams[10])-1)*hardPenalty*easyBonus)
	}
	return clampStability(next)
}

func nextIntervalDays(s float64) int64 {
	ivl := javaRound((s / factor) * (math.Pow(desiredRetention, 1/decay) - 1))
	return min(max(ivl, 1), maximumInterval)
}

var fuzzRanges = []struct{ start, end, factor float64 }{
	{2.5, 7.0, 0.15},
	{7.0, 20.0, 0.1},
	{20.0, math.Inf(1), 0.05},
}

func fuzzed(intervalDays int64, rng *javaRandom) int64 {
	if float64(intervalDays) < 2.5 {
		return intervalDays
	}
	delta := 1.0
	for _, f := range fuzzRanges {
		delta += f.factor * math.Max(math.Min(float64(intervalDays), f.end)-f.start, 0)
	}
	lo := javaRound(float64(intervalDays) - delta)
	hi := javaRound(float64(intervalDays) + delta)
	lo = max(2, lo)
	hi = min(hi, maximumInterval)
	lo = min(lo, hi)
	return min(int64(math.Floor(rng.nextDouble()*float64(hi-lo+1)))+lo, maximumInterval)
}

// stepInterval is a learning or relearning step's wait for rating r, and
// whether the card graduates instead.
func stepInterval(steps []int64, step *int, r int) (wait int64, nextStep int, graduate bool) {
	at := 0
	if step != nil {
		at = *step
	}
	if len(steps) == 0 || (at >= len(steps) && r >= hard) {
		return 0, 0, true
	}
	switch r {
	case again:
		return steps[0], 0, false
	case hard:
		if at == 0 && len(steps) == 1 {
			return javaRound(float64(steps[0]*1000)*1.5) / 1000, at, false
		} else if at == 0 {
			return javaRound(float64(steps[0]*1000+steps[1]*1000)/2.0) / 1000, at, false
		}
		return steps[at], at, false
	case good:
		if at+1 == len(steps) {
			return 0, 0, true
		}
		return steps[at+1], at + 1, false
	}
	return 0, 0, true
}

// review answers card m (whose java-fsrs id is cardID) with rating r at
// now, as ReviewSession.answer does on the phone.
func review(m memory, cardID int32, r int, now int64) memory {
	if now < m.Last {
		now = m.Last
	}
	seed := cardID*31 + javaLongHash(m.Last)
	rng := newJavaRandom(int64(seed))

	var elapsed *int64
	if m.Last != 0 {
		d := daysBetween(m.Last, now)
		elapsed = &d
	}
	sameDay := elapsed != nil && *elapsed < 1
	f := func(v float64) *float64 { return &v }
	var wait int64 // seconds

	switch m.State {
	case stateLearning, stateRelearning:
		if m.State == stateLearning && m.Stability == nil && m.Difficulty == nil {
			m.Stability, m.Difficulty = f(initialStability(r)), f(initialDifficulty(r))
		} else if sameDay {
			s := shortTermStability(*m.Stability, r)
			d := nextDifficulty(*m.Difficulty, r)
			m.Stability, m.Difficulty = f(s), f(d)
		} else {
			s := nextStability(*m.Difficulty, *m.Stability, retrievability(m, now), r)
			d := nextDifficulty(*m.Difficulty, r)
			m.Stability, m.Difficulty = f(s), f(d)
		}
		steps := learningSteps
		if m.State == stateRelearning {
			steps = relearningSteps
		}
		var graduate bool
		var next int
		wait, next, graduate = stepInterval(steps, m.Step, r)
		if r == easy {
			graduate = true
		}
		if graduate {
			m.State, m.Step = stateReview, nil
			wait = nextIntervalDays(*m.Stability) * day
		} else {
			m.Step = &next
		}
	case stateReview:
		if sameDay {
			m.Stability = f(shortTermStability(*m.Stability, r))
		} else {
			m.Stability = f(nextStability(*m.Difficulty, *m.Stability, retrievability(m, now), r))
		}
		m.Difficulty = f(nextDifficulty(*m.Difficulty, r))
		if r == again {
			zero := 0
			m.State, m.Step = stateRelearning, &zero
			wait = relearningSteps[0]
		} else {
			wait = nextIntervalDays(*m.Stability) * day
		}
	}
	if m.State == stateReview {
		wait = fuzzed(wait/day, rng) * day
	}
	m.Due = now + wait
	m.Last = now
	return m
}

// javaStringHash is String.hashCode, over UTF-16 code units as Java's strings are.
func javaStringHash(s string) int32 {
	var h int32
	for _, c := range utf16.Encode([]rune(s)) {
		h = 31*h + int32(c)
	}
	return h
}

// javaLongHash is Long.hashCode.
func javaLongHash(v int64) int32 { return int32(v ^ int64(uint64(v)>>32)) }

// javaRandom is java.util.Random's generator, enough for nextDouble.
type javaRandom struct{ seed int64 }

const (
	javaMultiplier = 0x5DEECE66D
	javaMask       = (1 << 48) - 1
)

func newJavaRandom(seed int64) *javaRandom {
	return &javaRandom{seed: (seed ^ javaMultiplier) & javaMask}
}

func (r *javaRandom) next(bits uint) int32 {
	r.seed = (r.seed*javaMultiplier + 0xB) & javaMask
	return int32(uint64(r.seed) >> (48 - bits))
}

func (r *javaRandom) nextDouble() float64 {
	return float64(int64(r.next(26))<<27+int64(r.next(27))) * (1.0 / (1 << 53))
}
