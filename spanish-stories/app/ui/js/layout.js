.pragma library

// Lays a story's (spanish, [english...]) tokens out into pages of positioned
// text items. Pure JavaScript: text widths come from the `measure` callback,
// so the same code runs in the app and in tests.
//
// A long story is read a window at a time (ReaderView.qml), so the tokens
// given here may start anywhere in it: opts.offset is the story's index of
// tokens[0], and every token index this returns is the story's.

// Punctuation that hugs the word before it / the word after it.
var CLOSERS = ".,;:!?)]}»”’…%";
var OPENERS = "¿¡([{«“‘—";

function isWordLike(text) {
    return /[0-9A-Za-zÀ-ÿĀ-ž]/.test(text);
}

function noSpaceBefore(text) {
    return !isWordLike(text) && CLOSERS.indexOf(text.charAt(0)) >= 0;
}

function noSpaceAfter(text) {
    return !isWordLike(text) && OPENERS.indexOf(text.charAt(text.length - 1)) >= 0;
}

function isParagraphBreak(text) {
    return text === "\n" || text === "\n\n" || text === "¶";
}

// Splits tokens into paragraphs of unbreakable clusters of pieces.
// A piece is one space-free fragment of a token's Spanish text.
// restarts: local token indices where a fresh page starts, mid-paragraph
// or not (the window was extended backwards to there).
// Returns [{ clusters, indent, restart }].
function buildParagraphs(tokens, indentFirst, restarts) {
    var paragraphs = [];
    var clusters = [];
    var cluster = null;
    var glueNext = true; // start of paragraph: nothing to put a space after
    // A dash opens an aside (—dice el pollo) or, right after a word while an
    // aside is open, closes it (—dice el pollo—, el cielo...): a closing dash
    // hugs the word before it and is followed by a space. A dash after . : ;
    // (but not ...) starts a new line of dialogue, like one opening a paragraph.
    var asideOpen = false;
    var prevWord = false;
    var prevText = "";
    var next = { indent: indentFirst, restart: false };
    var restartAt = {};
    for (var r = 0; r < restarts.length; r++) restartAt[restarts[r]] = true;

    function flushParagraph() {
        if (cluster) clusters.push(cluster);
        if (clusters.length) {
            paragraphs.push({ clusters: clusters, indent: next.indent, restart: next.restart });
            next = { indent: true, restart: false };
        }
        clusters = [];
        cluster = null;
        glueNext = true;
        asideOpen = false;
        prevWord = false;
        prevText = "";
    }

    for (var i = 0; i < tokens.length; i++) {
        var es = tokens[i][0];
        var en = tokens[i][1] || [];
        if (restartAt[i]) {
            var midParagraph = clusters.length > 0 || cluster !== null;
            flushParagraph();
            next = { indent: !midParagraph && i > 0 && isParagraphBreak(tokens[i - 1][0]), restart: true };
        }
        if (isParagraphBreak(es)) {
            flushParagraph();
            continue;
        }
        var link = en.length > 0;
        var words = /\s/.test(es) ? es.split(/\s+/).filter(function (w) { return w.length > 0; }) : [es];
        var closingDash = false;
        var closesAfter = false; // "!—" in "—¡y bien vengado!— del..."
        if (!link && es.charAt(0) === "—" && cluster) {
            closingDash = asideOpen && prevWord;
            asideOpen = !closingDash && (prevWord || !/[.:;]$/.test(prevText) || /(\.\.\.|…)$/.test(prevText));
        } else if (!link && asideOpen && es.length > 1 && es.charAt(es.length - 1) === "—") {
            closesAfter = true;
            asideOpen = false;
        }
        for (var w = 0; w < words.length; w++) {
            var text = words[w];
            var glued = w === 0 ? (glueNext || noSpaceBefore(text) || closingDash) : false;
            // src: the token it comes from; first: it begins that token.
            var piece = { text: text, tok: link ? i : -1, punct: !link, src: i, first: w === 0 };
            if (glued && cluster) {
                cluster.pieces.push(piece);
            } else {
                if (cluster) clusters.push(cluster);
                cluster = { pieces: [piece], spaced: !glued };
            }
        }
        glueNext = words.length > 0 && noSpaceAfter(words[words.length - 1]);
        if ((closingDash && es === "—") || closesAfter) glueNext = false;
        if (words.length > 0) {
            prevWord = link || isWordLike(es);
            prevText = es;
        }
    }
    flushParagraph();
    return paragraphs;
}

var widths = {};
var widthsFont = null;

var cachedTokens = null;
var cachedKey = "";
var cachedParagraphs = null;

// opts: width, height, lineHeight, spaceWidth, fontKey (font and size the
//       widths from `measure` belong to),
//       indent (first line of every paragraph but the story's first),
//       firstPageTop (space reserved on page one for the title),
//       offset (story index of tokens[0]), indentFirst (tokens[0] starts a
//       paragraph that isn't the story's first), restarts (story indices
//       where a page must start afresh).
// Lines are justified like a book: every line but a paragraph's last is
// stretched to the full width by widening the spaces between words.
// Returns [{ lines, pieces, segs, firstToken, lastToken, startToken, endToken, startClean, wordsLeft }]:
//   lines:  [{x, y, text, spacing}]  what is drawn: each line as one text,
//           every space in it widened by `spacing` px
//   pieces: [{x, y, w, text, tok, punct}]  one per word or punctuation mark
//   segs:   [{x, y, w, tok}]  a phrase's run of words on one line, spaces
//           included; this is what gets the dotted underline and the tap target.
//   firstToken, lastToken: the first and last tappable token on the page.
//   startToken, endToken: the first and last token with anything on the page;
//           startClean: the page begins with the start of startToken.
//   wordsLeft: Spanish words from this page to the end of tokens.
function paginate(tokens, measure, opts) {
    var off = opts.offset || 0;
    // Widths are kept between layouts in the same font: a chunk of a book
    // arriving relays out the window, mostly words already measured.
    if (opts.fontKey !== widthsFont) {
        widths = {};
        widthsFont = opts.fontKey;
    }
    var widthCache = widths;
    function widthOf(text) {
        var w = widthCache[text];
        if (w === undefined) w = widthCache[text] = measure(text);
        return w;
    }
    function clusterText(cl) {
        var t = "";
        for (var k = 0; k < cl.pieces.length; k++) t += cl.pieces[k].text;
        return t;
    }
    // A cluster is drawn as one run of text, so it is measured as one.
    function clusterWidth(cl) {
        if (cl.width === undefined || cl.widthFont !== widthsFont) {
            cl.width = widthOf(clusterText(cl));
            cl.widthFont = widthsFont;
        }
        return cl.width;
    }

    // A cluster wider than a line ("INSULTE-A-ALBUS-DUMBLEDORE-EN-MI-PRESENCIA")
    // wraps after its hyphens, like a book.
    function breakAtHyphens(cl) {
        var parts = [];
        var part = null;
        for (var k = 0; k < cl.pieces.length; k++) {
            var piece = cl.pieces[k];
            var bits = piece.text.match(/[^-]+-+|[^-]+$|-+/g) || [piece.text];
            for (var b = 0; b < bits.length; b++) {
                var bit = { text: bits[b], tok: piece.tok, punct: piece.punct, src: piece.src, first: piece.first && b === 0 };
                if (part && b > 0) {
                    parts.push(part);
                    part = null;
                }
                if (!part) part = { pieces: [], spaced: parts.length ? false : cl.spaced };
                part.pieces.push(bit);
            }
        }
        if (part) parts.push(part);
        return parts;
    }

    // Splitting doesn't change with the font, so a relayout skips it.
    var restarts = [];
    for (var r = 0; r < (opts.restarts || []).length; r++) {
        var local = opts.restarts[r] - off;
        if (local > 0 && local < tokens.length) restarts.push(local);
    }
    var key = off + "|" + (opts.indentFirst ? 1 : 0) + "|" + restarts.join(",");
    if (tokens !== cachedTokens || key !== cachedKey) {
        cachedParagraphs = buildParagraphs(tokens, !!opts.indentFirst, restarts);
        cachedTokens = tokens;
        cachedKey = key;
    }
    var paragraphs = cachedParagraphs;
    var pages = [];
    var page = null;
    var y = 0;
    var lh = opts.lineHeight;

    function newPage() {
        page = { lines: [], pieces: [], segs: [], firstToken: -1, lastToken: -1, startToken: -1, endToken: -1,
                 startClean: true, wordsLeft: 0 };
        pages.push(page);
        y = pages.length === 1 ? (opts.firstPageTop || 0) : 0;
    }

    function placeLine(line, last) {
        if (y + lh > opts.height && page.pieces.length) newPage();
        var gaps = 0;
        for (var i = 1; i < line.entries.length; i++) if (line.entries[i].gap > 0) gaps++;
        var stretch = (!last && gaps > 0) ? (opts.width - line.end) / gaps : 0;
        var x = line.start;
        var seg = null;
        var text = "";
        for (i = 0; i < line.entries.length; i++) {
            var e = line.entries[i];
            if (e.gap > 0) {
                x += e.gap + stretch;
                text += " ";
            }
            text += clusterText(e.cl);
            // Pieces share out the cluster's width, which kerning between
            // them makes a little different from the sum of theirs.
            var sum = 0;
            for (var k = 0; k < e.cl.pieces.length; k++) sum += widthOf(e.cl.pieces[k].text);
            var scale = sum > 0 ? clusterWidth(e.cl) / sum : 1;
            for (k = 0; k < e.cl.pieces.length; k++) {
                var piece = e.cl.pieces[k];
                var w = widthOf(piece.text) * scale;
                var tok = piece.tok >= 0 ? piece.tok + off : -1;
                if (page.startToken < 0) {
                    page.startToken = piece.src + off;
                    page.startClean = piece.first;
                }
                page.endToken = piece.src + off;
                page.pieces.push({ x: x, y: y, w: w, text: piece.text, tok: tok, punct: piece.punct });
                if (tok >= 0 && !piece.punct) {
                    page.wordsLeft++;
                    if (seg && seg.tok === tok) {
                        seg.w = x + w - seg.x;
                    } else {
                        seg = { x: x, y: y, w: w, tok: tok };
                        page.segs.push(seg);
                    }
                    if (page.firstToken < 0) page.firstToken = tok;
                    page.lastToken = tok;
                } else {
                    seg = null;
                }
                x += w;
            }
        }
        // The line is drawn as one text, its spaces widened by `spacing`
        // (font.wordSpacing) to justify it.
        page.lines.push({ x: line.start, y: y, text: text, spacing: stretch });
        y += lh;
    }

    newPage();
    for (var p = 0; p < paragraphs.length; p++) {
        var para = paragraphs[p];
        if (para.restart && page.pieces.length) newPage();
        var clusters = [];
        for (var c0 = 0; c0 < para.clusters.length; c0++) {
            var cl0 = para.clusters[c0];
            if (clusterWidth(cl0) > opts.width) clusters = clusters.concat(breakAtHyphens(cl0));
            else clusters.push(cl0);
        }
        var start = para.indent ? (opts.indent || 0) : 0;
        var line = { start: start, end: start, entries: [] };
        for (var c = 0; c < clusters.length; c++) {
            var cl = clusters[c];
            var cw = clusterWidth(cl);
            var gap = (line.entries.length && cl.spaced) ? opts.spaceWidth : 0;
            if (line.entries.length && line.end + gap + cw > opts.width) {
                placeLine(line, false);
                line = { start: 0, end: 0, entries: [] };
                gap = 0;
            }
            line.entries.push({ cl: cl, gap: gap });
            line.end += gap + cw;
        }
        if (line.entries.length) placeLine(line, true);
    }

    for (var j = pages.length - 2; j >= 0; j--) pages[j].wordsLeft += pages[j + 1].wordsLeft;

    // Pages that hold only punctuation still need a token for progress.
    for (var i = 0; i < pages.length; i++) {
        if (pages[i].firstToken < 0) {
            pages[i].firstToken = i > 0 ? pages[i - 1].lastToken : off;
            pages[i].lastToken = pages[i].firstToken;
        }
        if (pages[i].startToken < 0) {
            pages[i].startToken = pages[i].endToken = i > 0 ? pages[i - 1].endToken : off;
        }
    }
    return pages;
}

// The page showing token `token` (the last one starting at or before it).
function pageForToken(pages, token) {
    for (var i = pages.length - 1; i >= 0; i--) {
        if (pages[i].startToken <= token) return i;
    }
    return 0;
}

// Finds the phrase segment under (px, py). Lines touch, so only the
// horizontal distance gets some slack, which makes short words easy to hit.
function hitTest(segs, px, py, lineHeight, slack) {
    var best = null;
    var bestDist = 1e9;
    for (var i = 0; i < segs.length; i++) {
        var s = segs[i];
        if (py < s.y || py >= s.y + lineHeight) continue;
        var dx = px < s.x ? s.x - px : (px > s.x + s.w ? px - (s.x + s.w) : 0);
        if (dx > slack) continue;
        if (dx < bestDist) {
            bestDist = dx;
            best = s;
        }
    }
    return best;
}
