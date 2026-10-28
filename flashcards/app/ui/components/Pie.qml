import QtQuick
import "../js/hatch.js" as Hatch

// Card Counts' pie, from the top clockwise as Anki draws it, each slice in
// its kind's fill and outlined in black.
Canvas {
    id: pie
    property var counts: []
    onCountsChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var cx = width / 2, cy = height / 2, r = Math.min(width, height) / 2 - 3;
        var total = 0;
        for (var i = 0; i < counts.length; i++)
            total += counts[i];
        ctx.lineWidth = 3;
        ctx.strokeStyle = "#000000";
        if (total === 0) {
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
            ctx.stroke();
            return;
        }
        var start = -Math.PI / 2;
        for (i = 0; i < counts.length; i++) {
            if (counts[i] === 0)
                continue;
            var end = start + 2 * Math.PI * counts[i] / total;
            ctx.save();
            ctx.beginPath();
            if (counts[i] < total)
                ctx.moveTo(cx, cy);
            ctx.arc(cx, cy, r, start, end, false);
            ctx.closePath();
            ctx.clip();
            Hatch.paint(ctx, i, cx - r, cy - r, 2 * r, 2 * r);
            ctx.restore();
            ctx.beginPath();
            if (counts[i] < total)
                ctx.moveTo(cx, cy);
            ctx.arc(cx, cy, r, start, end, false);
            ctx.closePath();
            ctx.stroke();
            start = end;
        }
    }
}
