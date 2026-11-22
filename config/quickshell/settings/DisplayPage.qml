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
    property string statusMsg: ""

    function refresh(): void {
        if (!randrProc.running)
            randrProc.running = true;
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

    function applyLive(outName: string): void {
        const m = root.selectedModeByOutput[outName];
        const s = root.selectedScaleByOutput[outName] || 1.0;
        if (!m)
            return;
        const modeArg = m.width + "x" + m.height + "@" + m.refreshStr + "Hz";
        root.statusMsg = "Applying " + outName + " (" + modeArg + " @ " + s + "x)...";
        applyProc.command = ["wlr-randr", "--output", outName, "--mode", modeArg, "--scale", String(s)];
        applyProc.running = true;
    }

    function savePersistent(outName: string): void {
        const m = root.selectedModeByOutput[outName];
        const s = root.selectedScaleByOutput[outName] || 1.0;
        if (!m)
            return;
        root.statusMsg = "Saved " + outName + " rule to ~/.config/mango/local.conf";
        applyProc.command = [
            Quickshell.shellPath("scripts/apply-local-setting.sh"),
            "set-monitor", outName,
            String(m.width), String(m.height), m.refreshStr, String(s)
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

                        parsed.push({
                            name: o.name,
                            description: o.description || o.model || o.name,
                            enabled: !!o.enabled,
                            scale: Number(o.scale || 1.0),
                            currentMode: currentMode,
                            modes: topModes
                        });
                    }
                    root.selectedModeByOutput = modeMap;
                    root.selectedScaleByOutput = scaleMap;
                    root.outputs = parsed;
                } catch (err) {}
            }
        }
    }

    Process {
        id: applyProc
        onExited: refreshDelay.restart()
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
            font.pixelSize: 10
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
                    font.pixelSize: 12
                    color: Theme.primary
                }

                Text {
                    text: "Detect Outputs"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
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
                        font.pixelSize: 16
                        color: Theme.primary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: outCard.modelData.name
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            text: outCard.modelData.description
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Rectangle {
                        implicitHeight: 20
                        implicitWidth: stateTxt.implicitWidth + 12
                        radius: Theme.r(8)
                        color: outCard.modelData.enabled ? Theme.withAlpha(Theme.success, 0.20) : Theme.subCardBg

                        Text {
                            id: stateTxt
                            anchors.centerIn: parent
                            text: outCard.modelData.enabled ? "ACTIVE" : "OFF"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: outCard.modelData.enabled ? Theme.success : Theme.fgSurfaceVariant
                        }
                    }
                }

                Text {
                    text: "RESOLUTION & REFRESH RATE"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
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
                                font.pixelSize: 10
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
                    font.pixelSize: 10
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
                                font.pixelSize: 10
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
                            font.pixelSize: 11
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
                            font.pixelSize: 11
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
}
