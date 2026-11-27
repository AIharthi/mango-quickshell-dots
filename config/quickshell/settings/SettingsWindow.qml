pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."
import "../m3"

PanelWindow {
    id: root

    property bool isOpen: true
    property string activePage: "appearance"
    property bool _entered: false
    readonly property bool shown: root.isOpen && root._entered

    signal pageSelected(string page)
    signal closeRequested()
    signal openStoreRequested()

    property string searchQuery: ""
    property bool resetMenuOpen: false
    property bool confirmFactoryReset: false
    property var pageHistory: []
    property var lastInGroup: ({})
    property int railTipIdx: -1
    property real railTipY: 0

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
            Qt.callLater(() => {
                settingsFocusScope.forceActiveFocus();
            });
        } else {
            searchQuery = "";
            resetMenuOpen = false;
            confirmFactoryReset = false;
            railTipIdx = -1;
        }
    }

    function navigateTo(pageId: string): void {
        if (!pageId || pageId === root.resolvedPage)
            return;
        const nextHist = root.pageHistory.concat([root.resolvedPage]).slice(-25);
        root.pageHistory = nextHist;
        const map = Object.assign({}, root.lastInGroup);
        map[root.groupIdForPage(pageId)] = pageId;
        root.lastInGroup = map;
        root.railTipIdx = -1;
        root.pageSelected(pageId);
    }

    function goBack(): void {
        if (root.pageHistory.length > 0) {
            const copy = root.pageHistory.slice();
            const prev = copy.pop();
            root.pageHistory = copy;
            root.pageSelected(prev);
        } else if (root.resolvedPage !== "appearance") {
            root.pageSelected("appearance");
        }
    }

    readonly property var navItems: {
        const items = [
            { id: "appearance",    section: "Personalize",     label: "Appearance",     icon: "󰏘", source: "AppearancePage.qml",    sub: "Modes, surfaces, typography, cursor, and wallpaper transitions" },
            { id: "themes",        section: "Personalize",     label: "Themes & Colors",icon: "󰌁", source: "ThemesPage.qml",       sub: "Vibes, curated presets, Matugen extraction, and wallpapers" },
            { id: "island",        section: "Personalize",     label: "Dynamic Island", icon: "󰀵", source: "IslandPage.qml",       sub: "Floating pill, pods, morphing, expanded hub, and pill widgets" },
            { id: "split",         section: "Personalize",     label: "Split Islands",  icon: "󰕰", source: "SplitPage.qml",        sub: "3 stationary floating pods, per-pod Sequoia hubs, and pod modules" },
            { id: "sequoia",       section: "Personalize",     label: "Sequoia Bar",    icon: "󰘔", source: "SequoiaPage.qml",      sub: "macOS top menu bar, Control Center popover, Spotlight, and modules" },
            { id: "shell",         section: "Personalize",     label: "Shell & Bar",    icon: "󰕮", source: "ShellPage.qml",        sub: "Active bar switcher, Simple bar, file manager, and screenshots" },
            { id: "windows",       section: "Desktop & Input", label: "Windows",        icon: "󰖲", source: "WindowsPage.qml",      sub: "Picture-in-Picture, tiling layouts, gaps, and window rules" },
            { id: "input",         section: "Desktop & Input", label: "Input & Touchpad", icon: "󰌌", source: "InputPage.qml",      sub: "Keyboard, mouse, touchpad, and MSI I2C fix" },
            { id: "shortcuts",     section: "Desktop & Input", label: "Shortcuts",      icon: "󰌌", source: "ShortcutsPage.qml",    sub: "Browse, edit, and add MangoWC keybindings" },
            { id: "notifications", section: "Desktop & Input", label: "Notifications",  icon: "󰂚", source: "NotificationsPage.qml", sub: "Do Not Disturb, alert timeouts, and notification history" },
            { id: "apps",          section: "Desktop & Input", label: "Apps & Startup", icon: "󰀻", source: "AppsPage.qml",         sub: "Default applications, hidden launcher apps, and startup" }
        ];
        if (DeviceCaps.hasAudio)
            items.push({ id: "audio",     section: "Hardware", label: "Audio",     icon: "󰋋", source: "AudioPage.qml",     sub: "Volume, card profiles, per-app mixer, and channel test" });
        if (DeviceCaps.hasWlrRandr)
            items.push({ id: "displays",  section: "Hardware", label: "Displays",  icon: "󰍹", source: "DisplayPage.qml",   sub: "Resolution, arrangement, rotation, VRR, and night light" });
        if (DeviceCaps.hasNetwork || DeviceCaps.hasWifi)
            items.push({ id: "network",   section: "Hardware", label: "Network",   icon: "󰤨", source: "NetworkPage.qml",   sub: "Ethernet Wi-Fi share, interfaces, IP/DNS, and Wi-Fi" });
        if (DeviceCaps.hasBluetooth)
            items.push({ id: "bluetooth", section: "Hardware", label: "Bluetooth", icon: "󰂯", source: "BluetoothPage.qml", sub: "Adapter power and paired Bluetooth devices" });
        if (DeviceCaps.hasFoot || DeviceCaps.hasKitty)
            items.push({ id: "terminals", section: "System",   label: "Terminals", icon: "󰆍", source: "TerminalPage.qml",  sub: "Foot and Kitty opacity, padding, cursor, and scrollback" });
        items.push({ id: "privacy",       section: "System",   label: "Privacy",   icon: "󰌾", source: "PrivacyPage.qml",   sub: "Clipboard, history, camera, mic, lock, and login screen" });
        items.push({ id: "monitor",       section: "System",   label: "Monitor",   icon: "󰍛", source: "MonitorPage.qml",   sub: "Thermal sensors, running processes, and system services" });
        items.push({ id: "store",         section: "System",   label: "App Store", icon: "󰏖", source: "StorePage.qml",     sub: "Arch & Fedora native packages, AUR helpers, Flatpak, and updates" });
        items.push({ id: "debloat",       section: "System",   label: "Debloater", icon: "󰃢", source: "DebloatPage.qml",   sub: "CachyOS / Arch & Fedora bloat removal, services, DNF/Pacman tweaks & cache cleanup" });
        items.push({ id: "system",        section: "System",   label: "System",    icon: "󰋼", source: "SystemPage.qml",    sub: "Doctor, config updater, power daemon, storage, and backup" });
        return items;
    }

    readonly property var searchIndex: [
        { label: "One-Click Aesthetic Vibes",  pageId: "themes",        keywords: "vibe aurora glass minimal square oled stealth neon cyber cozy paper full dock bar gruvbox dracula notch" },
        { label: "16 Curated Theme Presets",   pageId: "themes",        keywords: "preset catppuccin tokyo night gruvbox nord rose pine dracula everforest kanagawa solarized one dark ayu oxocarbon synthwave oled sakura cyberpunk dark light" },
        { label: "Seed Accent Color Generator",pageId: "themes",        keywords: "seed accent hex rgb material you color generator solid wallpaper" },
        { label: "Wallpaper Studio & Matugen", pageId: "themes",        keywords: "wallpaper random solid dominant source color matugen extraction lightness prefer contrast tonal expressive vibrant monochrome rainbow" },
        { label: "Live Palette & Custom Themes",pageId: "themes",       keywords: "custom theme palette slot primary secondary surface outline error export import json save" },
        { label: "MangoWC Border & Shadow Colors",pageId: "themes",     keywords: "focus color border color colored shadow tint shadow opacity dim strength mango theme" },
        { label: "Shell Modes & Surface Finish",pageId: "appearance",   keywords: "mode simple blur surface style default glass frosted oled flat tinted panel opacity card opacity roundness border glow width ui text font scale" },
        { label: "Wallpaper Transitions",      pageId: "appearance",    keywords: "wallpaper transition effect speed duration resize fps grow wipe fade wave outer awww swww" },
        { label: "GTK & Icon Theme",           pageId: "appearance",    keywords: "gtk icon theme hinting antialiasing rgba cursor blink text scale" },
        { label: "UI & Terminal Font",         pageId: "appearance",    keywords: "font typography family size jetbrains mono foot kitty gtk" },
        { label: "Cursor Theme & Size",        pageId: "appearance",    keywords: "cursor pointer size theme hide" },
        { label: "Dynamic Island & Pill",      pageId: "island",        keywords: "island hover delay collapse media spin equalizer osd pill height notch floating margin bento cupertino stage cockpit hub capsule split" },
        { label: "Dynamic Island Widgets & Presets", pageId: "island",  keywords: "island bar widgets modules date window title workspaces tags layout cpu ram volume mute keyboard layout tray quick icons files battery presets minimal balanced full network speed" },
        { label: "Split Islands & Per-Pod Hubs", pageId: "split",       keywords: "split islands 3 pods floating spaces hub media focus timer control center cachyos presets transluscent height margin" },
        { label: "Sequoia Bar & Control Center", pageId: "sequoia",     keywords: "sequoia menubar macos top bar control center spotlight popover floating translucent menu icon aurora cachyos apple arch fedora gentoo" },
        { label: "Sequoia Menu Bar Modules",   pageId: "sequoia",       keywords: "sequoia modules app title workspaces layout media system cpu ram net speed volume battery tray store spotlight date" },
        { label: "Active Top Bar Switcher",    pageId: "shell",         keywords: "bar ui style switcher simple edge bar apple split menubar classic" },
        { label: "Dynamic File Manager (Rust)",pageId: "shell",         keywords: "file manager files rust explorer miller columns dual pane grid preview customize bar icon" },
        { label: "Simple Bar & Screenshots",   pageId: "shell",         keywords: "bar height top bottom layout screenshot grim slurp clipboard delay screen record video weather slideshow" },
        { label: "Weather & Wallpaper Slideshow", pageId: "shell",      keywords: "weather wttr city temperature celsius fahrenheit bar slideshow rotate wallpaper" },
        { label: "Accessibility & Motion",     pageId: "shell",         keywords: "reduced motion animations high contrast borders a11y" },
        { label: "Aurora App Store (Arch & Fedora)", pageId: "store",   keywords: "store app software pacman aur paru yay fedora dnf rpmfusion flatpak flathub install remove updates catalog search" },
        { label: "CachyOS & Fedora Debloater", pageId: "debloat",       keywords: "debloat bloatware cachyos fedora arch remove abrt octopi packagekit orphans dnf5 pacman cache cleanup snapshot restore" },
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
        { label: "Ethernet Wi-Fi Share (Laptop / PC)", pageId: "network", keywords: "ethernet wifi share bridge tether laptop pc cable dhcp nat dnsmasq static internet" },
        { label: "Bluetooth Devices",          pageId: "bluetooth",     keywords: "bluetooth pair connect audio device" },
        { label: "Keyboard, Mouse & Touchpad", pageId: "input",         keywords: "keyboard model layout repeat sandbox mouse left handed middle click scroll touchpad" },
        { label: "MSI Touchpad I2C Fix",       pageId: "input",         keywords: "msi touchpad fix i2c designware unbind bind restart arch cachyos boot service" },
        { label: "Foot & Kitty Settings",      pageId: "terminals",     keywords: "terminal foot kitty opacity alpha padding cursor blink scrollback" },
        { label: "DND, Critical & Sounds",     pageId: "notifications", keywords: "notification dnd do not disturb critical sound history clear test alerts calendar timer" },
        { label: "Defaults, Hidden Apps & Env",pageId: "apps",          keywords: "default browser terminal editor hidden apps launcher startup autostart exec_once env" },
        { label: "Shortcuts & Custom Binds",   pageId: "shortcuts",     keywords: "shortcut keybind hotkeys super mod mousebind custom bind cheat sheet" },
        { label: "Clipboard, Idle Lock & SDDM",    pageId: "privacy",   keywords: "privacy clipboard history clear middle paste recent files camera microphone lock idle timeout suspend sddm greeter login sync" },
        { label: "Sensors, Processes & Init",  pageId: "monitor",       keywords: "temp temperature cpu gpu process pid kill openrc systemd services" },
        { label: "User, Clock & Backup",       pageId: "system",        keywords: "user account clock 24h seconds date format keep awake disk storage backup export reset doctor health diagnostics aurora battery watts" },
        { label: "Distro & Package Center",    pageId: "system",        keywords: "distro arch pacman paru yay fedora dnf rpm gentoo portage emerge openrc systemd elogind flatpak updates packages" },
        { label: "Aurora Config Updater",      pageId: "system",        keywords: "update updater config dotfiles git pull sync mango-quickshell-dots github reload" },
        { label: "Power Daemon & Modes",       pageId: "system",        keywords: "power daemon mode profile saver balanced performance governor epp boost dpm aurora-powerd" },
        { label: "Capture Studio & Screenshots", pageId: "shell",       keywords: "capture studio screenshot recording gallery annotate satty swappy wf-recorder copy trash" },
        { label: "Snippets Vault & Sessions",  pageId: "shortcuts",     keywords: "snippets vault templates workspace sessions save restore window switcher" }
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

    readonly property int railW: 80

    readonly property var railGroups: {
        const defs = [
            { id: "look",     label: "Look",     icon: "󰏘", pages: ["appearance", "themes"] },
            { id: "bars",     label: "Bars",     icon: "󰕰", pages: ["split", "island", "sequoia", "shell"] },
            { id: "desktop",  label: "Desktop",  icon: "󰖲", pages: ["windows", "input", "shortcuts", "notifications", "apps"] },
            { id: "hardware", label: "Hardware", icon: "󰋋", pages: ["audio", "displays", "network", "bluetooth"] },
            { id: "store",    label: "Store",    icon: "󰏖", pages: ["store"] },
            { id: "debloat",  label: "Debloat",  icon: "󰃢", pages: ["debloat"] },
            { id: "system",   label: "System",   icon: "󰍛", pages: ["terminals", "privacy", "monitor", "system"] }
        ];
        const byId = {};
        for (let i = 0; i < root.navItems.length; i++)
            byId[root.navItems[i].id] = root.navItems[i];
        const out = [];
        for (let g = 0; g < defs.length; g++) {
            const sub = [];
            for (let p = 0; p < defs[g].pages.length; p++) {
                const it = byId[defs[g].pages[p]];
                if (it)
                    sub.push(it);
            }
            if (sub.length > 0)
                out.push({ id: defs[g].id, label: defs[g].label, icon: defs[g].icon, items: sub });
        }
        return out;
    }

    function groupIdForPage(pid: string): string {
        for (let g = 0; g < root.railGroups.length; g++) {
            const items = root.railGroups[g].items;
            for (let i = 0; i < items.length; i++) {
                if (items[i].id === pid)
                    return root.railGroups[g].id;
            }
        }
        return root.railGroups.length > 0 ? root.railGroups[0].id : "look";
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
    readonly property string activeGroupId: groupIdForPage(resolvedPage)
    readonly property var currentGroup: {
        for (let i = 0; i < railGroups.length; i++) {
            if (railGroups[i].id === activeGroupId)
                return railGroups[i];
        }
        return railGroups[0];
    }

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

        Keys.onEscapePressed: {
            if (root.resetMenuOpen)
                root.resetMenuOpen = false;
            else if (root.searchQuery.length > 0)
                root.searchQuery = "";
            else
                root.closeRequested();
        }

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

        // Centered M3 Expressive Settings Dialog (DarkShadowShell layout)
        Rectangle {
            id: dialog
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 1080)
            height: Math.min(parent.height - 40, 720)
            radius: Theme.r(30)
            color: Theme.m3PanelBg
            clip: true
            border.width: 1
            border.color: Theme.m3Line

            opacity: root.shown ? 1.0 : 0.0
            scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.965)

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            // Eat clicks inside dialog and dismiss transient popovers
            MouseArea {
                anchors.fill: parent
                onClicked: root.resetMenuOpen = false
            }

            // ================= Left 80px M3 Navigation Rail =================
            Item {
                id: railArea
                x: 0
                y: 0
                width: root.railW
                height: parent.height

                // Spinning M3Blob Emblem (Home -> Appearance)
                Item {
                    id: emblemBtn
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 16
                    width: 48
                    height: 48
                    scale: emblemMouse.pressed ? 0.92 : (emblemMouse.containsMouse ? 1.06 : 1.0)
                    Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                    M3Blob {
                        anchors.fill: parent
                        kind: ShellState.m3Shape
                        color: Theme.m3PrimaryContainer
                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 42000
                            loops: Animation.Infinite
                            running: root.shown && !Theme.reducedMotion
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒓"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(21)
                        color: Theme.m3OnPrimaryContainer
                    }

                    MouseArea {
                        id: emblemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.navigateTo("appearance")
                    }
                }

                // Rail Group Icons
                Flickable {
                    id: navFlick
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: emblemBtn.bottom
                    anchors.topMargin: 12
                    anchors.bottom: railResetBtn.top
                    anchors.bottomMargin: 10
                    contentWidth: width
                    contentHeight: railCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: railCol
                        width: navFlick.width
                        spacing: 6

                        Repeater {
                            model: root.railGroups

                            delegate: Item {
                                id: railItem
                                required property var modelData
                                required property int index
                                readonly property bool on: root.activeGroupId === railItem.modelData.id
                                readonly property bool gapAfter: railItem.index === 0 || railItem.modelData.id === "debloat"

                                width: navFlick.width
                                height: 52 + (railItem.gapAfter ? 12 : 0)

                                Rectangle {
                                    visible: railItem.gapAfter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 57
                                    width: 28
                                    height: 1
                                    color: Theme.m3Line
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 4
                                    width: railItem.on ? 54 : (railItemMouse.containsMouse ? 48 : 24)
                                    height: railItem.on ? 44 : 40
                                    radius: Theme.r(railItem.on ? 16 : 20)
                                    color: railItem.on ? Theme.m3SecondaryContainer : Theme.m3SurfaceHigh
                                    opacity: (railItem.on || railItemMouse.containsMouse) ? 1.0 : 0.0

                                    Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                                    Behavior on height { enabled: !Theme.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }
                                    Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 160 } }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 4
                                    height: railItem.on ? 44 : 40
                                    verticalAlignment: Text.AlignVCenter
                                    text: railItem.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(20)
                                    color: railItem.on ? Theme.m3OnSecondaryContainer : Theme.m3InkDim
                                    Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 160 } }
                                }

                                MouseArea {
                                    id: railItemMouse
                                    width: parent.width
                                    height: 52
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const targetId = root.lastInGroup[railItem.modelData.id] || railItem.modelData.items[0].id;
                                        root.navigateTo(targetId);
                                    }
                                    onContainsMouseChanged: {
                                        if (containsMouse) {
                                            root.railTipIdx = railItem.index;
                                            root.railTipY = railItem.mapToItem(dialog, 0, 8).y;
                                        } else if (root.railTipIdx === railItem.index) {
                                            root.railTipIdx = -1;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Rail Footer Reset Trigger
                Rectangle {
                    id: railResetBtn
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 16
                    width: 44
                    height: 44
                    radius: Theme.r(root.resetMenuOpen ? 14 : 22)
                    color: root.resetMenuOpen
                        ? Theme.m3ErrorContainer
                        : (railRstMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                    Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 160 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰑐"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(18)
                        color: root.resetMenuOpen ? Theme.m3OnErrorContainer : Theme.warning
                    }

                    MouseArea {
                        id: railRstMouse
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
            }

            // Floating Rail Hover Tooltip
            Rectangle {
                readonly property var hoveredGroup: (root.railTipIdx >= 0 && root.railTipIdx < root.railGroups.length)
                    ? root.railGroups[root.railTipIdx]
                    : null
                visible: hoveredGroup !== null && !root.resetMenuOpen
                x: root.railW - 4
                y: root.railTipY
                z: 55
                height: 34
                width: railTipTxt.implicitWidth + 24
                radius: Theme.r(17)
                color: Theme.m3InverseSurface

                Text {
                    id: railTipTxt
                    anchors.centerIn: parent
                    text: parent.hoveredGroup ? parent.hoveredGroup.label : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.Bold
                    color: Theme.m3InverseInk
                }
            }

            // Floating Reset Menu Popover
            Rectangle {
                visible: root.resetMenuOpen
                x: root.railW + 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                z: 65
                width: 224
                implicitHeight: rstMenuCol.implicitHeight + 20
                radius: Theme.r(22)
                color: Theme.m3PanelBg
                border.width: 1
                border.color: Theme.m3Line

                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: rstMenuCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        Layout.leftMargin: 6
                        text: "Reset Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.Bold
                        color: Theme.m3Ink
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Theme.r(16)
                        color: sbRstAppMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC

                        Text {
                            anchors.centerIn: parent
                            text: "Appearance & Theme"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
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
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Theme.r(16)
                        color: sbRstBarMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC

                        Text {
                            anchors.centerIn: parent
                            text: "Bar & Shell"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                            color: Theme.m3Primary
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
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Theme.r(16)
                        color: root.confirmFactoryReset
                            ? Theme.m3Error
                            : (sbRstAllMouse.containsMouse ? Theme.m3ErrorContainer : Theme.m3SurfaceC)

                        Text {
                            anchors.centerIn: parent
                            text: root.confirmFactoryReset ? "Confirm Factory Reset?" : "Factory Reset All"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: root.confirmFactoryReset ? Theme.m3OnPrimary : (sbRstAllMouse.containsMouse ? Theme.m3OnErrorContainer : Theme.m3Error)
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

            // ================= Top Header (Back, Breadcrumb, Search, Close) =================
            Item {
                id: topHeader
                x: root.railW + 14
                y: 14
                width: parent.width - x - 18
                height: 66

                // Circular Back Button
                Rectangle {
                    id: backBtn
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: Theme.r(bkm.pressed ? 14 : 22)
                    color: bkm.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                    opacity: (root.pageHistory.length === 0 && root.resolvedPage === "appearance") ? 0.35 : 1.0
                    Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰁍"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(18)
                        color: Theme.m3Ink
                    }

                    MouseArea {
                        id: bkm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goBack()
                    }
                }

                // Breadcrumb & Page Title
                Column {
                    anchors.left: backBtn.right
                    anchors.leftMargin: 14
                    anchors.right: searchBox.left
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Row {
                        spacing: 6

                        Text {
                            text: "SETTINGS"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                            color: crumbHomeMouse.containsMouse ? Theme.m3Primary : Theme.m3InkDim

                            MouseArea {
                                id: crumbHomeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.navigateTo("appearance")
                            }
                        }

                        Text {
                            text: "\u203a"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.Bold
                            color: Theme.m3InkDim
                        }

                        Text {
                            text: root.currentGroup ? root.currentGroup.label.toUpperCase() : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                            color: Theme.m3Primary
                        }
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.currentNavItem.label
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(24)
                        font.weight: Font.Bold
                        color: Theme.m3Ink
                    }
                }

                // Search Capsule
                Rectangle {
                    id: searchBox
                    anchors.right: headerCloseBtn.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(270, Math.max(180, parent.width * 0.28))
                    height: 40
                    radius: Theme.r(20)
                    color: searchInput.activeFocus ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                    border.width: searchInput.activeFocus ? 2 : 1
                    border.color: searchInput.activeFocus ? Theme.m3Primary : Theme.m3Line
                    Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(15)
                        color: searchInput.activeFocus ? Theme.m3Primary : Theme.m3InkDim
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.leftMargin: 38
                        anchors.right: clearSearchBtn.visible ? clearSearchBtn.left : parent.right
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search settings..."
                            visible: searchInput.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            color: Theme.m3InkDim
                        }

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.searchQuery
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            color: Theme.m3Ink
                            selectionColor: Theme.m3Primary
                            selectedTextColor: Theme.m3OnPrimary
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
                                    root.navigateTo(root.searchMatches[0].pageId);
                                    root.searchQuery = "";
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: clearSearchBtn
                        visible: root.searchQuery.length > 0
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        radius: Theme.r(12)
                        color: clearSearchMouse.containsMouse ? Theme.m3SurfaceC : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(11)
                            color: Theme.m3InkDim
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

                // Circular Close Button
                Rectangle {
                    id: headerCloseBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    radius: Theme.r(closeBtnMouse.pressed ? 14 : 20)
                    color: closeBtnMouse.containsMouse ? Theme.m3ErrorContainer : Theme.m3SurfaceHigh
                    scale: closeBtnMouse.pressed ? 0.94 : 1.0
                    Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 130 } }
                    Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(15)
                        color: closeBtnMouse.containsMouse ? Theme.m3OnErrorContainer : Theme.m3Ink
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

            // Floating Search Results Dropdown
            Rectangle {
                visible: root.searchQuery.trim().length > 0
                anchors.right: parent.right
                anchors.rightMargin: 18
                y: 80
                z: 60
                width: 340
                height: Math.min(340, Math.max(60, searchHitsCol.implicitHeight + 20))
                radius: Theme.r(24)
                color: Theme.m3PanelBg
                border.width: 1
                border.color: Theme.m3Line
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 10
                    contentWidth: width
                    contentHeight: searchHitsCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: searchHitsCol
                        width: parent.width
                        spacing: 5

                        Text {
                            visible: root.searchMatches.length === 0
                            Layout.fillWidth: true
                            Layout.margins: 8
                            text: "No matching setting"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            color: Theme.m3InkDim
                        }

                        Repeater {
                            model: root.searchMatches

                            delegate: Rectangle {
                                id: hitBtn
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: Theme.r(16)
                                color: hitMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    anchors.topMargin: 6
                                    anchors.bottomMargin: 6
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: hitBtn.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(11)
                                        font.weight: Font.Bold
                                        color: Theme.m3Ink
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: "in " + hitBtn.modelData.pageId
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(9)
                                        color: Theme.m3Primary
                                    }
                                }

                                MouseArea {
                                    id: hitMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.navigateTo(hitBtn.modelData.pageId);
                                        root.searchQuery = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ================= Rounded Content Pane Beside Rail =================
            Rectangle {
                id: pane
                x: root.railW
                y: 88
                width: parent.width - x - 14
                height: parent.height - y - 14
                radius: Theme.r(28)
                color: Theme.m3PaneBg
                border.width: 1
                border.color: Theme.m3Line
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Sub-Tabs Strip + Subtitle Caption
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: subHdrCol.implicitHeight + 20
                        color: "transparent"

                        ColumnLayout {
                            id: subHdrCol
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            anchors.topMargin: 12
                            anchors.bottomMargin: 8
                            spacing: 8

                            Flickable {
                                visible: root.currentGroup && root.currentGroup.items.length > 1
                                Layout.fillWidth: true
                                implicitHeight: 34
                                contentWidth: subTabRow.implicitWidth
                                contentHeight: 34
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Row {
                                    id: subTabRow
                                    spacing: 6

                                    Repeater {
                                        model: root.currentGroup ? root.currentGroup.items : []

                                        delegate: Rectangle {
                                            id: subTabPill
                                            required property var modelData
                                            readonly property bool isSel: root.resolvedPage === subTabPill.modelData.id

                                            height: 32
                                            width: subTabInner.implicitWidth + 24
                                            radius: Theme.r(subTabPill.isSel ? 12 : 16)
                                            color: subTabPill.isSel
                                                ? Theme.m3Primary
                                                : (subTabMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                                            Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 140 } }

                                            Row {
                                                id: subTabInner
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: subTabPill.modelData.icon
                                                    font.family: Theme.iconFont
                                                    font.pixelSize: Theme.fs(12)
                                                    color: subTabPill.isSel ? Theme.m3OnPrimary : Theme.m3InkDim
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: subTabPill.modelData.label
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(11)
                                                    font.weight: subTabPill.isSel ? Font.Bold : Font.Medium
                                                    color: subTabPill.isSel ? Theme.m3OnPrimary : Theme.m3Ink
                                                }
                                            }

                                            MouseArea {
                                                id: subTabMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.navigateTo(subTabPill.modelData.id)
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.currentNavItem.sub
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    color: Theme.m3InkDim
                                }

                                Rectangle {
                                    implicitHeight: 22
                                    implicitWidth: stylePillTxt.implicitWidth + 14
                                    radius: Theme.r(11)
                                    color: Theme.m3SecondaryContainer

                                    Text {
                                        id: stylePillTxt
                                        anchors.centerIn: parent
                                        text: {
                                            for (let i = 0; i < Theme.availableModes.length; i++) {
                                                if (Theme.availableModes[i].id === Theme.shellMode)
                                                    return Theme.availableModes[i].label;
                                            }
                                            return "Island";
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(9)
                                        font.weight: Font.Bold
                                        color: Theme.m3OnSecondaryContainer
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20
                        color: Theme.m3Line
                    }

                    // Scrollable Page Container with Animated Page Entry
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20
                        Layout.topMargin: 12
                        Layout.bottomMargin: 14

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
                                    duration: 120
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

                            Connections {
                                target: pageLoader.item
                                ignoreUnknownSignals: true
                                function onOpenPageRequested(page) {
                                    root.navigateTo(page);
                                }
                                function onOpenStoreRequested() {
                                    root.closeRequested();
                                    root.openStoreRequested();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
