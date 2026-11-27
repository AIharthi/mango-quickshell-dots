pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import ".."

RowLayout {
    id: root

    property bool compact: false
    property string hiddenPlayerHint: ""

    function isHiddenMediaItem(item: var): bool {
        if (!item)
            return false;
        const hint = (root.hiddenPlayerHint || "").toLowerCase().trim();
        if (hint.length === 0)
            return false;
        const hay = (
            String(item.id || "") + " " +
            String(item.title || "") + " " +
            String(item.tooltipTitle || "") + " " +
            String(item.icon || "")
        ).toLowerCase();
        const tokens = hint.split(/[^a-z0-9]+/).filter(t => t.length >= 3);
        for (let i = 0; i < tokens.length; i++) {
            if (hay.indexOf(tokens[i]) !== -1)
                return true;
        }
        const knownPlayers = [
            "spotify", "vlc", "rhythmbox", "strawberry", "clementine",
            "audacious", "elisa", "amberol", "mpv", "tidal", "youtube", "cider"
        ];
        for (let j = 0; j < knownPlayers.length; j++) {
            const p = knownPlayers[j];
            if (hint.indexOf(p) !== -1 && hay.indexOf(p) !== -1)
                return true;
        }
        return false;
    }

    readonly property var visibleTrayItems: {
        const vals = SystemTray.items ? SystemTray.items.values : null;
        if (!vals || vals.length === 0)
            return [];
        const out = [];
        for (let i = 0; i < vals.length; i++) {
            const it = vals[i];
            if (!root.isHiddenMediaItem(it))
                out.push(it);
        }
        return out;
    }

    readonly property bool hasItems: root.visibleTrayItems.length > 0

    visible: hasItems
    spacing: root.compact ? 2 : 4

    Repeater {
        model: root.visibleTrayItems

        delegate: Rectangle {
            id: trayBtn
            required property var modelData
            readonly property var trayItem: modelData

            implicitWidth: root.compact ? 24 : 26
            implicitHeight: root.compact ? 24 : 26
            radius: Theme.r(root.compact ? 6 : 13)
            color: trayMouse.containsMouse
                ? Theme.m3SurfaceHigh
                : (root.compact ? "transparent" : Theme.m3SurfaceC)
            border.width: root.compact ? 0 : 1
            border.color: Theme.m3Line
            scale: trayMouse.pressed ? 0.90 : (trayMouse.containsMouse ? 1.08 : 1.0)

            visible: trayIconImg.source.toString().length > 0 && trayIconImg.status !== Image.Error

            Behavior on color {
                enabled: !Theme.isSimple
                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.isSimple
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            IconImage {
                id: trayIconImg
                anchors.centerIn: parent
                width: 15
                height: 15
                asynchronous: true
                source: trayBtn.trayItem ? trayBtn.trayItem.icon : ""
                visible: source.toString().length > 0
            }

            MouseArea {
                id: trayMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    const item = trayBtn.trayItem;
                    if (!item)
                        return;
                    const win = trayBtn.QsWindow.window;
                    if (mouse.button === Qt.RightButton) {
                        if (item.hasMenu && win) {
                            const pos = trayBtn.QsWindow.itemPosition(trayBtn);
                            const px = Math.round(pos.x);
                            const py = Math.round(pos.y + trayBtn.height);
                            Qt.callLater(() => item.display(win, px, py));
                        }
                    } else if (mouse.button === Qt.MiddleButton) {
                        item.secondaryActivate();
                    } else {
                        if (item.onlyMenu && win) {
                            const pos = trayBtn.QsWindow.itemPosition(trayBtn);
                            item.display(win, Math.round(pos.x), Math.round(pos.y + trayBtn.height));
                        } else {
                            item.activate();
                        }
                    }
                }
            }
        }
    }
}
