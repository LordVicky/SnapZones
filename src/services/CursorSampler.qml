pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// A short-lived, unprivileged helper polls Hyprland's user IPC socket while a
// native mouse drag is active. The layer-shell overlay remains click-through;
// this process is the only cursor-position source used by the extension.
QtObject {
    id: root

    property bool running: false
    property int intervalMs: 16
    property int token: 0
    property bool restartCycle: false
    property int restartAttempts: 0
    property bool sampleSeen: false
    readonly property int maxRestartAttempts: 3
    readonly property int restartDelayMs: 500
    readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("../helpers/cursor_sampler.py")).replace(/^file:\/\//, ""))
    readonly property string pythonExecutable: Quickshell.env("SNAPZONES_PYTHON") || "python3"
    property point cursor: Qt.point(0, 0)
    property bool available: false
    property string lastError: ""

    signal cursorSample(real x, real y, real timestamp, int token)

    function scheduleRestart(reason) {
        if (!root.running || root.restartCycle || root.restartTimer.running)
            return;
        root.available = false;
        root.lastError = String(reason || "cursor sampler stopped while requested").slice(0, 240);
        root.sampleSeen = false;
        if (root.restartAttempts >= root.maxRestartAttempts) {
            root.lastError = root.lastError + " (retry limit reached)";
            return;
        }
        root.restartAttempts += 1;
        root.restartCycle = true;
        root.restartTimer.start();
    }

    property Timer restartTimer: Timer {
        interval: root.restartDelayMs
        repeat: false
        onTriggered: root.restartCycle = false
    }

    function acceptLine(line) {
        let parsed;
        try {
            parsed = JSON.parse(String(line || ""));
        } catch (_error) {
            return;
        }
        if (parsed?.type === "status") {
            root.lastError = String(parsed?.error || "");
            root.available = parsed?.available === true;
            return;
        }
        if (parsed?.type !== "cursor")
            return;
        const x = Number(parsed?.x);
        const y = Number(parsed?.y);
        if (!Number.isFinite(x) || !Number.isFinite(y) || Math.abs(x) > 10000000 || Math.abs(y) > 10000000)
            return;
        root.cursor = Qt.point(Math.round(x), Math.round(y));
        root.available = true;
        root.lastError = "";
        root.sampleSeen = true;
        // ponytail: one helper exists only for the active drag; use the live
        // controller token instead of racing the Process command binding.
        root.cursorSample(root.cursor.x, root.cursor.y, Number(parsed?.time) || 0, root.token);
    }

    property Process samplerProcess: Process {
        id: process
        running: root.running && !root.restartCycle
        command: [root.pythonExecutable, root.scriptPath, "--interval-ms", String(Math.max(8, Math.min(1000, root.intervalMs))), "--token", String(Math.max(0, root.token))]

        stdout: SplitParser {
            onRead: line => root.acceptLine(line)
        }

        stderr: SplitParser {
            onRead: line => {
                if (String(line || "").trim())
                    root.lastError = String(line).trim().slice(0, 240);
            }
        }

        onStarted: {
            root.sampleSeen = false;
        }

        onRunningChanged: {
            if (!running && root.running && !root.restartCycle)
                // Quickshell exposes the requested process state through this
                // signal. A false transition covers both FailedToStart and a
                // helper that stopped unexpectedly.
                root.scheduleRestart("cursor sampler failed to start or stopped while requested");
        }

        onExited: (exitCode, _exitStatus) => {
            root.available = false;
            if (!root.running)
                return;
            const code = Number(exitCode);
            root.scheduleRestart(Number.isFinite(code) && code !== 0 ? "cursor sampler exited (" + code + ")" : "cursor sampler exited");
        }
    }

    onRunningChanged: {
        if (!root.running) {
            root.available = false;
            root.restartTimer.stop();
            root.restartCycle = false;
            root.restartAttempts = 0;
            root.sampleSeen = false;
        }
    }
}
