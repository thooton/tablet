import QtQuick
import "../js/theme.js" as Theme

// Bottom half of the toolbar: page number, time left and a slider that
// jumps through the story (it moves on release, to spare the e-ink). A
// story too long to lay out whole has no page numbers (pageCount 0): its
// slider goes by percent.
Rectangle {
    id: bar
    property int pageIndex: 0
    property int pageCount: 1
    property int minutesLeft: 0
    property int percent: 0
    property QtObject fonts
    signal seek(int pageIndex)
    signal seekPercent(int percent)

    readonly property bool paged: pageCount > 0
    readonly property int steps: paged ? pageCount : 101
    // While dragging: the page (or percent) the knob points at.
    property int preview: -1
    readonly property int shown: preview >= 0 ? preview : (paged ? pageIndex : percent)
    readonly property real fraction: steps > 1 ? shown / (steps - 1) : 0

    width: Theme.screenWidth
    height: 292
    color: Theme.paper

    MouseArea { anchors.fill: parent }  // taps on the bar stay on the bar

    Rectangle {
        width: parent.width
        height: 3
        color: Theme.ink
    }
    Text {
        objectName: "toolbarPage"
        y: 66
        width: parent.width
        height: 40
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: bar.paged ? "Página " + (bar.shown + 1) + " de " + bar.pageCount : bar.shown + "%"
        color: Theme.ink
        font.family: bar.fonts.sansSemi
        font.weight: Font.DemiBold
        font.pixelSize: 34
    }
    Text {
        objectName: "toolbarTime"
        y: 118
        width: parent.width
        height: 38
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: (bar.minutesLeft <= 1 ? "1 min restante" : bar.minutesLeft + " min restantes")
              + (bar.paged ? "  |  " + bar.percent + "%" : "")
        color: Theme.ink2
        font.family: bar.fonts.sans
        font.pixelSize: 30
    }

    Item {
        id: slider
        objectName: "slider"
        x: 216
        y: 204
        width: parent.width - 432
        height: 60

        Rectangle {
            y: 28
            width: parent.width
            height: 4
            color: Theme.ink3
        }
        Rectangle {
            y: 25
            width: parent.width * bar.fraction
            height: 10
            color: Theme.ink
        }
        Rectangle {
            x: parent.width * bar.fraction - width / 2
            y: 4
            width: 52
            height: 52
            radius: 26
            color: Theme.white
            border.width: 4
            border.color: Theme.ink
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -30
            function pageAt(mx) {
                var f = Math.max(0, Math.min(1, (mx - 30) / slider.width));
                return Math.round(f * (bar.steps - 1));
            }
            onPressed: mouse => bar.preview = pageAt(mouse.x)
            onPositionChanged: mouse => bar.preview = pageAt(mouse.x)
            onReleased: mouse => {
                var target = pageAt(mouse.x);
                bar.preview = -1;
                if (bar.paged)
                    bar.seek(target);
                else if (target !== bar.percent)
                    bar.seekPercent(target);
            }
            onCanceled: bar.preview = -1
        }
    }
}
