pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

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
        if (arg.indexOf("qs ipc call island ") === 0)
            return "Shell: " + arg.slice("qs ipc call island ".length);
        if (arg.length > 0 && (act === "spawn" || act === "spawn_shell"))
            return arg;
        if (arg.length > 0)
            return act + " (" + arg + ")";
        return act;
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
        radius: Theme.r(24)
        color: Theme.notchBg
        border.width: Math.max(1, Theme.islandBorderWidth)
        border.color: Theme.islandBorder

        // Prevent backdrop click-through inside modal
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "󰌌"
                    font.family: Theme.iconFont
                    font.pixelSize: 18
                    color: Theme.primary
                }

                Text {
                    text: "Keyboard & Mouse Shortcuts"
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: countTxt.implicitWidth + 12
                    radius: Theme.r(10)
                    color: Theme.cardBg

                    Text {
                        id: countTxt
                        anchors.centerIn: parent
                        text: root.filteredBinds.length + " binds"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Theme.r(14)
                    color: closeMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                        color: closeMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
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
                implicitHeight: 38
                radius: Theme.r(12)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: searchInput.activeFocus ? Theme.primary : Theme.cardBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "󰍉"
                        font.family: Theme.iconFont
                        font.pixelSize: 15
                        color: searchInput.activeFocus ? Theme.primary : Theme.fgSurfaceVariant
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0
                            text: "Filter shortcuts by key, app, or action (Esc to close)..."
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fgSurface
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.fgPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
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

            // Category Chips
            Flickable {
                Layout.fillWidth: true
                implicitHeight: 28
                contentWidth: catRow.implicitWidth
                clip: true

                Row {
                    id: catRow
                    spacing: 6

                    Repeater {
                        model: root.categories
                        delegate: Rectangle {
                            id: catChip
                            required property string modelData
                            readonly property bool isSel: root.selectedCategory === catChip.modelData

                            implicitHeight: 26
                            implicitWidth: catLbl.implicitWidth + 16
                            radius: Theme.r(13)
                            color: catChip.isSel
                                ? Theme.primary
                                : (catMouse.containsMouse ? Theme.hoverBg : Theme.cardBg)
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                id: catLbl
                                anchors.centerIn: parent
                                text: catChip.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: catChip.isSel ? Font.Bold : Font.Medium
                                color: catChip.isSel ? Theme.fgPrimary : Theme.fgSurfaceVariant
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
            }

            // Shortcuts Grid
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.r(16)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                GridView {
                    id: bindGrid
                    anchors.fill: parent
                    anchors.margins: 10
                    cellWidth: Math.floor(width / 2)
                    cellHeight: 42
                    clip: true
                    model: root.filteredBinds

                    delegate: Item {
                        id: bindCell
                        required property var modelData
                        width: bindGrid.cellWidth - 6
                        height: bindGrid.cellHeight - 4

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.r(10)
                            color: Theme.subCardBg

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Row {
                                    spacing: 3

                                    Repeater {
                                        model: bindCell.modelData.mods
                                        delegate: Rectangle {
                                            required property string modelData
                                            implicitHeight: 20
                                            implicitWidth: modLbl.implicitWidth + 8
                                            radius: Theme.r(5)
                                            color: Theme.withAlpha(Theme.primary, 0.20)
                                            border.width: 1
                                            border.color: Theme.withAlpha(Theme.primary, 0.45)

                                            Text {
                                                id: modLbl
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: Theme.primary
                                            }
                                        }
                                    }

                                    Rectangle {
                                        implicitHeight: 20
                                        implicitWidth: keyLbl.implicitWidth + 10
                                        radius: Theme.r(5)
                                        color: Theme.surfaceContainerHighest
                                        border.width: 1
                                        border.color: Theme.outlineVariant

                                        Text {
                                            id: keyLbl
                                            anchors.centerIn: parent
                                            text: bindCell.modelData.key
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: Theme.fgSurface
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
                                    font.pixelSize: 10
                                    color: Theme.fgSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }

            // Footer
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Customize bindings in Settings → Shortcuts · Super + / to toggle"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgSurfaceVariant
            }
        }
    }
}
