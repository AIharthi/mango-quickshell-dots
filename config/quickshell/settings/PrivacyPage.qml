pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property bool rememberRecent: true
    property bool rememberApps: true
    property bool disableCamera: false
    property bool disableMicrophone: false
    property bool hideIdentity: false
    property bool recentExists: false
    property real recentSizeKb: 0.0
    property bool disableMiddlePaste: false
    property bool sddmInstalled: false
    property bool sddmWritable: false
    property bool sddmActive: false
    property string statusMsg: ""

    function refresh(): void {
        if (!privProc.running)
            privProc.running = true;
        if (!localProc.running)
            localProc.running = true;
        if (!sddmStatusProc.running)
            sddmStatusProc.running = true;
    }

    function setPrivacy(key: string, val: bool): void {
        if (mutProc.running)
            return;
        mutProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "privacy-set", key, val ? "true" : "false"];
        mutProc.running = true;
    }

    function toggleMiddlePaste(): void {
        const nextDisable = !root.disableMiddlePaste;
        root.disableMiddlePaste = nextDisable;
        Quickshell.execDetached([Quickshell.shellPath("scripts/apply-local-setting.sh"), "set", "disable_middle_paste", nextDisable ? "1" : "0"]);
        Quickshell.execDetached([Quickshell.shellPath("scripts/manage-system.sh"), "gtk-set", "gtk-enable-primary-paste", nextDisable ? "false" : "true"]);
    }

    function applyPrivPayload(raw: string): void {
        const txt = (raw || "").trim();
        if (txt.length === 0)
            return;
        try {
            const d = JSON.parse(txt);
            if (d.rememberRecent !== undefined) root.rememberRecent = !!d.rememberRecent;
            if (d.rememberApps !== undefined) root.rememberApps = !!d.rememberApps;
            if (d.disableCamera !== undefined) root.disableCamera = !!d.disableCamera;
            if (d.disableMicrophone !== undefined) root.disableMicrophone = !!d.disableMicrophone;
            if (d.hideIdentity !== undefined) root.hideIdentity = !!d.hideIdentity;
            if (d.recentExists !== undefined) root.recentExists = !!d.recentExists;
            if (d.recentSizeKb !== undefined) root.recentSizeKb = Number(d.recentSizeKb || 0);
        } catch (err) {}
    }

    Component.onCompleted: refresh()

    Process {
        id: privProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "privacy-get"]
        stdout: StdioCollector {
            onStreamFinished: root.applyPrivPayload(text)
        }
    }

    Process {
        id: mutProc
        stdout: StdioCollector {
            onStreamFinished: root.applyPrivPayload(text)
        }
    }

    Process {
        id: localProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (typeof d.disable_middle_paste === "boolean")
                        root.disableMiddlePaste = d.disable_middle_paste;
                } catch (err) {}
            }
        }
    }

    Process {
        id: clipClearProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "clear-clipboard"]
        onExited: root.statusMsg = "Clipboard & primary selection cleared"
    }

    Process {
        id: recentClearProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "clear-recent"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.applyPrivPayload(text);
                root.statusMsg = "Recently opened files log wiped";
            }
        }
    }

    Process {
        id: sddmStatusProc
        command: [Quickshell.shellPath("scripts/sync-sddm-theme.sh"), "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    root.sddmInstalled = !!d.installed;
                    root.sddmWritable = !!d.writable;
                    root.sddmActive = !!d.active;
                } catch (err) {}
            }
        }
    }

    Process {
        id: sddmSyncProc
        command: [Quickshell.shellPath("scripts/sync-sddm-theme.sh")]
        onExited: exitCode => {
            root.statusMsg = (exitCode === 0)
                ? "SDDM Mango Island theme synced with current wallpaper & palette"
                : "Unable to sync SDDM theme (check permissions)";
            if (!sddmStatusProc.running)
                sddmStatusProc.running = true;
        }
    }

    // --- 1. Clipboard & Primary Selection ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: clipCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: clipCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Clipboard & selection privacy"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Disable Middle-Click Primary Paste"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Prevents accidental pasting of highlighted text across MangoWC & GTK"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: root.disableMiddlePaste
                    onToggled: root.toggleMiddlePaste()
                }
            }

            RowLayout {
                visible: DeviceCaps.hasClipboard
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Wipe sensitive text or screenshots stored in Wayland clipboard"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: clrClipRow.implicitWidth + 16
                    radius: Theme.r(8)
                    color: clrClipMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.20) : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: clrClipMouse.containsMouse ? Theme.error : Theme.cardBorder

                    RowLayout {
                        id: clrClipRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            text: "󰆴"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(12)
                            color: clrClipMouse.containsMouse ? Theme.error : Theme.primary
                        }

                        Text {
                            text: "Clear Clipboard"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: clrClipMouse.containsMouse ? Theme.error : Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: clrClipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!clipClearProc.running)
                                clipClearProc.running = true;
                        }
                    }
                }
            }
        }
    }

    // --- 2. History & Telemetry Privacy ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: histCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: histCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "File history & account privacy"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Remember Recently Opened Files"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.rememberRecent
                    onToggled: root.setPrivacy("remember-recent-files", !root.rememberRecent)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: root.recentExists
                        ? ("Recent files index (~/.local/share/recently-used.xbel · " + root.recentSizeKb + " KB)")
                        : "Recent files history is empty"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    visible: root.recentExists
                    implicitHeight: 26
                    implicitWidth: clrRecLbl.implicitWidth + 14
                    radius: Theme.r(7)
                    color: clrRecMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.20) : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: clrRecLbl
                        anchors.centerIn: parent
                        text: "Clear Recent History"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: clrRecMouse.containsMouse ? Theme.error : Theme.fgSurface
                    }

                    MouseArea {
                        id: clrRecMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!recentClearProc.running)
                                recentClearProc.running = true;
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Remember Application Usage Statistics"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.rememberApps
                    onToggled: root.setPrivacy("remember-app-usage", !root.rememberApps)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Hide User Identity in App Portals"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.hideIdentity
                    onToggled: root.setPrivacy("hide-identity", !root.hideIdentity)
                }
            }
        }
    }

    // --- 3. Sensor & Session Security ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: secCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: secCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Camera, microphone & screen lock"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Disable Camera in Desktop Portals"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.disableCamera
                    activeColor: Theme.warning
                    onToggled: root.setPrivacy("disable-camera", !root.disableCamera)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Disable & Mute Microphone Input"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.disableMicrophone
                    activeColor: Theme.warning
                    onToggled: root.setPrivacy("disable-microphone", !root.disableMicrophone)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Wayland Screen Locker"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }

                    Text {
                        text: DeviceCaps.hasLocker
                            ? ("Active locker: " + DeviceCaps.lockerCmd + " (Super + Shift + L)")
                            : "No locker installed (install swaylock, hyprlock, or waylock)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    visible: DeviceCaps.hasLocker
                    implicitHeight: 28
                    implicitWidth: lockNowLbl.implicitWidth + 16
                    radius: Theme.r(8)
                    color: lockNowMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: lockNowLbl
                        anchors.centerIn: parent
                        text: "Lock Now"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: lockNowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/lock.sh")])
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.outlineVariant
            }

            Text {
                text: "Idle lock & auto-suspend"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Auto-Lock on Inactivity"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }
                    Text {
                        text: "Paused automatically when Keep Awake or fullscreen inhibitor is active"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.idleLockEnabled
                    onToggled: ShellState.setPref("idleLockEnabled", !ShellState.idleLockEnabled)
                }
            }

            StepControl {
                label: "Idle Lock Timeout"
                displayValue: Math.round(ShellState.idleLockSeconds / 60) + "m"
                controlEnabled: ShellState.idleLockEnabled
                onDecremented: ShellState.setPref("idleLockSeconds", Math.max(60, ShellState.idleLockSeconds - 60))
                onIncremented: ShellState.setPref("idleLockSeconds", Math.min(3600, ShellState.idleLockSeconds + 60))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Auto-Suspend on Extended Inactivity"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.idleSuspendEnabled
                    onToggled: ShellState.setPref("idleSuspendEnabled", !ShellState.idleSuspendEnabled)
                }
            }

            StepControl {
                label: "Auto-Suspend Timeout"
                displayValue: Math.round(ShellState.idleSuspendSeconds / 60) + "m"
                controlEnabled: ShellState.idleSuspendEnabled
                onDecremented: ShellState.setPref("idleSuspendSeconds", Math.max(120, ShellState.idleSuspendSeconds - 60))
                onIncremented: ShellState.setPref("idleSuspendSeconds", Math.min(7200, ShellState.idleSuspendSeconds + 60))
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.outlineVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "SDDM Login Theme Sync (mango-island)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }
                    Text {
                        text: root.sddmInstalled
                            ? ((root.sddmActive ? "Active · " : "Installed · ") + (root.sddmWritable ? "Auto-syncing theme & wallpaper" : "Run install.sh --with-sddm to enable user sync"))
                            : "Not installed yet. Run ./install.sh --with-sddm"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    visible: root.sddmInstalled && root.sddmWritable
                    implicitHeight: 28
                    implicitWidth: syncSddmLbl.implicitWidth + 16
                    radius: Theme.r(8)
                    color: syncSddmMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: syncSddmLbl
                        anchors.centerIn: parent
                        text: "Sync SDDM Now"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: syncSddmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!sddmSyncProc.running)
                                sddmSyncProc.running = true;
                        }
                    }
                }
            }

            Text {
                visible: root.statusMsg.length > 0
                text: root.statusMsg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.success
            }
        }
    }
}
