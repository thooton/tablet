import QtQuick
import "../js/theme.js" as Theme

// Header.jsx at phone width: h-14 px-3, the falcon in a 36 px box, the title
// (text-[17px] font-medium tracking-tight), a 1 px rule below. Buttons go in
// as children, right-aligned with gap-1.
Item {
    id: header
    property string title
    property string subtitle
    default property alias actions: actionRow.data

    width: parent ? parent.width : 0
    height: Theme.px(56)

    Item {
        id: mark
        x: Theme.px(12)
        width: Theme.px(36)
        height: Theme.px(36)
        anchors.verticalCenter: parent.verticalCenter
        Icon {
            anchors.centerIn: parent
            name: "falcon"
            size: 26
        }
    }

    UiText {
        id: titleText
        x: mark.x + mark.width + Theme.px(10)
        width: Math.min(implicitWidth, actionRow.x - x - Theme.px(8))
        height: parent.height - Theme.lineWidth
        text: header.title
        size: 17
        tight: true
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    UiText {
        visible: header.subtitle !== ""
        x: titleText.x + titleText.width + Theme.px(12)
        width: Math.max(0, actionRow.x - x - Theme.px(8))
        height: parent.height - Theme.lineWidth
        text: header.subtitle
        size: 14.5
        color: Theme.inkSoft
        elide: Text.ElideRight
    }

    Row {
        id: actionRow
        x: parent.width - Theme.px(12) - width
        y: (parent.height - Theme.lineWidth - height) / 2
        height: Theme.px(36)
        spacing: Theme.px(4)
    }

    Rule {
        anchors.bottom: parent.bottom
    }
}
