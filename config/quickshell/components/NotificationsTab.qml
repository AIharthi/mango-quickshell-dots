pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root

    property bool active: false

    signal inputFocusChanged(bool focused)

    spacing: 10

    // --- Calendar & Left Column State ---
    property int viewYear: (new Date()).getFullYear()
    property int viewMonth: (new Date()).getMonth()    // 0..11
    property string timerMode: "timer"               // "timer" | "stopwatch"
    property string bottomWidget: "timer"            // "timer" | "notes"

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    function shiftMonth(delta: int): void {
        let m = root.viewMonth + delta;
        let y = root.viewYear;
        while (m < 0) {
            m += 12;
            y -= 1;
        }
        while (m >= 12) {
            m -= 12;
            y += 1;
        }
        root.viewMonth = m;
        root.viewYear = y;
    }

    function goToday(): void {
        const now = new Date();
        root.viewYear = now.getFullYear();
        root.viewMonth = now.getMonth();
    }

    readonly property var calendarCells: {
        const y = root.viewYear;
        const m = root.viewMonth;
        const now = new Date();
        const todayY = now.getFullYear();
        const todayM = now.getMonth();
        const todayD = now.getDate();

        const firstWeekday = (new Date(y, m, 1)).getDay(); // 0=Sun..6=Sat
        const daysInMonth = (new Date(y, m + 1, 0)).getDate();
        const daysInPrev = (new Date(y, m, 0)).getDate();

        const cells = [];
        for (let i = firstWeekday - 1; i >= 0; i--) {
            cells.push({ day: daysInPrev - i, inMonth: false, isToday: false });
        }
        for (let d = 1; d <= daysInMonth; d++) {
            cells.push({
                day: d,
                inMonth: true,
                isToday: (y === todayY && m === todayM && d === todayD)
            });
        }
        let nextDay = 1;
        while (cells.length < 42) {
            cells.push({ day: nextDay++, inMonth: false, isToday: false });
        }
        return cells;
    }

    // Sync scratchpad text from ShellState without fighting active user edits
    Connections {
        target: ShellState
        function onScratchpadTextChanged(): void {
            if (!scratchInput.activeFocus && scratchInput.text !== ShellState.scratchpadText)
                scratchInput.text = ShellState.scratchpadText;
        }
    }

    Timer {
        id: scratchSaveTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (scratchInput.text !== ShellState.scratchpadText)
                ShellState.setPref("scratchpadText", scratchInput.text);
        }
    }

    onActiveChanged: {
        if (active) {
            ShellState.clearUnread();
            if (!scratchInput.activeFocus && scratchInput.text !== ShellState.scratchpadText)
                scratchInput.text = ShellState.scratchpadText;
        } else {
            if (scratchInput.activeFocus)
                scratchInput.focus = false;
            inputFocusChanged(false);
        }
    }

    // ==================== LEFT COLUMN: Calendar + Focus Timer + Scratchpad ====================
    ColumnLayout {
        Layout.preferredWidth: 288
        Layout.minimumWidth: 280
        Layout.maximumWidth: 294
        Layout.fillHeight: true
        spacing: 8

        // --- Month Calendar Card ---
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 206
            Layout.minimumHeight: 202
            Layout.maximumHeight: 212
            radius: Theme.r(18)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder
            clip: true

            ColumnLayout {
                id: calCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 4

                    Text {
                        text: root.monthNames[root.viewMonth] + " " + root.viewYear
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: Theme.r(11)
                        color: prevM.containsMouse ? Theme.hoverBg : Theme.subCardBg

                        Text {
                            anchors.centerIn: parent
                            text: "󰅁"
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: prevM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shiftMonth(-1)
                        }
                    }

                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: todayLbl.implicitWidth + 12
                        radius: Theme.r(11)
                        color: todayM.containsMouse ? Theme.hoverBg : Theme.subCardBg

                        Text {
                            id: todayLbl
                            anchors.centerIn: parent
                            text: "Today"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Theme.primary
                        }

                        MouseArea {
                            id: todayM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goToday()
                        }
                    }

                    Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: Theme.r(11)
                        color: nextM.containsMouse ? Theme.hoverBg : Theme.subCardBg

                        Text {
                            anchors.centerIn: parent
                            text: "󰅂"
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: nextM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shiftMonth(1)
                        }
                    }
                }

                // Weekday headers + Circular Apple Day Cells
                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    rowSpacing: 2
                    columnSpacing: 2

                    Repeater {
                        model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                        delegate: Text {
                            required property string modelData
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Repeater {
                        model: root.calendarCells
                        delegate: Item {
                            id: dayCell
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 21

                            Rectangle {
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                radius: 10
                                color: dayCell.modelData.isToday
                                    ? Theme.primary
                                    : (dayHover.containsMouse && dayCell.modelData.inMonth ? Theme.hoverBg : "transparent")
                            }

                            Text {
                                anchors.centerIn: parent
                                text: dayCell.modelData.day
                                font.family: Theme.monoFont
                                font.pixelSize: 10
                                font.weight: dayCell.modelData.isToday ? Font.Bold : Font.Medium
                                color: {
                                    if (dayCell.modelData.isToday)
                                        return Theme.fgPrimary;
                                    return dayCell.modelData.inMonth
                                        ? Theme.fgSurface
                                        : Theme.withAlpha(Theme.fgSurfaceVariant, Theme.isDark ? 0.62 : 0.68);
                                }
                            }

                            MouseArea {
                                id: dayHover
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }
                    }
                }
            }
        }

        // --- 2-Segment Bottom Drawer Switcher (Focus & Weather | Notes) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            Layout.minimumHeight: 30
            Layout.maximumHeight: 30
            radius: Theme.r(15)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 4

                Repeater {
                    model: [
                        { id: "timer", label: "󰔛 Focus & Weather" },
                        { id: "notes", label: "󰎞 Notes" }
                    ]

                    delegate: Rectangle {
                        id: bwTab
                        required property var modelData
                        readonly property bool sel: root.bottomWidget === bwTab.modelData.id
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.r(12)
                        color: bwTab.sel ? Theme.primary : (bwMouse.containsMouse ? Theme.hoverBg : "transparent")

                        Text {
                            anchors.centerIn: parent
                            text: bwTab.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: bwTab.sel ? Font.Bold : Font.Medium
                            color: bwTab.sel ? Theme.fgPrimary : Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: bwMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.bottomWidget = bwTab.modelData.id
                        }
                    }
                }
            }
        }

        // --- Focus / Pomodoro Timer & Stopwatch Card ---
        Rectangle {
            visible: root.bottomWidget === "timer"
            Layout.fillWidth: true
            Layout.fillHeight: !ShellState.weatherEnabled
            implicitHeight: timerCol.implicitHeight + 20
            radius: Theme.r(18)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: (ShellState.timerActive || ShellState.stopwatchActive) ? Theme.primary : Theme.cardBorder
            clip: true

            ColumnLayout {
                id: timerCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 7

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 4

                    RowLayout {
                        spacing: 12

                        Item {
                            implicitWidth: tglTimerCol.implicitWidth
                            implicitHeight: tglTimerCol.implicitHeight

                            Column {
                                id: tglTimerCol
                                spacing: 2
                                Text {
                                    text: "Timer"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: root.timerMode === "timer" ? Font.Bold : Font.Medium
                                    color: root.timerMode === "timer" ? Theme.primary : Theme.fgSurfaceVariant
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 2
                                    radius: 1
                                    color: Theme.primary
                                    visible: root.timerMode === "timer"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.timerMode = "timer"
                            }
                        }

                        Item {
                            implicitWidth: tglSwCol.implicitWidth
                            implicitHeight: tglSwCol.implicitHeight

                            Column {
                                id: tglSwCol
                                spacing: 2
                                Text {
                                    text: "Stopwatch"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: root.timerMode === "stopwatch" ? Font.Bold : Font.Medium
                                    color: root.timerMode === "stopwatch" ? Theme.primary : Theme.fgSurfaceVariant
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 2
                                    radius: 1
                                    color: Theme.primary
                                    visible: root.timerMode === "stopwatch"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.timerMode = "stopwatch"
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: ShellState.weatherEnabled
                        text: root.timerMode === "timer"
                            ? ShellState.formatTimer(ShellState.timerRemainingSec)
                            : ShellState.formatTimer(ShellState.stopwatchElapsedSec)
                        font.family: Theme.monoFont
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        color: (root.timerMode === "timer" ? ShellState.timerActive : ShellState.stopwatchActive)
                            ? Theme.primary
                            : Theme.fgSurface
                    }
                }

                // Expanded Apple Focus Hero Time (when Weather card is hidden, fills space gracefully)
                Item {
                    Layout.fillHeight: !ShellState.weatherEnabled
                    visible: !ShellState.weatherEnabled
                }

                ColumnLayout {
                    visible: !ShellState.weatherEnabled
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 2

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.timerMode === "timer"
                            ? ShellState.formatTimer(ShellState.timerRemainingSec)
                            : ShellState.formatTimer(ShellState.stopwatchElapsedSec)
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        font.weight: Font.Bold
                        color: (root.timerMode === "timer" ? ShellState.timerActive : ShellState.stopwatchActive)
                            ? Theme.primary
                            : Theme.fgSurface
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.timerMode === "timer"
                            ? (ShellState.timerActive ? "Focus session running" : "Focus Timer Ready")
                            : (ShellState.stopwatchActive ? "Stopwatch running" : "Stopwatch Ready")
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        color: Theme.fgSurfaceVariant
                    }
                }

                // Subtle Apple Progress Bar during active Timer
                Rectangle {
                    visible: root.timerMode === "timer" && ShellState.timerDurationSec > 0
                    Layout.fillWidth: true
                    implicitHeight: 5
                    radius: 2.5
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.max(0.0, Math.min(1.0, ShellState.timerRemainingSec / Math.max(1, ShellState.timerDurationSec)))
                        radius: 2.5
                        color: Theme.primary
                    }
                }

                Item {
                    Layout.fillHeight: !ShellState.weatherEnabled
                    visible: !ShellState.weatherEnabled
                }

                // Timer Presets + Controls
                RowLayout {
                    visible: root.timerMode === "timer"
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 4

                    Repeater {
                        model: [5, 15, 25, 45]
                        delegate: Rectangle {
                            id: preBtn
                            required property int modelData
                            readonly property bool isSel: ShellState.timerDurationSec === preBtn.modelData * 60
                            implicitHeight: 24
                            Layout.fillWidth: true
                            radius: Theme.r(12)
                            color: preBtn.isSel
                                ? Theme.activeBg
                                : (preMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)

                            Text {
                                anchors.centerIn: parent
                                text: preBtn.modelData + "m"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: preBtn.isSel ? Theme.primary : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: preMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.resetTimer(preBtn.modelData * 60)
                            }
                        }
                    }

                    Rectangle {
                        implicitHeight: 24
                        implicitWidth: startLbl.implicitWidth + 14
                        radius: Theme.r(12)
                        color: ShellState.timerActive
                            ? Theme.withAlpha(Theme.warning, 0.24)
                            : Theme.primary

                        Text {
                            id: startLbl
                            anchors.centerIn: parent
                            text: ShellState.timerActive ? "Pause" : "Start"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: ShellState.timerActive ? Theme.warning : Theme.fgPrimary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.toggleTimer()
                        }
                    }

                    Rectangle {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: Theme.r(12)
                        color: rstMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                        Text {
                            anchors.centerIn: parent
                            text: "󰑐"
                            font.family: Theme.iconFont
                            font.pixelSize: 11
                            color: Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: rstMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.resetTimer(ShellState.timerDurationSec)
                        }
                    }
                }

                // Stopwatch Controls + Laps
                ColumnLayout {
                    visible: root.timerMode === "stopwatch"
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Theme.r(12)
                            color: ShellState.stopwatchActive
                                ? Theme.withAlpha(Theme.warning, 0.24)
                                : Theme.primary

                            Text {
                                anchors.centerIn: parent
                                text: ShellState.stopwatchActive ? "Pause" : "Start"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: ShellState.stopwatchActive ? Theme.warning : Theme.fgPrimary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.toggleStopwatch()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Theme.r(12)
                            color: lapMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                            Text {
                                anchors.centerIn: parent
                                text: "Lap"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: Theme.secondary
                            }
                            MouseArea {
                                id: lapMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.addStopwatchLap()
                            }
                        }

                        Rectangle {
                            implicitWidth: 24
                            implicitHeight: 24
                            radius: Theme.r(12)
                            color: swRstMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                font.family: Theme.iconFont
                                font.pixelSize: 11
                                color: Theme.fgSurfaceVariant
                            }
                            MouseArea {
                                id: swRstMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.resetStopwatch()
                            }
                        }
                    }

                    Row {
                        visible: (ShellState.stopwatchLaps || []).length > 0
                        spacing: 4

                        Repeater {
                            model: (ShellState.stopwatchLaps || []).slice(0, 4)
                            delegate: Rectangle {
                                id: lapBadge
                                required property string modelData
                                required property int index
                                implicitHeight: 17
                                implicitWidth: lapTxt.implicitWidth + 10
                                radius: Theme.r(8)
                                color: Theme.subCardBg

                                Text {
                                    id: lapTxt
                                    anchors.centerIn: parent
                                    text: "#" + ((ShellState.stopwatchLaps || []).length - lapBadge.index) + " " + lapBadge.modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                    color: Theme.fgSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- Opt-In Compact Weather Card ---
        Rectangle {
            visible: root.bottomWidget === "timer" && ShellState.weatherEnabled
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: wCol.implicitHeight + 18
            radius: Theme.r(18)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder
            clip: true

            RowLayout {
                id: wCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                Text {
                    text: ShellState.weatherIcon
                    font.family: Theme.iconFont
                    font.pixelSize: 22
                    color: Theme.primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: ShellState.weatherAvailable
                            ? (ShellState.weatherTemp + " · " + ShellState.weatherCondition)
                            : "Weather unavailable"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: ShellState.weatherAvailable
                            ? (ShellState.weatherCity + " · 󰖎 " + ShellState.weatherHumidity + " · " + ShellState.weatherWind)
                            : "Click refresh or check Settings under Shell"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    implicitWidth: 24
                    implicitHeight: 24
                    radius: Theme.r(12)
                    color: wRefMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                    Text {
                        anchors.centerIn: parent
                        text: "󰑐"
                        font.family: Theme.iconFont
                        font.pixelSize: 11
                        color: Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: wRefMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.refreshWeather(true)
                    }
                }
            }
        }

        // --- Quick Scratchpad Card ---
        Rectangle {
            visible: root.bottomWidget === "notes"
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.r(18)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: scratchInput.activeFocus ? Theme.primary : Theme.cardBorder
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Notes"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.fgSurfaceVariant
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: scratchInput.text.length > 0
                        text: "Clear"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: clrNoteMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant

                        MouseArea {
                            id: clrNoteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                scratchInput.text = "";
                                ShellState.setPref("scratchpadText", "");
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Text {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        visible: scratchInput.text.length === 0
                        text: "Type a quick note (auto-saved)..."
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }

                    TextEdit {
                        id: scratchInput
                        anchors.fill: parent
                        wrapMode: TextEdit.Wrap
                        color: Theme.fgSurface
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.fgPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        text: ShellState.scratchpadText

                        onTextChanged: {
                            if (activeFocus)
                                scratchSaveTimer.restart();
                        }
                        onActiveFocusChanged: {
                            root.inputFocusChanged(activeFocus);
                            if (!activeFocus && scratchInput.text !== ShellState.scratchpadText)
                                ShellState.setPref("scratchpadText", scratchInput.text);
                        }
                    }
                }
            }
        }
    }

    // ==================== RIGHT COLUMN: macOS Notification Center ====================
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(18)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 6

                Text {
                    text: "Notifications"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: cntLbl.implicitWidth + 10
                    radius: Theme.r(10)
                    color: Theme.subCardBg

                    Text {
                        id: cntLbl
                        anchors.centerIn: parent
                        text: String((ShellState.notificationHistory || []).length)
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: dndRow.implicitWidth + 12
                    radius: Theme.r(12)
                    color: ShellState.dnd
                        ? Theme.withAlpha(Theme.warning, 0.20)
                        : (dndMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: ShellState.dnd ? 1 : Theme.subBorderWidth
                    border.color: ShellState.dnd ? Theme.warning : Theme.cardBorder

                    RowLayout {
                        id: dndRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: ShellState.dnd ? "󰂛" : "󰂚"
                            font.family: Theme.iconFont
                            font.pixelSize: 11
                            color: ShellState.dnd ? Theme.warning : Theme.fgSurfaceVariant
                        }
                        Text {
                            text: ShellState.dnd ? "DND On" : "DND"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: ShellState.dnd ? Theme.warning : Theme.fgSurfaceVariant
                        }
                    }

                    MouseArea {
                        id: dndMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.toggleDnd()
                    }
                }

                Rectangle {
                    visible: (ShellState.notificationHistory || []).length > 0
                    implicitHeight: 24
                    implicitWidth: clrAllLbl.implicitWidth + 12
                    radius: Theme.r(12)
                    color: clrAllMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.20) : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: clrAllMouse.containsMouse ? Theme.error : Theme.cardBorder

                    Text {
                        id: clrAllLbl
                        anchors.centerIn: parent
                        text: "Clear All"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: clrAllMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: clrAllMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.clearHistory()
                    }
                }
            }

            // Notification Feed
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: notifList
                    anchors.fill: parent
                    spacing: 6
                    clip: true
                    model: ShellState.notificationHistory || []

                    delegate: Rectangle {
                        id: nCard
                        required property var modelData
                        readonly property bool urgent: Number(nCard.modelData.urgency || 0) === 2

                        width: notifList.width
                        implicitHeight: nCol.implicitHeight + 18
                        radius: Theme.r(14)
                        color: Theme.subCardBg
                        border.width: nCard.urgent ? 1 : Theme.subBorderWidth
                        border.color: nCard.urgent ? Theme.withAlpha(Theme.error, 0.65) : Theme.cardBorder
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8
                            width: 3
                            radius: 1.5
                            color: nCard.urgent ? Theme.error : Theme.primary
                        }

                        ColumnLayout {
                            id: nCol
                            anchors.fill: parent
                            anchors.leftMargin: 13
                            anchors.rightMargin: 9
                            anchors.topMargin: 9
                            anchors.bottomMargin: 9
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    radius: Theme.r(10)
                                    color: nCard.urgent ? Theme.withAlpha(Theme.error, 0.20) : Theme.withAlpha(Theme.primary, 0.16)

                                    Text {
                                        anchors.centerIn: parent
                                        text: nCard.urgent ? "󰀨" : "󰂚"
                                        font.family: Theme.iconFont
                                        font.pixelSize: 10
                                        color: nCard.urgent ? Theme.error : Theme.primary
                                    }
                                }

                                Text {
                                    text: nCard.modelData.appName || "System"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: nCard.urgent ? Theme.error : Theme.primary
                                }

                                Text {
                                    text: nCard.modelData.timeStr || ""
                                    font.family: Theme.monoFont
                                    font.pixelSize: 9
                                    color: Theme.fgSurfaceVariant
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    radius: Theme.r(10)
                                    color: dismissMouse.containsMouse ? Theme.hoverBg : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        font.family: Theme.iconFont
                                        font.pixelSize: 10
                                        color: Theme.fgSurfaceVariant
                                    }

                                    MouseArea {
                                        id: dismissMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ShellState.dismissNotification(nCard.modelData.uid)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: {
                                    const s = String(nCard.modelData.summary || "").trim();
                                    const a = String(nCard.modelData.appName || "System").trim();
                                    return s.length > 0 && s.toLowerCase() !== a.toLowerCase();
                                }
                                text: nCard.modelData.summary || ""
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: String(nCard.modelData.body || "").replace(/\n+/g, " ")
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: (ShellState.notificationHistory || []).length === 0
                    spacing: 8

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 50
                        implicitHeight: 50
                        radius: Theme.r(25)
                        color: Theme.subCardBg

                        Text {
                            anchors.centerIn: parent
                            text: ShellState.dnd ? "󰂛" : "󰂜"
                            font.family: Theme.iconFont
                            font.pixelSize: 24
                            color: ShellState.dnd ? Theme.warning : Theme.primary
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: ShellState.dnd ? "Do Not Disturb is active" : "No Notifications"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: ShellState.dnd ? "Desktop alerts are silenced" : "You're all caught up"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }
                }
            }
        }
    }
}
