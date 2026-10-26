import QtQuick
import "../js/theme.js" as Theme

// What colour says in Anki, as a shape: New a triangle, Learning a square,
// To Review a circle, solid black. Faint for a queue with nothing in it.
Item {
    id: mark
    property int queue: 0          // 0 New, 1 Learning, 2 Review
    property color color: Theme.ink
    property int size: 30

    width: size
    height: size

    onColorChanged: triangle.requestPaint()

    Canvas {
        id: triangle
        anchors.fill: parent
        visible: mark.queue === 0
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = mark.color;
            ctx.beginPath();
            ctx.moveTo(width / 2, height * 0.06);
            ctx.lineTo(width, height * 0.94);
            ctx.lineTo(0, height * 0.94);
            ctx.closePath();
            ctx.fill();
        }
        onVisibleChanged: requestPaint()
    }
    Rectangle {
        visible: mark.queue === 1
        anchors.centerIn: parent
        width: mark.size * 0.84
        height: width
        color: mark.color
    }
    Rectangle {
        visible: mark.queue === 2
        anchors.fill: parent
        radius: width / 2
        color: mark.color
    }
}
