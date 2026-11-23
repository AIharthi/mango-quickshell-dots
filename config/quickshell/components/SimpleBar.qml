pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property bool active: true
    property string screenName: ""
    property string monitorName: ""
    property string currentLayout: "T"
    property string activeWindowTitle: ""
    property real cpuPercent: 0
    property real _prevTotal: 0
    property real _prevIdle: 0
    property real ramPercent: 0
    property int volPercent: 50
    property bool volMuted: false
    property string kbLayoutShort: ""
    property var tagsModel: [
        { index: 1, is_active: true,  is_urgent: false, client_count: 0 },
        { index: 2, is_active: false, is_urgent: false, client_count: 0 },
        { index: 3, is_active: false, is_urgent: false, client_count: 0 },
        { index: 4, is_active: false, is_urgent: false, client_count: 0 },
        { index: 5, is_active: false, is_urgent: false, client_count: 0 },
        { index: 6, is_active: false, is_urgent: false, client_count: 0 },
        { index: 7, is_active: false, is_urgent: false, client_count: 0 },
        { index: 8, is_active: false, is_urgent: false, client_count: 0 },
        { index: 9, is_active: false, is_urgent: false, client_count: 0 }
    ]

    signal toggleDashboardRequested()
    signal toggleLauncherRequested()
    signal toggleSettingsRequested()
    signal toggleFilesRequested()

    color: Theme.surfaceContainerLowest
    radius: 0

    function parseTagsJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const payload = JSON.parse(trimmed);
            const list = payload.all_tags;
            if (!list || list.length === 0)
                return;

            const targetMon = root.screenName.length > 0 ? root.screenName : root.monitorName;
            let chosen = list[0];
            for (let i = 0; i < list.length; i++) {
                if (list[i].monitor === targetMon) {
                    chosen = list[i];
                    break;
                }
            }

            if (chosen.monitor)
                root.monitorName = chosen.monitor;
            if (chosen.tags && chosen.tags.length > 0) {
                const normalized = [];
                let activeLayout = root.currentLayout;
                for (let j = 0; j < Math.min(9, chosen.tags.length); j++) {
                    const t = chosen.tags[j];
                    if (t.is_active && t.layout)
                        activeLayout = t.layout;
                    normalized.push({
                        index: t.index,
                        is_active: !!t.is_active,
                        is_urgent: !!t.is_urgent,
                        client_count: t.client_count || 0
                    });
                }
                root.currentLayout = activeLayout;
                root.tagsModel = normalized;
            }
        } catch (err) {}
    }

    function parseWinJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const d = JSON.parse(trimmed);
            if (d.error || !d.id || (!d.title && !d.appid)) {
                root.activeWindowTitle = "";
                return;
            }
            root.activeWindowTitle = String(d.title || d.appid || "");
        } catch (err) {}
    }

    function parseKbJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const d = JSON.parse(trimmed);
            const full = String(d.layout || "").trim();
            if (full.length === 0) {
                root.kbLayoutShort = "";
                return;
            }
            const paren = full.match(/\(([^)]+)\)/);
            if (paren && paren[1])
                root.kbLayoutShort = paren[1].trim().slice(0, 3).toUpperCase();
            else
                root.kbLayoutShort = full.slice(0, 2).toUpperCase();
        } catch (err) {}
    }

    function parseCpuStat(raw: string): void {
        if (!raw)
            return;
        const firstLine = raw.split("\n")[0] || "";
        if (!firstLine.startsWith("cpu "))
            return;
        const parts = firstLine.trim().split(/\s+/);
        if (parts.length < 5)
            return;
        const user = parseFloat(parts[1]) || 0;
        const nice = parseFloat(parts[2]) || 0;
        const system = parseFloat(parts[3]) || 0;
        const idle = parseFloat(parts[4]) || 0;
        const iowait = parseFloat(parts[5]) || 0;
        const irq = parseFloat(parts[6]) || 0;
        const softirq = parseFloat(parts[7]) || 0;
        const steal = parseFloat(parts[8]) || 0;
        const idleAll = idle + iowait;
        const totalAll = user + nice + system + idleAll + irq + softirq + steal;
        if (root._prevTotal > 0 && totalAll > root._prevTotal) {
            const totalDelta = totalAll - root._prevTotal;
            const idleDelta = idleAll - root._prevIdle;
            root.cpuPercent = Math.max(0, Math.min(100, ((totalDelta - idleDelta) / totalDelta) * 100));
        }
        root._prevTotal = totalAll;
        root._prevIdle = idleAll;
    }

    function parseMeminfo(raw: string): void {
        if (!raw)
            return;
        let totalKb = 0;
        let availKb = -1;
        let freeKb = 0;
        let buffersKb = 0;
        let cachedKb = 0;
        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.startsWith("MemTotal:"))
                totalKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("MemAvailable:"))
                availKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("MemFree:"))
                freeKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("Buffers:"))
                buffersKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("Cached:"))
                cachedKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
        }
        if (totalKb <= 0)
            return;
        if (availKb < 0)
            availKb = freeKb + buffersKb + cachedKb;
        const usedKb = Math.max(0, totalKb - availKb);
        root.ramPercent = Math.max(0, Math.min(100, (usedKb / totalKb) * 100));
    }

    function parseVolOut(raw: string): void {
        const parts = (raw || "").split("---");
        if (parts.length > 0) {
            const m = parts[0].match(/(\d+)%/);
            if (m && m[1])
                root.volPercent = Math.max(0, Math.min(150, parseInt(m[1], 10)));
        }
        if (parts.length > 1)
            root.volMuted = parts[1].toLowerCase().indexOf("yes") !== -1;
    }

    SystemClock {
        id: clock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Process {
        id: tagStream
        command: ["mmsg", "watch", "all-tags"]
        running: root.active
        stdout: SplitParser {
            onRead: line => root.parseTagsJson(line)
        }
        onExited: {
            if (root.active)
                restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.active)
                tagStream.running = true;
        }
    }

    Process {
        id: winStream
        command: ["mmsg", "watch", "focusing-client"]
        running: root.active && ShellState.barShowWindow
        stdout: SplitParser {
            onRead: line => root.parseWinJson(line)
        }
    }

    Process {
        id: kbStream
        command: ["mmsg", "watch", "keyboardlayout"]
        running: root.active && ShellState.barShowKbLayout
        stdout: SplitParser {
            onRead: line => root.parseKbJson(line)
        }
    }

    Process {
        id: sysProc
        command: ["sh", "-c", "head -n 1 /proc/stat; echo '---'; grep -E '^(MemTotal|MemAvailable|MemFree|Buffers|Cached):' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (text || "").split("---");
                if (parts.length >= 2) {
                    root.parseCpuStat(parts[0].trim());
                    root.parseMeminfo(parts[1].trim());
                }
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.active && ShellState.barShowSystem
        triggeredOnStart: true
        onTriggered: {
            if (!sysProc.running)
                sysProc.running = true;
        }
    }

    Process {
        id: volProc
        command: ["sh", "-c", "pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null; echo '---'; pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.parseVolOut(text)
        }
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.active && ShellState.barShowVolume && DeviceCaps.hasAudio
        triggeredOnStart: true
        onTriggered: {
            if (!volProc.running)
                volProc.running = true;
        }
    }

    Timer {
        id: volRefreshTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (!volProc.running)
                volProc.running = true;
        }
    }

    // Left: Flat Square MangoWC Tags + Layout Indicator + Active Window Title
    Row {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        Repeater {
            model: root.tagsModel

            delegate: Rectangle {
                id: tagCell
                required property var modelData
                readonly property bool isActive: tagCell.modelData.is_active
                readonly property bool isUrgent: tagCell.modelData.is_urgent
                readonly property bool isOccupied: tagCell.modelData.client_count > 0

                width: 26
                height: parent.height
                radius: 0
                color: {
                    if (tagCell.isUrgent)
                        return Theme.error;
                    if (tagCell.isActive)
                        return Theme.primary;
                    if (tagMouse.containsMouse)
                        return Theme.hoverBg;
                    return "transparent";
                }

                Text {
                    anchors.centerIn: parent
                    text: tagCell.modelData.index
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: tagCell.isActive ? Font.Bold : Font.Medium
                    color: {
                        if (tagCell.isUrgent)
                            return Theme.fgError;
                        if (tagCell.isActive)
                            return Theme.fgPrimary;
                        if (tagCell.isOccupied)
                            return Theme.fgSurface;
                        return Theme.withAlpha(Theme.fgSurfaceVariant, 0.5);
                    }
                }

                // Minimal 2px bottom square indicator for occupied inactive tags
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 2
                    radius: 0
                    visible: tagCell.isOccupied && !tagCell.isActive && !tagCell.isUrgent
                    color: Theme.secondary
                }

                MouseArea {
                    id: tagMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + tagCell.modelData.index + ",0"])
                }
            }
        }

        // Crisp 1px separator
        Rectangle {
            visible: ShellState.simpleBarShowLayout
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Flat Layout Switcher
        Rectangle {
            visible: ShellState.simpleBarShowLayout
            width: layoutTxt.implicitWidth + 14
            height: parent.height
            radius: 0
            color: layoutMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                id: layoutTxt
                anchors.centerIn: parent
                text: "[" + root.currentLayout + "]"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            MouseArea {
                id: layoutMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
            }
        }

        Rectangle {
            visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        Text {
            visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 10
            rightPadding: 8
            width: Math.min(260, implicitWidth)
            elide: Text.ElideRight
            maximumLineCount: 1
            text: root.activeWindowTitle
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.Medium
            color: Theme.fgSurfaceVariant
        }
    }

    // Center: Plain Square Monospace Clock
    Row {
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: ShellState.formatTime(clock.date)
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Bold
            color: Theme.fgSurface
        }

        Text {
            visible: ShellState.simpleBarShowDate || ShellState.barShowDate
            text: ShellState.formatDate(clock.date)
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgSurfaceVariant
        }
    }

    // Right: CPU/RAM + Volume + KB Layout + Tray + Battery + Settings + Mode Switches + Hub Toggle
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        // Optional CPU & RAM monitor
        Rectangle {
            visible: ShellState.barShowSystem
            width: sysBarRow.implicitWidth + 14
            height: parent.height
            radius: 0
            color: "transparent"

            Row {
                id: sysBarRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: "CPU " + Math.round(root.cpuPercent) + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: root.cpuPercent > 85 ? Theme.error : Theme.primary
                }

                Text {
                    text: "RAM " + Math.round(root.ramPercent) + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: root.ramPercent > 85 ? Theme.warning : Theme.secondary
                }
            }
        }

        Rectangle {
            visible: ShellState.barShowSystem
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Optional Interactive Volume Indicator
        Rectangle {
            visible: ShellState.barShowVolume && DeviceCaps.hasAudio
            width: volBarTxt.implicitWidth + 14
            height: parent.height
            radius: 0
            color: volBarMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                id: volBarTxt
                anchors.centerIn: parent
                text: root.volMuted ? "VOL MUTE" : ("VOL " + root.volPercent + "%")
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: root.volMuted ? Theme.error : Theme.fgSurfaceVariant
            }

            MouseArea {
                id: volBarMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]);
                    volRefreshTimer.restart();
                }
                onWheel: wheel => {
                    const delta = wheel.angleDelta.y > 0 ? "+5%" : "-5%";
                    Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", delta]);
                    volRefreshTimer.restart();
                }
            }
        }

        Rectangle {
            visible: ShellState.barShowVolume && DeviceCaps.hasAudio
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Optional Keyboard Layout Badge
        Rectangle {
            visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
            width: kbBarTxt.implicitWidth + 14
            height: parent.height
            radius: 0
            color: "transparent"

            Text {
                id: kbBarTxt
                anchors.centerIn: parent
                text: root.kbLayoutShort
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurface
            }
        }

        Rectangle {
            visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // System Tray (shown only when tray module enabled and tray apps exist)
        Item {
            width: trayStrip.implicitWidth + 10
            height: parent.height
            visible: ShellState.barShowTray && trayStrip.hasItems

            SystemTrayStrip {
                id: trayStrip
                anchors.centerIn: parent
                compact: true
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.barShowTray && trayStrip.hasItems
            color: Theme.outlineVariant
        }

        // Active-Only Status Indicators (DND / Keep Awake)
        Rectangle {
            width: 28
            height: parent.height
            radius: 0
            visible: ShellState.dnd
            color: dndBarMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰂛"
                font.family: Theme.iconFont
                font.pixelSize: 12
                color: Theme.warning
            }

            MouseArea {
                id: dndBarMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ShellState.toggleDnd()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.dnd
            color: Theme.outlineVariant
        }

        Rectangle {
            width: 28
            height: parent.height
            radius: 0
            visible: ShellState.keepAwake
            color: awakeBarMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰅶"
                font.family: Theme.iconFont
                font.pixelSize: 12
                color: Theme.tertiary
            }

            MouseArea {
                id: awakeBarMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ShellState.toggleKeepAwake()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.keepAwake
            color: Theme.outlineVariant
        }

        // Hardware-Aware Battery Indicator (Laptops only)
        Rectangle {
            width: batRow.implicitWidth + 14
            height: parent.height
            radius: 0
            visible: DeviceCaps.hasBattery && ShellState.barShowBattery
            color: "transparent"

            Row {
                id: batRow
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
                    color: DeviceCaps.batteryLow
                        ? Theme.error
                        : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurface)
                }
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: DeviceCaps.hasBattery && ShellState.barShowBattery
            color: Theme.outlineVariant
        }

        // File Manager Toggle
        Rectangle {
            width: 30
            height: parent.height
            radius: 0
            visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
            color: filesSbMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰉋"
                font.family: Theme.iconFont
                font.pixelSize: 13
                color: filesSbMouse.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
            }

            MouseArea {
                id: filesSbMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleFilesRequested()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
            color: Theme.outlineVariant
        }

        // Settings Window Toggle
        Rectangle {
            width: 30
            height: parent.height
            radius: 0
            color: settingsBtnMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰒓"
                font.family: Theme.iconFont
                font.pixelSize: 13
                color: Theme.fgSurfaceVariant
            }

            MouseArea {
                id: settingsBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleSettingsRequested()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Simple Mode Toggle (click to return to Default mode)
        Rectangle {
            width: simpleLbl.implicitWidth + 16
            height: parent.height
            radius: 0
            color: simpleBtnMouse.containsMouse
                ? Qt.lighter(Theme.primary, 1.08)
                : Theme.primary

            Text {
                id: simpleLbl
                anchors.centerIn: parent
                text: "SIMPLE"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgPrimary
            }

            MouseArea {
                id: simpleBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.toggleShellMode("simple")
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Blur Mode Switch
        Rectangle {
            width: blurLbl.implicitWidth + 16
            height: parent.height
            radius: 0
            color: blurBtnMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                id: blurLbl
                anchors.centerIn: parent
                text: "BLUR"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            MouseArea {
                id: blurBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.setShellMode("blur")
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Quick Hub / Controls Toggle
        Rectangle {
            width: 34
            height: parent.height
            radius: 0
            color: hubBtnMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰍜"
                font.family: Theme.iconFont
                font.pixelSize: 13
                color: Theme.fgSurface
            }

            MouseArea {
                id: hubBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleDashboardRequested()
            }
        }
    }

    // Crisp 1px bottom hairline border
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.outlineVariant
    }
}
