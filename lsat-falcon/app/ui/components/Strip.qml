import QtQuick
import "../js/theme.js" as Theme

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
        fitWhole();
    }

    // Only the chips that fit whole are shown.
    function fitWhole() {
        var list = chipList();
        var fit = 0;
        for (var k = 0; k < list.length; k++)
            if (list[k].x >= shift - 0.5 && list[k].x + list[k].width - shift <= width + 0.5)
                fit = list[k].x + list[k].width - shift;
        view.width = row.width <= width ? width : fit;
    }

    // A sideways swipe turns a page of chips: forward to the first chip not
    // wholly in view, back to the page that ends just before the first one.
    function page(dir) {
        var list = chipList();
        if (row.width <= width || !list.length)
            return;
        var s = shift;
        if (dir > 0) {
            for (var n = 0; n < list.length; n++)
                if (list[n].x + list[n].width - shift > view.width + 0.5) {
                    s = list[n].x;
                    break;
                }
        } else {
            var last = -1;
            for (var k = 0; k < list.length; k++)
                if (list[k].x < shift - 0.5)
                    last = k;
            if (last < 0)
                return;
            s = list[last].x;
            for (var m = last; m >= 0; m--) {
                if (list[last].x + list[last].width - list[m].x > width + 0.5)
                    break;
                s = list[m].x;
            }
        }
        shift = s;
        fitWhole();
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

        // Tells a sideways swipe (a page of chips) from a tap, which goes to
        // the chip under the finger (see Pager.qml).
        MouseArea {
            anchors.fill: parent
            z: 1
            property real startX: 0
            onPressed: mouse => startX = mouse.x
            onReleased: mouse => {
                var dx = mouse.x - startX;
                if (Math.abs(dx) > Theme.px(50)) {
                    strip.page(dx < 0 ? 1 : -1);
                } else {
                    var chip = row.childAt(mouse.x + strip.shift, mouse.y - row.y);
                    if (chip && chip.tappable === true)
                        chip.tap(0, 0);
                }
            }
        }
    }
}
