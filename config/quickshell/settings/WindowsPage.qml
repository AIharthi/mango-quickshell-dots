pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property bool sloppyFocus: true
    property bool warpCursor: true
    property bool focusOnActivate: true
    property bool newIsMaster: true
    property real masterFactor: 0.55
    property bool smartGaps: false
    property bool dragTileToTile: true
    property real scrollerProportion: 0.8
    property bool enableFloatingSnap: true
    property int snapDistance: 24

    function loadSettings(): void {
        if (!readProc.running)
            readProc.running = true;
    }

    function setSetting(key: string, val: var): void {
        if (key === "sloppy_focus")
            root.sloppyFocus = !!val;
        else if (key === "warp_cursor")
            root.warpCursor = !!val;
        else if (key === "focus_on_activate")
            root.focusOnActivate = !!val;
        else if (key === "new_is_master")
            root.newIsMaster = !!val;
        else if (key === "default_master_factor")
            root.masterFactor = Number(val);
        else if (key === "smart_gaps")
            root.smartGaps = !!val;
        else if (key === "drag_tile_to_tile")
            root.dragTileToTile = !!val;
        else if (key === "scroller_default_proportion")
            root.scrollerProportion = Number(val);
        else if (key === "enable_floating_snap")
            root.enableFloatingSnap = !!val;
        else if (key === "snap_distance")
            root.snapDistance = Math.round(Number(val));

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
                    if (typeof d.sloppy_focus === "boolean")
                        root.sloppyFocus = d.sloppy_focus;
                    if (typeof d.warp_cursor === "boolean")
                        root.warpCursor = d.warp_cursor;
                    if (typeof d.focus_on_activate === "boolean")
                        root.focusOnActivate = d.focus_on_activate;
                    if (typeof d.new_is_master === "boolean")
                        root.newIsMaster = d.new_is_master;
                    if (typeof d.default_master_factor === "number")
                        root.masterFactor = d.default_master_factor;
                    if (typeof d.smart_gaps === "boolean")
                        root.smartGaps = d.smart_gaps;
                    if (typeof d.drag_tile_to_tile === "boolean")
                        root.dragTileToTile = d.drag_tile_to_tile;
                    if (typeof d.scroller_default_proportion === "number")
                        root.scrollerProportion = d.scroller_default_proportion;
                    if (typeof d.enable_floating_snap === "boolean")
                        root.enableFloatingSnap = d.enable_floating_snap;
                    if (typeof d.snap_distance === "number")
                        root.snapDistance = d.snap_distance;
                } catch (err) {}
            }
        }
    }

    // --- 1. Focus & Cursor Behavior ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: focusCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: focusCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "FOCUS & CURSOR"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Focus Follows Mouse (Sloppy Focus)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.sloppyFocus
                    onToggled: root.setSetting("sloppy_focus", !root.sloppyFocus)
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Warp Cursor to Focused Window"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.warpCursor
                    onToggled: root.setSetting("warp_cursor", !root.warpCursor)
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Focus Window When Activated"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.focusOnActivate
                    onToggled: root.setSetting("focus_on_activate", !root.focusOnActivate)
                }
            }
        }
    }

    // --- 2. Tiling & Layout Defaults ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: tileCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: tileCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "TILING & LAYOUTS"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Open New Window as Master"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.newIsMaster
                    onToggled: root.setSetting("new_is_master", !root.newIsMaster)
                }
            }

            StepControl {
                label: "Master Area Ratio"
                displayValue: Math.round(root.masterFactor * 100) + "%"
                onDecremented: root.setSetting("default_master_factor", Number(Math.max(0.40, root.masterFactor - 0.05).toFixed(2)))
                onIncremented: root.setSetting("default_master_factor", Number(Math.min(0.75, root.masterFactor + 0.05).toFixed(2)))
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Smart Gaps (Hide When Single Window)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.smartGaps
                    onToggled: root.setSetting("smart_gaps", !root.smartGaps)
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Drag-to-Swap Tiled Windows"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.dragTileToTile
                    onToggled: root.setSetting("drag_tile_to_tile", !root.dragTileToTile)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 145
                    text: "Scroller Column Width"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { label: "50%",  val: 0.50 },
                        { label: "65%",  val: 0.65 },
                        { label: "80%",  val: 0.80 },
                        { label: "100%", val: 1.00 }
                    ]

                    delegate: Rectangle {
                        id: scrollerChip
                        required property var modelData
                        readonly property bool selected: Math.abs(root.scrollerProportion - scrollerChip.modelData.val) < 0.03

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: scrollerChip.selected
                            ? Theme.withAlpha(Theme.secondary, 0.22)
                            : (scMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: scrollerChip.selected ? 1 : Theme.cardBorderWidth
                        border.color: scrollerChip.selected ? Theme.secondary : Theme.cardBorder
                        scale: scMouse.pressed ? 0.95 : 1.0

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
                            text: scrollerChip.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: scrollerChip.selected ? Font.Bold : Font.Normal
                            color: scrollerChip.selected ? Theme.secondary : Theme.fgSurface
                        }

                        MouseArea {
                            id: scMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSetting("scroller_default_proportion", scrollerChip.modelData.val)
                        }
                    }
                }
            }
        }
    }

    // --- 3. Floating Windows ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: fltCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: fltCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "FLOATING WINDOWS"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Magnetic Edge Snapping"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.enableFloatingSnap
                    onToggled: root.setSetting("enable_floating_snap", !root.enableFloatingSnap)
                }
            }

            StepControl {
                label: "Snap Distance"
                displayValue: root.snapDistance + " px"
                controlEnabled: root.enableFloatingSnap
                onDecremented: root.setSetting("snap_distance", Math.max(8, root.snapDistance - 4))
                onIncremented: root.setSetting("snap_distance", Math.min(48, root.snapDistance + 4))
            }
        }
    }
}
