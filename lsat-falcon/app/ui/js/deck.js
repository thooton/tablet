.pragma library
.import "theme.js" as Theme

// The question deck: the index the backend sends at startup (build/data/
// meta.json), and the web app's logic over it — filters, shuffling, the
// summaries the settings panel shows, question keys and scoring
// (src/data.js, filters.js, question-url.js, scoring.js).
//
// Questions are referred to by their index everywhere. The text of a
// question is fetched from the backend when it's shown.

var SEP = "::";

var questions = [];   // {i, test, section, number, difficulty, cat, group, correct, experimental}
var groups = [];      // {i, isRC, number, qs: [question index]}
var categories = [];  // {section, group, type, subtype, path, label}
var tests = [];       // [{key, test, label, heldOut, sections: [{key, label, section, experimental, qs}]}]
var exams = [];
var conversions = {};
var heldOutTests = {};
var testLabels = {};
var deckTitle = "";
var ready = false;

function load(meta) {
    categories = meta.categories;
    conversions = meta.conversions || {};
    deckTitle = meta.deckTitle || "";
    heldOutTests = {};
    for (var h = 0; h < meta.heldOut.length; h++)
        heldOutTests[meta.heldOut[h]] = true;

    questions = new Array(meta.q.length);
    for (var i = 0; i < meta.q.length; i++) {
        var r = meta.q[i];
        questions[i] = {
            i: i, test: r[0], section: r[1], number: r[2], difficulty: r[3],
            cat: r[4], group: r[5], correct: r[6], experimental: r[7] === 1
        };
    }
    groups = new Array(meta.groups.length);
    for (var g = 0; g < meta.groups.length; g++) {
        var row = meta.groups[g];
        groups[g] = { i: g, isRC: row[0] === 1, number: row[1], qs: row[2] };
    }
    tests = meta.tests;
    exams = meta.exams;
    testLabels = {};
    for (var t = 0; t < tests.length; t++)
        if (tests[t].test !== null)
            testLabels[tests[t].test] = tests[t].label;
    ready = true;
}

function isHeldOut(test) {
    return heldOutTests[test] === true;
}

function category(i) {
    return categories[questions[i].cat];
}

function label(i) {
    return category(i).label;
}

function groupOf(i) {
    return groups[questions[i].group];
}

function isRC(i) {
    return groupOf(i).isRC;
}

// The app's name stands in for a test label: meta.json's deck title is a
// count ("6461 Questions") that matches nothing on screen.
var appTitle = "LSAT Falcon";

function titleFor(i) {
    var q = questions[i];
    if (!q || q.test === null)
        return appTitle;
    return testLabels[q.test] || ("Test " + q.test);
}

// ---- filters (src/filters.js)

function typeKey(cat) {
    return cat && cat.section && cat.type ? cat.section + SEP + cat.type : null;
}

// The type chips: LR types under their open/closed groups, then RC's.
var TYPE_FILTERS = (function () {
    var out = [];
    for (var code in Theme.TAXONOMY) {
        var section = Theme.TAXONOMY[code];
        for (var groupName in section.groups) {
            var types = section.groups[groupName];
            for (var k = 0; k < types.length; k++) {
                out.push({
                    key: code + SEP + types[k],
                    label: types[k],
                    group: groupName === "Question" ? section.label : section.label + " | " + groupName
                });
            }
        }
    }
    return out;
})();

var TYPE_GROUPS = (function () {
    var out = [];
    for (var i = 0; i < TYPE_FILTERS.length; i++) {
        var item = TYPE_FILTERS[i];
        var last = out[out.length - 1];
        if (last && last.label === item.group)
            last.items.push(item);
        else
            out.push({ label: item.group, items: [item] });
    }
    return out;
})();

var SECTION_FILTERS = (function () {
    var out = [];
    for (var code in Theme.TAXONOMY)
        out.push({ code: code, label: Theme.TAXONOMY[code].label });
    return out;
})();

// f: {sections, types, levels, tests} as arrays, heldOut: bool. Empty arrays
// mean everything in that dimension.
function applyFilters(f) {
    var sections = toSet(f.sections), types = toSet(f.types), levels = toSet(f.levels), testSet = toSet(f.tests);
    var out = [];
    for (var i = 0; i < questions.length; i++) {
        var q = questions[i];
        var cat = categories[q.cat];
        if (!f.heldOut && isHeldOut(q.test))
            continue;
        if (f.sections.length && !sections[cat.section])
            continue;
        if (f.types.length && !types[typeKey(cat)])
            continue;
        if (f.levels.length && !levels[q.difficulty])
            continue;
        if (f.tests.length && !testSet[q.test])
            continue;
        out.push(i);
    }
    return out;
}

function toSet(list) {
    var s = {};
    for (var i = 0; i < list.length; i++)
        s[list[i]] = true;
    return s;
}

function poolSize(heldOut) {
    if (heldOut)
        return questions.length;
    var n = 0;
    for (var i = 0; i < questions.length; i++)
        if (!isHeldOut(questions[i].test))
            n++;
    return n;
}

// Deterministic PRNG, so changing a filter doesn't reshuffle the deck.
function mulberry32(seed) {
    var a = seed >>> 0;
    return function () {
        a = (a + 0x6d2b79f5) >>> 0;
        var t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

// Passage groups shuffle as one unit, so siblings are never split up.
function shuffleDeck(list, seed) {
    var rand = mulberry32(seed);
    var blocks = [];
    var byGroup = {};
    for (var i = 0; i < list.length; i++) {
        var g = questions[list[i]].group;
        var block = byGroup[g];
        if (!block) {
            block = byGroup[g] = [];
            blocks.push(block);
        }
        block.push(list[i]);
    }
    for (var j = blocks.length - 1; j > 0; j--) {
        var k = Math.floor(rand() * (j + 1));
        var tmp = blocks[j];
        blocks[j] = blocks[k];
        blocks[k] = tmp;
    }
    var out = [];
    for (var b = 0; b < blocks.length; b++)
        for (var c = 0; c < blocks[b].length; c++)
            out.push(blocks[b][c]);
    return out;
}

// "Any", or the numbers with consecutive runs collapsed: "108-109, 113".
function summarizeTests(selected) {
    var nums = selected.filter(function (v) { return v !== null; }).sort(function (a, b) { return a - b; });
    if (!nums.length)
        return selected.length ? "—" : "Any";
    var parts = [];
    var start = nums[0], prev = nums[0];
    for (var i = 1; i < nums.length; i++) {
        if (nums[i] === prev + 1) {
            prev = nums[i];
        } else {
            parts.push(start === prev ? "" + start : start + "-" + prev);
            start = prev = nums[i];
        }
    }
    parts.push(start === prev ? "" + start : start + "-" + prev);
    if (nums.length < selected.length)
        parts.push("—");
    return parts.join(", ");
}

function summarizeTypes(selected) {
    if (!selected.length)
        return "Any";
    var set = toSet(selected);
    var seen = {}, labels = [];
    for (var i = 0; i < TYPE_FILTERS.length; i++) {
        var t = TYPE_FILTERS[i];
        if (set[t.key] && !seen[t.label]) {
            seen[t.label] = true;
            labels.push(t.label);
        }
    }
    return labels.join(", ");
}

// ---- where you are (src/question-url.js): PT<test>-S<section>-Q<number>,
// with -P while the passage is up. Questions without coordinates fall back
// to their index.

function questionKey(i) {
    var q = questions[i];
    if (!q)
        return "";
    if (q.test > 0 && q.section > 0 && q.number > 0)
        return "PT" + q.test + "-S" + q.section + "-Q" + q.number;
    return "I" + i;
}

function passageKey(i) {
    return questionKey(groupOf(i).qs[0]) + "-P";
}

// -> {i, passage} or null
function positionFromKey(value) {
    if (!value)
        return null;
    var passage = /-P$/.test(value);
    var base = passage ? value.slice(0, -2) : value;
    var m = base.match(/^I(\d+)$/);
    if (m) {
        var n = Number(m[1]);
        return n < questions.length ? { i: n, passage: passage } : null;
    }
    for (var i = 0; i < questions.length; i++)
        if (questionKey(i) === base)
            return { i: i, passage: passage };
    return null;
}

// ---- scoring (src/scoring.js)

var CURVE = [100.876, 150.182, -169.698, 99.342];

function clampScore(s) {
    return Math.min(180, Math.max(120, Math.round(s)));
}

function curveScore(fraction) {
    var p = Math.min(1, Math.max(0, fraction));
    var sum = 0;
    for (var i = 0; i < CURVE.length; i++)
        sum += CURVE[i] * Math.pow(p, i);
    return clampScore(sum);
}

function scaledScore(test, correct, total) {
    if (!total)
        return { score: 120, basis: "curve" };
    var table = conversions[test];
    var fraction = Math.min(1, Math.max(0, correct / total));
    if (!table)
        return { score: curveScore(fraction), basis: "curve" };
    var count = table.length - 1;
    if (total === count)
        return { score: table[correct], basis: "chart" };
    return { score: table[Math.round(fraction * count)], basis: "scaled" };
}
