/*
    BetterLockScreen Dial — an i3lock-style reactive ring indicator for the
    KDE Plasma lock screen.

    SPDX-License-Identifier: MIT

    Drop-in visual replacement for the password text field. It does NOT handle
    authentication itself: it is driven by the (hidden) PlasmaExtras.PasswordField
    passed in as `passwordField`, plus the kscreenlocker `authenticator` context
    property. The typed characters are never shown — only the ring reacts, exactly
    like i3lock.

    States (`dialState`):
      idle       -> ring #003366, faint inside
      verifying  -> ring becomes a segmented spinner (set by MainBlock on submit)
      wrong      -> dark-red ring + inside (authenticator.onFailed)
      success    -> dark-green ring + inside (authenticator.onSucceeded)
*/

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: dial

    // Sized in grid units so it fits inside the lock screen's central slot
    // (SessionManagementScreen caps that area at ~gridUnit*10) and never
    // overlaps the power buttons below. Tweak `dialUnits` to taste.
    property real dialUnits: 6
    implicitWidth: Kirigami.Units.gridUnit * dialUnits
    implicitHeight: Kirigami.Units.gridUnit * dialUnits

    // The hidden password field driving the keystroke reactions. `var` so we can
    // read `.text.length` dynamically without a concrete type.
    property var passwordField

    // High-level state; MainBlock flips this to "verifying" on submit.
    property string dialState: "idle"

    // --- Geometry ---------------------------------------------------------
    property real ringWidth: Math.max(6, Math.round(Math.min(width, height) * 0.07))
    readonly property real ringRadius: Math.min(width, height) / 2 - ringWidth - 4

    //? --- Colors ---------------------------------------------------------
    readonly property color colIdleRing: "#003366"          // main
    readonly property color colVerRing: "#3584e4"           // verifying (complementary blue)
    readonly property color colWrongRing: "#8B0000"         // dark red
    readonly property color colSuccessRing: "#006400"       // dark green
    readonly property color colIdleInside: Qt.rgba(0.0, 0.20, 0.40, 0.10)
    readonly property color colWrongInside: Qt.rgba(0.545, 0.0, 0.0, 0.30)
    readonly property color colSuccessInside: Qt.rgba(0.0, 0.39, 0.0, 0.30)
    property color keyhlColor: "#4A90D9"                    // keypress highlight
    property color bshlColor: "#B22222"                     // backspace highlight

    readonly property color ringColor: dialState === "wrong" ? colWrongRing
                                      : dialState === "success" ? colSuccessRing
                                      : dialState === "verifying" ? colVerRing
                                      : colIdleRing
    readonly property color insideColor: dialState === "wrong" ? colWrongInside
                                       : dialState === "success" ? colSuccessInside
                                       : colIdleInside

    // --- Reactive highlight state ----------------------------------------
    property real highlightStart: 0      // degrees
    property real highlightOpacity: 0
    property color highlightColor: keyhlColor
    readonly property real highlightArcDeg: 26

    // --- Verifying segmented spinner -------------------------------------
    property color spinnerColor: "#006400"        // colour of the lit segments
    property int segmentCount: 8                 // number of ring segments
    property int spinIndex: 0                     // current bright segment (advances)
    readonly property real segmentGapFrac: 0.32   // gap as a fraction of each segment pitch
    readonly property int spinTrail: 5            // length of the bright trailing head

    function reset() {
        dialState = "idle";
        highlightOpacity = 0;
        canvas.requestPaint();
    }

    function flash(c) {
        highlightColor = c;
        highlightStart = Math.random() * 360;
        highlightOpacity = 1.0;
        canvas.requestPaint();
        highlightClearTimer.restart();
    }

    // Watch the password length to react to key presses / backspaces.
    property int _lastLen: 0
    readonly property int pwLength: passwordField ? passwordField.text.length : 0
    onPwLengthChanged: {
        const delta = pwLength - _lastLen;
        _lastLen = pwLength;
        if (delta > 0) {
            flash(keyhlColor);
            if (dialState === "wrong" || dialState === "success") {
                dialState = "idle"; // user typing
            }
        } else if (delta === -1) {
            flash(bshlColor);
        }
    }

    onDialStateChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind !== 0) {
                return; // ignore non-interactive failures here
            }
            dial.dialState = "wrong";
            wrongRevertTimer.restart();
        }
        function onSucceeded() {
            dial.dialState = "success";
        }
    }

    // kscreenlocker also clears the password ~3s after a
    // failure (which MainBlock turns into reset()), but revert anyway in case
    // the user just sits there.
    Timer {
        id: wrongRevertTimer
        interval: 2500
        onTriggered: if (dial.dialState === "wrong") dial.dialState = "idle"
    }

    // clear the highlight shortly after it appears.
    Timer {
        id: highlightClearTimer
        interval: 90
        onTriggered: { dial.highlightOpacity = 0; canvas.requestPaint(); }
    }

    // advance the bright segment around the ring.
    Timer {
        id: spinTimer
        interval: 70
        repeat: true
        running: dial.dialState === "verifying"
        onTriggered: { dial.spinIndex = (dial.spinIndex + 1) % dial.segmentCount; canvas.requestPaint(); }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const cx = width / 2;
            const cy = height / 2;
            const r = dial.ringRadius;
            const w = dial.ringWidth;
            const TAU = Math.PI * 2;

            // Inside fill
            ctx.beginPath();
            ctx.arc(cx, cy, r - w / 2, 0, TAU);
            ctx.fillStyle = dial.insideColor;
            ctx.fill();

            //solid normally
            if (dial.dialState === "verifying") {
                const N = dial.segmentCount;
                const pitch = TAU / N;
                const seg = pitch * (1 - dial.segmentGapFrac);
                ctx.lineWidth = w;
                ctx.lineCap = "butt";
                ctx.strokeStyle = dial.spinnerColor;
                for (let i = 0; i < N; i++) {
                    const d = (dial.spinIndex - i + N) % N;
                    let a = 0.16;                                              // dim base
                    if (d < dial.spinTrail) a = 1.0 - (d / dial.spinTrail) * 0.78; // bright head -> fade
                    ctx.globalAlpha = a;
                    ctx.beginPath();
                    const a0 = -Math.PI / 2 + i * pitch;                       // first segment at top
                    ctx.arc(cx, cy, r, a0, a0 + seg);
                    ctx.stroke();
                }
                ctx.globalAlpha = 1.0;
            } else {
                ctx.beginPath();
                ctx.lineWidth = w;
                ctx.strokeStyle = dial.ringColor;
                ctx.arc(cx, cy, r, 0, TAU);
                ctx.stroke();
            }

            // Keystroke highlight arc
            if (dial.highlightOpacity > 0) {
                const h0 = dial.highlightStart * Math.PI / 180;
                const hlen = dial.highlightArcDeg * Math.PI / 180;
                ctx.globalAlpha = dial.highlightOpacity;
                ctx.beginPath();
                ctx.lineWidth = w + 2;
                ctx.lineCap = "butt";
                ctx.strokeStyle = dial.highlightColor;
                ctx.arc(cx, cy, r, h0, h0 + hlen);
                ctx.stroke();
                ctx.globalAlpha = 1.0;
            }
        }
    }
}
