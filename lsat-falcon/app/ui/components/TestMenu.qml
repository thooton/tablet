import QtQuick
import "../js/theme.js" as Theme
import "../js/deck.js" as Deck

// The settings sidebar (Sidebar.jsx + TestMenu.jsx). At this width it
// covers the whole screen. Filters first, then the deck as test → section →
// question, in test order however the deck is dealt; one section is open at
// a time, starting with the one you're in. The whole panel pages as one.
Rectangle {
    id: menu
    property var deckPos: ({})
    property int deckSize: 0
    property int totalSize: 0
    property int currentI: -1
    property var answers: ({})
    property var settings: ({ sections: [], types: [], levels: [], tests: [], heldOut: false, shuffle: true })
    property int deckVersion: 0
    signal jump(int i)
    signal toggleSection(string code)
    signal clearSections
    signal toggleType(string key)
    signal clearTypes
    signal toggleLevel(int level)
    signal clearLevels
    signal toggleTest(var test)
    signal clearTests
    signal toggleHeldOut
    signal toggleShuffle
    signal close

    color: Theme.surface

    readonly property bool filtered: settings.sections.length > 0 || settings.types.length > 0
                                     || settings.levels.length > 0 || settings.tests.length > 0

    // Only what survives the filters, and only tests/sections with something left.
    readonly property var visibleTests: {
        deckVersion;
        var out = [];
        for (var t = 0; t < Deck.tests.length; t++) {
            var test = Deck.tests[t];
            var sections = [], count = 0;
            for (var s = 0; s < test.sections.length; s++) {
                var qs = test.sections[s].qs.filter(function (i) { return menu.deckPos[i] !== undefined; });
                if (qs.length) {
                    sections.push({ key: test.sections[s].key, label: test.sections[s].label, qs: qs });
                    count += qs.length;
                }
            }
            if (sections.length)
                out.push({ key: test.key, label: test.label, heldOut: test.heldOut, count: count, sections: sections });
        }
        return out;
    }
    readonly property string currentKey: {
        var first = "";
        for (var t = 0; t < visibleTests.length; t++)
            for (var s = 0; s < visibleTests[t].sections.length; s++) {
                var sec = visibleTests[t].sections[s];
                if (!first)
                    first = sec.key;
                if (sec.qs.indexOf(currentI) >= 0)
                    return sec.key;
            }
        return first;
    }
    // undefined follows the question you're on; a key pins one section open;
    // null closes them all.
    property var openKey: undefined
    readonly property var shownKey: {
        if (openKey === null)
            return null;
        for (var t = 0; t < visibleTests.length; t++)
            for (var s = 0; s < visibleTests[t].sections.length; s++)
                if (visibleTests[t].sections[s].key === openKey)
                    return openKey;
        return currentKey;
    }

    // deckVersion is read so these follow the deck once it has loaded:
    // js/deck.js itself isn't something bindings can watch.
    readonly property var drilledTests: deckVersion >= 0 ? Deck.tests.filter(function (t) { return !t.heldOut; }) : []
    readonly property var heldOutTests: deckVersion >= 0 ? Deck.tests.filter(function (t) { return t.heldOut; }) : []

    property Item currentRow: null
    function revealCurrent() {
        list.body.forceLayout();
        list.reset();
        if (currentRow)
            list.reveal(currentRow, 0, true);
    }
    onVisibleChanged: if (visible) Qt.callLater(revealCurrent)

    // ---- header
    Item {
        id: head
        width: parent.width
        height: Theme.px(56)
        UiText {
            x: Theme.px(20)
            height: parent.height
            text: "Settings"
            size: 17
            tight: true
            font.weight: Font.Medium
        }
        IconButton {
            x: parent.width - Theme.px(20) - width
            anchors.verticalCenter: parent.verticalCenter
            icon: "close"
            iconSize: 18
            onClicked: menu.close()
        }
        Rule {
            anchors.bottom: parent.bottom
        }
    }

    // The filters stay put above the deck, as on the web; when the Type and
    // Test lists are open they page on their own, up to most of the screen.
    Pager {
        id: pager
        y: head.height
        width: parent.width
        height: Math.min(body.height, (parent.height - y) * 0.62)
        // Where the shown part ends: under the last whole row, so no row is
        // left cut in half at the rule.
        readonly property real shown: {
            contentY;
            return maxY > 0 ? lineTop(contentY + height) - contentY : height;
        }

        // Section
        Item {
            width: pager.width
            height: Theme.px(28) + 2 * Theme.px(12)
            Row {
                x: Theme.px(16)
                height: parent.height
                spacing: Theme.px(6)
                UiText {
                    height: parent.height
                    text: "Section"
                    size: 13
                    color: Theme.inkFaint
                    rightPadding: Theme.px(4)
                }
                Repeater {
                    model: Deck.SECTION_FILTERS
                    delegate: Chip {
                        objectName: "section_" + modelData.code
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        on: menu.settings.sections.indexOf(modelData.code) >= 0
                        onClicked: menu.toggleSection(modelData.code)
                    }
                }
            }
            TextLink {
                visible: menu.settings.sections.length > 0
                x: parent.width - Theme.px(16) - width
                anchors.verticalCenter: parent.verticalCenter
                text: "Clear"
                onClicked: menu.clearSections()
            }
            Rule {
                anchors.bottom: parent.bottom
            }
        }

        // Type
        FilterDropdown {
            label: "Type"
            summary: Deck.summarizeTypes(menu.settings.types)
            active: menu.settings.types.length > 0
            onClear: menu.clearTypes()
            Repeater {
                model: Deck.TYPE_GROUPS
                delegate: Column {
                    width: parent.width
                    SectionLabel {
                        height: Theme.px(11) * 1.5 + Theme.px(8) + Theme.px(6)
                        topPadding: Theme.px(8) - Theme.px(6)
                        text: modelData.label
                        size: 11
                    }
                    Flow {
                        width: parent.width
                        spacing: Theme.px(6)
                        Repeater {
                            model: modelData.items
                            delegate: Chip {
                                text: modelData.label
                                on: menu.settings.types.indexOf(modelData.key) >= 0
                                onClicked: menu.toggleType(modelData.key)
                            }
                        }
                    }
                }
            }
        }

        // Difficulty
        Item {
            width: pager.width
            height: Theme.px(28) + 2 * Theme.px(12)
            Row {
                x: Theme.px(16)
                height: parent.height
                spacing: Theme.px(6)
                UiText {
                    height: parent.height
                    text: "Difficulty"
                    size: 13
                    color: Theme.inkFaint
                    rightPadding: Theme.px(4)
                }
                Repeater {
                    model: Theme.DIFFICULTY_LEVELS
                    delegate: Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        on: menu.settings.levels.indexOf(modelData) >= 0
                        onClicked: menu.toggleLevel(modelData)
                    }
                }
            }
            TextLink {
                visible: menu.settings.levels.length > 0
                x: parent.width - Theme.px(16) - width
                anchors.verticalCenter: parent.verticalCenter
                text: "Clear"
                onClicked: menu.clearLevels()
            }
            Rule {
                anchors.bottom: parent.bottom
            }
        }

        // Test
        FilterDropdown {
            visible: menu.drilledTests.length + menu.heldOutTests.length > 1
            label: "Test"
            summary: Deck.summarizeTests(menu.settings.tests)
            active: menu.settings.tests.length > 0
            onClear: menu.clearTests()
            Item {
                width: parent.width
                height: Theme.px(4)
            }
            Flow {
                width: parent.width
                spacing: Theme.px(6)
                Repeater {
                    model: menu.drilledTests
                    delegate: Chip {
                        text: modelData.test === null ? "—" : modelData.test
                        on: menu.settings.tests.indexOf(modelData.test) >= 0
                        onClicked: menu.toggleTest(modelData.test)
                    }
                }
            }
            // The reserved tests are listed so it's clear what drilling
            // leaves out, but can't be picked until the switch puts them in.
            Item {
                visible: menu.heldOutTests.length > 0
                width: parent.width
                height: Theme.px(12) + Theme.px(28) + Theme.px(6)
                Row {
                    y: Theme.px(12)
                    height: Theme.px(28)
                    spacing: Theme.px(8)
                    SectionLabel {
                        height: parent.height
                        text: "Held out"
                        size: 11
                    }
                    TextLink {
                        visible: !menu.settings.heldOut
                        text: "Include"
                        onClicked: menu.toggleHeldOut()
                    }
                }
            }
            Flow {
                visible: menu.heldOutTests.length > 0
                width: parent.width
                spacing: Theme.px(6)
                Repeater {
                    model: menu.heldOutTests
                    delegate: Chip {
                        text: modelData.test === null ? "—" : modelData.test
                        on: menu.settings.heldOut && menu.settings.tests.indexOf(modelData.test) >= 0
                        enabled: menu.settings.heldOut
                        onClicked: menu.toggleTest(modelData.test)
                    }
                }
            }
        }

        // Switches
        Item {
            visible: menu.heldOutTests.length > 0
            width: pager.width
            height: Theme.px(13) * 1.5 + 2 * Theme.px(12)
            UiText {
                x: Theme.px(16)
                height: parent.height
                text: "Drill held-out tests"
                size: 13
                color: Theme.inkFaint
            }
            Switch {
                x: parent.width - Theme.px(16) - width
                anchors.verticalCenter: parent.verticalCenter
                on: menu.settings.heldOut
                onClicked: menu.toggleHeldOut()
            }
            Rule {
                anchors.bottom: parent.bottom
            }
        }
        Item {
            width: pager.width
            height: Theme.px(13) * 1.5 + 2 * Theme.px(12)
            UiText {
                x: Theme.px(16)
                height: parent.height
                text: "Shuffle"
                size: 13
                color: Theme.inkFaint
            }
            Switch {
                x: parent.width - Theme.px(16) - width
                anchors.verticalCenter: parent.verticalCenter
                on: menu.settings.shuffle
                onClicked: menu.toggleShuffle()
            }
            Rule {
                anchors.bottom: parent.bottom
            }
        }
        Item {
            width: pager.width
            height: Theme.px(13) * 1.5 + 2 * Theme.px(12)
            UiText {
                x: Theme.px(16)
                height: parent.height
                text: menu.deckSize + " question" + (menu.deckSize === 1 ? "" : "s")
                      + (menu.filtered ? " (filtered from " + menu.totalSize + ")" : "")
                size: 13
                color: Theme.inkFaint
            }
            Rule {
                anchors.bottom: parent.bottom
            }
        }

    }

    Rectangle {
        y: pager.y + pager.shown
        width: parent.width
        height: pager.height - pager.shown
        color: Theme.surface
        MouseArea { anchors.fill: parent }
    }

    Rule {
        visible: pager.maxY > 0
        y: pager.y + pager.shown - height
        z: 1
    }

    Pager {
        id: list
        y: pager.y + pager.shown
        width: parent.width
        height: parent.height - y

        Repeater {
            model: menu.visibleTests
            delegate: Column {
                id: testBlock
                property var test: modelData
                width: list.width

                Item {
                    width: parent.width
                    height: Theme.px(12) * 1.5 + 2 * Theme.px(8)
                    Row {
                        x: Theme.px(16)
                        height: parent.height
                        spacing: Theme.px(8)
                        SectionLabel {
                            height: parent.height
                            text: testBlock.test.label
                        }
                        Rectangle {
                            visible: testBlock.test.heldOut
                            anchors.verticalCenter: parent.verticalCenter
                            width: badge.implicitWidth + 2 * Theme.px(6)
                            height: badge.implicitHeight + 2 * Theme.px(2)
                            radius: Theme.px(4)
                            color: Theme.chip
                            SectionLabel {
                                id: badge
                                anchors.centerIn: parent
                                text: "Held out"
                                size: 10
                            }
                        }
                    }
                    UiText {
                        x: parent.width - Theme.px(16) - width
                        height: parent.height
                        text: testBlock.test.count
                        size: 12
                        color: Theme.inkFaint
                    }
                }

                Repeater {
                    model: testBlock.test.sections
                    delegate: Column {
                        id: sectionBlock
                        property var section: modelData
                        readonly property bool open: section.key === menu.shownKey
                        width: parent.width

                        Pressable {
                            width: parent.width
                            height: Theme.px(13.5) * 1.5 + 2 * Theme.px(8)
                            onClicked: menu.openKey = sectionBlock.open ? null : sectionBlock.section.key
                            Icon {
                                x: Theme.px(16)
                                anchors.verticalCenter: parent.verticalCenter
                                name: "chevron"
                                size: 16
                                rotation: sectionBlock.open ? 0 : -90
                                opacity: 0.6
                            }
                            UiText {
                                x: Theme.px(16 + 16 + 8)
                                width: count.x - x - Theme.px(8)
                                height: parent.height
                                text: sectionBlock.section.label
                                size: 13.5
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            UiText {
                                id: count
                                x: parent.width - Theme.px(16) - width
                                height: parent.height
                                text: sectionBlock.section.qs.length
                                size: 12.5
                                color: Theme.inkFaint
                            }
                        }

                        Repeater {
                            model: sectionBlock.open ? sectionBlock.section.qs : []
                            delegate: Pressable {
                                id: row
                                readonly property var q: Deck.questions[modelData]
                                readonly property bool here: modelData === menu.currentI
                                readonly property var pick: menu.answers[modelData]
                                width: parent.width
                                height: Theme.px(13.5) * 1.5 + 2 * Theme.px(8)
                                color: here ? Theme.chip : "transparent"
                                onClicked: {
                                    menu.jump(modelData);
                                    menu.close();
                                }
                                onHereChanged: if (here) menu.currentRow = row
                                Component.onCompleted: if (here) menu.currentRow = row

                                Rectangle {
                                    id: num
                                    x: Theme.px(32)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.px(24)
                                    height: width
                                    radius: Theme.px(6)
                                    color: row.here ? Theme.surface : Theme.chip
                                    UiText {
                                        anchors.centerIn: parent
                                        text: row.q.number === null ? "•" : row.q.number
                                        size: 12
                                        font.weight: Font.Medium
                                    }
                                }
                                UiText {
                                    x: num.x + num.width + Theme.px(12)
                                    width: marks.x - x - Theme.px(12)
                                    height: parent.height
                                    text: Deck.label(modelData)
                                    size: 13.5
                                    elide: Text.ElideRight
                                }
                                Row {
                                    id: marks
                                    x: parent.width - Theme.px(16) - width
                                    height: parent.height
                                    spacing: Theme.px(8)
                                    DifficultyMeter {
                                        anchors.verticalCenter: parent.verticalCenter
                                        value: row.q.difficulty
                                        compact: true
                                    }
                                    // Right: a black dot. Wrong: a ring.
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.px(8)
                                        height: width
                                        radius: width / 2
                                        color: row.pick !== undefined && row.pick === row.q.correct ? Theme.correct : "transparent"
                                        border.width: row.pick !== undefined && row.pick !== row.q.correct ? Theme.lineWidth : 0
                                        border.color: Theme.wrong
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        UiText {
            visible: menu.visibleTests.length === 0
            x: Theme.px(16)
            height: Theme.px(13.5) * 1.5 + 2 * Theme.px(12)
            text: "Nothing matches these filters."
            size: 13.5
            color: Theme.inkFaint
        }
        Item {
            width: 1
            height: Theme.px(8)
        }
    }
}
