import QtQuick
import "../js/theme.js" as Theme
import "../js/format.js" as Format

// One answer choice (QuestionPane.jsx): the letter tile, the text, and the
// eliminate button in the right gutter. Answered, the credited choice gets a
// heavy border and a check where the eliminate button was; a wrong pick gets
// a grey border and a cross (green and red on the web). Behind the text, a
// bar shows the share of test takers who chose it.
Pressable {
    id: choice
    property string letter
    property string text
    property bool selected: false
    property bool revealed: false
    property bool isCorrect: false
    property var share: null          // percent, once revealed
    property bool eliminated: false
    property bool showEliminate: false
    property bool strikeMode: false
    signal select
    signal eliminate

    readonly property real pad: Theme.px(12)
    readonly property real borderW: Theme.px(2)
    readonly property bool markCorrect: revealed && isCorrect
    readonly property bool markWrong: revealed && selected && !isCorrect

    height: Math.max(tile.height + 1, body.height) + 2 * Theme.px(10) + 2 * borderW
    radius: Theme.px(12)
    border.width: markCorrect || markWrong ? borderW : 0
    border.color: markCorrect ? Theme.correct : "#8c8c8c"
    onClicked: {
        if (choice.revealed)
            return;
        if (choice.strikeMode)
            choice.eliminate();
        else
            choice.select();
    }

    Rectangle {
        id: tile
        x: choice.borderW + choice.pad
        y: choice.borderW + Theme.px(10) + 1
        width: Theme.px(30)
        height: width
        radius: Theme.px(6)
        opacity: choice.eliminated ? 0.45 : 1
        color: choice.selected ? Theme.navy : Theme.chip
        UiText {
            anchors.centerIn: parent
            text: choice.letter
            size: 14
            font.weight: Font.Medium
            color: choice.selected ? Theme.white : Theme.ink
        }
    }

    Item {
        id: body
        x: tile.x + tile.width + Theme.px(16)
        y: choice.borderW + Theme.px(10)
        width: gutter.x - Theme.px(16) - x
        height: textItem.height

        Rectangle {
            visible: choice.share !== null
            x: -Theme.px(6)
            y: -Theme.px(3)
            height: parent.height + Theme.px(6)
            width: (choice.share || 0) / 100 * parent.width + Theme.px(6)
            radius: Theme.px(6)
            color: choice.isCorrect ? Theme.shareBarCorrect : Theme.shareBar
        }
        RichPara {
            id: textItem
            html: Format.highlight(choice.text, [], 0, false)
            color: choice.eliminated ? Theme.inkFaint : Theme.inkStrong
            font.strikeout: choice.eliminated
        }
    }

    // The right-hand button: eliminate (minus) while working, then the
    // verdict once answered.
    Pressable {
        id: gutter
        width: Theme.px(21)
        height: Theme.px(21)
        x: choice.width - choice.borderW - choice.pad - width
        y: choice.borderW + Theme.px(10) + Theme.px(4)
        visible: choice.showEliminate && !choice.revealed || choice.markCorrect || choice.markWrong
        enabled: !choice.revealed
        disabledOpacity: 1
        slop: Theme.px(12)
        onClicked: choice.eliminate()
        Icon {
            anchors.centerIn: parent
            name: choice.markCorrect ? "check" : choice.markWrong ? "close" : "minus-circle"
            size: 21
            opacity: choice.revealed || choice.eliminated ? 1 : 0.55
        }
    }
}
