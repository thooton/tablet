.pragma library

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// "24 Oct", or "24 Oct 2025" for another year.
function date(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime()))
        return "";
    var s = d.getDate() + " " + MONTHS[d.getMonth()];
    if (d.getFullYear() !== new Date().getFullYear())
        s += " " + d.getFullYear();
    return s;
}

function time(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime()))
        return "";
    var m = d.getMinutes();
    return d.getHours() + ":" + (m < 10 ? "0" : "") + m;
}

function size(bytes) {
    if (bytes >= 1024 * 1024)
        return (bytes / 1024 / 1024).toFixed(1) + " MB";
    return Math.max(1, Math.round(bytes / 1024)) + " KB";
}

function active(app) {
    var p = app.job ? app.job.phase : "";
    return p === "waiting" || p === "downloading" || p === "installing";
}

// The capsule beside an app: {text, filled, percent, action}, or null.
// action is what tapping it does: "install", "cancel" or "".
function capsule(app) {
    var job = app.job;
    if (job) {
        switch (job.phase) {
        case "waiting":
            return { text: "WAITING", filled: false, percent: -1, action: "cancel" };
        case "downloading":
            return { text: job.percent + "%", filled: false, percent: job.percent, action: "" };
        case "installing":
            return { text: "INSTALLING", filled: false, percent: -1, action: "" };
        case "done":
            return { text: "DONE", filled: false, percent: -1, action: "" };
        case "failed":
            return { text: "RETRY", filled: true, percent: -1, action: "install" };
        }
    }
    if (app.status === "update")
        return { text: "UPDATE", filled: true, percent: -1, action: "install" };
    if (app.status === "get")
        return { text: "GET", filled: true, percent: -1, action: "install" };
    return null;
}

// The line under an app's name.
function versionLine(app) {
    var when = app.notes.length ? date(app.notes[0].time) : "";
    var parts = [];
    if (app.status === "update" && !(app.job && app.job.phase === "done"))
        parts.push((app.installedVersion || "Old version") + " → " + app.version);
    else if (app.status === "newer")
        parts.push(app.installedVersion + " here, " + app.version + " in the release");
    else
        parts.push("Version " + app.version);
    if (app.status === "get")
        parts.push(size(app.size));
    else if (when)
        parts.push(when);
    return parts.join("  ·  ");
}

// The last line: what went wrong, or what's new.
function noteLine(app) {
    if (app.job && app.job.phase === "failed")
        return app.job.message;
    if (app.notes.length)
        return app.notes[0].text;
    return "";
}
