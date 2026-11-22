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
    property string activeCategory: "All"
    property string searchQuery: ""

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

    // --- 2. Keybinding Rows ---
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

                    // Keycap Pills
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

                    // Action & Target
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
