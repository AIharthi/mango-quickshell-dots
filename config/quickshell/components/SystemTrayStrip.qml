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
    readonly property bool hasItems: SystemTray.items.values.length > 0

    visible: hasItems
    spacing: root.compact ? 2 : 4

    Repeater {
        model: SystemTray.items

        delegate: Rectangle {
            id: trayBtn
            required property var modelData
            readonly property var trayItem: modelData

            implicitWidth: root.compact ? 24 : 26
            implicitHeight: root.compact ? 24 : 26
            radius: Theme.r(root.compact ? 6 : 13)
            color: trayMouse.containsMouse
                ? Theme.hoverBg
                : (root.compact ? "transparent" : Theme.cardBg)
            border.width: root.compact ? 0 : Theme.cardBorderWidth
            border.color: Theme.cardBorder
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
