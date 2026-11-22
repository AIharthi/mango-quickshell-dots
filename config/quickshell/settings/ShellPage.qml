pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: root
    spacing: 12

    // --- 1. Dynamic Island & Pill Behavior ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: islCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: islCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "DYNAMIC ISLAND & COMPACT PILL"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Expand Hub on Pointer Hover"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "When disabled, click the pill or press Super + D to expand"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.islandHoverExpand
                    onToggled: ShellState.setPref("islandHoverExpand", !ShellState.islandHoverExpand)
                }
            }

            StepControl {
                label: "Hover Expand Delay"
                displayValue: ShellState.islandHoverDelayMs + " ms"
                controlEnabled: ShellState.islandHoverExpand
                onDecremented: ShellState.setPref("islandHoverDelayMs", Math.max(50, ShellState.islandHoverDelayMs - 50))
                onIncremented: ShellState.setPref("islandHoverDelayMs", Math.min(1500, ShellState.islandHoverDelayMs + 50))
            }

            StepControl {
                label: "Auto-Collapse Leave Delay"
                displayValue: ShellState.islandCollapseDelayMs + " ms"
                onDecremented: ShellState.setPref("islandCollapseDelayMs", Math.max(200, ShellState.islandCollapseDelayMs - 100))
                onIncremented: ShellState.setPref("islandCollapseDelayMs", Math.min(4000, ShellState.islandCollapseDelayMs + 100))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Show Now-Playing MPRIS Strip in Pill"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.pillShowMedia
                    onToggled: ShellState.setPref("pillShowMedia", !ShellState.pillShowMedia)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                opacity: ShellState.pillShowMedia ? 1.0 : 0.45

                Text {
                    Layout.fillWidth: true
                    text: "Rotate Album Cover Art While Playing"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.pillSpinArt
                    onToggled: ShellState.setPref("pillSpinArt", !ShellState.pillSpinArt)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                opacity: ShellState.pillShowMedia ? 1.0 : 0.45

                Text {
                    Layout.fillWidth: true
                    text: "Show Animated Mini Equalizer Bars"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.pillShowEqualizer
                    onToggled: ShellState.setPref("pillShowEqualizer", !ShellState.pillShowEqualizer)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "On-Screen Volume & Brightness OSD Popups"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.osdEnabled
                    onToggled: ShellState.setPref("osdEnabled", !ShellState.osdEnabled)
                }
            }

            StepControl {
                label: "OSD Popup Duration"
                displayValue: (ShellState.osdTimeoutMs / 1000.0).toFixed(1) + " s"
                controlEnabled: ShellState.osdEnabled
                onDecremented: ShellState.setPref("osdTimeoutMs", Math.max(800, ShellState.osdTimeoutMs - 200))
                onIncremented: ShellState.setPref("osdTimeoutMs", Math.min(6000, ShellState.osdTimeoutMs + 200))
            }
        }
    }

    // --- 2. Simple Square Bar ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: barCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: barCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "SIMPLE MODE TOP/BOTTOM BAR"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            StepControl {
                label: "Bar Thickness"
                displayValue: ShellState.simpleBarHeight + " px"
                onDecremented: ShellState.setPref("simpleBarHeight", Math.max(22, ShellState.simpleBarHeight - 2))
                onIncremented: ShellState.setPref("simpleBarHeight", Math.min(44, ShellState.simpleBarHeight + 2))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Screen Edge Position"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                RowLayout {
                    spacing: 6

                    Repeater {
                        model: ["top", "bottom"]

                        delegate: Rectangle {
                            id: posPill
                            required property string modelData
                            readonly property bool selected: ShellState.simpleBarPosition === posPill.modelData

                            implicitHeight: 24
                            implicitWidth: posTxt.implicitWidth + 16
                            radius: Theme.r(7)
                            color: posPill.selected
                                ? Theme.withAlpha(Theme.primary, 0.22)
                                : (posMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: posPill.selected ? 1 : Theme.cardBorderWidth
                            border.color: posPill.selected ? Theme.primary : Theme.cardBorder

                            Text {
                                id: posTxt
                                anchors.centerIn: parent
                                text: posPill.modelData === "top" ? "Top" : "Bottom"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: posPill.selected ? Font.Bold : Font.Medium
                                color: posPill.selected ? Theme.primary : Theme.fgSurface
                            }

                            MouseArea {
                                id: posMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.setPref("simpleBarPosition", posPill.modelData)
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
                    text: "Show Layout Badge ([T]) Beside Workspaces"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.simpleBarShowLayout
                    onToggled: ShellState.setPref("simpleBarShowLayout", !ShellState.simpleBarShowLayout)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Show Date Next to Bar Clock"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.simpleBarShowDate
                    onToggled: ShellState.setPref("simpleBarShowDate", !ShellState.simpleBarShowDate)
                }
            }
        }
    }

    // --- 3. Screenshot Capture Pipeline ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: shotCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: shotCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "SCREENSHOTS (GRIM + SLURP)"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Save Directory"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: dirInput.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: dirInput.activeFocus ? Theme.primary : Theme.cardBorder

                    TextInput {
                        id: dirInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        text: ShellState.screenshotDir
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurface
                        clip: true
                        onAccepted: {
                            if (text.trim().length > 0)
                                ShellState.setPref("screenshotDir", text.trim());
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: saveDirLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: saveDirMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: saveDirLbl
                        anchors.centerIn: parent
                        text: "Save"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: saveDirMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (dirInput.text.trim().length > 0)
                                ShellState.setPref("screenshotDir", dirInput.text.trim());
                        }
                    }
                }
            }

            StepControl {
                label: "Capture Countdown Delay"
                displayValue: ShellState.screenshotDelay + " s"
                onDecremented: ShellState.setPref("screenshotDelay", Math.max(0, ShellState.screenshotDelay - 1))
                onIncremented: ShellState.setPref("screenshotDelay", Math.min(10, ShellState.screenshotDelay + 1))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Copy Captured Image to Clipboard (wl-copy)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.screenshotCopyClipboard
                    onToggled: ShellState.setPref("screenshotCopyClipboard", !ShellState.screenshotCopyClipboard)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Send Dynamic Island Notification After Capture"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.screenshotNotify
                    onToggled: ShellState.setPref("screenshotNotify", !ShellState.screenshotNotify)
                }
            }
        }
    }

    // --- 4. Accessibility & Motion ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: a11yCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: a11yCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "ACCESSIBILITY & MOTION"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Reduce Motion (Shell + GTK)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Disables spinning art, equalizer animation, and UI motion across Quickshell & GTK"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.reducedMotion
                    onToggled: ShellState.setPref("reducedMotion", !ShellState.reducedMotion)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "High-Contrast Card & Island Outlines"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Forces crisp high-visibility borders across panels, cards, and GTK a11y schema"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.highContrast
                    onToggled: ShellState.setPref("highContrast", !ShellState.highContrast)
                }
            }
        }
    }
}
