import QtQuick
import "../js/theme.js" as Theme

// One of Anki's histograms in black: a bar per bin, the tallest's count at
// the top of the axis, labels under some bins (null for none), or, given
// one more label than bins, under the edges between them.
Item {
    id: bars
    property var values: []
    property var labels: []
    property QtObject fonts
    property int textSize: 28

    readonly property int peak: {
        var m = 0;
        for (var i = 0; i < values.length; i++)
            m = Math.max(m, values[i]);
        return m;
    }
    readonly property bool edges: labels.length === values.length + 1
    readonly property real axisX: topLabel.implicitWidth + 16
    readonly property real base: height - textSize - 18
    readonly property real binWidth: values.length ? (width - axisX) / values.length : 0

    Text {
        id: topLabel
        anchors.right: axis.left
        anchors.rightMargin: 10
        y: 0
        text: bars.peak
        color: Theme.subtle
        font.family: bars.fonts.sans
        font.pixelSize: bars.textSize
    }
    Text {
        anchors.right: axis.left
        anchors.rightMargin: 10
        y: bars.base - implicitHeight * 0.8
        text: "0"
        color: Theme.subtle
        font.family: bars.fonts.sans
        font.pixelSize: bars.textSize
    }
    Rectangle {
        id: axis
        x: bars.axisX
        y: topLabel.implicitHeight / 2
        width: 2
        height: bars.base - y
        color: Theme.ink
    }
    Rectangle {
        x: bars.axisX
        y: bars.base
        width: bars.width - bars.axisX
        height: 2
        color: Theme.ink
    }
    Repeater {
        model: bars.values.length
        Rectangle {
            readonly property real h: bars.peak > 0 && bars.values[index] > 0
                ? Math.max(3, (bars.base - axis.y) * bars.values[index] / bars.peak) : 0
            visible: h > 0
            x: bars.axisX + index * bars.binWidth + bars.binWidth * 0.12
            width: bars.binWidth * 0.76
            y: bars.base - h
            height: h
            color: Theme.ink
        }
    }
    Repeater {
        model: bars.labels.length
        Text {
            readonly property real at: bars.axisX + index * bars.binWidth + (bars.edges ? 0 : bars.binWidth / 2)
            visible: bars.labels[index] !== null && bars.labels[index] !== undefined
            x: !bars.edges || (index > 0 && index < bars.values.length) ? at - implicitWidth / 2
                : index === 0 ? at : at - implicitWidth
            y: bars.base + 10
            text: visible ? bars.labels[index] : ""
            color: Theme.subtle
            font.family: bars.fonts.sans
            font.pixelSize: bars.textSize
        }
    }
}
