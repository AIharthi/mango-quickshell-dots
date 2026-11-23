pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

ColumnLayout {
    id: root
    spacing: 12

    readonly property var durationOptions: [
        { label: "2.5s", ms: 2500 },
        { label: "4.5s", ms: 4500 },
        { label: "7s",   ms: 7000 },
        { label: "10s",  ms: 10000 }
    ]

    Component.onCompleted: ShellState.clearUnread()

    // --- 1. Do Not Disturb & Popup Behavior ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: dndCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: dndCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Text {
                text: "DO NOT DISTURB & POPUPS"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: Theme.r(10)
                    color: ShellState.dnd ? Theme.withAlpha(Theme.warning, 0.20) : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: ShellState.dnd ? Theme.withAlpha(Theme.warning, 0.45) : Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: ShellState.dnd ? "󰂛" : "󰂚"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(16)
                        color: ShellState.dnd ? Theme.warning : Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Do Not Disturb"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Silence notification island banners while continuing to record incoming notifications below"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.dnd
                    activeColor: Theme.warning
                    onToggled: ShellState.toggleDnd()
                }
            }

            // Auto-hide timeout selector
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Popup Auto-Hide Duration"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                RowLayout {
                    spacing: 5

                    Repeater {
                        model: root.durationOptions

                        delegate: Rectangle {
                            id: durPill
                            required property var modelData
                            readonly property bool selected: ShellState.notifTimeoutMs === durPill.modelData.ms

                            implicitHeight: 24
                            implicitWidth: durTxt.implicitWidth + 14
                            radius: Theme.r(7)
                            color: durPill.selected
                                ? Theme.withAlpha(Theme.primary, 0.22)
                                : (durMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: durPill.selected ? 1 : Theme.cardBorderWidth
                            border.color: durPill.selected ? Theme.primary : Theme.cardBorder
                            scale: durMouse.pressed ? 0.95 : 1.0

                            Behavior on color {
                                enabled: !Theme.isSimple
                                ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                            }
                            Behavior on scale {
                                enabled: !Theme.isSimple
                                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                            }

                            Text {
                                id: durTxt
                                anchors.centerIn: parent
                                text: durPill.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: durPill.selected ? Font.Bold : Font.Medium
                                color: durPill.selected ? Theme.primary : Theme.fgSurface
                            }

                            MouseArea {
                                id: durMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.setPref("notifTimeoutMs", durPill.modelData.ms)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Allow Critical / Urgent Alerts During DND"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.dndAllowCritical
                    onToggled: ShellState.setPref("dndAllowCritical", !ShellState.dndAllowCritical)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Play Desktop Sound on Notification"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.notifSoundEnabled
                    onToggled: ShellState.setPref("notifSoundEnabled", !ShellState.notifSoundEnabled)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Session History Capacity"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                RowLayout {
                    spacing: 5

                    Repeater {
                        model: [20, 40, 100]

                        delegate: Rectangle {
                            id: hCapPill
                            required property int modelData
                            readonly property bool selected: ShellState.notifMaxHistory === hCapPill.modelData

                            implicitHeight: 24
                            implicitWidth: hCapTxt.implicitWidth + 12
                            radius: Theme.r(7)
                            color: hCapPill.selected ? Theme.withAlpha(Theme.secondary, 0.22) : Theme.subCardBg
                            border.width: hCapPill.selected ? 1 : Theme.cardBorderWidth
                            border.color: hCapPill.selected ? Theme.secondary : Theme.cardBorder

                            Text {
                                id: hCapTxt
                                anchors.centerIn: parent
                                text: String(hCapPill.modelData)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: hCapPill.selected ? Font.Bold : Font.Medium
                                color: hCapPill.selected ? Theme.secondary : Theme.fgSurface
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.setPref("notifMaxHistory", hCapPill.modelData)
                            }
                        }
                    }
                }
            }

            // Test notification button
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Preview banner appearance & auto-dismiss timing"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: testRow.implicitWidth + 18
                    radius: Theme.r(8)
                    color: testMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    scale: testMouse.pressed ? 0.96 : 1.0

                    Behavior on color {
                        enabled: !Theme.isSimple
                        ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        id: testRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "󰂞"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(12)
                            color: Theme.primary
                        }

                        Text {
                            text: "Send Test Notification"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: testMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached([
                            "sh", "-c",
                            "command -v notify-send >/dev/null && notify-send -a Settings 'Test Notification' 'Dynamic Island notifications are active'"
                        ])
                    }
                }
            }
        }
    }

    // --- 2. Notification History ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: histCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: histCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "NOTIFICATION HISTORY"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 18
                    implicitWidth: cntTxt.implicitWidth + 10
                    radius: Theme.r(6)
                    color: Theme.withAlpha(Theme.secondary, 0.18)

                    Text {
                        id: cntTxt
                        anchors.centerIn: parent
                        text: String(ShellState.notificationHistory.length)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.secondary
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: ShellState.notificationHistory.length > 0
                    implicitHeight: 24
                    implicitWidth: clrRow.implicitWidth + 14
                    radius: Theme.r(7)
                    color: clrHistMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        id: clrRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            text: "󰆴"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(11)
                            color: clrHistMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                        }

                        Text {
                            text: "Clear All"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: clrHistMouse.containsMouse ? Theme.error : Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: clrHistMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.clearHistory()
                    }
                }
            }

            Repeater {
                model: ShellState.notificationHistory

                delegate: Rectangle {
                    id: notifCard
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: notifBodyCol.implicitHeight + 16
                    radius: Theme.r(11)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        ColumnLayout {
                            id: notifBodyCol
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: notifCard.modelData.appName || "System"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                }

                                Text {
                                    text: "·  " + (notifCard.modelData.timeStr || "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    color: Theme.fgSurfaceVariant
                                }

                                Item { Layout.fillWidth: true }
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: notifCard.modelData.summary || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.DemiBold
                                color: Theme.fgSurface
                            }

                            Text {
                                visible: (notifCard.modelData.body || "").length > 0
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: notifCard.modelData.body || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 22
                            implicitHeight: 22
                            radius: Theme.r(6)
                            color: disMouse.containsMouse ? Theme.hoverBg : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(10)
                                color: Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: disMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.dismissNotification(notifCard.modelData.uid)
                            }
                        }
                    }
                }
            }

            Text {
                visible: ShellState.notificationHistory.length === 0
                text: "No notifications recorded in this session yet"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant
            }
        }
    }
}
