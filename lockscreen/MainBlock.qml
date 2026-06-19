/*
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

import org.kde.breeze.components

SessionManagementScreen {
    id: sessionManager

    readonly property alias mainPasswordBox: passwordBox
    property bool lockScreenUiVisible: false
    property alias showPassword: passwordBox.showPassword

    //the y position that should be ensured visible when the on screen keyboard is visible
    property int visibleBoundary: mapFromItem(loginButton, 0, 0).y
    onHeightChanged: visibleBoundary = mapFromItem(loginButton, 0, 0).y + loginButton.height + Kirigami.Units.smallSpacing
    /*
     * Login has been requested with the following username and password
     * If username field is visible, it will be taken from that, otherwise from the "name" property of the currentIndex
     */
    signal passwordResult(string password)

    onUserSelected: {
        const nextControl = (passwordBox.visible ? passwordBox : loginButton);
        // Don't startLogin() here, because the signal is connected to the
        // Escape key as well, for which it wouldn't make sense to trigger
        // login. Using TabFocusReason, so that the loginButton gets the
        // visual highlight.
        nextControl.forceActiveFocus(Qt.TabFocusReason);
    }

    function startLogin() {
        const password = passwordBox.text

        // This is partly because it looks nicer, but more importantly it
        // works round a Qt bug that can trigger if the app is closed with a
        // TextField focused.
        //
        // See https://bugreports.qt.io/browse/QTBUG-55460
        loginButton.forceActiveFocus();
        dial.dialState = "verifying";
        passwordResult(password);
    }

    // i3lock-style dial replaces the visible password field. The PasswordField
    // itself is kept (invisible, opacity 0) so all authentication plumbing —
    // PasswordSync, grace lock, virtual keyboard, clear, fingerprint/smartcard —
    // keeps working unchanged. Only the ring reacts to keystrokes.
    Item {
        id: dialContainer
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 0
        implicitWidth: dial.implicitWidth
        implicitHeight: dial.implicitHeight
        // Reserve the dial's full height so the layout can't compress this slot
        // (the ring is a fixed-size canvas). Without this the dial spills over
        // the media controls below when music is playing; with it, the media
        // controls are pushed down to make room.
        Layout.minimumHeight: dial.implicitHeight
        Layout.preferredHeight: dial.implicitHeight
        Layout.preferredWidth: dial.implicitWidth

        DialIndicator {
            id: dial
            anchors.centerIn: parent
            passwordField: passwordBox
        }

        PlasmaExtras.PasswordField {
            id: passwordBox
            anchors.centerIn: parent
            width: dial.width
            height: dial.height
            opacity: 0
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
            text: PasswordSync.password

            focus: true
            enabled: !authenticator.graceLocked

            // Focus-driven and invisible (see upstream note): no cursor renders.
            cursorVisible: false

            onAccepted: {
                if (sessionManager.lockScreenUiVisible) {
                    sessionManager.startLogin();
                }
            }

            //if empty and left or right is pressed change selection in user switch
            //this cannot be in keys.onLeftPressed as then it doesn't reach the password box
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left && !text) {
                    sessionManager.userList.decrementCurrentIndex();
                    event.accepted = true
                }
                if (event.key === Qt.Key_Right && !text) {
                    sessionManager.userList.incrementCurrentIndex();
                    event.accepted = true
                }
            }

            Connections {
                target: root
                function onClearPassword() {
                    dial.reset();
                    passwordBox.forceActiveFocus()
                    passwordBox.text = "";
                    passwordBox.text = Qt.binding(() => PasswordSync.password);
                }
                function onNotificationRepeated() {
                    sessionManager.playHighlightAnimation();
                }
            }
        }
        Binding {
            target: PasswordSync
            property: "password"
            value: passwordBox.text
        }

        // Kept (tiny + invisible, but focusable) for the startLogin() focus
        // workaround and Enter handling.
        PlasmaComponents3.Button {
            id: loginButton
            anchors.top: parent.top
            anchors.left: parent.left
            width: 1
            height: 1
            opacity: 0
            Accessible.name: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button accessible only", "Unlock")
            onClicked: sessionManager.startLogin()
            Keys.onEnterPressed: clicked()
            Keys.onReturnPressed: clicked()
        }
    }

    // NOTE: the "Type password to unlock…" prompt label was intentionally
    // omitted so the full-size dial and the now-playing media strip both fit
    // inside KDE's height-capped central area without overlapping the power
    // buttons. To bring it back, shrink `dialUnits` in DialIndicator.qml to make
    // room, then add a PlasmaComponents3.Label here.

    component FailableLabel : PlasmaComponents3.Label {
        id: _failableLabel
        required property int kind
        required property string label

        visible: authenticator.authenticatorTypes & kind
        text: label
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true

        RejectPasswordAnimation {
            id: _rejectAnimation
            target: _failableLabel
            onFinished: _timer.restart()
        }

        Connections {
            target: authenticator
            function onNoninteractiveError(kind, authenticator) {
                if (kind & _failableLabel.kind) {
                    _failableLabel.text = Qt.binding(() => authenticator.errorMessage)
                    _rejectAnimation.start()
                }
            }
            // On a wrong password (interactive auth → kind 0), replace the hint
            // (e.g. "(or scan your fingerprint…)") with "Try again". The _timer
            // started by the reject animation reverts it back to `label`.
            function onFailed(kind) {
                if (kind === 0) {
                    _failableLabel.text = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "Try again")
                    _rejectAnimation.start()
                }
            }
        }
        Timer {
            id: _timer
            interval: Kirigami.Units.humanMoment
            onTriggered: {
                _failableLabel.text = Qt.binding(() => _failableLabel.label)
            }
        }
    }

    FailableLabel {
        kind: ScreenLocker.Authenticator.Fingerprint
        label: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your fingerprint on the reader)")
    }
    FailableLabel {
        kind: ScreenLocker.Authenticator.Smartcard
        label: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your smartcard)")
    }
}
