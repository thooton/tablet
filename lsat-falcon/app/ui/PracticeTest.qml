import QtQuick
import "components"
import "js/theme.js" as Theme
import "js/deck.js" as Deck

// PracticeTest.jsx: sit a whole PrepTest. setup → brief → section → … →
// results → review. Inside a section you can move between questions and
// change answers; finishing it is final. Nothing is marked until the end.
Item {
    id: practice
    property QtObject store
    signal exit

    property var exam: null
    property bool timed: true
    property string phase: "setup"
    property int si: 0
    property var answers: ({})
    property var eliminated: ({})
    property var flags: ({})
    property int seconds: 0           // inside the current section
    property int elapsed: 0           // the finished sections, together
    property string confirmText: ""
    property var confirmAction: null

    readonly property int limit: Theme.SECTION_MINUTES * 60
    readonly property int warning: 5 * 60
    readonly property var sections: exam ? exam.sections : []
    readonly property var section: sections[si] || null
    readonly property bool midTest: phase === "brief" || phase === "section"

    function start(test, isTimed) {
        exam = Deck.exams.filter(function (e) { return e.test === test; })[0];
        timed = isTimed;
        si = 0;
        answers = {};
        eliminated = {};
        flags = {};
        seconds = 0;
        elapsed = 0;
        phase = "brief";
    }

    function finishSection() {
        elapsed += seconds;
        seconds = 0;
        if (si + 1 < sections.length) {
            si++;
            phase = "brief";
        } else {
            phase = "results";
        }
    }

    function ask(text, action) {
        confirmText = text;
        confirmAction = action;
    }

    function leave() {
        if (midTest)
            ask("End this practice test? Your answers will be lost.", function () { practice.exit(); });
        else
            exit();
    }

    function withChange(map, key, value) {
        var out = {};
        for (var k in map)
            out[k] = map[k];
        out[key] = value;
        return out;
    }

    // The section clock. It runs whether or not the limit is enforced: untimed
    // still tells you how long a section took.
    Timer {
        interval: 1000
        repeat: true
        running: practice.phase === "section"
        onTriggered: {
            practice.seconds++;
            if (practice.timed && practice.seconds >= practice.limit)
                practice.finishSection();
        }
    }

    // E-ink redraws for every change, so the clock shows whole minutes:
    // counting down they round up (35 min at the start, <1 min in the last).
    function clock(s) {
        s = Math.max(0, s);
        if (s < 60)
            return practice.timed ? "<1 min" : "0 min";
        return (practice.timed ? Math.ceil(s / 60) : Math.floor(s / 60)) + " min";
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
    }

    Header {
        id: header
        title: practice.exam && practice.phase !== "setup" ? practice.exam.label : "Practice test"

        Rectangle {
            visible: practice.phase === "section"
            readonly property bool late: practice.timed && practice.limit - practice.seconds <= practice.warning
            width: timerRow.width + 2 * Theme.px(12)
            height: Theme.px(36)
            radius: Theme.px(8)
            color: late ? Theme.surface : Theme.chip
            border.width: late ? Theme.px(1.5) : 0
            border.color: Theme.ink
            Row {
                id: timerRow
                anchors.centerIn: parent
                spacing: Theme.px(8)
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: practice.timed ? "clock" : "stopwatch"
                    size: 18
                }
                UiText {
                    text: practice.clock(practice.timed ? practice.limit - practice.seconds : practice.seconds)
                    size: 15
                    font.weight: parent.parent.late ? Font.Bold : Font.Medium
                }
            }
        }
        PillButton {
            kind: "ghost"
            h: 36
            padX: 12
            textSize: 14.5
            radius: Theme.px(8)
            text: practice.midTest ? "End test" : "Done"
            onClicked: practice.leave()
        }
    }

    Item {
        id: body
        y: header.height
        width: parent.width
        height: parent.height - y

        ExamSetup {
            objectName: "examSetup"
            anchors.fill: parent
            visible: practice.phase === "setup"
            onStart: (test, isTimed) => practice.start(test, isTimed)
        }

        // The brief before each section.
        Column {
            visible: practice.phase === "brief" && practice.section !== null
            anchors.centerIn: parent
            width: Math.min(parent.width - 2 * Theme.px(20), Theme.px(440))
            SectionLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Section " + (practice.si + 1) + " of " + practice.sections.length
                size: 13
            }
            Item { width: 1; height: Theme.px(12) }
            UiText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: practice.section ? (practice.section.name || "Questions") : ""
                size: 30
                tight: true
                font.weight: Font.DemiBold
            }
            Item { width: 1; height: Theme.px(8) }
            UiText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: practice.section ? practice.section.qs.length + " questions ("
                                         + (practice.timed ? Theme.SECTION_MINUTES + " minutes" : "untimed") + ")" : ""
                size: 15
                color: Theme.inkSoft
            }
            Item { width: 1; height: Theme.px(32) }
            PillButton {
                objectName: "beginButton"
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Begin section"
                onClicked: {
                    sectionView.idx = 0;
                    practice.phase = "section";
                }
            }
        }

        // ---- a section under exam conditions
        Item {
            id: sectionView
            visible: practice.phase === "section"
            anchors.fill: parent
            property int idx: 0
            readonly property var qs: practice.section ? practice.section.qs : []
            readonly property int qi: qs.length ? qs[Math.min(idx, qs.length - 1)] : -1
            readonly property bool last: idx === qs.length - 1
            readonly property string finishLabel: practice.si === practice.sections.length - 1 ? "Finish test" : "Finish section"

            function jump(n) {
                idx = Math.min(qs.length - 1, Math.max(0, n));
            }
            onQiChanged: {
                practice.store.request(qi);
                if (idx + 1 < qs.length)
                    practice.store.request(qs[idx + 1]);
            }
            // Leaving a section can't be undone, so ask first when anything
            // is still blank.
            function finish() {
                var blank = qs.filter(function (i) { return practice.answers[i] === undefined; }).length;
                if (blank)
                    practice.ask(blank + (blank > 1 ? " questions are" : " question is") + " unanswered. "
                                 + finishLabel + "?", function () { practice.finishSection(); });
                else
                    practice.finishSection();
            }

            ExamPanes {
                width: parent.width
                height: footer.y
                question: sectionView.qi >= 0 && practice.phase === "section" ? practice.store.model(sectionView.qi) : null
                siblings: sectionView.qi >= 0 ? Deck.groupOf(sectionView.qi).qs.filter(function (i) {
                    return sectionView.qs.indexOf(i) >= 0;
                }) : []
                selected: practice.answers[sectionView.qi] || ""
                eliminated: practice.eliminated[sectionView.qi] || []
                showBookmark: true
                bookmarked: practice.flags[sectionView.qi] === true
                onSelect: letter => practice.answers = practice.withChange(practice.answers, sectionView.qi, letter)
                onEliminate: letter => {
                    var cur = practice.eliminated[sectionView.qi] || [];
                    var next = cur.indexOf(letter) >= 0 ? cur.filter(function (l) { return l !== letter; }) : cur.concat([letter]);
                    practice.eliminated = practice.withChange(practice.eliminated, sectionView.qi, next);
                }
                onToggleBookmark: practice.flags = practice.withChange(practice.flags, sectionView.qi, !practice.flags[sectionView.qi])
                onJump: i => sectionView.jump(sectionView.qs.indexOf(i))
            }

            Item {
                id: footer
                width: parent.width
                height: Theme.px(68)
                y: parent.height - height
                Rule {}
                PillButton {
                    id: backButton
                    x: Theme.px(12)
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "ghost"
                    h: 40
                    padX: 12
                    textSize: 14.5
                    text: "Back"
                    enabled: sectionView.idx > 0
                    onClicked: sectionView.jump(sectionView.idx - 1)
                }
                Palette {
                    x: backButton.x + backButton.width + Theme.px(8)
                    width: footerRight.x - Theme.px(8) - x
                    height: parent.height
                    questions: sectionView.qs
                    numbers: sectionView.qs.map(function (i) { return Deck.questions[i].number; })
                    currentIndex: sectionView.idx
                    answers: practice.answers
                    flags: practice.flags
                    onJump: n => sectionView.jump(n)
                }
                Row {
                    id: footerRight
                    x: parent.width - Theme.px(12) - width
                    height: parent.height
                    spacing: Theme.px(4)
                    PillButton {
                        visible: !sectionView.last
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "ghost"
                        h: 40
                        padX: 12
                        textSize: 14.5
                        text: sectionView.finishLabel
                        onClicked: sectionView.finish()
                    }
                    PillButton {
                        objectName: "nextButton"
                        anchors.verticalCenter: parent.verticalCenter
                        padX: 20
                        text: sectionView.last ? sectionView.finishLabel : "Next"
                        onClicked: sectionView.last ? sectionView.finish() : sectionView.jump(sectionView.idx + 1)
                    }
                }
            }
        }

        // ---- the score report
        Pager {
            id: results
            visible: practice.phase === "results"
            anchors.fill: parent

            // Blanks count as wrong, as on the real test.
            readonly property var scored: practice.exam ? practice.sections.filter(function (s) { return !s.experimental; })
                                                          .reduce(function (all, s) { return all.concat(s.qs); }, []) : []
            readonly property int correctCount: scored.filter(function (i) { return practice.answers[i] === Deck.questions[i].correct; }).length
            readonly property int answered: scored.filter(function (i) { return practice.answers[i] !== undefined; }).length
            readonly property int score: practice.exam ? Deck.scaledScore(practice.exam.test, correctCount, scored.length).score : 0
            readonly property var byType: {
                var rows = {}, out = [];
                for (var n = 0; n < scored.length; n++) {
                    var i = scored[n], cat = Deck.category(i);
                    if (!rows[cat.path]) {
                        rows[cat.path] = { label: cat.label, section: cat.section, right: 0, total: 0 };
                        out.push(rows[cat.path]);
                    }
                    rows[cat.path].total++;
                    if (practice.answers[i] === Deck.questions[i].correct)
                        rows[cat.path].right++;
                }
                var seen = {};
                for (var r = 0; r < out.length; r++)
                    seen[out[r].label] = (seen[out[r].label] || 0) + 1;
                for (r = 0; r < out.length; r++)
                    if (seen[out[r].label] > 1)
                        out[r].label += " (" + out[r].section + ")";
                return out.sort(function (a, b) { return b.total - a.total; });
            }
            function duration(s) {
                var m = Math.round(s / 60);
                if (m < 1)
                    return Math.round(s) + "s";
                return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m";
            }

            Column {
                x: Theme.px(20)
                width: parent.width - 2 * Theme.px(20)

                Item { width: 1; height: Theme.px(24) }
                UiText {
                    text: practice.exam ? practice.exam.label + " complete" : ""
                    size: 17
                    tight: true
                    font.weight: Font.Medium
                    color: Theme.accent
                }
                Item { width: 1; height: Theme.px(20) }
                Row {
                    spacing: Theme.px(24)
                    UiText {
                        text: results.score
                        size: 64
                        tight: true
                        font.weight: Font.DemiBold
                        height: Theme.px(64)
                    }
                    Repeater {
                        model: [
                            { value: results.correctCount, label: "correct" },
                            { value: results.scored.length - results.correctCount, label: "incorrect" }
                        ]
                        delegate: Column {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.px(4)
                            UiText {
                                text: modelData.value
                                size: 26
                                tight: true
                                font.weight: Font.DemiBold
                                height: Theme.px(26)
                            }
                            Item { width: 1; height: Theme.px(6) }
                            UiText {
                                text: modelData.label
                                size: 13
                                color: Theme.inkSoft
                            }
                        }
                    }
                }
                Item { width: 1; height: Theme.px(20) }
                UiText {
                    width: parent.width
                    wrapMode: Text.Wrap
                    size: 14
                    lineHeight: 1.7
                    color: Theme.inkSoft
                    text: {
                        var total = results.scored.length, blank = total - results.answered;
                        var pct = total ? Math.round(results.correctCount / total * 100) : 0;
                        var parts = [results.correctCount + " of " + total + " right (" + pct + "%)"];
                        if (blank > 0)
                            parts.push(blank + " left blank (counted wrong)");
                        parts.push(practice.timed ? "timed" : "untimed");
                        if (practice.elapsed)
                            parts.push(results.duration(practice.elapsed));
                        return parts.join("  |  ");
                    }
                }

                Item { width: 1; height: Theme.px(36) }
                SectionLabel {
                    text: "By section"
                }
                Item { width: 1; height: Theme.px(4) }
                Rule {}
                Repeater {
                    model: practice.sections
                    delegate: ResultRow {
                        label: modelData.label + (modelData.experimental ? " (experimental)" : "")
                        correctCount: modelData.qs.filter(function (i) { return practice.answers[i] === Deck.questions[i].correct; }).length
                        total: modelData.qs.length
                    }
                }

                Item { width: 1; height: Theme.px(32) }
                SectionLabel {
                    text: "By question type"
                }
                Item { width: 1; height: Theme.px(4) }
                Rule {}
                Repeater {
                    model: results.byType
                    delegate: ResultRow {
                        label: modelData.label
                        correctCount: modelData.right
                        total: modelData.total
                        muted: true
                    }
                }

                Item { width: 1; height: Theme.px(36) }
                Flow {
                    width: parent.width
                    spacing: Theme.px(12)
                    PillButton {
                        text: "Review answers"
                        onClicked: {
                            review.idx = 0;
                            practice.phase = "review";
                        }
                    }
                    PillButton {
                        kind: "outline"
                        padX: 24
                        text: "Another test"
                        onClicked: practice.phase = "setup"
                    }
                    PillButton {
                        kind: "ghost"
                        padX: 16
                        text: "Back to drilling"
                        onClicked: practice.exit()
                    }
                }
                Item { width: 1; height: Theme.px(48) }
            }
        }

        // ---- review: the finished test with everything showing
        Item {
            id: review
            visible: practice.phase === "review"
            anchors.fill: parent
            property int idx: 0
            readonly property var qs: practice.sections.reduce(function (all, s) { return all.concat(s.qs); }, [])
            readonly property int qi: qs.length ? qs[Math.min(idx, qs.length - 1)] : -1
            function jump(n) {
                idx = Math.min(qs.length - 1, Math.max(0, n));
            }
            onQiChanged: if (qi >= 0) practice.store.request(qi)

            ExamPanes {
                width: parent.width
                height: reviewFooter.y
                question: review.qi >= 0 && practice.phase === "review" ? practice.store.model(review.qi) : null
                siblings: review.qi >= 0 ? Deck.groupOf(review.qi).qs.filter(function (i) { return review.qs.indexOf(i) >= 0; }) : []
                selected: practice.answers[review.qi] || ""
                revealed: true
                showExplanation: true
                onJump: i => review.jump(review.qs.indexOf(i))
            }

            Item {
                id: reviewFooter
                width: parent.width
                height: Theme.px(68)
                y: parent.height - height
                Rule {}
                PillButton {
                    id: reportButton
                    x: Theme.px(12)
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "ghost"
                    h: 40
                    padX: 12
                    textSize: 14.5
                    text: "Score report"
                    onClicked: practice.phase = "results"
                }
                // One bar per question: filled when right, open when wrong.
                Strip {
                    id: bars
                    x: reportButton.x + reportButton.width + Theme.px(8)
                    width: reviewRight.x - Theme.px(8) - x
                    height: parent.height
                    spacing: Theme.px(6)
                    current: barRepeater.count > review.idx ? barRepeater.itemAt(review.idx) : null
                    Repeater {
                        id: barRepeater
                        model: review.qs
                        delegate: Pressable {
                            readonly property bool isRight: practice.answers[modelData] === Deck.questions[modelData].correct
                            readonly property bool here: index === review.idx
                            width: Theme.px(10) + 2 * Theme.px(4)
                            height: Theme.px(24) + 2 * Theme.px(4)
                            radius: Theme.px(6)
                            border.width: here ? Theme.lineWidth : 0
                            border.color: Theme.navy
                            onClicked: review.idx = index
                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(10)
                                height: Theme.px(24)
                                radius: width / 2
                                color: parent.isRight ? Theme.correct : Theme.surface
                                border.width: parent.isRight ? 0 : Theme.lineWidth
                                border.color: Theme.wrong
                            }
                        }
                    }
                }
                Row {
                    id: reviewRight
                    x: parent.width - Theme.px(12) - width
                    height: parent.height
                    spacing: Theme.px(4)
                    PillButton {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "ghost"
                        h: 40
                        padX: 12
                        textSize: 14.5
                        text: "Back"
                        enabled: review.idx > 0
                        onClicked: review.jump(review.idx - 1)
                    }
                    PillButton {
                        anchors.verticalCenter: parent.verticalCenter
                        padX: 20
                        text: "Next"
                        enabled: review.idx < review.qs.length - 1
                        onClicked: review.jump(review.idx + 1)
                    }
                }
            }
        }
    }

    ConfirmDialog {
        visible: practice.confirmText !== ""
        text: practice.confirmText
        onAccepted: {
            var action = practice.confirmAction;
            practice.confirmText = "";
            practice.confirmAction = null;
            if (action)
                action();
        }
        onRejected: {
            practice.confirmText = "";
            practice.confirmAction = null;
        }
    }
}
