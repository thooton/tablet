import QtQuick
import "../js/theme.js" as Theme
import "../js/format.js" as Format

// PassagePane.jsx, stacked: "Section 3, Question 9" in the accent colour,
// the passage or stimulus, then the question card once answered. In a
// practice test the passage's questions follow as chips to jump between.
// (The web app's find-in-passage needs a keyboard and is left out.)
Column {
    id: pane
    property var question: null       // the view model from main.qml
    property bool revealed: false
    property bool passageOnly: false
    property var quote: null          // {text, hit, nonce}
    property var siblings: []         // question indexes, practice tests only
    property var siblingNumbers: []
    property bool jumpable: false
    signal jump(int i)

    readonly property bool alsoQuestion: question && question.section && !passageOnly && question.number
    readonly property var paras: question ? Format.paragraphsOf(question.passage) : []
    readonly property var quoteHit: question && quote ? Format.quoteMark(paras, quote.text, quote.hit) : null
    readonly property var paragraphs: question
                                      ? Format.prose(question.passage, question.isRC ? "passage" : "stimulus",
                                                     quoteHit ? quoteHit.marks : [], false)
                                      : []

    // Where the quoted phrase is, in this pane's coordinates (approximate:
    // its paragraph, then its share of the way through it).
    function quoteY() {
        if (!quoteHit)
            return -1;
        // The Column's children include its Repeater; the paragraphs are
        // the ones with `isLabel`.
        prose.forceLayout();
        var items = [];
        for (var i = 0; i < prose.children.length; i++)
            if (prose.children[i].isLabel !== undefined)
                items.push(prose.children[i]);
        var item = items[quoteHit.para];
        if (!item)
            return -1;
        return prose.y + item.y + item.height * quoteHit.offset;
    }

    width: parent ? parent.width : 0

    Item {
        width: parent.width
        height: Theme.px(28) + Theme.px(20)
        UiText {
            height: Theme.px(28)
            text: !pane.question ? "" : (pane.question.section ? "Section " + pane.question.section : "Stimulus")
                  + (pane.alsoQuestion ? ", Question " + pane.question.number : "")
            size: 17
            tight: true
            font.weight: Font.Medium
            color: Theme.accent
        }
    }

    Prose {
        id: prose
        paragraphs: pane.paragraphs
    }

    // Practice tests list the passage's questions under it.
    Item {
        visible: pane.jumpable && pane.siblings.length > 1
        width: parent.width
        height: visible ? Theme.px(36) + Theme.px(20) + chips.height : 0
        Rule {
            y: Theme.px(36)
        }
        Flow {
            id: chips
            y: Theme.px(36) + Theme.px(20)
            width: parent.width
            spacing: Theme.px(8)
            UiText {
                height: Theme.px(28)
                text: "Passage questions"
                size: 13
                color: Theme.inkFaint
                rightPadding: Theme.px(4)
            }
            Repeater {
                model: pane.siblings
                delegate: Chip {
                    text: pane.siblingNumbers[index] == null ? "•" : pane.siblingNumbers[index]
                    on: pane.question && modelData === pane.question.i
                    onClicked: pane.jump(modelData)
                }
            }
        }
    }

    Item {
        visible: pane.revealed && pane.question !== null
        width: parent.width
        height: visible ? Theme.px(8) + card.height + Theme.px(16) : 0
        QuestionCard {
            id: card
            y: Theme.px(8)
            label: pane.question ? pane.question.label : ""
            number: pane.question && pane.question.number !== null ? pane.question.number : "?"
            difficulty: pane.question ? pane.question.difficulty : 0
        }
    }
}
