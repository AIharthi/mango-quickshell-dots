pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Material 3 Expressive workspace strip modeled on DarkShadowShell's WsStrip.qml:
// inactive tags are soft dots (dimmed/tinted when occupied), while the active tag
// stretches into a primary pill displaying its workspace number.
Item {
    id: ws

    property var model: []
    property int barHeight: 34
    property bool compact: false
    property bool interactive: true

    readonly property int chipH: Math.max(18, Math.min(24, barHeight - 10))
    readonly property int dotH: compact ? 8 : 10
    readonly property int activeW: compact ? 32 : 38

    signal switchRequested(int index)
    signal relativeSwitchRequested(int delta)

    implicitWidth: wsRow.implicitWidth
    implicitHeight: Math.max(ws.chipH, ws.dotH + 6)

    WheelHandler {
        enabled: ws.interactive
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property real sum: 0
        property bool done: false
        onWheel: function(e) {
            if (e.pixelDelta && Math.abs(e.pixelDelta.y) > 0) {
                restTimer.restart();
                if (done) return;
                sum += e.pixelDelta.y;
                if (Math.abs(sum) >= 40) {
                    ws.relativeSwitchRequested(sum > 0 ? -1 : 1);
                    done = true;
                }
            } else {
                restTimer.restart();
                sum += e.angleDelta.y;
                if (Math.abs(sum) >= 120) {
                    ws.relativeSwitchRequested(sum > 0 ? -1 : 1);
                    sum = 0;
                }
            }
        }
    }

    Timer {
        id: restTimer
        interval: 260
        repeat: false
        onTriggered: {
            wsWheelState.reset();
        }
    }

    QtObject {
        id: wsWheelState
        function reset() {
            // Handler resets naturally on idle
        }
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: ws.compact ? 5 : 7

        Repeater {
            model: ws.model

            delegate: Item {
                id: cell
                required property var modelData
                readonly property int wid: Number(cell.modelData.index || (index + 1))
                readonly property bool isActive: !!cell.modelData.is_active
                readonly property bool isUrgent: !!cell.modelData.is_urgent
                readonly property bool isOccupied: Number(cell.modelData.client_count || 0) > 0

                width: cell.isActive ? ws.activeW : (ws.dotH + 4)
                height: Math.max(ws.chipH, ws.dotH + 4)

                Behavior on width {
                    enabled: !Theme.reducedMotion
                    NumberAnimation {
                        duration: 260
                        easing.type: Theme.m3Springy
                        easing.overshoot: 1.4
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: cell.isActive ? parent.width : ws.dotH
                    height: cell.isActive ? ws.chipH : ws.dotH
                    radius: Theme.isSimple ? 0 : (height / 2)
                    scale: cellMouse.containsMouse && !cell.isActive ? 1.24 : 1.0

                    color: {
                        if (cell.isUrgent)
                            return Theme.m3Error;
                        if (cell.isActive)
                            return Theme.m3Primary;
                        if (cell.isOccupied)
                            return Theme.m3OnSecondaryContainer;
                        return Theme.m3Track;
                    }

                    opacity: cell.isActive || cell.isUrgent ? 1.0 : (cell.isOccupied ? 0.72 : 0.90)

                    Behavior on height {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 240; easing.type: Theme.m3Springy; easing.overshoot: 1.4 }
                    }
                    Behavior on color {
                        enabled: !Theme.reducedMotion
                        ColorAnimation { duration: 180 }
                    }
                    Behavior on scale {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    Text {
                        anchors.centerIn: parent
                        opacity: cell.isActive ? 1.0 : 0.0
                        visible: opacity > 0.01
                        text: String(cell.wid)
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(ws.compact ? 10 : 11)
                        font.weight: Font.Bold
                        color: cell.isUrgent ? Theme.m3OnErrorContainer : Theme.m3OnPrimary

                        Behavior on opacity {
                            enabled: !Theme.reducedMotion
                            NumberAnimation { duration: 160 }
                        }
                    }
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    enabled: ws.interactive
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ws.switchRequested(cell.wid)
                }
            }
        }
    }
}
