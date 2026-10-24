import QtQuick

// A row of chips that may be wider than its space, as the web app's
// overflow-x strips are (the group tabs, a section's question palette).
// Rather than scroll, it shifts by whole stretches so the current chip is
// always in view, the way the web app scrolls it into view.
Item {
    id: strip
    default property alias chips: row.data
    property Item current: null
    property alias spacing: row.spacing
    property real shift: 0

    clip: true
    implicitHeight: row.height

    function ensureVisible() {
        if (!current) {
            shift = 0;
            return;
        }
        var left = current.x, right = current.x + current.width;
        if (row.width <= width)
            shift = 0;
        else if (right - shift > width)
            shift = Math.min(row.width - width, right - width + width / 3);
        else if (left - shift < 0)
            shift = Math.max(0, left - width / 3);
    }
    onCurrentChanged: Qt.callLater(ensureVisible)
    onWidthChanged: Qt.callLater(ensureVisible)

    Row {
        id: row
        x: -strip.shift
        anchors.verticalCenter: parent.verticalCenter
        onWidthChanged: Qt.callLater(strip.ensureVisible)
    }
}
