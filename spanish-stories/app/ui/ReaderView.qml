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
    property var story: null       // {id, title, level, tokens: [[es, [en...]]]}
    property var progress: null    // {token, finished}
    property var settings: ({})
    property QtObject fonts

    signal back
    signal savePosition(int token, bool finished)
    signal markFinished
    signal resetProgress
    signal changeSetting(string key, var value)

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

    // ---- state
    property var pages: []
    property int pageIndex: 0
    readonly property var page: pages.length ? pages[Math.min(pageIndex, pages.length - 1)]
                                            : ({ pieces: [], segs: [], firstToken: 0, lastToken: 0 })
    readonly property var tokens: story ? story.tokens : []
    property int selectedTok: -1
    property bool toolbarOpen: false
    property bool menuOpen: false
    property bool sheetOpen: false
    property bool finished: progress ? progress.finished === true : false

    readonly property int percent: {
        if (!pages.length || !tokens.length)
            return 0;
        if (pageIndex >= pages.length - 1)
            return 100;
        return Math.round(page.firstToken / tokens.length * 100);
    }
    readonly property int minutesLeft: Math.ceil(Layout.wordsFrom(tokens, page.firstToken) / Theme.wordsPerMinute)

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

    // ---- layout
    property int anchorToken: 0
    function scheduleLayout(token) {
        anchorToken = token;
        Qt.callLater(relayout);
    }
    function currentToken() {
        return pages.length ? page.firstToken : (progress ? progress.token : 0);
    }
    function relayout() {
        if (!active || !story) {
            pages = [];
            return;
        }
        titleText.forceLayout();
        var p = Layout.paginate(story.tokens, function (t) { return metrics.advanceWidth(t); }, {
            width: textWidth,
            height: linesPerPage * lineHeight,
            lineHeight: lineHeight,
            spaceWidth: metrics.advanceWidth(" "),
            indent: Math.round(Theme.indentEm * fontSize),
            firstPageTop: titleBlock.height
        });
        pages = p;
        pageIndex = Layout.pageForToken(p, anchorToken);
    }

    onStoryChanged: {
        selectedTok = -1;
        toolbarOpen = menuOpen = sheetOpen = false;
        finished = progress ? progress.finished === true : false;
        scheduleLayout(progress ? progress.token : 0);
    }
    onActiveChanged: scheduleLayout(currentToken())
    onFontSizeChanged: scheduleLayout(currentToken())
    onFamilyChanged: scheduleLayout(currentToken())

    function goTo(index) {
        if (!pages.length)
            return;
        index = Math.max(0, Math.min(pages.length - 1, index));
        selectedTok = -1;
        if (index === pageIndex)
            return;
        pageIndex = index;
        var last = index === pages.length - 1;
        if (last)
            finished = true;
        savePosition(pages[index].firstToken, last);
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
        if (y < Theme.topStrip) {
            toolbarOpen = true;
        } else if (y >= Theme.screenHeight - Theme.pageBottomStrip) {
            changeSetting("footer", !showFooter);
        } else if (x < Theme.pageLeft) {
            goTo(pageIndex - 1);
        } else if (x >= Theme.screenWidth - Theme.pageLeft) {
            goTo(pageIndex + 1);
        } else {
            var hit = segAt(x, y);
            if (hit)
                selectedTok = hit.tok;
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
            visible: reader.pageIndex === 0
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

        // Highlight and dotted underline, one per phrase segment.
        Repeater {
            model: reader.page.segs
            delegate: Item {
                readonly property bool selected: modelData.tok === reader.selectedTok
                Rectangle {
                    visible: parent.selected
                    x: modelData.x - 6
                    y: modelData.y + reader.textTop - 2
                    width: modelData.w + 12
                    height: metrics.height + 10
                    color: Theme.ink
                }
                Image {
                    visible: reader.showDots && !parent.selected
                    // Whole dots only: the tile is 10 px with its dot in the middle.
                    x: modelData.x
                    y: modelData.y + reader.textTop + metrics.height + 3
                    width: Math.max(1, Math.round(modelData.w / 10)) * 10 - 2
                    height: 8
                    source: "images/dots.png"
                    fillMode: Image.TileHorizontally
                    horizontalAlignment: Image.AlignLeft
                }
            }
        }

        Repeater {
            model: reader.page.pieces
            delegate: Text {
                x: modelData.x
                y: modelData.y + reader.textTop
                text: modelData.text
                color: !modelData.punct && modelData.tok === reader.selectedTok ? Theme.white : Theme.ink
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
        translations: reader.selectedTok >= 0 && reader.tokens[reader.selectedTok] ? reader.tokens[reader.selectedTok][1] : []
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
            pageCount: Math.max(1, reader.pages.length)
            minutesLeft: reader.minutesLeft
            percent: reader.percent
            fonts: reader.fonts
            onSeek: index => reader.goTo(index)
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
                    reader.goTo(0);
                } else if (key === "read") {
                    reader.finished = true;
                    reader.markFinished();
                } else if (key === "reset") {
                    reader.selectedTok = -1;
                    reader.pageIndex = 0;
                    reader.finished = false;
                    reader.resetProgress();
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
