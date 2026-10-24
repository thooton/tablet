import QtQuick
import "../js/theme.js" as Theme
import "../js/deck.js" as Deck

// ExamSetup.jsx: which test (held-out ones first), and whether the clock
// is enforced.
Pager {
    id: setup
    signal start(var test, bool timed)

    property string testKey: {
        for (var i = 0; i < Deck.exams.length; i++)
            if (Deck.exams[i].heldOut)
                return Deck.exams[i].key;
        return Deck.exams.length ? Deck.exams[0].key : "";
    }
    property bool timed: true
    readonly property var exam: Deck.exams.filter(function (e) { return e.key === setup.testKey; })[0] || null

    Column {
        x: Theme.px(20)
        width: parent.width - 2 * Theme.px(20)

        Item { width: 1; height: Theme.px(24) }

        Repeater {
            model: [
                { label: "Held out", list: Deck.exams.filter(function (e) { return e.heldOut; }) },
                { label: "Drilled", list: Deck.exams.filter(function (e) { return !e.heldOut; }) }
            ]
            delegate: Column {
                visible: modelData.list.length > 0
                width: parent.width
                Item { width: 1; height: index === 0 ? 0 : Theme.px(32) }
                SectionLabel {
                    text: modelData.label
                }
                Item { width: 1; height: Theme.px(12) }
                Flow {
                    width: parent.width
                    spacing: Theme.px(8)
                    Repeater {
                        model: modelData.list
                        delegate: Chip {
                            big: true
                            text: modelData.test
                            on: modelData.key === setup.testKey
                            onClicked: setup.testKey = modelData.key
                        }
                    }
                }
            }
        }

        Item { width: 1; height: Theme.px(32) }
        SectionLabel {
            text: "Timing"
        }
        Item { width: 1; height: Theme.px(12) }
        Rectangle {
            width: segments.width + 2 * Theme.px(4)
            height: segments.height + 2 * Theme.px(4)
            radius: Theme.px(8)
            color: Theme.chip
            Row {
                id: segments
                x: Theme.px(4)
                y: Theme.px(4)
                Repeater {
                    model: [true, false]
                    delegate: Pressable {
                        readonly property bool on: setup.timed === modelData
                        width: segLabel.implicitWidth + 2 * Theme.px(20)
                        height: Theme.px(36)
                        radius: Theme.px(6)
                        color: on ? Theme.surface : "transparent"
                        border.width: on ? Theme.lineWidth : 0
                        border.color: Theme.ink
                        onClicked: setup.timed = modelData
                        UiText {
                            id: segLabel
                            anchors.centerIn: parent
                            text: modelData ? "Timed" : "Untimed"
                            size: 14
                            font.weight: Font.Medium
                            color: parent.on ? Theme.ink : Theme.inkSoft
                        }
                    }
                }
            }
        }

        Item { width: 1; height: Theme.px(36) }
        PillButton {
            objectName: "startButton"
            text: "Start"
            enabled: setup.exam !== null
            onClicked: setup.start(setup.exam.test, setup.timed)
        }
        Item { width: 1; height: Theme.px(40) }
    }
}
