import QtQuick
import "../js/theme.js" as Theme

// One story in the library: title, one-line summary, then the level tag, a
// row of dots (one per ~70 words, filled up to the reading position) and
// the % read once the story has been opened. A thin rule separates the rows.
Item {
    id: row
    property var story
    property QtObject fonts

    height: Theme.rowHeight

    readonly property int dotCount: Math.min(60, Math.max(6, Math.round(story.words / 70)))
    readonly property int dotsRead: story.finished ? dotCount
                                                   : Math.round(Math.min(1, story.progress) * dotCount)

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 2
        color: Theme.rule
    }

    // The 150 px block (title 56 + summary 42 + 12 + progress 40) is centred
    // in the row above its 2 px rule.
    Column {
        y: Math.round((Theme.rowHeight - 2 - 150) / 2)
        width: parent.width

        Text {
            objectName: "rowTitle"
            width: parent.width
            height: 56
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: row.story.title
            color: Theme.ink
            font.family: row.fonts.sans
            font.pixelSize: 47
        }
        Text {
            width: parent.width
            height: 42
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: row.story.description
            color: Theme.ink2
            font.family: row.fonts.sans
            font.pixelSize: 32
        }
        Item { width: 1; height: 12 }
        Row {
            height: 40
            spacing: 20

            Rectangle {
                visible: row.story.level !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: tag.implicitWidth + 2 * 9 + 4
                height: 23 + 6 + 5 + 4
                color: "transparent"
                border.width: 2
                border.color: Theme.ink
                Text {
                    id: tag
                    x: 2 + 9
                    y: 2 + 6
                    height: 23
                    verticalAlignment: Text.AlignVCenter
                    text: row.story.level
                    color: Theme.ink
                    font.family: row.fonts.sansBold
                    font.weight: Font.Bold
                    font.pixelSize: 23
                    font.letterSpacing: 23 * 0.04
                }
            }
            Row {
                objectName: "rowDots"
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: row.dotCount
                    delegate: Item {
                        width: 15
                        height: 10
                        Rectangle {
                            readonly property bool read: index < row.dotsRead
                            anchors.centerIn: parent
                            width: read ? 10 : 6
                            height: width
                            radius: width / 2
                            color: read ? Theme.ink : Theme.dotUnread
                        }
                    }
                }
            }
            Text {
                objectName: "rowStatus"
                visible: row.story.started || row.story.finished
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: (row.story.finished ? 100 : Math.round(row.story.progress * 100)) + "%"
                color: Theme.ink2
                font.family: row.fonts.sans
                font.pixelSize: 27
            }
        }
    }
}
