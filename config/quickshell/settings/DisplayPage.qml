pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property var outputs: []
    property var selectedModeByOutput: ({})
    property var selectedScaleByOutput: ({})
    property var selectedTransformByOutput: ({})
    property var selectedVrrByOutput: ({})
    property var selectedPosByOutput: ({})
    property int brightnessPct: 80
    property string statusMsg: ""

    readonly property int enabledCount: {
        let c = 0;
        for (let i = 0; i < root.outputs.length; i++) {
            if (root.outputs[i].enabled)
                c++;
        }
        return c;
    }

    readonly property var rotationOptions: [
        { label: "0° Normal",  wlr: "normal", rr: 0 },
        { label: "90° Right",  wlr: "90",     rr: 1 },
        { label: "180° Flip",  wlr: "180",    rr: 2 },
        { label: "270° Left",  wlr: "270",    rr: 3 }
    ]

    function rrForTransform(tr: string): int {
        if (tr === "90") return 1;
        if (tr === "180") return 2;
        if (tr === "270") return 3;
        return 0;
    }

    function refresh(): void {
        if (!randrProc.running)
            randrProc.running = true;
        if ((DeviceCaps.hasBacklight || DeviceCaps.hasDdcutil) && !brightReadProc.running)
            brightReadProc.running = true;
    }

    function otherOutputFor(outName: string): string {
        for (let i = 0; i < root.outputs.length; i++) {
            if (root.outputs[i].name !== outName)
                return root.outputs[i].name;
        }
        return "";
    }

    function setSelectedMode(outName: string, modeObj: var): void {
        const next = Object.assign({}, root.selectedModeByOutput);
        next[outName] = modeObj;
        root.selectedModeByOutput = next;
    }

    function setSelectedScale(outName: string, scaleVal: real): void {
        const next = Object.assign({}, root.selectedScaleByOutput);
        next[outName] = scaleVal;
        root.selectedScaleByOutput = next;
    }

    function setSelectedTransform(outName: string, trVal: string): void {
        const next = Object.assign({}, root.selectedTransformByOutput);
        next[outName] = trVal;
        root.selectedTransformByOutput = next;
    }

    function setSelectedVrr(outName: string, enabled: bool): void {
        const next = Object.assign({}, root.selectedVrrByOutput);
        next[outName] = !!enabled;
        root.selectedVrrByOutput = next;
    }

    function setSelectedPos(outName: string, posVal: string): void {
        const next = Object.assign({}, root.selectedPosByOutput);
        next[outName] = posVal;
        root.selectedPosByOutput = next;
    }

    function toggleOutputEnabled(outName: string, currentlyEnabled: bool): void {
        if (currentlyEnabled && root.enabledCount <= 1) {
            root.statusMsg = "Cannot disable the only active display";
            return;
        }
        root.statusMsg = (currentlyEnabled ? "Disabling " : "Enabling ") + outName + "...";
        applyProc.command = ["wlr-randr", "--output", outName, currentlyEnabled ? "--off" : "--on"];
        applyProc.running = true;
    }

    function setBrightness(pct: int): void {
        const clamped = Math.max(5, Math.min(100, pct));
        root.brightnessPct = clamped;
        if (DeviceCaps.hasBacklight)
            Quickshell.execDetached(["brightnessctl", "set", clamped + "%"]);
        else if (DeviceCaps.hasDdcutil)
            Quickshell.execDetached(["ddcutil", "setvcp", "10", String(clamped)]);
    }

    function applyLive(outName: string): void {
        const m = root.selectedModeByOutput[outName];
        const s = root.selectedScaleByOutput[outName] || 1.0;
        const tr = root.selectedTransformByOutput[outName] || "normal";
        const vrr = !!root.selectedVrrByOutput[outName];
        const pos = root.selectedPosByOutput[outName] || "auto";
        const other = root.otherOutputFor(outName);
        if (!m)
            return;
        const modeArg = m.width + "x" + m.height + "@" + m.refreshStr + "Hz";
        root.statusMsg = "Applying " + outName + " (" + modeArg + " @ " + s + "x, " + tr + ")...";
        const cmd = [
            "wlr-randr", "--output", outName,
            "--mode", modeArg,
            "--scale", String(s),
            "--transform", tr,
            "--adaptive-sync", vrr ? "enabled" : "disabled"
        ];
        if (pos !== "auto" && other.length > 0) {
            cmd.push("--" + pos);
            cmd.push(other);
        }
        applyProc.command = cmd;
        applyProc.running = true;
    }

    function savePersistent(outName: string): void {
        const m = root.selectedModeByOutput[outName];
        const s = root.selectedScaleByOutput[outName] || 1.0;
        const tr = root.selectedTransformByOutput[outName] || "normal";
        const rr = root.rrForTransform(tr);
        const vrr = root.selectedVrrByOutput[outName] ? "1" : "0";
        if (!m)
            return;
        root.statusMsg = "Saved " + outName + " rule to ~/.config/mango/local.conf";
        applyProc.command = [
            Quickshell.shellPath("scripts/apply-local-setting.sh"),
            "set-monitor", outName,
            String(m.width), String(m.height), m.refreshStr, String(s),
            String(rr), vrr
        ];
        applyProc.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: randrProc
        command: ["wlr-randr", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const arr = JSON.parse(raw);
                    if (!Array.isArray(arr))
                        return;
                    const parsed = [];
                    const modeMap = {};
                    const scaleMap = {};
                    const transMap = {};
                    const vrrMap = {};

                    for (let i = 0; i < arr.length; i++) {
                        const o = arr[i];
                        const modes = [];
                        const seen = {};
                        let currentMode = null;

                        if (Array.isArray(o.modes)) {
                            for (let j = 0; j < o.modes.length; j++) {
                                const m = o.modes[j];
                                const hz = Number(m.refresh || 60).toFixed(2);
                                const key = m.width + "x" + m.height + "@" + hz;
                                if (seen[key] && !m.current && !m.preferred)
                                    continue;
                                seen[key] = true;
                                const entry = {
                                    key: key,
                                    width: m.width,
                                    height: m.height,
                                    refresh: Number(m.refresh || 60),
                                    refreshStr: Number(m.refresh || 60).toFixed(6),
                                    label: m.width + "×" + m.height + " @ " + Math.round(Number(m.refresh || 60)) + "Hz",
                                    preferred: !!m.preferred,
                                    current: !!m.current
                                };
                                modes.push(entry);
                                if (m.current && !currentMode)
                                    currentMode = entry;
                            }
                        }
                        if (!currentMode && modes.length > 0)
                            currentMode = modes[0];

                        const topModes = modes.slice(0, 9);
                        if (currentMode && topModes.indexOf(currentMode) === -1)
                            topModes.unshift(currentMode);

                        modeMap[o.name] = currentMode;
                        scaleMap[o.name] = Number(o.scale || 1.0);
                        transMap[o.name] = String(o.transform || "normal");
                        vrrMap[o.name] = !!o.adaptive_sync;

                        parsed.push({
                            name: o.name,
                            description: o.description || o.model || o.name,
                            enabled: !!o.enabled,
                            scale: Number(o.scale || 1.0),
                            transform: String(o.transform || "normal"),
                            adaptiveSync: !!o.adaptive_sync,
                            currentMode: currentMode,
                            modes: topModes
                        });
                    }
                    root.selectedModeByOutput = modeMap;
                    root.selectedScaleByOutput = scaleMap;
                    root.selectedTransformByOutput = transMap;
                    root.selectedVrrByOutput = vrrMap;
                    root.outputs = parsed;
                } catch (err) {}
            }
        }
    }

    Process {
        id: applyProc
        onExited: refreshDelay.restart()
    }

    Process {
        id: brightReadProc
        command: [
            "python3", "-c",
            "import re,shutil,subprocess\n" +
            "if shutil.which('brightnessctl'):\n" +
            "  out = subprocess.check_output(['brightnessctl','-m'], text=True, stderr=subprocess.DEVNULL)\n" +
            "  m = re.search(r',(\\d+)%,', out)\n" +
            "  if m: print(m.group(1))\n" +
            "elif shutil.which('ddcutil'):\n" +
            "  out = subprocess.check_output(['ddcutil','getvcp','10','--terse'], text=True, stderr=subprocess.DEVNULL)\n" +
            "  parts = out.strip().split()\n" +
            "  if len(parts) >= 4: print(parts[3])"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt((text || "").trim(), 10);
                if (!isNaN(v))
                    root.brightnessPct = Math.max(5, Math.min(100, v));
            }
        }
    }

    Timer {
        id: refreshDelay
        interval: 350
        repeat: false
        onTriggered: root.refresh()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: root.statusMsg
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(10)
            color: Theme.primary
        }

        Rectangle {
            implicitHeight: 28
            implicitWidth: refRow.implicitWidth + 16
            radius: Theme.r(10)
            color: refMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: refRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                    text: "󰑐"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(12)
                    color: Theme.primary
                }

                Text {
                    text: "Detect Outputs"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: refMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
            }
        }
    }

    Repeater {
        model: root.outputs

        delegate: Rectangle {
            id: outCard
            required property var modelData
            readonly property var activeMode: root.selectedModeByOutput[outCard.modelData.name] || outCard.modelData.currentMode
            readonly property real activeScale: root.selectedScaleByOutput[outCard.modelData.name] !== undefined
                ? root.selectedScaleByOutput[outCard.modelData.name]
                : outCard.modelData.scale
            readonly property string activeTransform: root.selectedTransformByOutput[outCard.modelData.name] !== undefined
                ? root.selectedTransformByOutput[outCard.modelData.name]
                : (outCard.modelData.transform || "normal")
            readonly property bool activeVrr: root.selectedVrrByOutput[outCard.modelData.name] !== undefined
                ? root.selectedVrrByOutput[outCard.modelData.name]
                : !!outCard.modelData.adaptiveSync

            Layout.fillWidth: true
            implicitHeight: outCol.implicitHeight + 24
            radius: Theme.r(16)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            ColumnLayout {
                id: outCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "󰍹"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(16)
                        color: Theme.primary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: outCard.modelData.name
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            text: outCard.modelData.description
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: stateTxt.implicitWidth + 14
                        radius: Theme.r(8)
                        color: stateMouse.containsMouse
                            ? Theme.hoverBg
                            : (outCard.modelData.enabled ? Theme.withAlpha(Theme.success, 0.20) : Theme.subCardBg)
                        border.width: Theme.cardBorderWidth
                        border.color: outCard.modelData.enabled ? Theme.withAlpha(Theme.success, 0.45) : Theme.cardBorder

                        Text {
                            id: stateTxt
                            anchors.centerIn: parent
                            text: outCard.modelData.enabled ? "ACTIVE" : "OFF"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.Bold
                            color: outCard.modelData.enabled ? Theme.success : Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: stateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleOutputEnabled(outCard.modelData.name, !!outCard.modelData.enabled)
                        }
                    }
                }

                Text {
                    text: "RESOLUTION & REFRESH RATE"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: outCard.modelData.modes

                        delegate: Rectangle {
                            id: modePill
                            required property var modelData
                            readonly property bool selected: outCard.activeMode && outCard.activeMode.key === modePill.modelData.key

                            implicitHeight: 26
                            implicitWidth: modeTxt.implicitWidth + 14
                            radius: Theme.r(8)
                            color: modePill.selected
                                ? Theme.withAlpha(Theme.primary, 0.22)
                                : (modePillMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: modePill.selected ? 1 : Theme.cardBorderWidth
                            border.color: modePill.selected ? Theme.primary : Theme.cardBorder
                            scale: modePillMouse.pressed ? 0.95 : 1.0

                            Behavior on color {
                                enabled: !Theme.isSimple
                                ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                            }
                            Behavior on scale {
                                enabled: !Theme.isSimple
                                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                            }

                            Text {
                                id: modeTxt
                                anchors.centerIn: parent
                                text: modePill.modelData.label + (modePill.modelData.preferred ? " ★" : "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: modePill.selected ? Font.Bold : Font.Normal
                                color: modePill.selected ? Theme.primary : Theme.fgSurface
                            }

                            MouseArea {
                                id: modePillMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setSelectedMode(outCard.modelData.name, modePill.modelData)
                            }
                        }
                    }
                }

                Text {
                    text: "DISPLAY SCALE"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [1.0, 1.25, 1.5, 1.75, 2.0]

                        delegate: Rectangle {
                            id: scalePill
                            required property real modelData
                            readonly property bool selected: Math.abs(outCard.activeScale - scalePill.modelData) < 0.05

                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: Theme.r(8)
                            color: scalePill.selected
                                ? Theme.withAlpha(Theme.secondary, 0.22)
                                : (scaleMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: scalePill.selected ? 1 : Theme.cardBorderWidth
                            border.color: scalePill.selected ? Theme.secondary : Theme.cardBorder
                            scale: scaleMouse.pressed ? 0.95 : 1.0

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
                                text: scalePill.modelData + "x"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: scalePill.selected ? Font.Bold : Font.Medium
                                color: scalePill.selected ? Theme.secondary : Theme.fgSurface
                            }

                            MouseArea {
                                id: scaleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setSelectedScale(outCard.modelData.name, scalePill.modelData)
                            }
                        }
                    }
                }

                // Orientation / Rotation
                Text {
                    text: "ORIENTATION & ROTATION"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.rotationOptions

                        delegate: Rectangle {
                            id: rotPill
                            required property var modelData
                            readonly property bool selected: outCard.activeTransform === rotPill.modelData.wlr

                            implicitHeight: 26
                            implicitWidth: rotTxt.implicitWidth + 16
                            radius: Theme.r(8)
                            color: rotPill.selected
                                ? Theme.withAlpha(Theme.primary, 0.22)
                                : (rotMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: rotPill.selected ? 1 : Theme.cardBorderWidth
                            border.color: rotPill.selected ? Theme.primary : Theme.cardBorder

                            Text {
                                id: rotTxt
                                anchors.centerIn: parent
                                text: rotPill.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: rotPill.selected ? Font.Bold : Font.Medium
                                color: rotPill.selected ? Theme.primary : Theme.fgSurface
                            }

                            MouseArea {
                                id: rotMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setSelectedTransform(outCard.modelData.name, rotPill.modelData.wlr)
                            }
                        }
                    }
                }

                // Multi-Monitor Relative Position (when > 1 display connected)
                ColumnLayout {
                    visible: root.outputs.length > 1
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "MULTI-MONITOR POSITION (" + (root.otherOutputFor(outCard.modelData.name) || "other") + ")"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.fgSurfaceVariant
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { id: "auto",     label: "Auto" },
                                { id: "left-of",  label: "Left of" },
                                { id: "right-of", label: "Right of" },
                                { id: "above",    label: "Above" },
                                { id: "below",    label: "Below" }
                            ]

                            delegate: Rectangle {
                                id: mPosPill
                                required property var modelData
                                readonly property string curPos: root.selectedPosByOutput[outCard.modelData.name] || "auto"
                                readonly property bool selected: mPosPill.curPos === mPosPill.modelData.id

                                implicitHeight: 24
                                implicitWidth: mPosTxt.implicitWidth + 14
                                radius: Theme.r(7)
                                color: mPosPill.selected ? Theme.withAlpha(Theme.secondary, 0.22) : Theme.subCardBg
                                border.width: mPosPill.selected ? 1 : Theme.cardBorderWidth
                                border.color: mPosPill.selected ? Theme.secondary : Theme.cardBorder

                                Text {
                                    id: mPosTxt
                                    anchors.centerIn: parent
                                    text: mPosPill.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: mPosPill.selected ? Font.Bold : Font.Medium
                                    color: mPosPill.selected ? Theme.secondary : Theme.fgSurface
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setSelectedPos(outCard.modelData.name, mPosPill.modelData.id)
                                }
                            }
                        }
                    }
                }

                // Adaptive Sync (VRR)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Adaptive Sync (VRR)"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Text {
                            text: "Synchronize refresh rate with variable-rate content (if supported by display)"
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    ToggleSwitch {
                        checked: outCard.activeVrr
                        onToggled: root.setSelectedVrr(outCard.modelData.name, !outCard.activeVrr)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Theme.r(9)
                        color: applyLiveMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                        scale: applyLiveMouse.pressed ? 0.97 : 1.0

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
                            text: "Apply Live"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.Bold
                            color: Theme.fgPrimary
                        }

                        MouseArea {
                            id: applyLiveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyLive(outCard.modelData.name)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Theme.r(9)
                        color: saveRuleMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.cardBorderWidth
                        border.color: Theme.cardBorder
                        scale: saveRuleMouse.pressed ? 0.97 : 1.0

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
                            text: "Save to local.conf"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        MouseArea {
                            id: saveRuleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.savePersistent(outCard.modelData.name)
                        }
                    }
                }
            }
        }
    }

    // --- Conditional Brightness Card (Backlight or DDC/CI monitor control) ---
    Rectangle {
        visible: DeviceCaps.hasBacklight || DeviceCaps.hasDdcutil
        Layout.fillWidth: true
        implicitHeight: brtCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: brtCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "DISPLAY BRIGHTNESS (" + (DeviceCaps.hasBacklight ? "BACKLIGHT" : "DDC/CI") + ")"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            StepControl {
                label: "Screen Luminance"
                displayValue: root.brightnessPct + "%"
                onDecremented: root.setBrightness(root.brightnessPct - 10)
                onIncremented: root.setBrightness(root.brightnessPct + 10)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [25, 50, 75, 100]

                    delegate: Rectangle {
                        id: brtPill
                        required property int modelData
                        readonly property bool selected: Math.abs(root.brightnessPct - brtPill.modelData) < 5
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: brtPill.selected ? Theme.withAlpha(Theme.primary, 0.22) : Theme.subCardBg
                        border.width: brtPill.selected ? 1 : Theme.cardBorderWidth
                        border.color: brtPill.selected ? Theme.primary : Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: brtPill.modelData + "%"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: brtPill.selected ? Font.Bold : Font.Medium
                            color: brtPill.selected ? Theme.primary : Theme.fgSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setBrightness(brtPill.modelData)
                        }
                    }
                }
            }
        }
    }

    // --- Conditional Night Light Card (visible only if hyprsunset / wlsunset / gammastep is installed) ---
    Rectangle {
        visible: DeviceCaps.hasNightLight
        Layout.fillWidth: true
        implicitHeight: nlCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: nlCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰖔"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(15)
                    color: ShellState.nightLightEnabled ? Theme.warning : Theme.fgSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "NIGHT LIGHT (" + (DeviceCaps.nightLightCmd.length > 0 ? DeviceCaps.nightLightCmd : "color filter") + ")"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.fgSurfaceVariant
                    }

                    Text {
                        text: "Reduce blue light emission at " + ShellState.nightLightTemp + "K"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }
                }

                ToggleSwitch {
                    checked: ShellState.nightLightEnabled
                    activeColor: Theme.warning
                    onToggled: ShellState.setNightLight(!ShellState.nightLightEnabled, ShellState.nightLightTemp)
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [3000, 3500, 4000, 4500, 5200, 6000]

                    delegate: Rectangle {
                        id: nlPill
                        required property int modelData
                        readonly property bool selected: ShellState.nightLightTemp === nlPill.modelData

                        implicitHeight: 26
                        implicitWidth: nlTxt.implicitWidth + 14
                        radius: Theme.r(8)
                        color: nlPill.selected
                            ? Theme.withAlpha(Theme.warning, 0.22)
                            : (nlMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: nlPill.selected ? 1 : Theme.cardBorderWidth
                        border.color: nlPill.selected ? Theme.warning : Theme.cardBorder

                        Text {
                            id: nlTxt
                            anchors.centerIn: parent
                            text: nlPill.modelData + "K"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: nlPill.selected ? Font.Bold : Font.Medium
                            color: nlPill.selected ? Theme.warning : Theme.fgSurface
                        }

                        MouseArea {
                            id: nlMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setNightLight(true, nlPill.modelData)
                        }
                    }
                }
            }
        }
    }
}
