import QtQuick
import "../js/hatch.js" as Hatch

// A swatch of one of Card Counts' fills, outlined.
Canvas {
    property int kind: 0
    width: 52
    height: 52
    onKindChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        Hatch.paint(ctx, kind, 0, 0, width, height);
        ctx.lineWidth = 2;
        ctx.strokeStyle = "#000000";
        ctx.strokeRect(1, 1, width - 2, height - 2);
    }
}
