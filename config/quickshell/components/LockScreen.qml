pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import ".."

Item {
    id: root

    property bool locked: false
    property string errorText: ""
    property bool authenticating: false
    property string currentUser: String(Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user")
    property string kbLayoutShort: ""
    property string _pendingPwd: ""

    signal clearInputs()

    readonly property var activePlayer: {
        const players = Mpris.players.values;
        if (!players || players.length === 0)
            return null;
        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (p && p.isPlaying)
                return p;
        }
        for (let j = 0; j < players.length; j++) {
            const p = players[j];
            if (p && p.trackTitle && p.trackTitle.length > 0)
                return p;
        }
        return null;
    }

    function lock(): void {
        if (root.locked)
            return;
        root.errorText = "";
        root.authenticating = false;
        root._pendingPwd = "";
        root.clearInputs();
        root.locked = true;
        if (!kbProc.running)
            kbProc.running = true;
        if (!pam.active)
            pam.start();
    }

    function unlock(): void {
        root._pendingPwd = "";
        root.authenticating = false;
        root.errorText = "";
        root.clearInputs();
        if (pam.active)
            pam.abort();
        root.locked = false;
    }

    function submitPassword(pwd: string): void {
        if (root.authenticating)
            return;
        if (!pwd || pwd.length === 0) {
            root.errorText = "Enter your password";
            return;
        }
        root.errorText = "";
        root.authenticating = true;
        root.clearInputs();
        if (pam.active && pam.responseRequired) {
            pam.respond(pwd);
        } else {
            root._pendingPwd = pwd;
            if (!pam.active) {
                if (!pam.start()) {
                    root.authenticating = false;
                    root._pendingPwd = "";
                    root.errorText = "Unable to start PAM authentication";
                }
            }
        }
    }

    Process {
        id: userFallbackProc
        command: ["id", "-un"]
        running: root.currentUser === "user"
        stdout: StdioCollector {
            onStreamFinished: {
                const u = (text || "").trim();
                if (u.length > 0)
                    root.currentUser = u;
            }
        }
    }

    Process {
        id: kbProc
        command: ["mmsg", "get", "keyboardlayout"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    const full = String(d.layout || "").trim();
                    const paren = full.match(/\(([^)]+)\)/);
                    if (paren && paren[1])
                        root.kbLayoutShort = paren[1].trim().slice(0, 3).toUpperCase();
                    else if (full.length > 0)
                        root.kbLayoutShort = full.slice(0, 2).toUpperCase();
                } catch (err) {}
            }
        }
    }

    PamContext {
        id: pam
        configDirectory: Quickshell.shellPath("pam")
        config: "lock"

        onResponseRequiredChanged: {
            if (pam.responseRequired && root._pendingPwd.length > 0) {
                const p = root._pendingPwd;
                root._pendingPwd = "";
                pam.respond(p);
            }
        }

        onPamMessage: {
            if (pam.messageIsError && pam.message && pam.message.length > 0)
                root.errorText = pam.message;
        }

        onCompleted: result => {
            root.authenticating = false;
            root._pendingPwd = "";
            if (result === PamResult.Success) {
                root.errorText = "";
                root.clearInputs();
                root.locked = false;
            } else {
                root.errorText = (result === PamResult.MaxTries)
                    ? "Too many attempts — wait a moment"
                    : "Authentication failed — try again";
                if (root.locked && !pam.active)
                    pam.start();
            }
        }

        onError: err => {
            root.authenticating = false;
            root._pendingPwd = "";
            root.errorText = "PAM error: " + PamError.toString(err);
        }
    }

    // Wayland ext-idle-notify-v1 Idle Power Manager (respects fullscreen/media inhibitors & keepAwake)
    IdleMonitor {
        id: idleLockMonitor
        enabled: ShellState.idleLockEnabled && !ShellState.keepAwake && !root.locked
        timeout: Math.max(30, ShellState.idleLockSeconds)
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle && enabled)
                root.lock();
        }
    }

    IdleMonitor {
        id: idleSuspendMonitor
        enabled: ShellState.idleSuspendEnabled && !ShellState.keepAwake
        timeout: Math.max(60, ShellState.idleSuspendSeconds)
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle && enabled) {
                if (ShellState.idleLockEnabled && !root.locked)
                    root.lock();
                Quickshell.execDetached(["loginctl", "suspend"]);
            }
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        WlSessionLockSurface {
            id: lockSurf
            color: Theme.surfaceContainerLowest

            property bool confirmPoweroff: false

            SystemClock {
                id: lockClock
                precision: SystemClock.Seconds
            }

            Connections {
                target: root
                function onClearInputs(): void {
                    pwdInput.text = "";
                }
            }

            onVisibleChanged: {
                if (lockSurf.visible && root.locked) {
                    focusDelay.restart();
                }
            }

            Timer {
                id: focusDelay
                interval: 40
                repeat: false
                onTriggered: {
                    if (lockSurf.visible && root.locked)
                        pwdInput.forceActiveFocus();
                }
            }

            Timer {
                id: poweroffConfirmTimer
                interval: 4000
                repeat: false
                onTriggered: lockSurf.confirmPoweroff = false
            }

            // Wallpaper Layer
            Image {
                anchors.fill: parent
                visible: !Theme.isSimple && ShellState.surfaceStyle !== "oled" && Theme.wallpaperPath.length > 0
                source: Theme.wallpaperPath.length > 0 ? ("file://" + Theme.wallpaperPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(Math.max(1, lockSurf.width), Math.max(1, lockSurf.height))
            }

            // Ambient Theme Scrim
            Rectangle {
                anchors.fill: parent
                color: {
                    if (Theme.isSimple || ShellState.surfaceStyle === "oled")
                        return Theme.surfaceContainerLowest;
                    return Theme.isDark
                        ? Qt.rgba(0.03, 0.03, 0.06, 0.72)
                        : Qt.rgba(0.94, 0.94, 0.97, 0.68);
                }
            }

            // Main Lock Card
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(440, Math.max(300, lockSurf.width - 48))
                implicitHeight: cardCol.implicitHeight + 52
                radius: Theme.r(28)
                color: Theme.notchBg
                border.width: Math.max(1, Theme.islandBorderWidth)
                border.color: root.errorText.length > 0 ? Theme.error : Theme.islandBorder

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 26
                    spacing: 14

                    // Clock & Date
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: ShellState.formatTime(lockClock.date)
                            font.family: Theme.fontFamily
                            font.pixelSize: 48
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: ShellState.formatDate(lockClock.date)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    // Status Pill Strip (User, Layout, Battery, DND)
                    Flow {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6

                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: userChipRow.implicitWidth + 16
                            radius: Theme.r(12)
                            color: Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            RowLayout {
                                id: userChipRow
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    text: "󰀄"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 12
                                    color: Theme.primary
                                }
                                Text {
                                    text: root.currentUser
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: Theme.fgSurface
                                }
                            }
                        }

                        Rectangle {
                            visible: root.kbLayoutShort.length > 0
                            implicitHeight: 24
                            implicitWidth: kbChipRow.implicitWidth + 14
                            radius: Theme.r(12)
                            color: Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            RowLayout {
                                id: kbChipRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: "󰌌"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 11
                                    color: Theme.secondary
                                }
                                Text {
                                    text: root.kbLayoutShort
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }
                            }
                        }

                        Rectangle {
                            visible: DeviceCaps.hasBattery
                            implicitHeight: 24
                            implicitWidth: batChipRow.implicitWidth + 14
                            radius: Theme.r(12)
                            color: Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            RowLayout {
                                id: batChipRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: DeviceCaps.batteryIcon
                                    font.family: Theme.iconFont
                                    font.pixelSize: 12
                                    color: DeviceCaps.batteryLow
                                        ? Theme.error
                                        : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant)
                                }
                                Text {
                                    text: DeviceCaps.batteryPercent + "%"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }
                            }
                        }

                        Rectangle {
                            visible: ShellState.dnd
                            implicitHeight: 24
                            implicitWidth: 26
                            radius: Theme.r(12)
                            color: Theme.withAlpha(Theme.warning, 0.16)
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.withAlpha(Theme.warning, 0.45)

                            Text {
                                anchors.centerIn: parent
                                text: "󰂛"
                                font.family: Theme.iconFont
                                font.pixelSize: 12
                                color: Theme.warning
                            }
                        }
                    }

                    // Active Media Pill (when music is loaded/playing)
                    Rectangle {
                        visible: root.activePlayer !== null && (root.activePlayer.trackTitle || "").length > 0
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: Theme.r(14)
                        color: Theme.cardBg
                        border.width: Theme.cardBorderWidth
                        border.color: Theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                text: (root.activePlayer && root.activePlayer.isPlaying) ? "󰎈" : "󰏤"
                                font.family: Theme.iconFont
                                font.pixelSize: 15
                                color: Theme.primary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    text: root.activePlayer ? (root.activePlayer.trackTitle || "") : ""
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: Theme.fgSurface
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: root.activePlayer ? (root.activePlayer.trackArtist || "") : ""
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.fgSurfaceVariant
                                }
                            }

                            Rectangle {
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: Theme.r(13)
                                color: mediaMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                                Text {
                                    anchors.centerIn: parent
                                    text: (root.activePlayer && root.activePlayer.isPlaying) ? "󰏤" : "󰐊"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 12
                                    color: Theme.fgSurface
                                }

                                MouseArea {
                                    id: mediaMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.activePlayer && root.activePlayer.canTogglePlaying)
                                            root.activePlayer.togglePlaying();
                                    }
                                }
                            }
                        }
                    }

                    // Password Input Box
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: Theme.r(14)
                        color: Theme.cardBg
                        border.width: 1
                        border.color: pwdInput.activeFocus
                            ? Theme.primary
                            : (root.errorText.length > 0 ? Theme.error : Theme.cardBorder)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: root.authenticating ? "󰦖" : "󰌾"
                                font.family: Theme.iconFont
                                font.pixelSize: 15
                                color: pwdInput.activeFocus ? Theme.primary : Theme.fgSurfaceVariant
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pwdInput.text.length === 0
                                    text: root.authenticating ? "Verifying..." : "Enter password to unlock"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.fgSurfaceVariant
                                }

                                TextInput {
                                    id: pwdInput
                                    anchors.fill: parent
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    enabled: !root.authenticating
                                    color: Theme.fgSurface
                                    selectionColor: Theme.primary
                                    selectedTextColor: Theme.fgPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    clip: true

                                    Keys.onReturnPressed: root.submitPassword(text)
                                    Keys.onEnterPressed: root.submitPassword(text)
                                    Keys.onEscapePressed: text = ""
                                }
                            }

                            Rectangle {
                                implicitWidth: 30
                                implicitHeight: 30
                                radius: Theme.r(10)
                                color: submitMouse.containsMouse ? Theme.primary : Theme.subCardBg

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰌍"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 14
                                    color: submitMouse.containsMouse ? Theme.fgPrimary : Theme.primary
                                }

                                MouseArea {
                                    id: submitMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.submitPassword(pwdInput.text)
                                }
                            }
                        }
                    }

                    // Error / Feedback Text
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.errorText.length > 0
                        text: root.errorText
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Theme.error
                    }
                }
            }

            // Bottom-Right Quick Session Power Controls
            RowLayout {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                spacing: 8

                Rectangle {
                    implicitHeight: 34
                    implicitWidth: suspRow.implicitWidth + 20
                    radius: Theme.r(17)
                    color: suspMouse.containsMouse ? Theme.hoverBg : Theme.notchBg
                    border.width: Math.max(1, Theme.cardBorderWidth)
                    border.color: Theme.cardBorder

                    RowLayout {
                        id: suspRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "󰒲"
                            font.family: Theme.iconFont
                            font.pixelSize: 13
                            color: Theme.secondary
                        }
                        Text {
                            text: "Suspend"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: suspMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["loginctl", "suspend"])
                    }
                }

                Rectangle {
                    implicitHeight: 34
                    implicitWidth: pwrRow.implicitWidth + 20
                    radius: Theme.r(17)
                    color: lockSurf.confirmPoweroff
                        ? Theme.error
                        : (pwrMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.notchBg)
                    border.width: Math.max(1, Theme.cardBorderWidth)
                    border.color: lockSurf.confirmPoweroff ? Theme.error : Theme.cardBorder

                    RowLayout {
                        id: pwrRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "󰐥"
                            font.family: Theme.iconFont
                            font.pixelSize: 13
                            color: lockSurf.confirmPoweroff ? Theme.fgError : Theme.error
                        }
                        Text {
                            text: lockSurf.confirmPoweroff ? "Confirm Poweroff?" : "Poweroff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: lockSurf.confirmPoweroff ? Theme.fgError : Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: pwrMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!lockSurf.confirmPoweroff) {
                                lockSurf.confirmPoweroff = true;
                                poweroffConfirmTimer.restart();
                            } else {
                                Quickshell.execDetached(["loginctl", "poweroff"]);
                            }
                        }
                    }
                }
            }
        }
    }
}
