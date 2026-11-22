pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property string kbLayout: "us,ara"
    property int repeatRate: 30
    property int repeatDelay: 450
    property int cursorSize: 24
    property bool mouseNaturalScroll: false
    property bool tapToClick: true
    property bool trackpadNaturalScroll: false
    property bool disableWhileTyping: true
    property bool disableTrackpad: false

    function loadSettings(): void {
        if (!readProc.running)
            readProc.running = true;
    }

    function setSetting(key: string, val: var): void {
        if (key === "xkb_rules_layout")
            root.kbLayout = String(val);
        else if (key === "repeat_rate")
            root.repeatRate = Number(val);
        else if (key === "repeat_delay")
            root.repeatDelay = Number(val);
        else if (key === "cursor_size")
            root.cursorSize = Number(val);
        else if (key === "mouse_natural_scrolling")
            root.mouseNaturalScroll = !!val;
        else if (key === "tap_to_click")
            root.tapToClick = !!val;
        else if (key === "trackpad_natural_scrolling")
            root.trackpadNaturalScroll = !!val;
        else if (key === "trackpad_disable_while_typing")
            root.disableWhileTyping = !!val;
        else if (key === "disable_trackpad")
            root.disableTrackpad = !!val;

        const outVal = (typeof val === "boolean") ? (val ? "1" : "0") : String(val);
        Quickshell.execDetached([Quickshell.shellPath("scripts/apply-local-setting.sh"), "set", key, outVal]);
    }

    Component.onCompleted: loadSettings()

    Process {
        id: readProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (typeof d.xkb_rules_layout === "string") {
                        root.kbLayout = d.xkb_rules_layout;
                        layoutInput.text = d.xkb_rules_layout;
                    }
                    if (typeof d.repeat_rate === "number")
                        root.repeatRate = d.repeat_rate;
                    if (typeof d.repeat_delay === "number")
                        root.repeatDelay = d.repeat_delay;
                    if (typeof d.cursor_size === "number")
                        root.cursorSize = d.cursor_size;
                    if (typeof d.mouse_natural_scrolling === "boolean")
                        root.mouseNaturalScroll = d.mouse_natural_scrolling;
                    if (typeof d.tap_to_click === "boolean")
                        root.tapToClick = d.tap_to_click;
                    if (typeof d.trackpad_natural_scrolling === "boolean")
                        root.trackpadNaturalScroll = d.trackpad_natural_scrolling;
                    if (typeof d.trackpad_disable_while_typing === "boolean")
                        root.disableWhileTyping = d.trackpad_disable_while_typing;
                    if (typeof d.disable_trackpad === "boolean")
                        root.disableTrackpad = d.disable_trackpad;
                } catch (err) {}
            }
        }
    }

    // --- 1. Keyboard Settings ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: kbCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: kbCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "KEYBOARD (PER-DEVICE LOCAL.CONF)"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            // Preset Layouts
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: ["us", "us,ara", "us,de", "us,fr", "us,es"]

                    delegate: Rectangle {
                        id: layChip
                        required property string modelData
                        readonly property bool selected: root.kbLayout === layChip.modelData

                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: layChip.selected
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (layMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: layChip.selected ? 1 : Theme.cardBorderWidth
                        border.color: layChip.selected ? Theme.primary : Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: layChip.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: layChip.selected ? Font.Bold : Font.Medium
                            color: layChip.selected ? Theme.primary : Theme.fgSurface
                        }

                        MouseArea {
                            id: layMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                layoutInput.text = layChip.modelData;
                                root.setSetting("xkb_rules_layout", layChip.modelData);
                            }
                        }
                    }
                }
            }

            // Custom Layout Input
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: layoutInput.activeFocus ? Theme.primary : Theme.cardBorder

                    TextInput {
                        id: layoutInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        text: root.kbLayout
                        color: Theme.fgSurface
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        clip: true
                        Keys.onReturnPressed: root.setSetting("xkb_rules_layout", text)
                        Keys.onEnterPressed: root.setSetting("xkb_rules_layout", text)
                    }
                }

                Rectangle {
                    implicitWidth: 72
                    implicitHeight: 30
                    radius: Theme.r(8)
                    color: applyLayMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                    Text {
                        anchors.centerIn: parent
                        text: "Apply"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        id: applyLayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setSetting("xkb_rules_layout", layoutInput.text)
                    }
                }
            }

            // Repeat Rate
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.preferredWidth: 115
                    text: "Repeat Rate"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [20, 30, 40, 50]

                    delegate: Rectangle {
                        id: rateBtn
                        required property int modelData
                        readonly property bool selected: root.repeatRate === rateBtn.modelData

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: rateBtn.selected
                            ? Theme.withAlpha(Theme.secondary, 0.22)
                            : (rateMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: rateBtn.selected ? 1 : Theme.cardBorderWidth
                        border.color: rateBtn.selected ? Theme.secondary : Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: rateBtn.modelData + "/s"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: rateBtn.selected ? Font.Bold : Font.Normal
                            color: rateBtn.selected ? Theme.secondary : Theme.fgSurface
                        }

                        MouseArea {
                            id: rateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSetting("repeat_rate", rateBtn.modelData)
                        }
                    }
                }
            }

            // Repeat Delay
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.preferredWidth: 115
                    text: "Repeat Delay"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [250, 350, 450, 600]

                    delegate: Rectangle {
                        id: delayBtn
                        required property int modelData
                        readonly property bool selected: root.repeatDelay === delayBtn.modelData

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: delayBtn.selected
                            ? Theme.withAlpha(Theme.secondary, 0.22)
                            : (delayMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: delayBtn.selected ? 1 : Theme.cardBorderWidth
                        border.color: delayBtn.selected ? Theme.secondary : Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: delayBtn.modelData + "ms"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: delayBtn.selected ? Font.Bold : Font.Normal
                            color: delayBtn.selected ? Theme.secondary : Theme.fgSurface
                        }

                        MouseArea {
                            id: delayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSetting("repeat_delay", delayBtn.modelData)
                        }
                    }
                }
            }
        }
    }

    // --- 2. Mouse & Cursor Settings ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: mouseCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: mouseCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "POINTER & CURSOR"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Mouse Natural Scrolling"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitWidth: 56
                    implicitHeight: 24
                    radius: Theme.r(8)
                    color: root.mouseNaturalScroll ? Theme.withAlpha(Theme.primary, 0.24) : Theme.subCardBg
                    border.width: root.mouseNaturalScroll ? 1 : Theme.cardBorderWidth
                    border.color: root.mouseNaturalScroll ? Theme.primary : Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: root.mouseNaturalScroll ? "ON" : "OFF"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: root.mouseNaturalScroll ? Theme.primary : Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setSetting("mouse_natural_scrolling", !root.mouseNaturalScroll)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.preferredWidth: 115
                    text: "Cursor Size"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [20, 24, 28, 32]

                    delegate: Rectangle {
                        id: curBtn
                        required property int modelData
                        readonly property bool selected: root.cursorSize === curBtn.modelData

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: curBtn.selected
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (curMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: curBtn.selected ? 1 : Theme.cardBorderWidth
                        border.color: curBtn.selected ? Theme.primary : Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: curBtn.modelData + "px"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: curBtn.selected ? Font.Bold : Font.Normal
                            color: curBtn.selected ? Theme.primary : Theme.fgSurface
                        }

                        MouseArea {
                            id: curMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSetting("cursor_size", curBtn.modelData)
                        }
                    }
                }
            }
        }
    }

    // --- 3. Trackpad Settings (shown only on laptops/touchpad devices) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: tpCol.implicitHeight + 24
        visible: DeviceCaps.hasTouchpad
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: tpCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "TOUCHPAD"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: [
                    { key: "tap_to_click",                  label: "Tap to Click",          val: root.tapToClick },
                    { key: "trackpad_natural_scrolling",    label: "Natural Scrolling",     val: root.trackpadNaturalScroll },
                    { key: "trackpad_disable_while_typing", label: "Disable While Typing",  val: root.disableWhileTyping },
                    { key: "disable_trackpad",              label: "Disable Touchpad",      val: root.disableTrackpad }
                ]

                delegate: RowLayout {
                    id: tpRow
                    required property var modelData
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: tpRow.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurface
                    }

                    Rectangle {
                        implicitWidth: 56
                        implicitHeight: 24
                        radius: Theme.r(8)
                        color: tpRow.modelData.val ? Theme.withAlpha(Theme.primary, 0.24) : Theme.subCardBg
                        border.width: tpRow.modelData.val ? 1 : Theme.cardBorderWidth
                        border.color: tpRow.modelData.val ? Theme.primary : Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: tpRow.modelData.val ? "ON" : "OFF"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: tpRow.modelData.val ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSetting(tpRow.modelData.key, !tpRow.modelData.val)
                        }
                    }
                }
            }
        }
    }
}
