pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Item {
    id: root

    property bool active: false
    property bool ready: false
    property string lastError: ""

    property int _nextId: 1
    property var _callbacks: ({})
    property var _queue: []
    property int _restartAttempts: 0

    signal progressEvent(int reqId, string label, int done, int total, int pct, string current)

    onActiveChanged: {
        if (!active) {
            root.ready = false;
            root._callbacks = ({});
            root._queue = [];
            root._restartAttempts = 0;
            ShellState.fmOpActive = false;
            ShellState.fmOpLabel = "";
            ShellState.fmOpProgress = 0;
            ShellState.fmOpCurrent = "";
        }
    }

    function _flushQueue(): void {
        if (!daemon.running || !root.ready || root._queue.length === 0)
            return;
        const pending = root._queue;
        root._queue = [];
        for (let i = 0; i < pending.length; i++)
            daemon.write(pending[i] + "\n");
    }

    function _handleLine(rawLine: string): void {
        const trimmed = (rawLine || "").trim();
        if (trimmed.length === 0)
            return;
        let msg = null;
        try {
            msg = JSON.parse(trimmed);
        } catch (err) {
            return;
        }
        if (!msg)
            return;

        if (msg.event === "ready") {
            root.ready = true;
            root.lastError = "";
            root._restartAttempts = 0;
            root._flushQueue();
            return;
        }

        if (msg.event === "progress") {
            const done = Number(msg.done || 0);
            const total = Math.max(1, Number(msg.total || 1));
            const pct = Number(msg.pct || 0);
            const lbl = String(msg.label || "Working");
            const cur = String(msg.current || "");
            const activeOp = done < total;
            ShellState.fmOpActive = activeOp;
            ShellState.fmOpLabel = activeOp ? lbl : "";
            ShellState.fmOpProgress = activeOp ? (pct / 100.0) : 0.0;
            ShellState.fmOpCurrent = activeOp ? cur : "";
            root.progressEvent(Number(msg.id || 0), lbl, done, total, pct, cur);
            return;
        }

        const rid = Number(msg.id || 0);
        const cb = root._callbacks[rid];
        if (cb) {
            const copy = Object.assign({}, root._callbacks);
            delete copy[rid];
            root._callbacks = copy;
            if (!msg.ok)
                ShellState.fmOpActive = false;
            cb(!!msg.ok, msg.data, msg.error ? String(msg.error) : "");
        }
    }

    function request(op: string, params: var, callback: var): int {
        const rid = root._nextId++;
        const payload = Object.assign({ id: rid, op: op }, params || {});
        if (callback) {
            const copy = Object.assign({}, root._callbacks);
            copy[rid] = callback;
            root._callbacks = copy;
        }
        const line = JSON.stringify(payload);
        if (daemon.running && root.ready) {
            daemon.write(line + "\n");
        } else {
            root._queue = root._queue.concat([line]);
            if (root.active && !daemon.running)
                daemon.running = true;
        }
        return rid;
    }

    function listDir(path: string, hidden: bool, sortBy: string, desc: bool, dirsFirst: bool, cb: var): void {
        request("list", {
            path: path,
            hidden: hidden,
            sort: sortBy,
            desc: desc,
            dirsFirst: dirsFirst
        }, cb);
    }

    function dirStamp(path: string, cb: var): void {
        request("dir_stamp", { path: path }, cb);
    }

    function getPlaces(cb: var): void {
        request("places", {}, cb);
    }

    function previewPath(path: string, cb: var): void {
        request("preview", { path: path }, cb);
    }

    function searchDir(path: string, query: string, hidden: bool, maxRes: int, cb: var): void {
        request("search", {
            path: path,
            query: query,
            hidden: hidden,
            max: maxRes
        }, cb);
    }

    function mkdir(dirPath: string, name: string, cb: var): void {
        request("mkdir", { path: dirPath, name: name }, cb);
    }

    function touch(dirPath: string, name: string, cb: var): void {
        request("touch", { path: dirPath, name: name }, cb);
    }

    function renameItem(path: string, newName: string, cb: var): void {
        request("rename", { path: path, newName: newName }, cb);
    }

    function copyPaths(paths: var, dest: string, cb: var): void {
        ShellState.fmOpActive = true;
        ShellState.fmOpLabel = "Copying";
        ShellState.fmOpProgress = 0.0;
        request("copy", { paths: paths, dest: dest, overwrite: false }, (ok, data, err) => {
            ShellState.fmOpActive = false;
            if (cb) cb(ok, data, err);
        });
    }

    function movePaths(paths: var, dest: string, cb: var): void {
        ShellState.fmOpActive = true;
        ShellState.fmOpLabel = "Moving";
        ShellState.fmOpProgress = 0.0;
        request("move", { paths: paths, dest: dest, overwrite: false }, (ok, data, err) => {
            ShellState.fmOpActive = false;
            if (cb) cb(ok, data, err);
        });
    }

    function trashPaths(paths: var, cb: var): void {
        request("trash", { paths: paths }, cb);
    }

    function trashList(cb: var): void {
        request("trash_list", {}, cb);
    }

    function trashRestore(trashName: string, cb: var): void {
        request("trash_restore", { trashName: trashName }, cb);
    }

    function trashEmpty(cb: var): void {
        request("trash_empty", {}, cb);
    }

    function deletePaths(paths: var, cb: var): void {
        request("delete", { paths: paths }, cb);
    }

    function chmodPath(path: string, mode: string, cb: var): void {
        request("chmod", { path: path, mode: mode }, cb);
    }

    function compressPaths(paths: var, destDir: string, name: string, format: string, cb: var): void {
        ShellState.fmOpActive = true;
        ShellState.fmOpLabel = "Compressing";
        ShellState.fmOpProgress = 0.0;
        request("compress", { paths: paths, destDir: destDir, name: name, format: format }, (ok, data, err) => {
            ShellState.fmOpActive = false;
            if (cb) cb(ok, data, err);
        });
    }

    function extractArchive(path: string, destDir: string, cb: var): void {
        ShellState.fmOpActive = true;
        ShellState.fmOpLabel = "Extracting";
        ShellState.fmOpProgress = 0.0;
        request("extract", { path: path, destDir: destDir }, (ok, data, err) => {
            ShellState.fmOpActive = false;
            if (cb) cb(ok, data, err);
        });
    }

    function bookmarkAdd(path: string, name: string, cb: var): void {
        request("bookmark_add", { path: path, name: name }, cb);
    }

    function bookmarkRemove(path: string, cb: var): void {
        request("bookmark_remove", { path: path }, cb);
    }

    function copyUri(paths: var, cb: var): void {
        request("copy_uri", { paths: paths }, cb);
    }

    function copyText(text: string, cb: var): void {
        request("copy_text", { text: text }, cb);
    }

    function openPath(path: string, cb: var): void {
        request("open", { path: path }, cb);
    }

    function openWith(path: string, app: string, cb: var): void {
        request("open_with", { path: path, app: app }, cb);
    }

    function openTerminal(dirPath: string, cb: var): void {
        request("terminal", { path: dirPath, terminal: ShellState.defaultTerminal }, cb);
    }

    Process {
        id: daemon
        command: [Quickshell.shellPath("bin/mango-fm"), "serve"]
        stdinEnabled: true
        running: root.active
        stdout: SplitParser {
            onRead: line => root._handleLine(line)
        }
        onExited: exitCode => {
            root.ready = false;
            ShellState.fmOpActive = false;
            if (root.active && root._restartAttempts < 3) {
                root._restartAttempts += 1;
                root.lastError = "Backend restarted (" + exitCode + ")";
                restartTimer.restart();
            } else if (root.active) {
                root.lastError = "Rust backend stopped (code " + exitCode + ")";
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root.active && !daemon.running)
                daemon.running = true;
        }
    }
}
