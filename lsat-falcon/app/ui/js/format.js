.pragma library
.import "theme.js" as Theme

// Text formatting, ported from the web app (Prose.jsx, emphasis.js,
// quotes.js, explanation-format.js, ExplanationPane.jsx). It produces Qt
// rich text: each paragraph becomes one RichText Text item.
//
// The web app's emphasis rules use lookbehind, which Qt's JavaScript engine
// can't be relied on for. Each rule here instead captures the character
// before the opening delimiter as group 1 (the "prefix") and its contents as
// group 2, and the match starts after the prefix.

function escape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// Inside a paragraph a single newline is just a wrapped line, as in HTML.
function inline(s) {
    return escape(s).replace(/\n/g, " ");
}

// ---- paragraphs (Prose.jsx)

var LABEL_LINE = /^[ \t]*(Passage [A-Z])[ \t]*$/;
var RUN_IN_LABEL = /^(Passage [A-Z])[ \t]+(?=[A-Z“‘"(])/;

function splitLabels(block) {
    var out = [];
    var buf = [];
    function flush() {
        var text = buf.join("\n").trim();
        if (text)
            out.push(text);
        buf = [];
    }
    var lines = block.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var alone = line.match(LABEL_LINE);
        if (alone) {
            flush();
            out.push(alone[1]);
            continue;
        }
        var runIn = i === 0 ? line.match(RUN_IN_LABEL) : null;
        if (runIn) {
            out.push(runIn[1]);
            buf.push(line.slice(runIn[0].length));
            continue;
        }
        buf.push(line);
    }
    flush();
    return out;
}

// Blank-line separated paragraphs, with "Passage A" labels split out.
function paragraphsOf(text) {
    var out = [];
    var blocks = String(text || "").split(/\n{2,}/);
    for (var i = 0; i < blocks.length; i++) {
        var parts = splitLabels(blocks[i]);
        for (var j = 0; j < parts.length; j++)
            if (parts[j])
                out.push(parts[j]);
    }
    return out;
}

var LABELLED = /^([^\s:][^:\n]{0,58}):[ \t]+(?=\S)/;
var LABEL_WORD = /^(?:[A-Za-z0-9][A-Za-z0-9’'-]*|(?:Dr|Mr|Mrs|Ms|Prof|St|[A-Z])\.)$/;
var CLAUSE_WORD = /^(?:is|are|was|were|be|been|has|have|had|do|does|did|made|said|will|would|can|could|should|must|may|might|seems|means)$/;

// A stimulus paragraph opening with a speaker's label: "Columnist:".
function isSpeaker(p) {
    var m = p.match(LABELLED);
    if (!m)
        return false;
    var words = m[1].split(/[ \t]+/);
    if (words.length > 5 || !/^[A-Z0-9]/.test(words[0]))
        return false;
    for (var i = 0; i < words.length; i++)
        if (!LABEL_WORD.test(words[i]) || CLAUSE_WORD.test(words[i]))
            return false;
    return true;
}

// ---- marks: spans of a paragraph wrapped in markup

var EMPHASIS = [
    { tag: "u", pre: true, re: /(^|[^_])__(?!\s)((?:[^_]|_(?!_))*?[^\s_])__(?!_)/g },
    { tag: "b", pre: true, re: /(^|[^*])\*\*(?!\s)([\s\S]*?[^\s])\*\*(?!\*)/g },
    { tag: "s", pre: true, re: /(^|[^~])~~(?!\s)([\s\S]*?[^\s])~~(?!~)/g },
    { tag: "i", pre: true, re: /(^|[^*\w])\*(?!\s)([^*\n]*?[^\s*])\*(?![*\w])/g },
    { tag: "i", pre: true, re: /(^|[^_\w])_(?!\s)([^_\n]*?[^\s_])_(?![_\w])/g }
];

// The non-overlapping matches of `marks` in reading order; earlier marks win
// a tie. A mark may accept only some matches, by paragraph and position.
function findMarks(text, marks, para) {
    var hits = [];
    for (var rank = 0; rank < marks.length; rank++) {
        var mark = marks[rank];
        var re = mark.re;
        re.lastIndex = 0;
        var nth = 0;
        var m;
        while ((m = re.exec(text)) !== null) {
            if (!m[0].length) {
                re.lastIndex++;
                continue;
            }
            var lead = mark.pre ? m[1].length : 0;
            if (!mark.accept || mark.accept(para, nth)) {
                hits.push({
                    start: m.index + lead, end: m.index + m[0].length, rank: rank, mark: mark,
                    inner: mark.pre ? m[2] : null
                });
            }
            nth++;
        }
    }
    hits.sort(function (a, b) {
        return a.start - b.start || a.rank - b.rank || b.end - a.end;
    });
    var kept = [];
    for (var i = 0; i < hits.length; i++)
        if (!kept.length || hits[i].start >= kept[kept.length - 1].end)
            kept.push(hits[i]);
    return kept;
}

// Rich text for `text` with `marks` applied. A mark either has `tag` (a
// delimiter pair: what it held goes back through here, so emphasis nests) or
// `open`/`close` markup around the matched text.
function marked(text, marks, para) {
    var hits = findMarks(text, marks, para);
    if (!hits.length)
        return inline(text);
    var out = "";
    var at = 0;
    for (var i = 0; i < hits.length; i++) {
        var h = hits[i];
        out += inline(text.slice(at, h.start));
        if (h.mark.tag)
            out += "<" + h.mark.tag + ">" + marked(h.inner, marks, para) + "</" + h.mark.tag + ">";
        else
            out += h.mark.open(text.slice(h.start, h.end)) + inline(text.slice(h.start, h.end)) + h.mark.close;
        at = h.end;
    }
    return out + inline(text.slice(at));
}

// `md` turns on markdown emphasis: explanations use it, but a passage or
// stimulus is quoted verbatim, where an asterisk is the page's own.
function highlight(text, marks, para, md) {
    var all = (marks || []).concat(md ? EMPHASIS : []);
    if (!all.length)
        return inline(text);
    return marked(text, all, para || 0);
}

// ---- quotes (quotes.js)

function escapeRe(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

var LOOSE = [[/['‘’]/g, "['‘’]"], [/["“”]/g, "[\"“”]"], [/[-–—]/g, "[-–—]"]];

function loosePhraseRe(phrase, flags) {
    var words = phrase.trim().split(/\s+/);
    var parts = [];
    for (var i = 0; i < words.length; i++) {
        var w = escapeRe(words[i]);
        for (var k = 0; k < LOOSE.length; k++)
            w = w.replace(LOOSE[k][0], LOOSE[k][1]);
        if (w)
            parts.push(w);
    }
    return parts.length ? new RegExp(parts.join("\\s+"), flags || "") : null;
}

function trimTail(s) {
    return s.replace(/[.,;:!?]+$/, "").trim();
}

function locate(paras, quote) {
    var candidates = [quote.trim(), trimTail(quote)];
    for (var c = 0; c < candidates.length; c++) {
        if (candidates[c].length < 2)
            continue;
        var re = loosePhraseRe(candidates[c]);
        if (!re)
            continue;
        for (var p = 0; p < paras.length; p++)
            if (re.test(paras[p]))
                return candidates[c];
    }
    return null;
}

// The quotes in a stem that can be found in the passage: {raw, text}.
function passageQuotes(stem, passage) {
    if (!stem || !passage)
        return [];
    var paras = passage.split(/\n{2,}/).filter(function (p) { return p.trim(); });
    var found = [];
    var re = /[“"]([^“”"]+)[”"]/g;
    var m;
    while ((m = re.exec(stem)) !== null) {
        var dup = false;
        for (var i = 0; i < found.length; i++)
            if (found[i].raw === m[0])
                dup = true;
        if (dup)
            continue;
        var text = locate(paras, m[1]);
        if (text)
            found.push({ raw: m[0], text: text });
    }
    return found;
}

// Marks for a stem: each quote is a link ("quote:<n>") on a lavender — here
// grey — ground, a shade darker while it's the one being shown.
function quoteRefMarks(quotes, activeText) {
    var marks = [];
    for (var n = 0; n < quotes.length; n++) {
        (function (q, n) {
            var bg = q.text === activeText ? Theme.quoteStrong : Theme.quote;
            marks.push({
                re: new RegExp(escapeRe(q.raw), "g"),
                open: function () {
                    return '<a href="quote:' + n + '" style="color:' + Theme.ink + ';text-decoration:none">'
                        + '<span style="background-color:' + bg + '">';
                },
                close: "</span></a>"
            });
        })(quotes[n], n);
    }
    return marks;
}

// The passage side of a quote: one occurrence at a time, chosen by `hit`.
// Returns {marks, para, offset} where para/offset locate the mark (so the
// view can bring it into sight), or null when the phrase isn't there.
function quoteMark(paras, text, hit) {
    var re = loosePhraseRe(text, "ig");
    if (!re)
        return null;
    var counts = [], total = 0;
    for (var i = 0; i < paras.length; i++) {
        var n = (paras[i].match(re) || []).length;
        counts.push(n);
        total += n;
    }
    if (!total)
        return null;
    var nth = hit % total, para = 0;
    while (nth >= counts[para])
        nth -= counts[para++];
    var at = 0;
    re.lastIndex = 0;
    for (var k = 0; k <= nth; k++) {
        var m = re.exec(paras[para]);
        at = m.index;
    }
    return {
        para: para,
        offset: at / Math.max(1, paras[para].length),
        marks: [{
            re: loosePhraseRe(text, "ig"),
            accept: function (p, j) { return p === para && j === nth; },
            open: function () { return '<span style="background-color:' + Theme.quoteStrong + '">'; },
            close: "</span>"
        }]
    };
}

// Paragraph models for the Prose component: {kind, html, indent}.
// kind: "label" (Passage A) or "p"; indent: "passage", "speaker" or "".
function prose(text, indent, marks, md) {
    var paras = paragraphsOf(text);
    var out = [];
    for (var i = 0; i < paras.length; i++) {
        var p = paras[i];
        if (/^Passage [A-Z]$/.test(p)) {
            out.push({ kind: "label", html: escape(p), indent: "" });
            continue;
        }
        out.push({
            kind: "p",
            html: highlight(p, marks, i, md),
            indent: indent === "passage" ? "passage" : indent === "stimulus" && isSpeaker(p) ? "speaker" : ""
        });
    }
    return out;
}

// ---- explanations (ExplanationPane.jsx, explanation-format.js)

var MARKER = /^\(?([A-E])\)?[.:)]?\s+/;
var GROUP = /^([A-E])\),\s+(?:[A-E]\),\s+)*(?:and\s+)?[A-E]\)\s+/;
var GROUP_HEAD = /^[A-E]\),\s+/;

// Intro paragraphs and per-answer notes, the notes in A–E order.
function parseExplanation(explanation) {
    var paras = String(explanation || "").split(/\n{2,}/).map(function (s) { return s.trim(); })
        .filter(function (s) { return s; });
    var seen = {};
    var start = paras.length;
    for (var i = paras.length - 1; i >= 0; i--) {
        var m = paras[i].match(GROUP) || paras[i].match(MARKER);
        if (!m)
            continue;
        if (seen[m[1]])
            break;
        seen[m[1]] = true;
        start = i;
    }
    var intro = paras.slice(0, start);
    var notes = [];
    var rest = paras.slice(start);
    for (var j = 0; j < rest.length; j++) {
        var para = rest[j];
        var g = para.match(GROUP);
        var mm = g || para.match(MARKER);
        if (mm) {
            var head = g ? para.match(GROUP_HEAD)[0] : mm[0];
            notes.push({ letter: mm[1], paras: [para.slice(head.length)] });
        } else if (notes.length) {
            notes[notes.length - 1].paras.push(para);
        }
    }
    notes.sort(function (a, b) { return a.letter < b.letter ? -1 : a.letter > b.letter ? 1 : 0; });
    return { intro: intro, notes: notes };
}

var RULE = /^(?:_{3,}|-{3,})$/;
var QUOTE = /^>\s?(.*)$/;
var BULLET = /^[*-]\s+(.+)$/;
var ORDERED = /^(\d+)\.\s+(.+)$/;

function allMatch(lines, re) {
    var out = [];
    for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(re);
        if (!m)
            return null;
        out.push(m);
    }
    return out;
}

// Block structure: {type: "rule" | "paragraph" | "quote" | "list", ...}.
function explanationBlocks(paragraphs) {
    var blocks = [];
    for (var i = 0; i < paragraphs.length; i++) {
        var text = paragraphs[i].trim();
        if (!text)
            continue;
        if (RULE.test(text)) {
            blocks.push({ type: "rule" });
            continue;
        }
        var lines = text.split("\n");
        var prev = blocks[blocks.length - 1];
        var quoted = allMatch(lines, QUOTE);
        if (quoted) {
            var items = [];
            for (var q = 0; q < quoted.length; q++) {
                var item = quoted[q][1].trim();
                if (item)
                    items.push(RULE.test(item) ? { type: "rule" } : { type: "paragraph", text: item });
            }
            if (prev && prev.type === "quote")
                prev.items = prev.items.concat(items);
            else
                blocks.push({ type: "quote", items: items });
            continue;
        }
        var bullets = allMatch(lines, BULLET);
        if (bullets) {
            var bitems = bullets.map(function (m) { return m[1].trim(); });
            if (prev && prev.type === "list" && !prev.ordered)
                prev.items = prev.items.concat(bitems);
            else
                blocks.push({ type: "list", ordered: false, start: 1, items: bitems });
            continue;
        }
        var ordered = allMatch(lines, ORDERED);
        if (ordered) {
            var startN = Number(ordered[0][1]);
            var oitems = ordered.map(function (m) { return m[2].trim(); });
            if (prev && prev.type === "list" && prev.ordered && startN === prev.start + prev.items.length)
                prev.items = prev.items.concat(oitems);
            else
                blocks.push({ type: "list", ordered: true, start: startN, items: oitems });
            continue;
        }
        blocks.push({ type: "paragraph", text: text });
    }
    return blocks;
}

// Blocks with their rich text filled in, for ExplanationBlocks.qml.
function explanationModel(paragraphs) {
    var blocks = explanationBlocks(paragraphs);
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i];
        if (b.type === "paragraph") {
            b.html = highlight(b.text, [], 0, true);
        } else if (b.type === "quote") {
            for (var j = 0; j < b.items.length; j++)
                if (b.items[j].type === "paragraph")
                    b.items[j].html = highlight(b.items[j].text, [], 0, true);
        } else if (b.type === "list") {
            b.html = b.items.map(function (t) { return highlight(t, [], 0, true); });
        }
    }
    return blocks;
}
