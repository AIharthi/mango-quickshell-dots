pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "."

// DarkShadowShell ControlCenter Overview tab: 136px M3 PrimaryContainer hero clock + spinning Blob,
// monthly calendar with Blob marking today, and 3 M3Blob CPU / RAM / Battery-or-Disk resource cards.
ColumnLayout {
    id: ov

    property bool active: false

    spacing: 12

    SystemClock {
        id: ovClock
        precision: SystemClock.Minutes
    }

    // 1. Hero Time & Date Platter with Spinning Background M3Blob
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 136
        radius: Theme.r(28)
        color: Theme.m3PrimaryContainer
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        M3Blob {
            width: 152
            height: 152
            x: parent.width - 118
            y: -28
            kind: ShellState.m3Shape
            color: Qt.rgba(Theme.m3Primary.r, Theme.m3Primary.g, Theme.m3Primary.b, Theme.isDark ? 0.16 : 0.14)

            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 38000
                loops: Animation.Infinite
                running: ov.active && ov.visible && !Theme.reducedMotion && !Theme.isSimple
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: ShellState.formatTime(ovClock.date)
                font.family: Theme.monoFont
                font.pixelSize: Theme.fs(44)
                font.weight: Font.Medium
                color: Theme.m3OnPrimaryContainer
            }

            Text {
                text: Qt.formatDate(ovClock.date, "dddd, d MMMM")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                color: Theme.withAlpha(Theme.m3OnPrimaryContainer, 0.84)
            }
        }
    }

    // 2. Month Calendar Card with M3Blob on Today
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: calCol.implicitHeight + 28
        radius: Theme.r(26)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        readonly property int yr: ovClock.date.getFullYear()
        readonly property int mo: ovClock.date.getMonth()
        readonly property int todayDay: ovClock.date.getDate()
        readonly property int lead: (new Date(yr, mo, 1).getDay() + 6) % 7
        readonly property int daysInMonth: new Date(yr, mo + 1, 0).getDate()

        ColumnLayout {
            id: calCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: Qt.formatDate(ovClock.date, "MMMM yyyy")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    font.weight: Font.DemiBold
                    color: Theme.m3Ink
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: ShellState.weatherEnabled && ShellState.weatherAvailable
                    text: ShellState.weatherIcon + " " + ShellState.weatherTemp
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Bold
                    color: Theme.m3Primary
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 7
                rowSpacing: 2
                columnSpacing: 0

                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    delegate: Text {
                        required property string modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.m3InkDim
                    }
                }

                Repeater {
                    model: (new Date(ovClock.date.getFullYear(), ovClock.date.getMonth(), 1).getDay() + 6) % 7
                        + new Date(ovClock.date.getFullYear(), ovClock.date.getMonth() + 1, 0).getDate()

                    delegate: Item {
                        required property int index
                        readonly property int leadCount: (new Date(ovClock.date.getFullYear(), ovClock.date.getMonth(), 1).getDay() + 6) % 7
                        readonly property int dayNum: index - leadCount + 1
                        readonly property bool isToday: dayNum === ovClock.date.getDate()

                        Layout.fillWidth: true
                        implicitHeight: 30

                        M3Blob {
                            visible: isToday
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            kind: ShellState.m3Shape
                            color: Theme.m3Primary
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: dayNum > 0
                            text: String(dayNum)
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(11)
                            font.weight: isToday ? Font.Bold : Font.Normal
                            color: isToday ? Theme.m3OnPrimary : Theme.m3Ink
                        }
                    }
                }
            }
        }
    }

    // 3. DarkShadowShell 3 Resource Cards (pentagon CPU, cookie RAM, flower/circle Battery or Disk)
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                {
                    shape: "pentagon",
                    label: "CPU",
                    val: Math.round(SystemTelemetry.cpuPercent) + "%"
                },
                {
                    shape: "cookie",
                    label: "RAM",
                    val: Math.round(SystemTelemetry.memPercent) + "%"
                },
                {
                    shape: DeviceCaps.hasBattery ? "flower" : "circle",
                    label: DeviceCaps.hasBattery ? "Battery" : "Disk",
                    val: DeviceCaps.hasBattery ? (DeviceCaps.batteryPercent + "%") : (Math.round(SystemTelemetry.diskPercent) + "%")
                }
            ]

            delegate: Rectangle {
                id: resCard
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 118
                radius: Theme.r(24)
                color: Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 12
                    width: 68
                    height: 68

                    M3Blob {
                        anchors.fill: parent
                        kind: resCard.modelData.shape
                        color: Theme.m3PrimaryContainer
                    }

                    Text {
                        anchors.centerIn: parent
                        text: resCard.modelData.val
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(16)
                        font.weight: Font.DemiBold
                        color: Theme.m3OnPrimaryContainer
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    text: resCard.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.m3InkDim
                }
            }
        }
    }
}
