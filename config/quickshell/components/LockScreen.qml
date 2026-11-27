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
import "../m3"

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
        if (!root.locked)
            return null;
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
        running: !(Quickshell.env("USER") || Quickshell.env("LOGNAME") || "")
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

            readonly property real uiScale: Math.max(0.75, Math.min(1.12, lockSurf.height / 1000))
            readonly property real cardW: Math.round(252 * uiScale)
            readonly property real cardH: Math.round(472 * uiScale)
            readonly property bool hasMedia: root.activePlayer !== null && (root.activePlayer.trackTitle || "").length > 0

            // Build 42-cell month calendar array matching real current month
            readonly property var monthCells: {
                const d = lockClock.date;
                const y = d.getFullYear();
                const m = d.getMonth();
                const firstDow = new Date(y, m, 1).getDay();
                const daysInMonth = new Date(y, m + 1, 0).getDate();
                const cells = [];
                for (let i = 0; i < firstDow; i++)
                    cells.push(0);
                for (let day = 1; day <= daysInMonth; day++)
                    cells.push(day);
                while (cells.length % 7 !== 0)
                    cells.push(0);
                return cells;
            }

            // Ambient Theme Scrim
            Rectangle {
                anchors.fill: parent
                opacity: lockSurf.cardVisible ? 1.0 : 0.0
                color: {
                    if (Theme.isSimple || ShellState.surfaceStyle === "oled")
                        return Theme.m3SurfaceLowest;
                    return Theme.isDark
                        ? Qt.rgba(0.03, 0.03, 0.05, 0.70)
                        : Qt.rgba(0.95, 0.94, 0.96, 0.66);
                }

                Behavior on opacity {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
            }

            // ================= M3 Expressive 3-Card Hero Row (DarkShadowShell LockCards) =================
            Row {
                id: cardsRow
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(24, Math.round((lockSurf.height - lockSurf.cardH) / 2 - lockSurf.height * 0.045))
                spacing: Math.round(18 * lockSurf.uiScale)
                opacity: lockSurf.cardVisible ? 1.0 : 0.0
                scale: Theme.reducedMotion ? 1.0 : (root._unlocking ? 1.04 : (root._revealed ? 1.0 : 0.94))

                Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }

                // --- Card 1: Month & Today Calendar ---
                Rectangle {
                    width: lockSurf.cardW
                    height: lockSurf.cardH
                    radius: Theme.r(32)
                    color: Theme.m3PanelBg
                    border.width: 1
                    border.color: Theme.m3Line
                    clip: true

                    Text {
                        x: 22
                        y: 12
                        width: parent.width - 36
                        text: Qt.formatDate(lockClock.date, "MMM").toUpperCase()
                        color: Theme.m3Primary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(74 * lockSurf.uiScale)
                        font.weight: Font.Black
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 36
                    }

                    Column {
                        x: 24
                        y: Math.round(112 * lockSurf.uiScale)
                        spacing: 3

                        Text {
                            text: Qt.formatDate(lockClock.date, "dddd d")
                            color: Theme.m3Ink
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(20 * lockSurf.uiScale)
                            font.weight: Font.Bold
                        }

                        Text {
                            text: Qt.formatDate(lockClock.date, "MMMM yyyy")
                            color: Theme.m3InkDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(11 * lockSurf.uiScale)
                            font.weight: Font.Medium
                        }
                    }

                    Grid {
                        id: lockCalGrid
                        x: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 20
                        width: parent.width - 32
                        columns: 7
                        rowSpacing: Math.round(6 * lockSurf.uiScale)
                        columnSpacing: 0
                        readonly property real cellW: width / 7

                        Repeater {
                            model: ["S", "M", "T", "W", "T", "F", "S"]
                            delegate: Text {
                                required property string modelData
                                width: lockCalGrid.cellW
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                color: Theme.m3InkDim
                                opacity: 0.72
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.round(10 * lockSurf.uiScale)
                                font.weight: Font.Bold
                            }
                        }

                        Repeater {
                            model: lockSurf.monthCells
                            delegate: Item {
                                id: dayCell
                                required property int modelData
                                readonly property bool isToday: dayCell.modelData > 0 && dayCell.modelData === lockClock.date.getDate()
                                width: lockCalGrid.cellW
                                height: Math.round(28 * lockSurf.uiScale)

                                M3Blob {
                                    anchors.centerIn: parent
                                    visible: dayCell.isToday
                                    width: Math.round(28 * lockSurf.uiScale)
                                    height: width
                                    kind: "cookie"
                                    color: Theme.m3Primary

                                    RotationAnimator on rotation {
                                        from: 0
                                        to: 360
                                        duration: 30000
                                        loops: Animation.Infinite
                                        running: dayCell.visible && lockSurf.cardVisible && !Theme.reducedMotion
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: dayCell.modelData > 0 ? String(dayCell.modelData) : ""
                                    color: dayCell.isToday ? Theme.m3OnPrimary : Theme.m3Ink
                                    opacity: dayCell.isToday ? 1.0 : 0.85
                                    font.family: Theme.monoFont
                                    font.pixelSize: Math.round(11 * lockSurf.uiScale)
                                    font.weight: dayCell.isToday ? Font.Bold : Font.Medium
                                }
                            }
                        }
                    }
                }

                // --- Card 2: Stacked Time + Expressive Wavy Seconds Ring ---
                Rectangle {
                    width: lockSurf.cardW
                    height: lockSurf.cardH
                    radius: Theme.r(32)
                    color: Theme.m3PanelBg
                    border.width: 1
                    border.color: Theme.m3Line
                    clip: true

                    // Auth Activity Strip
                    Rectangle {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 3
                        radius: 1.5
                        visible: root.authenticating
                        width: parent.width * 0.55
                        color: Theme.m3Primary

                        SequentialAnimation on opacity {
                            running: root.authenticating && !Theme.reducedMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 420; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 16
                        text: root.greetingText(lockClock.date)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.m3Primary
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.round(44 * lockSurf.uiScale)
                        spacing: Math.round(-28 * lockSurf.uiScale)

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatTime(lockClock.date, "hh")
                            color: Theme.m3Ink
                            font.family: Theme.monoFont
                            font.pixelSize: Math.round(116 * lockSurf.uiScale)
                            font.weight: Font.Black
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatTime(lockClock.date, "mm")
                            color: Theme.m3Primary
                            font.family: Theme.monoFont
                            font.pixelSize: Math.round(116 * lockSurf.uiScale)
                            font.weight: Font.Black
                        }
                    }

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Math.round(28 * lockSurf.uiScale)
                        width: Math.round(116 * lockSurf.uiScale)
                        height: width

                        M3Blob {
                            anchors.fill: parent
                            kind: ShellState.m3Shape
                            color: Theme.m3PrimaryContainer

                            RotationAnimator on rotation {
                                from: 0
                                to: 360
                                duration: 55000
                                loops: Animation.Infinite
                                running: lockSurf.cardVisible && !Theme.reducedMotion
                            }
                        }

                        M3WavyArc {
                            anchors.fill: parent
                            anchors.margins: 10
                            value: Math.max(0.02, lockClock.date.getSeconds() / 60.0)
                            thick: ShellState.m3WaveThick
                            wavy: ShellState.m3WavyProgress
                            moving: lockSurf.cardVisible && !Theme.reducedMotion
                            color: Theme.m3Primary
                            track: Theme.m3Track
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Qt.formatTime(lockClock.date, "ss")
                            color: Theme.m3OnPrimaryContainer
                            font.family: Theme.monoFont
                            font.pixelSize: Math.round(24 * lockSurf.uiScale)
                            font.weight: Font.Bold
                        }
                    }
                }

                // --- Card 3: Music Controller OR Session Profile ---
                Rectangle {
                    width: lockSurf.cardW
                    height: lockSurf.cardH
                    radius: Theme.r(32)
                    color: Theme.m3PanelBg
                    border.width: 1
                    border.color: Theme.m3Line
                    clip: true

                    // Media Card Content
                    Item {
                        anchors.fill: parent
                        visible: lockSurf.hasMedia

                        Text {
                            x: 20
                            y: 18
                            width: parent.width - 40
                            text: root.activePlayer ? (root.activePlayer.trackTitle || "") : ""
                            color: Theme.m3Ink
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(22 * lockSurf.uiScale)
                            font.weight: Font.Black
                            lineHeight: 0.95
                        }

                        Rectangle {
                            x: 20
                            y: Math.round(parent.height * 0.23)
                            height: 26
                            radius: Theme.r(13)
                            width: Math.min(parent.width - 40, artistLbl.implicitWidth + 22)
                            color: Theme.m3Primary

                            Text {
                                id: artistLbl
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, parent.width - 20)
                                elide: Text.ElideRight
                                text: root.activePlayer ? (root.activePlayer.trackArtist || "Now Playing") : ""
                                color: Theme.m3OnPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                        }

                        M3ShapeImage {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.round(parent.height * 0.34)
                            width: parent.width - 44
                            height: Math.round(parent.height * 0.37)
                            kind: ShellState.m3Shape
                            source: (root.activePlayer && root.activePlayer.trackArtUrl) ? root.activePlayer.trackArtUrl : ""
                            empty: Theme.m3SurfaceC
                            fallbackGlyph: (root.activePlayer && root.activePlayer.isPlaying) ? "󰎈" : "󰏤"
                            fallbackColor: Theme.m3Primary
                            spinning: false
                        }

                        M3WavyLine {
                            x: 20
                            width: parent.width - 40
                            height: 14
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 66
                            value: (root.activePlayer && root.activePlayer.length > 0)
                                ? Math.max(0.0, Math.min(1.0, root.activePlayer.position / root.activePlayer.length))
                                : 0.0
                            moving: root.activePlayer ? !!root.activePlayer.isPlaying : false
                            wavy: ShellState.m3WavyProgress
                            thick: ShellState.m3WaveThick
                            seekable: !!(root.activePlayer && root.activePlayer.canSeek)
                            color: Theme.m3Primary
                            track: Theme.m3Track
                            onMoved: v => {
                                if (root.activePlayer && root.activePlayer.canSeek && root.activePlayer.length > 0)
                                    root.activePlayer.position = v * root.activePlayer.length;
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 16
                            spacing: 8

                            Rectangle {
                                width: 54
                                height: 38
                                radius: Theme.r(prevMouse.pressed ? 11 : 19)
                                color: prevMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒮"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 16
                                    color: Theme.m3Ink
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
                                width: 72
                                height: 38
                                radius: Theme.r(mediaMouse.pressed ? 12 : 19)
                                color: mediaMouse.containsMouse ? Qt.lighter(Theme.m3Primary, 1.08) : Theme.m3Primary

                                Text {
                                    anchors.centerIn: parent
                                    text: (root.activePlayer && root.activePlayer.isPlaying) ? "󰏤" : "󰐊"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 18
                                    color: Theme.m3OnPrimary
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
                                width: 54
                                height: 38
                                radius: Theme.r(nextMouse.pressed ? 11 : 19)
                                color: nextMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒭"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 16
                                    color: Theme.m3Ink
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

                    // Fallback Session Profile Card (when no media playing)
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 40
                        visible: !lockSurf.hasMedia
                        spacing: 14

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: Math.round(108 * lockSurf.uiScale)
                            height: width

                            M3Blob {
                                anchors.fill: parent
                                kind: ShellState.m3Shape
                                color: Theme.m3PrimaryContainer
                            }

                            Text {
                                anchors.centerIn: parent
                                text: root.currentUser.length > 0 ? root.currentUser[0].toUpperCase() : "A"
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.round(40 * lockSurf.uiScale)
                                font.weight: Font.Black
                                color: Theme.m3OnPrimaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.currentUser
                                font.family: Theme.fontFamily
                                font.pixelSize: 18
                                font.weight: Font.Bold
                                color: Theme.m3Ink
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: DeviceCaps.hostname.length > 0 ? DeviceCaps.hostname : "Wayland Session"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.m3InkDim
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitHeight: 28
                            implicitWidth: lockedLbl.implicitWidth + 24
                            radius: Theme.r(14)
                            color: Theme.m3SecondaryContainer

                            Text {
                                id: lockedLbl
                                anchors.centerIn: parent
                                text: "󰌾  Session Locked"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: Theme.m3OnSecondaryContainer
                            }
                        }
                    }
                }
            }

            // Floating Error Banner above Bottom Pill Dock
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: bottomDock.top
                anchors.bottomMargin: 12
                visible: root.errorText.length > 0 && lockSurf.cardVisible
                height: 32
                width: errTxt.implicitWidth + 28
                radius: Theme.r(16)
                color: Theme.m3ErrorContainer
                border.width: 1
                border.color: Theme.m3Error

                Text {
                    id: errTxt
                    anchors.centerIn: parent
                    text: root.errorText
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: Theme.m3OnErrorContainer
                }
            }

            // ================= Bottom Floating Pill Dock =================
            Row {
                id: bottomDock
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(32 * lockSurf.uiScale)
                spacing: 10
                opacity: lockSurf.cardVisible ? 1.0 : 0.0
                transform: Translate {
                    y: Theme.reducedMotion ? 0 : (lockSurf.cardVisible ? 0 : 24)
                    Behavior on y { enabled: !Theme.reducedMotion; NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
                }
                Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                // Left Info Pill (Battery + Keyboard Layout + DND)
                Rectangle {
                    visible: DeviceCaps.hasBattery || root.kbLayoutShort.length > 0 || ShellState.dnd
                    height: 54
                    radius: Theme.r(27)
                    width: leftDockRow.implicitWidth + 18
                    color: Theme.m3PanelBg
                    border.width: 1
                    border.color: Theme.m3Line

                    Row {
                        id: leftDockRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            visible: DeviceCaps.hasBattery
                            height: 38
                            radius: Theme.r(19)
                            width: batDockRow.implicitWidth + 20
                            color: Theme.m3SurfaceC

                            Row {
                                id: batDockRow
                                anchors.centerIn: parent
                                spacing: 6

                                Item {
                                    width: 20
                                    height: 20
                                    anchors.verticalCenter: parent.verticalCenter

                                    M3WavyArc {
                                        anchors.fill: parent
                                        value: Math.max(0.04, DeviceCaps.batteryPercent / 100.0)
                                        thick: 3
                                        wavy: false
                                        color: DeviceCaps.batteryLow ? Theme.m3Error : Theme.m3Primary
                                        track: Theme.m3Track
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: DeviceCaps.batteryPercent + "%"
                                    font.family: Theme.monoFont
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: Theme.m3Ink
                                }
                            }
                        }

                        Rectangle {
                            visible: root.kbLayoutShort.length > 0
                            height: 38
                            radius: Theme.r(19)
                            width: kbDockRow.implicitWidth + 20
                            color: kbChipMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC

                            Row {
                                id: kbDockRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰌌"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 13
                                    color: Theme.m3Primary
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.kbLayoutShort
                                    font.family: Theme.monoFont
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: Theme.m3Ink
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
                            visible: ShellState.dnd
                            width: 38
                            height: 38
                            radius: Theme.r(19)
                            color: Theme.m3SecondaryContainer

                            Text {
                                anchors.centerIn: parent
                                text: "󰂛"
                                font.family: Theme.iconFont
                                font.pixelSize: 14
                                color: Theme.m3OnSecondaryContainer
                            }
                        }
                    }
                }

                // Center Password Capsule with Failure Shake
                Rectangle {
                    id: pwdBox
                    height: 54
                    width: Math.round(360 * Math.min(1.0, lockSurf.uiScale))
                    radius: Theme.r(27)
                    color: root.errorText.length > 0 ? Theme.m3ErrorContainer : Theme.m3PanelBg
                    border.width: pwdInput.activeFocus || root.errorText.length > 0 ? 2 : 1
                    border.color: root.errorText.length > 0
                        ? Theme.m3Error
                        : (pwdInput.activeFocus ? Theme.m3Primary : Theme.m3Line)

                    Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }
                    Behavior on border.color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }

                    transform: Translate {
                        id: pwdShake
                        x: 0
                    }

                    SequentialAnimation {
                        id: shakeAnim
                        NumberAnimation { target: pwdShake; property: "x"; to: -14; duration: 45; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: pwdShake; property: "x"; to: 14;  duration: 50; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: pwdShake; property: "x"; to: -10; duration: 50; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: pwdShake; property: "x"; to: 6;   duration: 45; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: pwdShake; property: "x"; to: 0;   duration: 45; easing.type: Easing.InOutQuad }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 8
                        spacing: 10

                        Text {
                            id: lockIconGlyph
                            text: root.authenticating ? "󰦖" : "󰌾"
                            font.family: Theme.iconFont
                            font.pixelSize: 17
                            color: root.errorText.length > 0
                                ? Theme.m3OnErrorContainer
                                : (pwdInput.activeFocus ? Theme.m3Primary : Theme.m3InkDim)

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
                                text: root.authenticating ? "Verifying..." : "Enter password..."
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: root.errorText.length > 0 ? Theme.m3OnErrorContainer : Theme.m3InkDim
                            }

                            TextInput {
                                id: pwdInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                enabled: !root.authenticating && !root._unlocking
                                color: root.errorText.length > 0 ? Theme.m3OnErrorContainer : Theme.m3Ink
                                selectionColor: Theme.m3Primary
                                selectedTextColor: Theme.m3OnPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
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

                        Rectangle {
                            width: 34
                            height: 34
                            radius: Theme.r(17)
                            color: eyeMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: root.showPassword ? "󰈉" : "󰈈"
                                font.family: Theme.iconFont
                                font.pixelSize: 14
                                color: root.showPassword ? Theme.m3Primary : Theme.m3InkDim
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
                            width: 38
                            height: 38
                            radius: Theme.r(submitMouse.pressed ? 12 : 19)
                            color: submitMouse.containsMouse ? Qt.lighter(Theme.m3Primary, 1.08) : Theme.m3Primary

                            Text {
                                anchors.centerIn: parent
                                text: "󰌍"
                                font.family: Theme.iconFont
                                font.pixelSize: 16
                                color: Theme.m3OnPrimary
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

                // Right Power Pill (Suspend / Reboot / Poweroff)
                Rectangle {
                    height: 54
                    radius: Theme.r(27)
                    width: lockPowerRow.implicitWidth + 16
                    color: Theme.m3PanelBg
                    border.width: 1
                    border.color: Theme.m3Line

                    Row {
                        id: lockPowerRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            width: 38
                            height: 38
                            radius: Theme.r(19)
                            color: suspMouse.containsMouse ? Theme.m3SecondaryContainer : Theme.m3SurfaceC

                            Text {
                                anchors.centerIn: parent
                                text: "󰒲"
                                font.family: Theme.iconFont
                                font.pixelSize: 15
                                color: suspMouse.containsMouse ? Theme.m3OnSecondaryContainer : Theme.m3Ink
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
                            height: 38
                            width: isPending ? rebConfirmTxt.implicitWidth + 24 : 38
                            radius: Theme.r(19)
                            color: rebootBtn.isPending
                                ? Theme.warning
                                : (rebMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC)

                            Row {
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰜉"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 15
                                    color: rebootBtn.isPending ? Theme.m3OnPrimary : Theme.warning
                                }

                                Text {
                                    id: rebConfirmTxt
                                    visible: rebootBtn.isPending
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Reboot?"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Theme.m3OnPrimary
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
                            height: 38
                            width: isPending ? pwrConfirmTxt.implicitWidth + 24 : 38
                            radius: Theme.r(19)
                            color: powerBtn.isPending
                                ? Theme.m3Error
                                : (pwrMouse.containsMouse ? Theme.m3ErrorContainer : Theme.m3SurfaceC)

                            Row {
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰐥"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 15
                                    color: powerBtn.isPending ? Theme.m3OnPrimary : Theme.m3Error
                                }

                                Text {
                                    id: pwrConfirmTxt
                                    visible: powerBtn.isPending
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Off?"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Theme.m3OnPrimary
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
}
