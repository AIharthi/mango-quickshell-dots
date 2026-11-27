pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Notifications
import ".."
import "../m3"

Item {
    id: root

    property string mode: "osd"                 // "osd" | "notification"
    property bool active: false

    // OSD State
    property string osdType: "volume"           // "volume" | "mute" | "brightness" | "mic" | "kb" | "media-play" | "media-next" | "media-prev"
    property real osdValue: 0.5                 // 0.0 .. 1.0
    property bool osdMuted: false
    property bool osdSupported: true
    property string osdTextValue: ""
    property bool osdShowBar: true

    // Notification State
    property var currentNotif: null
    readonly property bool isUrgent: currentNotif !== null
        && currentNotif.urgency === NotificationUrgency.Critical
    readonly property real notificationHeight: notifRow.implicitHeight

    signal dismissRequested()

    function showOsd(kind: string): void {
        const normalized = (kind || "volume").toLowerCase();
        root.osdType = normalized;
        root.osdTextValue = "";
        root.osdShowBar = (normalized === "volume" || normalized === "mute" || normalized === "brightness" || normalized === "mic");
        refreshOsdValue(normalized);
    }

    property bool _volRefreshPending: false
    property bool _brightRefreshPending: false
    property bool _micRefreshPending: false

    Timer {
        id: pwOsdSyncTimer
        interval: 45
        repeat: false
        onTriggered: {
            if (root.osdType === "mic") {
                if (MangoState.pwSourceReady) {
                    root.osdMuted = MangoState.micMuted;
                    root.osdValue = root.osdMuted ? 0.0 : 1.0;
                    root.osdSupported = true;
                }
            } else if (root.osdType === "volume" || root.osdType === "mute") {
                if (MangoState.pwSinkReady) {
                    root.osdValue = Math.max(0.0, Math.min(1.5, MangoState.volPercent / 100.0));
                    root.osdMuted = MangoState.volMuted;
                    root.osdSupported = true;
                }
            }
        }
    }

    function refreshOsdValue(kind: string): void {
        const normalized = (kind || root.osdType || "volume").toLowerCase();
        if (normalized === "brightness") {
            if (!DeviceCaps.hasBacklight) {
                root.osdSupported = false;
                return;
            }
            if (brightnessProc.running)
                root._brightRefreshPending = true;
            else
                brightnessProc.running = true;
        } else if (normalized === "mic") {
            if (!DeviceCaps.hasAudio) {
                root.osdSupported = false;
                return;
            }
            if (MangoState.pwSourceReady) {
                root.osdMuted = MangoState.micMuted;
                root.osdValue = root.osdMuted ? 0.0 : 1.0;
                root.osdSupported = true;
                pwOsdSyncTimer.restart();
                return;
            }
            if (micProc.running)
                root._micRefreshPending = true;
            else
                micProc.running = true;
        } else if (normalized === "kb") {
            root.osdSupported = true;
            if (MangoState.kbLayoutShort.length > 0) {
                root.osdTextValue = MangoState.kbLayoutShort;
            } else if (!kbProc.running) {
                kbProc.running = true;
            }
        } else if (normalized.indexOf("media-") === 0) {
            root.osdSupported = true;
            if (!mediaProc.running)
                mediaProc.running = true;
        } else {
            if (!DeviceCaps.hasAudio) {
                root.osdSupported = false;
                return;
            }
            if (MangoState.pwSinkReady) {
                root.osdValue = Math.max(0.0, Math.min(1.5, MangoState.volPercent / 100.0));
                root.osdMuted = MangoState.volMuted;
                root.osdSupported = true;
                pwOsdSyncTimer.restart();
                return;
            }
            if (volumeProc.running)
                root._volRefreshPending = true;
            else
                volumeProc.running = true;
        }
    }

    function showNotification(notif: var): void {
        root.currentNotif = notif;
    }

    function dismissNotification(): void {
        if (root.currentNotif) {
            try {
                root.currentNotif.dismiss();
            } catch (err) {}
        }
        root.currentNotif = null;
        root.dismissRequested();
    }

    // --- System Queries for OSD ---
    Process {
        id: volumeProc
        command: ["sh", "-c", "pactl get-sink-volume @DEFAULT_SINK@; pactl get-sink-mute @DEFAULT_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/([0-9]+)%/);
                if (match) {
                    const v = parseInt(match[1], 10) / 100.0;
                    root.osdValue = Math.max(0.0, Math.min(1.5, v));
                    root.osdMuted = text.indexOf("Mute: yes") !== -1 || v <= 0.001;
                    root.osdSupported = true;
                }
            }
        }
        onExited: {
            if (root._volRefreshPending) {
                root._volRefreshPending = false;
                volumeProc.running = true;
            }
        }
    }

    Process {
        id: brightnessProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                // Format: device,class,current,percent%,max
                const parts = raw.split(",");
                if (parts.length >= 4) {
                    const pct = parseFloat(parts[3].replace("%", ""));
                    if (!isNaN(pct)) {
                        root.osdValue = Math.max(0.0, Math.min(1.0, pct / 100.0));
                        root.osdSupported = true;
                        return;
                    }
                }
                root.osdSupported = false;
                root.osdValue = 0;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.osdSupported = false;
            if (root._brightRefreshPending) {
                root._brightRefreshPending = false;
                brightnessProc.running = true;
            }
        }
    }

    Process {
        id: micProc
        command: ["sh", "-c", "pactl get-source-volume @DEFAULT_SOURCE@; pactl get-source-mute @DEFAULT_SOURCE@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/([0-9]+)%/);
                if (match) {
                    const v = parseInt(match[1], 10) / 100.0;
                    root.osdValue = Math.max(0.0, Math.min(1.5, v));
                    root.osdMuted = text.indexOf("Mute: yes") !== -1 || v <= 0.001;
                    root.osdSupported = true;
                }
            }
        }
        onExited: {
            if (root._micRefreshPending) {
                root._micRefreshPending = false;
                micProc.running = true;
            }
        }
    }

    Process {
        id: kbProc
        command: ["mmsg", "get", "keyboardlayout"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                try {
                    const d = JSON.parse(raw);
                    root.osdTextValue = String(d.layout || "Unknown");
                } catch (err) {
                    root.osdTextValue = raw || "Switched";
                }
            }
        }
    }

    Process {
        id: mediaProc
        command: ["sh", "-c", "playerctl metadata --format '{{status}}\t{{title}}\t{{artist}}' 2>/dev/null || echo 'Stopped\tMedia\t'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (text || "").trim().split("\t");
                const st = parts[0] || "";
                const title = parts[1] || "";
                const artist = parts[2] || "";
                root.osdMuted = (st.toLowerCase() === "paused");
                if (title.length > 0 && artist.length > 0)
                    root.osdTextValue = title + " · " + artist;
                else
                    root.osdTextValue = title || st || "Media";
            }
        }
    }

    // --- 1. Apple Dynamic Island OSD Layout (Volume / Mute / Brightness / Mic / Media / KB) ---
    RowLayout {
        id: osdRow
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 12
        visible: root.mode === "osd"

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 38
            implicitHeight: 38

            M3Blob {
                anchors.fill: parent
                kind: ShellState.m3Shape
                color: (root.osdType !== "brightness" && root.osdType !== "kb" && root.osdType.indexOf("media-") !== 0 && root.osdMuted)
                    ? Theme.m3ErrorContainer
                    : Theme.m3PrimaryContainer
            }

            Text {
                anchors.centerIn: parent
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(16)
                color: (root.osdType !== "brightness" && root.osdType !== "kb" && root.osdType.indexOf("media-") !== 0 && root.osdMuted)
                    ? Theme.m3OnErrorContainer
                    : Theme.m3OnPrimaryContainer
                text: {
                    if (root.osdType === "brightness")
                        return "󰃠";
                    if (root.osdType === "mic")
                        return root.osdMuted ? "󰍭" : "󰍬";
                    if (root.osdType === "kb")
                        return "󰌌";
                    if (root.osdType === "media-next")
                        return "󰒭";
                    if (root.osdType === "media-prev")
                        return "󰒮";
                    if (root.osdType === "media-play")
                        return root.osdMuted ? "󰏤" : "󰐊";
                    if (root.osdMuted || root.osdValue <= 0.001)
                        return "󰝟";
                    if (root.osdValue < 0.45)
                        return "󰖀";
                    return "󰕾";
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: {
                        if (root.osdType === "brightness")
                            return root.osdSupported ? "Display" : "No Backlight";
                        if (root.osdType === "mic")
                            return root.osdMuted ? "Mic Muted" : "Microphone";
                        if (root.osdType === "kb")
                            return "Keyboard Layout";
                        if (root.osdType.indexOf("media-") === 0)
                            return root.osdTextValue.length > 0 ? root.osdTextValue : "Media";
                        return root.osdMuted ? "Muted" : "Sound";
                    }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Bold
                    color: Theme.m3Ink
                }

                Text {
                    text: {
                        if (root.osdType === "kb")
                            return root.osdTextValue.length > 0 ? root.osdTextValue : "Active";
                        if (root.osdType === "media-next")
                            return "Next";
                        if (root.osdType === "media-prev")
                            return "Prev";
                        if (root.osdType === "media-play")
                            return root.osdMuted ? "Paused" : "Playing";
                        return root.osdSupported ? (Math.round(root.osdValue * 100) + "%") : "N/A";
                    }
                    font.family: (root.osdType === "kb" || root.osdType.indexOf("media-") === 0) ? Theme.fontFamily : Theme.monoFont
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.Bold
                    color: (root.osdType !== "brightness" && root.osdType !== "kb" && root.osdType.indexOf("media-") !== 0 && root.osdMuted)
                        ? Theme.m3Error
                        : Theme.m3Primary
                }
            }

            M3WavyLine {
                visible: root.osdShowBar
                Layout.fillWidth: true
                implicitHeight: 14
                value: Math.max(0.0, Math.min(1.0, root.osdValue))
                moving: false
                handle: false
                color: (root.osdType !== "brightness" && root.osdMuted) ? Theme.m3Error : Theme.m3Primary
                track: Theme.m3Track
            }
        }
    }

    // --- 2. Apple Notification Morphing Toast Layout ---
    RowLayout {
        id: notifRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 10
        visible: root.mode === "notification" && root.currentNotif !== null

        // App Icon / Notification Thumbnail
        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 42
            implicitHeight: 42

            M3Blob {
                visible: !notifImg.visible
                anchors.fill: parent
                kind: ShellState.m3Shape
                color: root.isUrgent ? Theme.m3ErrorContainer : Theme.m3PrimaryContainer
            }

            ClippingRectangle {
                id: notifThumbClip
                visible: notifImg.visible
                anchors.fill: parent
                radius: Theme.r(14)
                color: Theme.m3SurfaceC

                Image {
                    id: notifImg
                    anchors.fill: parent
                    visible: root.currentNotif !== null
                        && ((root.currentNotif.image && root.currentNotif.image.length > 0))
                    source: (root.currentNotif && root.currentNotif.image) ? root.currentNotif.image : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(64, 64)
                }
            }

            IconImage {
                id: notifIcon
                anchors.centerIn: parent
                width: 22
                height: 22
                asynchronous: true
                readonly property string resolvedIcon: (root.currentNotif && root.currentNotif.appIcon)
                    ? Quickshell.iconPath(root.currentNotif.appIcon, true)
                    : ""
                visible: !notifImg.visible && resolvedIcon.length > 0 && status === Image.Ready
                source: resolvedIcon
            }

            Text {
                anchors.centerIn: parent
                visible: !notifImg.visible && !notifIcon.visible
                text: root.isUrgent ? "󰀨" : "󰂚"
                font.family: Theme.iconFont
                font.pixelSize: 18
                color: root.isUrgent ? Theme.m3OnErrorContainer : Theme.m3OnPrimaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: (root.currentNotif && root.currentNotif.appName)
                        ? root.currentNotif.appName
                        : "Notification"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: root.isUrgent ? Theme.m3Error : Theme.m3Primary
                }

                Text {
                    text: "now"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    color: Theme.m3InkDim
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: Theme.r(11)
                    color: closeMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: Theme.iconFont
                        font.pixelSize: 10
                        color: Theme.m3InkDim
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissNotification()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: (root.currentNotif && root.currentNotif.summary) ? root.currentNotif.summary : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.Bold
                color: Theme.m3Ink
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: (root.currentNotif && root.currentNotif.body)
                    ? root.currentNotif.body.replace(/\n+/g, " ")
                    : ""
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.m3InkDim
            }

            // Notification Action Buttons
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                visible: root.currentNotif !== null
                    && root.currentNotif.actions
                    && root.currentNotif.actions.length > 0

                Repeater {
                    model: root.currentNotif ? root.currentNotif.actions : []
                    delegate: Rectangle {
                        id: actionBtn
                        required property var modelData
                        implicitHeight: 28
                        implicitWidth: actionLabel.implicitWidth + 20
                        height: 28
                        width: actionLabel.implicitWidth + 20
                        radius: Theme.r(actionArea.pressed ? 10 : 14)
                        color: actionArea.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer

                        Text {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: actionBtn.modelData.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Theme.m3OnSecondaryContainer
                        }

                        MouseArea {
                            id: actionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                actionBtn.modelData.invoke();
                                root.dismissNotification();
                            }
                        }
                    }
                }
            }
        }
    }
}
