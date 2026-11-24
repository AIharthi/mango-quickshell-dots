import QtQuick 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0 as SddmComp

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: root.colSurfaceLowest

    // --- Bundled Fonts (with system fallback) ---
    FontLoader { id: plexReg; source: "fonts/IBMPlexSans-Regular.ttf" }
    FontLoader { id: plexMed; source: "fonts/IBMPlexSans-Medium.ttf" }
    FontLoader { id: plexSemi; source: "fonts/IBMPlexSans-SemiBold.ttf" }
    FontLoader { id: plexBold; source: "fonts/IBMPlexSans-Bold.ttf" }
    FontLoader { id: plexMonoBold; source: "fonts/IBMPlexMono-Bold.ttf" }
    FontLoader { id: jbReg; source: "fonts/JetBrainsMono-Regular.ttf" }
    FontLoader { id: jbBold; source: "fonts/JetBrainsMono-Bold.ttf" }
    FontLoader { id: nfIcons; source: "fonts/SymbolsNerdFont-Regular.ttf" }

    readonly property string uiFont: (typeof config !== "undefined" && config && config.font && String(config.font).length > 0)
        ? String(config.font)
        : ((plexReg.status === FontLoader.Ready) ? plexReg.name : "IBM Plex Sans")
    readonly property string monoFont: (typeof config !== "undefined" && config && config.monoFont && String(config.monoFont).length > 0)
        ? String(config.monoFont)
        : ((plexMonoBold.status === FontLoader.Ready) ? plexMonoBold.name : ((jbBold.status === FontLoader.Ready) ? jbBold.name : "IBM Plex Mono"))
    readonly property string iconFont: (nfIcons.status === FontLoader.Ready)
        ? nfIcons.name
        : String((config && config.iconFont) ? config.iconFont : "Symbols Nerd Font")

    // --- Theme Tokens synced from Quickshell / Matugen ---
    function cfgStr(key, fallback) {
        if (typeof config !== "undefined" && config && config[key] !== undefined && String(config[key]).length > 0)
            return String(config[key]);
        return fallback;
    }

    function cfgBool(key, fallback) {
        if (typeof config !== "undefined" && config && config[key] !== undefined) {
            var v = String(config[key]).trim().toLowerCase();
            if (v === "true" || v === "1" || v === "yes")
                return true;
            if (v === "false" || v === "0" || v === "no")
                return false;
        }
        return fallback;
    }

    function withAlpha(hexStr, alpha) {
        var s = String(hexStr || "").trim();
        if (s.charAt(0) === "#")
            s = s.slice(1);
        if (s.length !== 6)
            return Qt.rgba(0.12, 0.12, 0.18, alpha);
        var r = parseInt(s.slice(0, 2), 16) / 255.0;
        var g = parseInt(s.slice(2, 4), 16) / 255.0;
        var b = parseInt(s.slice(4, 6), 16) / 255.0;
        return Qt.rgba(r, g, b, alpha);
    }

    readonly property bool isDark: cfgBool("isDark", true)
    readonly property bool clock24h: cfgBool("clock24h", true)
    readonly property bool reducedMotion: cfgBool("reducedMotion", false)
    readonly property int cardRadius: Math.max(8, Math.min(36, parseInt(cfgStr("radius", "28"), 10) || 28))
    readonly property string bgSource: cfgStr("background", "")

    readonly property color colPrimary: cfgStr("primary", "#cba6f7")
    readonly property color colOnPrimary: cfgStr("onPrimary", "#11111b")
    readonly property color colSecondary: cfgStr("secondary", "#89b4fa")
    readonly property color colSurface: cfgStr("surface", "#1e1e2e")
    readonly property color colSurfaceLowest: cfgStr("surfaceLowest", "#11111b")
    readonly property string rawCardHex: cfgStr("cardBg", "#313244")
    readonly property color colCardBg: root.isDark ? withAlpha(rawCardHex, 0.54) : withAlpha(rawCardHex, 0.72)
    readonly property color colSubCardBg: root.isDark ? withAlpha(rawCardHex, 0.40) : withAlpha(rawCardHex, 0.58)
    readonly property color colNotchBg: root.isDark
        ? withAlpha(cfgStr("surfaceLowest", "#11111b"), 0.84)
        : withAlpha(cfgStr("surface", "#f4f4f8"), 0.88)
    readonly property color colFg: cfgStr("fgSurface", "#cdd6f4")
    readonly property color colFgMuted: cfgStr("fgSurfaceVariant", "#a6adc8")
    readonly property color colOutline: cfgStr("outline", "#6c7086")
    readonly property color colOutlineVar: cfgStr("outlineVariant", "#313244")
    readonly property color colBorder: root.isDark ? withAlpha(cfgStr("fgSurface", "#cdd6f4"), 0.16) : withAlpha(cfgStr("outline", "#6c7086"), 0.28)
    readonly property color colError: cfgStr("error", "#f38ba8")
    readonly property color colOnError: cfgStr("onError", "#11111b")
    readonly property color colWarning: cfgStr("warning", "#f9e2af")

    // --- State ---
    property bool _revealed: false
    property bool _unlocking: false
    property bool authenticating: false
    property bool showPassword: false
    property bool editingUser: false
    property string errorText: ""
    property string confirmPowerAction: ""
    property int userIndex: (typeof userModel !== "undefined" && userModel && userModel.lastIndex >= 0) ? userModel.lastIndex : 0
    property int sessionIndex: (typeof sessionModel !== "undefined" && sessionModel && sessionModel.lastIndex >= 0) ? sessionModel.lastIndex : 0
    property string activeUser: {
        if (typeof userModel !== "undefined" && userModel && userModel.count > 0) {
            var u = userModel.data(userModel.index(root.userIndex, 0), Qt.UserRole + 1);
            if (u && String(u).length > 0)
                return String(u);
            if (userModel.lastUser && String(userModel.lastUser).length > 0)
                return String(userModel.lastUser);
        }
        return "aurora";
    }

    function sessionName(idx) {
        if (typeof sessionModel === "undefined" || !sessionModel || sessionModel.count <= 0)
            return "Aurora Shell";
        var cur = sessionModel.data(sessionModel.index(idx, 0), Qt.UserRole + 4);
        return cur ? String(cur) : "Aurora Shell";
    }

    function currentKbLabel() {
        if (typeof keyboard === "undefined" || !keyboard || !keyboard.layouts || keyboard.layouts.length === 0)
            return "";
        var lay = keyboard.layouts[keyboard.currentLayout];
        if (!lay)
            return "";
        var s = String(lay.shortName || lay.longName || "");
        return s.slice(0, 3).toUpperCase();
    }

    function greetingText(dt) {
        var hr = dt ? dt.getHours() : (new Date()).getHours();
        var prefix = hr < 12 ? "Good Morning" : (hr < 18 ? "Good Afternoon" : "Good Evening");
        var usr = root.editingUser && userInput.text.length > 0 ? userInput.text : root.activeUser;
        return prefix + ", " + usr;
    }

    function formatClock(dt) {
        var fmt = root.clock24h ? "HH:mm" : "hh:mm AP";
        return Qt.formatDateTime(dt, fmt);
    }

    function formatDateStr(dt) {
        return Qt.formatDateTime(dt, "ddd d MMM yyyy");
    }

    function submitLogin() {
        if (root.authenticating || root._unlocking)
            return;
        var usr = root.editingUser ? userInput.text.trim() : root.activeUser;
        if (!usr || usr.length === 0) {
            root.errorText = "Enter a username";
            if (!root.reducedMotion)
                shakeAnim.restart();
            return;
        }
        if (!pwdInput.text || pwdInput.text.length === 0) {
            root.errorText = "Enter your password";
            if (!root.reducedMotion)
                shakeAnim.restart();
            pwdInput.forceActiveFocus();
            return;
        }
        root.errorText = "";
        root.authenticating = true;
        sddm.login(usr, pwdInput.text, root.sessionIndex);
    }

    Timer {
        id: revealTimer
        interval: 40
        repeat: false
        onTriggered: root._revealed = true
    }

    Timer {
        id: powerConfirmTimer
        interval: 4000
        repeat: false
        onTriggered: root.confirmPowerAction = ""
    }

    Timer {
        id: clockTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            var now = new Date();
            clockTxt.text = root.formatClock(now);
            dateTxt.text = root.formatDateStr(now);
            greetTxt.text = root.greetingText(now);
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.authenticating = false;
            pwdInput.text = "";
            root.errorText = "Incorrect password. Try again.";
            if (!root.reducedMotion)
                shakeAnim.restart();
            pwdInput.forceActiveFocus();
        }
        function onLoginSucceeded() {
            root.authenticating = false;
            root.errorText = "";
            root._unlocking = true;
        }
    }

    Component.onCompleted: {
        var now = new Date();
        clockTxt.text = root.formatClock(now);
        dateTxt.text = root.formatDateStr(now);
        greetTxt.text = root.greetingText(now);
        if (root.reducedMotion)
            root._revealed = true;
        else
            revealTimer.restart();
        pwdInput.forceActiveFocus();
    }

    // Ambient Gradient Fallback Background (when no wallpaper image is set)
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.colSurfaceLowest }
            GradientStop { position: 0.55; color: root.colSurface }
            GradientStop { position: 1.0; color: root.withAlpha(cfgStr("primary", "#cba6f7"), 0.18) }
        }
    }

    // Synced Wallpaper Image with entrance zoom-out
    Image {
        id: bgImg
        anchors.fill: parent
        visible: root.bgSource.length > 0 && status === Image.Ready
        source: root.bgSource
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        opacity: (root._revealed && !root._unlocking) ? 1.0 : 0.0
        scale: root.reducedMotion ? 1.0 : (root._unlocking ? 1.04 : (root._revealed ? 1.0 : 1.07))

        Behavior on opacity {
            enabled: !root.reducedMotion
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !root.reducedMotion
            NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
        }
    }

    // Ambient Scrim matching LockScreen.qml
    Rectangle {
        anchors.fill: parent
        opacity: (root._revealed && !root._unlocking) ? 1.0 : 0.0
        color: root.isDark
            ? Qt.rgba(0.03, 0.03, 0.06, 0.68)
            : Qt.rgba(0.94, 0.94, 0.97, 0.65)

        Behavior on opacity {
            enabled: !root.reducedMotion
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
    }

    // Main Centered Glass Card
    Rectangle {
        id: mainCard
        anchors.centerIn: parent
        width: Math.min(460, Math.max(320, root.width - 48))
        implicitHeight: cardCol.implicitHeight + 52
        radius: root.cardRadius
        color: root.colNotchBg
        border.width: 1
        border.color: root.errorText.length > 0 ? root.colError : root.colBorder
        clip: true

        opacity: (root._revealed && !root._unlocking) ? 1.0 : 0.0
        scale: root.reducedMotion ? 1.0 : (root._unlocking ? 1.04 : (root._revealed ? 1.0 : 0.93))
        transform: Translate {
            y: root.reducedMotion ? 0 : (root._unlocking ? -14 : (root._revealed ? 0 : 26))
            Behavior on y {
                enabled: !root.reducedMotion
                NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
            }
        }

        Behavior on opacity {
            enabled: !root.reducedMotion
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !root.reducedMotion
            NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            enabled: !root.reducedMotion
            ColorAnimation { duration: 160 }
        }

        // Top Specular Glass Sheen
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 52
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.34) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Top Auth Pulse Bar
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            height: 3
            radius: 1.5
            visible: root.authenticating
            width: parent.width * 0.55
            color: root.colPrimary

            SequentialAnimation on opacity {
                running: root.authenticating && !root.reducedMotion
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 420; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine }
            }
        }

        ColumnLayout {
            id: cardCol
            anchors.fill: parent
            anchors.margins: 26
            spacing: 13

            // Greeting + Clock + Date
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    id: greetTxt
                    Layout.alignment: Qt.AlignHCenter
                    text: root.greetingText(new Date())
                    font.family: root.uiFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: root.colPrimary
                }

                Text {
                    id: clockTxt
                    Layout.alignment: Qt.AlignHCenter
                    text: root.formatClock(new Date())
                    font.family: root.monoFont
                    font.pixelSize: 50
                    font.weight: Font.Bold
                    color: root.colFg
                }

                Text {
                    id: dateTxt
                    Layout.alignment: Qt.AlignHCenter
                    text: root.formatDateStr(new Date())
                    font.family: root.uiFont
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: root.colFgMuted
                }
            }

            // Interactive Pill Strip (User, Session, Keyboard Layout, Caps Lock)
            Flow {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                // User Selector Pill
                Rectangle {
                    implicitHeight: 26
                    implicitWidth: usrRow.implicitWidth + 16
                    radius: 13
                    color: usrMouse.containsMouse ? root.withAlpha(cfgStr("primary", "#cba6f7"), 0.16) : root.colCardBg
                    border.width: 0

                    RowLayout {
                        id: usrRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            text: "󰀄"
                            font.family: root.iconFont
                            font.pixelSize: 12
                            color: root.colPrimary
                        }
                        Text {
                            text: root.activeUser
                            font.family: root.uiFont
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: root.colFg
                        }
                    }

                    MouseArea {
                        id: usrMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof userModel !== "undefined" && userModel && userModel.count > 1) {
                                root.userIndex = (root.userIndex + 1) % userModel.count;
                            } else {
                                root.editingUser = !root.editingUser;
                                if (root.editingUser)
                                    userInput.forceActiveFocus();
                                else
                                    pwdInput.forceActiveFocus();
                            }
                        }
                    }
                }

                // Session Selector Pill
                Rectangle {
                    implicitHeight: 26
                    implicitWidth: sessRow.implicitWidth + 16
                    radius: 13
                    color: sessMouse.containsMouse ? root.withAlpha(cfgStr("secondary", "#89b4fa"), 0.16) : root.colCardBg
                    border.width: 0

                    RowLayout {
                        id: sessRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            text: "󰍹"
                            font.family: root.iconFont
                            font.pixelSize: 11
                            color: root.colSecondary
                        }
                        Text {
                            text: root.sessionName(root.sessionIndex)
                            font.family: root.uiFont
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: root.colFg
                        }
                    }

                    MouseArea {
                        id: sessMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof sessionModel !== "undefined" && sessionModel && sessionModel.count > 1)
                                root.sessionIndex = (root.sessionIndex + 1) % sessionModel.count;
                        }
                    }
                }

                // Keyboard Layout Selector Pill
                Rectangle {
                    visible: root.currentKbLabel().length > 0
                    implicitHeight: 26
                    implicitWidth: kbRow.implicitWidth + 14
                    radius: 13
                    color: kbMouse.containsMouse ? root.withAlpha(cfgStr("primary", "#cba6f7"), 0.16) : root.colCardBg
                    border.width: 0

                    RowLayout {
                        id: kbRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "󰌌"
                            font.family: root.iconFont
                            font.pixelSize: 11
                            color: root.colSecondary
                        }
                        Text {
                            text: root.currentKbLabel()
                            font.family: root.monoFont
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: root.colFg
                        }
                    }

                    MouseArea {
                        id: kbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof keyboard !== "undefined" && keyboard && keyboard.layouts && keyboard.layouts.length > 1)
                                keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length;
                        }
                    }
                }

                // Caps Lock Chip
                Rectangle {
                    visible: typeof keyboard !== "undefined" && keyboard && keyboard.capsLock
                    implicitHeight: 26
                    implicitWidth: capsLbl.implicitWidth + 14
                    radius: 13
                    color: root.withAlpha(cfgStr("warning", "#f9e2af"), 0.18)
                    border.width: 1
                    border.color: root.withAlpha(cfgStr("warning", "#f9e2af"), 0.55)

                    Text {
                        id: capsLbl
                        anchors.centerIn: parent
                        text: "Caps"
                        font.family: root.monoFont
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: root.colWarning
                    }
                }
            }

            // Optional Editable Username Input (when user clicks User pill on single-user setup)
            Rectangle {
                visible: root.editingUser
                Layout.fillWidth: true
                implicitHeight: 40
                radius: 12
                color: root.colCardBg
                border.width: 1
                border.color: userInput.activeFocus ? root.colPrimary : root.colBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "󰀄"
                        font.family: root.iconFont
                        font.pixelSize: 14
                        color: root.colPrimary
                    }

                    TextInput {
                        id: userInput
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        text: root.activeUser
                        color: root.colFg
                        selectionColor: root.colPrimary
                        selectedTextColor: root.colOnPrimary
                        font.family: root.uiFont
                        font.pixelSize: 12
                        clip: true

                        KeyNavigation.tab: pwdInput
                        Keys.onReturnPressed: pwdInput.forceActiveFocus()
                        Keys.onEnterPressed: pwdInput.forceActiveFocus()
                    }
                }
            }

            // Password Input Box with horizontal failure shake
            Rectangle {
                id: pwdBox
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 14
                color: root.colCardBg
                border.width: (pwdInput.activeFocus || root.errorText.length > 0) ? 1.5 : 1
                border.color: root.errorText.length > 0
                    ? root.colError
                    : (pwdInput.activeFocus ? root.colPrimary : root.colBorder)

                Behavior on border.color {
                    enabled: !root.reducedMotion
                    ColorAnimation { duration: 150 }
                }

                transform: Translate {
                    id: pwdShake
                    x: 0
                }

                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: pwdShake; property: "x"; to: -12; duration: 42; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: pwdShake; property: "x"; to: 12;  duration: 42; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: pwdShake; property: "x"; to: -9;  duration: 42; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: pwdShake; property: "x"; to: 9;   duration: 42; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: pwdShake; property: "x"; to: -4;  duration: 42; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: pwdShake; property: "x"; to: 0;   duration: 42; easing.type: Easing.InOutQuad }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        id: lockGlyph
                        text: root.authenticating ? "󰦖" : "󰌾"
                        font.family: root.iconFont
                        font.pixelSize: 15
                        color: root.errorText.length > 0
                            ? root.colError
                            : (pwdInput.activeFocus ? root.colPrimary : root.colFgMuted)

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                            running: root.authenticating && !root.reducedMotion
                            onRunningChanged: {
                                if (!running)
                                    lockGlyph.rotation = 0;
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pwdInput.text.length === 0
                            text: root.authenticating ? "Signing in..." : "Enter password to log in"
                            font.family: root.uiFont
                            font.pixelSize: 12
                            color: root.colFgMuted
                        }

                        TextInput {
                            id: pwdInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                            enabled: !root.authenticating && !root._unlocking
                            color: root.colFg
                            selectionColor: root.colPrimary
                            selectedTextColor: root.colOnPrimary
                            font.family: root.uiFont
                            font.pixelSize: 13
                            clip: true

                            onTextEdited: {
                                if (root.errorText.length > 0)
                                    root.errorText = "";
                            }
                            Keys.onReturnPressed: root.submitLogin()
                            Keys.onEnterPressed: root.submitLogin()
                            Keys.onEscapePressed: {
                                text = "";
                                root.errorText = "";
                            }
                        }
                    }

                    // Show/Hide Password Toggle
                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 9
                        color: eyeMouse.containsMouse ? root.withAlpha(cfgStr("primary", "#cba6f7"), 0.14) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: root.showPassword ? "󰈉" : "󰈈"
                            font.family: root.iconFont
                            font.pixelSize: 13
                            color: root.showPassword ? root.colPrimary : root.colFgMuted
                        }

                        MouseArea {
                            id: eyeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.showPassword = !root.showPassword;
                                pwdInput.forceActiveFocus();
                            }
                        }
                    }

                    // Login Submit Button
                    Rectangle {
                        implicitWidth: 30
                        implicitHeight: 30
                        radius: 10
                        color: submitMouse.containsMouse ? root.colPrimary : root.colSubCardBg
                        scale: submitMouse.pressed ? 0.92 : 1.0

                        Behavior on scale {
                            enabled: !root.reducedMotion
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰌍"
                            font.family: root.iconFont
                            font.pixelSize: 14
                            color: submitMouse.containsMouse ? root.colOnPrimary : root.colPrimary
                        }

                        MouseArea {
                            id: submitMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submitLogin()
                        }
                    }
                }
            }

            // Error Feedback
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: root.errorText.length > 0
                text: root.errorText
                font.family: root.uiFont
                font.pixelSize: 11
                font.weight: Font.Medium
                color: root.colError
            }
        }
    }

    // Bottom-Right Animated Session Power Pills
    RowLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 8
        opacity: (root._revealed && !root._unlocking) ? 1.0 : 0.0
        transform: Translate {
            y: root.reducedMotion ? 0 : ((root._revealed && !root._unlocking) ? 0 : 16)
            Behavior on y {
                enabled: !root.reducedMotion
                NumberAnimation { duration: 360; easing.type: Easing.OutCubic }
            }
        }
        Behavior on opacity {
            enabled: !root.reducedMotion
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        Rectangle {
            visible: typeof sddm === "undefined" || sddm.canSuspend
            implicitHeight: 34
            implicitWidth: suspRow.implicitWidth + 20
            radius: 17
            color: suspMouse.containsMouse ? root.withAlpha(cfgStr("primary", "#cba6f7"), 0.16) : root.colNotchBg
            border.width: 1
            border.color: root.colBorder
            scale: suspMouse.pressed ? 0.94 : 1.0

            Behavior on scale { enabled: !root.reducedMotion; NumberAnimation { duration: 90 } }

            RowLayout {
                id: suspRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "󰒲"
                    font.family: root.iconFont
                    font.pixelSize: 13
                    color: root.colSecondary
                }
                Text {
                    text: "Suspend"
                    font.family: root.uiFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: root.colFg
                }
            }

            MouseArea {
                id: suspMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.suspend()
            }
        }

        Rectangle {
            id: sddmRebootBtn
            visible: typeof sddm === "undefined" || sddm.canReboot
            readonly property bool isPending: root.confirmPowerAction === "reboot"
            implicitHeight: 34
            implicitWidth: rebRow.implicitWidth + 20
            radius: 17
            color: sddmRebootBtn.isPending
                ? root.colWarning
                : (rebMouse.containsMouse ? root.withAlpha(cfgStr("warning", "#f9e2af"), 0.22) : root.colNotchBg)
            border.width: 1
            border.color: sddmRebootBtn.isPending ? root.colWarning : root.colBorder
            scale: rebMouse.pressed ? 0.94 : 1.0

            Behavior on scale { enabled: !root.reducedMotion; NumberAnimation { duration: 90 } }

            RowLayout {
                id: rebRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "󰜉"
                    font.family: root.iconFont
                    font.pixelSize: 13
                    color: sddmRebootBtn.isPending ? root.colOnPrimary : root.colWarning
                }
                Text {
                    text: sddmRebootBtn.isPending ? "Confirm Reboot?" : "Reboot"
                    font.family: root.uiFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: sddmRebootBtn.isPending ? root.colOnPrimary : root.colFg
                }
            }

            MouseArea {
                id: rebMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.confirmPowerAction !== "reboot") {
                        root.confirmPowerAction = "reboot";
                        powerConfirmTimer.restart();
                    } else {
                        sddm.reboot();
                    }
                }
            }
        }

        Rectangle {
            id: sddmPowerBtn
            visible: typeof sddm === "undefined" || sddm.canPowerOff
            readonly property bool isPending: root.confirmPowerAction === "poweroff"
            implicitHeight: 34
            implicitWidth: pwrRow.implicitWidth + 20
            radius: 17
            color: sddmPowerBtn.isPending
                ? root.colError
                : (pwrMouse.containsMouse ? root.withAlpha(cfgStr("error", "#f38ba8"), 0.22) : root.colNotchBg)
            border.width: 1
            border.color: sddmPowerBtn.isPending ? root.colError : root.colBorder
            scale: pwrMouse.pressed ? 0.94 : 1.0

            Behavior on scale { enabled: !root.reducedMotion; NumberAnimation { duration: 90 } }

            RowLayout {
                id: pwrRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "󰐥"
                    font.family: root.iconFont
                    font.pixelSize: 13
                    color: sddmPowerBtn.isPending ? root.colOnError : root.colError
                }
                Text {
                    text: sddmPowerBtn.isPending ? "Confirm Poweroff?" : "Poweroff"
                    font.family: root.uiFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: sddmPowerBtn.isPending ? root.colOnError : root.colFg
                }
            }

            MouseArea {
                id: pwrMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.confirmPowerAction !== "poweroff") {
                        root.confirmPowerAction = "poweroff";
                        powerConfirmTimer.restart();
                    } else {
                        sddm.powerOff();
                    }
                }
            }
        }
    }
}
