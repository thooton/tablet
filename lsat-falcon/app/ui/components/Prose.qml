import QtQuick
import "../js/theme.js" as Theme

// Prose.jsx: paragraphs from format.prose(). An indented passage needs only
// a hairline between paragraphs (mt-2); unindented prose needs the gap
// (mt-4) to show where one ends. "Passage A" / "Passage B" are bold labels.
Column {
    id: prose
    property var paragraphs: []

    width: parent ? parent.width : 0

    Repeater {
        model: prose.paragraphs
        delegate: Item {
            readonly property bool isLabel: modelData.kind === "label"
            readonly property real gap: index === 0 ? 0 : Theme.px(isLabel ? 28 : modelData.indent === "passage" ? 8 : 16)
            width: prose.width
            height: gap + para.height + (isLabel ? Theme.px(8) : 0)

            RichPara {
                id: para
                y: parent.gap
                html: modelData.html
                indent: modelData.indent
                font.weight: parent.isLabel ? Font.Bold : Font.Normal
            }
        }
    }
}
