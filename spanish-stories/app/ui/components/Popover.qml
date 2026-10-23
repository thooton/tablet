import QtQuick
import "../js/theme.js" as Theme

// The translation card: a white bordered box holding only the English
// (stacked, no dividers), with a pointer to the highlighted phrase. It sits
// below the phrase when it fits, otherwise above, and stays 58 px from the
// screen edges. `anchorRect` is the highlighted phrase in screen pixels.
Item {
    id: pop
    property var anchorRect: ({ x: 0, y: 0, width: 0, height: 0 })
    property var translations: []
    property QtObject fonts

    readonly property real maxTextWidth: 900 - 6 - 108
    readonly property real widest: {
        var w = 0;
        for (var i = 0; i < translations.length; i++)
            w = Math.max(w, measure.advanceWidth(translations[i]));
        return Math.ceil(w) + 2;
    }
    readonly property real textWidth: Math.min(widest, maxTextWidth)

    width: Math.max(360, textWidth + 6 + 108)
    height: 3 + 40 + lines.height + 34 + 3

    readonly property real cx: anchorRect.x + anchorRect.width / 2
    readonly property bool below: anchorRect.y + anchorRect.height + 40 + height < Theme.screenHeight - 140
    x: Math.min(Math.max(cx - width / 2, 58), Theme.screenWidth - 58 - width)
    y: below ? anchorRect.y + anchorRect.height + 34 : anchorRect.y - 34 - height

    FontMetrics {
        id: measure
        font.family: pop.fonts.sansMedium
        font.weight: Font.Medium
        font.pixelSize: 44
    }

    MouseArea { anchors.fill: parent }  // a tap on the card does nothing

    Rectangle {
        anchors.fill: parent
        color: Theme.white
        border.width: 3
        border.color: Theme.ink
    }

    // Pointer: a bordered diamond whose inner half is painted over, so its
    // two outer edges join the box border.
    Rectangle {
        width: 37
        height: 37
        x: pop.cx - pop.x - width / 2
        y: (pop.below ? 1.5 : pop.height - 1.5) - height / 2
        rotation: 45
        color: Theme.white
        border.width: 3
        border.color: Theme.ink
    }
    Rectangle {
        x: pop.cx - pop.x - 26
        y: pop.below ? 0 : pop.height - 30
        width: 52
        height: 30
        color: Theme.white
    }

    Column {
        id: lines
        x: 3 + 54
        y: 3 + 40
        width: pop.width - 6 - 108
        spacing: 16
        Repeater {
            model: pop.translations
            delegate: Text {
                objectName: "translation"
                width: lines.width
                text: modelData
                wrapMode: Text.Wrap
                color: Theme.ink
                font.family: pop.fonts.sansMedium
                font.weight: Font.Medium
                font.pixelSize: 44
            }
        }
    }
}
