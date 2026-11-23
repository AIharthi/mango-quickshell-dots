pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property bool active: false
    property string screenName: ""
    property string monitorName: ""
    property string currentLayout: "T"
    readonly property int totalClients: {
        let sum = 0;
        const arr = root.tagsModel || [];
        for (let i = 0; i < arr.length; i++)
            sum += (arr[i].client_count || 0);
        return sum;
    }
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

    onActiveChanged: {
        if (!active)
            restartTimer.stop();
    }

    function parseTagsJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const payload = JSON.parse(trimmed);
            const list = payload.all_tags;
            if (!list || list.length === 0)
                return;

            // Prefer the assigned screen monitor name, else fallback to monitorName / first
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

    // Stream live tag state via MangoWC 0.18.5 mmsg JSON stream only while active
    Process {
        id: tagStream
        command: ["mmsg", "watch", "all-tags"]
        running: root.active
        stdout: SplitParser {
            onRead: line => root.parseTagsJson(line)
        }
        onExited: exitCode => {
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

    radius: Theme.r(18)
    color: Theme.cardBg
    border.width: Theme.cardBorderWidth
    border.color: Theme.cardBorder
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false

            Text {
                text: "󰖲  MANGOWC TAGS"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Item { Layout.fillWidth: true }

            // Interactive Layout Switcher Badge
            Rectangle {
                implicitHeight: 20
                implicitWidth: layoutLabel.implicitWidth + 14
                radius: Theme.r(10)
                color: layoutArea.containsMouse ? Theme.activeBg : Theme.subCardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                Text {
                    id: layoutLabel
                    anchors.centerIn: parent
                    text: "Layout: " + root.currentLayout
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.primary
                }

                MouseArea {
                    id: layoutArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
                }
            }
        }

        // Interactive 1-9 Tag Pills + Windows/Overview 10th Tile (2x5 symmetric grid)
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 5
            rowSpacing: 8
            columnSpacing: 8

            Repeater {
                model: root.tagsModel

                delegate: Rectangle {
                    id: tagBtn
                    required property var modelData
                    readonly property bool isActive: tagBtn.modelData.is_active
                    readonly property bool isUrgent: tagBtn.modelData.is_urgent
                    readonly property bool isOccupied: tagBtn.modelData.client_count > 0

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 40
                    radius: Theme.r(12)
                    scale: tagMouse.pressed ? 0.92 : 1.0

                    Behavior on scale {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }

                    color: {
                        if (tagBtn.isUrgent)
                            return Theme.error;
                        if (tagBtn.isActive)
                            return Theme.primary;
                        if (tagMouse.containsMouse)
                            return Theme.hoverBg;
                        if (tagBtn.isOccupied)
                            return Theme.withAlpha(Theme.primary, 0.16);
                        return Theme.subCardBg;
                    }

                    border.width: tagBtn.isActive ? 1 : Theme.cardBorderWidth
                    border.color: tagBtn.isActive ? Theme.primary : Theme.cardBorder

                    Behavior on color {
                        enabled: !Theme.isSimple
                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tagBtn.modelData.index
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: {
                                if (tagBtn.isUrgent)
                                    return Theme.fgError;
                                if (tagBtn.isActive)
                                    return Theme.fgPrimary;
                                return tagBtn.isOccupied ? Theme.fgSurface : Theme.fgSurfaceVariant;
                            }
                        }

                        // Client occupancy indicator dot / bar
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: tagBtn.isActive ? 12 : (tagBtn.modelData.client_count > 1 ? 10 : 5)
                            implicitHeight: 3
                            radius: Theme.r(1.5)
                            visible: tagBtn.isOccupied || tagBtn.isActive
                            color: {
                                if (tagBtn.isUrgent)
                                    return Theme.fgError;
                                if (tagBtn.isActive)
                                    return Theme.fgPrimary;
                                return Theme.secondary;
                            }
                        }
                    }

                    MouseArea {
                        id: tagMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + tagBtn.modelData.index + ",0"])
                    }
                }
            }

            // 10th Tile: Open Window Switcher (LMB) / Overview Grid (RMB)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 40
                radius: Theme.r(12)
                color: winTileMouse.containsMouse
                    ? Theme.withAlpha(Theme.secondary, 0.24)
                    : Theme.withAlpha(Theme.secondary, 0.12)
                border.width: Math.max(1, Theme.cardBorderWidth)
                border.color: winTileMouse.containsMouse ? Theme.secondary : Theme.withAlpha(Theme.secondary, 0.38)
                scale: winTileMouse.pressed ? 0.92 : 1.0

                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 1

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "󰖯"
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                        color: Theme.secondary
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.totalClients > 0 ? String(root.totalClients) : "Wins"
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        color: Theme.fgSurfaceVariant
                    }
                }

                MouseArea {
                    id: winTileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Quickshell.execDetached(["mmsg", "dispatch", "toggleoverview"]);
                        else
                            Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleWindowSwitcher"]);
                    }
                }
            }
        }
    }
}
