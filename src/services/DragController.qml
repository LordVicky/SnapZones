pragma ComponentBehavior: Bound

import QtQuick
import "../js/drag.js" as DragState

// Coordinates the compositor-owned native drag with the visual, click-through
// zone overlay. It never reads raw input and never moves the window until the
// release notification arrives from the user's Hyprland Lua binding.
QtObject {
    id: root

    property var manager
    property bool enabled: false
    readonly property bool active: root.dragState.phase === "active"
    property var dragState: DragState.createDragState()
    property point cursor: Qt.point(0, 0)
    property bool cursorAvailable: false
    readonly property int activeWatchdogMs: 5000
    readonly property int hardLifetimeMs: 30000

    signal started(string address)
    signal finished(int zone)
    signal cancelled(string reason)

    function now() {
        return Date.now();
    }

    function start() {
        if (!root.enabled || root.active || !root.manager || !root.manager.ready)
            return false;
        if (!root.manager.beginDragCapture())
            return false;
        const target = root.manager.pendingWindow;
        root.cursorAvailable = false;
        root.cursor = Qt.point(0, 0);
        activityWatchdogTimer.stop();
        hardLifetimeTimer.stop();
        const result = DragState.reduceDrag(root.dragState, {
            type: "start",
            address: root.manager.pendingAddress,
            monitor: root.manager.targetMonitorName,
            point: null,
            now: root.now()
        });
        if (result.effect.type !== "started") {
            root.manager.cancelDragCapture();
            return false;
        }
        root.dragState = result.state;
        root.manager.dragActive = true;
        root.manager.setHoveredZone(-1);
        activityWatchdogTimer.start();
        // This timer is a hard upper bound for one gesture. Unlike the
        // inactivity watchdog, valid cursor samples must never refresh it.
        hardLifetimeTimer.start();
        root.started(String(target?.address || root.manager.pendingAddress || ""));
        return true;
    }

    function monitorAndZone(point) {
        if (!root.manager || !point)
            return {
                monitor: "",
                zone: -1
            };
        const monitorName = root.manager.monitorForGlobalPoint(point);
        if (monitorName)
            root.manager.setDragTargetMonitor(monitorName);
        const screen = root.manager.targetScreen();
        if (!screen)
            return {
                monitor: monitorName,
                zone: -1
            };
        const rects = root.manager.globalZoneRectsForScreen(screen);
        return {
            monitor: monitorName,
            zone: DragState.zoneAtPoint(rects, point)
        };
    }

    function acceptCursor(x, y, sampleToken = root.dragState.token) {
        if (!root.active || !Number.isSafeInteger(Number(sampleToken)) || Number(sampleToken) !== Number(root.dragState.token))
            return false;
        const point = {
            x: Number(x),
            y: Number(y)
        };
        if (!Number.isFinite(point.x) || !Number.isFinite(point.y))
            return false;
        // A valid sample proves that the helper and compositor IPC are alive;
        // keep the generous active-drag watchdog from expiring mid-gesture.
        activityWatchdogTimer.restart();
        root.cursor = Qt.point(Math.round(point.x), Math.round(point.y));
        root.manager.dragCursor = root.cursor;
        root.cursorAvailable = true;
        const hover = root.monitorAndZone(point);
        const result = DragState.reduceDrag(root.dragState, {
            type: "move",
            token: Number(sampleToken),
            point: point,
            zone: hover.zone,
            now: root.now()
        });
        if (result.effect.type !== "ignored") {
            root.dragState = result.state;
            root.manager.setHoveredZone(hover.zone);
        }
        return true;
    }

    function end() {
        if (!root.active)
            return false;
        const point = root.cursorAvailable ? root.cursor : root.dragState.point;
        if (!point) {
            root.cancel("cursor-timeout");
            return false;
        }
        const hover = root.monitorAndZone(point);
        const result = DragState.reduceDrag(root.dragState, {
            type: "end",
            token: root.dragState.token,
            point: point,
            zone: hover.zone,
            now: root.now()
        });
        if (result.effect.type === "ignored") {
            root.cancel("stale-release");
            return false;
        }
        activityWatchdogTimer.stop();
        hardLifetimeTimer.stop();
        root.dragState = result.state;
        root.manager.setHoveredZone(-1);
        if (result.effect.type === "drop") {
            const accepted = root.manager.placeZone(result.effect.zone, true);
            root.manager.dragActive = false;
            if (accepted)
                root.finished(result.effect.zone);
            else
                root.manager.cancelDragCapture();
        } else {
            root.manager.dragActive = false;
            root.manager.cancelDragCapture();
            root.cancelled(result.effect.reason || "no-zone");
        }
        return result.effect.type === "drop";
    }

    function cancel(reason = "cancelled") {
        if (!root.active) {
            activityWatchdogTimer.stop();
            hardLifetimeTimer.stop();
            return false;
        }
        activityWatchdogTimer.stop();
        hardLifetimeTimer.stop();
        const result = DragState.reduceDrag(root.dragState, {
            type: "cancel",
            token: root.dragState.token,
            reason: String(reason)
        });
        root.dragState = result.state;
        root.manager.dragActive = false;
        root.manager.setHoveredZone(-1);
        root.manager.cancelDragCapture();
        root.cancelled(String(reason));
        return true;
    }

    property CursorSampler cursorSampler: CursorSampler {
        id: sampler
        running: root.active && root.enabled
        token: root.dragState.token
        intervalMs: root.manager?.config?.cursorSampleIntervalMs ?? 16
        onCursorSample: (x, y, _timestamp, sampleToken) => root.acceptCursor(x, y, sampleToken)
    }

    property Timer activityWatchdogTimer: Timer {
        id: activityWatchdogTimer
        interval: root.activeWatchdogMs
        repeat: false
        onTriggered: {
            if (root.active)
                root.cancel("cursor-timeout");
        }
    }

    property Timer hardLifetimeTimer: Timer {
        id: hardLifetimeTimer
        interval: root.hardLifetimeMs
        repeat: false
        onTriggered: {
            if (root.active)
                root.cancel("lifetime-timeout");
        }
    }

    onEnabledChanged: {
        if (!root.enabled && root.active)
            root.cancel("disabled");
    }
}
