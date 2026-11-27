pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../m3"

PanelWindow {
    id: root

    property bool isOpen: false
    property string query: ""
    property string selectedCategory: "All"
    property var categories: ["All"]
    property var allBinds: []

    signal closeRequested()

    visible: root.isOpen
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-keybinds"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function refresh(): void {
        if (!bindsProc.running)
            bindsProc.running = true;
    }

    onIsOpenChanged: {
        if (isOpen) {
            searchInput.text = "";
            root.query = "";
            root.selectedCategory = "All";
            refresh();
            focusTimer.restart();
        }
    }

    Component.onCompleted: {
        if (isOpen) {
            refresh();
            focusTimer.restart();
        }
    }

    Timer {
        id: focusTimer
        interval: 35
        repeat: false
        onTriggered: {
            if (root.isOpen)
                searchInput.forceActiveFocus();
        }
    }

    Process {
        id: bindsProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "keybinds-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    const cats = Array.isArray(d.categories) ? d.categories : [];
                    root.categories = ["All"].concat(cats);
                    root.allBinds = Array.isArray(d.binds) ? d.binds : [];
                } catch (err) {}
            }
        }
    }

    function formatBindingLabel(b: var): string {
        if (!b)
            return "";
        const arg = String(b.arg || "").trim();
        const act = String(b.action || "").trim();
        const ipcLabels = {
            "toggle": "Toggle hub",
            "toggleDashboard": "Toggle island hub",
            "collapse": "Collapse island",
            "toggleLauncher": "App launcher",
            "toggleFileManager": "File manager",
            "toggleFiles": "File manager",
            "toggleFilesTab": "Quick files drawer",
            "openFiles": "Open folder",
            "closeFiles": "Close file manager",
            "toggleSettings": "Settings",
            "openSettings": "Open settings",
            "closeSettings": "Close settings",
            "toggleKeybindSheet": "Keyboard shortcuts",
            "toggleWindowSwitcher": "Window switcher",
            "togglePowerMenu": "Power menu",
            "togglePowerOverlay": "Power menu",
            "toggleStore": "Aurora App Store",
            "openSettings debloat": "System Debloater",
            "toggleSplitLeft": "Split Left Spaces Hub",
            "toggleSplitCenter": "Split Center Media & Focus",
            "cycleSplitHubStyle": "Cycle Split Hub layout",
            "toggleThemeTab": "Themes & wallpaper",
            "toggleAlertsTab": "Notifications & calendar",
            "toggleNotifications": "Notifications & calendar",
            "toggleGameMode": "Toggle game mode",
            "toggleDnd": "Toggle Do Not Disturb",
            "toggleKeepAwake": "Toggle keep screen awake",
            "toggleDarkLight": "Toggle dark / light mode",
            "cycleHubUiStyle": "Cycle hub layout",
            "cycleBarUiStyle": "Cycle bar style",
            "cycleShellMode": "Cycle visual style",
            "randomWallpaper": "Shuffle wallpaper",
            "togglePip": "Toggle Picture-in-Picture",
            "cyclePipCorner": "Move PiP corner",
            "snapPip": "Snap PiP window",
            "lockSession": "Lock screen",
            "toggleClipboard": "Clipboard history",
            "toggleSnippets": "Snippets vault",
            "toggleCaptureHub": "Capture Studio",
            "clearClipboard": "Clear clipboard",
            "toggleEmoji": "Emoji picker",
            "refreshWeather": "Refresh weather",
            "syncSddmTheme": "Sync SDDM theme"
        };
        if (arg.indexOf("qs ipc call island ") === 0) {
            const fn = arg.slice("qs ipc call island ".length).trim();
            return ipcLabels[fn] || ("Shell: " + fn);
        }
        if (arg.indexOf("qs ipc call aurora ") === 0) {
            const fn = arg.slice("qs ipc call aurora ".length).trim();
            return ipcLabels[fn] || ("Shell: " + fn);
        }
        if (arg.indexOf("screenshot.sh") !== -1)
            return arg.indexOf("--full") !== -1 ? "Full screenshot" : "Area screenshot";
        if (arg.indexOf("record-screen.sh") !== -1)
            return "Toggle screen recording";
        if (arg.indexOf("pactl ") !== -1) {
            if (arg.indexOf("set-sink-mute") !== -1) return "Toggle audio mute";
            if (arg.indexOf("set-source-mute") !== -1) return "Toggle mic mute";
            if (arg.indexOf("+5%") !== -1) return "Volume up";
            if (arg.indexOf("-5%") !== -1) return "Volume down";
        }
        if (arg.indexOf("brightnessctl ") !== -1)
            return arg.indexOf("+") !== -1 ? "Brightness up" : "Brightness down";
        if (arg.length > 0 && (act === "spawn" || act === "spawn_shell"))
            return arg;
        const actLabels = {
            "killclient": "Close active window",
            "togglefloating": "Toggle floating window",
            "togglefullscreen": "Toggle fullscreen",
            "switch_layout": "Cycle tiling layout",
            "reload_config": "Reload MangoWC config",
            "quit": "Log out of MangoWC",
            "toggleoverview": "Workspace overview",
            "focusstack": "Cycle window focus",
            "view": "Switch workspace",
            "tag": "Move window to workspace",
            "focusmon": "Focus next monitor",
            "tagmon": "Move window to monitor"
        };
        if (arg.length > 0)
            return (actLabels[act] || act) + " (" + arg + ")";
        return actLabels[act] || act;
    }

    readonly property var filteredBinds: {
        const list = root.allBinds || [];
        const cat = root.selectedCategory;
        const q = root.query.trim().toLowerCase();
        const out = [];
        for (let i = 0; i < list.length; i++) {
            const b = list[i];
            if (cat !== "All" && b.category !== cat)
                continue;
            const desc = formatBindingLabel(b);
            if (q.length > 0) {
                const hay = (String(b.modsRaw || "") + " " + String(b.key || "") + " " + desc + " " + String(b.category || "")).toLowerCase();
                if (hay.indexOf(q) === -1)
                    continue;
            }
            out.push({
                mods: Array.isArray(b.mods) ? b.mods : [],
                key: String(b.key || ""),
                desc: desc,
                category: String(b.category || "General"),
                isMouse: b.kind === "mouse"
            });
        }
        return out;
    }

    // Backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.50)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    // Modal Container
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(840, Math.max(460, root.width - 72))
        height: Math.min(580, Math.max(380, root.height - 72))
        radius: Theme.r(32)
        color: Theme.m3PanelBg
        border.width: 1
        border.color: Theme.m3Line

        // Prevent backdrop click-through inside modal
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item {
                    implicitWidth: 44
                    implicitHeight: 44

                    M3Blob {
                        anchors.fill: parent
                        kind: ShellState.m3Shape
                        color: Theme.m3PrimaryContainer
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰌌"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(19)
                        color: Theme.m3OnPrimaryContainer
                    }
                }

                Text {
                    text: "Keyboard & Mouse Shortcuts"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(16)
                    font.weight: Font.Bold
                    color: Theme.m3Ink
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: countTxt.implicitWidth + 16
                    radius: Theme.r(12)
                    color: Theme.m3SecondaryContainer

                    Text {
                        id: countTxt
                        anchors.centerIn: parent
                        text: root.filteredBinds.length + " binds"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.m3OnSecondaryContainer
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: Theme.r(18)
                    color: closeMouse.containsMouse ? Theme.m3ErrorContainer : Theme.m3SurfaceC
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(14)
                        color: closeMouse.containsMouse ? Theme.m3OnErrorContainer : Theme.m3InkDim
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            // Search Input
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: Theme.r(22)
                color: searchInput.activeFocus ? Theme.m3SurfaceHigh : Theme.m3SurfaceC
                border.width: searchInput.activeFocus ? 2 : 1
                border.color: searchInput.activeFocus ? Theme.m3Primary : Theme.m3Line
                Behavior on color { ColorAnimation { duration: 160 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 10

                    Text {
                        text: "󰍉"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(16)
                        color: searchInput.activeFocus ? Theme.m3Primary : Theme.m3InkDim
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0
                            text: "Filter shortcuts by key, app, or action (Esc to close)..."
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            color: Theme.m3InkDim
                        }

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.m3Ink
                            selectionColor: Theme.m3Primary
                            selectedTextColor: Theme.m3OnPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            clip: true

                            onTextChanged: root.query = text
                            Keys.onEscapePressed: {
                                if (text.length > 0)
                                    text = "";
                                else
                                    root.closeRequested();
                            }
                        }
                    }
                }
            }

            // Category Chips (wrap cleanly so no category label clips)
            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.categories
                    delegate: Rectangle {
                        id: catChip
                        required property string modelData
                        readonly property bool isSel: root.selectedCategory === catChip.modelData

                        implicitHeight: 30
                        implicitWidth: catLbl.implicitWidth + 22
                        radius: Theme.r(catChip.isSel ? 11 : 15)
                        color: catChip.isSel
                            ? Theme.m3Primary
                            : (catMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC)
                        Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            id: catLbl
                            anchors.centerIn: parent
                            text: (catChip.isSel ? "󰄬 " : "") + catChip.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: catChip.isSel ? Font.Bold : Font.Medium
                            color: catChip.isSel ? Theme.m3OnPrimary : Theme.m3InkDim
                        }

                        MouseArea {
                            id: catMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedCategory = catChip.modelData
                        }
                    }
                }
            }

            // Shortcuts Grid
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.r(24)
                color: Theme.m3PaneBg
                border.width: 1
                border.color: Theme.m3Line
                clip: true

                GridView {
                    id: bindGrid
                    anchors.fill: parent
                    anchors.margins: 10
                    cellWidth: Math.floor(width / 2)
                    cellHeight: 46
                    clip: true
                    model: root.filteredBinds

                    delegate: Item {
                        id: bindCell
                        required property var modelData
                        width: bindGrid.cellWidth - 6
                        height: bindGrid.cellHeight - 6

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.r(16)
                            color: Theme.m3SurfaceC
                            border.width: 1
                            border.color: Theme.m3Line

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Row {
                                    spacing: 4

                                    Repeater {
                                        model: bindCell.modelData.mods
                                        delegate: Rectangle {
                                            id: modPill
                                            required property string modelData
                                            implicitHeight: 22
                                            implicitWidth: modLbl.implicitWidth + 10
                                            radius: Theme.r(8)
                                            color: Theme.m3PrimaryContainer

                                            Text {
                                                id: modLbl
                                                anchors.centerIn: parent
                                                text: modPill.modelData
                                                font.family: Theme.monoFont
                                                font.pixelSize: Theme.fs(9)
                                                font.weight: Font.Bold
                                                color: Theme.m3OnPrimaryContainer
                                            }
                                        }
                                    }

                                    Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: keyLbl.implicitWidth + 12
                                        radius: Theme.r(8)
                                        color: Theme.m3SurfaceHighest

                                        Text {
                                            id: keyLbl
                                            anchors.centerIn: parent
                                            text: bindCell.modelData.key
                                            font.family: Theme.monoFont
                                            font.pixelSize: Theme.fs(9)
                                            font.weight: Font.Bold
                                            color: Theme.m3Ink
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: bindCell.modelData.desc
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    horizontalAlignment: Text.AlignRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    color: Theme.m3InkDim
                                }
                            }
                        }
                    }
                }
            }

            // Footer
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Customize bindings in Settings under Shortcuts · Super + / to toggle"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.m3InkDim
            }
        }
    }
}
