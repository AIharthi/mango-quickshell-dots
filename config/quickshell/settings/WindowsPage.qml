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

    // Extended MangoWC layout & behavior flags
    property int defaultMasterCount: 1
    property bool centerMasterOverspread: false
    property bool monocleNoBorder: false
    property bool monocleNoGap: false
    property bool monocleNoRadius: false
    property bool noBorderWhenSingle: true
    property bool noRadiusWhenSingle: false
    property bool enableBorderResize: true
    property int borderResizeSize: 8
    property bool dwindleSmartSplit: true
    property bool dwindleSmartResize: false
    property bool scrollerFocusCenter: false
    property bool scrollerPreferCenter: false
    property bool scrollerPreferOverspread: false
    property real scrollerSingleProp: 1.0
    property bool focusCrossMonitor: false
    property bool focusCrossTag: false
    property bool exchangeCrossMonitor: true
    property bool scratchpadCrossMonitor: false
    property bool tagCarousel: true
    property bool enableHotarea: false
    property int hotareaSize: 10
    property int hotareaCorner: 1
    property bool hotareaDisableFullscreen: true
    property int overviewGapInner: 5
    property int overviewGapOuter: 30
    property bool allowTearing: false

    property var tagRules: ({ "1":"tile","2":"tile","3":"tile","4":"tile","5":"tile","6":"tile","7":"tile","8":"tile","9":"tile" })
    property var windowRules: []
    property string ruleStatus: ""
    property bool ruleFloating: true
    property bool ruleNoBlur: false
    property bool ruleNoShadow: false
    property string ruleTag: ""

    function loadSettings(): void {
        if (!readProc.running)
            readProc.running = true;
        if (!tagRulesProc.running)
            tagRulesProc.running = true;
        if (!winRulesProc.running)
            winRulesProc.running = true;
    }

    function setSetting(key: string, val: var): void {
        if (key === "sloppy_focus") root.sloppyFocus = !!val;
        else if (key === "warp_cursor") root.warpCursor = !!val;
        else if (key === "focus_on_activate") root.focusOnActivate = !!val;
        else if (key === "new_is_master") root.newIsMaster = !!val;
        else if (key === "default_master_factor") root.masterFactor = Number(val);
        else if (key === "smart_gaps") root.smartGaps = !!val;
        else if (key === "drag_tile_to_tile") root.dragTileToTile = !!val;
        else if (key === "scroller_default_proportion") root.scrollerProportion = Number(val);
        else if (key === "enable_floating_snap") root.enableFloatingSnap = !!val;
        else if (key === "snap_distance") root.snapDistance = Math.round(Number(val));
        else if (key === "default_master_count") root.defaultMasterCount = Math.round(Number(val));
        else if (key === "center_master_overspread") root.centerMasterOverspread = !!val;
        else if (key === "monocle_no_border") root.monocleNoBorder = !!val;
        else if (key === "monocle_no_gap") root.monocleNoGap = !!val;
        else if (key === "monocle_no_radius") root.monocleNoRadius = !!val;
        else if (key === "no_border_when_single") root.noBorderWhenSingle = !!val;
        else if (key === "no_radius_when_single") root.noRadiusWhenSingle = !!val;
        else if (key === "enable_border_resize") root.enableBorderResize = !!val;
        else if (key === "border_resize_size") root.borderResizeSize = Math.round(Number(val));
        else if (key === "dwindle_smart_split") root.dwindleSmartSplit = !!val;
        else if (key === "dwindle_smart_resize") root.dwindleSmartResize = !!val;
        else if (key === "scroller_focus_center") root.scrollerFocusCenter = !!val;
        else if (key === "scroller_prefer_center") root.scrollerPreferCenter = !!val;
        else if (key === "scroller_prefer_overspread") root.scrollerPreferOverspread = !!val;
        else if (key === "scroller_default_proportion_single") root.scrollerSingleProp = Number(val);
        else if (key === "focus_cross_monitor") root.focusCrossMonitor = !!val;
        else if (key === "focus_cross_tag") root.focusCrossTag = !!val;
        else if (key === "exchange_cross_monitor") root.exchangeCrossMonitor = !!val;
        else if (key === "scratchpad_cross_monitor") root.scratchpadCrossMonitor = !!val;
        else if (key === "tag_carousel") root.tagCarousel = !!val;
        else if (key === "enable_hotarea") root.enableHotarea = !!val;
        else if (key === "hotarea_size") root.hotareaSize = Math.round(Number(val));
        else if (key === "hotarea_corner") root.hotareaCorner = Math.round(Number(val));
        else if (key === "hotarea_disable_on_fullscreen") root.hotareaDisableFullscreen = !!val;
        else if (key === "overview_gap_inner") root.overviewGapInner = Math.round(Number(val));
        else if (key === "overview_gap_outer") root.overviewGapOuter = Math.round(Number(val));
        else if (key === "allow_tearing") root.allowTearing = !!val;

        const outVal = (typeof val === "boolean") ? (val ? "1" : "0") : String(val);
        Quickshell.execDetached([Quickshell.shellPath("scripts/apply-local-setting.sh"), "set", key, outVal]);
    }

    function setTagLayout(tagNum: string, layoutName: string): void {
        if (tagMutProc.running)
            return;
        tagMutProc.command = [Quickshell.shellPath("scripts/apply-local-setting.sh"), "tag-rule-set", tagNum, layoutName];
        tagMutProc.running = true;
    }

    function addWindowRule(appId: string): void {
        const cleanApp = (appId || "").trim();
        if (cleanApp.length === 0 || winMutProc.running)
            return;
        const parts = [];
        if (root.ruleFloating) parts.push("is_floating:1");
        if (root.ruleNoBlur) parts.push("no_blur:1");
        if (root.ruleNoShadow) parts.push("no_shadow:1");
        if (/^[1-9]$/.test(root.ruleTag.trim())) parts.push("tags:" + root.ruleTag.trim());
        parts.push("app_id:" + cleanApp);
        winMutProc.command = [Quickshell.shellPath("scripts/apply-local-setting.sh"), "window-rule-add", parts.join(",")];
        winMutProc.running = true;
    }

    function removeWindowRule(spec: string): void {
        if (winMutProc.running)
            return;
        winMutProc.command = [Quickshell.shellPath("scripts/apply-local-setting.sh"), "window-rule-remove", spec];
        winMutProc.running = true;
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
                    if (typeof d.enable_floating_snap === "boolean") root.enableFloatingSnap = d.enable_floating_snap;
                    if (typeof d.snap_distance === "number") root.snapDistance = d.snap_distance;
                    if (typeof d.default_master_count === "number") root.defaultMasterCount = d.default_master_count;
                    if (typeof d.center_master_overspread === "boolean") root.centerMasterOverspread = d.center_master_overspread;
                    if (typeof d.monocle_no_border === "boolean") root.monocleNoBorder = d.monocle_no_border;
                    if (typeof d.monocle_no_gap === "boolean") root.monocleNoGap = d.monocle_no_gap;
                    if (typeof d.monocle_no_radius === "boolean") root.monocleNoRadius = d.monocle_no_radius;
                    if (typeof d.no_border_when_single === "boolean") root.noBorderWhenSingle = d.no_border_when_single;
                    if (typeof d.no_radius_when_single === "boolean") root.noRadiusWhenSingle = d.no_radius_when_single;
                    if (typeof d.enable_border_resize === "boolean") root.enableBorderResize = d.enable_border_resize;
                    if (typeof d.border_resize_size === "number") root.borderResizeSize = d.border_resize_size;
                    if (typeof d.dwindle_smart_split === "boolean") root.dwindleSmartSplit = d.dwindle_smart_split;
                    if (typeof d.dwindle_smart_resize === "boolean") root.dwindleSmartResize = d.dwindle_smart_resize;
                    if (typeof d.scroller_focus_center === "boolean") root.scrollerFocusCenter = d.scroller_focus_center;
                    if (typeof d.scroller_prefer_center === "boolean") root.scrollerPreferCenter = d.scroller_prefer_center;
                    if (typeof d.scroller_prefer_overspread === "boolean") root.scrollerPreferOverspread = d.scroller_prefer_overspread;
                    if (typeof d.scroller_default_proportion_single === "number") root.scrollerSingleProp = d.scroller_default_proportion_single;
                    if (typeof d.focus_cross_monitor === "boolean") root.focusCrossMonitor = d.focus_cross_monitor;
                    if (typeof d.focus_cross_tag === "boolean") root.focusCrossTag = d.focus_cross_tag;
                    if (typeof d.exchange_cross_monitor === "boolean") root.exchangeCrossMonitor = d.exchange_cross_monitor;
                    if (typeof d.scratchpad_cross_monitor === "boolean") root.scratchpadCrossMonitor = d.scratchpad_cross_monitor;
                    if (typeof d.tag_carousel === "boolean") root.tagCarousel = d.tag_carousel;
                    if (typeof d.enable_hotarea === "boolean") root.enableHotarea = d.enable_hotarea;
                    if (typeof d.hotarea_size === "number") root.hotareaSize = d.hotarea_size;
                    if (typeof d.hotarea_corner === "number") root.hotareaCorner = d.hotarea_corner;
                    if (typeof d.hotarea_disable_on_fullscreen === "boolean") root.hotareaDisableFullscreen = d.hotarea_disable_on_fullscreen;
                    if (typeof d.overview_gap_inner === "number") root.overviewGapInner = d.overview_gap_inner;
                    if (typeof d.overview_gap_outer === "number") root.overviewGapOuter = d.overview_gap_outer;
                    if (typeof d.allow_tearing === "boolean") root.allowTearing = d.allow_tearing;
                } catch (err) {}
            }
        }
    }

    Process {
        id: tagRulesProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "tag-rules-get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (d && d["1"]) root.tagRules = d;
                } catch (err) {}
            }
        }
    }

    Process {
        id: tagMutProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (d && d["1"]) root.tagRules = d;
                } catch (err) {}
            }
        }
    }

    Process {
        id: winRulesProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "window-rules-get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.windowRules = Array.isArray(d.rules) ? d.rules : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: winMutProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.windowRules = Array.isArray(d.rules) ? d.rules : [];
                    root.ruleStatus = "Rule list synced & verified with mango -p";
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

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Allow Border Drag Resizing"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: root.enableBorderResize; onToggled: root.setSetting("enable_border_resize", !root.enableBorderResize) }
            }

            StepControl {
                label: "Border Resize Hitbox Size"
                displayValue: root.borderResizeSize + " px"
                controlEnabled: root.enableBorderResize
                onDecremented: root.setSetting("border_resize_size", Math.max(2, root.borderResizeSize - 2))
                onIncremented: root.setSetting("border_resize_size", Math.min(24, root.borderResizeSize + 2))
            }
        }
    }

    // --- 4. Extended Layout, Scroller, Overview & Hotarea ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: extCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: extCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "EXTENDED LAYOUT, CROSS-MONITOR & HOT CORNERS"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            StepControl {
                label: "Default Master Window Count"
                displayValue: String(root.defaultMasterCount)
                onDecremented: root.setSetting("default_master_count", Math.max(1, root.defaultMasterCount - 1))
                onIncremented: root.setSetting("default_master_count", Math.min(5, root.defaultMasterCount + 1))
            }

            StepControl {
                label: "Scroller Single-Window Proportion"
                displayValue: Math.round(root.scrollerSingleProp * 100) + "%"
                accentColor: Theme.secondary
                onDecremented: root.setSetting("scroller_default_proportion_single", Number(Math.max(0.40, root.scrollerSingleProp - 0.1).toFixed(2)))
                onIncremented: root.setSetting("scroller_default_proportion_single", Number(Math.min(1.00, root.scrollerSingleProp + 0.1).toFixed(2)))
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Scroller Center Focus / Prefer Center"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: root.scrollerFocusCenter; onToggled: root.setSetting("scroller_focus_center", !root.scrollerFocusCenter) }
                ToggleSwitch { checked: root.scrollerPreferCenter; activeColor: Theme.secondary; onToggled: root.setSetting("scroller_prefer_center", !root.scrollerPreferCenter) }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Dwindle Smart Split & Smart Resize"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: root.dwindleSmartSplit; onToggled: root.setSetting("dwindle_smart_split", !root.dwindleSmartSplit) }
                ToggleSwitch { checked: root.dwindleSmartResize; activeColor: Theme.secondary; onToggled: root.setSetting("dwindle_smart_resize", !root.dwindleSmartResize) }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Center-Master Overspread & No-Border Single"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: root.centerMasterOverspread; onToggled: root.setSetting("center_master_overspread", !root.centerMasterOverspread) }
                ToggleSwitch { checked: root.noBorderWhenSingle; activeColor: Theme.secondary; onToggled: root.setSetting("no_border_when_single", !root.noBorderWhenSingle) }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Monocle Clean Mode (Hide Border / Gap / Radius)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch {
                    checked: root.monocleNoBorder && root.monocleNoGap && root.monocleNoRadius
                    onToggled: {
                        const nxt = !(root.monocleNoBorder && root.monocleNoGap && root.monocleNoRadius);
                        root.setSetting("monocle_no_border", nxt);
                        root.setSetting("monocle_no_gap", nxt);
                        root.setSetting("monocle_no_radius", nxt);
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Focus Cross-Monitor & Cross-Tag"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: root.focusCrossMonitor; onToggled: root.setSetting("focus_cross_monitor", !root.focusCrossMonitor) }
                ToggleSwitch { checked: root.focusCrossTag; activeColor: Theme.secondary; onToggled: root.setSetting("focus_cross_tag", !root.focusCrossTag) }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Tag Carousel Loop & Exchange Cross-Monitor"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: root.tagCarousel; onToggled: root.setSetting("tag_carousel", !root.tagCarousel) }
                ToggleSwitch { checked: root.exchangeCrossMonitor; activeColor: Theme.secondary; onToggled: root.setSetting("exchange_cross_monitor", !root.exchangeCrossMonitor) }
            }

            StepControl {
                label: "Overview Mode Inner / Outer Gap"
                displayValue: root.overviewGapInner + " / " + root.overviewGapOuter + " px"
                onDecremented: {
                    root.setSetting("overview_gap_inner", Math.max(0, root.overviewGapInner - 2));
                    root.setSetting("overview_gap_outer", Math.max(0, root.overviewGapOuter - 4));
                }
                onIncremented: {
                    root.setSetting("overview_gap_inner", Math.min(36, root.overviewGapInner + 2));
                    root.setSetting("overview_gap_outer", Math.min(60, root.overviewGapOuter + 4));
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Enable Overview Hot Corner (Hotarea)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: root.enableHotarea; onToggled: root.setSetting("enable_hotarea", !root.enableHotarea) }
            }

            StepControl {
                label: "Hotarea Size & Disable Fullscreen"
                displayValue: root.hotareaSize + " px (c" + root.hotareaCorner + ")"
                controlEnabled: root.enableHotarea
                onDecremented: root.setSetting("hotarea_size", Math.max(4, root.hotareaSize - 2))
                onIncremented: root.setSetting("hotarea_size", Math.min(40, root.hotareaSize + 2))
            }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Allow Fullscreen Screen Tearing (Lowest Gaming Latency)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: root.allowTearing; activeColor: Theme.warning; onToggled: root.setSetting("allow_tearing", !root.allowTearing) }
            }
        }
    }

    // --- 5. Per-Tag Default Layouts (Tags 1-9) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: tagRuleCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: tagRuleCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "PER-WORKSPACE DEFAULT LAYOUTS (TAG RULES)"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

                delegate: RowLayout {
                    id: tRow
                    required property string modelData
                    readonly property string curLayout: root.tagRules[tRow.modelData] || "tile"

                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        Layout.preferredWidth: 52
                        text: "Tag " + tRow.modelData
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Repeater {
                        model: ["tile", "scroller", "dwindle", "grid", "monocle", "deck", "center_tile"]

                        delegate: Rectangle {
                            id: lChip
                            required property string modelData
                            readonly property bool selected: tRow.curLayout === lChip.modelData

                            implicitHeight: 22
                            implicitWidth: lTxt.implicitWidth + 10
                            radius: Theme.r(6)
                            color: lChip.selected ? Theme.withAlpha(Theme.primary, 0.22) : Theme.subCardBg
                            border.width: lChip.selected ? 1 : Theme.cardBorderWidth
                            border.color: lChip.selected ? Theme.primary : Theme.cardBorder

                            Text {
                                id: lTxt
                                anchors.centerIn: parent
                                text: lChip.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: lChip.selected ? Font.Bold : Font.Normal
                                color: lChip.selected ? Theme.primary : Theme.fgSurface
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setTagLayout(tRow.modelData, lChip.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 6. Custom Window Rules ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: winRuleCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: winRuleCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "CUSTOM WINDOW RULES (window_rule IN local.conf)"
                font.family: Theme.fontFamily
                font.pixelSize: 10
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
                    border.width: appIdIn.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: appIdIn.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "App ID / Class (e.g. pavucontrol, mpv, steam)..."
                            visible: appIdIn.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: appIdIn
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurface
                            clip: true
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: 64
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Tag 1-9"
                            visible: tagIn.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: tagIn
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.ruleTag
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurface
                            onTextEdited: root.ruleTag = text
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: addWrLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: addWrMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                    Text {
                        id: addWrLbl
                        anchors.centerIn: parent
                        text: "Add Rule"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        id: addWrMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.addWindowRule(appIdIn.text);
                            appIdIn.text = "";
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        { id: "flt",  label: "Floating" },
                        { id: "blur", label: "No Blur" },
                        { id: "shd",  label: "No Shadow" }
                    ]

                    delegate: Rectangle {
                        id: wrFlagChip
                        required property var modelData
                        readonly property bool active: wrFlagChip.modelData.id === "flt"
                            ? root.ruleFloating
                            : (wrFlagChip.modelData.id === "blur" ? root.ruleNoBlur : root.ruleNoShadow)

                        implicitHeight: 22
                        implicitWidth: wrFlTxt.implicitWidth + 12
                        radius: Theme.r(6)
                        color: wrFlagChip.active ? Theme.withAlpha(Theme.secondary, 0.22) : Theme.subCardBg
                        border.width: wrFlagChip.active ? 1 : Theme.cardBorderWidth
                        border.color: wrFlagChip.active ? Theme.secondary : Theme.cardBorder

                        Text {
                            id: wrFlTxt
                            anchors.centerIn: parent
                            text: wrFlagChip.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: wrFlagChip.active ? Theme.secondary : Theme.fgSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (wrFlagChip.modelData.id === "flt") root.ruleFloating = !root.ruleFloating;
                                else if (wrFlagChip.modelData.id === "blur") root.ruleNoBlur = !root.ruleNoBlur;
                                else root.ruleNoShadow = !root.ruleNoShadow;
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: root.ruleStatus.length > 0
                    text: root.ruleStatus
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    color: Theme.success
                }
            }

            Repeater {
                model: root.windowRules

                delegate: Rectangle {
                    id: wrRow
                    required property string modelData
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "window_rule=" + wrRow.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurface
                        }

                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: 20
                            radius: Theme.r(5)
                            color: delWrMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰆴"
                                font.family: Theme.iconFont
                                font.pixelSize: 11
                                color: delWrMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: delWrMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeWindowRule(wrRow.modelData)
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.windowRules.length === 0
                text: "No custom window rules configured in local.conf"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgSurfaceVariant
            }
        }
    }
}
