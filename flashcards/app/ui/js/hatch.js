.pragma library

// The fills Card Counts tells its kinds of card apart by, as the old DOS
// charts did in black and white: New "....", Learning "++++", Relearning
// "xxxx", Young "////", Mature solid. paint() fills x, y, w, h (or whatever
// the context is clipped to inside it) with kind's fill.
function paint(ctx, kind, x, y, w, h) {
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(x, y, w, h);
    ctx.fillStyle = "#000000";
    ctx.strokeStyle = "#000000";
    ctx.lineCap = "square";
    var i, j, step;
    if (kind === 0) {
        step = 18;
        for (j = y + step / 2; j < y + h; j += step)
            for (i = x + step / 2; i < x + w; i += step) {
                ctx.beginPath();
                ctx.arc(i, j, 2.6, 0, 2 * Math.PI);
                ctx.fill();
            }
    } else if (kind === 1 || kind === 2) {
        step = 26;
        var arm = 7;
        ctx.lineWidth = 3;
        ctx.beginPath();
        for (j = y + step / 2; j < y + h + arm; j += step)
            for (i = x + step / 2; i < x + w + arm; i += step) {
                if (kind === 1) {
                    ctx.moveTo(i - arm, j);
                    ctx.lineTo(i + arm, j);
                    ctx.moveTo(i, j - arm);
                    ctx.lineTo(i, j + arm);
                } else {
                    ctx.moveTo(i - arm, j - arm);
                    ctx.lineTo(i + arm, j + arm);
                    ctx.moveTo(i - arm, j + arm);
                    ctx.lineTo(i + arm, j - arm);
                }
            }
        ctx.stroke();
    } else if (kind === 3) {
        step = 16;
        ctx.lineWidth = 3.5;
        ctx.beginPath();
        for (i = x - h; i < x + w + h; i += step) {
            ctx.moveTo(i, y + h);
            ctx.lineTo(i + h, y);
        }
        ctx.stroke();
    } else {
        ctx.fillRect(x, y, w, h);
    }
}
