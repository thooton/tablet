package main

import (
	"math"
	"math/big"
	"unicode/utf16"
)

// The scheduler, ported line for line from the phone's (thooton/sonim,
// flashcards/android/core, com/flashcards/xp3/algo/Fsrs.java): Anki (v3, its
// default deck options, FSRS off) running the FSRS4Anki v6.1.1 custom
// scheduler (open-spaced-repetition/fsrs4anki, fsrs4anki_scheduler.js), with
// the script's defaults: FSRS-6's default parameters, request retention 0.9,
// maximum interval 36500 days, fuzz on.
//
// Anki decides the learning side: steps 1m 10m, relearning 10m; Again goes to
// the first step, Hard repeats the step (the first waits the average of the
// first two, or half again a lone step), Good moves on or graduates, Easy
// graduates; a step gets up to 25% more, at most 5 minutes; one that reaches
// past the 4am rollover comes due as a later day starts. The script decides
// the rest: a new card starts from its rating's initial state; every answer in
// (re)learning uses the short-term formula, whatever the time since the last,
// and Hard there may lower stability; a review card uses the long-term
// formulas, recall from the Anki days since its last review (0 counts as
// recall 1); stability and difficulty are rounded to two decimals at every
// step; intervals are fuzzed by 5% and a day either side, never below the
// previous interval when they grew, and Hard <= Good < Easy.
//
// The fuzz is the phone's, not the script's: one draw per answer from
// java.util.Random seeded by the card's id and last review, so a card
// answered on either device gets the same interval, and the interval shown
// over a button is the one it gives.

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

var w = [21]float64{
	0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
	1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
}

const (
	requestRetention = 0.9
	maximumInterval  = 36500
	day              = 86400
)

var (
	learningSteps   = []int64{60, 600} // seconds
	relearningSteps = []int64{600}
	decay           = -w[20]
	factor          = math.Pow(0.9, 1/decay) - 1
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

// review answers card m (whose java-fsrs id is cardID) with rating r at now,
// given the Anki days since its last review and the seconds to the next
// rollover, as Fsrs.review does on the phone.
func review(m memory, cardID int32, r int, now, elapsedDays, untilRollover int64) memory {
	if now < m.Last {
		now = m.Last
	}
	fuzz := newJavaRandom(int64(cardID*31 + javaLongHash(m.Last))).nextDouble()
	f := func(v float64) *float64 { return &v }
	next := m
	next.Last = now

	switch {
	case m.Last == 0:
		// a new card: init_states
		next.State = stateLearning
		next.Stability, next.Difficulty = f(initStability(r)), f(initDifficulty(r))
		goodDays := nextInterval(initStability(good), fuzz, -1)
		easyDays := max(nextInterval(initStability(easy), fuzz, -1), goodDays+1)
		step(&next, learningSteps, 0, r, now, untilRollover, fuzz, goodDays, easyDays)
	case m.State != stateReview:
		var s, d float64
		if m.Stability == nil || m.Difficulty == nil || *m.Stability == 0 || *m.Difficulty == 0 {
			s, d = initStability(again), initDifficulty(again)
		} else {
			s, d = *m.Stability, *m.Difficulty
		}
		next.Stability, next.Difficulty = f(shortTermStability(s, r)), f(nextDifficulty(d, r))
		goodDays := nextInterval(shortTermStability(s, good), fuzz, -1)
		easyDays := max(nextInterval(shortTermStability(s, easy), fuzz, -1), goodDays+1)
		steps := learningSteps
		if m.State == stateRelearning {
			steps = relearningSteps
		}
		at := 0
		if m.Step != nil {
			at = *m.Step
		}
		at = max(0, min(at, len(steps)-1))
		step(&next, steps, at, r, now, untilRollover, fuzz, goodDays, easyDays)
	default:
		scheduled := scheduledDays(m)
		var s, d float64
		if m.Stability == nil || m.Difficulty == nil || *m.Stability == 0 || *m.Difficulty == 0 {
			// convert_states, from Anki's default starting ease
			s = round2(math.Max(float64(scheduled), 0.1))
			d = constrainDifficulty(11 - (2.5-1)/
				(math.Exp(w[8])*math.Pow(s, -w[9])*(math.Exp(0.1*w[10])-1)))
		} else {
			s, d = *m.Stability, *m.Difficulty
		}
		ret := forgettingCurve(float64(max(0, elapsedDays)), s)
		next.Difficulty = f(nextDifficulty(d, r))
		if r == again {
			zero := 0
			next.Stability = f(nextForgetStability(d, s, ret))
			next.State, next.Step = stateRelearning, &zero
			next.Due = stepDue(now, relearningSteps[0], untilRollover, fuzz)
			return next
		}
		hardDays := nextInterval(nextRecallStability(d, s, ret, hard), fuzz, scheduled)
		goodDays := nextInterval(nextRecallStability(d, s, ret, good), fuzz, scheduled)
		easyDays := nextInterval(nextRecallStability(d, s, ret, easy), fuzz, scheduled)
		hardDays = min(hardDays, goodDays)
		goodDays = max(goodDays, hardDays+1)
		easyDays = max(easyDays, goodDays+1)
		next.Stability = f(nextRecallStability(d, s, ret, r))
		days := easyDays
		if r == hard {
			days = hardDays
		} else if r == good {
			days = goodDays
		}
		next.Due = now + days*day
	}
	return next
}

// retrievability is the probability of recall after elapsedDays Anki days
// (0 when unseen).
func retrievability(m memory, elapsedDays int64) float64 {
	if m.Last == 0 || m.Stability == nil {
		return 0
	}
	return forgettingCurve(float64(max(0, elapsedDays)), *m.Stability)
}

// step is one step of Anki's learning or relearning, or graduation.
func step(next *memory, steps []int64, at, r int, now, untilRollover int64, fuzz float64, goodDays, easyDays int64) {
	var wait int64
	switch {
	case r == again:
		at = 0
		wait = steps[0]
	case r == hard:
		switch {
		case at > 0:
			wait = steps[at]
		case len(steps) > 1:
			wait = (steps[0] + steps[1]) / 2
		default:
			wait = min(steps[0]*3/2, steps[0]+day)
		}
	case r == good && at+1 < len(steps):
		at++
		wait = steps[at]
	default:
		next.State, next.Step = stateReview, nil
		days := easyDays
		if r == good {
			days = goodDays
		}
		next.Due = now + days*day
		return
	}
	next.Step = &at
	next.Due = stepDue(now, wait, untilRollover, fuzz)
}

// stepDue is when a learning step of secs comes due: Anki adds up to 25%, at
// most five minutes, unless the step reaches the rollover, when it becomes a
// day's wait instead, due as the day starts.
func stepDue(now, secs, untilRollover int64, fuzz float64) int64 {
	if secs >= untilRollover {
		days := (secs-untilRollover)/day + 1
		return now + untilRollover + (days-1)*day
	}
	upper := secs + int64(math.Floor(math.Min(float64(secs)*0.25, 300)))
	if secs >= upper {
		return now + secs
	}
	return now + secs + int64(math.Floor(fuzz*float64(upper-secs)))
}

// scheduledDays is a review card's current interval, in days.
func scheduledDays(m memory) int64 {
	return int64(jsRound(float64(m.Due-m.Last) / day))
}

// --- fsrs4anki_scheduler.js ---

func constrainDifficulty(difficulty float64) float64 {
	return math.Min(math.Max(round2(difficulty), 1), 10)
}

// applyFuzz is apply_fuzz; floor is the review card's current interval, or -1.
func applyFuzz(ivl, fuzz float64, floor int64) float64 {
	if ivl < 2.5 {
		return ivl
	}
	ivl = jsRound(ivl)
	minIvl := math.Max(2, jsRound(ivl*0.95-1))
	maxIvl := jsRound(ivl*1.05 + 1)
	if floor >= 0 && ivl > float64(floor) {
		minIvl = math.Max(minIvl, float64(floor+1))
	}
	return math.Floor(fuzz*(maxIvl-minIvl+1) + minIvl)
}

func forgettingCurve(elapsedDays, stability float64) float64 {
	return math.Pow(1+factor*elapsedDays/stability, decay)
}

func nextInterval(stability, fuzz float64, floor int64) int64 {
	newInterval := applyFuzz(stability/factor*(math.Pow(requestRetention, 1/decay)-1), fuzz, floor)
	return int64(math.Min(math.Max(jsRound(newInterval), 1), maximumInterval))
}

func linearDamping(deltaD, oldD float64) float64 {
	return deltaD * (10 - oldD) / 9
}

func nextDifficulty(d float64, r int) float64 {
	deltaD := -w[6] * float64(r-3)
	nextD := d + linearDamping(deltaD, d)
	return constrainDifficulty(meanReversion(initDifficulty(easy), nextD))
}

func meanReversion(init, current float64) float64 {
	return w[7]*init + (1-w[7])*current
}

func nextRecallStability(d, s, ret float64, r int) float64 {
	hardPenalty, easyBonus := 1.0, 1.0
	if r == hard {
		hardPenalty = w[15]
	}
	if r == easy {
		easyBonus = w[16]
	}
	return round2(s * (1 + math.Exp(w[8])*
		(11-d)*
		math.Pow(s, -w[9])*
		(math.Exp((1-ret)*w[10])-1)*
		hardPenalty*
		easyBonus))
}

func nextForgetStability(d, s, ret float64) float64 {
	sMin := s / math.Exp(w[17]*w[18])
	return round2(math.Min(w[11]*
		math.Pow(d, -w[12])*
		(math.Pow(s+1, w[13])-1)*
		math.Exp((1-ret)*w[14]), sMin))
}

func shortTermStability(s float64, r int) float64 {
	sinc := math.Exp(w[17]*(float64(r)-3+w[18])) * math.Pow(s, -w[19])
	if r >= good {
		sinc = math.Max(sinc, 1)
	}
	return round2(s * sinc)
}

func initDifficulty(r int) float64 {
	return round2(constrainDifficulty(w[4] - math.Exp(w[5]*float64(r-1)) + 1))
}

func initStability(r int) float64 {
	return round2(math.Max(w[r-1], 0.1))
}

// round2 is JavaScript's +x.toFixed(2): the exact value, to two decimals,
// halves away from zero (BigDecimal's HALF_UP on the phone).
func round2(x float64) float64 {
	v := new(big.Float).SetPrec(256).SetFloat64(x)
	v.Mul(v, big.NewFloat(100))
	if x < 0 {
		v.Sub(v, big.NewFloat(0.5))
	} else {
		v.Add(v, big.NewFloat(0.5))
	}
	n, _ := v.Int(nil) // toward zero
	return float64(n.Int64()) / 100
}

// jsRound is JavaScript's Math.round: the nearest whole number, halves up.
func jsRound(x float64) float64 {
	t := math.Floor(x)
	if x-t >= 0.5 {
		return t + 1
	}
	return t
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
