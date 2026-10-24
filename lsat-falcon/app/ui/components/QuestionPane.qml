import QtQuick
import "../js/theme.js" as Theme
import "../js/format.js" as Format

// QuestionPane.jsx, stacked under the passage: the stem, then the choices
// with the tool card floating at their top right. Phrases the stem quotes
// from the passage are links that light the phrase up in the passage.
Column {
    id: pane
    property var question: null
    property string selected: ""
    property bool revealed: false
    property var eliminated: []
    property bool strikeMode: false
    property bool showBookmark: false
    property bool bookmarked: false
    property var quote: null
    signal select(string letter)
    signal eliminate(string letter)
    signal toggleStrike
    signal toggleBookmark
    signal showQuote(string text)

    readonly property var letters: question ? Object.keys(question.answers).sort() : []
    readonly property var quotes: question ? Format.passageQuotes(question.stem, question.passage) : []

    width: parent ? parent.width : 0

    // Answered, the tools move up into a row of their own.
    Item {
        visible: pane.revealed
        width: parent.width
        height: visible ? Theme.px(32) + Theme.px(12) : 0
        Row {
            spacing: Theme.px(4)
            ToolButton {
                visible: pane.showBookmark
                icon: pane.bookmarked ? "bookmark-filled" : "bookmark"
                active: pane.bookmarked
                onClicked: pane.toggleBookmark()
            }
            ToolButton {
                icon: "strike-a"
                active: pane.strikeMode
                onClicked: pane.toggleStrike()
            }
        }
    }

    // The stem. Taps on it go to its links.
    Item {
        id: stem
        property bool tappable: true
        function tap(x, y) {
            for (var i = 0; i < stemProse.children.length; i++) {
                var item = stemProse.children[i];
                if (!item.para)
                    continue;
                var p = item.para.mapFromItem(stem, x, y);
                var link = item.para.linkAt(p.x, p.y);
                if (link && link.indexOf("quote:") === 0) {
                    pane.showQuote(pane.quotes[Number(link.slice(6))].text);
                    return;
                }
            }
        }
        width: parent.width
        height: stemProse.height
        Column {
            id: stemProse
            width: parent.width
            Repeater {
                model: pane.question
                       ? Format.prose(pane.question.stem, "", Format.quoteRefMarks(pane.quotes, pane.quote ? pane.quote.text : ""), false)
                       : []
                delegate: Item {
                    property alias para: p
                    width: stemProse.width
                    height: (index === 0 ? 0 : Theme.px(16)) + p.height
                    RichPara {
                        id: p
                        y: index === 0 ? 0 : Theme.px(16)
                        html: modelData.html
                    }
                }
            }
        }
    }

    // The choices, with a 40 px gutter on the right for the tool card.
    Item {
        width: parent.width
        height: Theme.px(20) + choices.height + Theme.px(40)

        Column {
            id: choices
            y: Theme.px(20)
            x: -Theme.px(12)
            width: parent.width - Theme.px(40) + 2 * Theme.px(12)
            spacing: Theme.px(6)
            Repeater {
                model: pane.letters
                delegate: Choice {
                    objectName: "choice_" + modelData
                    width: choices.width
                    letter: modelData
                    text: pane.question.answers[modelData]
                    selected: pane.selected === modelData
                    revealed: pane.revealed
                    isCorrect: modelData === pane.question.correct
                    share: pane.revealed && pane.question.stats && pane.question.stats[modelData] !== undefined
                           ? pane.question.stats[modelData] : null
                    eliminated: pane.eliminated.indexOf(modelData) >= 0
                    showEliminate: pane.revealed || pane.strikeMode
                    strikeMode: pane.strikeMode && !pane.revealed
                    onSelect: pane.select(modelData)
                    onEliminate: pane.eliminate(modelData)
                }
            }
        }

        Rectangle {
            visible: !pane.revealed
            x: parent.width - width
            y: Theme.px(20) - Theme.px(8)
            z: 2
            width: tools.width + 2 * Theme.px(4) + 2 * border.width
            height: tools.height + 2 * Theme.px(4) + 2 * border.width
            radius: Theme.px(12)
            color: Theme.surface
            border.width: Theme.lineWidth
            border.color: Theme.line
            Column {
                id: tools
                anchors.centerIn: parent
                spacing: Theme.px(4)
                ToolButton {
                    visible: pane.showBookmark
                    icon: pane.bookmarked ? "bookmark-filled" : "bookmark"
                    active: pane.bookmarked
                    onClicked: pane.toggleBookmark()
                }
                ToolButton {
                    icon: "strike-a"
                    active: pane.strikeMode
                    onClicked: pane.toggleStrike()
                }
            }
        }
    }
}
