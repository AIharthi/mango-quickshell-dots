pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property var foot: ({ exists: false, alpha: 1.0, pad: 10, cursorStyle: "block", cursorBlink: false, scrollback: 1000 })
    property var kitty: ({ exists: false, opacity: 1.0, padding: 10, cursorShape: "block", cursorBlink: 0.5, scrollback: 2000, confirmClose: 0 })

    function applyPayload(raw: string): void {
        const txt = (raw || "").trim();
        if (txt.length === 0)
            return;
        try {
            const d = JSON.parse(txt);
            if (d.foot) root.foot = d.foot;
            if (d.kitty) root.kitty = d.kitty;
        } catch (err) {}
    }

    function setTerm(term: string, key: string, val: var): void {
        if (mutProc.running)
            return;
        mutProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "terminal-set", term, key, String(val)];
        mutProc.running = true;
    }

    Component.onCompleted: queryProc.running = true

    Process {
        id: queryProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "terminal-get"]
        stdout: StdioCollector {
            onStreamFinished: root.applyPayload(text)
        }
    }

    Process {
        id: mutProc
        stdout: StdioCollector {
            onStreamFinished: root.applyPayload(text)
        }
    }

    // --- 1. Foot Terminal ---
    Rectangle {
        visible: DeviceCaps.hasFoot && !!root.foot.exists
        Layout.fillWidth: true
        implicitHeight: footCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: footCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "FOOT WAYLAND TERMINAL (~/.config/foot/foot.ini)"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            StepControl {
                label: "Background Opacity (colors.alpha)"
                displayValue: Math.round(Number(root.foot.alpha || 1.0) * 100) + "%"
                onDecremented: root.setTerm("foot", "alpha", Math.max(0.50, Number(root.foot.alpha || 1.0) - 0.05).toFixed(2))
                onIncremented: root.setTerm("foot", "alpha", Math.min(1.00, Number(root.foot.alpha || 1.0) + 0.05).toFixed(2))
            }

            StepControl {
                label: "Window Inner Padding"
                displayValue: Number(root.foot.pad || 0) + " px"
                onDecremented: root.setTerm("foot", "pad", Math.max(0, Number(root.foot.pad || 0) - 2))
                onIncremented: root.setTerm("foot", "pad", Math.min(32, Number(root.foot.pad || 0) + 2))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Cursor Shape"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                RowLayout {
                    spacing: 5

                    Repeater {
                        model: ["block", "beam", "underline"]

                        delegate: Rectangle {
                            id: fCurPill
                            required property string modelData
                            readonly property bool selected: root.foot.cursorStyle === fCurPill.modelData

                            implicitHeight: 24
                            implicitWidth: fCurTxt.implicitWidth + 14
                            radius: Theme.r(7)
                            color: fCurPill.selected
                                ? Theme.withAlpha(Theme.primary, 0.22)
                                : (fCurMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: fCurPill.selected ? 1 : Theme.cardBorderWidth
                            border.color: fCurPill.selected ? Theme.primary : Theme.cardBorder

                            Text {
                                id: fCurTxt
                                anchors.centerIn: parent
                                text: fCurPill.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: fCurPill.selected ? Font.Bold : Font.Medium
                                color: fCurPill.selected ? Theme.primary : Theme.fgSurface
                            }

                            MouseArea {
                                id: fCurMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setTerm("foot", "cursorStyle", fCurPill.modelData)
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
                    text: "Blinking Cursor"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: !!root.foot.cursorBlink
                    onToggled: root.setTerm("foot", "cursorBlink", !root.foot.cursorBlink)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Scrollback Lines"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                RowLayout {
                    spacing: 5

                    Repeater {
                        model: [1000, 5000, 10000, 50000]

                        delegate: Rectangle {
                            id: fScrPill
                            required property int modelData
                            readonly property bool selected: Number(root.foot.scrollback || 0) === fScrPill.modelData

                            implicitHeight: 24
                            implicitWidth: fScrTxt.implicitWidth + 12
                            radius: Theme.r(7)
                            color: fScrPill.selected
                                ? Theme.withAlpha(Theme.secondary, 0.22)
                                : (fScrMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: fScrPill.selected ? 1 : Theme.cardBorderWidth
                            border.color: fScrPill.selected ? Theme.secondary : Theme.cardBorder

                            Text {
                                id: fScrTxt
                                anchors.centerIn: parent
                                text: fScrPill.modelData >= 1000 ? ((fScrPill.modelData / 1000) + "k") : String(fScrPill.modelData)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: fScrPill.selected ? Font.Bold : Font.Medium
                                color: fScrPill.selected ? Theme.secondary : Theme.fgSurface
                            }

                            MouseArea {
                                id: fScrMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setTerm("foot", "scrollback", fScrPill.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 2. Kitty Terminal ---
    Rectangle {
        visible: DeviceCaps.hasKitty && !!root.kitty.exists
        Layout.fillWidth: true
        implicitHeight: kittyCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: kittyCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "KITTY TERMINAL (~/.config/kitty/kitty.conf)"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            StepControl {
                label: "Background Opacity"
                displayValue: Math.round(Number(root.kitty.opacity || 1.0) * 100) + "%"
                accentColor: Theme.secondary
                onDecremented: root.setTerm("kitty", "opacity", Math.max(0.50, Number(root.kitty.opacity || 1.0) - 0.05).toFixed(2))
                onIncremented: root.setTerm("kitty", "opacity", Math.min(1.00, Number(root.kitty.opacity || 1.0) + 0.05).toFixed(2))
            }

            StepControl {
                label: "Window Padding Width"
                displayValue: Number(root.kitty.padding || 0) + " px"
                accentColor: Theme.secondary
                onDecremented: root.setTerm("kitty", "padding", Math.max(0, Number(root.kitty.padding || 0) - 2))
                onIncremented: root.setTerm("kitty", "padding", Math.min(32, Number(root.kitty.padding || 0) + 2))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Cursor Shape"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                RowLayout {
                    spacing: 5

                    Repeater {
                        model: ["block", "beam", "underline"]

                        delegate: Rectangle {
                            id: kCurPill
                            required property string modelData
                            readonly property bool selected: root.kitty.cursorShape === kCurPill.modelData

                            implicitHeight: 24
                            implicitWidth: kCurTxt.implicitWidth + 14
                            radius: Theme.r(7)
                            color: kCurPill.selected
                                ? Theme.withAlpha(Theme.secondary, 0.22)
                                : (kCurMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: kCurPill.selected ? 1 : Theme.cardBorderWidth
                            border.color: kCurPill.selected ? Theme.secondary : Theme.cardBorder

                            Text {
                                id: kCurTxt
                                anchors.centerIn: parent
                                text: kCurPill.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: kCurPill.selected ? Font.Bold : Font.Medium
                                color: kCurPill.selected ? Theme.secondary : Theme.fgSurface
                            }

                            MouseArea {
                                id: kCurMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setTerm("kitty", "cursorShape", kCurPill.modelData)
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
                    text: "Blinking Cursor"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Number(root.kitty.cursorBlink || 0) > 0
                    activeColor: Theme.secondary
                    onToggled: root.setTerm("kitty", "cursorBlink", Number(root.kitty.cursorBlink || 0) > 0 ? 0.0 : 0.5)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Confirm Before Closing OS Window"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Number(root.kitty.confirmClose || 0) !== 0
                    activeColor: Theme.secondary
                    onToggled: root.setTerm("kitty", "confirmClose", Number(root.kitty.confirmClose || 0) !== 0 ? 0 : 1)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Scrollback History"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                RowLayout {
                    spacing: 5

                    Repeater {
                        model: [2000, 10000, 25000, 50000]

                        delegate: Rectangle {
                            id: kScrPill
                            required property int modelData
                            readonly property bool selected: Number(root.kitty.scrollback || 0) === kScrPill.modelData

                            implicitHeight: 24
                            implicitWidth: kScrTxt.implicitWidth + 12
                            radius: Theme.r(7)
                            color: kScrPill.selected
                                ? Theme.withAlpha(Theme.secondary, 0.22)
                                : (kScrMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: kScrPill.selected ? 1 : Theme.cardBorderWidth
                            border.color: kScrPill.selected ? Theme.secondary : Theme.cardBorder

                            Text {
                                id: kScrTxt
                                anchors.centerIn: parent
                                text: (kScrPill.modelData / 1000) + "k"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: kScrPill.selected ? Font.Bold : Font.Medium
                                color: kScrPill.selected ? Theme.secondary : Theme.fgSurface
                            }

                            MouseArea {
                                id: kScrMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setTerm("kitty", "scrollback", kScrPill.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
