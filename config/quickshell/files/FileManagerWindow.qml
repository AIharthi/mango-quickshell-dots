pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root

    property bool isOpen: true
    property string initialPath: "~"
    property bool _entered: false
    readonly property bool shown: root.isOpen && root._entered

    signal closeRequested()
    signal openSettingsRequested(string page)

    Component.onCompleted: Qt.callLater(() => { root._entered = true; })
    onIsOpenChanged: {
        if (!isOpen) {
            customizeOpen = false;
            contextOpen = false;
            promptOpen = false;
            pathEditOpen = false;
        }
    }

    // --- Visual Styling & Rust Daemon Bridge ---
    FileStyleHelper { id: fstyle }
    FilesBackend {
        id: backend
        active: root.isOpen
        onReadyChanged: {
            if (ready) {
                refreshPlaces();
                loadActiveTab(true);
            }
        }
    }

    // --- State Model ---
    property var placesData: ({ places: [], bookmarks: [], drives: [], trashCount: 0 })
    property bool customizeOpen: false
    property string statusToast: ""
    property bool isErrorToast: false

    // Internal Clipboard (also mirrored to Wayland text/uri-list)
    property var clipboardPaths: []
    property string clipboardOp: "" // "copy" | "cut"

    // Tab State: [{ id, title, activePane (0|1), panes: [paneObj, paneObj] }]
    function createPaneState(startPath: string): var {
        return {
            path: startPath,
            displayPath: startPath,
            parent: "",
            breadcrumbs: [],
            dirStamp: "",
            history: [startPath],
            histIndex: 0,
            entries: [],
            parentEntries: [],
            millerChildEntries: [],
            millerChildTitle: "",
            filteredEntries: [],
            selectedPaths: [],
            focusedIndex: -1,
            anchorIndex: -1,
            isTrashView: false,
            searchQuery: "",
            recursiveSearch: false,
            searchEntries: [],
            searching: false,
            loading: false,
            totalCount: 0,
            dirCount: 0,
            fileCount: 0,
            totalHumanSize: "0 B"
        };
    }

    function resolvedStartPath(): string {
        if (root.initialPath && root.initialPath.length > 0 && root.initialPath !== "")
            return root.initialPath;
        if (ShellState.fmStartDir === "@last" && ShellState.fmLastDir && ShellState.fmLastDir.length > 0)
            return ShellState.fmLastDir;
        return "~";
    }

    property int _nextTabId: 2
    property var tabs: [
        {
            id: 1,
            title: "Home",
            activePane: 0,
            panes: [createPaneState(resolvedStartPath()), createPaneState("~")]
        }
    ]
    property int activeTabIndex: 0

    // Preview State
    property var previewData: null
    property bool previewLoading: false

    // Context Menu State
    property bool contextOpen: false
    property real contextX: 0
    property real contextY: 0
    property var contextEntry: null

    // Path Edit / Prompt Modal State
    property bool pathEditOpen: false
    property bool promptOpen: false
    property string promptKind: ""     // "mkdir" | "touch" | "rename" | "compress" | "delete" | "empty_trash"
    property string promptTitle: ""
    property string promptText: ""
    property var promptTarget: null

    Timer {
        id: toastTimer
        interval: 2800
        repeat: false
        onTriggered: {
            root.statusToast = "";
            root.isErrorToast = false;
        }
    }

    function showToast(msg: string, isErr: bool): void {
        root.statusToast = msg;
        root.isErrorToast = !!isErr;
        toastTimer.restart();
    }

    function currentTab(): var {
        if (!root.tabs || root.tabs.length === 0)
            return null;
        const idx = Math.max(0, Math.min(root.tabs.length - 1, root.activeTabIndex));
        return root.tabs[idx];
    }

    function getPane(tabIdx: int, paneIdx: int): var {
        const t = root.tabs[tabIdx];
        return (t && t.panes && t.panes[paneIdx]) ? t.panes[paneIdx] : null;
    }

    function activePane(): var {
        const t = currentTab();
        if (!t) return null;
        return t.panes[t.activePane] || t.panes[0];
    }

    function otherPaneIndex(): int {
        const t = currentTab();
        return t ? (t.activePane === 0 ? 1 : 0) : 0;
    }

    function updatePane(tabIdx: int, paneIdx: int, mutator: var): void {
        const nextTabs = root.tabs.slice();
        const t = Object.assign({}, nextTabs[tabIdx]);
        const panes = t.panes.slice();
        const p = Object.assign({}, panes[paneIdx]);
        mutator(p, t);
        p.filteredEntries = computeFiltered(p);
        panes[paneIdx] = p;
        t.panes = panes;
        nextTabs[tabIdx] = t;
        root.tabs = nextTabs;
    }

    function computeFiltered(pane: var): var {
        if (pane.recursiveSearch && (pane.searchQuery || "").trim().length > 0)
            return pane.searchEntries || [];
        const base = pane.entries || [];
        const q = (pane.searchQuery || "").trim().toLowerCase();
        if (q.length === 0)
            return base;
        return base.filter(e => String(e.name || "").toLowerCase().indexOf(q) !== -1);
    }

    function isPathBookmarked(p: string): bool {
        const list = root.placesData.bookmarks || [];
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].path || "") === p)
                return true;
        }
        return false;
    }

    function displayBreadcrumbs(rawList: var): var {
        const raw = Array.isArray(rawList) ? rawList : [];
        const home = Quickshell.env("HOME") || "";
        if (home.length > 0) {
            for (let i = 0; i < raw.length; i++) {
                if (String(raw[i].path || "") === home) {
                    const out = [{ label: "Home", path: home, isHome: true }];
                    for (let j = i + 1; j < raw.length; j++) {
                        out.push({
                            label: String(raw[j].label || ""),
                            path: String(raw[j].path || ""),
                            isHome: false
                        });
                    }
                    return out;
                }
            }
        }
        return raw.map(c => ({
            label: String(c.label || ""),
            path: String(c.path || ""),
            isHome: false
        }));
    }

    function refreshPlaces(): void {
        backend.getPlaces((ok, data, err) => {
            if (ok && data)
                root.placesData = data;
        });
    }

    function loadPane(tabIdx: int, paneIdx: int, preserveSelection: bool): void {
        const pane = getPane(tabIdx, paneIdx);
        if (!pane) return;

        if (pane.isTrashView) {
            updatePane(tabIdx, paneIdx, (p) => { p.loading = true; });
            backend.trashList((ok, data, err) => {
                updatePane(tabIdx, paneIdx, (p, t) => {
                    p.loading = false;
                    if (ok && data) {
                        p.entries = data.entries || [];
                        p.displayPath = "Trash";
                        p.totalCount = Number(data.totalCount || 0);
                        p.dirCount = 0;
                        p.fileCount = p.totalCount;
                        p.totalHumanSize = "";
                        if (!preserveSelection) {
                            p.selectedPaths = [];
                            p.focusedIndex = p.entries.length > 0 ? 0 : -1;
                        }
                        if (paneIdx === t.activePane)
                            t.title = "Trash";
                    } else if (err) {
                        root.showToast(err, true);
                    }
                });
            });
            return;
        }

        const reqPath = pane.path;
        updatePane(tabIdx, paneIdx, (p) => { p.loading = true; });
        backend.listDir(reqPath, ShellState.fmShowHidden, ShellState.fmSortBy, ShellState.fmSortDesc, ShellState.fmDirsFirst, (ok, data, err) => {
            if (!ok || !data) {
                updatePane(tabIdx, paneIdx, (p) => { p.loading = false; });
                if (err) root.showToast(err, true);
                return;
            }
            const realPath = String(data.path || reqPath);
            updatePane(tabIdx, paneIdx, (p, t) => {
                p.loading = false;
                p.path = realPath;
                p.displayPath = String(data.displayPath || realPath);
                p.parent = String(data.parent || "");
                p.breadcrumbs = data.breadcrumbs || [];
                p.dirStamp = String(data.dirStamp || "");
                p.entries = data.entries || [];
                p.totalCount = Number(data.totalCount || 0);
                p.dirCount = Number(data.dirCount || 0);
                p.fileCount = Number(data.fileCount || 0);
                p.totalHumanSize = String(data.totalHumanSize || "0 B");
                if (p.history && p.history.length > 0 && p.histIndex >= 0 && p.histIndex < p.history.length)
                    p.history[p.histIndex] = realPath;
                if (!preserveSelection) {
                    p.selectedPaths = [];
                    p.focusedIndex = p.entries.length > 0 ? 0 : -1;
                }
                if (paneIdx === t.activePane) {
                    const segs = realPath.split("/").filter(s => s.length > 0);
                    t.title = segs.length > 0 ? segs[segs.length - 1] : "/";
                }
            });

            if (tabIdx === root.activeTabIndex && paneIdx === root.currentTab().activePane) {
                ShellState.setPref("fmLastDir", realPath);
                const updated = getPane(tabIdx, paneIdx);
                if (updated && updated.filteredEntries.length > 0) {
                    const idx = Math.max(0, Math.min(updated.filteredEntries.length - 1, updated.focusedIndex));
                    inspectEntry(updated.filteredEntries[idx]);
                } else {
                    inspectEntry({ path: realPath, isDir: true });
                }
                if (ShellState.fmViewMode === "miller")
                    loadMillerParent(tabIdx, paneIdx, String(data.parent || ""));
            }
        });
    }

    function loadMillerParent(tabIdx: int, paneIdx: int, parentPath: string): void {
        if (!parentPath || parentPath.length === 0) {
            updatePane(tabIdx, paneIdx, (p) => { p.parentEntries = []; });
            return;
        }
        backend.listDir(parentPath, ShellState.fmShowHidden, ShellState.fmSortBy, ShellState.fmSortDesc, ShellState.fmDirsFirst, (ok, data) => {
            if (ok && data) {
                updatePane(tabIdx, paneIdx, (p) => { p.parentEntries = data.entries || []; });
            }
        });
    }

    function loadMillerChild(tabIdx: int, paneIdx: int, entry: var): void {
        if (ShellState.fmViewMode !== "miller")
            return;
        if (!entry || !entry.isDir) {
            updatePane(tabIdx, paneIdx, (p) => {
                p.millerChildEntries = [];
                p.millerChildTitle = entry ? String(entry.name || "") : "";
            });
            return;
        }
        backend.listDir(String(entry.path || ""), ShellState.fmShowHidden, ShellState.fmSortBy, ShellState.fmSortDesc, ShellState.fmDirsFirst, (ok, data) => {
            if (ok && data) {
                updatePane(tabIdx, paneIdx, (p) => {
                    p.millerChildEntries = (data.entries || []).slice(0, 80);
                    p.millerChildTitle = String(entry.name || "");
                });
            }
        });
    }

    function loadActiveTab(bothPanes: bool): void {
        const ti = root.activeTabIndex;
        const t = root.currentTab();
        if (!t) return;
        loadPane(ti, t.activePane, false);
        if (bothPanes || ShellState.fmDualPane)
            loadPane(ti, root.otherPaneIndex(), false);
    }

    function reloadBothActivePanes(preserveSel: bool): void {
        const ti = root.activeTabIndex;
        const t = root.currentTab();
        if (!t) return;
        loadPane(ti, t.activePane, preserveSel);
        if (ShellState.fmDualPane)
            loadPane(ti, root.otherPaneIndex(), preserveSel);
        refreshPlaces();
    }

    function inspectEntry(entry: var): void {
        if (!entry || !entry.path)
            return;
        const targetPath = String(entry.path);
        const ti = root.activeTabIndex;
        const t = root.currentTab();
        if (t && ShellState.fmViewMode === "miller")
            loadMillerChild(ti, t.activePane, entry);
        if (!ShellState.fmPreviewVisible)
            return;
        root.previewLoading = true;
        backend.previewPath(targetPath, (ok, data) => {
            root.previewLoading = false;
            if (ok && data)
                root.previewData = data;
        });
    }

    function navigateTo(rawPath: string, targetPaneIdx: int): void {
        const ti = root.activeTabIndex;
        const t = root.currentTab();
        if (!t) return;
        const pi = targetPaneIdx >= 0 ? targetPaneIdx : t.activePane;
        root.pathEditOpen = false;
        updatePane(ti, pi, (p) => {
            const trimmedHist = p.history.slice(0, p.histIndex + 1);
            if (trimmedHist.length === 0 || trimmedHist[trimmedHist.length - 1] !== rawPath) {
                trimmedHist.push(rawPath);
                p.history = trimmedHist;
                p.histIndex = trimmedHist.length - 1;
            }
            p.path = rawPath;
            p.isTrashView = false;
            p.searchQuery = "";
            p.recursiveSearch = false;
            p.searchEntries = [];
        });
        loadPane(ti, pi, false);
    }

    function openTrashInActivePane(): void {
        const ti = root.activeTabIndex;
        const t = root.currentTab();
        if (!t) return;
        updatePane(ti, t.activePane, (p) => {
            p.isTrashView = true;
            p.searchQuery = "";
            p.recursiveSearch = false;
        });
        loadPane(ti, t.activePane, false);
    }

    function goBack(): void {
        const ti = root.activeTabIndex;
        const t = root.currentTab();
        if (!t) return;
        const p = activePane();
        if (!p || p.histIndex <= 0) return;
        updatePane(ti, t.activePane, (pane) => {
            pane.histIndex -= 1;
            pane.path = pane.history[pane.histIndex];
            pane.isTrashView = false;
            pane.searchQuery = "";
            pane.recursiveSearch = false;
        });
        loadPane(ti, t.activePane, false);
    }

    function goForward(): void {
        const ti = root.activeTabIndex;
        const t = root.currentTab();
        if (!t) return;
        const p = activePane();
        if (!p || p.histIndex + 1 >= p.history.length) return;
        updatePane(ti, t.activePane, (pane) => {
            pane.histIndex += 1;
            pane.path = pane.history[pane.histIndex];
            pane.isTrashView = false;
            pane.searchQuery = "";
            pane.recursiveSearch = false;
        });
        loadPane(ti, t.activePane, false);
    }

    function goUp(): void {
        const p = activePane();
        if (!p || p.isTrashView || !p.parent || p.parent.length === 0)
            return;
        navigateTo(p.parent, -1);
    }

    function addTab(startPath: string): void {
        const id = root._nextTabId++;
        const sp = startPath && startPath.length > 0 ? startPath : "~";
        const newTab = {
            id: id,
            title: sp === "~" ? "Home" : sp.split("/").pop(),
            activePane: 0,
            panes: [createPaneState(sp), createPaneState("~")]
        };
        const nextTabs = root.tabs.concat([newTab]);
        root.tabs = nextTabs;
        root.activeTabIndex = nextTabs.length - 1;
        loadActiveTab(false);
    }

    function closeTab(idx: int): void {
        if (root.tabs.length <= 1) {
            root.closeRequested();
            return;
        }
        const nextTabs = root.tabs.slice();
        nextTabs.splice(idx, 1);
        root.tabs = nextTabs;
        root.activeTabIndex = Math.max(0, Math.min(nextTabs.length - 1, root.activeTabIndex));
        loadActiveTab(false);
    }

    function runRecursiveSearch(): void {
        const ti = root.activeTabIndex;
        const t = root.currentTab();
        if (!t) return;
        const p = activePane();
        if (!p) return;
        const q = (p.searchQuery || "").trim();
        if (!p.recursiveSearch || q.length === 0) {
            updatePane(ti, t.activePane, (pane) => {
                pane.searchEntries = [];
                pane.searching = false;
            });
            return;
        }
        updatePane(ti, t.activePane, (pane) => { pane.searching = true; });
        backend.searchDir(p.path, q, ShellState.fmShowHidden, 140, (ok, data, err) => {
            updatePane(ti, t.activePane, (pane) => {
                pane.searching = false;
                if (ok && data)
                    pane.searchEntries = data.entries || [];
            });
            if (!ok && err) root.showToast(err, true);
        });
    }

    // --- Selection Helpers ---
    function handleSelection(tabIdx: int, paneIdx: int, path: string, ctrl: bool, shift: bool): void {
        const pane = getPane(tabIdx, paneIdx);
        if (!pane) return;
        const list = pane.filteredEntries || [];
        let clickedIdx = -1;
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].path || "") === path) {
                clickedIdx = i;
                break;
            }
        }
        updatePane(tabIdx, paneIdx, (p) => {
            const cur = p.selectedPaths ? p.selectedPaths.slice() : [];
            if (shift && p.anchorIndex >= 0 && clickedIdx >= 0) {
                const lo = Math.min(p.anchorIndex, clickedIdx);
                const hi = Math.max(p.anchorIndex, clickedIdx);
                const range = [];
                for (let j = lo; j <= hi; j++)
                    range.push(String(list[j].path || ""));
                p.selectedPaths = range;
            } else if (ctrl) {
                const pos = cur.indexOf(path);
                if (pos === -1) cur.push(path);
                else cur.splice(pos, 1);
                p.selectedPaths = cur;
                if (clickedIdx >= 0) p.anchorIndex = clickedIdx;
            } else {
                p.selectedPaths = [path];
                if (clickedIdx >= 0) p.anchorIndex = clickedIdx;
            }
            if (clickedIdx >= 0) p.focusedIndex = clickedIdx;
        });
    }

    function selectAllActive(): void {
        const ti = root.activeTabIndex;
        const t = root.currentTab();
        if (!t) return;
        updatePane(ti, t.activePane, (p) => {
            const all = [];
            for (let i = 0; i < p.filteredEntries.length; i++)
                all.push(String(p.filteredEntries[i].path || ""));
            p.selectedPaths = all;
        });
    }

    function activeSelectionPaths(): var {
        const p = activePane();
        if (!p) return [];
        if (p.selectedPaths && p.selectedPaths.length > 0)
            return p.selectedPaths;
        if (p.focusedIndex >= 0 && p.focusedIndex < p.filteredEntries.length)
            return [String(p.filteredEntries[p.focusedIndex].path || "")];
        return [];
    }

    function focusedEntry(): var {
        const p = activePane();
        if (!p || p.focusedIndex < 0 || p.focusedIndex >= p.filteredEntries.length)
            return null;
        return p.filteredEntries[p.focusedIndex];
    }

    function activateEntry(entry: var, paneIdx: int): void {
        if (!entry) return;
        if (entry.isDir) {
            root.navigateTo(String(entry.path || ""), paneIdx);
        } else {
            backend.openPath(String(entry.path || ""), (ok, data, err) => {
                if (!ok && err) root.showToast(err, true);
                else root.showToast("Opening " + String(entry.name || ""), false);
            });
        }
    }

    // --- Actions & Prompts ---
    function copySelected(cutMode: bool): void {
        const paths = activeSelectionPaths();
        if (paths.length === 0) return;
        root.clipboardPaths = paths;
        root.clipboardOp = cutMode ? "cut" : "copy";
        if (!cutMode)
            backend.copyUri(paths, null);
        root.showToast((cutMode ? "Cut " : "Copied ") + paths.length + (paths.length === 1 ? " item" : " items"), false);
    }

    function pasteIntoActive(): void {
        const p = activePane();
        if (!p || p.isTrashView || root.clipboardPaths.length === 0) return;
        const isCut = root.clipboardOp === "cut";
        const fn = isCut ? backend.movePaths : backend.copyPaths;
        fn(root.clipboardPaths, p.path, (ok, data, err) => {
            if (ok) {
                if (isCut) {
                    root.clipboardPaths = [];
                    root.clipboardOp = "";
                }
                root.reloadBothActivePanes(false);
                root.showToast(isCut ? "Moved items" : "Pasted items", false);
            } else {
                root.showToast(err || "Paste failed", true);
            }
        });
    }

    function transferToOtherPane(isMove: bool): void {
        const t = root.currentTab();
        if (!t || !ShellState.fmDualPane) return;
        const dstPane = getPane(root.activeTabIndex, root.otherPaneIndex());
        const paths = activeSelectionPaths();
        if (!dstPane || dstPane.isTrashView || paths.length === 0) return;
        const fn = isMove ? backend.movePaths : backend.copyPaths;
        fn(paths, dstPane.path, (ok, data, err) => {
            if (ok) {
                root.reloadBothActivePanes(false);
                root.showToast((isMove ? "Moved " : "Copied ") + paths.length + " to other pane", false);
            } else {
                root.showToast(err || "Transfer failed", true);
            }
        });
    }

    function trashSelected(): void {
        const p = activePane();
        if (!p || p.isTrashView) return;
        const paths = activeSelectionPaths();
        if (paths.length === 0) return;
        backend.trashPaths(paths, (ok, data, err) => {
            if (ok) {
                root.reloadBothActivePanes(false);
                root.showToast("Moved " + paths.length + " to Trash", false);
            } else {
                root.showToast(err || "Trash failed", true);
            }
        });
    }

    function openPrompt(kind: string, title: string, initialText: string, target: var): void {
        root.contextOpen = false;
        root.promptKind = kind;
        root.promptTitle = title;
        root.promptText = initialText;
        root.promptTarget = target;
        root.promptOpen = true;
        promptFocusTimer.restart();
    }

    function submitPrompt(): void {
        const kind = root.promptKind;
        const txt = (root.promptText || "").trim();
        const pane = activePane();
        root.promptOpen = false;

        if (kind === "mkdir" && txt.length > 0 && pane) {
            backend.mkdir(pane.path, txt, (ok, data, err) => {
                if (ok) { root.reloadBothActivePanes(false); root.showToast("Created folder " + txt, false); }
                else root.showToast(err || "Failed to create folder", true);
            });
        } else if (kind === "touch" && txt.length > 0 && pane) {
            backend.touch(pane.path, txt, (ok, data, err) => {
                if (ok) { root.reloadBothActivePanes(false); root.showToast("Created file " + txt, false); }
                else root.showToast(err || "Failed to create file", true);
            });
        } else if (kind === "rename" && txt.length > 0 && root.promptTarget) {
            backend.renameItem(String(root.promptTarget.path || ""), txt, (ok, data, err) => {
                if (ok) { root.reloadBothActivePanes(false); root.showToast("Renamed to " + txt, false); }
                else root.showToast(err || "Rename failed", true);
            });
        } else if (kind === "compress" && txt.length > 0 && pane && root.promptTarget) {
            backend.compressPaths(root.promptTarget, pane.path, txt, "tar.gz", (ok, data, err) => {
                if (ok) { root.reloadBothActivePanes(false); root.showToast("Archive created", false); }
                else root.showToast(err || "Compress failed", true);
            });
        } else if (kind === "delete" && root.promptTarget) {
            backend.deletePaths(root.promptTarget, (ok, data, err) => {
                if (ok) { root.reloadBothActivePanes(false); root.showToast("Deleted permanently", false); }
                else root.showToast(err || "Delete failed", true);
            });
        } else if (kind === "empty_trash") {
            backend.trashEmpty((ok, data, err) => {
                if (ok) { root.reloadBothActivePanes(false); root.showToast("Trash emptied", false); }
                else root.showToast(err || "Failed to empty trash", true);
            });
        }
    }

    function toggleSort(field: string): void {
        if (ShellState.fmSortBy === field)
            ShellState.setPref("fmSortDesc", !ShellState.fmSortDesc);
        else {
            ShellState.setPrefsBatch({ fmSortBy: field, fmSortDesc: false });
        }
        reloadBothActivePanes(true);
    }

    // Re-load when sort/hidden prefs change dynamically from Customize drawer
    Connections {
        target: ShellState
        function onFmShowHiddenChanged(): void { if (backend.ready) root.reloadBothActivePanes(true); }
        function onFmDirsFirstChanged(): void { if (backend.ready) root.reloadBothActivePanes(true); }
        function onFmSortByChanged(): void { if (backend.ready) root.reloadBothActivePanes(true); }
        function onFmSortDescChanged(): void { if (backend.ready) root.reloadBothActivePanes(true); }
        function onFmDualPaneChanged(): void {
            if (ShellState.fmDualPane && backend.ready) {
                const ti = root.activeTabIndex;
                root.loadPane(ti, root.otherPaneIndex(), false);
            }
        }
        function onFmViewModeChanged(): void {
            if (ShellState.fmViewMode === "miller" && backend.ready) {
                const p = root.activePane();
                const t = root.currentTab();
                if (p && t) {
                    root.loadMillerParent(root.activeTabIndex, t.activePane, p.parent);
                    const foc = root.focusedEntry();
                    if (foc) root.loadMillerChild(root.activeTabIndex, t.activePane, foc);
                }
            }
        }
        function onFmPreviewVisibleChanged(): void {
            if (ShellState.fmPreviewVisible && backend.ready) {
                const foc = root.focusedEntry();
                if (foc) root.inspectEntry(foc);
            }
        }
    }

    // Lightweight 2.5s external filesystem change detector (runs ONLY while window is open)
    Timer {
        interval: 2500
        repeat: true
        running: root.isOpen && backend.ready
        onTriggered: {
            const p = root.activePane();
            const t = root.currentTab();
            if (!p || !t || p.isTrashView || (p.searchQuery || "").trim().length > 0)
                return;
            const ti = root.activeTabIndex;
            const pi = t.activePane;
            const expectedStamp = p.dirStamp;
            backend.dirStamp(p.path, (ok, data) => {
                if (ok && data && data.stamp && String(data.stamp) !== expectedStamp)
                    root.loadPane(ti, pi, true);
            });
        }
    }

    Timer { id: pathFocusTimer; interval: 20; repeat: false; onTriggered: { pathInput.forceActiveFocus(); pathInput.selectAll(); } }
    Timer { id: filterFocusTimer; interval: 20; repeat: false; onTriggered: { filterInput.forceActiveFocus(); filterInput.selectAll(); } }
    Timer { id: promptFocusTimer; interval: 20; repeat: false; onTriggered: { if (promptInput.visible) { promptInput.forceActiveFocus(); promptInput.selectAll(); } } }

    // Reload tabs if re-opened with an explicit initialPath from Island/IPC
    onInitialPathChanged: {
        if (root.initialPath && root.initialPath.length > 0 && backend.ready) {
            root.navigateTo(root.initialPath, -1);
        }
    }

    // --- Layer Shell Window Configuration ---
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
    WlrLayershell.namespace: "quickshell-files"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: root.isOpen

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (root.contextOpen) { root.contextOpen = false; event.accepted = true; return; }
                if (root.promptOpen) { root.promptOpen = false; event.accepted = true; return; }
                if (root.pathEditOpen) { root.pathEditOpen = false; event.accepted = true; return; }
                if (root.customizeOpen) { root.customizeOpen = false; event.accepted = true; return; }
                if (filterInput.activeFocus) { keyScope.forceActiveFocus(); event.accepted = true; return; }
                root.closeRequested();
                event.accepted = true;
                return;
            }

            if (root.promptOpen || root.pathEditOpen || filterInput.activeFocus)
                return;

            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            const alt = (event.modifiers & Qt.AltModifier) !== 0;

            if (ctrl && event.key === Qt.Key_L) {
                const p = root.activePane();
                pathInput.text = p ? p.path : "~";
                root.pathEditOpen = true;
                pathFocusTimer.restart();
                event.accepted = true;
            } else if (event.key === Qt.Key_Slash || (ctrl && event.key === Qt.Key_F)) {
                filterFocusTimer.restart();
                event.accepted = true;
            } else if (ctrl && event.key === Qt.Key_H) {
                ShellState.setPref("fmShowHidden", !ShellState.fmShowHidden);
                event.accepted = true;
            } else if (ctrl && event.key === Qt.Key_T) {
                const p = root.activePane();
                root.addTab(p && !p.isTrashView ? p.path : "~");
                event.accepted = true;
            } else if (ctrl && event.key === Qt.Key_W) {
                root.closeTab(root.activeTabIndex);
                event.accepted = true;
            } else if (ctrl && shift && event.key === Qt.Key_C) {
                const foc = root.focusedEntry();
                if (foc && foc.path) {
                    backend.copyText(String(foc.path), null);
                    root.showToast("Path copied", false);
                }
                event.accepted = true;
            } else if (ctrl && event.key === Qt.Key_C) {
                root.copySelected(false);
                event.accepted = true;
            } else if (ctrl && event.key === Qt.Key_X) {
                root.copySelected(true);
                event.accepted = true;
            } else if (ctrl && event.key === Qt.Key_V) {
                root.pasteIntoActive();
                event.accepted = true;
            } else if (ctrl && event.key === Qt.Key_A) {
                root.selectAllActive();
                event.accepted = true;
            } else if (ctrl && shift && event.key === Qt.Key_N) {
                root.openPrompt("mkdir", "New Folder Name", "New Folder", null);
                event.accepted = true;
            } else if (event.key === Qt.Key_F2) {
                const foc = root.focusedEntry();
                if (foc && !root.activePane().isTrashView)
                    root.openPrompt("rename", "Rename Item", String(foc.name || ""), foc);
                event.accepted = true;
            } else if (event.key === Qt.Key_F3) {
                ShellState.setPref("fmDualPane", !ShellState.fmDualPane);
                event.accepted = true;
            } else if (event.key === Qt.Key_F5) {
                if (ShellState.fmDualPane) root.transferToOtherPane(false);
                else root.reloadBothActivePanes(true);
                event.accepted = true;
            } else if (event.key === Qt.Key_Space) {
                ShellState.setPref("fmPreviewVisible", !ShellState.fmPreviewVisible);
                event.accepted = true;
            } else if (event.key === Qt.Key_Delete) {
                const paths = root.activeSelectionPaths();
                if (paths.length === 0) return;
                if (shift || root.activePane().isTrashView)
                    root.openPrompt("delete", "Delete " + paths.length + " item(s) permanently?", "", paths);
                else
                    root.trashSelected();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backspace || (alt && event.key === Qt.Key_Left)) {
                if (alt && event.key === Qt.Key_Left) root.goBack();
                else root.goUp();
                event.accepted = true;
            } else if (alt && event.key === Qt.Key_Right) {
                root.goForward();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                const ti = root.activeTabIndex;
                const t = root.currentTab();
                const p = root.activePane();
                if (!t || !p || p.filteredEntries.length === 0) return;
                const delta = event.key === Qt.Key_Down ? 1 : -1;
                const nextIdx = Math.max(0, Math.min(p.filteredEntries.length - 1, (p.focusedIndex < 0 ? 0 : p.focusedIndex + delta)));
                const targetEntry = p.filteredEntries[nextIdx];
                root.handleSelection(ti, t.activePane, String(targetEntry.path || ""), false, shift);
                const paneRef = t.activePane === 0 ? primaryPaneView : secondaryPaneView;
                paneRef.ensureVisibleIndex(nextIdx);
                root.inspectEntry(targetEntry);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                const foc = root.focusedEntry();
                if (foc && !root.activePane().isTrashView)
                    root.activateEntry(foc, root.currentTab().activePane);
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab && ShellState.fmDualPane) {
                const ti = root.activeTabIndex;
                const nextTabs = root.tabs.slice();
                const t = Object.assign({}, nextTabs[ti]);
                t.activePane = t.activePane === 0 ? 1 : 0;
                nextTabs[ti] = t;
                root.tabs = nextTabs;
                event.accepted = true;
            }
        }

        // Scrim Backdrop
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

        // Centered Dynamic File Manager Dialog
        Rectangle {
            id: dialog
            anchors.centerIn: parent

            readonly property int targetW: {
                if (ShellState.fmWindowSize === "compact") return 960;
                if (ShellState.fmWindowSize === "wide") return 1340;
                if (ShellState.fmWindowSize === "max") return Math.round(parent.width * 0.94);
                return 1140;
            }
            readonly property int targetH: {
                if (ShellState.fmWindowSize === "compact") return 600;
                if (ShellState.fmWindowSize === "wide") return 780;
                if (ShellState.fmWindowSize === "max") return Math.round(parent.height * 0.90);
                return 700;
            }

            width: Math.min(parent.width - 36, targetW)
            height: Math.min(parent.height - 44, targetH)
            radius: Theme.r(20)
            color: fstyle.windowBg
            border.width: Theme.isSimple ? 2 : Math.max(1, Theme.islandBorderWidth)
            border.color: fstyle.borderCol
            clip: true

            opacity: root.shown ? 1.0 : 0.0
            scale: (Theme.reducedMotion || root.shown) ? 1.0 : 0.97

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            // Glass Specular Sheen
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 44
                radius: parent.radius
                visible: !Theme.isSimple && (Theme.showGlassSheen || ShellState.fmSurfacePreset === "glass")
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.30) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Consume clicks inside dialog so scrim doesn't close
            MouseArea {
                anchors.fill: parent
                onClicked: root.contextOpen = false
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // ==================== 1. TOP WINDOW & TABS HEADER ====================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: ShellState.fmHeaderStyle === "pill" ? Theme.r(12) : Theme.r(8)
                    color: fstyle.headerBg
                    border.width: ShellState.fmHeaderStyle === "minimal" ? 0 : Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        // App Title Badge
                        RowLayout {
                            spacing: 6
                            Rectangle {
                                implicitWidth: 24
                                implicitHeight: 24
                                radius: Theme.r(7)
                                color: Theme.withAlpha(fstyle.accent, 0.20)
                                Text { anchors.centerIn: parent; text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: fstyle.accent }
                            }
                            Text {
                                text: "Files"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12)
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }
                        }

                        // Tabs Strip
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: root.tabs
                                delegate: Rectangle {
                                    id: tabChip
                                    required property var modelData
                                    required property int index
                                    readonly property bool cur: root.activeTabIndex === tabChip.index

                                    implicitHeight: 26
                                    implicitWidth: Math.min(170, tabInner.implicitWidth + 14)
                                    radius: Theme.r(8)
                                    color: tabChip.cur
                                        ? Theme.tileActiveBg
                                        : (tcMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                                    border.width: tabChip.cur ? Theme.activeControlBorderWidth : 0
                                    border.color: tabChip.cur ? fstyle.accent : Theme.cardBorder

                                    RowLayout {
                                        id: tabInner
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        Text {
                                            Layout.fillWidth: true
                                            text: String(tabChip.modelData.title || "Folder")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(10)
                                            font.weight: tabChip.cur ? Font.Bold : Font.Normal
                                            color: tabChip.cur ? fstyle.accent : Theme.fgSurface
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            visible: root.tabs.length > 1
                                            implicitWidth: 14
                                            implicitHeight: 14
                                            radius: Theme.r(4)
                                            color: xTabMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.25) : "transparent"
                                            z: 2
                                            Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                                            MouseArea {
                                                id: xTabMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.closeTab(tabChip.index)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: tcMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.activeTabIndex = tabChip.index;
                                            root.loadActiveTab(false);
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: 24
                                implicitHeight: 24
                                radius: Theme.r(7)
                                color: newTabMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                                Text { anchors.centerIn: parent; text: "󰐕"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurfaceVariant }
                                MouseArea {
                                    id: newTabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const p = root.activePane();
                                        root.addTab(p && !p.isTrashView ? p.path : "~");
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Quick View Mode Switcher (List | Grid | Miller)
                        RowLayout {
                            spacing: 2
                            Repeater {
                                model: [
                                    { id: "list",   icon: "󰕮" },
                                    { id: "grid",   icon: "󰀻" },
                                    { id: "miller", icon: "󰝰" }
                                ]
                                delegate: Rectangle {
                                    id: qvmBtn
                                    required property var modelData
                                    readonly property bool sel: ShellState.fmViewMode === qvmBtn.modelData.id
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    radius: Theme.r(7)
                                    color: qvmBtn.sel ? fstyle.accent : (qvmMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                                    border.width: qvmBtn.sel ? Theme.activeControlBorderWidth : 0
                                    border.color: fstyle.accent
                                    Text { anchors.centerIn: parent; text: qvmBtn.modelData.icon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: qvmBtn.sel ? fstyle.onAccent : Theme.fgSurfaceVariant }
                                    MouseArea { id: qvmMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmViewMode", qvmBtn.modelData.id) }
                                }
                            }
                        }

                        // Dual-Pane Toggle
                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Theme.r(7)
                            color: ShellState.fmDualPane ? fstyle.accent : (dpMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: ShellState.fmDualPane ? Theme.activeControlBorderWidth : 0
                            border.color: fstyle.accent
                            Text { anchors.centerIn: parent; text: "󰤼"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: ShellState.fmDualPane ? fstyle.onAccent : Theme.fgSurfaceVariant }
                            MouseArea { id: dpMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmDualPane", !ShellState.fmDualPane) }
                        }

                        // Preview Toggle
                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Theme.r(7)
                            color: ShellState.fmPreviewVisible ? fstyle.accent : (pvMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: ShellState.fmPreviewVisible ? Theme.activeControlBorderWidth : 0
                            border.color: fstyle.accent
                            Text { anchors.centerIn: parent; text: "󰈙"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: ShellState.fmPreviewVisible ? fstyle.onAccent : Theme.fgSurfaceVariant }
                            MouseArea { id: pvMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmPreviewVisible", !ShellState.fmPreviewVisible) }
                        }

                        // Customize Button
                        Rectangle {
                            implicitHeight: 26
                            implicitWidth: custLbl.implicitWidth + 14
                            radius: Theme.r(7)
                            color: root.customizeOpen ? fstyle.accent : (custMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: Theme.activeControlBorderWidth
                            border.color: root.customizeOpen ? fstyle.accent : Theme.cardBorder

                            Text {
                                id: custLbl
                                anchors.centerIn: parent
                                text: "󰏘 Customize"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Bold
                                color: root.customizeOpen ? fstyle.onAccent : fstyle.accent
                            }
                            MouseArea {
                                id: custMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.customizeOpen = !root.customizeOpen
                            }
                        }

                        // Settings Shortcut
                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Theme.r(7)
                            color: stgMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                            Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurfaceVariant }
                            MouseArea {
                                id: stgMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.closeRequested();
                                    root.openSettingsRequested("appearance");
                                }
                            }
                        }

                        // Close Button
                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Theme.r(7)
                            color: clsWinMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.subCardBg
                            Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: clsWinMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant }
                            MouseArea { id: clsWinMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
                        }
                    }
                }

                // ==================== 2. NAVIGATION, BREADCRUMBS & SEARCH BAR ====================
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    readonly property var ap: root.activePane()

                    // Back / Forward / Up / Refresh
                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(8)
                        color: bkMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                        border.width: Theme.subBorderWidth; border.color: Theme.cardBorder
                        opacity: (parent.ap && parent.ap.histIndex > 0) ? 1.0 : 0.45
                        Text { anchors.centerIn: parent; text: "󰁍"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurface }
                        MouseArea { id: bkMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.goBack() }
                    }

                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(8)
                        color: fwMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                        border.width: Theme.subBorderWidth; border.color: Theme.cardBorder
                        opacity: (parent.ap && parent.ap.histIndex + 1 < parent.ap.history.length) ? 1.0 : 0.45
                        Text { anchors.centerIn: parent; text: "󰁔"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurface }
                        MouseArea { id: fwMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.goForward() }
                    }

                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(8)
                        color: upBtnMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                        border.width: Theme.subBorderWidth; border.color: Theme.cardBorder
                        opacity: (parent.ap && !parent.ap.isTrashView && parent.ap.parent.length > 0) ? 1.0 : 0.45
                        Text { anchors.centerIn: parent; text: "󰁝"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurface }
                        MouseArea { id: upBtnMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.goUp() }
                    }

                    // Breadcrumbs OR Editable Path Bar
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: Theme.cardBg
                        border.width: root.pathEditOpen ? 1.5 : Theme.subBorderWidth
                        border.color: root.pathEditOpen ? fstyle.accent : Theme.cardBorder
                        clip: true

                        // Breadcrumb strip
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            visible: !root.pathEditOpen
                            spacing: 2

                            ScrollView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                                RowLayout {
                                    spacing: 2

                                    Text {
                                        visible: root.activePane() && root.activePane().isTrashView
                                        text: "󰩹 Trash"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(11)
                                        font.weight: Font.Bold
                                        color: Theme.error
                                    }

                                    Repeater {
                                        model: (root.activePane() && !root.activePane().isTrashView) ? root.displayBreadcrumbs(root.activePane().breadcrumbs) : []
                                        delegate: RowLayout {
                                            id: crumbWrap
                                            required property var modelData
                                            required property int index
                                            spacing: 2

                                            Text {
                                                visible: crumbWrap.index > 0
                                                text: "󰅂"
                                                font.family: Theme.iconFont
                                                font.pixelSize: Theme.fs(10)
                                                color: Theme.fgSurfaceVariant
                                            }

                                            Rectangle {
                                                implicitHeight: 20
                                                implicitWidth: cbRow.implicitWidth + 10
                                                radius: Theme.r(5)
                                                color: cbMouse.containsMouse ? Theme.hoverBg : "transparent"

                                                RowLayout {
                                                    id: cbRow
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    Text {
                                                        visible: !!crumbWrap.modelData.isHome
                                                        text: "󰋜"
                                                        font.family: Theme.iconFont
                                                        font.pixelSize: Theme.fs(11)
                                                        color: Theme.fgSurfaceVariant
                                                    }

                                                    Text {
                                                        id: cbLbl
                                                        text: String(crumbWrap.modelData.label || "/")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: Theme.fs(10)
                                                        font.weight: Font.Medium
                                                        color: Theme.fgSurface
                                                    }
                                                }
                                                MouseArea {
                                                    id: cbMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.navigateTo(String(crumbWrap.modelData.path || "/"), -1)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: 22; implicitHeight: 22; radius: Theme.r(5)
                                color: edPathMouse.containsMouse ? Theme.hoverBg : "transparent"
                                Text { anchors.centerIn: parent; text: "󰑕"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
                                MouseArea {
                                    id: edPathMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const p = root.activePane();
                                        pathInput.text = p ? p.path : "~";
                                        root.pathEditOpen = true;
                                        pathFocusTimer.restart();
                                    }
                                }
                            }
                        }

                        // Editable Path Field
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            visible: root.pathEditOpen
                            spacing: 6

                            TextField {
                                id: pathInput
                                Layout.fillWidth: true
                                color: Theme.fgSurface
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(11)
                                placeholderText: "Enter path (e.g. ~/Pictures or /etc)..."
                                placeholderTextColor: Theme.fgSurfaceVariant
                                background: null
                                padding: 0
                                onAccepted: root.navigateTo(text.trim(), -1)
                            }

                            Rectangle {
                                implicitHeight: 20; implicitWidth: 34; radius: Theme.r(5)
                                color: Theme.withAlpha(fstyle.accent, 0.22)
                                Text { anchors.centerIn: parent; text: "Go"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: fstyle.accent }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.navigateTo(pathInput.text.trim(), -1) }
                            }
                        }
                    }

                    // Filter / Recursive Search Input
                    Rectangle {
                        Layout.preferredWidth: 230
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: Theme.cardBg
                        border.width: filterInput.activeFocus ? 1.5 : Theme.subBorderWidth
                        border.color: filterInput.activeFocus ? fstyle.accent : Theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 4
                            spacing: 5

                            Text { text: "󰍉"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }

                            TextField {
                                id: filterInput
                                Layout.fillWidth: true
                                text: root.activePane() ? String(root.activePane().searchQuery || "") : ""
                                placeholderText: (root.activePane() && root.activePane().recursiveSearch) ? "Recursive search..." : "Filter (/)"
                                placeholderTextColor: Theme.fgSurfaceVariant
                                color: Theme.fgSurface
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                background: null
                                padding: 0
                                onTextChanged: {
                                    const t = root.currentTab();
                                    if (!t) return;
                                    const ap = root.activePane();
                                    if (ap && String(ap.searchQuery || "") === text)
                                        return;
                                    root.updatePane(root.activeTabIndex, t.activePane, (p) => {
                                        p.searchQuery = text;
                                    });
                                    if (ap && ap.recursiveSearch)
                                        searchDebounceTimer.restart();
                                }
                            }

                            // Deep Recursive Search Toggle
                            Rectangle {
                                implicitHeight: 20
                                implicitWidth: recLbl.implicitWidth + 8
                                radius: Theme.r(5)
                                readonly property bool recOn: root.activePane() ? !!root.activePane().recursiveSearch : false
                                color: recOn ? fstyle.accent : Theme.subCardBg
                                border.width: recOn ? Theme.activeControlBorderWidth : 0
                                border.color: fstyle.accent

                                Text {
                                    id: recLbl
                                    anchors.centerIn: parent
                                    text: "Deep"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(8)
                                    font.weight: Font.Bold
                                    color: parent.recOn ? fstyle.onAccent : Theme.fgSurfaceVariant
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const t = root.currentTab();
                                        if (!t) return;
                                        root.updatePane(root.activeTabIndex, t.activePane, (p) => {
                                            p.recursiveSearch = !p.recursiveSearch;
                                        });
                                        root.runRecursiveSearch();
                                    }
                                }
                            }
                        }
                    }

                    // Action Icons: New Folder | New File | Sort | Hidden | Terminal
                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(8)
                        color: mkdMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                        border.width: Theme.subBorderWidth; border.color: Theme.cardBorder
                        Text { anchors.centerIn: parent; text: "󰉖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.fgSurface }
                        MouseArea { id: mkdMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPrompt("mkdir", "New Folder Name", "New Folder", null) }
                    }

                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(8)
                        color: mkfMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                        border.width: Theme.subBorderWidth; border.color: Theme.cardBorder
                        Text { anchors.centerIn: parent; text: "󰈤"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.fgSurface }
                        MouseArea { id: mkfMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPrompt("touch", "New File Name", "notes.txt", null) }
                    }

                    // Sort Button
                    Rectangle {
                        implicitHeight: 28; implicitWidth: sortLbl.implicitWidth + 14; radius: Theme.r(8)
                        color: srtMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                        border.width: Theme.subBorderWidth; border.color: Theme.cardBorder

                        Text {
                            id: sortLbl
                            anchors.centerIn: parent
                            text: {
                                const map = { name: "Name", size: "Size", mtime: "Date", ext: "Type" };
                                const arr = ShellState.fmSortDesc ? " ↓" : " ↑";
                                return (map[ShellState.fmSortBy] || "Name") + arr;
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Medium
                            color: Theme.fgSurface
                        }
                        MouseArea {
                            id: srtMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    ShellState.setPref("fmSortDesc", !ShellState.fmSortDesc);
                                } else {
                                    const order = ["name", "mtime", "size", "ext"];
                                    const next = order[(order.indexOf(ShellState.fmSortBy) + 1) % order.length];
                                    ShellState.setPref("fmSortBy", next);
                                }
                            }
                        }
                    }

                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(8)
                        color: ShellState.fmShowHidden ? fstyle.accent : (hidMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg)
                        border.width: ShellState.fmShowHidden ? Theme.activeControlBorderWidth : 0; border.color: fstyle.accent
                        Text { anchors.centerIn: parent; text: ShellState.fmShowHidden ? "󰈈" : "󰈉"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: ShellState.fmShowHidden ? fstyle.onAccent : Theme.fgSurfaceVariant }
                        MouseArea { id: hidMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmShowHidden", !ShellState.fmShowHidden) }
                    }

                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(8)
                        color: trmMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                        border.width: Theme.subBorderWidth; border.color: Theme.cardBorder
                        Text { anchors.centerIn: parent; text: "󰆍"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.fgSurface }
                        MouseArea {
                            id: trmMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const p = root.activePane();
                                backend.openTerminal(p && !p.isTrashView ? p.path : "~", (ok, d, e) => {
                                    if (!ok && e) root.showToast(e, true);
                                    else root.showToast("Terminal opened", false);
                                });
                            }
                        }
                    }
                }

                // ==================== 3. MAIN WORKSPACE (SIDEBAR + PANES + INSPECTOR) ====================
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    // LEFT SIDEBAR
                    Rectangle {
                        id: sbCard
                        Layout.preferredWidth: fstyle.sidebarWidth
                        Layout.fillHeight: true
                        visible: ShellState.fmSidebarVisible
                        radius: Theme.r(12)
                        color: fstyle.sidebarBg
                        border.width: Theme.cardBorderWidth
                        border.color: Theme.cardBorder
                        clip: true

                        readonly property bool iconsOnly: ShellState.fmSidebarStyle === "icons"

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 7
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            ColumnLayout {
                                width: Math.max(32, fstyle.sidebarWidth - 16)
                                spacing: 4

                                Text {
                                    visible: !sbCard.iconsOnly
                                    text: "Places"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Font.Bold
                                    color: Theme.fgSurfaceVariant
                                }

                                Repeater {
                                    model: root.placesData.places || []
                                    delegate: Rectangle {
                                        id: sbPlace
                                        required property var modelData
                                        readonly property var ap: root.activePane()
                                        readonly property bool cur: ap && !ap.isTrashView && ap.path === String(sbPlace.modelData.path || "")
                                        readonly property bool iconMode: ShellState.fmSidebarStyle === "icons"

                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        radius: Theme.r(8)
                                        color: cur ? Theme.withAlpha(fstyle.accent, 0.22) : (spMouse.containsMouse ? Theme.hoverBg : "transparent")

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: sbPlace.iconMode ? 0 : 8
                                            anchors.rightMargin: sbPlace.iconMode ? 0 : 8
                                            spacing: 8

                                            Text {
                                                Layout.alignment: sbPlace.iconMode ? Qt.AlignHCenter : Qt.AlignVCenter
                                                Layout.fillWidth: sbPlace.iconMode
                                                horizontalAlignment: sbPlace.iconMode ? Text.AlignHCenter : Text.AlignLeft
                                                text: String(sbPlace.modelData.icon || "󰉋")
                                                font.family: Theme.iconFont
                                                font.pixelSize: Theme.fs(13)
                                                color: sbPlace.cur ? fstyle.accent : Theme.fgSurfaceVariant
                                            }
                                            Text {
                                                visible: !sbPlace.iconMode
                                                Layout.fillWidth: true
                                                text: String(sbPlace.modelData.name || "")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(11)
                                                font.weight: sbPlace.cur ? Font.Bold : Font.Normal
                                                color: sbPlace.cur ? fstyle.accent : Theme.fgSurface
                                                elide: Text.ElideRight
                                            }
                                        }
                                        MouseArea {
                                            id: spMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.navigateTo(String(sbPlace.modelData.path || "~"), -1)
                                        }
                                    }
                                }

                                // Trash row
                                Rectangle {
                                    id: sbTrashItem
                                    readonly property var ap: root.activePane()
                                    readonly property bool cur: ap && ap.isTrashView
                                    readonly property bool iconMode: ShellState.fmSidebarStyle === "icons"

                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    radius: Theme.r(8)
                                    color: cur ? Theme.withAlpha(Theme.error, 0.20) : (stMouse.containsMouse ? Theme.hoverBg : "transparent")

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: sbTrashItem.iconMode ? 0 : 8
                                        anchors.rightMargin: sbTrashItem.iconMode ? 0 : 8
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: sbTrashItem.iconMode
                                            horizontalAlignment: sbTrashItem.iconMode ? Text.AlignHCenter : Text.AlignLeft
                                            text: "󰩹"
                                            font.family: Theme.iconFont
                                            font.pixelSize: Theme.fs(13)
                                            color: sbTrashItem.cur ? Theme.error : Theme.fgSurfaceVariant
                                        }
                                        Text {
                                            visible: !sbTrashItem.iconMode
                                            Layout.fillWidth: true
                                            text: "Trash"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(11)
                                            color: sbTrashItem.cur ? Theme.error : Theme.fgSurface
                                        }
                                        Text {
                                            visible: !sbTrashItem.iconMode && Number(root.placesData.trashCount || 0) > 0
                                            text: String(root.placesData.trashCount || 0)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(9)
                                            font.weight: Font.Bold
                                            color: Theme.fgSurfaceVariant
                                        }
                                    }
                                    MouseArea {
                                        id: stMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openTrashInActivePane()
                                    }
                                }

                                // Bookmarks Section
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 6
                                    visible: ShellState.fmSidebarStyle !== "icons"

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Bookmarks"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(10)
                                        font.weight: Font.Bold
                                        color: Theme.fgSurfaceVariant
                                    }
                                    Rectangle {
                                        implicitWidth: 18; implicitHeight: 18; radius: Theme.r(5)
                                        color: pinBmMouse.containsMouse ? Theme.hoverBg : "transparent"
                                        Text { anchors.centerIn: parent; text: "󰐕"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: fstyle.accent }
                                        MouseArea {
                                            id: pinBmMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const p = root.activePane();
                                                if (!p || p.isTrashView) return;
                                                backend.bookmarkAdd(p.path, "", (ok, data) => {
                                                    if (ok && data) { root.placesData = data; root.showToast("Pinned bookmark", false); }
                                                });
                                            }
                                        }
                                    }
                                }

                                Repeater {
                                    model: root.placesData.bookmarks || []
                                    delegate: Rectangle {
                                        id: sbBm
                                        required property var modelData
                                        readonly property bool iconMode: ShellState.fmSidebarStyle === "icons"
                                        readonly property var ap: root.activePane()
                                        readonly property bool cur: ap && !ap.isTrashView && ap.path === String(sbBm.modelData.path || "")

                                        Layout.fillWidth: true
                                        implicitHeight: 26
                                        radius: Theme.r(7)
                                        color: cur ? Theme.withAlpha(fstyle.accent, 0.22) : (bmRowMouse.containsMouse ? Theme.hoverBg : "transparent")

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: sbBm.iconMode ? 0 : 8
                                            anchors.rightMargin: sbBm.iconMode ? 0 : 6
                                            spacing: 6
                                            Text {
                                                Layout.fillWidth: sbBm.iconMode
                                                horizontalAlignment: sbBm.iconMode ? Text.AlignHCenter : Text.AlignLeft
                                                text: "󰃀"
                                                font.family: Theme.iconFont
                                                font.pixelSize: Theme.fs(12)
                                                color: sbBm.cur ? fstyle.accent : Theme.secondary
                                            }
                                            Text {
                                                visible: !sbBm.iconMode
                                                Layout.fillWidth: true
                                                text: String(sbBm.modelData.name || "")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(10)
                                                color: sbBm.cur ? fstyle.accent : Theme.fgSurface
                                                elide: Text.ElideRight
                                            }
                                            Rectangle {
                                                visible: !sbBm.iconMode && bmRowMouse.containsMouse
                                                implicitWidth: 16; implicitHeight: 16; radius: Theme.r(4)
                                                color: rmBmMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.24) : "transparent"
                                                z: 2
                                                Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.error }
                                                MouseArea {
                                                    id: rmBmMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        backend.bookmarkRemove(String(sbBm.modelData.path || ""), (ok, data) => {
                                                            if (ok && data) root.placesData = data;
                                                        });
                                                    }
                                                }
                                            }
                                        }
                                        MouseArea {
                                            id: bmRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.navigateTo(String(sbBm.modelData.path || "~"), -1)
                                        }
                                    }
                                }

                                // Mounted Drives Section
                                Text {
                                    visible: ShellState.fmSidebarStyle !== "icons" && (root.placesData.drives || []).length > 0
                                    Layout.topMargin: 6
                                    text: "Drives"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Font.Bold
                                    color: Theme.fgSurfaceVariant
                                }

                                Repeater {
                                    model: root.placesData.drives || []
                                    delegate: Rectangle {
                                        id: sbDrive
                                        required property var modelData
                                        readonly property bool iconMode: ShellState.fmSidebarStyle === "icons"
                                        readonly property var ap: root.activePane()
                                        readonly property bool cur: ap && !ap.isTrashView && ap.path === String(sbDrive.modelData.mountPoint || "")

                                        Layout.fillWidth: true
                                        implicitHeight: sbDrive.iconMode ? 28 : 40
                                        radius: Theme.r(8)
                                        color: cur ? Theme.withAlpha(fstyle.accent, 0.20) : (drMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 3

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 5
                                                Text {
                                                    Layout.fillWidth: sbDrive.iconMode
                                                    horizontalAlignment: sbDrive.iconMode ? Text.AlignHCenter : Text.AlignLeft
                                                    text: sbDrive.modelData.removable ? "󰕓" : "󰋊"
                                                    font.family: Theme.iconFont
                                                    font.pixelSize: Theme.fs(12)
                                                    color: fstyle.accent
                                                }
                                                Text {
                                                    visible: !sbDrive.iconMode
                                                    Layout.fillWidth: true
                                                    text: String(sbDrive.modelData.label || "")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(10)
                                                    font.weight: Font.DemiBold
                                                    color: Theme.fgSurface
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    visible: !sbDrive.iconMode
                                                    text: String(sbDrive.modelData.availHuman || "")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(8)
                                                    color: Theme.fgSurfaceVariant
                                                }
                                            }

                                            Rectangle {
                                                visible: !sbDrive.iconMode
                                                Layout.fillWidth: true
                                                implicitHeight: 3
                                                radius: 1
                                                color: Theme.outlineVariant
                                                Rectangle {
                                                    height: parent.height
                                                    width: Math.round(parent.width * Math.min(1, Number(sbDrive.modelData.usedPct || 0) / 100))
                                                    radius: 1
                                                    color: Number(sbDrive.modelData.usedPct || 0) > 85 ? Theme.error : fstyle.accent
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: drMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.navigateTo(String(sbDrive.modelData.mountPoint || "/"), -1)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // CENTER PANE(S) + OPTIONAL DUAL PANE TRANSFER STRIP
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            readonly property var curTab: root.currentTab()
                            readonly property var p0: curTab ? curTab.panes[0] : root.createPaneState("~")
                            readonly property var p1: curTab ? curTab.panes[1] : root.createPaneState("~")

                            FilePaneView {
                                id: primaryPaneView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                fileStyle: fstyle
                                isActivePane: !ShellState.fmDualPane || (parent.curTab && parent.curTab.activePane === 0)
                                isTrashView: !!parent.p0.isTrashView
                                isSearchView: (parent.p0.searchQuery || "").trim().length > 0 && !!parent.p0.recursiveSearch
                                viewMode: ShellState.fmViewMode
                                entries: parent.p0.filteredEntries || []
                                parentEntries: parent.p0.parentEntries || []
                                millerChildEntries: parent.p0.millerChildEntries || []
                                millerChildTitle: String(parent.p0.millerChildTitle || "")
                                currentDir: String(parent.p0.path || "~")
                                parentDir: String(parent.p0.parent || "")
                                focusedIndex: Number(parent.p0.focusedIndex)
                                selectedPaths: parent.p0.selectedPaths || []
                                loading: !!parent.p0.loading || !!parent.p0.searching
                                emptyMessage: parent.p0.isTrashView ? "Trash is empty" : "Folder is empty"

                                onPaneClicked: {
                                    const nextTabs = root.tabs.slice();
                                    const t = Object.assign({}, nextTabs[root.activeTabIndex]);
                                    t.activePane = 0;
                                    nextTabs[root.activeTabIndex] = t;
                                    root.tabs = nextTabs;
                                }
                                onEntryFocused: (entry, idx) => root.inspectEntry(entry)
                                onEntryActivated: entry => root.activateEntry(entry, 0)
                                onSelectionToggled: (path, ctrl, shift) => root.handleSelection(root.activeTabIndex, 0, path, ctrl, shift)
                                onNavigatePathRequested: p => root.navigateTo(p, 0)
                                onTrashRestoreRequested: tn => {
                                    backend.trashRestore(tn, (ok, d, err) => {
                                        if (ok) { root.reloadBothActivePanes(false); root.showToast("Restored item", false); }
                                        else root.showToast(err || "Restore failed", true);
                                    });
                                }
                                onTrashEmptyRequested: root.openPrompt("empty_trash", "Empty Trash permanently?", "", null)
                                onContextMenuRequested: (entry, gx, gy) => {
                                    root.contextEntry = entry;
                                    root.contextX = Math.max(16, Math.min(keyScope.width - 210, gx));
                                    root.contextY = Math.max(16, Math.min(keyScope.height - 320, gy));
                                    root.contextOpen = true;
                                }
                                onEmptyContextMenuRequested: (gx, gy) => {
                                    root.contextEntry = null;
                                    root.contextX = Math.max(16, Math.min(keyScope.width - 210, gx));
                                    root.contextY = Math.max(16, Math.min(keyScope.height - 200, gy));
                                    root.contextOpen = true;
                                }
                            }

                            FilePaneView {
                                id: secondaryPaneView
                                visible: ShellState.fmDualPane
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                fileStyle: fstyle
                                isActivePane: parent.curTab && parent.curTab.activePane === 1
                                isTrashView: !!parent.p1.isTrashView
                                isSearchView: (parent.p1.searchQuery || "").trim().length > 0 && !!parent.p1.recursiveSearch
                                viewMode: ShellState.fmViewMode
                                entries: parent.p1.filteredEntries || []
                                parentEntries: parent.p1.parentEntries || []
                                millerChildEntries: parent.p1.millerChildEntries || []
                                millerChildTitle: String(parent.p1.millerChildTitle || "")
                                currentDir: String(parent.p1.path || "~")
                                parentDir: String(parent.p1.parent || "")
                                focusedIndex: Number(parent.p1.focusedIndex)
                                selectedPaths: parent.p1.selectedPaths || []
                                loading: !!parent.p1.loading || !!parent.p1.searching
                                emptyMessage: parent.p1.isTrashView ? "Trash is empty" : "Folder is empty"

                                onPaneClicked: {
                                    const nextTabs = root.tabs.slice();
                                    const t = Object.assign({}, nextTabs[root.activeTabIndex]);
                                    t.activePane = 1;
                                    nextTabs[root.activeTabIndex] = t;
                                    root.tabs = nextTabs;
                                }
                                onEntryFocused: (entry, idx) => root.inspectEntry(entry)
                                onEntryActivated: entry => root.activateEntry(entry, 1)
                                onSelectionToggled: (path, ctrl, shift) => root.handleSelection(root.activeTabIndex, 1, path, ctrl, shift)
                                onNavigatePathRequested: p => root.navigateTo(p, 1)
                                onContextMenuRequested: (entry, gx, gy) => {
                                    root.contextEntry = entry;
                                    root.contextX = Math.max(16, Math.min(keyScope.width - 210, gx));
                                    root.contextY = Math.max(16, Math.min(keyScope.height - 320, gy));
                                    root.contextOpen = true;
                                }
                                onEmptyContextMenuRequested: (gx, gy) => {
                                    root.contextEntry = null;
                                    root.contextX = Math.max(16, Math.min(keyScope.width - 210, gx));
                                    root.contextY = Math.max(16, Math.min(keyScope.height - 200, gy));
                                    root.contextOpen = true;
                                }
                            }
                        }

                        // Dual-Pane Quick Transfer Bar
                        Rectangle {
                            Layout.fillWidth: true
                            visible: ShellState.fmDualPane
                            implicitHeight: 30
                            radius: Theme.r(8)
                            color: Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const dst = root.getPane(root.activeTabIndex, root.otherPaneIndex());
                                        return "Other pane: " + (dst ? String(dst.displayPath || dst.path) : "~");
                                    }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    color: Theme.fgSurfaceVariant
                                    elide: Text.ElideMiddle
                                }

                                Rectangle {
                                    implicitHeight: 22; implicitWidth: cpOtherLbl.implicitWidth + 12; radius: Theme.r(6)
                                    color: cpOtherMouse.containsMouse ? fstyle.accent : Theme.withAlpha(fstyle.accent, 0.20)
                                    Text { id: cpOtherLbl; anchors.centerIn: parent; text: "F5 Copy to Other Pane"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: cpOtherMouse.containsMouse ? fstyle.onAccent : fstyle.accent }
                                    MouseArea { id: cpOtherMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.transferToOtherPane(false) }
                                }

                                Rectangle {
                                    implicitHeight: 22; implicitWidth: mvOtherLbl.implicitWidth + 12; radius: Theme.r(6)
                                    color: mvOtherMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                                    border.width: Theme.activeControlBorderWidth; border.color: Theme.cardBorder
                                    Text { id: mvOtherLbl; anchors.centerIn: parent; text: "Move to Other Pane"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.fgSurface }
                                    MouseArea { id: mvOtherMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.transferToOtherPane(true) }
                                }
                            }
                        }
                    }

                    // RIGHT INSPECTOR / PREVIEW PANE
                    FilePreviewPane {
                        id: previewPane
                        Layout.preferredWidth: 262
                        Layout.fillHeight: true
                        visible: ShellState.fmPreviewVisible && !root.customizeOpen
                        fileStyle: fstyle
                        previewData: root.previewData
                        loading: root.previewLoading
                        isBookmarked: root.previewData ? root.isPathBookmarked(String(root.previewData.path || "")) : false

                        onOpenRequested: p => backend.openPath(p, null)
                        onEditRequested: p => backend.openWith(p, ShellState.defaultEditor, null)
                        onTerminalRequested: p => backend.openTerminal(p, null)
                        onBookmarkToggleRequested: p => {
                            if (root.isPathBookmarked(p))
                                backend.bookmarkRemove(p, (ok, data) => { if (ok && data) { root.placesData = data; root.showToast("Removed bookmark", false); } });
                            else
                                backend.bookmarkAdd(p, "", (ok, data) => { if (ok && data) { root.placesData = data; root.showToast("Pinned bookmark", false); } });
                        }
                        onExtractRequested: p => {
                            const pane = root.activePane();
                            backend.extractArchive(p, pane ? pane.path : "", (ok, d, e) => {
                                if (ok) { root.reloadBothActivePanes(false); root.showToast("Archive extracted", false); }
                                else root.showToast(e || "Extraction failed", true);
                            });
                        }
                        onChmodRequested: (p, mode) => {
                            backend.chmodPath(p, mode, (ok, d, e) => {
                                if (ok) {
                                    root.reloadBothActivePanes(true);
                                    root.inspectEntry({ path: p });
                                    root.showToast("Permissions -> " + mode, false);
                                } else {
                                    root.showToast(e || "chmod failed", true);
                                }
                            });
                        }
                        onCopyTextRequested: (txt, lbl) => {
                            backend.copyText(txt, null);
                            root.showToast(lbl, false);
                        }
                        onChecksumRequested: p => {
                            previewPane.computingExtra = true;
                            backend.checksum(p, (ok, d, e) => {
                                previewPane.computingExtra = false;
                                if (ok && d && d.sha256) {
                                    if (previewPane.pPath === p || previewPane.pPath === String(d.path || ""))
                                        previewPane.computedHash = String(d.sha256);
                                } else {
                                    root.showToast(e || "Checksum failed", true);
                                }
                            });
                        }
                        onDirSizeRequested: p => {
                            previewPane.computingExtra = true;
                            backend.dirSize(p, (ok, d, e) => {
                                previewPane.computingExtra = false;
                                if (ok && d && d.humanSize !== undefined) {
                                    if (previewPane.pPath === p || previewPane.pPath === String(d.path || "")) {
                                        const summary = String(d.humanSize) + " · " + Number(d.files || 0) + " files, " + Number(d.dirs || 0) + " dirs" + (d.capped ? " (capped)" : "");
                                        previewPane.computedDirSummary = summary;
                                    }
                                } else {
                                    root.showToast(e || "Folder size failed", true);
                                }
                            });
                        }
                        onImportThemeRequested: p => {
                            Quickshell.execDetached([Quickshell.shellPath("scripts/manage-themes.sh"), "custom-import", p]);
                            root.showToast("Imported theme & applied", false);
                        }
                        onWallpaperApplied: (p, dyn) => {
                            root.showToast(dyn ? "Applied Matugen dynamic theme" : "Applied wallpaper", false);
                        }
                    }

                    // INLINE CUSTOMIZE DRAWER
                    FileCustomizeDrawer {
                        Layout.preferredWidth: 336
                        Layout.fillHeight: true
                        visible: root.customizeOpen
                        fileStyle: fstyle
                        onCloseRequested: root.customizeOpen = false
                    }
                }

                // ==================== 4. FOOTER STATUS, CLIPBOARD & PROGRESS BAR ====================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    readonly property var ap: root.activePane()

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            text: {
                                if (!parent.parent.ap) return "";
                                const sel = parent.parent.ap.selectedPaths ? parent.parent.ap.selectedPaths.length : 0;
                                const base = parent.parent.ap.dirCount + " folders, " + parent.parent.ap.fileCount + " files (" + parent.parent.ap.totalHumanSize + ")";
                                return sel > 1 ? (sel + " selected  ·  " + base) : base;
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }

                        // Clipboard indicator + Paste button
                        Rectangle {
                            visible: root.clipboardPaths.length > 0 && parent.parent.ap && !parent.parent.ap.isTrashView
                            implicitHeight: 20
                            implicitWidth: clipRow.implicitWidth + 12
                            radius: Theme.r(6)
                            color: Theme.tileActiveBg
                            border.width: Theme.activeControlBorderWidth
                            border.color: fstyle.accent

                            RowLayout {
                                id: clipRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: (root.clipboardOp === "cut" ? "Cut " : "Copied ") + root.clipboardPaths.length + " · Paste (Ctrl+V)"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: Font.Bold
                                    color: fstyle.accent
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pasteIntoActive()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Live Async Progress Pill
                        RowLayout {
                            visible: ShellState.fmOpActive
                            spacing: 6
                            Text {
                                text: ShellState.fmOpLabel + " " + Math.round(ShellState.fmOpProgress * 100) + "% " + ShellState.fmOpCurrent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.Bold
                                color: fstyle.accent
                            }
                            Rectangle {
                                implicitWidth: 80; implicitHeight: 6; radius: 3
                                color: Theme.outlineVariant
                                Rectangle {
                                    height: parent.height
                                    width: Math.round(parent.width * Math.max(0.08, ShellState.fmOpProgress))
                                    radius: 3
                                    color: fstyle.accent
                                }
                            }
                        }

                        // Toast Status
                        Text {
                            visible: root.statusToast.length > 0
                            text: root.statusToast
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: root.isErrorToast ? Theme.error : Theme.success
                        }

                        Text {
                            visible: root.statusToast.length === 0 && !ShellState.fmOpActive
                            text: "Ctrl+L Path · / Filter · F3 Split · Space Preview · Del Trash"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: Theme.outline
                        }
                    }
                }
            }
        }

        // Floating Context Menu
        Rectangle {
            id: ctxMenu
            visible: root.contextOpen
            x: root.contextX
            y: root.contextY
            width: 204
            height: ctxCol.implicitHeight + 12
            radius: Theme.r(10)
            color: Theme.isSimple ? Theme.surfaceContainerLowest : Theme.notchBg
            border.width: 1
            border.color: fstyle.borderCol
            z: 20

            readonly property var ce: root.contextEntry

            ColumnLayout {
                id: ctxCol
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                Repeater {
                    model: {
                        const e = ctxMenu.ce;
                        const ap = root.activePane();
                        const inTrash = ap && ap.isTrashView;
                        const items = [];
                        if (e && !inTrash) {
                            items.push({ act: "open", label: e.isDir ? "Open Folder" : "Open File", icon: "󰏌" });
                            if (!e.isDir) items.push({ act: "edit", label: "Open in Editor", icon: "󰅩" });
                            if (e.isDir) items.push({ act: "term", label: "Open Terminal Here", icon: "󰆍" });
                            if (e.isDir) items.push({ act: "newtab", label: "Open in New Tab", icon: "󰐕" });
                            if (String(e.category || "") === "image") items.push({ act: "wallpaper", label: "Set as Wallpaper", icon: "󰸉" });
                            if (String(e.category || "") === "archive") items.push({ act: "extract", label: "Extract Here", icon: "󰗄" });
                            items.push({ act: "copy", label: "Copy (Ctrl+C)", icon: "󰆏" });
                            items.push({ act: "cut", label: "Cut (Ctrl+X)", icon: "󰆐" });
                            items.push({ act: "rename", label: "Rename (F2)", icon: "󰑕" });
                            items.push({ act: "compress", label: "Compress (.tar.gz)", icon: "󰗄" });
                            items.push({ act: "copypath", label: "Copy Path", icon: "󰌷" });
                            items.push({ act: "trash", label: "Move to Trash", icon: "󰩹" });
                        } else if (!inTrash) {
                            items.push({ act: "mkdir", label: "New Folder", icon: "󰉖" });
                            items.push({ act: "touch", label: "New File", icon: "󰈤" });
                            if (root.clipboardPaths.length > 0)
                                items.push({ act: "paste", label: "Paste Here", icon: "󰆒" });
                            items.push({ act: "term_here", label: "Open Terminal Here", icon: "󰆍" });
                        }
                        return items;
                    }

                    delegate: Rectangle {
                        id: ctxBtn
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(6)
                        color: ctxBMouse.containsMouse ? Theme.hoverBg : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            Text {
                                text: String(ctxBtn.modelData.icon || "")
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(12)
                                color: ctxBtn.modelData.act === "trash" ? Theme.error : fstyle.accent
                            }
                            Text {
                                Layout.fillWidth: true
                                text: String(ctxBtn.modelData.label || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: ctxBtn.modelData.act === "trash" ? Theme.error : Theme.fgSurface
                            }
                        }
                        MouseArea {
                            id: ctxBMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const act = ctxBtn.modelData.act;
                                const e = ctxMenu.ce;
                                const ap = root.activePane();
                                root.contextOpen = false;
                                if (act === "open") root.activateEntry(e, root.currentTab().activePane);
                                else if (act === "edit") backend.openWith(String(e.path), ShellState.defaultEditor, null);
                                else if (act === "term") backend.openTerminal(String(e.path), null);
                                else if (act === "newtab") root.addTab(String(e.path));
                                else if (act === "wallpaper") { Theme.applyWallpaperWithCurrentMode(String(e.path)); root.showToast("Applied wallpaper", false); }
                                else if (act === "extract" && ap) backend.extractArchive(String(e.path), ap.path, (ok) => { if (ok) { root.reloadBothActivePanes(false); root.showToast("Extracted", false); } });
                                else if (act === "copy") root.copySelected(false);
                                else if (act === "cut") root.copySelected(true);
                                else if (act === "rename") root.openPrompt("rename", "Rename Item", String(e.name || ""), e);
                                else if (act === "compress") root.openPrompt("compress", "Archive Name (.tar.gz)", String(e.name || "archive"), root.activeSelectionPaths());
                                else if (act === "copypath") { backend.copyText(String(e.path), null); root.showToast("Path copied", false); }
                                else if (act === "trash") root.trashSelected();
                                else if (act === "mkdir") root.openPrompt("mkdir", "New Folder Name", "New Folder", null);
                                else if (act === "touch") root.openPrompt("touch", "New File Name", "notes.txt", null);
                                else if (act === "paste") root.pasteIntoActive();
                                else if (act === "term_here" && ap) backend.openTerminal(ap.path, null);
                            }
                        }
                    }
                }
            }
        }

        // Inline Modal Prompt (Mkdir / Touch / Rename / Compress / Delete Confirm)
        Rectangle {
            visible: root.promptOpen
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
            z: 30

            MouseArea { anchors.fill: parent; onClicked: root.promptOpen = false }

            Rectangle {
                anchors.centerIn: parent
                width: 360
                height: prCol.implicitHeight + 28
                radius: Theme.r(14)
                color: Theme.isSimple ? Theme.surface : Theme.notchBg
                border.width: 1
                border.color: fstyle.accent

                ColumnLayout {
                    id: prCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: root.promptTitle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        font.weight: Font.Bold
                        color: (root.promptKind === "delete" || root.promptKind === "empty_trash") ? Theme.error : Theme.fgSurface
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.promptKind !== "delete" && root.promptKind !== "empty_trash"
                        implicitHeight: 32
                        radius: Theme.r(8)
                        color: Theme.subCardBg
                        border.width: 1
                        border.color: fstyle.accent

                        TextField {
                            id: promptInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            text: root.promptText
                            color: Theme.fgSurface
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            background: null
                            padding: 0
                            onTextChanged: root.promptText = text
                            onAccepted: root.submitPrompt()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitHeight: 28; implicitWidth: 74; radius: Theme.r(8)
                            color: Theme.subCardBg; border.width: Theme.activeControlBorderWidth; border.color: Theme.cardBorder
                            Text { anchors.centerIn: parent; text: "Cancel"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.promptOpen = false }
                        }

                        Rectangle {
                            implicitHeight: 28; implicitWidth: 86; radius: Theme.r(8)
                            readonly property bool danger: root.promptKind === "delete" || root.promptKind === "empty_trash"
                            color: danger ? Theme.error : fstyle.accent
                            Text { anchors.centerIn: parent; text: parent.danger ? "Confirm" : "Apply"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: parent.danger ? Theme.fgError : fstyle.onAccent }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.submitPrompt() }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: searchDebounceTimer
        interval: 150
        repeat: false
        onTriggered: root.runRecursiveSearch()
    }
}
