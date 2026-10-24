import QtQuick
import "../js/theme.js" as Theme
import "../js/format.js" as Format

// ExplanationPane.jsx, stacked below the question: the heading row, the
// introduction, then a note per answer in A–E order with its letter in the
// gutter. The credited answer's letter is green on the web; here it's the
// one in heavy black while the rest stay faint.
Column {
    id: pane
    property var question: null

    readonly property var parsed: Format.parseExplanation(question ? question.explanation : "")

    width: parent ? parent.width : 0

    Rule {}
    Item {
        width: parent.width
        height: Theme.px(56)
        UiText {
            x: Theme.px(20)
            height: parent.height
            text: "Explanation"
            size: 17
            tight: true
            font.weight: Font.Medium
        }
    }
    Rule {}

    Column {
        x: Theme.px(20)
        width: parent.width - 2 * Theme.px(20)

        Item {
            width: 1
            height: Theme.px(24)
        }
        ExplanationBlocks {
            model: Format.explanationModel(pane.parsed.intro)
        }
        Item {
            width: 1
            height: Theme.px(28)
        }
        Column {
            width: parent.width
            spacing: Theme.px(20)
            Repeater {
                model: pane.parsed.notes
                delegate: Item {
                    readonly property bool credited: pane.question && modelData.letter === pane.question.correct
                    width: parent.width
                    height: noteBody.height
                    UiText {
                        width: Theme.px(16)
                        height: Math.round(Theme.readingSize * Theme.readingLine)
                        verticalAlignment: Text.AlignTop
                        topPadding: 1
                        text: modelData.letter
                        size: 16
                        font.weight: parent.credited ? Font.Bold : Font.Medium
                        color: parent.credited ? Theme.correct : Theme.inkFaint
                    }
                    ExplanationBlocks {
                        id: noteBody
                        x: Theme.px(16) + Theme.px(12)
                        width: parent.width - x
                        gap: Theme.px(12)
                        model: Format.explanationModel(modelData.paras)
                    }
                }
            }
        }
        Item {
            width: 1
            height: Theme.px(40)
        }
    }
}
