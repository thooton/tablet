import QtQuick

// A row of chips that may be wider than its space, as the web app's
// overflow-x strips are (the group tabs, a section's question palette).
// Rather than scroll, it shifts by whole stretches so the current chip is
// always in view, the way the web app scrolls it into view. It starts at a
// chip and shows only the chips that fit whole: half a "10" reads as "1".
Item {
    id: strip
    default property alias chips: row.data
    property Item current: null
    property alias spacing: row.spacing
    property real shift: 0

    implicitHeight: row.height

    // (Not by `visible`, which is false while the strip itself is hidden;
    // a Repeater has no width.)
    function chipList() {
        var out = [];
        for (var n = 0; n < row.children.length; n++)
            if (row.children[n].width > 0)
                out.push(row.children[n]);
        return out;
    }

    function ensureVisible() {
        var list = chipList();
        if (!current || row.width <= width) {
            shift = 0;
        } else {
            var left = current.x, right = current.x + current.width;
            var s = shift;
            if (right - s > width)
                s = Math.min(row.width - width, right - width + width / 3);
            else if (left - s < 0)
                s = Math.max(0, left - width / 3);
            // Start on a chip, never past the current one.
            for (var n = 0; n < list.length; n++)
                if (list[n].x >= s - 0.5 || list[n] === current) {
                    s = list[n].x;
                    break;
                }
            shift = s;
        }
        // Only the chips that fit whole are shown.
        var fit = 0;
        for (var k = 0; k < list.length; k++)
            if (list[k].x >= shift - 0.5 && list[k].x + list[k].width - shift <= width + 0.5)
                fit = list[k].x + list[k].width - shift;
        view.width = row.width <= width ? width : fit;
    }
    onCurrentChanged: Qt.callLater(ensureVisible)
    onWidthChanged: Qt.callLater(ensureVisible)

    Item {
        id: view
        width: strip.width
        height: strip.height
        clip: true

        Row {
            id: row
            x: -strip.shift
            anchors.verticalCenter: parent.verticalCenter
            onWidthChanged: Qt.callLater(strip.ensureVisible)
        }
    }
}
