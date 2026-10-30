import QtQuick
import "../js/theme.js" as Theme
import "../js/deck.js" as Deck

// The stacked passage and question of a practice test — and, in review, the
// explanation — in one pager. A reading-comp question opens on the question,
// with the passage a swipe back.
Pager {
    id: panes
    property var question: null
    property var siblings: []          // the passage's questions in this section
    property string selected: ""
    property bool revealed: false
    property var eliminated: []
    property bool showBookmark: false
    property bool bookmarked: false
    property bool showExplanation: false
    signal select(string letter)
    signal eliminate(string letter)
    signal toggleBookmark
    signal jump(int i)

    property bool strikeMode: false
    property var quote: null

    onQuestionChanged: Qt.callLater(place)

    property string placed: ""
    function layout() {
        passagePane.forceLayout();
        questionPane.forceLayout();
        column.forceLayout();
        panes.body.forceLayout();
    }
    function place() {
        var key = question ? question.i + "" : "";
        if (key === placed)
            return;
        placed = key;
        strikeMode = false;
        quote = null;
        layout();
        if (question && question.isRC) {
            reveal(questionPane, -Theme.px(20), false);
            settling.restart();
        } else {
            reset();
        }
    }
    // A long passage finishes laying out after the first pass, which moves
    // the question: land on it again until the page has settled.
    Timer {
        id: settling
        interval: 400
    }
    function showQuote(text) {
        quote = { text: text, hit: quote && quote.text === text ? quote.hit + 1 : 0,
                  nonce: (quote ? quote.nonce : 0) + 1 };
        Qt.callLater(function () {
            panes.layout();
            var y = passagePane.quoteY();
            if (y >= 0)
                panes.reveal(passagePane, y, true);
        });
    }

    Item {
        width: panes.width
        height: column.height + Theme.px(24)
        onHeightChanged: if (settling.running && panes.question && panes.question.isRC) Qt.callLater(function () {
            panes.layout();
            panes.reveal(questionPane, -Theme.px(20), false);
        })
        Column {
            id: column
            x: Theme.px(20)
            y: Theme.px(24)
            width: parent.width - 2 * Theme.px(20)
            spacing: Theme.px(24)

            PassagePane {
                id: passagePane
                question: panes.question
                revealed: panes.revealed
                quote: panes.quote
                jumpable: true
                siblings: panes.siblings
                siblingNumbers: panes.siblings.map(function (i) { return Deck.questions[i].number; })
                onJump: i => panes.jump(i)
            }
            QuestionPane {
                id: questionPane
                visible: panes.question !== null
                question: panes.question
                selected: panes.selected
                revealed: panes.revealed
                eliminated: panes.eliminated
                strikeMode: panes.strikeMode
                showBookmark: panes.showBookmark
                bookmarked: panes.bookmarked
                quote: panes.quote
                onSelect: letter => panes.select(letter)
                onEliminate: letter => panes.eliminate(letter)
                onToggleStrike: panes.strikeMode = !panes.strikeMode
                onToggleBookmark: panes.toggleBookmark()
                onShowQuote: text => panes.showQuote(text)
            }
        }
    }
    ExplanationPane {
        visible: panes.showExplanation && panes.question !== null && panes.question.explanation !== ""
        question: panes.question
    }
}
