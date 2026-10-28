import QtQuick
import "components"
import "js/theme.js" as Theme
import "js/layout.js" as Layout

// Reading screen: nothing but the text. Touch zones (see the mockup):
//   top strip      -> toolbar          bottom strip -> show/hide page number
//   left margin    -> previous page    right margin -> next page
//   a phrase       -> its translation  anything else closes the translation
//   swipe left / right anywhere turns the page.
Item {
    id: reader

    property bool active: false
    property var story: null       // {id, title, level, words, tokenCount}; the text comes from requestTokens
    property var progress: null    // {token, finished}
    property var settings: ({})
    property QtObject fonts

    signal back
    signal savePosition(int token, bool finished)
    signal markFinished
    signal resetProgress
    signal changeSetting(string key, var value)
    // {seq, from} for the tokens from `from` on, {seq, before} for the ones
    // before it, {seq, from, paragraph: true} for a jump; the reply goes to
    // receiveTokens.
    signal requestTokens(var request)

    // ---- settings
    readonly property int sizeIndex: Math.max(0, Math.min(Theme.textSizes.length - 1,
                                       settings.textSize === undefined ? Theme.defaultTextSize : settings.textSize))
    readonly property int fontSize: Theme.textSizes[sizeIndex]
    readonly property string family: settings.font === "sans" ? fonts.sans
                                   : settings.font === "atkinson" ? fonts.atkinson : fonts.serif
    readonly property bool showDots: settings.dots !== false
    readonly property bool showFooter: settings.footer === true

    // ---- geometry
    readonly property int lineHeight: Math.round(fontSize * Theme.lineFactor)
    readonly property int textWidth: Theme.screenWidth - 2 * Theme.pageLeft
    readonly property int linesPerPage: Math.floor((Theme.screenHeight - Theme.pageTop - Theme.pageBottomStrip) / lineHeight)
    // The glyph box (ascent + descent) is centred in each line, as in CSS.
    readonly property real textTop: (lineHeight - metrics.height) / 2

    // ---- the text in memory
    // Like a video player, the reader holds a window of the story: the
    // tokens around the page on screen, fetched from the backend a chunk at a
    // time ahead of the reader and dropped once far behind. A story that
    // fits in the window is held whole, from its start.
    readonly property int maxWindow: 6000     // tokens
    readonly property int aheadTokens: 1500   // keep this much past the page on screen
    property var tokens: []                   // tokens[0] is the story's token winStart
    property int winStart: 0
    readonly property int winEnd: winStart + tokens.length
    readonly property int total: story ? story.tokenCount : 0
    property bool indentFirst: false          // tokens[0] starts a paragraph
    property var restarts: []                 // where text fetched backwards meets the rest: a new page
    // Every page of the story is in the window, so page numbers are real.
    readonly property bool whole: total > 0 && total <= maxWindow && winEnd === total
    property int seq: 0
    property bool waiting: false
    property int pendingTurn: 0               // a page turn waiting for its text: +1 or -1
    property bool saveAfterLoad: false

    // ---- state
    property var pages: []
    property int pageIndex: 0
    readonly property var page: pages.length ? pages[Math.min(pageIndex, pages.length - 1)]
                                            : ({ lines: [], pieces: [], segs: [], firstToken: 0, lastToken: 0, startToken: 0, endToken: 0, wordsLeft: 0 })
    readonly property bool atEnd: pages.length > 0 && winEnd >= total && pageIndex >= pages.length - 1
    property int selectedTok: -1
    property bool toolbarOpen: false
    property bool menuOpen: false
    property bool sheetOpen: false
    property bool finished: progress ? progress.finished === true : false

    readonly property int percent: {
        if (!pages.length || !total)
            return 0;
        if (atEnd)
            return 100;
        return Math.round(page.startToken / total * 100);
    }
    readonly property int minutesLeft: {
        var words = whole ? page.wordsLeft : (story ? story.words * (total - page.startToken) / total : 0);
        return Math.ceil(words / Theme.wordsPerMinute);
    }

    function token(i) {
        return tokens[i - winStart];
    }

    FontMetrics {
        id: metrics
        font.family: reader.family
        font.pixelSize: reader.fontSize
    }
    FontMetrics {
        id: titleMetrics
        font.family: reader.family
        font.pixelSize: titleText.font.pixelSize
    }

    // ---- loading
    function fetch(request) {
        seq++;
        request.seq = seq;
        waiting = true;
        requestTokens(request);
    }

    // The tokens from the window's start (for a story held whole) or from the
    // saved page on.
    onStoryChanged: {
        selectedTok = -1;
        toolbarOpen = menuOpen = sheetOpen = false;
        finished = progress ? progress.finished === true : false;
        tokens = [];
        restarts = [];
        pages = [];
        pageIndex = 0;
        pendingTurn = 0;
        saveAfterLoad = false;
        waiting = false;
        if (!story)
            return;
        // Not `total`: its binding may not have caught up with the new story
        // yet, and a stale 0 put every story back at its start.
        var count = story.tokenCount;
        var at = progress ? Math.max(0, Math.min(progress.token, count - 1)) : 0;
        anchorToken = at;
        winStart = count <= maxWindow ? 0 : at;
        fetch({ from: winStart });
    }

    // A chunk from the backend: {seq, from, tokens, atParagraph}.
    function receiveTokens(chunk) {
        if (!story || chunk.seq !== seq)
            return;
        waiting = false;
        var got = chunk.tokens;
        var appended = false;
        if (!tokens.length) {
            winStart = chunk.from;
            indentFirst = chunk.atParagraph;
            restarts = [];
            tokens = got;
        } else if (chunk.from === winEnd && got.length) {
            tokens = tokens.concat(got);
            appended = true;
        }
        if (total <= maxWindow && winEnd < total) {
            fetch({ from: winEnd });  // a short story is laid out once, whole
            return;
        } else if (chunk.from + got.length === winStart && got.length) {
            // Fetched backwards: the text that was the window's start keeps
            // its pages, so it starts a new one.
            var keepTo = Math.max(chunk.from + maxWindow, page.endToken + aheadTokens);
            restarts = [winStart].concat(restarts).filter(function (r) { return r < keepTo; });
            tokens = got.concat(tokens.slice(0, Math.max(0, keepTo - winStart)));
            winStart = chunk.from;
            indentFirst = chunk.atParagraph;
        }
        if (appended && pages.length)
            extendLayout();
        else
            relayout();
        dropBehind();
        if (pendingTurn !== 0) {
            var turn = pendingTurn;
            pendingTurn = 0;
            goTo(pageIndex + turn);
        } else if (saveAfterLoad && pages.length) {
            saveAfterLoad = false;
            pageShown();
        }
        fill();
    }

    // Keeps the next chunk loaded, and the previous one when there's room.
    function fill() {
        if (waiting || !story || !pages.length)
            return;
        if (winEnd < total && (total <= maxWindow || winEnd - page.endToken < aheadTokens))
            fetch({ from: winEnd });
        else if (winStart > 0 && pageIndex < 3 && tokens.length + aheadTokens <= maxWindow)
            fetch({ before: winStart });
    }

    // Past maxWindow, forgets the pages well behind the one on screen. The
    // window then starts at a page that begins a token, where a layout from
    // there makes the same pages.
    function dropBehind() {
        if (tokens.length <= maxWindow)
            return;
        var cut = -1;
        for (var i = 0; i < pageIndex - 2; i++) {
            if (pages[i].startClean && winEnd - pages[i].startToken <= maxWindow) {
                cut = i;
                break;
            }
        }
        if (cut <= 0)
            return;
        var s = pages[cut].startToken;
        indentFirst = Layout.isParagraphBreak(tokens[s - winStart - 1][0]);
        restarts = restarts.filter(function (r) { return r > s; });
        tokens = tokens.slice(s - winStart);
        winStart = s;
        pages = pages.slice(cut);
        pageIndex -= cut;
    }

    // Starts afresh at token `at` (moved back to its paragraph's start).
    function jumpTo(at, save) {
        selectedTok = -1;
        if (whole) {
            goTo(Layout.pageForToken(pages, at));
            return;
        }
        tokens = [];
        restarts = [];
        pages = [];
        pageIndex = 0;
        pendingTurn = 0;
        anchorToken = at;
        saveAfterLoad = save;
        fetch({ from: at, paragraph: true });
    }

    // ---- layout
    // The word the page turned to began with. A re-flow (another font or
    // size, more text) keeps it on screen, rather than the re-flowed page's
    // first word, which would creep back a little with every change.
    property int anchorToken: 0
    function keepAnchor() {
        if (pages.length && (anchorToken < page.startToken || anchorToken > page.endToken))
            anchorToken = page.startToken;
    }
    function scheduleLayout(token) {
        anchorToken = token;
        Qt.callLater(function () {
            relayout();
            fill();
        });
    }
    function currentToken() {
        keepAnchor();
        return anchorToken;
    }
    function relayout() {
        if (!active || !story || !tokens.length) {
            pages = [];
            return;
        }
        keepAnchor();
        titleText.forceLayout();
        setPages(paginate(tokens, winStart, indentFirst, winStart === 0 ? titleBlock.height : 0));
        dropShortStart();
    }
    // Text fetched backwards is laid out back from where it meets the rest
    // (layout.js), so only the window's first page can be short. Unless it is
    // on screen, it goes, and comes back with the next chunk fetched before
    // it, whole.
    function dropShortStart() {
        if (winStart <= 0 || pageIndex < 1 || pages.length < 2 || !restarts.length
                || pages[0].lines.length >= linesPerPage || !pages[1].startClean)
            return;
        var s = pages[1].startToken;
        indentFirst = Layout.isParagraphBreak(tokens[s - winStart - 1][0]);
        restarts = restarts.filter(function (r) { return r > s; });
        tokens = tokens.slice(s - winStart);
        winStart = s;
        pages = pages.slice(1);
        pageIndex -= 1;
    }
    // After text arrives at the window's end only its last pages can change,
    // so the layout starts again from the last page but one (if it begins a
    // token: then a layout from there makes the same pages, as in
    // dropBehind) rather than from the window's start: laying out the whole
    // window took seconds on the tablet, every few pages.
    function extendLayout() {
        if (!active) {
            relayout();
            return;
        }
        var k = pages.length - 2;
        while (k > 0 && !pages[k].startClean)
            k--;
        if (k <= 0) {
            relayout();
            return;
        }
        keepAnchor();
        var s = pages[k].startToken;
        var tail = paginate(tokens.slice(s - winStart), s, Layout.isParagraphBreak(token(s - 1)[0]), 0);
        setPages(pages.slice(0, k).concat(tail));
    }
    function paginate(toks, offset, indentFirst, firstPageTop) {
        return Layout.paginate(toks, function (t) { return metrics.advanceWidth(t); }, {
            fontKey: family + "|" + fontSize,
            width: textWidth,
            height: linesPerPage * lineHeight,
            lineHeight: lineHeight,
            spaceWidth: metrics.advanceWidth(" "),
            indent: Math.round(Theme.indentEm * fontSize),
            firstPageTop: firstPageTop,
            offset: offset,
            indentFirst: indentFirst,
            restarts: restarts
        });
    }
    function setPages(p) {
        var most = dotSlots;
        for (var i = 0; i < p.length; i++)
            most = Math.max(most, p[i].segs.length);
        dotSlots = most;
        pages = p;
        pageIndex = Layout.pageForToken(p, anchorToken);
    }
    // The page's items are made once and reused, page after page: making
    // hundreds of them on every turn was most of a page turn's time on the
    // tablet. Lines are one text each; the dots are one image per phrase.
    property int dotSlots: 0
    readonly property var selectedSegs: page.segs.filter(function (s) { return s.tok === selectedTok; })
    readonly property var selectedPieces: page.pieces.filter(function (p) { return !p.punct && p.tok === selectedTok; })

    onActiveChanged: scheduleLayout(currentToken())
    onFontSizeChanged: scheduleLayout(currentToken())
    onFamilyChanged: scheduleLayout(currentToken())

    function goTo(index) {
        if (!pages.length)
            return;
        selectedTok = -1;
        // The window's last page may still be missing text, unless it's the story's.
        var last = winEnd >= total ? pages.length - 1 : Math.max(0, pages.length - 2);
        if (index > last) {
            if (winEnd < total) {
                pendingTurn = 1;
                if (!waiting)
                    fetch({ from: winEnd });
            }
            index = last;
        } else if (index < 0) {
            if (winStart > 0) {
                pendingTurn = -1;
                if (!waiting)
                    fetch({ before: winStart });
            }
            index = 0;
        }
        if (index === pageIndex)
            return;
        pageIndex = index;
        pageShown();
        dropBehind();
        fill();
    }

    function pageShown() {
        anchorToken = page.startToken;
        if (atEnd)
            finished = true;
        savePosition(page.startToken, atEnd);
    }

    function segAt(x, y) {
        return Layout.hitTest(page.segs, x - textArea.x, y - textArea.y, lineHeight, 14);
    }

    function tapAt(x, y) {
        if (selectedTok >= 0) {
            var other = segAt(x, y);
            selectedTok = other && other.tok !== selectedTok ? other.tok : -1;
            return;
        }
        // A word wins over the toolbar strip: after page 1 the first line of
        // text sits inside it, so only a tap that misses every word there
        // opens the toolbar.
        var hit = x >= Theme.pageLeft && x < Theme.screenWidth - Theme.pageLeft ? segAt(x, y) : null;
        if (hit) {
            selectedTok = hit.tok;
        } else if (y < Theme.topStrip) {
            toolbarOpen = true;
        } else if (y >= Theme.screenHeight - Theme.pageBottomStrip) {
            changeSetting("footer", !showFooter);
        } else if (x < Theme.pageLeft) {
            goTo(pageIndex - 1);
        } else if (x >= Theme.screenWidth - Theme.pageLeft) {
            goTo(pageIndex + 1);
        }
    }

    // The highlighted phrase in screen pixels (its first line, if it wraps).
    readonly property var selectedRect: {
        for (var i = 0; i < page.segs.length; i++) {
            var s = page.segs[i];
            if (s.tok === selectedTok)
                return { x: textArea.x + s.x - 6, y: textArea.y + s.y + textTop - 2,
                         width: s.w + 12, height: metrics.height + 10 };
        }
        return null;
    }

    // ---- the page
    Rectangle {
        anchors.fill: parent
        color: Theme.paper
    }

    Item {
        id: textArea
        objectName: "textArea"
        x: Theme.pageLeft
        y: Theme.pageTop
        width: reader.textWidth
        height: reader.linesPerPage * reader.lineHeight

        // Title: centred, on a block two body lines tall, first page only.
        Item {
            id: titleBlock
            objectName: "titleBlock"
            width: parent.width
            height: (Math.max(1, titleText.lineCount) + 1) * reader.lineHeight
            visible: reader.pageIndex === 0 && reader.winStart === 0
            Text {
                id: titleText
                y: (reader.lineHeight - titleMetrics.height) / 2
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                lineHeightMode: Text.FixedHeight
                lineHeight: reader.lineHeight
                text: reader.story ? reader.story.title : ""
                color: Theme.ink
                font.family: reader.family
                font.pixelSize: Math.round(reader.fontSize * 1.55)
            }
        }

        Repeater {
            model: reader.dotSlots
            delegate: Image {
                readonly property var seg: index < reader.page.segs.length ? reader.page.segs[index] : null
                visible: seg !== null && reader.showDots && seg.tok !== reader.selectedTok
                // Whole dots only: the tile is 10 px with its dot in the middle.
                x: seg ? seg.x : 0
                y: (seg ? seg.y : 0) + reader.textTop + metrics.height + 3
                width: seg ? Math.max(1, Math.round(seg.w / 10)) * 10 - 2 : 0
                height: 8
                source: "images/dots.png"
                fillMode: Image.TileHorizontally
                horizontalAlignment: Image.AlignLeft
            }
        }

        Repeater {
            model: reader.linesPerPage
            delegate: Text {
                readonly property var line: index < reader.page.lines.length ? reader.page.lines[index] : null
                visible: line !== null
                x: line ? line.x : 0
                y: (line ? line.y : 0) + reader.textTop
                text: line ? line.text : ""
                textFormat: Text.PlainText
                color: Theme.ink
                font.family: reader.family
                font.pixelSize: reader.fontSize
                font.wordSpacing: line ? line.spacing : 0
            }
        }

        // The tapped phrase: white on black.
        Repeater {
            model: reader.selectedSegs
            delegate: Rectangle {
                x: modelData.x - 6
                y: modelData.y + reader.textTop - 2
                width: modelData.w + 12
                height: metrics.height + 10
                color: Theme.ink
            }
        }
        Repeater {
            model: reader.selectedPieces
            delegate: Text {
                x: modelData.x
                y: modelData.y + reader.textTop
                text: modelData.text
                textFormat: Text.PlainText
                color: Theme.white
                font.family: reader.family
                font.pixelSize: reader.fontSize
            }
        }
    }

    // Page number (tap the bottom strip); stays on or off between sessions.
    Item {
        visible: reader.showFooter && !reader.toolbarOpen
        x: Theme.pageLeft
        y: Theme.screenHeight - 17 - 30
        width: reader.textWidth
        height: 30
        Text {
            objectName: "footerPage"
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            visible: reader.whole
            text: "Pág. " + (reader.pageIndex + 1) + " de " + reader.pages.length
            color: Theme.ink2
            font.family: reader.fonts.sansSemi
            font.weight: Font.DemiBold
            font.pixelSize: 30
        }
        Text {
            anchors.right: parent.right
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: reader.percent + "%"
            color: Theme.ink2
            font.family: reader.fonts.sansSemi
            font.weight: Font.DemiBold
            font.pixelSize: 30
        }
    }

    MouseArea {
        id: touch
        objectName: "pageTouch"
        anchors.fill: parent
        property real startX: 0
        property real startY: 0
        onPressed: mouse => {
            startX = mouse.x;
            startY = mouse.y;
        }
        onReleased: mouse => {
            var dx = mouse.x - startX;
            var dy = mouse.y - startY;
            if (Math.abs(dx) > 110 && Math.abs(dx) > Math.abs(dy)) {
                reader.selectedTok = -1;
                reader.goTo(reader.pageIndex + (dx < 0 ? 1 : -1));
            } else {
                reader.tapAt(mouse.x, mouse.y);
            }
        }
    }

    Popover {
        id: popover
        objectName: "popover"
        visible: reader.selectedRect !== null
        anchorRect: reader.selectedRect || ({ x: 0, y: 0, width: 0, height: 0 })
        translations: reader.selectedTok >= 0 && reader.token(reader.selectedTok) ? reader.token(reader.selectedTok)[1] : []
        fonts: reader.fonts
    }

    // ---- toolbar, ⋮ menu and Aa sheet
    Item {
        anchors.fill: parent
        visible: reader.toolbarOpen

        // Tapping the page outside the bars hides them.
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (reader.menuOpen)
                    reader.menuOpen = false;
                else
                    reader.toolbarOpen = false;
            }
        }
        ReaderTopBar {
            objectName: "toolbar"
            title: reader.story ? reader.story.title : ""
            level: reader.story && reader.story.level ? reader.story.level : ""
            fonts: reader.fonts
            onBack: reader.back()
            onTextSettings: {
                reader.toolbarOpen = reader.menuOpen = false;
                reader.sheetOpen = true;
            }
            onMenu: reader.menuOpen = !reader.menuOpen
            onHide: reader.toolbarOpen = reader.menuOpen = false
        }
        ReaderBottomBar {
            objectName: "bottomBar"
            y: parent.height - height
            pageIndex: reader.pageIndex
            pageCount: reader.whole ? Math.max(1, reader.pages.length) : 0
            minutesLeft: reader.minutesLeft
            percent: reader.percent
            fonts: reader.fonts
            onSeek: index => reader.goTo(index)
            onSeekPercent: p => reader.jumpTo(Math.min(reader.total - 1, Math.round(p / 100 * reader.total)), true)
        }
        // Clicks between the menu and the bars close the menu.
        MouseArea {
            anchors.fill: parent
            visible: reader.menuOpen
            onClicked: reader.menuOpen = false
        }
        MenuBox {
            objectName: "readerMenu"
            visible: reader.menuOpen
            x: parent.width - 11 - width
            y: 236
            fonts: reader.fonts
            model: [
                { key: "start", label: "Ir al principio" },
                { key: "read", label: "Marcar como leído" },
                { key: "reset", label: "Reiniciar progreso" }
            ]
            onTriggered: key => {
                reader.menuOpen = reader.toolbarOpen = false;
                if (key === "start") {
                    reader.jumpTo(0, true);
                } else if (key === "read") {
                    reader.finished = true;
                    reader.markFinished();
                } else if (key === "reset") {
                    reader.finished = false;
                    reader.resetProgress();
                    if (reader.whole) {
                        reader.selectedTok = -1;
                        reader.pageIndex = 0;
                        reader.anchorToken = 0;
                    } else {
                        reader.jumpTo(0, false);
                    }
                }
            }
        }
    }

    TextSheet {
        visible: reader.sheetOpen
        settings: reader.settings
        fonts: reader.fonts
        onChangeSetting: (key, value) => reader.changeSetting(key, value)
        onDismissed: reader.sheetOpen = false
    }
}
