pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Material 3 connected segmented button group with morphing active pill and check mark.
Row {
    id: seg

    property var options: [] // [{ value, label, icon }]
    property string current: ""
    property bool compact: false
    property bool showCheck: true

    signal chosen(string value)

    spacing: 2

    Repeater {
        model: seg.options

        delegate: Rectangle {
            id: segBtn
            required property var modelData
            required property int index

            readonly property bool on: seg.current === segBtn.modelData.value
            readonly property int h: seg.compact ? 30 : 36

            width: segRow.implicitWidth + (on && seg.showCheck ? 24 : 20)
            height: h
            radius: Theme.r(on ? Math.round(h / 2) : 10)
            color: on ? Theme.m3Primary : (segMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
            scale: segMouse.pressed ? 0.96 : 1.0

            Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 160 } }
            Behavior on radius {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 240; easing.type: Theme.m3Springy; easing.overshoot: 1.4 }
            }
            Behavior on width {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 260; easing.type: Theme.m3Springy; easing.overshoot: 1.3 }
            }

            Row {
                id: segRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                    visible: segBtn.on && seg.showCheck
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰄬"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(seg.compact ? 11 : 12)
                    color: Theme.m3OnPrimary
                }

                Text {
                    visible: !(segBtn.on && seg.showCheck) && String(segBtn.modelData.icon || "").length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(segBtn.modelData.icon || "")
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(seg.compact ? 11 : 12)
                    color: segBtn.on ? Theme.m3OnPrimary : Theme.m3InkDim
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(segBtn.modelData.label || "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(seg.compact ? 11 : 12)
                    font.weight: segBtn.on ? Font.DemiBold : Font.Normal
                    color: segBtn.on ? Theme.m3OnPrimary : Theme.m3Ink
                }
            }

            MouseArea {
                id: segMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: seg.chosen(segBtn.modelData.value)
            }
        }
    }
}
