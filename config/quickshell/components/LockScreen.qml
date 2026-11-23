pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import ".."

Item {
    id: root

    property bool locked: false
    property bool _revealed: false
    property bool _unlocking: false
    property bool showPassword: false
    property string errorText: ""
    property bool authenticating: false
    property string currentUser: String(Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user")
    property string kbLayoutShort: ""
    property string _pendingPwd: ""

    signal clearInputs()
    signal authFailedShake()

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

    function greetingText(dt: var): string {
        const hr = dt ? dt.getHours() : (new Date()).getHours();
        const prefix = hr < 12 ? "Good Morning" : (hr < 18 ? "Good Afternoon" : "Good Evening");
        return prefix + ", " + root.currentUser;
    }

    function lock(): void {
        if (root.locked)
            return;
        unlockDelayTimer.stop();
        root.errorText = "";
        root.authenticating = false;
        root._pendingPwd = "";
        root._unlocking = false;
        root._revealed = false;
        root.showPassword = false;
        root.clearInputs();
        root.locked = true;
        if (!kbProc.running)
            kbProc.running = true;
        if (!pam.active)
            pam.start();
        if (Theme.reducedMotion)
            root._revealed = true;
        else
            revealTimer.restart();
    }

    function unlock(): void {
        revealTimer.stop();
        unlockDelayTimer.stop();
        root._pendingPwd = "";
        root.authenticating = false;
        root.errorText = "";
        root.clearInputs();
        if (pam.active)
            pam.abort();
        if (Theme.reducedMotion) {
            root._revealed = false;
            root._unlocking = false;
            root.locked = false;
        } else {
            root._unlocking = true;
            unlockDelayTimer.restart();
        }
    }

    function finishAuthUnlock(): void {
        if (Theme.reducedMotion) {
            root._revealed = false;
            root._unlocking = false;
            root.locked = false;
        } else {
            root._unlocking = true;
            unlockDelayTimer.restart();
        }
    }

    function submitPassword(pwd: string): void {
        if (root.authenticating || root._unlocking)
            return;
        if (!pwd || pwd.length === 0) {
            root.errorText = "Enter your password";
            root.authFailedShake();
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
                    root.authFailedShake();
                }
            }
        }
    }

    function cycleKeyboardLayout(): void {
        Quickshell.execDetached(["mmsg", "dispatch", "switch_keyboard_layout"]);
        kbRefreshDelay.restart();
    }

    Timer {
        id: revealTimer
        interval: 25
        repeat: false
        onTriggered: {
            if (root.locked && !root._unlocking)
                root._revealed = true;
        }
    }

    Timer {
        id: unlockDelayTimer
        interval: 210
        repeat: false
        onTriggered: {
            root._revealed = false;
            root._unlocking = false;
            root.locked = false;
        }
    }

    Timer {
        id: kbRefreshDelay
        interval: 120
        repeat: false
        onTriggered: {
            if (!kbProc.running)
                kbProc.running = true;
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
                root.finishAuthUnlock();
            } else {
                root.errorText = (result === PamResult.MaxTries)
                    ? "Too many attempts. Wait a moment."
                    : "Incorrect password. Try again.";
                root.authFailedShake();
                if (root.locked && !pam.active)
                    pam.start();
            }
        }

        onError: err => {
            root.authenticating = false;
            root._pendingPwd = "";
            root.errorText = "PAM error: " + PamError.toString(err);
            root.authFailedShake();
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

            property string confirmPowerAction: ""
            readonly property bool cardVisible: root._revealed && !root._unlocking

            SystemClock {
                id: lockClock
                precision: SystemClock.Seconds
            }

            Connections {
                target: root
                function onClearInputs(): void {
                    pwdInput.text = "";
                }
                function onAuthFailedShake(): void {
                    if (!Theme.reducedMotion)
                        shakeAnim.restart();
                    pwdInput.forceActiveFocus();
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
                id: powerConfirmTimer
                interval: 4000
                repeat: false
                onTriggered: lockSurf.confirmPowerAction = ""
            }

            // Wallpaper Layer with smooth entrance zoom-out
            Image {
                anchors.fill: parent
                visible: !Theme.isSimple && ShellState.surfaceStyle !== "oled" && Theme.wallpaperPath.length > 0
                source: Theme.wallpaperPath.length > 0 ? ("file://" + Theme.wallpaperPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(Math.max(1, lockSurf.width), Math.max(1, lockSurf.height))
                opacity: lockSurf.cardVisible ? 1.0 : 0.0
                scale: Theme.reducedMotion ? 1.0 : (root._unlocking ? 1.04 : (root._revealed ? 1.0 : 1.07))

                Behavior on opacity {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
                }
            }

            // Ambient Theme Scrim
            Rectangle {
                anchors.fill: parent
                opacity: lockSurf.cardVisible ? 1.0 : 0.0
                color: {
                    if (Theme.isSimple || ShellState.surfaceStyle === "oled")
                        return Theme.surfaceContainerLowest;
                    return Theme.isDark
                        ? Qt.rgba(0.03, 0.03, 0.06, 0.72)
                        : Qt.rgba(0.94, 0.94, 0.97, 0.68);
                }

                Behavior on opacity {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
            }

            // Main Lock Card with entrance/exit choreography
            Rectangle {
                id: mainCard
                anchors.centerIn: parent
                width: Math.min(450, Math.max(310, lockSurf.width - 48))
                implicitHeight: cardCol.implicitHeight + 52
                radius: Theme.r(28)
                color: Theme.notchBg
                border.width: Math.max(1, Theme.islandBorderWidth)
                border.color: root.errorText.length > 0 ? Theme.error : Theme.islandBorder
                clip: true

                opacity: lockSurf.cardVisible ? 1.0 : 0.0
                scale: Theme.reducedMotion ? 1.0 : (root._unlocking ? 1.04 : (root._revealed ? 1.0 : 0.93))
                transform: Translate {
                    y: Theme.reducedMotion ? 0 : (root._unlocking ? -14 : (root._revealed ? 0 : 26))
                    Behavior on y {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
                    }
                }

                Behavior on opacity {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
                }
                Behavior on border.color {
                    enabled: !Theme.reducedMotion
                    ColorAnimation { duration: 160 }
                }

                // Subtle glass specular top sheen
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 52
                    radius: parent.radius
                    visible: Theme.showGlassSheen
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.34) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // Ambient auth pulse bar at top of card
                Rectangle {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 3
                    radius: 1.5
                    visible: root.authenticating
                    width: parent.width * 0.55
                    color: Theme.primary

                    SequentialAnimation on opacity {
                        running: root.authenticating && !Theme.reducedMotion
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 420; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine }
                    }
                }

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 26
                    spacing: 13

                    // Greeting + Clock + Date
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.greetingText(lockClock.date)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Theme.primary
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: ShellState.formatTime(lockClock.date)
                            font.family: Theme.monoFont
                            font.pixelSize: 50
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

                    // Status Pill Strip (User, Layout Switcher, Battery, DND)
                    Flow {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6

                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: userChipRow.implicitWidth + 16
                            radius: Theme.r(12)
                            color: Theme.cardBg
                            border.width: Theme.subBorderWidth
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
                            color: kbChipMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                            border.width: Theme.subBorderWidth
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
                                    font.family: Theme.monoFont
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }
                            }

                            MouseArea {
                                id: kbChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cycleKeyboardLayout()
                            }
                        }

                        Rectangle {
                            visible: DeviceCaps.hasBattery
                            implicitHeight: 24
                            implicitWidth: batChipRow.implicitWidth + 14
                            radius: Theme.r(12)
                            color: Theme.cardBg
                            border.width: Theme.subBorderWidth
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
                                    font.family: Theme.monoFont
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
                            border.width: Theme.subBorderWidth
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

                    // Active Media Pill with Album Art + Transport Controls
                    Rectangle {
                        visible: root.activePlayer !== null && (root.activePlayer.trackTitle || "").length > 0
                        Layout.fillWidth: true
                        implicitHeight: 50
                        radius: Theme.r(14)
                        color: Theme.cardBg
                        border.width: Theme.subBorderWidth
                        border.color: Theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            ClippingRectangle {
                                implicitWidth: 34
                                implicitHeight: 34
                                radius: Theme.r(9)
                                color: Theme.primaryContainer

                                Image {
                                    id: lockArtImg
                                    anchors.fill: parent
                                    source: (root.activePlayer && root.activePlayer.trackArtUrl) ? root.activePlayer.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize: Qt.size(64, 64)
                                    visible: source.toString().length > 0 && status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !lockArtImg.visible
                                    text: (root.activePlayer && root.activePlayer.isPlaying) ? "󰎈" : "󰏤"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 16
                                    color: Theme.primary
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: root.activePlayer ? (root.activePlayer.trackTitle || "") : ""
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
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

                            RowLayout {
                                spacing: 4

                                Rectangle {
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    radius: Theme.r(12)
                                    color: prevMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒮"
                                        font.family: Theme.iconFont
                                        font.pixelSize: 11
                                        color: Theme.fgSurface
                                    }

                                    MouseArea {
                                        id: prevMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.activePlayer && root.activePlayer.canGoPrevious)
                                                root.activePlayer.previous();
                                        }
                                    }
                                }

                                Rectangle {
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    radius: Theme.r(14)
                                    color: mediaMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.activePlayer && root.activePlayer.isPlaying) ? "󰏤" : "󰐊"
                                        font.family: Theme.iconFont
                                        font.pixelSize: 13
                                        color: Theme.fgPrimary
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

                                Rectangle {
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    radius: Theme.r(12)
                                    color: nextMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒭"
                                        font.family: Theme.iconFont
                                        font.pixelSize: 11
                                        color: Theme.fgSurface
                                    }

                                    MouseArea {
                                        id: nextMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.activePlayer && root.activePlayer.canGoNext)
                                                root.activePlayer.next();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Password Input Box with horizontal failure shake
                    Rectangle {
                        id: pwdBox
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: Theme.r(14)
                        color: Theme.cardBg
                        border.width: pwdInput.activeFocus || root.errorText.length > 0 ? 1.5 : 1
                        border.color: root.errorText.length > 0
                            ? Theme.error
                            : (pwdInput.activeFocus ? Theme.primary : Theme.cardBorder)

                        Behavior on border.color {
                            enabled: !Theme.reducedMotion
                            ColorAnimation { duration: 150 }
                        }

                        transform: Translate {
                            id: pwdShake
                            x: 0
                        }

                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: pwdShake; property: "x"; to: -12; duration: 42; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pwdShake; property: "x"; to: 12;  duration: 42; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pwdShake; property: "x"; to: -9;  duration: 42; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pwdShake; property: "x"; to: 9;   duration: 42; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pwdShake; property: "x"; to: -4;  duration: 42; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pwdShake; property: "x"; to: 0;   duration: 42; easing.type: Easing.InOutQuad }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                id: lockIconGlyph
                                text: root.authenticating ? "󰦖" : "󰌾"
                                font.family: Theme.iconFont
                                font.pixelSize: 15
                                color: root.errorText.length > 0
                                    ? Theme.error
                                    : (pwdInput.activeFocus ? Theme.primary : Theme.fgSurfaceVariant)

                                RotationAnimation on rotation {
                                    from: 0
                                    to: 360
                                    duration: 900
                                    loops: Animation.Infinite
                                    running: root.authenticating && !Theme.reducedMotion
                                    onRunningChanged: {
                                        if (!running)
                                            lockIconGlyph.rotation = 0;
                                    }
                                }
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
                                    echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                    enabled: !root.authenticating && !root._unlocking
                                    color: Theme.fgSurface
                                    selectionColor: Theme.primary
                                    selectedTextColor: Theme.fgPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    clip: true

                                    onTextEdited: {
                                        if (root.errorText.length > 0)
                                            root.errorText = "";
                                    }
                                    Keys.onReturnPressed: root.submitPassword(text)
                                    Keys.onEnterPressed: root.submitPassword(text)
                                    Keys.onEscapePressed: {
                                        text = "";
                                        root.errorText = "";
                                    }
                                }
                            }

                            // Show/Hide password toggle
                            Rectangle {
                                implicitWidth: 28
                                implicitHeight: 28
                                radius: Theme.r(9)
                                color: eyeMouse.containsMouse ? Theme.hoverBg : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: root.showPassword ? "󰈉" : "󰈈"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 13
                                    color: root.showPassword ? Theme.primary : Theme.fgSurfaceVariant
                                }

                                MouseArea {
                                    id: eyeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.showPassword = !root.showPassword;
                                        pwdInput.forceActiveFocus();
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: 30
                                implicitHeight: 30
                                radius: Theme.r(10)
                                color: submitMouse.containsMouse ? Theme.primary : Theme.subCardBg
                                scale: submitMouse.pressed ? 0.92 : 1.0

                                Behavior on scale {
                                    enabled: !Theme.reducedMotion
                                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                                }

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

            // Bottom-Right Animated Session Power Controls
            Item {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                implicitWidth: lockPowerRow.implicitWidth
                implicitHeight: lockPowerRow.implicitHeight
                opacity: lockSurf.cardVisible ? 1.0 : 0.0
                transform: Translate {
                    y: Theme.reducedMotion ? 0 : (lockSurf.cardVisible ? 0 : 16)
                    Behavior on y {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 360; easing.type: Easing.OutCubic }
                    }
                }
                Behavior on opacity {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    id: lockPowerRow
                    anchors.fill: parent
                    spacing: 8

                Rectangle {
                    implicitHeight: 34
                    implicitWidth: suspRow.implicitWidth + 20
                    radius: Theme.r(17)
                    color: suspMouse.containsMouse ? Theme.hoverBg : Theme.notchBg
                    border.width: Math.max(1, Theme.cardBorderWidth)
                    border.color: Theme.cardBorder
                    scale: suspMouse.pressed ? 0.94 : 1.0

                    Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

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
                    id: rebootBtn
                    readonly property bool isPending: lockSurf.confirmPowerAction === "reboot"
                    implicitHeight: 34
                    implicitWidth: rebRow.implicitWidth + 20
                    radius: Theme.r(17)
                    color: rebootBtn.isPending
                        ? Theme.warning
                        : (rebMouse.containsMouse ? Theme.withAlpha(Theme.warning, 0.22) : Theme.notchBg)
                    border.width: Math.max(1, Theme.cardBorderWidth)
                    border.color: rebootBtn.isPending ? Theme.warning : Theme.cardBorder
                    scale: rebMouse.pressed ? 0.94 : 1.0

                    Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                    RowLayout {
                        id: rebRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "󰜉"
                            font.family: Theme.iconFont
                            font.pixelSize: 13
                            color: rebootBtn.isPending ? Theme.fgPrimary : Theme.warning
                        }
                        Text {
                            text: rebootBtn.isPending ? "Confirm Reboot?" : "Reboot"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: rebootBtn.isPending ? Theme.fgPrimary : Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: rebMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (lockSurf.confirmPowerAction !== "reboot") {
                                lockSurf.confirmPowerAction = "reboot";
                                powerConfirmTimer.restart();
                            } else {
                                Quickshell.execDetached(["loginctl", "reboot"]);
                            }
                        }
                    }
                }

                Rectangle {
                    id: powerBtn
                    readonly property bool isPending: lockSurf.confirmPowerAction === "poweroff"
                    implicitHeight: 34
                    implicitWidth: pwrRow.implicitWidth + 20
                    radius: Theme.r(17)
                    color: powerBtn.isPending
                        ? Theme.error
                        : (pwrMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.notchBg)
                    border.width: Math.max(1, Theme.cardBorderWidth)
                    border.color: powerBtn.isPending ? Theme.error : Theme.cardBorder
                    scale: pwrMouse.pressed ? 0.94 : 1.0

                    Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                    RowLayout {
                        id: pwrRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "󰐥"
                            font.family: Theme.iconFont
                            font.pixelSize: 13
                            color: powerBtn.isPending ? Theme.fgError : Theme.error
                        }
                        Text {
                            text: powerBtn.isPending ? "Confirm Poweroff?" : "Poweroff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: powerBtn.isPending ? Theme.fgError : Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: pwrMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (lockSurf.confirmPowerAction !== "poweroff") {
                                lockSurf.confirmPowerAction = "poweroff";
                                powerConfirmTimer.restart();
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
}
