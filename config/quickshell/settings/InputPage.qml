pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property string kbLayout: "us"
    property string kbOptions: "grp:alt_shift_toggle"
    property string kbModel: "pc105"
    property bool numlockOn: false
    property int repeatRate: 30
    property int repeatDelay: 450

    property int mouseAccelProfile: 2
    property real mouseAccelSpeed: 0.0
    property bool mouseNaturalScroll: false
    property bool mouseLeftHanded: false
    property bool mouseMiddleEmu: false
    property real axisScrollFactor: 1.0
    property int mouseScrollMethod: 0

    property bool tapToClick: true
    property bool trackpadNaturalScroll: false
    property bool disableWhileTyping: true
    property bool disableTrackpad: false
    property int trackpadAccelProfile: 2
    property real trackpadAccelSpeed: 0.0
    property bool trackpadLeftHanded: false
    property bool trackpadMiddleEmu: false
    property real trackpadScrollFactor: 1.0
    property int trackpadClickMethod: 2
    property int trackpadScrollMethod: 1
    property bool tapAndDrag: true
    property bool dragLock: false
    property int swipeMinThreshold: 1

    property var i2cFix: ({
        ok: false,
        driverPresent: false,
        devices: ["i2c_designware.0"],
        selectedDevice: "i2c_designware.0",
        initSystem: "unknown",
        scriptInstalled: false,
        serviceInstalled: false,
        serviceEnabled: false,
        dmiVendor: "",
        dmiProduct: "",
        isMsi: false
    })
    property bool i2cBusy: false
    property string i2cMsg: ""
    property string i2cErr: ""
    property string selectedI2cDev: "i2c_designware.0"

    function loadI2cFix(): void {
        if (!i2cStatusProc.running)
            i2cStatusProc.running = true;
    }

    function runI2cAction(args: var): void {
        if (root.i2cBusy || i2cActionProc.running)
            return;
        root.i2cBusy = true;
        root.i2cMsg = "";
        root.i2cErr = "";
        i2cActionProc.command = [Quickshell.shellPath("scripts/msi-touchpad-fix.sh")].concat(args);
        i2cActionProc.running = true;
    }

    function loadSettings(): void {
        if (!readProc.running)
            readProc.running = true;
    }

    function setSetting(key: string, val: var): void {
        if (key === "xkb_rules_layout") root.kbLayout = String(val);
        else if (key === "xkb_rules_options") root.kbOptions = String(val);
        else if (key === "xkb_rules_model") root.kbModel = String(val);
        else if (key === "numlock_on") root.numlockOn = !!val;
        else if (key === "repeat_rate") root.repeatRate = Number(val);
        else if (key === "repeat_delay") root.repeatDelay = Number(val);
        else if (key === "mouse_accel_profile") root.mouseAccelProfile = Number(val);
        else if (key === "mouse_accel_speed") root.mouseAccelSpeed = Number(val);
        else if (key === "mouse_natural_scrolling") root.mouseNaturalScroll = !!val;
        else if (key === "mouse_left_handed") root.mouseLeftHanded = !!val;
        else if (key === "mouse_middle_button_emulation") root.mouseMiddleEmu = !!val;
        else if (key === "axis_scroll_factor") root.axisScrollFactor = Number(val);
        else if (key === "mouse_scroll_method") root.mouseScrollMethod = Number(val);
        else if (key === "tap_to_click") root.tapToClick = !!val;
        else if (key === "trackpad_natural_scrolling") root.trackpadNaturalScroll = !!val;
        else if (key === "trackpad_disable_while_typing") root.disableWhileTyping = !!val;
        else if (key === "disable_trackpad") root.disableTrackpad = !!val;
        else if (key === "trackpad_accel_profile") root.trackpadAccelProfile = Number(val);
        else if (key === "trackpad_accel_speed") root.trackpadAccelSpeed = Number(val);
        else if (key === "trackpad_left_handed") root.trackpadLeftHanded = !!val;
        else if (key === "trackpad_middle_button_emulation") root.trackpadMiddleEmu = !!val;
        else if (key === "trackpad_scroll_factor") root.trackpadScrollFactor = Number(val);
        else if (key === "trackpad_click_method") root.trackpadClickMethod = Number(val);
        else if (key === "trackpad_scroll_method") root.trackpadScrollMethod = Number(val);
        else if (key === "tap_and_drag") root.tapAndDrag = !!val;
        else if (key === "drag_lock") root.dragLock = !!val;
        else if (key === "swipe_min_threshold") root.swipeMinThreshold = Number(val);

        const outVal = (typeof val === "boolean") ? (val ? "1" : "0") : String(val);
        Quickshell.execDetached([Quickshell.shellPath("scripts/apply-local-setting.sh"), "set", key, outVal]);
    }

    Component.onCompleted: {
        loadSettings();
        loadI2cFix();
    }

    Process {
        id: i2cStatusProc
        command: [Quickshell.shellPath("scripts/msi-touchpad-fix.sh"), "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.i2cFix = d;
                        if (typeof d.selectedDevice === "string" && d.selectedDevice.length > 0)
                            root.selectedI2cDev = d.selectedDevice;
                    }
                } catch (err) {}
            }
        }
    }

    Process {
        id: i2cActionProc
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.i2cFix = d;
                        if (typeof d.selectedDevice === "string" && d.selectedDevice.length > 0)
                            root.selectedI2cDev = d.selectedDevice;
                        root.i2cMsg = String(d.message || "Touchpad I2C fix updated");
                        root.i2cErr = "";
                        DeviceCaps.refresh();
                    } else if (d && d.error) {
                        root.i2cErr = String(d.error);
                        root.i2cMsg = "";
                    }
                } catch (err) {
                    root.i2cErr = "Unable to parse MSI touchpad fix output";
                }
            }
        }
        onExited: code => {
            root.i2cBusy = false;
            if (code !== 0 && root.i2cErr.length === 0)
                root.i2cErr = "MSI touchpad fix exited with code " + code;
        }
    }

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
                    if (typeof d.xkb_rules_options === "string")
                        root.kbOptions = d.xkb_rules_options;
                    if (typeof d.numlock_on === "boolean")
                        root.numlockOn = d.numlock_on;
                    if (typeof d.repeat_rate === "number")
                        root.repeatRate = d.repeat_rate;
                    if (typeof d.repeat_delay === "number")
                        root.repeatDelay = d.repeat_delay;
                    if (typeof d.mouse_accel_profile === "number")
                        root.mouseAccelProfile = d.mouse_accel_profile;
                    if (typeof d.mouse_accel_speed === "number")
                        root.mouseAccelSpeed = d.mouse_accel_speed;
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
                    if (typeof d.trackpad_accel_profile === "number")
                        root.trackpadAccelProfile = d.trackpad_accel_profile;
                    if (typeof d.trackpad_accel_speed === "number")
                        root.trackpadAccelSpeed = d.trackpad_accel_speed;
                    if (typeof d.xkb_rules_model === "string") root.kbModel = d.xkb_rules_model;
                    if (typeof d.mouse_left_handed === "boolean") root.mouseLeftHanded = d.mouse_left_handed;
                    if (typeof d.mouse_middle_button_emulation === "boolean") root.mouseMiddleEmu = d.mouse_middle_button_emulation;
                    if (typeof d.axis_scroll_factor === "number") root.axisScrollFactor = d.axis_scroll_factor;
                    if (typeof d.mouse_scroll_method === "number") root.mouseScrollMethod = d.mouse_scroll_method;
                    if (typeof d.trackpad_left_handed === "boolean") root.trackpadLeftHanded = d.trackpad_left_handed;
                    if (typeof d.trackpad_middle_button_emulation === "boolean") root.trackpadMiddleEmu = d.trackpad_middle_button_emulation;
                    if (typeof d.trackpad_scroll_factor === "number") root.trackpadScrollFactor = d.trackpad_scroll_factor;
                    if (typeof d.trackpad_click_method === "number") root.trackpadClickMethod = d.trackpad_click_method;
                    if (typeof d.trackpad_scroll_method === "number") root.trackpadScrollMethod = d.trackpad_scroll_method;
                    if (typeof d.tap_and_drag === "boolean") root.tapAndDrag = d.tap_and_drag;
                    if (typeof d.drag_lock === "boolean") root.dragLock = d.drag_lock;
                    if (typeof d.swipe_min_threshold === "number") root.swipeMinThreshold = d.swipe_min_threshold;
                } catch (err) {}
            }
        }
    }

    // --- 0. MSI Laptop Touchpad I2C Recovery ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: i2cCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: i2cCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.withAlpha(Theme.secondary, 0.16)

                    Text {
                        anchors.centerIn: parent
                        text: "󰟸"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(14)
                        color: Theme.secondary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "MSI touchpad I2C fix"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Unbinds and rebinds i2c_designware at runtime or boot (systemd / OpenRC)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: i2cBadgeTxt.implicitWidth + 14
                    radius: Theme.r(11)
                    color: (root.i2cFix.serviceInstalled && root.i2cFix.serviceEnabled)
                        ? Theme.withAlpha(Theme.success, 0.18)
                        : ((root.i2cFix.scriptInstalled || root.i2cFix.serviceInstalled)
                            ? Theme.withAlpha(Theme.warning, 0.18)
                            : Theme.subCardBg)

                    Text {
                        id: i2cBadgeTxt
                        anchors.centerIn: parent
                        text: (root.i2cFix.serviceInstalled && root.i2cFix.serviceEnabled)
                            ? "Boot fix active"
                            : ((root.i2cFix.scriptInstalled || root.i2cFix.serviceInstalled) ? "Installed" : "Not installed")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.Bold
                        color: (root.i2cFix.serviceInstalled && root.i2cFix.serviceEnabled)
                            ? Theme.success
                            : ((root.i2cFix.scriptInstalled || root.i2cFix.serviceInstalled) ? Theme.warning : Theme.fgSurfaceVariant)
                    }
                }
            }

            // Device Selector Chips
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 115
                    text: "I2C Device"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.i2cFix.devices || ["i2c_designware.0"]

                        delegate: Rectangle {
                            id: i2cDevChip
                            required property string modelData
                            readonly property bool selected: root.selectedI2cDev === i2cDevChip.modelData

                            implicitHeight: 24
                            implicitWidth: i2cDevLbl.implicitWidth + 14
                            radius: Theme.r(7)
                            color: i2cDevChip.selected
                                ? Theme.primary
                                : (i2cDevMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: i2cDevChip.selected ? Theme.activeControlBorderWidth : 0
                            border.color: Theme.primary

                            Text {
                                id: i2cDevLbl
                                anchors.centerIn: parent
                                text: i2cDevChip.modelData
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(10)
                                font.weight: i2cDevChip.selected ? Font.Bold : Font.Normal
                                color: i2cDevChip.selected ? Theme.fgPrimary : Theme.fgSurface
                            }

                            MouseArea {
                                id: i2cDevMouse
                                anchors.fill: parent
                                enabled: !root.i2cBusy
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.selectedI2cDev = i2cDevChip.modelData
                            }
                        }
                    }
                }
            }

            // Hardware / Driver Info Strip
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: i2cInfoCol.implicitHeight + 12
                radius: Theme.r(9)
                color: Theme.subCardBg

                ColumnLayout {
                    id: i2cInfoCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Driver: " + (root.i2cFix.driverPresent ? "i2c_designware present" : "not detected")
                            + " · Init: " + String(root.i2cFix.initSystem || "unknown")
                            + " · Touchpad: " + (DeviceCaps.hasTouchpad ? "detected" : "not detected")
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        color: Theme.fgSurfaceVariant
                    }

                    Text {
                        visible: String(root.i2cFix.dmiVendor || "").length > 0 || String(root.i2cFix.dmiProduct || "").length > 0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Hardware: " + [String(root.i2cFix.dmiVendor || ""), String(root.i2cFix.dmiProduct || "")].filter(s => s.length > 0).join(" · ")
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        color: root.i2cFix.isMsi ? Theme.secondary : Theme.fgSurfaceVariant
                    }
                }
            }

            // Action Buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: i2cRstMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    opacity: root.i2cBusy ? 0.55 : 1.0

                    Text {
                        anchors.centerIn: parent
                        text: root.i2cBusy ? "Working..." : "Restart I2C Now"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: i2cRstMouse
                        anchors.fill: parent
                        enabled: !root.i2cBusy
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.runI2cAction(["restart", root.selectedI2cDev])
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: i2cInstMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                    opacity: root.i2cBusy ? 0.55 : 1.0

                    Text {
                        anchors.centerIn: parent
                        text: root.i2cFix.serviceInstalled ? "Reinstall Boot Fix" : "Install Boot Fix"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        id: i2cInstMouse
                        anchors.fill: parent
                        enabled: !root.i2cBusy
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.runI2cAction(["install", root.selectedI2cDev])
                    }
                }

                Rectangle {
                    visible: !!root.i2cFix.scriptInstalled || !!root.i2cFix.serviceInstalled
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: i2cRmMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.subCardBg
                    opacity: root.i2cBusy ? 0.55 : 1.0

                    Text {
                        anchors.centerIn: parent
                        text: "Remove Boot Fix"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.error
                    }

                    MouseArea {
                        id: i2cRmMouse
                        anchors.fill: parent
                        enabled: !root.i2cBusy
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.runI2cAction(["uninstall"])
                    }
                }
            }

            Text {
                visible: root.i2cMsg.length > 0 || root.i2cErr.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.i2cErr.length > 0 ? root.i2cErr : root.i2cMsg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: root.i2cErr.length > 0 ? Theme.error : Theme.success
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
                text: "Keyboard (per-device local.conf)"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
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
                            ? Theme.primary
                            : (layMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: layChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: layMouse.pressed ? 0.95 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: layChip.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: layChip.selected ? Font.Bold : Font.Medium
                            color: layChip.selected ? Theme.fgPrimary : Theme.fgSurface
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
                    border.width: layoutInput.activeFocus ? 1 : Theme.subBorderWidth
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
                        font.pixelSize: Theme.fs(11)
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
                    scale: applyLayMouse.pressed ? 0.95 : 1.0

                    Behavior on color {
                        enabled: !Theme.isSimple
                        ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "Apply"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
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

            // XKB Switch Shortcut
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 115
                    text: "Switch Shortcut"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { label: "Alt+Shift", val: "grp:alt_shift_toggle" },
                        { label: "Win+Space", val: "grp:win_space_toggle" },
                        { label: "Caps Lock", val: "grp:caps_toggle" },
                        { label: "Caps to Esc",  val: "caps:escape" }
                    ]

                    delegate: Rectangle {
                        id: optBtn
                        required property var modelData
                        readonly property bool selected: root.kbOptions === optBtn.modelData.val

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: optBtn.selected
                            ? Theme.primary
                            : (optMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: optBtn.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: optMouse.pressed ? 0.95 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: optBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: optBtn.selected ? Font.Bold : Font.Normal
                            color: optBtn.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: optMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSetting("xkb_rules_options", optBtn.modelData.val)
                        }
                    }
                }
            }

            // Repeat Rate
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 115
                    text: "Repeat Rate"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
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
                            ? Theme.secondary
                            : (rateMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: rateBtn.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.secondary
                        scale: rateMouse.pressed ? 0.95 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: rateBtn.modelData + "/s"
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: rateBtn.selected ? Font.Bold : Font.Normal
                            color: rateBtn.selected ? Theme.contrastInk(Theme.secondary) : Theme.fgSurface
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
                spacing: 6

                Text {
                    Layout.preferredWidth: 115
                    text: "Repeat Delay"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
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
                            ? Theme.secondary
                            : (delayMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: delayBtn.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.secondary
                        scale: delayMouse.pressed ? 0.95 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: delayBtn.modelData + "ms"
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: delayBtn.selected ? Font.Bold : Font.Normal
                            color: delayBtn.selected ? Theme.contrastInk(Theme.secondary) : Theme.fgSurface
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

            // NumLock on Startup
            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Enable NumLock on Startup"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.numlockOn
                    onToggled: root.setSetting("numlock_on", !root.numlockOn)
                }
            }

            // Keyboard Model
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 115
                    text: "Keyboard Model"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: ["pc104", "pc105", "macbook79"]

                    delegate: Rectangle {
                        id: modChip
                        required property string modelData
                        readonly property bool selected: root.kbModel === modChip.modelData

                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: modChip.selected ? Theme.primary : Theme.subCardBg
                        border.width: modChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: modChip.modelData
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: modChip.selected ? Font.Bold : Font.Normal
                            color: modChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSetting("xkb_rules_model", modChip.modelData)
                        }
                    }
                }
            }

            // Live Key Repeat & Layout Test Box
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Theme.r(8)
                color: Theme.subCardBg
                border.width: kbTestIn.activeFocus ? 1 : Theme.subBorderWidth
                border.color: kbTestIn.activeFocus ? Theme.primary : Theme.cardBorder

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Type here to test key repeat rate, delay & layout switching..."
                        visible: kbTestIn.text.length === 0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }

                    TextInput {
                        id: kbTestIn
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                        clip: true
                    }
                }
            }
        }
    }

    // --- 2. Mouse & Pointer Settings ---
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

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Mouse & pointer"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Cursor theme & size in Appearance"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(9)
                    color: Theme.fgSurfaceVariant
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 115
                    text: "Accel Profile"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { label: "Flat (Raw)", val: 1 },
                        { label: "Adaptive",   val: 2 }
                    ]

                    delegate: Rectangle {
                        id: mProfBtn
                        required property var modelData
                        readonly property bool selected: root.mouseAccelProfile === mProfBtn.modelData.val

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: mProfBtn.selected
                            ? Theme.primary
                            : (mProfMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: mProfBtn.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: mProfMouse.pressed ? 0.96 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: mProfBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: mProfBtn.selected ? Font.Bold : Font.Normal
                            color: mProfBtn.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: mProfMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSetting("mouse_accel_profile", mProfBtn.modelData.val)
                        }
                    }
                }
            }

            StepControl {
                label: "Mouse Pointer Speed"
                displayValue: (root.mouseAccelSpeed >= 0 ? "+" : "") + root.mouseAccelSpeed.toFixed(1)
                onDecremented: root.setSetting("mouse_accel_speed", Number(Math.max(-1.0, root.mouseAccelSpeed - 0.1).toFixed(1)))
                onIncremented: root.setSetting("mouse_accel_speed", Number(Math.min(1.0, root.mouseAccelSpeed + 0.1).toFixed(1)))
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Mouse Natural Scrolling"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.mouseNaturalScroll
                    onToggled: root.setSetting("mouse_natural_scrolling", !root.mouseNaturalScroll)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Left-Handed Mouse Buttons"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch { checked: root.mouseLeftHanded; onToggled: root.setSetting("mouse_left_handed", !root.mouseLeftHanded) }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Middle-Button Emulation (Left + Right Click)"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch { checked: root.mouseMiddleEmu; onToggled: root.setSetting("mouse_middle_button_emulation", !root.mouseMiddleEmu) }
            }

            StepControl {
                label: "Mouse Wheel Scroll Factor"
                displayValue: root.axisScrollFactor.toFixed(1) + "x"
                onDecremented: root.setSetting("axis_scroll_factor", Number(Math.max(0.2, root.axisScrollFactor - 0.2).toFixed(1)))
                onIncremented: root.setSetting("axis_scroll_factor", Number(Math.min(4.0, root.axisScrollFactor + 0.2).toFixed(1)))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text { Layout.preferredWidth: 115; text: "Scroll Method"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }

                Repeater {
                    model: [
                        { label: "Wheel", val: 0 },
                        { label: "Button Drag", val: 3 }
                    ]

                    delegate: Rectangle {
                        id: mScrBtn
                        required property var modelData
                        readonly property bool selected: root.mouseScrollMethod === mScrBtn.modelData.val
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: mScrBtn.selected ? Theme.primary : Theme.subCardBg
                        border.width: mScrBtn.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        Text { anchors.centerIn: parent; text: mScrBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: mScrBtn.selected ? Font.Bold : Font.Normal; color: mScrBtn.selected ? Theme.fgPrimary : Theme.fgSurface }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("mouse_scroll_method", mScrBtn.modelData.val) }
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
            spacing: 9

            Text {
                text: "Touchpad"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
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
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }

                    ToggleSwitch {
                        checked: tpRow.modelData.val
                        onToggled: root.setSetting(tpRow.modelData.key, !tpRow.modelData.val)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 115
                    text: "Accel Profile"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { label: "Flat",     val: 1 },
                        { label: "Adaptive", val: 2 }
                    ]

                    delegate: Rectangle {
                        id: tpProfBtn
                        required property var modelData
                        readonly property bool selected: root.trackpadAccelProfile === tpProfBtn.modelData.val

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: tpProfBtn.selected
                            ? Theme.secondary
                            : (tpProfMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: tpProfBtn.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.secondary
                        scale: tpProfMouse.pressed ? 0.96 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: tpProfBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: tpProfBtn.selected ? Font.Bold : Font.Normal
                            color: tpProfBtn.selected ? Theme.contrastInk(Theme.secondary) : Theme.fgSurface
                        }

                        MouseArea {
                            id: tpProfMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSetting("trackpad_accel_profile", tpProfBtn.modelData.val)
                        }
                    }
                }
            }

            StepControl {
                label: "Touchpad Speed"
                displayValue: (root.trackpadAccelSpeed >= 0 ? "+" : "") + root.trackpadAccelSpeed.toFixed(1)
                accentColor: Theme.secondary
                onDecremented: root.setSetting("trackpad_accel_speed", Number(Math.max(-1.0, root.trackpadAccelSpeed - 0.1).toFixed(1)))
                onIncremented: root.setSetting("trackpad_accel_speed", Number(Math.min(1.0, root.trackpadAccelSpeed + 0.1).toFixed(1)))
            }

            Repeater {
                model: [
                    { key: "tap_and_drag",                      label: "Tap and Drag",              val: root.tapAndDrag },
                    { key: "drag_lock",                         label: "Drag Lock",                 val: root.dragLock },
                    { key: "trackpad_left_handed",              label: "Left-Handed Touchpad",      val: root.trackpadLeftHanded },
                    { key: "trackpad_middle_button_emulation",  label: "Emulate Middle Click",      val: root.trackpadMiddleEmu }
                ]

                delegate: RowLayout {
                    id: tpExtRow
                    required property var modelData
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: tpExtRow.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                    ToggleSwitch { checked: tpExtRow.modelData.val; activeColor: Theme.secondary; onToggled: root.setSetting(tpExtRow.modelData.key, !tpExtRow.modelData.val) }
                }
            }

            StepControl {
                label: "Touchpad Scroll Speed"
                displayValue: root.trackpadScrollFactor.toFixed(1) + "x"
                accentColor: Theme.secondary
                onDecremented: root.setSetting("trackpad_scroll_factor", Number(Math.max(0.2, root.trackpadScrollFactor - 0.2).toFixed(1)))
                onIncremented: root.setSetting("trackpad_scroll_factor", Number(Math.min(4.0, root.trackpadScrollFactor + 0.2).toFixed(1)))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { Layout.preferredWidth: 115; text: "Click Method"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                Repeater {
                    model: [{ label: "Button Areas", val: 1 }, { label: "Clickfinger", val: 2 }]
                    delegate: Rectangle {
                        id: tpClkBtn
                        required property var modelData
                        readonly property bool selected: root.trackpadClickMethod === tpClkBtn.modelData.val
                        Layout.fillWidth: true; implicitHeight: 24; radius: Theme.r(7)
                        color: tpClkBtn.selected ? Theme.secondary : Theme.subCardBg
                        border.width: tpClkBtn.selected ? Theme.activeControlBorderWidth : 0; border.color: Theme.secondary
                        Text { anchors.centerIn: parent; text: tpClkBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: tpClkBtn.selected ? Font.Bold : Font.Normal; color: tpClkBtn.selected ? Theme.contrastInk(Theme.secondary) : Theme.fgSurface }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("trackpad_click_method", tpClkBtn.modelData.val) }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { Layout.preferredWidth: 115; text: "Scroll Gesture"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                Repeater {
                    model: [{ label: "Two-Finger", val: 1 }, { label: "Edge", val: 2 }]
                    delegate: Rectangle {
                        id: tpScrBtn
                        required property var modelData
                        readonly property bool selected: root.trackpadScrollMethod === tpScrBtn.modelData.val
                        Layout.fillWidth: true; implicitHeight: 24; radius: Theme.r(7)
                        color: tpScrBtn.selected ? Theme.secondary : Theme.subCardBg
                        border.width: tpScrBtn.selected ? Theme.activeControlBorderWidth : 0; border.color: Theme.secondary
                        Text { anchors.centerIn: parent; text: tpScrBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: tpScrBtn.selected ? Font.Bold : Font.Normal; color: tpScrBtn.selected ? Theme.contrastInk(Theme.secondary) : Theme.fgSurface }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("trackpad_scroll_method", tpScrBtn.modelData.val) }
                    }
                }
            }

            StepControl {
                label: "Swipe Threshold"
                displayValue: String(root.swipeMinThreshold)
                accentColor: Theme.secondary
                onDecremented: root.setSetting("swipe_min_threshold", Math.max(1, root.swipeMinThreshold - 1))
                onIncremented: root.setSetting("swipe_min_threshold", Math.min(10, root.swipeMinThreshold + 1))
            }
        }
    }
}
