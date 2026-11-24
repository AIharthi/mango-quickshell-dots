pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"

ColumnLayout {
    id: root
    spacing: 12

    property int overrideCount: 0
    property string activeCursor: "catppuccin-mocha-dark-cursors"
    property int activeCursorSize: 24

    property string cpuInfo: ""
    property var gpusInfo: []
    property real memUsedGb: 0
    property real memTotalGb: 0
    property int memUsedPct: 0
    property string uptimeStr: ""
    property string timezoneStr: ""
    property var powerProfiles: ({ hasPowerProfiles: false, active: "", available: [] })
    property var disks: []
    property var userInfo: ({ user: "", fullName: "", uid: 1000, shell: "", home: "", groups: [], lang: "", sessionType: "", desktop: "" })
    property var backupsList: []
    property string backupStatus: ""
    property var doctorReport: ({ ok: true, summary: "Running diagnostics...", passCount: 0, warnCount: 0, failCount: 0, checks: [] })
    property bool doctorRunning: false

    function runDoctor(): void {
        if (doctorProc.running)
            return;
        root.doctorRunning = true;
        doctorProc.running = true;
    }

    function loadOverrides(): void {
        if (!localProc.running)
            localProc.running = true;
        if (!sysInfoProc.running)
            sysInfoProc.running = true;
        if (!userProc.running)
            userProc.running = true;
        if (!backupsListProc.running)
            backupsListProc.running = true;
        runDoctor();
    }

    function exportBackup(): void {
        if (!backupProc.running)
            backupProc.running = true;
    }

    function restoreBackup(archivePath: string): void {
        const clean = (archivePath || "").trim();
        if (clean.length === 0 || restoreProc.running)
            return;
        restoreProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "restore-settings", clean];
        restoreProc.running = true;
    }

    function resetOverrides(): void {
        if (!resetProc.running)
            resetProc.running = true;
    }

    function setPowerProfile(prof: string): void {
        if (powerProfProc.running)
            return;
        powerProfProc.command = ["powerprofilesctl", "set", prof];
        powerProfProc.running = true;
    }

    Component.onCompleted: loadOverrides()

    SystemClock {
        id: sysClock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
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
                    if (typeof d.overrideCount === "number")
                        root.overrideCount = d.overrideCount;
                    if (typeof d.cursor_theme === "string")
                        root.activeCursor = d.cursor_theme;
                    if (typeof d.cursor_size === "number")
                        root.activeCursorSize = d.cursor_size;
                } catch (err) {}
            }
        }
    }

    Process {
        id: sysInfoProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "system-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d.cpu) root.cpuInfo = String(d.cpu);
                    if (Array.isArray(d.gpus)) root.gpusInfo = d.gpus;
                    if (d.memory) {
                        root.memUsedGb = Number(d.memory.usedGb || 0);
                        root.memTotalGb = Number(d.memory.totalGb || 0);
                        root.memUsedPct = Number(d.memory.usedPct || 0);
                    }
                    if (d.uptime) root.uptimeStr = String(d.uptime);
                    if (d.timezone) root.timezoneStr = String(d.timezone);
                    if (d.powerProfiles) root.powerProfiles = d.powerProfiles;
                    if (Array.isArray(d.disks)) root.disks = d.disks;
                } catch (err) {}
            }
        }
    }

    Process {
        id: powerProfProc
        onExited: {
            if (!sysInfoProc.running)
                sysInfoProc.running = true;
        }
    }

    Process {
        id: resetProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "reset"]
        onExited: root.loadOverrides()
    }

    Process {
        id: userProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "user-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (d && d.user) root.userInfo = d;
                } catch (err) {}
            }
        }
    }

    Process {
        id: backupProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "backup-settings"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (d && Array.isArray(d.backups))
                        root.backupsList = d.backups;
                    if (d && d.path)
                        root.backupStatus = "Saved backup: " + d.path + " (" + d.sizeKb + " KB)";
                } catch (err) {}
            }
        }
    }

    Process {
        id: backupsListProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "list-backups"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (d && Array.isArray(d.backups))
                        root.backupsList = d.backups;
                } catch (err) {}
            }
        }
    }

    Process {
        id: restoreProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (d && Array.isArray(d.backups))
                        root.backupsList = d.backups;
                    if (d && Array.isArray(d.restored)) {
                        root.backupStatus = "Restored " + d.restored.length + " config files from " + d.path;
                        sysReloadTimer.restart();
                    }
                } catch (err) {}
            }
        }
    }

    Process {
        id: doctorProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "doctor"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.doctorRunning = false;
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && Array.isArray(d.checks))
                        root.doctorReport = d;
                } catch (err) {}
            }
        }
        onExited: root.doctorRunning = false
    }

    // --- 0. Aurora Shell 2.0 · System Health Doctor ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: docCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: docCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: verLbl.implicitWidth + 12
                    radius: Theme.r(10)
                    color: Theme.withAlpha(Theme.primary, 0.18)

                    Text {
                        id: verLbl
                        anchors.centerIn: parent
                        text: "Aurora Shell 2.0"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                Text {
                    text: "System Doctor"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Text {
                    Layout.fillWidth: true
                    text: String(root.doctorReport.summary || "")
                    elide: Text.ElideRight
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(9)
                    color: Number(root.doctorReport.failCount || 0) > 0
                        ? Theme.error
                        : (Number(root.doctorReport.warnCount || 0) > 0 ? Theme.warning : Theme.success)
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: runDocLbl.implicitWidth + 16
                    radius: Theme.r(8)
                    color: runDocMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    border.width: 0

                    Text {
                        id: runDocLbl
                        anchors.centerIn: parent
                        text: root.doctorRunning ? "Checking..." : "󰑐 Run Diagnostics"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: runDocMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runDoctor()
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 8
                rowSpacing: 8
                visible: Array.isArray(root.doctorReport.checks) && root.doctorReport.checks.length > 0

                Repeater {
                    model: root.doctorReport.checks || []
                    delegate: Rectangle {
                        id: chkCard
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: chkCol.implicitHeight + 14
                        radius: Theme.r(10)
                        color: Theme.subCardBg
                        border.width: 0

                        ColumnLayout {
                            id: chkCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    implicitWidth: 7
                                    implicitHeight: 7
                                    radius: 3.5
                                    color: chkCard.modelData.status === "ok"
                                        ? Theme.success
                                        : (chkCard.modelData.status === "warn" ? Theme.warning : Theme.error)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(chkCard.modelData.label || "")
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Font.DemiBold
                                    color: Theme.fgSurface
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: String(chkCard.modelData.detail || "")
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 1. Device & Hardware Summary ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hostCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: hostCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "Device & hardware"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: Theme.r(10)
                    color: Theme.withAlpha(Theme.primary, 0.18)

                    Text {
                        anchors.centerIn: parent
                        text: DeviceCaps.deviceType === "laptop" ? "󰌢" : "󰍹"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(18)
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: (DeviceCaps.hostname || "localhost") + " · " + (DeviceCaps.deviceType === "laptop" ? "Laptop Profile" : "Desktop Profile")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        text: DeviceCaps.distro + " · Kernel " + DeviceCaps.kernel
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }

                    Text {
                        text: "Mode: " + Theme.shellMode.toUpperCase() + " · Cursor: " + root.activeCursor + " (" + root.activeCursorSize + "px)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.primary
                    }

                    Text {
                        visible: DeviceCaps.hasBattery
                        text: "Battery: " + DeviceCaps.batteryPercent + "% (" + DeviceCaps.batteryStatus + ")"
                            + (DeviceCaps.batteryWatts > 0 ? (" · " + DeviceCaps.batteryWatts.toFixed(1) + "W") : "")
                            + (DeviceCaps.batteryEta.length > 0 ? (" · " + DeviceCaps.batteryEta) : "")
                            + " · Health " + DeviceCaps.batteryHealth + "%"
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        color: DeviceCaps.batteryLow ? Theme.error : Theme.fgSurfaceVariant
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: cpuCol.implicitHeight + 12
                    radius: Theme.r(9)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: cpuCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2

                        Text {
                            text: "Processor & memory"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.cpuInfo.length > 0 ? root.cpuInfo : "Detecting CPU..."
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Text {
                            text: "RAM: " + root.memUsedGb.toFixed(1) + " / " + root.memTotalGb.toFixed(1) + " GB (" + root.memUsedPct + "%)"
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            color: Theme.secondary
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: gpuCol.implicitHeight + 12
                    radius: Theme.r(9)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: gpuCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2

                        Text {
                            text: "Graphics & session"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.gpusInfo.length > 0 ? root.gpusInfo.join(" + ") : "Wayland GPU"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Text {
                            text: "Up " + (root.uptimeStr || "-") + " · " + (root.timezoneStr || "Local")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.tertiary
                        }
                    }
                }
            }
        }
    }

    // --- 2. Date & Time Format ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: clockCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: clockCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰥔"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(14)
                    color: Theme.primary
                }

                Text {
                    Layout.fillWidth: true
                    text: "Date & time format"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: previewClockTxt.implicitWidth + 14
                    radius: Theme.r(7)
                    color: Theme.withAlpha(Theme.primary, 0.16)
                    border.width: Theme.subBorderWidth
                    border.color: Theme.withAlpha(Theme.primary, 0.4)

                    Text {
                        id: previewClockTxt
                        anchors.centerIn: parent
                        text: ShellState.formatTime(sysClock.date) + "  ·  " + ShellState.formatDate(sysClock.date)
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Use 24-Hour Clock"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.clock24h
                    onToggled: ShellState.setPref("clock24h", !ShellState.clock24h)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Show Seconds in Bar & Island"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.clockShowSeconds
                    onToggled: ShellState.setPref("clockShowSeconds", !ShellState.clockShowSeconds)
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: ["ddd d MMM", "yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy"]

                    delegate: Rectangle {
                        id: dfPill
                        required property string modelData
                        readonly property bool selected: ShellState.dateFormat === dfPill.modelData

                        implicitHeight: 24
                        implicitWidth: dfTxt.implicitWidth + 14
                        radius: Theme.r(7)
                        color: dfPill.selected
                            ? Theme.secondary
                            : (dfMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: dfPill.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.secondary

                        Text {
                            id: dfTxt
                            anchors.centerIn: parent
                            text: Qt.formatDateTime(sysClock.date, dfPill.modelData)
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: dfPill.selected ? Font.Bold : Font.Medium
                            color: dfPill.selected ? Theme.contrastInk(Theme.secondary) : Theme.fgSurface
                        }

                        MouseArea {
                            id: dfMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("dateFormat", dfPill.modelData)
                        }
                    }
                }
            }
        }
    }

    // --- 3. Disk Storage ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: diskCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: diskCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰋊"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(14)
                    color: Theme.secondary
                }

                Text {
                    Layout.fillWidth: true
                    text: "Disk storage"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }
            }

            Repeater {
                model: root.disks

                delegate: Rectangle {
                    id: diskRow
                    required property var modelData
                    readonly property int pct: Number(diskRow.modelData.usedPct || 0)
                    readonly property color barColor: diskRow.pct >= 88
                        ? Theme.error
                        : (diskRow.pct >= 72 ? Theme.warning : Theme.primary)

                    Layout.fillWidth: true
                    implicitHeight: diskInner.implicitHeight + 14
                    radius: Theme.r(10)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: diskInner
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: diskRow.modelData.mount
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            Text {
                                text: "(" + diskRow.modelData.device + " · " + diskRow.modelData.fs + ")"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: diskRow.modelData.usedGb + " / " + diskRow.modelData.totalGb + " GB (" + diskRow.modelData.availGb + " GB free)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 6
                            radius: Theme.r(3)
                            color: Theme.surfaceContainerHighest

                            Rectangle {
                                width: Math.max(0, Math.min(parent.width, parent.width * (diskRow.pct / 100.0)))
                                height: parent.height
                                radius: Theme.r(3)
                                color: diskRow.barColor

                                Behavior on width {
                                    enabled: !Theme.isSimple
                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.disks.length === 0
                text: "No mounted block storage reported"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurfaceVariant
            }
        }
    }

    // --- 4. Detected Hardware Capabilities ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: capCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: capCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Detected hardware capabilities"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: redetectLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: redetectMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: redetectLbl
                        anchors.centerIn: parent
                        text: "󰑐 Re-detect"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.primary
                    }

                    MouseArea {
                        id: redetectMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            DeviceCaps.refresh();
                            root.loadOverrides();
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 6
                columnSpacing: 6

                Repeater {
                    model: [
                        { label: "Audio",       ok: DeviceCaps.hasAudio },
                        { label: "Displays",    ok: DeviceCaps.hasWlrRandr },
                        { label: "Wi-Fi",       ok: DeviceCaps.hasWifi },
                        { label: "Bluetooth",   ok: DeviceCaps.hasBluetooth },
                        { label: "Battery",     ok: DeviceCaps.hasBattery },
                        { label: "Backlight",   ok: DeviceCaps.hasBacklight },
                        { label: "Touchpad",    ok: DeviceCaps.hasTouchpad },
                        { label: "Locker",      ok: DeviceCaps.hasLocker },
                        { label: "Night Light", ok: DeviceCaps.hasNightLight },
                        { label: "Power Prof.", ok: DeviceCaps.hasPowerProfiles },
                        { label: "XDG MIME",    ok: DeviceCaps.hasXdgMime },
                        { label: "Idle Inhib.", ok: true },
                        { label: "Network",     ok: DeviceCaps.hasNetwork },
                        { label: "NMCLI",       ok: DeviceCaps.hasNmcli },
                        { label: "DDC/CI",      ok: DeviceCaps.hasDdcutil },
                        { label: "Clipboard",   ok: DeviceCaps.hasClipboard }
                    ]

                    delegate: Rectangle {
                        id: capBadge
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: capBadge.modelData.ok
                            ? Theme.withAlpha(Theme.success, 0.16)
                            : Theme.subCardBg
                        border.width: Theme.subBorderWidth
                        border.color: capBadge.modelData.ok ? Theme.withAlpha(Theme.success, 0.45) : Theme.cardBorder

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: capBadge.modelData.ok ? "󰄬" : "·"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(11)
                                color: capBadge.modelData.ok ? Theme.success : Theme.outline
                            }

                            Text {
                                text: capBadge.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: capBadge.modelData.ok ? Font.Bold : Font.Normal
                                color: capBadge.modelData.ok ? Theme.fgSurface : Theme.fgSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 5. Power, Idle Inhibitor & Session ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: pwrCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: pwrCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Power, idle & session"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "󰅶"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(15)
                    color: ShellState.keepAwake ? Theme.tertiary : Theme.fgSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Keep Screen Awake (Idle Inhibitor)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Prevents Wayland display sleep or automatic locking while enabled"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.keepAwake
                    activeColor: Theme.tertiary
                    onToggled: ShellState.toggleKeepAwake()
                }
            }

            // Conditional Power Profile Selector (only if power-profiles-daemon is available)
            ColumnLayout {
                visible: !!root.powerProfiles.hasPowerProfiles
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "Power profile"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.powerProfiles.available || []

                        delegate: Rectangle {
                            id: ppPill
                            required property string modelData
                            readonly property bool selected: root.powerProfiles.active === ppPill.modelData

                            implicitHeight: 26
                            implicitWidth: ppTxt.implicitWidth + 16
                            radius: Theme.r(8)
                            color: ppPill.selected
                                ? Theme.primary
                                : (ppMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: ppPill.selected ? Theme.activeControlBorderWidth : 0
                            border.color: Theme.primary

                            Text {
                                id: ppTxt
                                anchors.centerIn: parent
                                text: ppPill.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: ppPill.selected ? Font.Bold : Font.Medium
                                color: ppPill.selected ? Theme.fgPrimary : Theme.fgSurface
                            }

                            MouseArea {
                                id: ppMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setPowerProfile(ppPill.modelData)
                            }
                        }
                    }
                }
            }

            PowerMenu {
                Layout.fillWidth: true
            }
        }
    }

    // --- 6. Per-Device MangoWC Overrides ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 46
        radius: Theme.r(14)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "Per-Device Overrides (~/.config/mango/local.conf)"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Text {
                    text: root.overrideCount + " active override rule(s) on this device"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: reloadWmLbl.implicitWidth + 16
                radius: Theme.r(8)
                color: reloadWmMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                border.width: Theme.subBorderWidth
                border.color: Theme.cardBorder
                scale: reloadWmMouse.pressed ? 0.95 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }

                Text {
                    id: reloadWmLbl
                    anchors.centerIn: parent
                    text: "Reload WM"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.primary
                }

                MouseArea {
                    id: reloadWmMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "reload_config"])
                }
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: rstLocalLbl.implicitWidth + 16
                radius: Theme.r(8)
                color: rstLocalMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.subCardBg
                border.width: Theme.subBorderWidth
                border.color: Theme.cardBorder
                scale: rstLocalMouse.pressed ? 0.95 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }

                Text {
                    id: rstLocalLbl
                    anchors.centerIn: parent
                    text: "Reset local.conf"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: rstLocalMouse.containsMouse ? Theme.error : Theme.fgSurface
                }

                MouseArea {
                    id: rstLocalMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resetOverrides()
                }
            }
        }
    }

    property bool confirmResetApp: false
    property bool confirmResetBar: false
    property bool confirmFactoryAll: false

    Timer {
        id: sysConfirmTimer
        interval: 4000
        repeat: false
        onTriggered: {
            root.confirmResetApp = false;
            root.confirmResetBar = false;
            root.confirmFactoryAll = false;
        }
    }

    Timer {
        id: sysReloadTimer
        interval: 700
        repeat: false
        onTriggered: root.loadOverrides()
    }

    function clearSysConfirms(): void {
        root.confirmResetApp = false;
        root.confirmResetBar = false;
        root.confirmFactoryAll = false;
        sysConfirmTimer.stop();
    }

    // --- 7. User Account & Settings Backup ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: acctCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: acctCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "User account, backup & reset"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: (root.userInfo.user || "user") + " (UID " + root.userInfo.uid + ") · " + (root.userInfo.shell || "/bin/sh")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Session: " + (root.userInfo.desktop || "mango") + " (" + (root.userInfo.sessionType || "wayland") + ") · Locale: " + (root.userInfo.lang || "C.UTF-8")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }

                    Text {
                        visible: (root.userInfo.groups || []).length > 0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Groups: " + (root.userInfo.groups || []).join(", ")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: bkpLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: bkpMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                    Text { id: bkpLbl; anchors.centerIn: parent; text: "Export Backup"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgPrimary }
                    MouseArea { id: bkpMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.exportBackup() }
                }
            }

            // Recent Backup Archives (1-click Restore)
            Flow {
                visible: root.backupsList.length > 0
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.backupsList

                    delegate: Rectangle {
                        id: bkpItem
                        required property var modelData
                        implicitHeight: 24
                        implicitWidth: bkpItemRow.implicitWidth + 12
                        radius: Theme.r(7)
                        color: bkpItemMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.subBorderWidth
                        border.color: bkpItemMouse.containsMouse ? Theme.primary : Theme.cardBorder

                        RowLayout {
                            id: bkpItemRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text { text: "󰑐 Restore " + bkpItem.modelData.name; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Medium; color: Theme.fgSurface }
                            Text { text: "(" + bkpItem.modelData.sizeKb + " KB)"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(8); color: Theme.primary }
                        }

                        MouseArea {
                            id: bkpItemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.restoreBackup(bkpItem.modelData.path)
                        }
                    }
                }
            }

            // Reset & Recovery Button Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: root.confirmResetApp
                        ? Theme.warning
                        : (rstSysAppMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                    border.width: Theme.activeControlBorderWidth
                    border.color: root.confirmResetApp ? Theme.warning : Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: root.confirmResetApp ? "Confirm Appearance?" : "Reset Appearance"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: root.confirmResetApp ? Theme.contrastInk(Theme.warning) : Theme.warning
                    }

                    MouseArea {
                        id: rstSysAppMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.confirmResetApp) {
                                root.clearSysConfirms();
                                root.confirmResetApp = true;
                                sysConfirmTimer.restart();
                                return;
                            }
                            root.clearSysConfirms();
                            ShellState.resetAppearance();
                            root.backupStatus = "Appearance, theme, font & blur restored to defaults";
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: root.confirmResetBar
                        ? Theme.secondary
                        : (rstSysBarMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                    border.width: Theme.activeControlBorderWidth
                    border.color: root.confirmResetBar ? Theme.secondary : Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: root.confirmResetBar ? "Confirm Bar Reset?" : "Reset Bar & Shell"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: root.confirmResetBar ? Theme.contrastInk(Theme.secondary) : Theme.secondary
                    }

                    MouseArea {
                        id: rstSysBarMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.confirmResetBar) {
                                root.clearSysConfirms();
                                root.confirmResetBar = true;
                                sysConfirmTimer.restart();
                                return;
                            }
                            root.clearSysConfirms();
                            ShellState.resetBar();
                            root.backupStatus = "Bar widgets & shell behavior restored to defaults";
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: root.confirmFactoryAll
                        ? Theme.error
                        : (rstFactoryMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.18) : Theme.subCardBg)
                    border.width: Theme.activeControlBorderWidth
                    border.color: root.confirmFactoryAll ? Theme.error : Theme.withAlpha(Theme.error, 0.45)

                    Text {
                        anchors.centerIn: parent
                        text: root.confirmFactoryAll ? "Confirm Factory Reset?" : "Factory Reset All"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: root.confirmFactoryAll ? Theme.fgError : Theme.error
                    }

                    MouseArea {
                        id: rstFactoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.confirmFactoryAll) {
                                root.clearSysConfirms();
                                root.confirmFactoryAll = true;
                                sysConfirmTimer.restart();
                                return;
                            }
                            root.clearSysConfirms();
                            ShellState.resetAllSettings();
                            sysReloadTimer.restart();
                            root.backupStatus = "Factory reset complete (shell-prefs + local.conf + theme)";
                        }
                    }
                }
            }

            Text {
                visible: root.backupStatus.length > 0
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.backupStatus
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.success
            }
        }
    }
}
