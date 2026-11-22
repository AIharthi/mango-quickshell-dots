pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

ColumnLayout {
    id: root
    spacing: 12

    // --- 1. Shell & MangoWC Visual Mode ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: modeCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: modeCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "VISUAL MODE (QUICKSHELL + MANGOWC)"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { id: "default", title: "Default", desc: "Dynamic Island & rounded windows", icon: "󰕮" },
                        { id: "simple",  title: "Simple",  desc: "0px square, flat bar, zero gaps",  icon: "󰝤" },
                        { id: "blur",    title: "Blur",    desc: "Frosted glass & blurry windows",   icon: "󰂵" }
                    ]

                    delegate: Rectangle {
                        id: modeCard
                        required property var modelData
                        readonly property bool selected: Theme.shellMode === modeCard.modelData.id

                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        radius: Theme.r(12)
                        color: modeCard.selected
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (modeCardMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: modeCard.selected ? 1 : Theme.cardBorderWidth
                        border.color: modeCard.selected ? Theme.primary : Theme.cardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: modeCard.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: 15
                                    color: modeCard.selected ? Theme.primary : Theme.fgSurfaceVariant
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modeCard.modelData.title
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: modeCard.selected ? Theme.primary : Theme.fgSurface
                                }

                                Text {
                                    visible: modeCard.selected
                                    text: "󰄬"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 13
                                    color: Theme.primary
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modeCard.modelData.desc
                                wrapMode: Text.WordWrap
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: modeCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setShellMode(modeCard.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // --- 2. Palette & Color Scheme ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: themeCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: themeCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "THEME & PALETTE"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: schemeLbl.implicitWidth + 18
                    radius: Theme.r(12)
                    color: schemeBtnMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: schemeLbl
                        anchors.centerIn: parent
                        text: (Theme.colorScheme === "dark" ? "󰖔  Dark" : "󰖙  Light")
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: schemeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.toggleScheme()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { id: "dynamic", label: "Dynamic (Matugen)" },
                        { id: "preset",  label: "Preset Palette" }
                    ]

                    delegate: Rectangle {
                        id: palModeBtn
                        required property var modelData
                        readonly property bool selected: Theme.themeMode === palModeBtn.modelData.id

                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Theme.r(10)
                        color: palModeBtn.selected
                            ? Theme.primary
                            : (palModeMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: Theme.cardBorderWidth
                        border.color: palModeBtn.selected ? Theme.primary : Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: palModeBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: palModeBtn.selected ? Font.Bold : Font.Medium
                            color: palModeBtn.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: palModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setMode(palModeBtn.modelData.id)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: Theme.availablePresets

                    delegate: Rectangle {
                        id: presetBtn
                        required property var modelData
                        readonly property bool selected: Theme.themeMode === "preset" && Theme.presetName === presetBtn.modelData.id

                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Theme.r(10)
                        color: presetBtn.selected
                            ? Theme.activeBg
                            : (presetBtnMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: presetBtn.selected ? 1 : Theme.cardBorderWidth
                        border.color: presetBtn.selected ? Theme.primary : Theme.cardBorder

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                implicitWidth: 10
                                implicitHeight: 10
                                radius: Theme.r(5)
                                color: presetBtn.modelData.swatch
                            }

                            Text {
                                text: presetBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: presetBtn.selected ? Font.Bold : Font.Medium
                                color: presetBtn.selected ? Theme.primary : Theme.fgSurface
                            }
                        }

                        MouseArea {
                            id: presetBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.applyPreset(presetBtn.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // --- 3. MangoWC Visual Tuning ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: tuneCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: tuneCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "MANGOWC EFFECTS & GEOMETRY"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: resetLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: resetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: resetLbl
                        anchors.centerIn: parent
                        text: "Reset Defaults"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: resetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.resetModePrefs()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 28
                visible: Theme.isSimple
                radius: Theme.r(8)
                color: Theme.withAlpha(Theme.warning, 0.14)
                border.width: 1
                border.color: Theme.withAlpha(Theme.warning, 0.4)

                Text {
                    anchors.centerIn: parent
                    text: "Simple Mode enforces 0px radius, zero gaps, and no blur/animations."
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.warning
                }
            }

            Repeater {
                model: [
                    { key: "blurFocusedOpacity",   label: "Blur Focused Opacity",   val: Theme.blurFocusedOpacity.toFixed(2),   raw: Theme.blurFocusedOpacity,   step: 0.02, min: 0.60, max: 1.00, decimals: 2 },
                    { key: "blurUnfocusedOpacity", label: "Blur Unfocused Opacity", val: Theme.blurUnfocusedOpacity.toFixed(2), raw: Theme.blurUnfocusedOpacity, step: 0.02, min: 0.50, max: 0.98, decimals: 2 },
                    { key: "blurRadius",           label: "Blur Radius",            val: Theme.blurRadius + " px",              raw: Theme.blurRadius,           step: 1,    min: 2,    max: 16,   decimals: 0 },
                    { key: "blurPasses",           label: "Blur Passes",            val: String(Theme.blurPasses),              raw: Theme.blurPasses,           step: 1,    min: 1,    max: 6,    decimals: 0 },
                    { key: "defaultRadius",        label: "Window Corner Radius",   val: Theme.defaultRadius + " px",           raw: Theme.defaultRadius,        step: 2,    min: 0,    max: 28,   decimals: 0 },
                    { key: "defaultGaps",          label: "Window Gaps",            val: Theme.defaultGaps + " px",             raw: Theme.defaultGaps,          step: 2,    min: 0,    max: 24,   decimals: 0 }
                ]

                delegate: RowLayout {
                    id: stepRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    opacity: Theme.isSimple ? 0.5 : 1.0

                    Text {
                        Layout.fillWidth: true
                        text: stepRow.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurface
                    }

                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: minusMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.cardBorderWidth
                        border.color: Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: "-"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        MouseArea {
                            id: minusMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const next = Math.max(stepRow.modelData.min, stepRow.modelData.raw - stepRow.modelData.step);
                                Theme.updateModePref(stepRow.modelData.key, stepRow.modelData.decimals > 0 ? Number(next.toFixed(2)) : Math.round(next));
                            }
                        }
                    }

                    Text {
                        Layout.preferredWidth: 56
                        horizontalAlignment: Text.AlignHCenter
                        text: stepRow.modelData.val
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: plusMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.cardBorderWidth
                        border.color: Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        MouseArea {
                            id: plusMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const next = Math.min(stepRow.modelData.max, stepRow.modelData.raw + stepRow.modelData.step);
                                Theme.updateModePref(stepRow.modelData.key, stepRow.modelData.decimals > 0 ? Number(next.toFixed(2)) : Math.round(next));
                            }
                        }
                    }
                }
            }

            // Animations Toggle Row
            RowLayout {
                Layout.fillWidth: true
                opacity: Theme.isSimple ? 0.5 : 1.0

                Text {
                    Layout.fillWidth: true
                    text: "Window Animations"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitWidth: 58
                    implicitHeight: 24
                    radius: Theme.r(8)
                    color: Theme.wmAnimations ? Theme.withAlpha(Theme.primary, 0.24) : Theme.subCardBg
                    border.width: Theme.wmAnimations ? 1 : Theme.cardBorderWidth
                    border.color: Theme.wmAnimations ? Theme.primary : Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: Theme.wmAnimations ? "ON" : "OFF"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.wmAnimations ? Theme.primary : Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.updateModePref("animations", !Theme.wmAnimations)
                    }
                }
            }
        }
    }
}
