pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

// Material 3 Expressive Android 16 style grouped settings row (outer 22px, inner 6px radii, 40px icon square -> circle).
Rectangle {
    id: row

    property string label: ""
    property string desc: ""
    property string icon: ""
    property bool lit: false
    property bool joinPrev: false
    property bool joinNext: false

    default property alias rightContent: rightSlot.data

    readonly property bool hasIcon: icon.length > 0
    readonly property real topR: Theme.isSimple ? 0 : (joinPrev ? Theme.m3RowIn : Theme.m3RowOut)
    readonly property real botR: Theme.isSimple ? 0 : (joinNext ? Theme.m3RowIn : Theme.m3RowOut)

    Layout.fillWidth: true
    implicitHeight: Math.max(desc.length > 0 ? 68 : 56, mainRow.implicitHeight + 20)
    topLeftRadius: topR
    topRightRadius: topR
    bottomLeftRadius: botR
    bottomRightRadius: botR
    color: hov.hovered ? Theme.m3SurfaceHigh : Theme.m3SurfaceC
    border.width: Theme.isSimple ? 1 : 0
    border.color: Theme.m3Line

    Behavior on topLeftRadius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on bottomLeftRadius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }

    HoverHandler { id: hov }

    RowLayout {
        id: mainRow
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 14

        Rectangle {
            visible: row.hasIcon
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 40
            implicitHeight: 40
            radius: Theme.isSimple ? 0 : (row.lit ? 20 : Theme.r(12))
            color: row.lit ? Theme.m3PrimaryContainer : Theme.m3SurfaceHighest

            Behavior on radius {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 280; easing.type: Theme.m3Springy; easing.overshoot: 1.5 }
            }
            Behavior on color {
                enabled: !Theme.reducedMotion
                ColorAnimation { duration: 180 }
            }

            Text {
                anchors.centerIn: parent
                text: row.icon
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(17)
                color: row.lit ? Theme.m3OnPrimaryContainer : Theme.m3InkDim
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: row.label
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                font.weight: Font.Medium
                color: Theme.m3Ink
            }

            Text {
                visible: row.desc.length > 0
                Layout.fillWidth: true
                text: row.desc
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.m3InkDim
            }
        }

        RowLayout {
            id: rightSlot
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
        }
    }
}
