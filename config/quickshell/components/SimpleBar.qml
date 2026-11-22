pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property bool active: true
    property string screenName: ""
    property string monitorName: ""
    property string currentLayout: "T"
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

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
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

    // Left: Flat Square MangoWC Tags + Layout Indicator
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
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Flat Layout Switcher
        Rectangle {
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
    }

    // Center: Plain Square Monospace Clock
    Row {
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Bold
            color: Theme.fgSurface
        }

        Text {
            text: Qt.formatDateTime(clock.date, "ddd MMM d")
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgSurfaceVariant
        }
    }

    // Right: Tray + Battery (if present) + Settings + Mode Switches + Hub Toggle
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        // System Tray (shown only when tray apps exist)
        Item {
            width: trayStrip.implicitWidth + 10
            height: parent.height
            visible: trayStrip.hasItems

            SystemTrayStrip {
                id: trayStrip
                anchors.centerIn: parent
                compact: true
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: trayStrip.hasItems
            color: Theme.outlineVariant
        }

        // Hardware-Aware Battery Indicator (Laptops only)
        Rectangle {
            width: batRow.implicitWidth + 14
            height: parent.height
            radius: 0
            visible: DeviceCaps.hasBattery
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
            visible: DeviceCaps.hasBattery
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
