pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

Rectangle {
    id: root

    property string pendingAction: ""
    readonly property bool compact: root.width < 440
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
        } else if (actionId === "suspend" || actionId === "logout" || actionId === "reboot" || actionId === "poweroff") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/manage-system.sh"), "power-action", actionId]);
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

    implicitHeight: 40
    radius: Theme.r(20)
    color: Theme.m3SurfaceC
    border.width: 1
    border.color: Theme.m3Line
    clip: true

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.compact ? 4 : 6
        anchors.rightMargin: root.compact ? 4 : 6
        spacing: root.compact ? 4 : 6

        Repeater {
            model: root.actionsModel

            delegate: Rectangle {
                id: btn
                required property var modelData
                readonly property bool isPending: root.pendingAction === btn.modelData.id

                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: Theme.r(btnArea.pressed ? 9 : 15)
                clip: true
                color: {
                    if (btn.isPending)
                        return Theme.m3Error;
                    if (btnArea.containsMouse)
                        return btn.modelData.danger ? Theme.m3ErrorContainer : Theme.m3SecondaryContainer;
                    return Theme.m3SurfaceHigh;
                }
                scale: btnArea.pressed ? 0.94 : 1.0

                Behavior on color {
                    enabled: !Theme.reducedMotion
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on radius {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 150 }
                }
                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 90 }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: root.compact ? 3 : 5

                    Text {
                        text: btn.modelData.icon
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(12)
                        color: {
                            if (btn.isPending)
                                return Theme.m3OnErrorContainer;
                            if (btn.modelData.danger && btnArea.containsMouse)
                                return Theme.m3OnErrorContainer;
                            if (btn.modelData.danger)
                                return Theme.m3Error;
                            return btnArea.containsMouse ? Theme.m3OnSecondaryContainer : Theme.m3Ink;
                        }
                    }

                    Text {
                        text: btn.isPending ? "Confirm?" : btn.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(root.compact ? 9 : 10)
                        font.weight: btn.isPending ? Font.Bold : Font.Medium
                        color: {
                            if (btn.isPending)
                                return Theme.m3OnErrorContainer;
                            if (btn.modelData.danger && btnArea.containsMouse)
                                return Theme.m3OnErrorContainer;
                            if (btn.modelData.danger)
                                return Theme.m3Error;
                            return btnArea.containsMouse ? Theme.m3OnSecondaryContainer : Theme.m3Ink;
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
