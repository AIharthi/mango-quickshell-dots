pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property var categories: []
    property var allBinds: []
    property var customBinds: []
    property string activeCategory: "All"
    property string searchQuery: ""

    property bool showAddForm: false
    property var newMods: ["SUPER"]
    property string newAction: "spawn"
    property string bindStatus: ""
    property bool bindError: false

    readonly property var filteredBinds: {
        const q = (root.searchQuery || "").trim().toLowerCase();
        const cat = root.activeCategory;
        const out = [];
        for (let i = 0; i < root.allBinds.length; i++) {
            const b = root.allBinds[i];
            if (cat !== "All" && b.category !== cat)
                continue;
            if (q.length > 0) {
                const hay = (b.category + " " + b.modsRaw + " " + b.key + " " + b.action + " " + b.arg).toLowerCase();
                if (hay.indexOf(q) === -1)
                    continue;
            }
            out.push(b);
        }
        return out;
    }

    function refresh(): void {
        if (!bindsProc.running)
            bindsProc.running = true;
        if (!customBindsProc.running)
            customBindsProc.running = true;
    }

    function toggleMod(modName: string): void {
        if (modName === "NONE") {
            root.newMods = ["NONE"];
            return;
        }
        let next = root.newMods.filter(m => m !== "NONE");
        if (next.indexOf(modName) !== -1) {
            next = next.filter(m => m !== modName);
            if (next.length === 0)
                next = ["SUPER"];
        } else {
            next.push(modName);
        }
        root.newMods = next;
    }

    function addCustomBind(keyStr: string, argStr: string): void {
        const k = (keyStr || "").trim();
        if (k.length === 0 || bindMutProc.running)
            return;
        const mods = root.newMods.join("+");
        const cmd = [Quickshell.shellPath("scripts/apply-local-setting.sh"), "bind-add", mods, k, root.newAction];
        if ((argStr || "").trim().length > 0)
            cmd.push(argStr.trim());
        root.bindError = false;
        root.bindStatus = "Validating with MangoWC...";
        bindMutProc.command = cmd;
        bindMutProc.running = true;
    }

    function removeCustomBind(rawLine: string): void {
        if (bindMutProc.running)
            return;
        root.bindError = false;
        bindMutProc.command = [Quickshell.shellPath("scripts/apply-local-setting.sh"), "bind-remove", rawLine];
        bindMutProc.running = true;
    }

    Component.onCompleted: refresh()

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
                    root.categories = Array.isArray(d.categories) ? d.categories : [];
                    root.allBinds = Array.isArray(d.binds) ? d.binds : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: customBindsProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "bind-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.customBinds = Array.isArray(d.customBinds) ? d.customBinds : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: bindMutProc
        stdout: StdioCollector {
            id: mutOut
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.customBinds = Array.isArray(d.customBinds) ? d.customBinds : [];
                } catch (err) {}
            }
        }
        stderr: StdioCollector {
            id: mutErr
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.bindError = true;
                root.bindStatus = (mutErr.text || "").trim().split("\n")[0] || "Conflict or invalid keybinding (rolled back)";
            } else {
                root.bindError = false;
                root.bindStatus = "Custom shortcut saved & active!";
                bindsProc.running = true;
            }
        }
    }

    // --- 1. Search & Category Filter ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: filterCol.implicitHeight + 22
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: filterCol
            anchors.fill: parent
            anchors.margins: 11
            spacing: 9

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: bindSearch.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: bindSearch.activeFocus ? Theme.primary : Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 6

                        Text {
                            text: "󰍉"
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: bindSearch.activeFocus ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 18

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Filter shortcuts by key, action, or app..."
                                visible: bindSearch.text.length === 0
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }

                            TextInput {
                                id: bindSearch
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                text: root.searchQuery
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgSurface
                                clip: true
                                onTextEdited: root.searchQuery = text
                            }
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: countBadge.implicitWidth + 16
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: countBadge
                        anchors.centerIn: parent
                        text: root.filteredBinds.length + " binds"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: addToggleLbl.implicitWidth + 16
                    radius: Theme.r(8)
                    color: root.showAddForm ? Theme.primary : Theme.subCardBg
                    border.width: root.showAddForm ? 1 : Theme.cardBorderWidth
                    border.color: root.showAddForm ? Theme.primary : Theme.cardBorder

                    Text {
                        id: addToggleLbl
                        anchors.centerIn: parent
                        text: root.showAddForm ? "Close Form" : "+ Add Custom"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: root.showAddForm ? Theme.fgPrimary : Theme.primary
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showAddForm = !root.showAddForm
                    }
                }
            }

            // Custom Shortcut Builder Form
            ColumnLayout {
                visible: root.showAddForm
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text { text: "Mods:"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgSurfaceVariant }

                    Repeater {
                        model: ["SUPER", "SHIFT", "CTRL", "ALT", "NONE"]
                        delegate: Rectangle {
                            id: modPick
                            required property string modelData
                            readonly property bool selected: root.newMods.indexOf(modPick.modelData) !== -1
                            implicitHeight: 22; implicitWidth: modPickTxt.implicitWidth + 10; radius: Theme.r(6)
                            color: modPick.selected ? Theme.withAlpha(Theme.primary, 0.22) : Theme.subCardBg
                            border.width: modPick.selected ? 1 : Theme.cardBorderWidth
                            border.color: modPick.selected ? Theme.primary : Theme.cardBorder
                            Text { id: modPickTxt; anchors.centerIn: parent; text: modPick.modelData; font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: modPick.selected ? Font.Bold : Font.Normal; color: modPick.selected ? Theme.primary : Theme.fgSurface }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMod(modPick.modelData) }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Repeater {
                        model: ["spawn", "spawn_shell", "toggleoverview", "switch_layout"]
                        delegate: Rectangle {
                            id: actPick
                            required property string modelData
                            readonly property bool selected: root.newAction === actPick.modelData
                            implicitHeight: 22; implicitWidth: actPickTxt.implicitWidth + 10; radius: Theme.r(6)
                            color: actPick.selected ? Theme.withAlpha(Theme.secondary, 0.22) : Theme.subCardBg
                            border.width: actPick.selected ? 1 : Theme.cardBorderWidth
                            border.color: actPick.selected ? Theme.secondary : Theme.cardBorder
                            Text { id: actPickTxt; anchors.centerIn: parent; text: actPick.modelData; font.family: Theme.fontFamily; font.pixelSize: 9; color: actPick.selected ? Theme.secondary : Theme.fgSurface }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.newAction = actPick.modelData }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 110; implicitHeight: 28; radius: Theme.r(8); color: Theme.subCardBg
                        border.width: keyIn.activeFocus ? 1 : Theme.cardBorderWidth; border.color: keyIn.activeFocus ? Theme.primary : Theme.cardBorder
                        Item {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Key (e.g. e, F5)"; visible: keyIn.text.length === 0; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgSurfaceVariant }
                            TextInput { id: keyIn; anchors.fill: parent; verticalAlignment: TextInput.AlignVCenter; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgSurface; clip: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 28; radius: Theme.r(8); color: Theme.subCardBg
                        border.width: argIn.activeFocus ? 1 : Theme.cardBorderWidth; border.color: argIn.activeFocus ? Theme.primary : Theme.cardBorder
                        Item {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Command / Argument (for spawn)"; visible: argIn.text.length === 0; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgSurfaceVariant }
                            TextInput { id: argIn; anchors.fill: parent; verticalAlignment: TextInput.AlignVCenter; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgSurface; clip: true }
                        }
                    }

                    Rectangle {
                        implicitHeight: 28; implicitWidth: saveBindLbl.implicitWidth + 14; radius: Theme.r(8); color: Theme.primary
                        Text { id: saveBindLbl; anchors.centerIn: parent; text: "Save Bind"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: Theme.fgPrimary }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.addCustomBind(keyIn.text, argIn.text)
                        }
                    }
                }

                Text {
                    visible: root.bindStatus.length > 0
                    text: root.bindStatus
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: root.bindError ? Theme.error : Theme.success
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 5

                Repeater {
                    model: ["All"].concat(root.categories)

                    delegate: Rectangle {
                        id: catPill
                        required property string modelData
                        readonly property bool selected: root.activeCategory === catPill.modelData

                        implicitHeight: 24
                        implicitWidth: catTxt.implicitWidth + 12
                        radius: Theme.r(7)
                        color: catPill.selected
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (catMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: catPill.selected ? 1 : Theme.cardBorderWidth
                        border.color: catPill.selected ? Theme.primary : Theme.cardBorder

                        Text {
                            id: catTxt
                            anchors.centerIn: parent
                            text: catPill.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: catPill.selected ? Font.Bold : Font.Medium
                            color: catPill.selected ? Theme.primary : Theme.fgSurface
                        }

                        MouseArea {
                            id: catMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeCategory = catPill.modelData
                        }
                    }
                }
            }
        }
    }

    // --- 2. Custom local.conf Shortcuts (removable) ---
    Rectangle {
        visible: root.customBinds.length > 0
        Layout.fillWidth: true
        implicitHeight: custCol.implicitHeight + 20
        radius: Theme.r(14)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: custCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Text { text: "YOUR CUSTOM SHORTCUTS (local.conf)"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: Theme.fgSurfaceVariant }

            Repeater {
                model: root.customBinds
                delegate: Rectangle {
                    id: cbRow
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: 30; radius: Theme.r(8); color: Theme.subCardBg
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 6; spacing: 8
                        Text { text: cbRow.modelData.raw; Layout.fillWidth: true; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.primary }
                        Rectangle {
                            implicitWidth: 20; implicitHeight: 20; radius: Theme.r(5)
                            color: delCbMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : "transparent"
                            Text { anchors.centerIn: parent; text: "󰆴"; font.family: Theme.iconFont; font.pixelSize: 11; color: delCbMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant }
                            MouseArea { id: delCbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.removeCustomBind(cbRow.modelData.raw) }
                        }
                    }
                }
            }
        }
    }

    // --- 3. All Keybinding Rows ---
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.filteredBinds

            delegate: Rectangle {
                id: bindRow
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: Math.max(38, bindRowLayout.implicitHeight + 12)
                radius: Theme.r(11)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                RowLayout {
                    id: bindRowLayout
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: 10

                    RowLayout {
                        Layout.preferredWidth: 230
                        spacing: 4

                        Repeater {
                            model: bindRow.modelData.mods

                            delegate: Rectangle {
                                id: modCap
                                required property string modelData
                                implicitHeight: 22
                                implicitWidth: modTxt.implicitWidth + 10
                                radius: Theme.r(6)
                                color: Theme.withAlpha(Theme.primary, 0.16)
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.primary, 0.35)

                                Text {
                                    id: modTxt
                                    anchors.centerIn: parent
                                    text: modCap.modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                }
                            }
                        }

                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: keyTxt.implicitWidth + 12
                            radius: Theme.r(6)
                            color: Theme.subCardBg
                            border.width: 1
                            border.color: Theme.outlineVariant

                            Text {
                                id: keyTxt
                                anchors.centerIn: parent
                                text: (bindRow.modelData.kind === "mouse" ? "󰍽 " : "") + bindRow.modelData.key
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: bindRow.modelData.arg && bindRow.modelData.arg.length > 0
                                ? (bindRow.modelData.action + "  ·  " + bindRow.modelData.arg)
                                : bindRow.modelData.action
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Text {
                            text: bindRow.modelData.category
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.fgSurfaceVariant
                        }
                    }
                }
            }
        }

        Text {
            visible: root.filteredBinds.length === 0
            text: "No shortcuts match that filter"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgSurfaceVariant
        }
    }
}
