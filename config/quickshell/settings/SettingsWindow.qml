pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

PanelWindow {
    id: root

    property bool isOpen: true
    property string activePage: "appearance"
    property bool _entered: false
    readonly property bool shown: root.isOpen && root._entered

    signal pageSelected(string page)
    signal closeRequested()

    property string searchQuery: ""
    property bool resetMenuOpen: false
    property bool confirmFactoryReset: false

    Timer {
        id: drawerConfirmTimer
        interval: 4000
        repeat: false
        onTriggered: root.confirmFactoryReset = false
    }

    Component.onCompleted: Qt.callLater(() => {
        root._entered = true;
        if (root.isOpen)
            settingsFocusScope.forceActiveFocus();
    })
    onIsOpenChanged: {
        if (isOpen) {
            Qt.callLater(() => settingsFocusScope.forceActiveFocus());
        } else {
            searchQuery = "";
            resetMenuOpen = false;
            confirmFactoryReset = false;
        }
    }

    readonly property var navItems: {
        const items = [
            { id: "appearance", label: "Appearance",    icon: "󰏘", source: "AppearancePage.qml",    sub: "Modes, surfaces, island shape, fonts, cursor, GTK & blur" },
            { id: "themes",     label: "Themes & Colors",icon: "󰌁", source: "ThemesPage.qml",       sub: "Vibes, 16 presets, Matugen, seed hex, custom themes & wallpapers" },
            { id: "shell",      label: "Shell & Bar",   icon: "󰕮", source: "ShellPage.qml",         sub: "Dynamic Island, Simple Bar, screenshots & motion" },
            { id: "windows",    label: "Windows",       icon: "󰖲", source: "WindowsPage.qml",       sub: "Picture-in-Picture (PiP), tiling layouts, tag & window rules" }
        ];
        if (DeviceCaps.hasAudio)
            items.push({ id: "audio", label: "Audio", icon: "󰋋", source: "AudioPage.qml", sub: "Volume, card profiles, per-app mixer & test" });
        if (DeviceCaps.hasWlrRandr)
            items.push({ id: "displays", label: "Displays", icon: "󰍹", source: "DisplayPage.qml", sub: "Resolution, layout, rotation, VRR & brightness" });
        if (DeviceCaps.hasNetwork || DeviceCaps.hasWifi)
            items.push({ id: "network", label: "Network", icon: "󰤨", source: "NetworkPage.qml", sub: "Interfaces, IP/DNS & Wi-Fi connections" });
        if (DeviceCaps.hasBluetooth)
            items.push({ id: "bluetooth", label: "Bluetooth", icon: "󰂯", source: "BluetoothPage.qml", sub: "Adapter power & paired devices" });
        items.push({ id: "input", label: "Input", icon: "󰌌", source: "InputPage.qml", sub: "Keyboard, pointer speed, scroll & touchpad" });
        if (DeviceCaps.hasFoot || DeviceCaps.hasKitty)
            items.push({ id: "terminals", label: "Terminals", icon: "󰆍", source: "TerminalPage.qml", sub: "Foot & Kitty opacity, padding, cursor & scrollback" });
        items.push({ id: "notifications", label: "Notifications", icon: "󰂚", source: "NotificationsPage.qml", sub: "Do Not Disturb, alerts, duration & history" });
        items.push({ id: "apps",          label: "Apps & Startup",icon: "󰀻", source: "AppsPage.qml",          sub: "Default apps, hidden launcher apps, env & startup" });
        items.push({ id: "shortcuts",     label: "Shortcuts",     icon: "󰌌", source: "ShortcutsPage.qml",     sub: "View, filter & add MangoWC shortcuts" });
        items.push({ id: "privacy",       label: "Privacy",       icon: "󰌾", source: "PrivacyPage.qml",       sub: "Clipboard, history tracking, camera, mic & lock" });
        items.push({ id: "monitor",       label: "Monitor",       icon: "󰍛", source: "MonitorPage.qml",       sub: "Temperatures, running processes & services" });
        items.push({ id: "system",        label: "System",        icon: "󰋼", source: "SystemPage.qml",        sub: "User, clock, storage, backup & local.conf" });
        return items;
    }

    readonly property var searchIndex: [
        { label: "One-Click Aesthetic Vibes",  pageId: "themes",        keywords: "vibe aurora glass minimal square oled stealth neon cyber cozy paper full dock bar gruvbox dracula notch" },
        { label: "16 Curated Theme Presets",   pageId: "themes",        keywords: "preset catppuccin tokyo night gruvbox nord rose pine dracula everforest kanagawa solarized one dark ayu oxocarbon synthwave oled sakura cyberpunk dark light" },
        { label: "Seed Accent Color Generator",pageId: "themes",        keywords: "seed accent hex rgb material you color generator solid wallpaper" },
        { label: "Wallpaper Studio & Matugen", pageId: "themes",        keywords: "wallpaper random solid dominant source color matugen extraction lightness prefer contrast tonal expressive vibrant monochrome rainbow" },
        { label: "Live Palette & Custom Themes",pageId: "themes",       keywords: "custom theme palette slot primary secondary surface outline error export import json save" },
        { label: "MangoWC Border & Shadow Colors",pageId: "themes",     keywords: "focus color border color colored shadow tint shadow opacity dim strength mango theme" },
        { label: "Shell Modes & Surface Finish",pageId: "appearance",   keywords: "mode simple blur surface style default glass frosted oled flat tinted panel opacity card opacity roundness border glow width" },
        { label: "Dynamic Island Shape & Scale",pageId: "appearance",   keywords: "island style floating pill top notch full-width bar pill height top margin ui text font scale" },
        { label: "Wallpaper Transitions",      pageId: "appearance",    keywords: "wallpaper transition effect speed duration resize fps grow wipe fade wave outer awww swww" },
        { label: "GTK & Icon Theme",           pageId: "appearance",    keywords: "gtk icon theme hinting antialiasing rgba cursor blink text scale" },
        { label: "UI & Terminal Font",         pageId: "appearance",    keywords: "font typography family size jetbrains mono foot kitty gtk" },
        { label: "Cursor Theme & Size",        pageId: "appearance",    keywords: "cursor pointer size theme hide" },
        { label: "Dynamic Island & Pill",      pageId: "shell",         keywords: "island hover delay collapse media spin equalizer osd pill" },
        { label: "Bar & Hub UI Designs",       pageId: "shell",         keywords: "bar ui style hub layout cupertino control center split islands sequoia menu bar stage cockpit bento apple capsule" },
        { label: "Bar Widgets & Modules",      pageId: "shell",         keywords: "bar widgets modules date active window title workspaces tags layout cpu ram volume mute keyboard layout tray quick icons files battery presets minimal balanced full" },
        { label: "Dynamic File Manager (Rust)",pageId: "shell",         keywords: "file manager files rust explorer miller columns dual pane grid preview customize bar icon" },
        { label: "Simple Bar & Screenshots",   pageId: "shell",         keywords: "bar height top bottom layout screenshot grim slurp clipboard delay screen record video weather slideshow" },
        { label: "Weather & Wallpaper Slideshow", pageId: "shell",      keywords: "weather wttr city temperature celsius fahrenheit bar slideshow rotate wallpaper" },
        { label: "Accessibility & Motion",     pageId: "shell",         keywords: "reduced motion animations high contrast borders a11y" },
        { label: "Reset & Factory Recovery",   pageId: "system",        keywords: "reset restore undo default factory recovery reset appearance reset bar" },
        { label: "Picture-in-Picture (PiP)",   pageId: "windows",       keywords: "pip picture in picture video youtube float sticky global overlay corner bottom right top left firefox helium chrome discord popout" },
        { label: "Tiling, Hotarea & Overview", pageId: "windows",       keywords: "tiling scroller master gaps snap floating focus warp monocle hotarea tearing overview" },
        { label: "Per-Tag & Window Rules",     pageId: "windows",       keywords: "tag_rule window_rule workspace default layout floating rule app_id" },
        { label: "Output, Mic & 150% Boost",   pageId: "audio",         keywords: "audio sound volume mute speaker headphone microphone sink over amplification boost" },
        { label: "Card Profiles & Speaker Test",pageId: "audio",        keywords: "card profile hdmi analog left right stereo speaker test" },
        { label: "Per-App Volume Mixer",       pageId: "audio",         keywords: "app application mixer stream sink-input firefox mpv spotify" },
        { label: "Resolution, Position & VRR", pageId: "displays",      keywords: "display monitor screen resolution hz refresh scale rotate 90 180 270 vrr left right above below" },
        { label: "Brightness & Night Light",   pageId: "displays",      keywords: "backlight ddcutil brightness night light warmth kelvin" },
        { label: "Ethernet, IP, DNS & Wi-Fi",  pageId: "network",       keywords: "network ethernet ip gateway dns nmcli wifi wireless ssid password" },
        { label: "Bluetooth Devices",          pageId: "bluetooth",     keywords: "bluetooth pair connect audio device" },
        { label: "Keyboard, Mouse & Touchpad", pageId: "input",         keywords: "keyboard model layout repeat sandbox mouse left handed middle click scroll touchpad" },
        { label: "Foot & Kitty Settings",      pageId: "terminals",     keywords: "terminal foot kitty opacity alpha padding cursor blink scrollback" },
        { label: "DND, Critical & Sounds",     pageId: "notifications", keywords: "notification dnd do not disturb critical sound history clear test alerts calendar timer" },
        { label: "Defaults, Hidden Apps & Env",pageId: "apps",          keywords: "default browser terminal editor hidden apps launcher startup autostart exec_once env" },
        { label: "Shortcuts & Custom Binds",   pageId: "shortcuts",     keywords: "shortcut keybind hotkeys super mod mousebind custom bind cheat sheet" },
        { label: "Clipboard, Idle Lock & SDDM",    pageId: "privacy",   keywords: "privacy clipboard history clear middle paste recent files camera microphone lock idle timeout suspend sddm greeter login sync" },
        { label: "Sensors, Processes & Init",  pageId: "monitor",       keywords: "temp temperature cpu gpu process pid kill openrc systemd services" },
        { label: "User, Clock & Backup",       pageId: "system",        keywords: "user account clock 24h seconds date format keep awake disk storage backup export reset" }
    ]

    readonly property var searchMatches: {
        const q = (root.searchQuery || "").trim().toLowerCase();
        if (q.length === 0)
            return [];
        const availableIds = {};
        for (let i = 0; i < root.navItems.length; i++)
            availableIds[root.navItems[i].id] = true;
        const hits = [];
        for (let i = 0; i < root.searchIndex.length; i++) {
            const entry = root.searchIndex[i];
            if (!availableIds[entry.pageId])
                continue;
            const hay = (entry.label + " " + entry.keywords + " " + entry.pageId).toLowerCase();
            if (hay.indexOf(q) !== -1)
                hits.push(entry);
        }
        return hits;
    }

    readonly property int currentNavIndex: {
        for (let i = 0; i < navItems.length; i++) {
            if (navItems[i].id === root.activePage)
                return i;
        }
        return 0;
    }

    readonly property var currentNavItem: navItems[currentNavIndex]
    readonly property string resolvedPage: currentNavItem.id
    readonly property string pageSource: currentNavItem.source

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-settings"
    WlrLayershell.keyboardFocus: root.isOpen
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    FocusScope {
        id: settingsFocusScope
        anchors.fill: parent
        focus: root.isOpen

        Keys.onEscapePressed: root.closeRequested()

        // Dimmed scrim backdrop (click outside to close)
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, Theme.isSimple ? 0.56 : 0.44)
            opacity: root.shown ? 1.0 : 0.0

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.isOpen
                onClicked: root.closeRequested()
            }
        }

        // Centered Settings Dialog
        ClippingRectangle {
            id: dialog
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 940)
            height: Math.min(parent.height - 40, 640)
            radius: Theme.r(22)
            color: Theme.notchBg
            contentUnderBorder: false
            contentInsideBorder: true
            border.width: Theme.islandBorderWidth
            border.color: Theme.islandBorder

            opacity: root.shown ? 1.0 : 0.0
            scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.96)

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            // Eat clicks inside dialog so backdrop MouseArea does not close it
            MouseArea {
                anchors.fill: parent
            }

            // Subtle glass specular top sheen in Blur Mode
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 48
                radius: dialog.radius
                visible: Theme.showGlassSheen
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.30) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // --- Left Navigation Sidebar ---
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 204
                    topLeftRadius: Math.max(0, dialog.radius - dialog.border.width)
                    bottomLeftRadius: Math.max(0, dialog.radius - dialog.border.width)
                    topRightRadius: 0
                    bottomRightRadius: 0
                    color: Theme.isSimple ? Theme.surfaceContainerLow : Theme.withAlpha(Theme.surfaceContainerLow, Theme.isBlur ? 0.45 : 0.72)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        // App Title & Device Chip
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            RowLayout {
                                spacing: 8

                                Text {
                                    text: "󰒓"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 16
                                    color: Theme.primary
                                }

                                Text {
                                    text: "Settings"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 24
                                radius: Theme.r(8)
                                color: Theme.subCardBg
                                border.width: Theme.cardBorderWidth
                                border.color: Theme.cardBorder

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        text: DeviceCaps.deviceType === "laptop" ? "󰌢" : "󰍹"
                                        font.family: Theme.iconFont
                                        font.pixelSize: 12
                                        color: Theme.secondary
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (DeviceCaps.deviceType === "laptop" ? "Laptop" : "Desktop")
                                            + (DeviceCaps.hostname.length > 0 ? (" · " + DeviceCaps.hostname) : "")
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        color: Theme.fgSurfaceVariant
                                    }
                                }
                            }
                        }

                        // Search Bar (jump directly to any setting group)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: Theme.r(8)
                            color: Theme.subCardBg
                            border.width: searchInput.activeFocus ? 1 : Theme.cardBorderWidth
                            border.color: searchInput.activeFocus ? Theme.primary : Theme.cardBorder

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 6

                                Text {
                                    text: "󰍉"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 12
                                    color: searchInput.activeFocus ? Theme.primary : Theme.fgSurfaceVariant
                                }

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 18

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Search settings..."
                                        visible: searchInput.text.length === 0
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.fgSurfaceVariant
                                    }

                                    TextInput {
                                        id: searchInput
                                        anchors.fill: parent
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: root.searchQuery
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.fgSurface
                                        clip: true
                                        selectByMouse: true
                                        onTextEdited: root.searchQuery = text
                                        Keys.onEscapePressed: event => {
                                            if (text.length > 0) {
                                                root.searchQuery = "";
                                                event.accepted = true;
                                            } else {
                                                root.closeRequested();
                                                event.accepted = true;
                                            }
                                        }
                                        Keys.onReturnPressed: {
                                            if (root.searchMatches.length > 0) {
                                                root.pageSelected(root.searchMatches[0].pageId);
                                                root.searchQuery = "";
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: root.searchQuery.length > 0
                                    implicitWidth: 18
                                    implicitHeight: 18
                                    radius: Theme.r(6)
                                    color: clearSearchMouse.containsMouse ? Theme.hoverBg : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        font.family: Theme.iconFont
                                        font.pixelSize: 10
                                        color: Theme.fgSurfaceVariant
                                    }

                                    MouseArea {
                                        id: clearSearchMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.searchQuery = ""
                                    }
                                }
                            }
                        }

                        // Search Results OR Scrollable Category Navigation
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: width
                            contentHeight: root.searchQuery.trim().length > 0 ? searchCol.implicitHeight : navHost.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: searchCol
                                visible: root.searchQuery.trim().length > 0
                                width: parent.width
                                spacing: 4

                                Text {
                                    visible: root.searchMatches.length === 0
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    text: "No matching setting"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.fgSurfaceVariant
                                }

                                Repeater {
                                    model: root.searchMatches

                                    delegate: Rectangle {
                                        id: hitBtn
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 38
                                        radius: Theme.r(9)
                                        color: hitMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                                        border.width: Theme.cardBorderWidth
                                        border.color: Theme.cardBorder

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 9
                                            anchors.rightMargin: 9
                                            anchors.topMargin: 5
                                            anchors.bottomMargin: 5
                                            spacing: 1

                                            Text {
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                text: hitBtn.modelData.label
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: Theme.fgSurface
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                text: "in " + hitBtn.modelData.pageId
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 9
                                                color: Theme.primary
                                            }
                                        }

                                        MouseArea {
                                            id: hitMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.pageSelected(hitBtn.modelData.pageId);
                                                root.searchQuery = "";
                                            }
                                        }
                                    }
                                }
                            }

                            // Dynamic Navigation Links with Sliding Selection Indicator
                            Item {
                                id: navHost
                                visible: root.searchQuery.trim().length === 0
                                width: parent.width
                                implicitHeight: navCol.implicitHeight

                                Rectangle {
                                    id: navIndicator
                                    x: 0
                                    y: root.currentNavIndex * 38
                                    width: parent.width
                                    height: 34
                                    radius: Theme.r(10)
                                    color: Theme.primary
                                    border.width: Theme.isSimple ? 1 : 0
                                    border.color: Theme.primary

                                    Behavior on y {
                                        enabled: !Theme.reducedMotion
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                }

                                ColumnLayout {
                                    id: navCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 4

                                    Repeater {
                                        model: root.navItems

                                        delegate: Rectangle {
                                            id: navBtn
                                            required property var modelData
                                            readonly property bool isSelected: root.resolvedPage === navBtn.modelData.id

                                            Layout.fillWidth: true
                                            implicitHeight: 34
                                            radius: Theme.r(10)
                                            color: (!navBtn.isSelected && navMouse.containsMouse) ? Theme.hoverBg : "transparent"
                                            scale: navMouse.pressed ? 0.97 : 1.0

                                            Behavior on color {
                                                enabled: !Theme.isSimple
                                                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                                            }
                                            Behavior on scale {
                                                enabled: !Theme.isSimple
                                                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 9

                                                Text {
                                                    text: navBtn.modelData.icon
                                                    font.family: Theme.iconFont
                                                    font.pixelSize: 14
                                                    color: navBtn.isSelected ? Theme.fgPrimary : Theme.fgSurfaceVariant

                                                    Behavior on color {
                                                        enabled: !Theme.isSimple
                                                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: navBtn.modelData.label
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: navBtn.isSelected ? Font.Bold : Font.Medium
                                                    color: navBtn.isSelected ? Theme.fgPrimary : Theme.fgSurface

                                                    Behavior on color {
                                                        enabled: !Theme.isSimple
                                                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: navMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.pageSelected(navBtn.modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Sidebar Reset Drawer (always accessible if a tweak goes wrong)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: rstDrawerCol.implicitHeight + 10
                            radius: Theme.r(9)
                            color: Theme.subCardBg
                            border.width: Theme.cardBorderWidth
                            border.color: root.resetMenuOpen ? Theme.warning : Theme.cardBorder

                            ColumnLayout {
                                id: rstDrawerCol
                                anchors.fill: parent
                                anchors.margins: 5
                                spacing: 4

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(7)
                                    color: rstToggleMouse.containsMouse ? Theme.hoverBg : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        Text {
                                            text: "󰑐"
                                            font.family: Theme.iconFont
                                            font.pixelSize: 11
                                            color: Theme.warning
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Reset Settings"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: Theme.fgSurface
                                        }

                                        Text {
                                            text: root.resetMenuOpen ? "󰅃" : "󰅀"
                                            font.family: Theme.iconFont
                                            font.pixelSize: 11
                                            color: Theme.fgSurfaceVariant
                                        }
                                    }

                                    MouseArea {
                                        id: rstToggleMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.resetMenuOpen = !root.resetMenuOpen;
                                            if (!root.resetMenuOpen)
                                                root.confirmFactoryReset = false;
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: root.resetMenuOpen
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(6)
                                    color: sbRstAppMouse.containsMouse ? Theme.withAlpha(Theme.warning, 0.20) : Theme.cardBg

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Appearance & Theme"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                        color: Theme.warning
                                    }

                                    MouseArea {
                                        id: sbRstAppMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            ShellState.resetAppearance();
                                            root.resetMenuOpen = false;
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: root.resetMenuOpen
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(6)
                                    color: sbRstBarMouse.containsMouse ? Theme.withAlpha(Theme.secondary, 0.20) : Theme.cardBg

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Bar & Shell"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                        color: Theme.secondary
                                    }

                                    MouseArea {
                                        id: sbRstBarMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            ShellState.resetBar();
                                            root.resetMenuOpen = false;
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: root.resetMenuOpen
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(6)
                                    color: root.confirmFactoryReset
                                        ? Theme.error
                                        : (sbRstAllMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.20) : Theme.cardBg)

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.confirmFactoryReset ? "Confirm Factory?" : "Factory Reset All"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: root.confirmFactoryReset ? Theme.fgError : Theme.error
                                    }

                                    MouseArea {
                                        id: sbRstAllMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.confirmFactoryReset) {
                                                root.confirmFactoryReset = true;
                                                drawerConfirmTimer.restart();
                                                return;
                                            }
                                            root.confirmFactoryReset = false;
                                            drawerConfirmTimer.stop();
                                            ShellState.resetAllSettings();
                                            root.resetMenuOpen = false;
                                        }
                                    }
                                }
                            }
                        }

                        // Active Mode Pill in Footer
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: Theme.r(9)
                            color: Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 6

                                Text {
                                    text: "Mode:"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.fgSurfaceVariant
                                }

                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    text: Theme.shellMode.toUpperCase()
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                }
                            }
                        }
                    }
                }

                // Vertical Hairline Divider
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    color: Theme.isSimple ? Theme.outlineVariant : Theme.withAlpha(Theme.outlineVariant, 0.45)
                }

                // --- Right Content Area ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // Page Header
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 16
                        Layout.bottomMargin: 10
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: root.currentNavItem.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            Text {
                                text: root.currentNavItem.sub
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: Theme.r(14)
                            color: closeBtnMouse.containsMouse
                                ? Theme.withAlpha(Theme.error, 0.22)
                                : Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder
                            scale: closeBtnMouse.pressed ? 0.90 : 1.0

                            Behavior on color {
                                enabled: !Theme.isSimple
                                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                            Behavior on scale {
                                enabled: !Theme.isSimple
                                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                font.family: Theme.iconFont
                                font.pixelSize: 13
                                color: closeBtnMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: closeBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeRequested()
                            }
                        }
                    }

                    // Horizontal Hairline Divider
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.isSimple ? Theme.outlineVariant : Theme.withAlpha(Theme.outlineVariant, 0.35)
                    }

                    // Scrollable Page Container with Animated Page Entry
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 16

                        Flickable {
                            id: scrollFlick
                            anchors.fill: parent
                            clip: true
                            contentWidth: width
                            contentHeight: pageLoader.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            Loader {
                                id: pageLoader
                                width: scrollFlick.width
                                source: root.pageSource

                                NumberAnimation {
                                    id: pageEnterAnim
                                    target: pageLoader
                                    property: "opacity"
                                    from: 0.0
                                    to: 1.0
                                    duration: 110
                                    easing.type: Easing.OutCubic
                                }

                                onLoaded: {
                                    scrollFlick.contentY = 0;
                                    if (!Theme.reducedMotion)
                                        pageEnterAnim.restart();
                                    else
                                        pageLoader.opacity = 1.0;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
