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
    property var powerState: ({
        ok: false,
        hasPowerProfiles: false,
        backend: "direct",
        daemonRunning: false,
        daemonInstalled: false,
        initSystem: "unknown",
        active: "balanced",
        available: [],
        governor: "",
        epp: "",
        driver: "",
        boostSupported: false,
        boostEnabled: false,
        platformProfile: "",
        hasPlatformProfile: false,
        gpuDpmSupported: false,
        gpuDpmLevel: "",
        cpuFreqMhz: 0,
        hasBattery: false,
        onAc: true,
        autoSwitch: false,
        acProfile: "balanced",
        batteryProfile: "power-saver",
        gpuDpmControl: true,
        boostOnSaver: false
    })
    property bool powerBusy: false
    property string powerMsg: ""
    property string powerErr: ""
    property bool confirmRemovePowerd: false

    property var updaterState: ({
        ok: false,
        repoFound: false,
        repoPath: "",
        remoteUrl: "https://github.com/AIharthi/mango-quickshell-dots.git",
        branch: "main",
        localCommit: "",
        localSubject: "",
        localDate: "",
        installedCommit: "",
        installedAt: "",
        dirty: false,
        dirtyCount: 0,
        behindCount: 0,
        aheadCount: 0,
        upToDate: false,
        needsInstall: false,
        hasGit: true,
        hasCargo: true,
        pendingCommits: []
    })
    property bool updaterBusy: false
    property string updaterMsg: ""
    property string updaterErr: ""
    property bool updaterRebuildRust: true
    property bool updaterNeedsReload: false

    property var disks: []
    property var userInfo: ({ user: "", fullName: "", uid: 1000, shell: "", home: "", groups: [], lang: "", sessionType: "", desktop: "" })
    property var backupsList: []
    property string backupStatus: ""
    property var doctorReport: ({ ok: true, summary: "Running diagnostics...", passCount: 0, warnCount: 0, failCount: 0, checks: [] })
    property bool doctorRunning: false
    property var distroStatus: ({ ok: false, family: "", prettyName: "", initSystem: "", seatManager: "", hasOpenRcUser: false, packageManager: "", installedCount: 0, worldCount: 0, repos: [], syncStatus: "", updatesChecked: false, pendingCount: 0, dbLocked: false, preservedRebuild: false, aurHelper: "", flatpakCount: 0, updateCmd: "" })
    property bool distroLoading: false
    property string distroError: ""

    function runDoctor(): void {
        if (doctorProc.running)
            return;
        root.doctorRunning = true;
        doctorProc.running = true;
    }

    function refreshDistro(forceRefresh: bool): void {
        if (distroProc.running)
            return;
        root.distroLoading = true;
        root.distroError = "";
        distroProc.command = [
            Quickshell.shellPath("scripts/manage-system.sh"),
            "distro",
            forceRefresh ? "refresh" : "status"
        ];
        distroProc.running = true;
    }

    function launchDistroUpdate(): void {
        const cmd = String(root.distroStatus.updateCmd || "").trim();
        if (cmd.length === 0)
            return;
        Quickshell.execDetached([
            Quickshell.shellPath("scripts/launch-app.sh"),
            "terminal-exec",
            "sh", "-c",
            cmd + "; printf '\\nPress Enter to close...'; read _"
        ]);
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
        refreshDistro(false);
        loadUpdaterStatus();
        loadPowerState();
    }

    function loadUpdaterStatus(): void {
        if (!updaterProc.running)
            updaterProc.running = true;
    }

    function runUpdater(actionArgs: var, busyMsg: string): void {
        if (root.updaterBusy || updaterActionProc.running)
            return;
        root.updaterBusy = true;
        root.updaterErr = "";
        root.updaterMsg = busyMsg || "Working...";
        updaterActionProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "config-update"].concat(actionArgs);
        updaterActionProc.running = true;
    }

    function reloadQuickshell(): void {
        Quickshell.execDetached([
            "sh", "-c",
            "sleep 0.25; pkill -x qs 2>/dev/null || true; sleep 0.35; qs -d </dev/null >/dev/null 2>&1 &"
        ]);
    }

    function loadPowerState(): void {
        if (!powerStatusProc.running)
            powerStatusProc.running = true;
    }

    function runPowerAction(actionArgs: var, busyMsg: string): void {
        if (root.powerBusy || powerActionProc.running)
            return;
        root.powerBusy = true;
        root.powerErr = "";
        root.powerMsg = busyMsg;
        powerActionProc.command = [Quickshell.shellPath("scripts/manage-powerd.sh")].concat(actionArgs);
        powerActionProc.running = true;
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
        root.runPowerAction(["set", prof], "Switching to " + prof + "...");
    }

    function setPowerConfig(key: string, val: string): void {
        root.runPowerAction(["config", key, val], "");
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
                    if (Array.isArray(d.disks)) root.disks = d.disks;
                } catch (err) {}
            }
        }
    }

    Timer {
        id: powerConfirmTimer
        interval: 4000
        repeat: false
        onTriggered: root.confirmRemovePowerd = false
    }

    Process {
        id: powerStatusProc
        command: [Quickshell.shellPath("scripts/manage-powerd.sh"), "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok)
                        root.powerState = d;
                } catch (err) {}
            }
        }
    }

    Process {
        id: powerActionProc
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.powerState = d;
                        root.powerErr = "";
                        root.powerMsg = d.daemonRunning
                            ? ("Power mode: " + String(d.active || "balanced"))
                            : ("Applied: " + String(d.active || "balanced"));
                        DeviceCaps.refresh();
                    } else if (d && d.error) {
                        root.powerErr = String(d.error);
                        root.powerMsg = "";
                    }
                } catch (err) {
                    root.powerErr = "Unable to parse power daemon response";
                }
            }
        }
        onExited: code => {
            root.powerBusy = false;
            if (code !== 0 && root.powerErr.length === 0)
                root.powerErr = "Power daemon command exited with code " + code;
        }
    }

    Process {
        id: updaterProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "config-update", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.updaterState = d;
                        if (!repoPathInput.activeFocus)
                            repoPathInput.text = String(d.repoPath || "~/mango-quickshell-dots");
                    } else if (d && d.error) {
                        root.updaterErr = String(d.error);
                    }
                } catch (err) {}
            }
        }
    }

    Process {
        id: updaterActionProc
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.updaterState = d;
                        root.updaterErr = "";
                        if (!repoPathInput.activeFocus)
                            repoPathInput.text = String(d.repoPath || "~/mango-quickshell-dots");
                        if (d.message)
                            root.updaterMsg = String(d.message);
                        else if (d.behindCount > 0)
                            root.updaterMsg = d.behindCount + " update(s) ready from origin/" + String(d.branch || "main");
                        else if (d.needsInstall)
                            root.updaterMsg = "Local repo differs from installed snapshot";
                        else
                            root.updaterMsg = "Repository is up to date";

                        if (d.restartShellRecommended)
                            root.updaterNeedsReload = true;
                        if (d.updated) {
                            root.runDoctor();
                            root.refreshDistro(false);
                            root.loadPowerState();
                        }
                    } else if (d && d.error) {
                        root.updaterErr = String(d.error);
                        root.updaterMsg = "";
                    }
                } catch (err) {
                    root.updaterErr = "Unable to parse config updater response";
                }
            }
        }
        onExited: code => {
            root.updaterBusy = false;
            if (code !== 0 && root.updaterErr.length === 0)
                root.updaterErr = "Config updater exited with code " + code;
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

    Process {
        id: distroProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.distroLoading = false;
                const raw = (text || "").trim();
                if (raw.length === 0) {
                    root.distroError = "Distro status returned an empty response";
                    return;
                }
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok === false) {
                        root.distroError = String(d.error || "Unable to inspect distro packages");
                        return;
                    }
                    if (d && d.ok) {
                        root.distroError = "";
                        root.distroStatus = d;
                    }
                } catch (err) {
                    root.distroError = "Unable to parse distro status";
                }
            }
        }
        onExited: (code) => {
            root.distroLoading = false;
            if (code !== 0 && root.distroError.length === 0)
                root.distroError = "Distro check exited with code " + code;
        }
    }

    // --- 0. Aurora Shell 2.1 · System Health Doctor ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: docCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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
                        text: "Aurora Shell 2.1"
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

    // --- 0b. Cross-Distro Package & Init Center (Arch / Fedora / Gentoo) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: distCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: distCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰏗"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(15)
                    color: Theme.primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Distro & packages"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        text: root.distroStatus.ok
                            ? (String(root.distroStatus.prettyName || DeviceCaps.distro)
                                + " · " + String(root.distroStatus.initSystem || "")
                                + " + " + String(root.distroStatus.seatManager || ""))
                            : "Arch (pacman), Fedora (dnf), and Gentoo (Portage)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: chkDistLbl.implicitWidth + 16
                    radius: Theme.r(8)
                    color: chkDistMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg

                    Text {
                        id: chkDistLbl
                        anchors.centerIn: parent
                        text: root.distroLoading ? "Checking..." : "Check status"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: chkDistMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshDistro(true)
                    }
                }

                Rectangle {
                    visible: root.distroStatus.ok && String(root.distroStatus.updateCmd || "").length > 0
                    implicitHeight: 26
                    implicitWidth: updDistLbl.implicitWidth + 16
                    radius: Theme.r(8)
                    color: Theme.primary

                    Text {
                        id: updDistLbl
                        anchors.centerIn: parent
                        text: "Update in terminal"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launchDistroUpdate()
                    }
                }
            }

            // Loading / Error / Empty states
            Text {
                visible: root.distroLoading && !root.distroStatus.ok
                text: "Inspecting local package database and init runtime..."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                visible: !root.distroLoading && root.distroError.length > 0 && !root.distroStatus.ok
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.distroError
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.error
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: retryDistTxt.implicitWidth + 14
                    radius: Theme.r(7)
                    color: Theme.subCardBg

                    Text {
                        id: retryDistTxt
                        anchors.centerIn: parent
                        text: "Retry"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshDistro(true)
                    }
                }
            }

            GridLayout {
                visible: root.distroStatus.ok
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 8
                rowSpacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: pmCol.implicitHeight + 14
                    radius: Theme.r(10)
                    color: Theme.subCardBg

                    ColumnLayout {
                        id: pmCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 3

                        Text {
                            text: String(root.distroStatus.packageManager || "Packages")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Number(root.distroStatus.installedCount || 0) + " installed"
                                + (Number(root.distroStatus.worldCount || 0) > 0 ? (" · " + root.distroStatus.worldCount + " @world") : "")
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: (String(root.distroStatus.aurHelper || "").length > 0 ? ("AUR: " + root.distroStatus.aurHelper + " · ") : "")
                                + Number(root.distroStatus.flatpakCount || 0) + " Flatpak apps"
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: repoCol.implicitHeight + 14
                    radius: Theme.r(10)
                    color: Theme.subCardBg

                    ColumnLayout {
                        id: repoCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 3

                        Text {
                            text: root.distroStatus.family === "gentoo" ? "Repositories & overlays" : "Enabled repositories"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: (Array.isArray(root.distroStatus.repos) && root.distroStatus.repos.length > 0)
                                ? root.distroStatus.repos.join(", ")
                                : "None detected"
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.distroStatus.hasOpenRcUser ? "openrc-user active" : ("Family: " + String(root.distroStatus.family || "linux"))
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: syncCol.implicitHeight + 14
                    radius: Theme.r(10)
                    color: Theme.subCardBg

                    ColumnLayout {
                        id: syncCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 3

                        Text {
                            text: "Sync & health"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: String(root.distroStatus.syncStatus || "Unknown")
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                            color: (Number(root.distroStatus.pendingCount || 0) > 0 || root.distroStatus.dbLocked)
                                ? Theme.warning
                                : Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.distroStatus.dbLocked
                                ? "Database lock present"
                                : (root.distroStatus.preservedRebuild ? "Preserved libs in registry" : "Package DB unlocked")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: (root.distroStatus.dbLocked || root.distroStatus.preservedRebuild)
                                ? Theme.warning
                                : Theme.fgSurfaceVariant
                        }
                    }
                }
            }
        }
    }

    // --- 0c. Aurora Config Updater ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: updCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: updCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰚰"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(15)
                    color: Theme.primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Config updater"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.updaterState.repoFound
                            ? (String(root.updaterState.branch || "main") + " · "
                                + String(root.updaterState.localCommit || "HEAD")
                                + (root.updaterState.dirty ? (" · " + root.updaterState.dirtyCount + " local edit(s)") : ""))
                            : "Link or clone your mango-quickshell-dots repository"
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: updBadgeTxt.implicitWidth + 14
                    radius: Theme.r(11)
                    color: !root.updaterState.repoFound
                        ? Theme.subCardBg
                        : (Number(root.updaterState.behindCount || 0) > 0
                            ? Theme.withAlpha(Theme.warning, 0.20)
                            : (root.updaterState.upToDate
                                ? Theme.withAlpha(Theme.success, 0.18)
                                : Theme.withAlpha(Theme.secondary, 0.18)))

                    Text {
                        id: updBadgeTxt
                        anchors.centerIn: parent
                        text: !root.updaterState.repoFound
                            ? "Not linked"
                            : (Number(root.updaterState.behindCount || 0) > 0
                                ? (root.updaterState.behindCount + " update(s) ready")
                                : (root.updaterState.needsInstall ? "Sync needed" : "Up to date"))
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.Bold
                        color: !root.updaterState.repoFound
                            ? Theme.fgSurfaceVariant
                            : (Number(root.updaterState.behindCount || 0) > 0
                                ? Theme.warning
                                : (root.updaterState.upToDate ? Theme.success : Theme.secondary))
                    }
                }
            }

            // Dedicated Full-Width Action Bar (prevents button clipping on laptop widths)
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    visible: !!root.updaterState.repoFound
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: chkUpdMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    opacity: root.updaterBusy ? 0.55 : 1.0

                    Text {
                        id: chkUpdLbl
                        anchors.centerIn: parent
                        text: root.updaterBusy ? "Working..." : "Check Updates"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: chkUpdMouse
                        anchors.fill: parent
                        enabled: !root.updaterBusy
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.runUpdater(["check"], "Fetching origin updates...")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: applyUpdMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                    opacity: root.updaterBusy ? 0.55 : 1.0

                    Text {
                        id: applyUpdLbl
                        anchors.centerIn: parent
                        text: !root.updaterState.repoFound
                            ? "Clone Repo"
                            : (Number(root.updaterState.behindCount || 0) > 0 ? "Pull & Update" : "Pull & Sync")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        id: applyUpdMouse
                        anchors.fill: parent
                        enabled: !root.updaterBusy
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!root.updaterState.repoFound) {
                                const target = (repoPathInput.text || "").trim() || "~/mango-quickshell-dots";
                                root.runUpdater(["clone", target], "Cloning mango-quickshell-dots...");
                            } else {
                                root.runUpdater(root.updaterRebuildRust ? ["apply"] : ["apply", "--skip-build"], "Fetching, pulling, and installing updates...");
                            }
                        }
                    }
                }

                Rectangle {
                    visible: !!root.updaterState.repoFound
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: syncLocalMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    opacity: root.updaterBusy ? 0.55 : 1.0

                    Text {
                        id: syncLocalLbl
                        anchors.centerIn: parent
                        text: "Sync Local"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: syncLocalMouse
                        anchors.fill: parent
                        enabled: !root.updaterBusy
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.runUpdater(root.updaterRebuildRust ? ["apply", "--no-pull"] : ["apply", "--no-pull", "--skip-build"], "Syncing local repository files...")
                    }
                }

                Rectangle {
                    visible: root.updaterNeedsReload
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: relShMouse.containsMouse ? Qt.lighter(Theme.secondary, 1.08) : Theme.secondary

                    Text {
                        id: relShLbl
                        anchors.centerIn: parent
                        text: "Reload Shell"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.contrastInk(Theme.secondary)
                    }

                    MouseArea {
                        id: relShMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.reloadQuickshell()
                    }
                }
            }

            // Repo Path Input Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Repo Path"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: repoPathInput.activeFocus ? 1 : Theme.subBorderWidth
                    border.color: repoPathInput.activeFocus ? Theme.primary : Theme.cardBorder

                    TextInput {
                        id: repoPathInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        text: String(root.updaterState.repoPath || "~/mango-quickshell-dots")
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurface
                        clip: true
                        selectByMouse: true
                        Keys.onReturnPressed: root.runUpdater(["set-repo", text], "Linking repository...")
                    }
                }

                Rectangle {
                    implicitWidth: 56
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: saveRepoMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    opacity: root.updaterBusy ? 0.55 : 1.0

                    Text {
                        anchors.centerIn: parent
                        text: "Save"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: saveRepoMouse
                        anchors.fill: parent
                        enabled: !root.updaterBusy
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.runUpdater(["set-repo", repoPathInput.text], "Linking repository...")
                    }
                }
            }

            // Commit Info & Rust Rebuild Toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        visible: root.updaterState.repoFound
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Installed: " + (String(root.updaterState.installedCommit || "").length > 0 ? String(root.updaterState.installedCommit) : "untracked")
                            + " · Latest local: " + String(root.updaterState.localSubject || "")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }

                    Text {
                        text: "Rebuild Rust backends on update"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }
                }

                ToggleSwitch {
                    checked: root.updaterRebuildRust
                    onToggled: root.updaterRebuildRust = !root.updaterRebuildRust
                }
            }

            // Pending Commits List
            ColumnLayout {
                visible: Array.isArray(root.updaterState.pendingCommits) && root.updaterState.pendingCommits.length > 0
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: root.updaterState.pendingCommits || []

                    delegate: Rectangle {
                        id: pCommitRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: Theme.subCardBg

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: String(pCommitRow.modelData.hash || "")
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.Bold
                                color: Theme.primary
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: String(pCommitRow.modelData.subject || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.fgSurface
                            }

                            Text {
                                text: String(pCommitRow.modelData.date || "")
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.updaterMsg.length > 0 || root.updaterErr.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.updaterErr.length > 0 ? root.updaterErr : root.updaterMsg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: root.updaterErr.length > 0 ? Theme.error : Theme.success
            }
        }
    }

    // --- 1. Device & Hardware Summary ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hostCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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

            // Power Modes & Daemon Controller
            ColumnLayout {
                visible: Array.isArray(root.powerState.available) && root.powerState.available.length > 0
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: "Power modes & daemon"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.fgSurfaceVariant
                    }

                    Rectangle {
                        implicitHeight: 20
                        implicitWidth: pwrBadgeTxt.implicitWidth + 12
                        radius: Theme.r(10)
                        color: root.powerState.daemonRunning
                            ? Theme.withAlpha(Theme.success, 0.18)
                            : (root.powerState.daemonInstalled
                                ? Theme.withAlpha(Theme.warning, 0.18)
                                : Theme.subCardBg)

                        Text {
                            id: pwrBadgeTxt
                            anchors.centerIn: parent
                            text: root.powerState.daemonRunning
                                ? "Daemon running"
                                : (root.powerState.daemonInstalled ? "Service installed" : String(root.powerState.backend || "Direct sysfs"))
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.Bold
                            color: root.powerState.daemonRunning
                                ? Theme.success
                                : (root.powerState.daemonInstalled ? Theme.warning : Theme.fgSurfaceVariant)
                        }
                    }
                }

                // 3-Segment Power Mode Cards
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "power-saver", label: "Power Saver", icon: "󰌪" },
                            { id: "balanced",    label: "Balanced",    icon: "󰾅" },
                            { id: "performance", label: "Performance", icon: "󱐋" }
                        ]

                        delegate: Rectangle {
                            id: ppCard
                            required property var modelData
                            readonly property bool available: (root.powerState.available || []).indexOf(ppCard.modelData.id) !== -1
                            readonly property bool selected: root.powerState.active === ppCard.modelData.id

                            visible: ppCard.available
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Theme.r(9)
                            color: ppCard.selected
                                ? Theme.primary
                                : (ppMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: ppCard.selected ? Theme.activeControlBorderWidth : 0
                            border.color: Theme.primary
                            opacity: root.powerBusy ? 0.65 : 1.0

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: ppCard.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(13)
                                    color: ppCard.selected ? Theme.fgPrimary : Theme.primary
                                }

                                Text {
                                    text: ppCard.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: ppCard.selected ? Font.Bold : Font.Medium
                                    color: ppCard.selected ? Theme.fgPrimary : Theme.fgSurface
                                }
                            }

                            MouseArea {
                                id: ppMouse
                                anchors.fill: parent
                                enabled: !root.powerBusy
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.setPowerProfile(ppCard.modelData.id)
                            }
                        }
                    }
                }

                // Live Telemetry Strip
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: pwrTelCol.implicitHeight + 12
                    radius: Theme.r(9)
                    color: Theme.subCardBg

                    ColumnLayout {
                        id: pwrTelCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "Backend: " + String(root.powerState.backend || "direct")
                                + " · Driver: " + (String(root.powerState.driver || "") || "unknown")
                                + " · Gov: " + (String(root.powerState.governor || "") || "-")
                                + (String(root.powerState.epp || "").length > 0 ? (" · EPP: " + root.powerState.epp) : "")
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "CPU: " + Number(root.powerState.cpuFreqMhz || 0) + " MHz"
                                + (root.powerState.boostSupported ? (" · Boost: " + (root.powerState.boostEnabled ? "On" : "Off")) : "")
                                + (root.powerState.hasPlatformProfile ? (" · ACPI: " + String(root.powerState.platformProfile || "-")) : "")
                                + (root.powerState.gpuDpmSupported ? (" · GPU DPM: " + String(root.powerState.gpuDpmLevel || "-")) : "")
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                        }
                    }
                }

                // Daemon Service Management Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "aurora-powerd service (" + String(root.powerState.initSystem || "unknown") + ")"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.powerState.daemonRunning
                                ? "Socket active on /run/aurora-powerd.sock"
                                : "Install service for instant switching and AC/battery automation"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Rectangle {
                        visible: !root.powerState.daemonRunning
                        implicitHeight: 26
                        implicitWidth: instPwrLbl.implicitWidth + 14
                        radius: Theme.r(8)
                        color: instPwrMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                        opacity: root.powerBusy ? 0.55 : 1.0

                        Text {
                            id: instPwrLbl
                            anchors.centerIn: parent
                            text: root.powerState.daemonInstalled ? "Start / Reinstall Daemon" : "Install & Start Daemon"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgPrimary
                        }

                        MouseArea {
                            id: instPwrMouse
                            anchors.fill: parent
                            enabled: !root.powerBusy
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.runPowerAction(["install-service"], "Installing and starting aurora-powerd...")
                        }
                    }

                    Rectangle {
                        visible: !!root.powerState.daemonInstalled
                        implicitHeight: 26
                        implicitWidth: rmPwrLbl.implicitWidth + 14
                        radius: Theme.r(8)
                        color: root.confirmRemovePowerd
                            ? Theme.error
                            : (rmPwrMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.subCardBg)
                        opacity: root.powerBusy ? 0.55 : 1.0

                        Text {
                            id: rmPwrLbl
                            anchors.centerIn: parent
                            text: root.confirmRemovePowerd ? "Confirm Remove?" : "Remove Daemon"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: root.confirmRemovePowerd ? Theme.fgError : Theme.error
                        }

                        MouseArea {
                            id: rmPwrMouse
                            anchors.fill: parent
                            enabled: !root.powerBusy
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!root.confirmRemovePowerd) {
                                    root.confirmRemovePowerd = true;
                                    powerConfirmTimer.restart();
                                    return;
                                }
                                root.confirmRemovePowerd = false;
                                powerConfirmTimer.stop();
                                root.runPowerAction(["uninstall-service"], "Removing aurora-powerd service...");
                            }
                        }
                    }
                }

                // Daemon Tuning Controls (when daemon is running)
                ColumnLayout {
                    visible: !!root.powerState.daemonRunning
                    Layout.fillWidth: true
                    spacing: 7

                    RowLayout {
                        visible: !!root.powerState.boostSupported
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Disable CPU boost in Power Saver"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            color: Theme.fgSurface
                        }

                        ToggleSwitch {
                            checked: !root.powerState.boostOnSaver
                            onToggled: root.setPowerConfig("boost_on_saver", root.powerState.boostOnSaver ? "false" : "true")
                        }
                    }

                    RowLayout {
                        visible: !!root.powerState.gpuDpmSupported
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Control AMD GPU DPM level"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            color: Theme.fgSurface
                        }

                        ToggleSwitch {
                            checked: !!root.powerState.gpuDpmControl
                            onToggled: root.setPowerConfig("gpu_dpm", root.powerState.gpuDpmControl ? "false" : "true")
                        }
                    }

                    RowLayout {
                        visible: !!root.powerState.hasBattery
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Auto-switch on AC / Battery (" + (root.powerState.onAc ? "On AC" : "On Battery") + ")"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            color: Theme.fgSurface
                        }

                        ToggleSwitch {
                            checked: !!root.powerState.autoSwitch
                            onToggled: root.setPowerConfig("auto_switch", root.powerState.autoSwitch ? "false" : "true")
                        }
                    }

                    RowLayout {
                        visible: !!root.powerState.hasBattery && !!root.powerState.autoSwitch
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.preferredWidth: 85
                            text: "AC Profile"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }

                        Repeater {
                            model: ["power-saver", "balanced", "performance"]

                            delegate: Rectangle {
                                id: acChip
                                required property string modelData
                                readonly property bool selected: root.powerState.acProfile === acChip.modelData
                                Layout.fillWidth: true
                                implicitHeight: 24
                                radius: Theme.r(7)
                                color: acChip.selected ? Theme.primary : Theme.subCardBg

                                Text {
                                    anchors.centerIn: parent
                                    text: acChip.modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: acChip.selected ? Font.Bold : Font.Normal
                                    color: acChip.selected ? Theme.fgPrimary : Theme.fgSurface
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setPowerConfig("ac_profile", acChip.modelData)
                                }
                            }
                        }
                    }

                    RowLayout {
                        visible: !!root.powerState.hasBattery && !!root.powerState.autoSwitch
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.preferredWidth: 85
                            text: "Battery Profile"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }

                        Repeater {
                            model: ["power-saver", "balanced", "performance"]

                            delegate: Rectangle {
                                id: batChip
                                required property string modelData
                                readonly property bool selected: root.powerState.batteryProfile === batChip.modelData
                                Layout.fillWidth: true
                                implicitHeight: 24
                                radius: Theme.r(7)
                                color: batChip.selected ? Theme.secondary : Theme.subCardBg

                                Text {
                                    anchors.centerIn: parent
                                    text: batChip.modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: batChip.selected ? Font.Bold : Font.Normal
                                    color: batChip.selected ? Theme.contrastInk(Theme.secondary) : Theme.fgSurface
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setPowerConfig("battery_profile", batChip.modelData)
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: root.powerMsg.length > 0 || root.powerErr.length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.powerErr.length > 0 ? root.powerErr : root.powerMsg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: root.powerErr.length > 0 ? Theme.error : Theme.success
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
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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
