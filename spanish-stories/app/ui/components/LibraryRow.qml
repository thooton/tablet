import QtQuick
import "../js/theme.js" as Theme

// One story in the library: level badge, title, one-line summary, then the
// word count and Nuevo / a progress bar with % / Terminado. A thin rule
// separates the rows.
Item {
    id: row
    property var story
    property QtObject fonts

    height: Theme.rowHeight

    // The 133 px block (title 56 + summary 40 + 10 + meta 27) is centred in
    // the row above its 2 px rule.
    readonly property real blockTop: Math.round((Theme.rowHeight - 2 - 133) / 2)

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 2
        color: Theme.rule
    }

    Rectangle {
        y: row.blockTop
        width: 108
        height: 58
        radius: 8
        color: Theme.ink
        visible: row.story.level !== ""
        Text {
            anchors.centerIn: parent
            text: row.story.level
            color: Theme.white
            font.family: row.fonts.sansBold
            font.weight: Font.Bold
            font.pixelSize: 30
            font.letterSpacing: 1.2
        }
    }

    Column {
        x: 108 + 38
        y: row.blockTop
        width: parent.width - x

        Text {
            objectName: "rowTitle"
            width: parent.width
            height: 56
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: row.story.title
            color: Theme.ink
            font.family: row.fonts.sansSemi
            font.weight: Font.DemiBold
            font.pixelSize: 46
        }
        Text {
            width: parent.width
            height: 40
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: row.story.description
            color: Theme.ink2
            font.family: row.fonts.sans
            font.pixelSize: 28
        }
        Item { width: 1; height: 10 }
        Row {
            height: 27
            spacing: 22

            Text {
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: row.story.words + " palabras"
                color: Theme.ink2
                font.family: row.fonts.sans
                font.pixelSize: 27
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.story.started
                width: 190
                height: 14
                radius: 7
                color: "transparent"
                border.width: 2
                border.color: Theme.ink
                Rectangle {
                    width: parent.width * Math.min(1, row.story.progress)
                    height: parent.height
                    radius: 7
                    color: Theme.ink
                }
            }
            Text {
                objectName: "rowStatus"
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                readonly property bool strong: !row.story.started || row.story.finished
                text: row.story.finished ? "Terminado"
                                         : row.story.started ? Math.round(row.story.progress * 100) + "%" : "Nuevo"
                color: strong ? Theme.ink : Theme.ink2
                font.family: strong ? row.fonts.sansBold : row.fonts.sans
                font.weight: strong ? Font.Bold : Font.Normal
                font.pixelSize: 27
            }
        }
    }
}
