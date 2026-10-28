import QtQuick
import "../js/theme.js" as Theme

// BottomBar.jsx: a group's tabs (P for a passage, then its questions), the
// arrows that step through them, and the main button: Continue once you've
// answered (or read the passage), Finish on the last one, Skip otherwise.
Item {
    id: bar
    property bool revealed: false
    property bool isLast: false
    property var siblings: []          // question indexes
    property var numbers: []           // their printed numbers
    property int currentI: -1
    property bool hasPassage: false
    property bool readingPassage: false
    property bool canBack: false
    property bool canForward: false
    signal jump(int i)
    signal showPassage
    signal back
    signal forward
    signal skip
    signal next

    width: parent ? parent.width : 0
    height: Theme.px(64)

    Rule {}

    Strip {
        id: tabs
        visible: bar.siblings.length > 0
        x: Theme.px(16)
        width: right.x - Theme.px(12) - x
        height: parent.height
        spacing: Theme.px(6)
        current: {
            if (bar.readingPassage)
                return passageTab;
            for (var i = 0; i < tabRepeater.count; i++) {
                var item = tabRepeater.itemAt(i);
                if (item && item.selected)
                    return item;
            }
            return null;
        }

        TabChip {
            id: passageTab
            visible: bar.hasPassage
            text: "P"
            selected: bar.readingPassage
            onClicked: bar.showPassage()
        }
        Repeater {
            id: tabRepeater
            model: bar.siblings
            delegate: TabChip {
                text: bar.numbers[index] == null ? (index + 1) : bar.numbers[index]
                selected: modelData === bar.currentI && !bar.readingPassage
                onClicked: bar.jump(modelData)
            }
        }
    }

    Row {
        id: right
        x: parent.width - Theme.px(16) - width
        height: parent.height
        spacing: Theme.px(8)

        StepButton {
            visible: bar.siblings.length > 0
            anchors.verticalCenter: parent.verticalCenter
            icon: "arrow-left"
            enabled: bar.canBack
            onClicked: bar.back()
        }
        StepButton {
            visible: bar.siblings.length > 0
            anchors.verticalCenter: parent.verticalCenter
            icon: "arrow-right"
            enabled: bar.canForward
            onClicked: bar.forward()
        }
        Rectangle {
            visible: bar.siblings.length > 0
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.px(1) + 2 * Theme.px(4)
            height: Theme.px(28)
            color: "transparent"
            Rectangle {
                anchors.centerIn: parent
                width: Theme.lineWidth
                height: parent.height
                color: Theme.line
            }
        }
        PillButton {
            objectName: "mainButton"
            anchors.verticalCenter: parent.verticalCenter
            kind: bar.readingPassage || bar.revealed ? "primary" : "outline"
            text: bar.readingPassage ? "Continue" : bar.revealed ? (bar.isLast ? "Finish" : "Continue") : "Skip"
            onClicked: bar.readingPassage || bar.revealed ? bar.next() : bar.skip()
        }
    }
}
