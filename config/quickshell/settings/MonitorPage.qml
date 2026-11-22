pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property var sensors: []
    property var processes: []
    property var services: []
    property string sortBy: "cpu"
    property string procFilter: ""
    property string svcFilter: "all"        // "all" | "active"
    property string initSystem: ""
    property string statusMsg: ""

    readonly property var filteredProcs: {
        const q = root.procFilter.trim().toLowerCase();
        if (q.length === 0)
            return root.processes;
        const out = [];
        for (let i = 0; i < root.processes.length; i++) {
            const p = root.processes[i];
            if ((p.name + " " + p.pid).toLowerCase().indexOf(q) !== -1)
                out.push(p);
        }
        return out;
    }

    readonly property var filteredServices: {
        const list = root.services || [];
        const out = [];
        for (let i = 0; i < list.length; i++) {
            const s = list[i];
            const st = String(s.status || "").toLowerCase();
            if (root.svcFilter === "active" && st !== "started" && st !== "running" && st !== "active")
                continue;
            out.push(s);
        }
        return out.slice(0, 35);
    }

    function refreshFast(): void {
        if (!hwmonProc.running)
            hwmonProc.running = true;
        if (!procListProc.running) {
            procListProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "processes", root.sortBy];
            procListProc.running = true;
        }
    }

    function refreshAll(): void {
        refreshFast();
        if (!svcProc.running)
            svcProc.running = true;
    }

    function signalProc(pid: int, sig: string): void {
        if (killProc.running)
            return;
        root.statusMsg = "Sent SIG" + sig + " to PID " + pid;
        killProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "kill-proc", String(pid), sig];
        killProc.running = true;
    }

    Component.onCompleted: refreshAll()

    Timer {
        interval: 4000
        repeat: true
        running: true
        onTriggered: root.refreshFast()
    }

    Process {
        id: hwmonProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "hwmon"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.sensors = Array.isArray(d.sensors) ? d.sensors : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: procListProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.processes = Array.isArray(d.processes) ? d.processes : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: svcProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "services"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.initSystem = d.initSystem || "";
                    root.services = Array.isArray(d.services) ? d.services : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: killProc
        onExited: root.refreshFast()
    }

    // --- 1. Live Thermal Sensors ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: thermCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: thermCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "HARDWARE THERMAL SENSORS (/sys/class/hwmon · 4s LIVE)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: thermRefLbl.implicitWidth + 12
                    radius: Theme.r(7)
                    color: thermRefMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: thermRefLbl
                        anchors.centerIn: parent
                        text: "Refresh"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: thermRefMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshAll()
                    }
                }
            }

            GridLayout {
                visible: root.sensors.length > 0
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: root.sensors

                    delegate: Rectangle {
                        id: sensCard
                        required property var modelData
                        readonly property real temp: Number(sensCard.modelData.tempC || 0)
                        readonly property real crit: Math.max(40, Number(sensCard.modelData.critC || 100))
                        readonly property real ratio: Math.max(0.0, Math.min(1.0, temp / crit))
                        readonly property color barCol: temp >= 80 ? Theme.error : (temp >= 65 ? Theme.warning : Theme.primary)

                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Theme.r(10)
                        color: Theme.subCardBg
                        border.width: Theme.cardBorderWidth
                        border.color: Theme.cardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: sensCard.modelData.chip + " · " + sensCard.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.fgSurface
                                }

                                Text {
                                    text: sensCard.temp.toFixed(1) + " °C"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: sensCard.barCol
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 5
                                radius: Theme.r(3)
                                color: Theme.surfaceContainerHighest

                                Rectangle {
                                    width: parent.width * sensCard.ratio
                                    height: parent.height
                                    radius: Theme.r(3)
                                    color: sensCard.barCol

                                    Behavior on width {
                                        enabled: !Theme.reducedMotion
                                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.sensors.length === 0
                text: "No hwmon thermal sensors exposed by kernel"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgSurfaceVariant
            }
        }
    }

    // --- 2. Process Manager ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: procCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: procCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "TOP RUNNING PROCESSES"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Repeater {
                    model: [
                        { id: "cpu", label: "CPU %" },
                        { id: "mem", label: "RAM MB" }
                    ]

                    delegate: Rectangle {
                        id: sortPill
                        required property var modelData
                        readonly property bool selected: root.sortBy === sortPill.modelData.id

                        implicitHeight: 22
                        implicitWidth: sortTxt.implicitWidth + 12
                        radius: Theme.r(7)
                        color: sortPill.selected
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (sortMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: sortPill.selected ? 1 : Theme.cardBorderWidth
                        border.color: sortPill.selected ? Theme.primary : Theme.cardBorder

                        Text {
                            id: sortTxt
                            anchors.centerIn: parent
                            text: sortPill.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: sortPill.selected ? Font.Bold : Font.Medium
                            color: sortPill.selected ? Theme.primary : Theme.fgSurface
                        }

                        MouseArea {
                            id: sortMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.sortBy = sortPill.modelData.id;
                                root.refreshFast();
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 28
                radius: Theme.r(8)
                color: Theme.subCardBg
                border.width: procFilterIn.activeFocus ? 1 : Theme.cardBorderWidth
                border.color: procFilterIn.activeFocus ? Theme.primary : Theme.cardBorder

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Filter processes by name or PID..."
                        visible: procFilterIn.text.length === 0
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }

                    TextInput {
                        id: procFilterIn
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        text: root.procFilter
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurface
                        clip: true
                        onTextEdited: root.procFilter = text
                    }
                }
            }

            Repeater {
                model: root.filteredProcs.slice(0, 15)

                delegate: Rectangle {
                    id: procRow
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 8

                        Text {
                            Layout.preferredWidth: 46
                            text: String(procRow.modelData.pid)
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: procRow.modelData.name
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.preferredWidth: 52
                            horizontalAlignment: Text.AlignRight
                            text: Number(procRow.modelData.cpuPct).toFixed(1) + "%"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Number(procRow.modelData.cpuPct) >= 50 ? Theme.warning : Theme.primary
                        }

                        Text {
                            Layout.preferredWidth: 68
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(Number(procRow.modelData.memMb)) + " MB"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.secondary
                        }

                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: termLbl.implicitWidth + 10
                            radius: Theme.r(5)
                            color: termMouse.containsMouse ? Theme.withAlpha(Theme.warning, 0.22) : Theme.cardBg

                            Text {
                                id: termLbl
                                anchors.centerIn: parent
                                text: "Stop"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: termMouse.containsMouse ? Theme.warning : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: termMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.signalProc(procRow.modelData.pid, "TERM")
                            }
                        }

                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: killLbl.implicitWidth + 10
                            radius: Theme.r(5)
                            color: killMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.cardBg

                            Text {
                                id: killLbl
                                anchors.centerIn: parent
                                text: "Kill"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: killMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: killMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.signalProc(procRow.modelData.pid, "KILL")
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.statusMsg.length > 0
                text: root.statusMsg
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.info
            }
        }
    }

    // --- 3. Services Viewer (OpenRC / systemd) ---
    Rectangle {
        visible: root.services.length > 0
        Layout.fillWidth: true
        implicitHeight: svcCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: svcCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "SYSTEM SERVICES (" + (root.initSystem ? root.initSystem.toUpperCase() : "INIT") + ")"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Repeater {
                    model: [
                        { id: "all", label: "All" },
                        { id: "active", label: "Running" }
                    ]

                    delegate: Rectangle {
                        id: svcFiltPill
                        required property var modelData
                        readonly property bool selected: root.svcFilter === svcFiltPill.modelData.id

                        implicitHeight: 22
                        implicitWidth: svcFiltTxt.implicitWidth + 12
                        radius: Theme.r(7)
                        color: svcFiltPill.selected
                            ? Theme.withAlpha(Theme.secondary, 0.22)
                            : (svcFiltMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: svcFiltPill.selected ? 1 : Theme.cardBorderWidth
                        border.color: svcFiltPill.selected ? Theme.secondary : Theme.cardBorder

                        Text {
                            id: svcFiltTxt
                            anchors.centerIn: parent
                            text: svcFiltPill.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: svcFiltPill.selected ? Font.Bold : Font.Medium
                            color: svcFiltPill.selected ? Theme.secondary : Theme.fgSurface
                        }

                        MouseArea {
                            id: svcFiltMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.svcFilter = svcFiltPill.modelData.id
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 6
                rowSpacing: 6

                Repeater {
                    model: root.filteredServices

                    delegate: Rectangle {
                        id: svcRow
                        required property var modelData
                        readonly property string stLow: String(svcRow.modelData.status || "").toLowerCase()
                        readonly property bool runningState: stLow === "started" || stLow === "running" || stLow === "active"

                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: Theme.subCardBg
                        border.width: Theme.cardBorderWidth
                        border.color: Theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: svcRow.modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgSurface
                            }

                            Text {
                                text: svcRow.modelData.status
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: svcRow.runningState ? Theme.success : Theme.fgSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
