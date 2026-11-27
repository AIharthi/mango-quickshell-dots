pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property bool hasXdgMime: DeviceCaps.hasXdgMime
    property var candidatesByRole: ({})
    property var mimeDefaults: ({})
    property var startupUserItems: []
    property var startupBuiltinItems: []
    property var hiddenIds: []
    property var hiddenPrefixes: []
    property var envVars: []
    property string envStatus: ""

    readonly property var quickRoles: [
        { role: "terminal", key: "defaultTerminal",    label: "Terminal",     bindHint: "SUPER + Return", icon: "󰆍" },
        { role: "browser",  key: "defaultBrowser",     label: "Web Browser",  bindHint: "SUPER + B",      icon: "󰖟" },
        { role: "editor",   key: "defaultEditor",      label: "Editor",       bindHint: "SUPER + Z",      icon: "󰏫" },
        { role: "files",    key: "defaultFileManager", label: "File Manager", bindHint: "Launcher",       icon: "󰉋" }
    ]

    readonly property var mimeRows: [
        { key: "web",    label: "Web Links (HTTP/HTTPS)", icon: "󰖟" },
        { key: "files",  label: "Folders (Directory)",    icon: "󰉋" },
        { key: "text",   label: "Plain Text",             icon: "󰏫" },
        { key: "images", label: "Images (PNG)",           icon: "󰋩" },
        { key: "video",  label: "Video (MP4)",            icon: "󰕧" }
    ]

    function currentForPref(prefKey: string): string {
        if (prefKey === "defaultTerminal") return ShellState.defaultTerminal;
        if (prefKey === "defaultBrowser") return ShellState.defaultBrowser;
        if (prefKey === "defaultEditor") return ShellState.defaultEditor;
        return ShellState.defaultFileManager;
    }

    function refreshAll(): void {
        if (!defaultsProc.running)
            defaultsProc.running = true;
        if (!startupProc.running)
            startupProc.running = true;
        if (!hiddenGetProc.running)
            hiddenGetProc.running = true;
        if (!envListProc.running)
            envListProc.running = true;
    }

    function addHidden(kind: string, val: string): void {
        const clean = (val || "").trim();
        if (clean.length === 0 || hiddenMutProc.running)
            return;
        hiddenMutProc.command = [Quickshell.shellPath("scripts/manage-settings.sh"), "hidden-apps-add", kind, clean];
        hiddenMutProc.running = true;
    }

    function removeHidden(kind: string, val: string): void {
        if (hiddenMutProc.running)
            return;
        hiddenMutProc.command = [Quickshell.shellPath("scripts/manage-settings.sh"), "hidden-apps-remove", kind, val];
        hiddenMutProc.running = true;
    }

    function addEnv(k: string, v: string): void {
        const ck = (k || "").trim();
        const cv = (v || "").trim();
        if (ck.length === 0 || cv.length === 0 || envMutProc.running)
            return;
        envMutProc.command = [Quickshell.shellPath("scripts/apply-local-setting.sh"), "env-add", ck, cv];
        envMutProc.running = true;
    }

    function removeEnv(k: string): void {
        if (envMutProc.running)
            return;
        envMutProc.command = [Quickshell.shellPath("scripts/apply-local-setting.sh"), "env-remove", k];
        envMutProc.running = true;
    }

    function applyHiddenPayload(raw: string): void {
        try {
            const d = JSON.parse((raw || "").trim());
            root.hiddenIds = Array.isArray(d.hiddenIds) ? d.hiddenIds : [];
            root.hiddenPrefixes = Array.isArray(d.hiddenNamePrefixes) ? d.hiddenNamePrefixes : [];
        } catch (err) {}
    }

    function setMimeDefault(mime: string, desktopId: string): void {
        if (defaultsSetProc.running)
            return;
        defaultsSetProc.command = [Quickshell.shellPath("scripts/manage-settings.sh"), "defaults-set", mime, desktopId];
        defaultsSetProc.running = true;
    }

    function addStartup(cmd: string): void {
        const clean = (cmd || "").trim();
        if (clean.length === 0 || startupMutProc.running)
            return;
        startupMutProc.command = [Quickshell.shellPath("scripts/manage-settings.sh"), "startup-add", clean];
        startupMutProc.running = true;
    }

    function removeStartup(cmd: string): void {
        if (startupMutProc.running)
            return;
        startupMutProc.command = [Quickshell.shellPath("scripts/manage-settings.sh"), "startup-remove", cmd];
        startupMutProc.running = true;
    }

    function applyDefaultsPayload(raw: string): void {
        const txt = (raw || "").trim();
        if (txt.length === 0)
            return;
        try {
            const d = JSON.parse(txt);
            if (d.hasXdgMime !== undefined)
                root.hasXdgMime = !!d.hasXdgMime;
            if (d.candidates)
                root.candidatesByRole = d.candidates;
            if (d.mimeDefaults)
                root.mimeDefaults = d.mimeDefaults;
        } catch (err) {}
    }

    function applyStartupPayload(raw: string): void {
        const txt = (raw || "").trim();
        if (txt.length === 0)
            return;
        try {
            const d = JSON.parse(txt);
            root.startupUserItems = Array.isArray(d.items) ? d.items : [];
            root.startupBuiltinItems = Array.isArray(d.builtin) ? d.builtin : [];
        } catch (err) {}
    }

    Component.onCompleted: refreshAll()

    Process {
        id: defaultsProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "defaults-get"]
        stdout: StdioCollector {
            onStreamFinished: root.applyDefaultsPayload(text)
        }
    }

    Process {
        id: defaultsSetProc
        stdout: StdioCollector {
            onStreamFinished: root.applyDefaultsPayload(text)
        }
    }

    Process {
        id: startupProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "startup-list"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStartupPayload(text)
        }
    }

    Process {
        id: startupMutProc
        stdout: StdioCollector {
            onStreamFinished: root.applyStartupPayload(text)
        }
    }

    Process {
        id: hiddenGetProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "hidden-apps-get"]
        stdout: StdioCollector {
            onStreamFinished: root.applyHiddenPayload(text)
        }
    }

    Process {
        id: hiddenMutProc
        stdout: StdioCollector {
            onStreamFinished: root.applyHiddenPayload(text)
        }
    }

    Process {
        id: envListProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "env-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.envVars = Array.isArray(d.envs) ? d.envs : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: envMutProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.envVars = Array.isArray(d.envs) ? d.envs : [];
                    root.envStatus = "Environment saved & verified with mango -p";
                } catch (err) {}
            }
        }
    }

    // --- 1. Quick-Launch Keybind Applications ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: quickCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: quickCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Quick-launch keybind applications"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: root.quickRoles

                delegate: Rectangle {
                    id: appRow
                    required property var modelData
                    readonly property string activeCmd: root.currentForPref(appRow.modelData.key)
                    readonly property var candidates: root.candidatesByRole[appRow.modelData.role] || []

                    Layout.fillWidth: true
                    implicitHeight: appRowCol.implicitHeight + 16
                    radius: Theme.r(11)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: appRowCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 7

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: appRow.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(14)
                                color: Theme.primary
                            }

                            Text {
                                text: appRow.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: hintTxt.implicitWidth + 10
                                radius: Theme.r(5)
                                color: Theme.cardBg
                                border.width: Theme.subBorderWidth
                                border.color: Theme.cardBorder

                                Text {
                                    id: hintTxt
                                    anchors.centerIn: parent
                                    text: appRow.modelData.bindHint
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fs(9)
                                    color: Theme.fgSurfaceVariant
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: appRow.activeCmd
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Bold
                                color: Theme.secondary
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: appRow.candidates

                                delegate: Rectangle {
                                    id: candPill
                                    required property string modelData
                                    readonly property bool selected: appRow.activeCmd === candPill.modelData

                                    implicitHeight: 24
                                    implicitWidth: candTxt.implicitWidth + 14
                                    radius: Theme.r(7)
                                    color: candPill.selected
                                        ? Theme.primary
                                        : (candMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg)
                                    border.width: candPill.selected ? Theme.activeControlBorderWidth : 0
                                    border.color: Theme.primary

                                    Text {
                                        id: candTxt
                                        anchors.centerIn: parent
                                        text: candPill.modelData
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(10)
                                        font.weight: candPill.selected ? Font.Bold : Font.Medium
                                        color: candPill.selected ? Theme.fgPrimary : Theme.fgSurface
                                    }

                                    MouseArea {
                                        id: candMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ShellState.setPref(appRow.modelData.key, candPill.modelData)
                                    }
                                }
                            }
                        }

                        // Custom Command Input
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 26
                                radius: Theme.r(7)
                                color: Theme.cardBg
                                border.width: customInput.activeFocus ? 1 : Theme.subBorderWidth
                                border.color: customInput.activeFocus ? Theme.primary : Theme.cardBorder

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Custom command (e.g. alacritty, firefox, zed)..."
                                        visible: customInput.text.length === 0
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(10)
                                        color: Theme.fgSurfaceVariant
                                    }

                                    TextInput {
                                        id: customInput
                                        anchors.fill: parent
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fs(10)
                                        color: Theme.fgSurface
                                        clip: true
                                        onAccepted: {
                                            if (text.trim().length > 0) {
                                                ShellState.setPref(appRow.modelData.key, text.trim());
                                                text = "";
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                implicitHeight: 26
                                implicitWidth: setCmdLbl.implicitWidth + 14
                                radius: Theme.r(7)
                                color: setCmdMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                                border.width: Theme.subBorderWidth
                                border.color: Theme.cardBorder

                                Text {
                                    id: setCmdLbl
                                    anchors.centerIn: parent
                                    text: "Set"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                }

                                MouseArea {
                                    id: setCmdMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const c = customInput.text.trim();
                                        if (c.length > 0) {
                                            ShellState.setPref(appRow.modelData.key, c);
                                            customInput.text = "";
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

    // --- 2. XDG Default Applications ---
    Rectangle {
        visible: root.hasXdgMime
        Layout.fillWidth: true
        implicitHeight: xdgCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: xdgCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "System default applications"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: root.mimeRows

                delegate: Rectangle {
                    id: mimeRow
                    required property var modelData
                    readonly property var info: root.mimeDefaults[mimeRow.modelData.key] || ({ mime: "", current: "", options: [] })
                    readonly property string currentId: String(mimeRow.info.current || "")
                    readonly property var optionsList: Array.isArray(mimeRow.info.options) ? mimeRow.info.options : []

                    Layout.fillWidth: true
                    implicitHeight: mimeInner.implicitHeight + 16
                    radius: Theme.r(11)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: mimeInner
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: mimeRow.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(13)
                                color: Theme.secondary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: mimeRow.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            Text {
                                text: mimeRow.currentId.length > 0 ? mimeRow.currentId : "Unassigned"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: mimeRow.currentId.length > 0 ? Theme.primary : Theme.fgSurfaceVariant
                            }
                        }

                        Flow {
                            visible: mimeRow.optionsList.length > 0
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: mimeRow.optionsList

                                delegate: Rectangle {
                                    id: optPill
                                    required property var modelData
                                    readonly property bool selected: mimeRow.currentId === optPill.modelData.id

                                    implicitHeight: 24
                                    implicitWidth: optTxt.implicitWidth + 14
                                    radius: Theme.r(7)
                                    color: optPill.selected
                                        ? Theme.secondary
                                        : (optMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg)
                                    border.width: optPill.selected ? Theme.activeControlBorderWidth : 0
                                    border.color: Theme.secondary

                                    Text {
                                        id: optTxt
                                        anchors.centerIn: parent
                                        text: optPill.modelData.name
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(10)
                                        font.weight: optPill.selected ? Font.Bold : Font.Medium
                                        color: optPill.selected ? Theme.contrastInk(Theme.secondary) : Theme.fgSurface
                                    }

                                    MouseArea {
                                        id: optMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setMimeDefault(mimeRow.info.mime, optPill.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 3. Startup Applications (exec_once) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: startCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: startCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Startup applications"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: startupInput.activeFocus ? 1 : Theme.subBorderWidth
                    border.color: startupInput.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Add startup command (e.g. waypaper --restore, foot)..."
                            visible: startupInput.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: startupInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(11)
                            color: Theme.fgSurface
                            clip: true
                            onAccepted: {
                                if (text.trim().length > 0) {
                                    root.addStartup(text);
                                    text = "";
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: addStartRow.implicitWidth + 16
                    radius: Theme.r(8)
                    color: addStartMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                    scale: addStartMouse.pressed ? 0.96 : 1.0

                    Behavior on color {
                        enabled: !Theme.isSimple
                        ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        id: addStartRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "󰐕"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(12)
                            color: Theme.fgPrimary
                        }

                        Text {
                            text: "Add"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgPrimary
                        }
                    }

                    MouseArea {
                        id: addStartMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const cmd = startupInput.text.trim();
                            if (cmd.length > 0) {
                                root.addStartup(cmd);
                                startupInput.text = "";
                            }
                        }
                    }
                }
            }

            Repeater {
                model: root.startupUserItems

                delegate: Rectangle {
                    id: usrStartRow
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Theme.r(9)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "local.conf"
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.Bold
                            color: Theme.primary
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: usrStartRow.modelData.cmd
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(11)
                            color: Theme.fgSurface
                        }

                        Rectangle {
                            implicitWidth: 24
                            implicitHeight: 24
                            radius: Theme.r(6)
                            color: editStartMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.20) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰏫"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(12)
                                color: editStartMouse.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: editStartMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    startupInput.text = usrStartRow.modelData.cmd;
                                    root.removeStartup(usrStartRow.modelData.cmd);
                                    startupInput.forceActiveFocus();
                                }
                            }
                        }

                        Rectangle {
                            implicitWidth: 24
                            implicitHeight: 24
                            radius: Theme.r(6)
                            color: delStartMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.20) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰆴"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(12)
                                color: delStartMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: delStartMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeStartup(usrStartRow.modelData.cmd)
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.startupUserItems.length === 0
                text: "No custom startup commands added to local.conf yet"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurfaceVariant
            }

            ColumnLayout {
                visible: root.startupBuiltinItems.length > 0
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Core autostart services (autostart.sh)"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(9)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Repeater {
                    model: root.startupBuiltinItems

                    delegate: Rectangle {
                        id: coreRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(7)
                        color: Theme.subCardBg
                        opacity: 0.78

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: coreRow.modelData.cmd
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }
                    }
                }
            }
        }
    }

    // --- 4. App Launcher Visibility (hidden-apps.json) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hidCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: hidCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Launcher visibility"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: hideIn.activeFocus ? 1 : Theme.subBorderWidth
                    border.color: hideIn.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Desktop ID or name prefix to hide (e.g. qdbusviewer)..."
                            visible: hideIn.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: hideIn
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurface
                            clip: true
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: hidIdLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: hidIdMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                    Text { id: hidIdLbl; anchors.centerIn: parent; text: "Hide ID"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgPrimary }
                    MouseArea { id: hidIdMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.addHidden("id", hideIn.text); hideIn.text = ""; } }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: hidPfLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: hidPfMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text { id: hidPfLbl; anchors.centerIn: parent; text: "Hide Prefix"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.secondary }
                    MouseArea { id: hidPfMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.addHidden("prefix", hideIn.text); hideIn.text = ""; } }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 5

                Repeater {
                    model: root.hiddenIds

                    delegate: Rectangle {
                        id: hidTag
                        required property string modelData
                        implicitHeight: 22
                        implicitWidth: hidTagRow.implicitWidth + 12
                        radius: Theme.r(6)
                        color: Theme.subCardBg
                        border.width: Theme.subBorderWidth
                        border.color: Theme.cardBorder

                        RowLayout {
                            id: hidTagRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text { text: hidTag.modelData; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.fgSurface }
                            Text { text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.error }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.removeHidden("id", hidTag.modelData)
                        }
                    }
                }
            }

            Flow {
                visible: root.hiddenPrefixes.length > 0
                Layout.fillWidth: true
                spacing: 5

                Repeater {
                    model: root.hiddenPrefixes

                    delegate: Rectangle {
                        id: pfTag
                        required property string modelData
                        implicitHeight: 22
                        implicitWidth: pfTagRow.implicitWidth + 12
                        radius: Theme.r(6)
                        color: Theme.withAlpha(Theme.secondary, 0.14)
                        border.width: Theme.subBorderWidth
                        border.color: Theme.withAlpha(Theme.secondary, 0.4)

                        RowLayout {
                            id: pfTagRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text { text: "prefix:" + pfTag.modelData; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.secondary }
                            Text { text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.error }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.removeHidden("prefix", pfTag.modelData)
                        }
                    }
                }
            }
        }
    }

    // --- 5. Session Environment Variables (env= in local.conf) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: envCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: envCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Session environment variables (env= in local.conf)"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgSurfaceVariant }
                Text { visible: root.envStatus.length > 0; text: root.envStatus; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.success }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.preferredWidth: 160
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: envKeyIn.activeFocus ? 1 : Theme.subBorderWidth
                    border.color: envKeyIn.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Variable"; visible: envKeyIn.text.length === 0; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                        TextInput { id: envKeyIn; anchors.fill: parent; verticalAlignment: TextInput.AlignVCenter; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurface; clip: true }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: envValIn.activeFocus ? 1 : Theme.subBorderWidth
                    border.color: envValIn.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Value (e.g. wayland)"; visible: envValIn.text.length === 0; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                        TextInput { id: envValIn; anchors.fill: parent; verticalAlignment: TextInput.AlignVCenter; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurface; clip: true }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: addEnvLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: addEnvMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                    Text { id: addEnvLbl; anchors.centerIn: parent; text: "Add Env"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgPrimary }
                    MouseArea {
                        id: addEnvMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.addEnv(envKeyIn.text, envValIn.text);
                            envKeyIn.text = "";
                            envValIn.text = "";
                        }
                    }
                }
            }

            Repeater {
                model: root.envVars

                delegate: Rectangle {
                    id: envRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 6; spacing: 8
                        Text { text: envRow.modelData.key; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.secondary }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: "= " + envRow.modelData.value; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }

                        Rectangle {
                            implicitWidth: 20; implicitHeight: 20; radius: Theme.r(5)
                            color: editEnvMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.22) : "transparent"
                            Text { anchors.centerIn: parent; text: "󰏫"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: editEnvMouse.containsMouse ? Theme.primary : Theme.fgSurfaceVariant }
                            MouseArea {
                                id: editEnvMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    envKeyIn.text = envRow.modelData.key;
                                    envValIn.text = envRow.modelData.value;
                                    envValIn.forceActiveFocus();
                                }
                            }
                        }

                        Rectangle {
                            implicitWidth: 20; implicitHeight: 20; radius: Theme.r(5)
                            color: delEnvMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : "transparent"
                            Text { anchors.centerIn: parent; text: "󰆴"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: delEnvMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant }
                            MouseArea { id: delEnvMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.removeEnv(envRow.modelData.key) }
                        }
                    }
                }
            }

            Text {
                visible: root.envVars.length === 0
                text: "No custom environment variables defined in local.conf"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurfaceVariant
            }
        }
    }
}
