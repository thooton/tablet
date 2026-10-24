import QtQuick
import "../js/theme.js" as Theme

// ExamSection.jsx's question palette: every question of the section, the
// current one navy, answered ones grey, the rest outlined, with a dot on
// the ones bookmarked.
Strip {
    id: grid
    property var questions: []
    property var numbers: []
    property int currentIndex: 0
    property var answers: ({})
    property var flags: ({})
    signal jump(int index)

    spacing: Theme.px(6)
    current: repeater.count > grid.currentIndex ? repeater.itemAt(grid.currentIndex) : null

    Repeater {
        id: repeater
        model: grid.questions
        delegate: Pressable {
            readonly property bool here: index === grid.currentIndex
            readonly property bool answered: grid.answers[modelData] !== undefined
            width: Math.max(Theme.px(32), num.implicitWidth + 2 * Theme.px(6))
            height: Theme.px(32)
            radius: Theme.px(6)
            color: here ? Theme.navy : answered ? Theme.chip : "transparent"
            border.width: here || answered ? 0 : Theme.lineWidth
            border.color: Theme.line
            onClicked: grid.jump(index)
            UiText {
                id: num
                anchors.centerIn: parent
                text: grid.numbers[index] == null ? index + 1 : grid.numbers[index]
                size: 12.5
                font.weight: Font.Medium
                color: parent.here ? Theme.white : parent.answered ? Theme.ink : Theme.inkFaint
            }
            Rectangle {
                visible: grid.flags[modelData] === true
                width: Theme.px(6)
                height: width
                radius: width / 2
                x: parent.width - width + Theme.px(2)
                y: -Theme.px(2)
                color: Theme.ink
                border.width: 1
                border.color: Theme.surface
            }
        }
    }
}
