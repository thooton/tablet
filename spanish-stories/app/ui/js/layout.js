.pragma library

// Lays a story's (spanish, [english...]) tokens out into pages of positioned
// text items. Pure JavaScript: text widths come from the `measure` callback,
// so the same code runs in the app and in tests.

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
function buildParagraphs(tokens) {
    var paragraphs = [];
    var clusters = [];
    var cluster = null;
    var glueNext = true; // start of paragraph: nothing to put a space after

    function flushParagraph() {
        if (cluster) clusters.push(cluster);
        if (clusters.length) paragraphs.push(clusters);
        clusters = [];
        cluster = null;
        glueNext = true;
    }

    for (var i = 0; i < tokens.length; i++) {
        var es = tokens[i][0];
        var en = tokens[i][1] || [];
        if (isParagraphBreak(es)) {
            flushParagraph();
            continue;
        }
        var link = en.length > 0;
        var words = es.split(/\s+/).filter(function (w) { return w.length > 0; });
        for (var w = 0; w < words.length; w++) {
            var text = words[w];
            var glued = w === 0 ? (glueNext || noSpaceBefore(text)) : false;
            var piece = { text: text, tok: link ? i : -1, punct: !link };
            if (glued && cluster) {
                cluster.pieces.push(piece);
            } else {
                if (cluster) clusters.push(cluster);
                cluster = { pieces: [piece], spaced: !glued };
            }
        }
        glueNext = words.length > 0 && noSpaceAfter(words[words.length - 1]);
    }
    flushParagraph();
    return paragraphs;
}

// opts: width, height, lineHeight, spaceWidth,
//       indent (first line of every paragraph but the story's first),
//       firstPageTop (space reserved on page one for the title).
// Lines are justified like a book: every line but a paragraph's last is
// stretched to the full width by widening the spaces between words.
// Returns [{ pieces, segs, firstToken, lastToken }]:
//   pieces: [{x, y, w, text, tok, punct}]  one per word or punctuation mark
//   segs:   [{x, y, w, tok}]  a phrase's run of words on one line, spaces
//           included; this is what gets the dotted underline and the tap target.
function paginate(tokens, measure, opts) {
    var widthCache = {};
    function widthOf(text) {
        if (!(text in widthCache)) widthCache[text] = measure(text);
        return widthCache[text];
    }
    function clusterWidth(cl) {
        var w = 0;
        for (var k = 0; k < cl.pieces.length; k++) w += widthOf(cl.pieces[k].text);
        return w;
    }

    var paragraphs = buildParagraphs(tokens);
    var pages = [];
    var page = null;
    var y = 0;
    var lh = opts.lineHeight;

    function newPage() {
        page = { pieces: [], segs: [], firstToken: -1, lastToken: -1 };
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
        for (i = 0; i < line.entries.length; i++) {
            var e = line.entries[i];
            if (e.gap > 0) x += e.gap + stretch;
            for (var k = 0; k < e.cl.pieces.length; k++) {
                var piece = e.cl.pieces[k];
                var w = widthOf(piece.text);
                page.pieces.push({ x: x, y: y, w: w, text: piece.text, tok: piece.tok, punct: piece.punct });
                if (piece.tok >= 0 && !piece.punct) {
                    if (seg && seg.tok === piece.tok) {
                        seg.w = x + w - seg.x;
                    } else {
                        seg = { x: x, y: y, w: w, tok: piece.tok };
                        page.segs.push(seg);
                    }
                    if (page.firstToken < 0) page.firstToken = piece.tok;
                    page.lastToken = piece.tok;
                } else {
                    seg = null;
                }
                x += w;
            }
        }
        y += lh;
    }

    newPage();
    for (var p = 0; p < paragraphs.length; p++) {
        var clusters = paragraphs[p];
        var start = p > 0 ? (opts.indent || 0) : 0;
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

    // Pages that hold only punctuation still need a token for progress.
    for (var i = 0; i < pages.length; i++) {
        if (pages[i].firstToken < 0) {
            pages[i].firstToken = i > 0 ? pages[i - 1].lastToken : 0;
            pages[i].lastToken = pages[i].firstToken;
        }
    }
    return pages;
}

function pageForToken(pages, token) {
    for (var i = pages.length - 1; i >= 0; i--) {
        if (pages[i].firstToken <= token) return i;
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

// Number of Spanish words in tokens[from..], for the time-left estimate.
function wordsFrom(tokens, from) {
    var n = 0;
    for (var i = Math.max(0, from); i < tokens.length; i++) {
        var en = tokens[i][1];
        if (en && en.length) n += tokens[i][0].split(/\s+/).filter(function (w) { return w.length > 0; }).length;
    }
    return n;
}
