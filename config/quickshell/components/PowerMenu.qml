pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

Rectangle {
    id: root

    property string pendingAction: ""
    signal actionTriggered(string actionId)

    function clearPending(): void {
        confirmResetTimer.stop();
        root.pendingAction = "";
    }

    function executeAction(actionId: string): void {
        clearPending();
        root.actionTriggered(actionId);
        if (actionId === "lock") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/lock.sh")]);
        } else if (actionId === "suspend") {
            Quickshell.execDetached(["loginctl", "suspend"]);
        } else if (actionId === "logout") {
            Quickshell.execDetached(["mmsg", "dispatch", "quit"]);
        } else if (actionId === "reboot") {
            Quickshell.execDetached(["loginctl", "reboot"]);
        } else if (actionId === "poweroff") {
            Quickshell.execDetached(["loginctl", "poweroff"]);
        }
    }

    readonly property var actionsModel: {
        const list = [];
        if (DeviceCaps.hasLocker) {
            list.push({ id: "lock", label: "Lock", icon: "󰌾", danger: false, needsConfirm: false });
        }
        list.push({ id: "suspend",  label: "Suspend",  icon: "󰒲", danger: false, needsConfirm: false });
        list.push({ id: "logout",   label: "Logout",   icon: "󰍃", danger: true,  needsConfirm: true  });
        list.push({ id: "reboot",   label: "Reboot",   icon: "󰜉", danger: true,  needsConfirm: true  });
        list.push({ id: "poweroff", label: "Poweroff", icon: "󰐥", danger: true,  needsConfirm: true  });
        return list;
    }

    Timer {
        id: confirmResetTimer
        interval: 4000
        repeat: false
        onTriggered: root.pendingAction = ""
    }

    implicitHeight: 34
    radius: Theme.r(12)
    color: Theme.cardBg
    border.width: Theme.cardBorderWidth
    border.color: Theme.cardBorder

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 6

        Repeater {
            model: root.actionsModel

            delegate: Rectangle {
                id: btn
                required property var modelData
                readonly property bool isPending: root.pendingAction === btn.modelData.id

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: Theme.r(8)
                color: {
                    if (btn.isPending)
                        return Theme.error;
                    if (btnArea.containsMouse)
                        return btn.modelData.danger ? Theme.withAlpha(Theme.error, 0.22) : Theme.hoverBg;
                    return Theme.subCardBg;
                }
                border.width: Theme.cardBorderWidth
                border.color: btn.isPending ? Theme.error : Theme.cardBorder
                scale: btnArea.pressed ? 0.95 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: btn.modelData.icon
                        font.family: Theme.iconFont
                        font.pixelSize: 12
                        color: {
                            if (btn.isPending)
                                return Theme.fgError;
                            if (btn.modelData.danger && btnArea.containsMouse)
                                return Theme.error;
                            return Theme.fgSurface;
                        }
                    }

                    Text {
                        text: btn.isPending ? "Confirm?" : btn.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: btn.isPending ? Font.Bold : Font.DemiBold
                        color: {
                            if (btn.isPending)
                                return Theme.fgError;
                            if (btn.modelData.danger && btnArea.containsMouse)
                                return Theme.error;
                            return Theme.fgSurface;
                        }
                    }
                }

                MouseArea {
                    id: btnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (btn.modelData.needsConfirm && !btn.isPending) {
                            root.pendingAction = btn.modelData.id;
                            confirmResetTimer.restart();
                        } else {
                            root.executeAction(btn.modelData.id);
                        }
                    }
                }
            }
        }
    }
}
