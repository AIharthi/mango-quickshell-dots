pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property real outVolume: 0.5
    property bool outMuted: false
    property real inVolume: 0.5
    property bool inMuted: false
    property bool _dragging: false
    property string defaultSink: ""
    property string defaultSource: ""
    property var sinks: []
    property var sources: []
    property var sinkInputs: []
    property var audioCards: []
    property string testStatus: ""
    readonly property real maxOutVolume: ShellState.audioOverAmp ? 1.5 : 1.0

    function refresh(): void {
        if (!audioQueryProc.running)
            audioQueryProc.running = true;
        if (!cardsQueryProc.running)
            cardsQueryProc.running = true;
    }

    function setSinkVolume(ratio: real): void {
        const cap = root.maxOutVolume;
        const c = Math.max(0.0, Math.min(cap, ratio));
        root.outVolume = c;
        root.outMuted = c <= 0.001;
        Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", Math.round(c * 100) + "%"]);
    }

    function toggleOverAmp(): void {
        const nxt = !ShellState.audioOverAmp;
        ShellState.setPref("audioOverAmp", nxt);
        if (!nxt && root.outVolume > 1.0)
            root.setSinkVolume(1.0);
    }

    function setCardProfile(cardName: string, profileName: string): void {
        if (cardMutProc.running)
            return;
        cardMutProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "audio-set-profile", cardName, profileName];
        cardMutProc.running = true;
    }

    function testSpeaker(channel: string): void {
        if (testAudioProc.running)
            return;
        root.testStatus = "Playing " + channel + " test tone...";
        testAudioProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "audio-test", channel];
        testAudioProc.running = true;
    }

    function setSourceVolume(ratio: real): void {
        const c = Math.max(0.0, Math.min(1.0, ratio));
        root.inVolume = c;
        root.inMuted = c <= 0.001;
        Quickshell.execDetached(["pactl", "set-source-volume", "@DEFAULT_SOURCE@", Math.round(c * 100) + "%"]);
    }

    function setStreamVolume(streamIdx: int, ratio: real): void {
        const c = Math.max(0.0, Math.min(1.5, ratio));
        const pct = Math.round(c * 100);
        const updated = [];
        for (let i = 0; i < root.sinkInputs.length; i++) {
            const it = root.sinkInputs[i];
            if (it.index === streamIdx)
                updated.push(Object.assign({}, it, { vol: c, mute: pct <= 0 }));
            else
                updated.push(it);
        }
        root.sinkInputs = updated;
        Quickshell.execDetached(["pactl", "set-sink-input-volume", String(streamIdx), pct + "%"]);
    }

    function toggleStreamMute(streamIdx: int): void {
        const updated = [];
        for (let i = 0; i < root.sinkInputs.length; i++) {
            const it = root.sinkInputs[i];
            if (it.index === streamIdx)
                updated.push(Object.assign({}, it, { mute: !it.mute }));
            else
                updated.push(it);
        }
        root.sinkInputs = updated;
        Quickshell.execDetached(["pactl", "set-sink-input-mute", String(streamIdx), "toggle"]);
    }

    function runAudioAction(cmd: list<string>): void {
        if (actionProc.running)
            return;
        actionProc.command = cmd;
        actionProc.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: audioQueryProc
        command: [
            "python3", "-c",
            "import json,re,subprocess\n" +
            "def out(c):\n" +
            "  try: return subprocess.check_output(c, stderr=subprocess.DEVNULL, text=True)\n" +
            "  except Exception: return ''\n" +
            "def pct(s):\n" +
            "  m = re.search(r'(\\d+)%', s)\n" +
            "  return int(m.group(1))/100.0 if m else 0.5\n" +
            "sinks_raw = out(['pactl','--format=json','list','sinks'])\n" +
            "srcs_raw = out(['pactl','--format=json','list','sources'])\n" +
            "inputs_raw = out(['pactl','--format=json','list','sink-inputs'])\n" +
            "sinks = [{'name':x['name'],'desc':x.get('description') or x['name']} for x in (json.loads(sinks_raw) if sinks_raw else [])]\n" +
            "sources = [{'name':x['name'],'desc':x.get('description') or x['name']} for x in (json.loads(srcs_raw) if srcs_raw else []) if not x['name'].endswith('.monitor')]\n" +
            "def stream_pct(v):\n" +
            "  vals = []\n" +
            "  for ch in (v or {}).values():\n" +
            "    m = re.search(r'(\\d+)%', str(ch.get('value_percent','')))\n" +
            "    if m: vals.append(int(m.group(1)))\n" +
            "  return (sum(vals)/len(vals)/100.0) if vals else 1.0\n" +
            "inputs = []\n" +
            "for x in (json.loads(inputs_raw) if inputs_raw else []):\n" +
            "  p = x.get('properties') or {}\n" +
            "  app = p.get('application.name') or p.get('application.process.binary') or 'Audio Stream'\n" +
            "  media = p.get('media.name') or ''\n" +
            "  inputs.append({'index': x.get('index', 0), 'name': app, 'media': media if media != app else '', 'mute': bool(x.get('mute')), 'vol': stream_pct(x.get('volume'))})\n" +
            "sv = out(['pactl','get-sink-volume','@DEFAULT_SINK@'])\n" +
            "sm = out(['pactl','get-sink-mute','@DEFAULT_SINK@'])\n" +
            "iv = out(['pactl','get-source-volume','@DEFAULT_SOURCE@'])\n" +
            "im = out(['pactl','get-source-mute','@DEFAULT_SOURCE@'])\n" +
            "print(json.dumps({'defaultSink':out(['pactl','get-default-sink']).strip(),'defaultSource':out(['pactl','get-default-source']).strip(),'outVol':pct(sv),'outMuted':('yes' in sm),'inVol':pct(iv),'inMuted':('yes' in im),'sinks':sinks,'sources':sources,'sinkInputs':inputs}))"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    root.defaultSink = d.defaultSink || "";
                    root.defaultSource = d.defaultSource || "";
                    root.outVolume = Math.max(0.0, Math.min(1.5, Number(d.outVol || 0)));
                    root.outMuted = !!d.outMuted;
                    root.inVolume = Math.max(0.0, Math.min(1.0, Number(d.inVol || 0)));
                    root.inMuted = !!d.inMuted;
                    root.sinks = Array.isArray(d.sinks) ? d.sinks : [];
                    root.sources = Array.isArray(d.sources) ? d.sources : [];
                    root.sinkInputs = Array.isArray(d.sinkInputs) ? d.sinkInputs : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: cardsQueryProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "audio-cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.audioCards = Array.isArray(d.cards) ? d.cards : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: cardMutProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.audioCards = Array.isArray(d.cards) ? d.cards : [];
                    refreshTimer.restart();
                } catch (err) {}
            }
        }
    }

    Process {
        id: testAudioProc
        onExited: root.testStatus = ""
    }

    Process {
        id: actionProc
        onExited: refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: 200
        repeat: false
        onTriggered: root.refresh()
    }

    // --- Toolbar ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Item { Layout.fillWidth: true }

        Rectangle {
            implicitHeight: 28
            implicitWidth: pavuRow.implicitWidth + 16
            visible: DeviceCaps.hasPavucontrol
            radius: Theme.r(10)
            color: pavuMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.subBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: pavuRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "󰋋"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(13)
                    color: Theme.secondary
                }

                Text {
                    text: "Open Pavucontrol"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: pavuMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["pavucontrol"])
            }
        }

        Rectangle {
            implicitHeight: 28
            implicitWidth: refRow.implicitWidth + 16
            radius: Theme.r(10)
            color: refMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.subBorderWidth
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
                    text: "Refresh"
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

    // --- Output Volume & Devices ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: outCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: outCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Output (speakers & headphones)"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: Theme.r(15)
                    color: outMuteMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: root.outMuted ? "󰝟" : "󰕾"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(15)
                        color: root.outMuted ? Theme.error : Theme.primary
                    }

                    MouseArea {
                        id: outMuteMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAudioAction(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"])
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 24

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 8
                        radius: Theme.r(4)
                        color: Theme.surfaceContainerHighest

                        Rectangle {
                            height: parent.height
                            width: parent.width * Math.min(1.0, root.outVolume / root.maxOutVolume)
                            radius: Theme.r(4)
                            color: root.outMuted
                                ? Theme.outline
                                : (root.outVolume > 1.0 ? Theme.warning : Theme.primary)

                            Behavior on width {
                                enabled: !root._dragging && !Theme.isSimple
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            root._dragging = true;
                            root.setSinkVolume((mouse.x / width) * root.maxOutVolume);
                        }
                        onPositionChanged: mouse => {
                            if (pressed)
                                root.setSinkVolume((mouse.x / width) * root.maxOutVolume);
                        }
                        onReleased: root._dragging = false
                        onCanceled: root._dragging = false
                    }
                }

                Text {
                    Layout.preferredWidth: 42
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.outVolume * 100) + "%"
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Bold
                    color: root.outVolume > 1.0 ? Theme.warning : Theme.fgSurface
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Over-Amplification (Allow up to 150% Boost)"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }

                ToggleSwitch {
                    checked: ShellState.audioOverAmp
                    activeColor: Theme.warning
                    onToggled: root.toggleOverAmp()
                }
            }

            RowLayout {
                visible: DeviceCaps.hasSpeakerTest
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.testStatus.length > 0 ? root.testStatus : "Speaker Channel Test"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: root.testStatus.length > 0 ? Theme.primary : Theme.fgSurfaceVariant
                }

                Repeater {
                    model: ["left", "stereo", "right"]

                    delegate: Rectangle {
                        id: tstChip
                        required property string modelData
                        implicitHeight: 24
                        implicitWidth: tstTxt.implicitWidth + 14
                        radius: Theme.r(7)
                        color: tstMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.subBorderWidth
                        border.color: Theme.cardBorder

                        Text {
                            id: tstTxt
                            anchors.centerIn: parent
                            text: tstChip.modelData.charAt(0).toUpperCase() + tstChip.modelData.slice(1)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.primary
                        }

                        MouseArea {
                            id: tstMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.testSpeaker(tstChip.modelData)
                        }
                    }
                }
            }

            Repeater {
                model: root.sinks

                delegate: Rectangle {
                    id: sinkRow
                    required property var modelData
                    readonly property bool isDefault: sinkRow.modelData.name === root.defaultSink

                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Theme.r(10)
                    color: sinkRow.isDefault
                        ? Theme.tileActiveBg
                        : (sinkMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                    border.width: sinkRow.isDefault ? Theme.activeControlBorderWidth : 0
                    border.color: Theme.primary

                    Rectangle {
                        visible: sinkRow.isDefault
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 7
                        anchors.bottomMargin: 7
                        width: 3
                        radius: 1.5
                        color: Theme.primary
                    }
                    scale: sinkMouse.pressed ? 0.98 : 1.0

                    Behavior on color {
                        enabled: !Theme.isSimple
                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: sinkRow.isDefault ? "󰄬" : "󰋋"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(13)
                            color: sinkRow.isDefault ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            text: sinkRow.modelData.desc
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: sinkRow.isDefault ? Font.Bold : Font.Normal
                            color: Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: sinkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAudioAction(["pactl", "set-default-sink", sinkRow.modelData.name])
                    }
                }
            }
        }
    }

    // --- Input Volume & Microphones ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: inCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: inCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Input (microphones)"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: Theme.r(15)
                    color: inMuteMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: root.inMuted ? "󰍭" : "󰍬"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(15)
                        color: root.inMuted ? Theme.error : Theme.secondary
                    }

                    MouseArea {
                        id: inMuteMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAudioAction(["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"])
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 24

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 8
                        radius: Theme.r(4)
                        color: Theme.surfaceContainerHighest

                        Rectangle {
                            height: parent.height
                            width: parent.width * root.inVolume
                            radius: Theme.r(4)
                            color: root.inMuted ? Theme.outline : Theme.secondary

                            Behavior on width {
                                enabled: !root._dragging && !Theme.isSimple
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            root._dragging = true;
                            root.setSourceVolume(mouse.x / width);
                        }
                        onPositionChanged: mouse => {
                            if (pressed)
                                root.setSourceVolume(mouse.x / width);
                        }
                        onReleased: root._dragging = false
                        onCanceled: root._dragging = false
                    }
                }

                Text {
                    Layout.preferredWidth: 38
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.inVolume * 100) + "%"
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
            }

            Repeater {
                model: root.sources

                delegate: Rectangle {
                    id: srcRow
                    required property var modelData
                    readonly property bool isDefault: srcRow.modelData.name === root.defaultSource

                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Theme.r(10)
                    color: srcRow.isDefault
                        ? Theme.tileActiveBg
                        : (srcMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                    border.width: srcRow.isDefault ? Theme.activeControlBorderWidth : 0
                    border.color: Theme.secondary

                    Rectangle {
                        visible: srcRow.isDefault
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 7
                        anchors.bottomMargin: 7
                        width: 3
                        radius: 1.5
                        color: Theme.secondary
                    }
                    scale: srcMouse.pressed ? 0.98 : 1.0

                    Behavior on color {
                        enabled: !Theme.isSimple
                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: srcRow.isDefault ? "󰄬" : "󰍬"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(13)
                            color: srcRow.isDefault ? Theme.secondary : Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            text: srcRow.modelData.desc
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: srcRow.isDefault ? Font.Bold : Font.Normal
                            color: Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: srcMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAudioAction(["pactl", "set-default-source", srcRow.modelData.name])
                    }
                }
            }

            Text {
                visible: root.sources.length === 0
                text: "No microphone input devices detected"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant
            }
        }
    }

    // --- 3. Application Volume Mixer ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: appMixCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: appMixCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Application mixer"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: mixRefLbl.implicitWidth + 12
                    radius: Theme.r(7)
                    color: mixRefMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: mixRefLbl
                        anchors.centerIn: parent
                        text: "Refresh"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: mixRefMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refresh()
                    }
                }
            }

            Repeater {
                model: root.sinkInputs

                delegate: Rectangle {
                    id: streamRow
                    required property var modelData
                    readonly property real clampedRatio: Math.max(0.0, Math.min(1.0, Number(streamRow.modelData.vol || 0)))

                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Theme.r(11)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Theme.r(8)
                            color: streamRow.modelData.mute ? Theme.withAlpha(Theme.error, 0.18) : Theme.withAlpha(Theme.primary, 0.16)

                            Text {
                                anchors.centerIn: parent
                                text: streamRow.modelData.mute ? "󰖁" : "󰎈"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(13)
                                color: streamRow.modelData.mute ? Theme.error : Theme.primary
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleStreamMute(streamRow.modelData.index)
                            }
                        }

                        ColumnLayout {
                            Layout.preferredWidth: 150
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: streamRow.modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: streamRow.modelData.mute ? Theme.fgSurfaceVariant : Theme.fgSurface
                            }

                            Text {
                                visible: (streamRow.modelData.media || "").length > 0
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: streamRow.modelData.media || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        // Horizontal App Stream Slider
                        Item {
                            id: streamTrackHost
                            Layout.fillWidth: true
                            implicitHeight: 22

                            Rectangle {
                                id: streamTrack
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 8
                                radius: Theme.r(4)
                                color: Theme.surfaceContainerHighest

                                Rectangle {
                                    width: parent.width * streamRow.clampedRatio
                                    height: parent.height
                                    radius: Theme.r(4)
                                    color: streamRow.modelData.mute ? Theme.outlineVariant : Theme.primary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: mouse => root.setStreamVolume(streamRow.modelData.index, mouse.x / Math.max(1, width))
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        root.setStreamVolume(streamRow.modelData.index, mouse.x / Math.max(1, width));
                                }
                            }
                        }

                        Text {
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                            text: streamRow.modelData.mute ? "Mute" : (Math.round(streamRow.modelData.vol * 100) + "%")
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: streamRow.modelData.mute ? Theme.error : Theme.fgSurface
                        }
                    }
                }
            }

            Text {
                visible: root.sinkInputs.length === 0
                text: "No active audio playback streams right now"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant
            }
        }
    }

    // --- 4. Audio Hardware Card Profiles ---
    Rectangle {
        visible: root.audioCards.length > 0
        Layout.fillWidth: true
        implicitHeight: cardProfCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: cardProfCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Hardware audio card profiles"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: root.audioCards

                delegate: Rectangle {
                    id: cardBox
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: cardBoxCol.implicitHeight + 14
                    radius: Theme.r(10)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: cardBoxCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: cardBox.modelData.desc
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 5

                            Repeater {
                                model: cardBox.modelData.profiles || []

                                delegate: Rectangle {
                                    id: profChip
                                    required property var modelData
                                    readonly property bool selected: cardBox.modelData.activeProfile === profChip.modelData.name

                                    implicitHeight: 22
                                    implicitWidth: profTxt.implicitWidth + 12
                                    radius: Theme.r(6)
                                    color: profChip.selected
                                        ? Theme.primary
                                        : (profMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg)
                                    border.width: profChip.selected ? Theme.activeControlBorderWidth : 0
                                    border.color: Theme.primary

                                    Text {
                                        id: profTxt
                                        anchors.centerIn: parent
                                        text: profChip.modelData.desc
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(9)
                                        font.weight: profChip.selected ? Font.Bold : Font.Normal
                                        color: profChip.selected ? Theme.fgPrimary : Theme.fgSurface
                                    }

                                    MouseArea {
                                        id: profMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setCardProfile(cardBox.modelData.name, profChip.modelData.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
