import QtQuick
import "components"
import "js/theme.js" as Theme
import "js/deck.js" as Deck

// Drilling: App.jsx. One question at a time from the filtered (and by
// default shuffled) deck; a reading-comp passage and its questions are the
// tabs of one group in the bottom bar.
//
// Answers only live as long as the current group, as on the web. The
// filters and switches are saved, and so is where you are (the web app's
// ?q=PT141-S4-Q9 / -P), so reopening the app lands on the same question.
Item {
    id: drill

    property QtObject store            // main.qml's question cache
    property var savedSettings: null
    property string savedPosition: ""
    signal saveSettings(var settings)
    signal savePosition(string position)
    signal practiceTest
    signal closeApp
    signal info

    property var settings: ({ sections: [], types: [], levels: [], tests: [], heldOut: false, shuffle: true })
    // The order is fixed for the session so a filter change doesn't deal a
    // new one underneath you.
    readonly property real seed: Math.floor(Math.random() * 4294967296)
    property var deck: []
    property var deckPos: ({})
    property int deckVersion: 0
    property int currentI: -1
    property var answers: ({})
    property var eliminated: ({})
    property bool strikeMode: false
    property string tab: "passage"     // which of a passage group's tabs is open
    property var quote: null           // {text, hit, nonce}
    property bool finished: false
    property bool menuOpen: false
    property bool started: false

    // ---- settings

    function loadSettings(saved) {
        var s = { sections: [], types: [], levels: [], tests: [], heldOut: false, shuffle: true };
        if (saved) {
            var known = function (value, valid) {
                return Array.isArray(value) ? value.filter(valid) : [];
            };
            s.sections = known(saved.sections, function (v) { return Theme.TAXONOMY[v] !== undefined; });
            s.types = known(saved.types, function (v) {
                return Deck.TYPE_FILTERS.some(function (t) { return t.key === v; });
            });
            s.levels = known(saved.levels, function (v) { return Theme.DIFFICULTY_LEVELS.indexOf(v) >= 0; });
            s.tests = known(saved.tests, function (v) {
                return Deck.tests.some(function (t) { return t.test === v; });
            });
            if (typeof saved.heldOut === "boolean")
                s.heldOut = saved.heldOut;
            if (typeof saved.shuffle === "boolean")
                s.shuffle = saved.shuffle;
            if (!s.heldOut)
                s.tests = s.tests.filter(function (t) { return !Deck.isHeldOut(t); });
        }
        return s;
    }

    function start() {
        var position = Deck.positionFromKey(savedPosition);
        var s = loadSettings(savedSettings);
        // A saved position in a held-out test is followed, as a ?q link is.
        if (position && Deck.isHeldOut(Deck.questions[position.i].test))
            s.heldOut = true;
        if (position) {
            currentI = position.i;
            tab = position.passage ? "passage" : "question";
        }
        settings = s;
        started = true;
        rebuild();
    }

    function update(change) {
        var s = {};
        for (var k in settings)
            s[k] = settings[k];
        for (k in change)
            s[k] = change[k];
        settings = s;
        finished = false;
        rebuild();
        saveSettings(s);
    }

    function toggled(list, value) {
        var i = list.indexOf(value);
        return i >= 0 ? list.slice(0, i).concat(list.slice(i + 1)) : list.concat([value]);
    }

    // Putting the reserved tests back out of drilling also drops them from
    // the test filter, so the filter can't be left on questions it lost.
    function toggleHeldOut() {
        if (settings.heldOut)
            update({ heldOut: false, tests: settings.tests.filter(function (t) { return !Deck.isHeldOut(t); }) });
        else
            update({ heldOut: true });
    }

    function rebuild() {
        var list = Deck.applyFilters(settings);
        var order = settings.shuffle ? Deck.shuffleDeck(list, seed) : list;
        var pos = {};
        for (var i = 0; i < order.length; i++)
            pos[order[i]] = i;
        deckPos = pos;
        deck = order;
        deckVersion++;
    }

    // ---- where you are

    // Position is kept by question, not by index: when a filter changes you
    // stay on the current question if it survives, and fall to the top if not.
    readonly property int qi: deckVersion >= 0 && currentI >= 0 && deckPos[currentI] !== undefined
                              ? currentI : (deck.length ? deck[0] : -1)
    readonly property int idx: qi >= 0 && deckPos[qi] !== undefined ? deckPos[qi] : 0
    readonly property bool isLast: idx === deck.length - 1
    readonly property var group: qi >= 0 ? Deck.groupOf(qi) : null
    readonly property bool revealed: qi >= 0 && answers[qi] !== undefined
    readonly property var siblings: !group || !(group.isRC || group.qs.length > 1) ? []
                                    : group.qs.filter(function (i) { return drill.deckPos[i] !== undefined; })
    readonly property int siblingIdx: siblings.indexOf(qi)
    readonly property bool hasPassage: group !== null && group.isRC
    readonly property bool readingPassage: hasPassage && siblings.length > 0 && tab === "passage"
    readonly property bool canGroupBack: siblings.length > 0 && (readingPassage ? false : hasPassage ? true : siblingIdx > 0)
    readonly property bool canGroupForward: siblings.length > 0 && (readingPassage ? true : siblingIdx < siblings.length - 1)
    readonly property var question: qi >= 0 ? store.model(qi) : null

    property int lastGroup: -2
    onQiChanged: {
        if (qi < 0)
            return;
        // Once a filter takes the selected question away, the one shown in
        // its place becomes the selection, so widening the filter again
        // doesn't jump back.
        if (currentI !== qi)
            Qt.callLater(function () { drill.currentI = drill.qi; });
        var g = Deck.questions[qi].group;
        if (g !== lastGroup) {
            // Answers last as long as the group, and a new group opens on
            // its passage — except where the app opened, from a saved place.
            if (lastGroup !== -2) {
                answers = {};
                tab = "passage";
            }
            lastGroup = g;
        }
        strikeMode = false;
        quote = null;
        prefetch();
    }

    readonly property string positionKey: qi < 0 ? "" : readingPassage ? Deck.passageKey(qi) : Deck.questionKey(qi)
    onPositionKeyChanged: if (started && positionKey) savePosition(positionKey)

    function prefetch() {
        store.request(qi);
        for (var s = 0; s < siblings.length; s++)
            store.request(siblings[s]);
        if (idx + 1 < deck.length)
            store.request(deck[idx + 1]);
    }

    function goTo(pos) {
        var target = deck[pos];
        if (target === undefined)
            return;
        currentI = target;
    }
    function goToId(i) {
        currentI = i;
        finished = false;
    }
    function openQuestion(i) {
        tab = "question";
        goToId(i);
    }
    function advance() {
        if (isLast) {
            answers = {};
            finished = true;
        } else {
            goTo(idx + 1);
        }
    }
    function groupBack() {
        if (readingPassage)
            return;
        if (hasPassage && siblingIdx <= 0)
            tab = "passage";
        else if (siblingIdx > 0)
            openQuestion(siblings[siblingIdx - 1]);
    }
    function groupForward() {
        if (readingPassage) {
            tab = "question";
            if (siblings[0] !== qi)
                goToId(siblings[0]);
        } else if (siblingIdx < siblings.length - 1) {
            openQuestion(siblings[siblingIdx + 1]);
        }
    }
    // Done reading lands on the passage's first question.
    function next() {
        if (readingPassage) {
            tab = "question";
            if (siblings[0] !== qi)
                goToId(siblings[0]);
        } else {
            advance();
        }
    }

    function select(letter) {
        if (qi < 0 || answers[qi] !== undefined)
            return;
        var a = {};
        for (var k in answers)
            a[k] = answers[k];
        a[qi] = letter;
        answers = a;
        // Picking a struck-out answer un-strikes it.
        var e = eliminatedFor(qi);
        if (e.indexOf(letter) >= 0)
            setEliminated(qi, e.filter(function (l) { return l !== letter; }));
    }
    function eliminatedFor(i) {
        return eliminated[i] || [];
    }
    function setEliminated(i, list) {
        var e = {};
        for (var k in eliminated)
            e[k] = eliminated[k];
        e[i] = list;
        eliminated = e;
    }
    function toggleEliminate(letter) {
        setEliminated(qi, toggled(eliminatedFor(qi), letter));
    }
    function showQuote(text) {
        quote = { text: text, hit: quote && quote.text === text ? quote.hit + 1 : 0,
                  nonce: (quote ? quote.nonce : 0) + 1 };
        Qt.callLater(revealQuote);
    }
    function revealQuote() {
        layout();
        var y = passagePane.quoteY();
        if (y >= 0)
            pager.reveal(passagePane, y, true);
    }

    // Positioners lay out lazily; measure only after they have.
    function layout() {
        passagePane.forceLayout();
        questionPane.forceLayout();
        panes.forceLayout();
        pager.body.forceLayout();
    }

    // A reading-comp question opens on the question itself, with its passage
    // one swipe back; everything else opens at the top.
    property string placed: ""
    function place() {
        var key = qi + ":" + readingPassage + ":" + (question !== null);
        if (key === placed)
            return;
        placed = key;
        layout();
        if (question && hasPassage && !readingPassage)
            pager.reveal(questionPane, -Theme.px(20), false);
        else
            pager.reset();
    }
    onQuestionChanged: Qt.callLater(place)
    onReadingPassageChanged: Qt.callLater(place)

    // ---- the screen

    Header {
        id: header
        title: drill.qi >= 0 ? Deck.titleFor(drill.qi) : Deck.deckTitle
        IconButton {
            icon: "info"
            onClicked: drill.info()
        }
        IconButton {
            objectName: "practiceButton"
            visible: drill.started && Deck.exams.length > 0
            icon: "stopwatch"
            onClicked: {
                drill.menuOpen = false;
                drill.answers = {};
                drill.practiceTest();
            }
        }
        IconButton {
            objectName: "settingsButton"
            icon: "settings"
            active: drill.menuOpen
            onClicked: drill.menuOpen = !drill.menuOpen
        }
        IconButton {
            icon: "close"
            onClicked: drill.closeApp()
        }
    }

    Item {
        id: main
        y: header.height
        width: parent.width
        height: (drill.finished || drill.qi < 0 ? parent.height : bottomBar.y) - y

        Pager {
            id: pager
            visible: !drill.finished && drill.qi >= 0
            anchors.fill: parent

            Item {
                width: pager.width
                height: panes.height + Theme.px(20)
                Column {
                    id: panes
                    x: Theme.px(20)
                    y: Theme.px(20)
                    width: parent.width - 2 * Theme.px(20)
                    spacing: Theme.px(24)

                    PassagePane {
                        id: passagePane
                        question: drill.question
                        revealed: drill.revealed && !drill.readingPassage
                        passageOnly: drill.readingPassage
                        quote: drill.quote
                    }
                    QuestionPane {
                        id: questionPane
                        visible: !drill.readingPassage && drill.question !== null
                        question: drill.question
                        selected: drill.question && drill.answers[drill.qi] !== undefined ? drill.answers[drill.qi] : ""
                        revealed: drill.revealed
                        eliminated: drill.eliminated[drill.qi] || []
                        strikeMode: drill.strikeMode
                        quote: drill.quote
                        onSelect: letter => drill.select(letter)
                        onEliminate: letter => drill.toggleEliminate(letter)
                        onToggleStrike: drill.strikeMode = !drill.strikeMode
                        onShowQuote: text => drill.showQuote(text)
                    }
                }
            }
            ExplanationPane {
                visible: drill.revealed && !drill.readingPassage && drill.question !== null
                question: drill.question
            }
        }

        Results {
            visible: drill.finished
            anchors.fill: parent
            count: drill.deck.length
            onRestart: {
                drill.answers = {};
                drill.eliminated = {};
                drill.finished = false;
                drill.goTo(0);
            }
        }

        // No question matches the filters.
        Column {
            visible: drill.started && drill.qi < 0
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.px(32)
            spacing: Theme.px(20)
            UiText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                size: 15
                color: Theme.inkSoft
                text: {
                    var s = drill.settings, parts = [];
                    if (s.sections.length)
                        parts.push(s.sections.slice().sort().map(function (c) {
                            return c === "LR" ? "logical reasoning" : "reading comprehension";
                        }).join(", "));
                    if (s.levels.length)
                        parts.push("difficulty " + s.levels.slice().sort().join(", "));
                    if (s.types.length)
                        parts.push("type " + Deck.summarizeTypes(s.types));
                    if (s.tests.length)
                        parts.push("test " + s.tests.slice().sort(function (a, b) { return a - b; }).join(", "));
                    return "No questions match " + parts.join("; ") + ".";
                }
            }
            PillButton {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Clear filter"
                onClicked: drill.update({ sections: [], types: [], levels: [], tests: [] })
            }
        }
    }

    BottomBar {
        id: bottomBar
        visible: !drill.finished && drill.qi >= 0
        y: parent.height - height
        revealed: drill.revealed
        isLast: drill.isLast
        siblings: drill.siblings
        numbers: drill.siblings.map(function (i) { return Deck.questions[i].number; })
        currentI: drill.qi
        hasPassage: drill.hasPassage
        readingPassage: drill.readingPassage
        canBack: drill.canGroupBack
        canForward: drill.canGroupForward
        onJump: i => drill.openQuestion(i)
        onShowPassage: drill.tab = "passage"
        onBack: drill.groupBack()
        onForward: drill.groupForward()
        onSkip: drill.advance()
        onNext: drill.next()
    }

    TestMenu {
        visible: drill.menuOpen
        anchors.fill: parent
        deckPos: drill.deckPos
        deckVersion: drill.deckVersion
        deckSize: drill.deck.length
        totalSize: drill.deckVersion >= 0 ? Deck.poolSize(drill.settings.heldOut) : 0
        currentI: drill.qi
        answers: drill.answers
        settings: drill.settings
        onClose: drill.menuOpen = false
        onJump: i => drill.goToId(i)
        onToggleSection: code => drill.update({ sections: drill.toggled(drill.settings.sections, code) })
        onClearSections: drill.update({ sections: [] })
        onToggleType: key => drill.update({ types: drill.toggled(drill.settings.types, key) })
        onClearTypes: drill.update({ types: [] })
        onToggleLevel: level => drill.update({ levels: drill.toggled(drill.settings.levels, level) })
        onClearLevels: drill.update({ levels: [] })
        onToggleTest: test => drill.update({ tests: drill.toggled(drill.settings.tests, test) })
        onClearTests: drill.update({ tests: [] })
        onToggleHeldOut: drill.toggleHeldOut()
        onToggleShuffle: drill.update({ shuffle: !drill.settings.shuffle })
    }
}
