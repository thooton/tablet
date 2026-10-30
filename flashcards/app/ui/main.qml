import QtQuick
import net.asivery.AppLoad 1.0
import "components"
import "js/theme.js" as Theme

// Flashcards: Anki's desktop window on the reMarkable, in black and white.
// Its toolbar (←, where the user is, Sync), the deck list, a deck's overview with Study
// Now, the reviewer, the deck's options and its statistics; and, until the tablet is
// paired with the command center, the pairing code. Where Anki tells the
// queues apart by colour, a shape does: New a triangle, Learning a square,
// To Review a circle.
//
// The backend (backend/) keeps the cards, schedules them and syncs them;
// this draws what it sends: the decks and how sync stands (101) and the
// card to show (102), and the statistics (103).
Rectangle {
    id: root
    anchors.fill: parent
    color: Theme.paper

    // Required by AppLoad.
    signal close
    // Never call backend.terminate() here (or anywhere): AppLoad then
    // unloads the app from its socket thread and the tablet's UI crashes
    // and restarts. The backend stays running and is reused next time
    // (tools/appload/lifecycle.go).
    function unloading() {
    }

    QtObject {
        id: fontSet
        readonly property string sans: family(sansRegular, "sans-serif")
        readonly property string sansMedium: family(sansMediumFile, sans)
        readonly property string sansSemi: family(sansSemiFile, sans)
        readonly property string sansBold: family(sansBoldFile, sans)
        function family(loader, fallback) {
            return loader.status === FontLoader.Ready ? loader.font.family : fallback;
        }
    }
    FontLoader { id: sansRegular; source: "fonts/IBMPlexSans-Regular.ttf" }
    FontLoader { id: sansMediumFile; source: "fonts/IBMPlexSans-Medium.ttf" }
    FontLoader { id: sansSemiFile; source: "fonts/IBMPlexSans-SemiBold.ttf" }
    FontLoader { id: sansBoldFile; source: "fonts/IBMPlexSans-Bold.ttf" }

    property var info: null          // the backend's state (101)
    property string screen: "decks"  // decks, overview, review, options, stats
    property string deckId: ""
    property var shown: null         // the card message (102) being shown
    property bool revealed: false
    property bool answering: false
    property double cardAt: 0        // when the card arrived (ms), for reveal()
    property int newPerDay: -1       // the options screen's value, until saved
    property var stats: null         // the statistics (103) being shown
    property bool statsWhole: false  // the whole collection's, not the deck's

    readonly property var decks: info ? info.decks : []
    readonly property var deck: {
        for (var i = 0; i < decks.length; i++)
            if (decks[i].id === deckId)
                return decks[i];
        return null;
    }

    AppLoad {
        id: backend
        applicationID: "flashcards"
        onMessageReceived: (type, contents) => {
            var msg;
            try {
                msg = JSON.parse(contents);
            } catch (e) {
                console.warn("flashcards: bad message", contents);
                return;
            }
            if (type === 101)
                root.info = msg;
            else if (type === 102)
                root.took(msg);
            else if (type === 103 && msg.deck === root.deckId && msg.whole === root.statsWhole)
                root.stats = msg;
        }
    }

    function send(type, payload) {
        backend.sendMessage(type, JSON.stringify(payload || {}));
    }

    // AppLoad may load the frontend before the backend has connected, so
    // keep asking until the first answer arrives.
    Timer {
        interval: 1500
        repeat: true
        triggeredOnStart: true
        running: root.info === null
        onTriggered: root.send(1)
    }

    function showDecks() {
        screen = "decks";
        shown = null;
        send(1);
    }
    function openDeck(id) {
        deckId = id;
        shown = null;
        screen = "overview";
        send(1);
        send(2, { deck: id });
    }
    // ahead: Anki's Review Ahead, the cards not yet due, likeliest forgotten first.
    function study(ahead) {
        revealed = false;
        answering = false;
        screen = "review";
        send(2, { deck: deckId, ahead: ahead === true });
    }
    function answer(rating) {
        if (!shown || !shown.card || answering)
            return;
        answering = true;
        send(3, { deck: deckId, card: shown.card.id, rating: rating });
    }
    // A second tap of a quick double tap on an answer lands on Show Answer,
    // where Good was: ignore Show Answer just after a card arrives.
    function reveal() {
        if (Date.now() - cardAt < 700)
            return;
        revealed = true;
    }
    function openOptions() {
        newPerDay = deck ? deck.newPerDay : -1;
        screen = "options";
    }
    function openStats(whole) {
        if (screen !== "stats")
            stats = null;
        statsWhole = whole === true;
        screen = "stats";
        send(7, { deck: deckId, whole: statsWhole });
    }
    function saveOptions() {
        send(4, { deck: deckId, new_per_day: newPerDay });
        screen = "overview";
    }

    // A card to show, or the deck done for now.
    function took(msg) {
        if (msg.deck !== deckId)
            return;
        shown = msg;
        cardAt = Date.now();
        answering = false;
        revealed = false;
        if (msg.done && screen === "review") {
            screen = "overview";
            send(1);
        }
        recheck.stop();
        if (msg.done && msg.recheck) {
            recheck.interval = Math.min(msg.recheck, 3600) * 1000;
            recheck.start();
        }
    }
    // A learning card comes back within learn-ahead: look again then.
    Timer {
        id: recheck
        onTriggered: if (root.screen === "overview") { root.send(1); root.send(2, { deck: root.deckId }); }
    }

    readonly property bool paired: info !== null && info.paired
    readonly property bool showProgress: info !== null && info.showProgress === true

    // One step up: the reviewer and the options to the deck's overview, the
    // overview to the decks, the decks out of the app.
    function back() {
        if (screen === "review" || screen === "options" || screen === "stats") {
            screen = "overview";
            send(1);
            send(2, { deck: deckId });
        } else if (screen === "overview")
            showDecks();
        else
            close();
    }

    // ---- toolbar: the way out on the left (X on the deck list, which closes
    // the app; ← in a deck, up a level), the screen's name centred and the
    // heaviest thing in the bar, Sync on the right, quieter
    Item {
        id: toolbar
        width: parent.width
        height: Theme.toolbarHeight
        visible: root.paired

        NavButton {
            icon: root.screen === "decks" ? "close" : "back"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.back()
        }
        // The screen's name: the overview's own page names the deck, large,
        // so the bar says Overview there rather than the name twice.
        Text {
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 2 * (Theme.margin + sync.width + 32))
            horizontalAlignment: Text.AlignHCenter
            text: root.screen === "decks" ? "Flashcards"
                : root.screen === "overview" ? "Overview"
                : root.screen === "options" ? "Options"
                : root.screen === "stats" ? "Statistics"
                : (root.deck ? root.deck.name : "")
            elide: Text.ElideRight
            color: Theme.ink
            font.family: fontSet.sansSemi
            font.weight: Font.DemiBold
            font.pixelSize: 44
        }
        ToolLink {
            id: sync
            anchors.right: parent.right
            anchors.rightMargin: Theme.margin
            anchors.verticalCenter: parent.verticalCenter
            text: root.info && root.info.syncing ? "Syncing…" : "Sync"
            onClicked: root.send(5)
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: Theme.rule
        }
    }
    // X or ←.
    component NavButton: Item {
        property string icon: "back"
        signal clicked
        x: 44
        width: 56
        height: 56
        Image {
            anchors.fill: parent
            source: "images/" + parent.icon + ".png"
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -28
            onClicked: parent.clicked()
        }
    }
    component ToolLink: Text {
        property bool current: false
        signal clicked
        color: Theme.ink
        font.family: current ? fontSet.sansSemi : fontSet.sans
        font.weight: current ? Font.DemiBold : Font.Normal
        font.pixelSize: 34
        MouseArea {
            anchors.fill: parent
            anchors.margins: -30
            onClicked: parent.clicked()
        }
    }

    // ---- the decks
    Item {
        id: deckPage
        visible: root.paired && root.screen === "decks"
        anchors.fill: parent
        anchors.topMargin: Theme.toolbarHeight + 56
        anchors.leftMargin: Theme.margin
        anchors.rightMargin: Theme.margin

        Column {
            width: parent.width
            // The table's head: Deck, then each queue under its shape.
            Item {
                width: parent.width
                height: 72
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 20
                    text: "Deck"
                    color: Theme.subtle
                    font.family: fontSet.sansMedium
                    font.weight: Font.Medium
                    font.pixelSize: 32
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: ["New", "Learn", "Due"]
                        Item {
                            width: Theme.deckColumn
                            height: 72
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 20
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12
                                Mark {
                                    queue: index
                                    size: 24
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData
                                    color: Theme.subtle
                                    font.family: fontSet.sansMedium
                                    font.weight: Font.Medium
                                    font.pixelSize: 32
                                }
                            }
                        }
                    }
                }
            }
            Rectangle { width: parent.width; height: 2; color: Theme.rule }
            Repeater {
                model: root.decks
                Item {
                    id: deckRow
                    readonly property var counts: modelData.counts
                    width: deckPage.width
                    height: Theme.deckRow
                    Text {
                        x: 20
                        width: parent.width - 3 * Theme.deckColumn - 40
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        elide: Text.ElideRight
                        color: Theme.ink
                        font.family: fontSet.sans
                        font.pixelSize: 42
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: 3
                            Text {
                                width: Theme.deckColumn
                                rightPadding: 20
                                horizontalAlignment: Text.AlignRight
                                text: deckRow.counts[index]
                                color: deckRow.counts[index] === 0 ? Theme.faint : Theme.ink
                                font.family: deckRow.counts[index] === 0 ? fontSet.sans : fontSet.sansMedium
                                font.weight: deckRow.counts[index] === 0 ? Font.Normal : Font.Medium
                                font.pixelSize: 42
                            }
                        }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.rule
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.openDeck(modelData.id)
                    }
                }
            }
            Text {
                width: parent.width
                topPadding: 56
                horizontalAlignment: Text.AlignHCenter
                visible: root.info !== null
                text: root.decks.length === 0
                    ? (root.info && (root.info.syncing || !root.info.synced) ? "Syncing…" : "No decks.")
                    : "Studied " + root.info.studied + (root.info.studied === 1 ? " card" : " cards") + " today."
                color: Theme.subtle
                font.family: fontSet.sans
                font.pixelSize: 34
            }
            Text {
                width: parent.width
                topPadding: 24
                horizontalAlignment: Text.AlignHCenter
                visible: root.info !== null && root.info.error !== ""
                text: root.info ? "Not synced: " + root.info.error : ""
                wrapMode: Text.Wrap
                color: Theme.ink
                font.family: fontSet.sans
                font.pixelSize: 34
            }
        }
    }

    // ---- a deck's overview
    Item {
        id: overview
        visible: root.paired && root.screen === "overview"
        anchors.fill: parent
        anchors.topMargin: Theme.toolbarHeight

        readonly property var counts: root.deck ? root.deck.counts : [0, 0, 0]
        readonly property bool any: counts[0] + counts[1] + counts[2] > 0

        Column {
            width: parent.width
            topPadding: 120
            spacing: 0
            Text {
                width: parent.width - 2 * Theme.margin
                x: Theme.margin
                horizontalAlignment: Text.AlignHCenter
                text: root.deck ? root.deck.name : ""
                wrapMode: Text.Wrap
                color: Theme.ink
                font.family: fontSet.sansSemi
                font.weight: Font.DemiBold
                font.pixelSize: 56
                bottomPadding: 64
            }
            // New, Learning, To Review, as Anki's table under the name.
            Repeater {
                model: overview.any ? ["New:", "Learning:", "To Review:"] : []
                Item {
                    width: overview.width
                    height: 76
                    Row {
                        x: overview.width / 2 - 360
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 22
                        Text {
                            width: 340
                            horizontalAlignment: Text.AlignRight
                            text: modelData
                            color: Theme.ink
                            font.family: fontSet.sans
                            font.pixelSize: 42
                        }
                        Mark {
                            queue: index
                            size: 30
                            anchors.verticalCenter: parent.verticalCenter
                            color: overview.counts[index] === 0 ? Theme.faint : Theme.ink
                        }
                        Text {
                            text: overview.counts[index]
                            color: overview.counts[index] === 0 ? Theme.faint : Theme.ink
                            font.family: fontSet.sansMedium
                            font.weight: Font.Medium
                            font.pixelSize: 42
                        }
                    }
                }
            }
            Item {
                width: parent.width
                height: 180
                visible: overview.any
                AnkiButton {
                    anchors.centerIn: parent
                    width: 420
                    fonts: fontSet
                    text: "Study Now"
                    preferred: true
                    onClicked: root.study()
                }
            }
            Text {
                visible: !overview.any
                width: parent.width
                leftPadding: Theme.margin * 2
                rightPadding: Theme.margin * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "Congratulations! You have finished this deck for now."
                color: Theme.ink
                font.family: fontSet.sans
                font.pixelSize: 44
                lineHeight: 1.2
            }
            Text {
                visible: !overview.any && root.shown !== null && root.shown.nextMinutes !== undefined
                width: parent.width
                topPadding: 40
                leftPadding: Theme.margin * 2
                rightPadding: Theme.margin * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.shown && root.shown.nextMinutes
                    ? "The next learning card will be ready in " + root.shown.nextMinutes
                      + (root.shown.nextMinutes === 1 ? " minute." : " minutes.")
                    : ""
                color: Theme.subtle
                font.family: fontSet.sans
                font.pixelSize: 36
            }
            Item {
                width: parent.width
                height: 220
                visible: !overview.any && root.shown !== null && root.shown.studied === true
                AnkiButton {
                    anchors.centerIn: parent
                    width: 460
                    fonts: fontSet
                    text: "Review Ahead"
                    onClicked: root.study(true)
                }
            }
        }
        BottomBar {
            Row {
                anchors.centerIn: parent
                spacing: 40
                AnkiButton {
                    width: 300
                    fonts: fontSet
                    text: "Options"
                    onClicked: root.openOptions()
                }
                AnkiButton {
                    width: 300
                    fonts: fontSet
                    text: "Stats"
                    onClicked: root.openStats(false)
                }
            }
        }
    }
    component BottomBar: Item {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 180
        Rectangle {
            width: parent.width
            height: 2
            color: Theme.rule
        }
    }

    // ---- the reviewer
    Item {
        id: reviewer
        visible: root.paired && root.screen === "review" && root.shown !== null && root.shown.card !== undefined
        anchors.fill: parent
        anchors.topMargin: Theme.toolbarHeight

        readonly property var card: root.shown && root.shown.card ? root.shown.card : null
        property real fontScale: 1
        property bool auxCut: false

        // Long cards (a word with its examples) shrink until they fit: no
        // scrolling on e-ink.
        // The texts' own heights, not the Column's: the Column lays out
        // only before the next frame, so it would still measure the last
        // card, or the front without the newly shown answer.
        function fit() {
            Qt.callLater(shrink);
        }
        function needed() {
            var h = frontText.implicitHeight;
            if (root.revealed) {
                h += answerRule.height + backText.implicitHeight;
                if (card !== null && card.aux.trim() !== "")
                    h += auxText.implicitHeight;
            }
            return h;
        }
        function shrink() {
            var scale = 1;
            fontScale = scale;
            auxText.maximumLineCount = 1000;
            auxCut = false;
            while (needed() > cardArea.height - 80 && scale > 0.45) {
                scale = scale * 0.85;
                fontScale = scale;
            }
            // Still too tall at the floor: cut the notes, not the counts.
            var room = cardArea.height - 80 - cardText.y;
            if (needed() > room && auxText.visible) {
                var line = (auxText.implicitHeight - auxText.topPadding) / auxText.lineCount;
                var free = room - (needed() - auxText.implicitHeight) - auxText.topPadding;
                var lines = Math.floor(free / line);
                auxCut = lines < 1;
                auxText.maximumLineCount = Math.max(1, lines);
            }
        }
        onCardChanged: fit()
        Connections {
            target: root
            function onRevealedChanged() { reviewer.fit(); }
        }

        Item {
            id: cardArea
            width: parent.width
            height: parent.height - Theme.bottomBar
            Column {
                id: cardText
                width: parent.width - 2 * Theme.margin
                x: Theme.margin
                y: 72
                spacing: 0
                Text {
                    id: frontText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: reviewer.card ? reviewer.card.front.trim() : ""
                    color: Theme.ink
                    font.family: fontSet.sans
                    font.pixelSize: Math.round(64 * reviewer.fontScale)
                }
                Item {
                    id: answerRule
                    visible: root.revealed
                    width: parent.width
                    height: Math.round(80 * reviewer.fontScale)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 2
                        color: Theme.rule
                    }
                }
                Text {
                    id: backText
                    visible: root.revealed
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: reviewer.card ? reviewer.card.back.trim() : ""
                    color: Theme.ink
                    font.family: fontSet.sans
                    font.pixelSize: Math.round(64 * reviewer.fontScale)
                }
                Text {
                    id: auxText
                    visible: root.revealed && !reviewer.auxCut && reviewer.card !== null && reviewer.card.aux.trim() !== ""
                    width: parent.width
                    topPadding: Math.round(40 * reviewer.fontScale)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: reviewer.card ? reviewer.card.aux.trim() : ""
                    color: Theme.subtle
                    font.family: fontSet.sans
                    font.pixelSize: Math.round(40 * reviewer.fontScale)
                    lineHeight: 1.15
                }
            }
        }

        // Anki's bottom bar: the counts over Show Answer, then the answers.
        Item {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Theme.bottomBar
            Rectangle {
                width: parent.width
                height: 2
                color: Theme.rule
            }
            Row {
                id: countsRow
                anchors.horizontalCenter: parent.horizontalCenter
                y: 30
                spacing: 56
                Repeater {
                    model: 3
                    Row {
                        spacing: 14
                        readonly property int count: root.shown ? root.shown.counts[index] : 0
                        readonly property bool current: root.shown !== null && root.shown.queue === index
                        Mark {
                            queue: index
                            size: 28
                            anchors.verticalCenter: parent.verticalCenter
                            color: count === 0 ? Theme.faint : Theme.ink
                        }
                        Text {
                            text: count
                            color: count === 0 ? Theme.faint : Theme.ink
                            font.family: current ? fontSet.sansBold : fontSet.sans
                            font.weight: current ? Font.Bold : Font.Normal
                            font.underline: current
                            font.pixelSize: 38
                        }
                    }
                }
            }
            // Options > Show progress: how far through the deck, small and to the side.
            Text {
                visible: root.showProgress && root.shown !== null && root.shown.progress !== undefined
                anchors.right: parent.right
                anchors.rightMargin: Theme.margin
                y: 36
                text: root.shown && root.shown.progress !== undefined ? (root.shown.progress / 100).toFixed(2) + "%" : ""
                color: Theme.subtle
                font.family: fontSet.sans
                font.pixelSize: 30
            }
            AnkiButton {
                visible: !root.revealed
                anchors.horizontalCenter: parent.horizontalCenter
                y: 140
                width: 520
                fonts: fontSet
                text: "Show Answer"
                preferred: true
                onClicked: root.reveal()
            }
            Row {
                visible: root.revealed
                anchors.horizontalCenter: parent.horizontalCenter
                y: 96
                spacing: 28
                Repeater {
                    model: ["Again", "Hard", "Good", "Easy"]
                    Column {
                        spacing: 14
                        Text {
                            width: 290
                            horizontalAlignment: Text.AlignHCenter
                            text: reviewer.card ? reviewer.card.intervals[index] : ""
                            color: Theme.subtle
                            font.family: fontSet.sans
                            font.pixelSize: 32
                        }
                        AnkiButton {
                            width: 290
                            fonts: fontSet
                            text: modelData
                            preferred: index === 2
                            onClicked: root.answer(index + 1)
                        }
                    }
                }
            }
        }
    }

    // ---- a deck's options
    Item {
        id: options
        visible: root.paired && root.screen === "options"
        anchors.fill: parent
        anchors.topMargin: Theme.toolbarHeight

        Column {
            width: parent.width - 2 * Theme.margin
            x: Theme.margin
            topPadding: 72
            spacing: 40
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.deck ? root.deck.name : ""
                elide: Text.ElideRight
                color: Theme.subtle
                font.family: fontSet.sans
                font.pixelSize: 36
            }
            // Anki's options sit on cards, each under its section's name.
            Rectangle {
                width: parent.width
                height: limits.height + 2 * 56
                radius: 16
                border.width: 2
                border.color: Theme.rule
                Column {
                    id: limits
                    x: 56
                    y: 56
                    width: parent.width - 112
                    spacing: 48
                    Text {
                        text: "Daily Limits"
                        color: Theme.ink
                        font.family: fontSet.sansSemi
                        font.weight: Font.DemiBold
                        font.pixelSize: 46
                    }
                    Item {
                        width: parent.width
                        height: Theme.buttonHeight
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "New cards/day"
                            color: Theme.ink
                            font.family: fontSet.sans
                            font.pixelSize: 42
                        }
                        // Auto, or a number a day.
                        Row {
                            anchors.right: parent.right
                            spacing: 0
                            Choice {
                                text: "Auto"
                                on: root.newPerDay < 0
                                onClicked: root.newPerDay = -1
                            }
                            Choice {
                                text: "Number"
                                on: root.newPerDay >= 0
                                onClicked: if (root.newPerDay < 0) root.newPerDay = 20
                            }
                        }
                    }
                    // The number, stepped as Anki's spin box steps it.
                    Item {
                        width: parent.width
                        height: Theme.buttonHeight
                        visible: root.newPerDay >= 0
                        Row {
                            anchors.right: parent.right
                            spacing: 24
                            Step { text: "−10"; by: -10 }
                            Step { text: "−"; by: -1 }
                            Text {
                                width: 170
                                height: Theme.buttonHeight
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: root.newPerDay
                                color: Theme.ink
                                font.family: fontSet.sansMedium
                                font.weight: Font.Medium
                                font.pixelSize: 52
                            }
                            Step { text: "+"; by: 1 }
                            Step { text: "+10"; by: 10 }
                        }
                    }
                }
            }
            // This device's display, not the deck's: applies at once.
            Rectangle {
                width: parent.width
                height: display.height + 2 * 56
                radius: 16
                border.width: 2
                border.color: Theme.rule
                Column {
                    id: display
                    x: 56
                    y: 56
                    width: parent.width - 112
                    spacing: 48
                    Text {
                        text: "Display"
                        color: Theme.ink
                        font.family: fontSet.sansSemi
                        font.weight: Font.DemiBold
                        font.pixelSize: 46
                    }
                    Item {
                        width: parent.width
                        height: Theme.buttonHeight
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Show progress"
                            color: Theme.ink
                            font.family: fontSet.sans
                            font.pixelSize: 42
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 0
                            Choice {
                                text: "Off"
                                on: !root.showProgress
                                onClicked: root.send(8, { show_progress: false })
                            }
                            Choice {
                                text: "On"
                                on: root.showProgress
                                onClicked: root.send(8, { show_progress: true })
                            }
                        }
                    }
                }
            }
        }
        BottomBar {
            Row {
                anchors.centerIn: parent
                spacing: 40
                AnkiButton {
                    width: 300
                    fonts: fontSet
                    text: "Cancel"
                    onClicked: root.screen = "overview"
                }
                AnkiButton {
                    width: 300
                    fonts: fontSet
                    text: "Save"
                    preferred: true
                    onClicked: root.saveOptions()
                }
            }
        }
    }
    component Choice: Rectangle {
        property string text
        property bool on: false
        signal clicked
        width: 230
        height: Theme.buttonHeight
        color: on ? Theme.ink : Theme.paper
        border.width: 2
        border.color: Theme.ink
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: parent.on ? Theme.paper : Theme.ink
            font.family: fontSet.sansMedium
            font.weight: Font.Medium
            font.pixelSize: 38
        }
        MouseArea {
            anchors.fill: parent
            onClicked: parent.clicked()
        }
    }
    component Step: AnkiButton {
        property int by: 1
        width: 130
        fonts: fontSet
        textSize: 42
        onClicked: root.newPerDay = Math.max(0, Math.min(9999, root.newPerDay + by))
    }

    // ---- a deck's statistics: Anki's Statistics window, its graphs each on
    // a card under its name, cut to what the cards' state can tell
    Item {
        id: statsPage
        visible: root.paired && root.screen === "stats"
        anchors.fill: parent
        anchors.topMargin: Theme.toolbarHeight

        readonly property var s: root.stats
        readonly property real inner: width - 2 * Theme.margin

        function plural(n, one, many) {
            return n + " " + (n === 1 ? one : many);
        }

        Column {
            visible: statsPage.s !== null
            x: Theme.margin
            width: statsPage.inner
            topPadding: 14
            spacing: 18

            // Anki's search bar: the deck, or the whole collection.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 80
                Radio {
                    text: root.deck ? root.deck.name : ""
                    on: !root.statsWhole
                    onClicked: root.openStats(false)
                }
                Radio {
                    text: "Collection"
                    on: root.statsWhole
                    onClicked: root.openStats(true)
                }
            }

            StatCard {
                title: "Today"
                Fact {
                    text: !statsPage.s ? ""
                        : statsPage.s.studied === 0 ? "No cards have been studied today."
                        : "Studied " + statsPage.plural(statsPage.s.studied, "card", "cards") + " today."
                }
                Fact {
                    visible: statsPage.s !== null && statsPage.s.studied > 0
                    color: Theme.subtle
                    text: statsPage.s ? "New: " + statsPage.s.introduced + "  |  Review: " + (statsPage.s.studied - statsPage.s.introduced) : ""
                }
            }

            StatCard {
                title: "Future Due"
                Bars {
                    width: parent.width
                    height: 210
                    fonts: fontSet
                    values: statsPage.s ? statsPage.s.due : []
                    labels: ["0", null, null, null, null, "5", null, null, null, null, "10", null, null, null, null,
                        "15", null, null, null, null, "20", null, null, null, null, "25", null, null, null, null]
                }
                Fact {
                    text: statsPage.s ? "Due today: " + statsPage.plural(statsPage.s.due[0], "review", "reviews")
                        + "  |  Due tomorrow: " + statsPage.plural(statsPage.s.due[1], "review", "reviews") : ""
                }
                Fact {
                    text: statsPage.s ? "Average: " + statsPage.s.dueAverage + " reviews/day  |  Total: "
                        + statsPage.plural(statsPage.s.dueTotal, "review", "reviews") : ""
                }
            }

            StatCard {
                title: "Card Counts"
                Row {
                    width: parent.width
                    spacing: 70
                    Pie {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 310
                        height: 310
                        counts: statsPage.s ? statsPage.s.counts : []
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 310 - 70
                        spacing: 6
                        Repeater {
                            model: statsPage.s ? statsPage.s.countNames.length : 0
                            CountRow {
                                kind: index
                                name: statsPage.s.countNames[index]
                                count: statsPage.s.counts[index]
                                share: statsPage.s.percents[index]
                            }
                        }
                        CountRow {
                            kind: -1
                            name: "Total"
                            count: statsPage.s ? statsPage.s.total : 0
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 22
                StatCard {
                    width: (parent.width - 22) / 2
                    title: "Review Intervals"
                    Bars {
                        width: parent.width
                        height: 180
                        fonts: fontSet
                        textSize: 24
                        values: statsPage.s ? statsPage.s.intervals : []
                        labels: statsPage.s ? statsPage.s.intervalLabels : []
                    }
                    Fact {
                        textSize: 32
                        text: statsPage.s ? "Average: " + statsPage.s.averageInterval : ""
                    }
                    Fact {
                        textSize: 32
                        text: statsPage.s ? "Longest: " + statsPage.s.longestInterval : ""
                    }
                }
                StatCard {
                    width: (parent.width - 22) / 2
                    title: "Card Retrievability"
                    Bars {
                        width: parent.width
                        height: 180
                        fonts: fontSet
                        textSize: 24
                        values: statsPage.s ? statsPage.s.recall : []
                        labels: ["0%", null, null, null, null, "50%", null, null, null, null, "100%"]
                    }
                    Fact {
                        textSize: 32
                        text: statsPage.s ? "Average: " + statsPage.s.averageRecall : ""
                    }
                    Fact {
                        textSize: 32
                        text: statsPage.s ? "Total knowledge: " + statsPage.plural(statsPage.s.knowledge, "card", "cards") : ""
                    }
                }
            }
        }
    }
    // A graph's card: white, outlined, its name centred over what it shows.
    component StatCard: Rectangle {
        property string title
        default property alias content: body.data
        width: parent ? parent.width : 0
        height: body.height + 2 * 24
        radius: 16
        border.width: 2
        border.color: Theme.rule
        Column {
            id: body
            x: 40
            y: 24
            width: parent.width - 80
            spacing: 12
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: parent.parent.title
                color: Theme.ink
                font.family: fontSet.sansSemi
                font.weight: Font.DemiBold
                font.pixelSize: 40
            }
        }
    }
    component Fact: Text {
        property int textSize: 34
        width: parent ? parent.width : 0
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: Theme.ink
        font.family: fontSet.sans
        font.pixelSize: textSize
    }
    // Card Counts' table: the fill, the name, the count, the share.
    component CountRow: Item {
        property int kind: 0
        property string name
        property int count: 0
        property string share: ""
        width: parent ? parent.width : 0
        height: 52
        Hatch {
            visible: parent.kind >= 0
            kind: Math.max(0, parent.kind)
            width: 44
            height: 44
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            x: 72
            anchors.verticalCenter: parent.verticalCenter
            text: parent.name
            color: Theme.ink
            font.family: parent.kind < 0 ? fontSet.sansSemi : fontSet.sans
            font.weight: parent.kind < 0 ? Font.DemiBold : Font.Normal
            font.pixelSize: 36
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 170
            anchors.verticalCenter: parent.verticalCenter
            text: parent.count
            color: Theme.ink
            font.family: parent.kind < 0 ? fontSet.sansSemi : fontSet.sansMedium
            font.weight: parent.kind < 0 ? Font.DemiBold : Font.Medium
            font.pixelSize: 36
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.share
            color: Theme.subtle
            font.family: fontSet.sans
            font.pixelSize: 36
        }
    }
    // Anki's radio button: a ring, with a dot in the one chosen.
    component Radio: Item {
        id: radio
        property string text
        property bool on: false
        signal clicked
        width: radioRow.width
        height: 80
        Row {
            id: radioRow
            height: parent.height
            spacing: 18
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: 20
                border.width: 3
                border.color: Theme.ink
                Rectangle {
                    visible: radio.on
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    radius: 10
                    color: Theme.ink
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 520)
                text: radio.text
                elide: Text.ElideRight
                color: Theme.ink
                font.family: radio.on ? fontSet.sansMedium : fontSet.sans
                font.weight: radio.on ? Font.Medium : Font.Normal
                font.pixelSize: 38
            }
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -20
            onClicked: radio.clicked()
        }
    }

    // ---- pairing: the code to type on the website's Tablet page
    Item {
        id: pairPage
        visible: root.info !== null && !root.info.paired
        anchors.fill: parent

        NavButton {
            icon: "close"
            y: (Theme.toolbarHeight - height) / 2
            onClicked: root.close()
        }
        Column {
            anchors.centerIn: parent
            width: parent.width - 4 * Theme.margin
            spacing: 36
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "PAIRING CODE"
                color: Theme.subtle
                font.family: fontSet.sansSemi
                font.weight: Font.DemiBold
                font.pixelSize: 34
                font.letterSpacing: 34 * 0.12
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                // "…" only while a code is on its way, not under an error.
                text: root.info && root.info.code ? root.info.code : root.info && root.info.pairErr !== "" ? "" : "…"
                color: Theme.ink
                font.family: fontSet.sansBold
                font.weight: Font.Bold
                font.pixelSize: 150
                font.letterSpacing: 150 * 0.08
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.info ? "Delta (" + root.info.host + "), Tablet" : ""
                color: Theme.subtle
                font.family: fontSet.sans
                font.pixelSize: 36
            }
            Text {
                width: parent.width
                topPadding: 40
                horizontalAlignment: Text.AlignHCenter
                visible: root.info !== null && root.info.pairErr !== ""
                wrapMode: Text.Wrap
                text: root.info ? root.info.pairErr : ""
                color: Theme.ink
                font.family: fontSet.sans
                font.pixelSize: 38
            }
            Item {
                width: parent.width
                height: Theme.buttonHeight
                visible: root.info !== null && !root.info.pairing && !root.info.code
                AnkiButton {
                    anchors.centerIn: parent
                    fonts: fontSet
                    text: "Try Again"
                    preferred: true
                    onClicked: root.send(6)
                }
            }
        }
    }
}
