pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import "../js/geometry.js" as Geometry
import "../js/layouts.js" as Layouts
import "../js/validation.js" as Validation
import "../overlay"
import "."

// Main state machine for Phase 2. It is deliberately a service so the
// cheatsheet, picker, and native drag controller share one layout selection
// and one placement queue.
// A process guard keeps IPC/global shortcuts/window overlays out of ii-vynx's
// auxiliary settings process (the same issue handled by ii-eve's app launcher).
Scope {
    id: root

    property string extensionId: "vynx-zones"
    property int _processKind: 0
    readonly property bool isMainShell: _processKind === 1

    property var layouts: Layouts.listLayouts()
    property var rawConfig: ExtensionManager.extensionConfigs?.[root.extensionId] || ({})
    readonly property var config: Validation.sanitizeConfig(root.rawConfig)
    property string activeLayoutId: "halves"
    property var monitorLayouts: ({})

    property bool pickerOpen: false
    property string targetMonitorName: ""
    property string pendingAddress: ""
    property var pendingWindow: null
    property int hoveredZone: -1
    property string errorMessage: ""
    property var savedGeometry: ({})
    property var pendingPlacement: null
    property var pendingRestore: null
    property int geometryRevision: 0
    // Set by DragController while the native Super+mouse move is active.
    // Unlike pickerOpen this state must not request keyboard focus.
    property bool dragActive: false
    property point dragCursor: Qt.point(0, 0)

    readonly property var currentLayout: Layouts.getLayout(root.layoutForMonitor(root.targetMonitorName))
    readonly property string currentLayoutName: root.currentLayout?.name || "Halves"
    readonly property bool ready: root.isMainShell && root.config.enabled

    HyprlandBridge {
        id: bridge
    }

    DragController {
        id: dragController
        manager: root
        enabled: root.ready && root.config.dragToZone
        onCancelled: reason => {
            if (reason !== "no-zone")
                root.errorMessage = "Drag cancelled: " + reason;
        }
    }

    Process {
        id: processKindProbe
        running: true
        command: ["bash", "-c", "tr '\\0' ' ' < /proc/" + Quickshell.processId + "/cmdline"]
        stdout: StdioCollector {
            id: cmdlineCollector
        }
        onExited: {
            // qs -c <name> is the persistent shell; qs -p <file> is a helper,
            // including the settings process that also loads extension services.
            root._processKind = / -c /.test(String(cmdlineCollector.text || "")) ? 1 : -1;
        }
    }

    Connections {
        target: ExtensionManager
        function onExtensionConfigsChanged() {
            root.syncConfig();
        }
    }

    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() {
            const focused = root.focusedMonitorName();
            if (!root.pickerOpen && focused) {
                root.targetMonitorName = focused;
                root.activeLayoutId = root.layoutForMonitor(focused);
            }
            root.geometryRevision += 1;
        }
        function onRawEvent(event) {
            const name = String(event?.name || "");
            if (name === "monitorremoved" || name === "monitoradded")
                root.monitorTopologyChanged();
        }
    }

    Connections {
        target: HyprlandData
        function onMonitorsChanged() {
            root.monitorTopologyChanged();
        }
    }

    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!GlobalStates.superDown && dragController.active)
                dragController.end();
        }
    }

    Connections {
        target: bridge
        function onCommandRejected(_operation, reason) {
            root.errorMessage = reason;
        }
        function onCommandFinished(operation, success, exitCode, errorText) {
            if (operation !== "place" && operation !== "retile")
                return;
            if (!success)
                root.errorMessage = errorText || ("Hyprland rejected placement (exit " + exitCode + ").");
            else
                root.errorMessage = "";
            if (operation === "place" && root.pendingPlacement) {
                const placement = root.pendingPlacement;
                root.pendingPlacement = null;
                if (!success && root.savedGeometry?.[placement.address] === placement.saved) {
                    const remaining = Object.assign({}, root.savedGeometry);
                    delete remaining[placement.address];
                    root.savedGeometry = remaining;
                }
            }
            if (root.pendingRestore) {
                const pending = root.pendingRestore;
                root.pendingRestore = null;
                if (success && root.savedGeometry?.[pending.address] === pending.saved) {
                    const remaining = Object.assign({}, root.savedGeometry);
                    delete remaining[pending.address];
                    root.savedGeometry = remaining;
                }
            }
        }
    }

    function syncConfig() {
        const config = root.config;
        const persisted = config && typeof config.monitorLayouts === "object" ? config.monitorLayouts : {};
        root.monitorLayouts = Object.assign({}, persisted);
        const focused = root.focusedMonitorName();
        if (!root.pickerOpen && focused) {
            root.targetMonitorName = focused;
            root.activeLayoutId = root.layoutForMonitor(focused);
        } else {
            root.activeLayoutId = root.layoutForMonitor(root.targetMonitorName);
        }
        root.geometryRevision += 1;
    }

    Component.onCompleted: root.syncConfig()
    onExtensionIdChanged: root.syncConfig()
    onTargetMonitorNameChanged: root.geometryRevision += 1

    function configValue(key, fallback) {
        return root.config?.[key] ?? fallback;
    }

    function focusedMonitorName() {
        const focused = String(Hyprland.focusedMonitor?.name || "");
        if (focused)
            return focused;
        const activeWorkspaceMonitor = HyprlandData.activeWorkspace?.monitor;
        if (typeof activeWorkspaceMonitor === "string")
            return activeWorkspaceMonitor;
        return String(activeWorkspaceMonitor?.name || "");
    }

    function layoutForMonitor(monitorName) {
        const name = String(monitorName || root.focusedMonitorName() || "");
        const selected = name && root.monitorLayouts?.[name] ? root.monitorLayouts[name] : root.config.layout;
        return Layouts.getLayout(selected).id;
    }

    function setLayout(layoutId, monitorName) {
        const layout = Layouts.getLayout(layoutId);
        if (!layout)
            return;
        const name = String(monitorName || root.targetMonitorName || "");
        root.activeLayoutId = layout.id;
        if (Validation.isSafeMonitorName(name)) {
            const assignments = Object.assign({}, root.monitorLayouts);
            assignments[name] = layout.id;
            root.monitorLayouts = assignments;
            ExtensionManager.setExtensionConfig(root.extensionId, "monitorLayouts", assignments);
            root.geometryRevision += 1;
            return;
        }
        ExtensionManager.setExtensionConfig(root.extensionId, "layout", layout.id);
        root.geometryRevision += 1;
    }

    function cycleLayout(direction = 1) {
        if (!root.pickerOpen)
            root.targetMonitorName = root.focusedMonitorName() || root.targetMonitorName;
        const next = Layouts.nextLayoutId(root.layoutForMonitor(root.targetMonitorName), direction);
        root.setLayout(next, root.targetMonitorName);
    }

    function monitorFromJson(name) {
        const monitors = Array.isArray(HyprlandData.monitors) ? HyprlandData.monitors : [];
        return monitors.find(monitor => String(monitor?.name || "") === String(name || "")) || null;
    }

    function nativeMonitors() {
        const values = Hyprland.monitors?.values;
        if (values === undefined || values === null)
            return null;
        return values;
    }

    function monitorStillExists(name) {
        const wanted = String(name || "");
        const screens = Quickshell.screens || [];
        if (screens.some(screen => String(screen?.name || "") === wanted))
            return true;
        const native = root.nativeMonitors();
        if (native !== null && native.length > 0)
            return native.some(monitor => String(monitor?.name || "") === wanted);
        return false;
    }

    function closePickerIfTargetGone() {
        if ((!root.pickerOpen && !root.dragActive) || !root.targetMonitorName || root.monitorStillExists(root.targetMonitorName))
            return;
        const focused = root.focusedMonitorName();
        if (root.dragActive)
            dragController.cancel("monitor-disconnected");
        else
            root.hidePicker();
        root.targetMonitorName = focused === root.targetMonitorName ? "" : focused;
        root.activeLayoutId = root.layoutForMonitor(root.targetMonitorName);
        root.errorMessage = "Target monitor disconnected.";
    }

    function monitorTopologyChanged() {
        root.geometryRevision += 1;
        // The immediate check handles model updates delivered synchronously;
        // the deferred check handles Hyprland's event-before-model ordering.
        root.closePickerIfTargetGone();
        Qt.callLater(root.closePickerIfTargetGone);
    }

    function monitorForScreen(screen) {
        const name = String(screen?.name || root.targetMonitorName || Hyprland.focusedMonitor?.name || "");
        const json = root.monitorFromJson(name);
        // hyprctl JSON is authoritative for compositor placement coordinates
        // and reserved edges. Qt/Quickshell monitor snapshots are fallbacks.
        if (json)
            return json;
        const native = (root.nativeMonitors() || []).find(monitor => String(monitor?.name || "") === name);
        const nativeSnapshot = native?.lastIpcObject;
        const snapshotWidth = nativeSnapshot?.width ?? nativeSnapshot?.size?.[0] ?? nativeSnapshot?.size?.width;
        const snapshotHeight = nativeSnapshot?.height ?? nativeSnapshot?.size?.[1] ?? nativeSnapshot?.size?.height;
        if (nativeSnapshot && Number(snapshotWidth) > 0 && Number(snapshotHeight) > 0) {
            return Object.assign({}, nativeSnapshot);
        }
        return {
            name: name,
            x: screen?.x || 0,
            y: screen?.y || 0,
            width: screen?.width || 1,
            height: screen?.height || 1
        };
    }

    function monitorForWindow(window) {
        if (!window)
            return "";
        const rawMonitor = window.monitor;
        if (typeof rawMonitor === "string" && !/^\d+$/.test(rawMonitor))
            return rawMonitor;
        if (rawMonitor && typeof rawMonitor === "object" && rawMonitor.name)
            return String(rawMonitor.name);
        const monitorId = Number(rawMonitor);
        if (rawMonitor !== undefined && rawMonitor !== null && rawMonitor !== "" && Number.isInteger(monitorId)) {
            const native = (root.nativeMonitors() || []).find(monitor => Number(monitor?.id) === monitorId);
            if (native?.name)
                return String(native.name);
            const json = (Array.isArray(HyprlandData.monitors) ? HyprlandData.monitors : []).find(monitor => Number(monitor?.id) === monitorId);
            if (json?.name)
                return String(json.name);
        }
        return String(window.monitorName || "");
    }

    function zoneRectsForScreen(screen) {
        const monitor = root.monitorForScreen(screen);
        // Layer-shell coordinates are local to the Quickshell Screen. Do not
        // use the monitor JSON origin here; it belongs only in placementRect.
        const workArea = Geometry.screenWorkArea(screen, monitor, root.config.padding);
        const layout = Layouts.getLayout(root.layoutForMonitor(monitor.name));
        const pixels = Geometry.zonesToPixels(layout.zones, workArea, root.config.gap);
        return pixels.map((rect, index) => ({
                    x: rect.x,
                    y: rect.y,
                    width: rect.width,
                    height: rect.height,
                    index: index,
                    label: String(index + 1),
                    name: layout.name
                }));
    }

    function placementRectForScreen(screen, index) {
        const monitor = root.monitorForScreen(screen);
        const workArea = Geometry.globalWorkAreaForScreen(monitor, screen, root.config.padding);
        const layout = Layouts.getLayout(root.layoutForMonitor(monitor.name));
        const zone = layout.zones[Number(index)];
        if (!zone)
            return null;
        return Geometry.zoneToPixels(zone, workArea, root.config.gap);
    }

    function activeWindowSnapshot() {
        // ii-vynx obtains active windows from the foreign-toplevel manager.
        // Capture the address before the picker takes keyboard focus.
        const toplevel = ToplevelManager.activeToplevel;
        let raw = toplevel?.lastIpcObject;
        if (!raw?.address)
            raw = toplevel?.HyprlandToplevel || toplevel;
        const address = String(raw?.address || raw?.HyprlandToplevel?.address || "");
        if (!Validation.isSafeAddress(address))
            return null;
        const normalizedAddress = Validation.normalizeAddress(address);
        const json = HyprlandData.windowByAddress?.[normalizedAddress] || HyprlandData.windowByAddress?.[address] || {};
        // The foreign-toplevel object is sparse and may expose default values
        // for fields it does not track. Let hyprctl's client snapshot win for
        // geometry and state such as `floating` and `fullscreen`.
        return Object.assign({}, raw, json, {
            address: normalizedAddress
        });
    }

    // Capture the focused client for a compositor-owned native drag without
    // opening the keyboard-focused picker. The drag overlay is deliberately
    // click-through, so the window keeps receiving Hyprland's pointer move.
    function beginDragCapture() {
        if (!root.ready || bridge.busy || root.pickerOpen)
            return false;
        const window = root.activeWindowSnapshot();
        if (!window || Validation.isUnsupportedWindow(window)) {
            root.errorMessage = "The focused window cannot be dragged into a zone.";
            return false;
        }
        if (window.floating !== true && !root.config.floatOnPlacement) {
            root.errorMessage = "The focused window is tiled; enable Float tiled windows to place it.";
            return false;
        }
        const monitor = root.monitorForWindow(window) || root.focusedMonitorName();
        if (!monitor || !root.monitorStillExists(monitor)) {
            root.errorMessage = "No active monitor is available for zone placement.";
            return false;
        }
        root.pendingWindow = window;
        root.pendingAddress = window.address;
        root.targetMonitorName = monitor;
        root.hoveredZone = -1;
        root.dragCursor = Qt.point(0, 0);
        root.errorMessage = "";
        return true;
    }

    function cancelDragCapture() {
        root.pendingAddress = "";
        root.pendingWindow = null;
        root.hoveredZone = -1;
        root.dragCursor = Qt.point(0, 0);
    }

    function cancelDrag(reason = "cancelled") {
        return dragController.cancel(String(reason));
    }

    function setDragTargetMonitor(name) {
        const wanted = String(name || "");
        if (!Validation.isSafeMonitorName(wanted) || !root.monitorStillExists(wanted))
            return false;
        if (root.targetMonitorName !== wanted)
            root.targetMonitorName = wanted;
        root.activeLayoutId = root.layoutForMonitor(wanted);
        return true;
    }

    function globalZoneRectsForScreen(screen) {
        const monitor = root.monitorForScreen(screen);
        const layout = Layouts.getLayout(root.layoutForMonitor(monitor.name));
        const workArea = Geometry.globalWorkAreaForScreen(monitor, screen, root.config.padding);
        const pixels = Geometry.zonesToPixels(layout.zones, workArea, root.config.gap);
        return pixels.map((rect, index) => ({
                    x: rect.x,
                    y: rect.y,
                    width: rect.width,
                    height: rect.height,
                    index: index,
                    label: String(index + 1),
                    name: layout.name
                }));
    }

    function monitorForGlobalPoint(point) {
        const x = Number(point?.x);
        const y = Number(point?.y);
        if (!Number.isFinite(x) || !Number.isFinite(y))
            return "";
        const screens = Quickshell.screens || [];
        for (const screen of screens) {
            const monitor = Geometry.normalizeMonitor(root.monitorForScreen(screen));
            const width = monitor.width / Math.max(0.1, monitor.scale);
            const height = monitor.height / Math.max(0.1, monitor.scale);
            if (x >= monitor.x && x < monitor.x + width && y >= monitor.y && y < monitor.y + height)
                return monitor.name;
        }
        return "";
    }

    function nativeToplevels() {
        const values = ToplevelManager.toplevels?.values;
        if (values === undefined || values === null)
            return null;
        return values;
    }

    function currentWindowForAddress(address) {
        const wanted = Validation.normalizeAddress(address);
        if (!wanted)
            return null;
        const json = HyprlandData.windowByAddress?.[wanted] || {};
        const native = (root.nativeToplevels() || []).find(toplevel => {
            const raw = String(toplevel?.address || toplevel?.HyprlandToplevel?.address || toplevel?.lastIpcObject?.address || "");
            return Validation.normalizeAddress(raw) === wanted;
        });
        let raw = native?.lastIpcObject;
        if (!raw?.address)
            raw = native?.HyprlandToplevel || native || {};
        return Object.assign({}, raw, json, {
            address: wanted
        });
    }

    function windowStillExists(address) {
        const candidateAddress = String(address || "");
        if (!Validation.isSafeAddress(candidateAddress))
            return false;
        const wanted = Validation.normalizeAddress(candidateAddress);
        const native = root.nativeToplevels();
        if (native !== null) {
            return native.some(toplevel => {
                const rawCandidate = String(toplevel?.address || toplevel?.HyprlandToplevel?.address || toplevel?.lastIpcObject?.address || "");
                const candidate = Validation.normalizeAddress(rawCandidate);
                return candidate === wanted;
            });
        }
        return !!HyprlandData.windowByAddress?.[wanted];
    }

    function beginPicker() {
        if (!root.ready || root.dragActive)
            return false;
        if (bridge.busy) {
            root.errorMessage = "Another placement is still in progress.";
            return false;
        }
        const window = root.activeWindowSnapshot();
        if (!window || Validation.isUnsupportedWindow(window)) {
            root.errorMessage = "The focused window cannot be placed in a zone.";
            return false;
        }
        if (window.floating !== true && !root.config.floatOnPlacement) {
            root.errorMessage = "The focused window is tiled; enable Float tiled windows to place it.";
            return false;
        }
        const monitor = root.monitorForWindow(window) || root.focusedMonitorName();
        if (!monitor || !root.monitorStillExists(monitor)) {
            root.errorMessage = "No active monitor is available for zone placement.";
            return false;
        }
        root.pendingWindow = window;
        root.pendingAddress = window.address;
        root.targetMonitorName = monitor;
        root.hoveredZone = -1;
        root.errorMessage = "";
        root.pickerOpen = true;
        return true;
    }

    function targetScreen() {
        return (Quickshell.screens || []).find(candidate => String(candidate?.name || "") === root.targetMonitorName) || null;
    }

    function revalidatePlacement(zoneIndex, fromDrag = false) {
        const index = Number(zoneIndex);
        if (!Number.isInteger(index) || index < 0)
            return {
                ok: false,
                reason: "The selected zone is invalid."
            };
        const address = Validation.normalizeAddress(root.pendingAddress);
        if (!address)
            return {
                ok: false,
                reason: "The target window address is invalid."
            };
        if (!root.windowStillExists(address))
            return {
                ok: false,
                reason: "The target window closed before placement."
            };
        const window = root.currentWindowForAddress(address);
        if (!window || Validation.isUnsupportedWindow(window))
            return {
                ok: false,
                reason: "The target window is no longer placeable."
            };
        if (window.floating !== true && !root.config.floatOnPlacement)
            return {
                ok: false,
                reason: "The target is tiled; enable Float tiled windows to place it."
            };
        const currentMonitor = root.monitorForWindow(window);
        // A native drag is allowed to cross monitors. The drag controller has
        // already selected and validated targetMonitorName from the latest
        // cursor sample; keep the equality guard for picker placements.
        if (!fromDrag && currentMonitor && currentMonitor !== root.targetMonitorName)
            return {
                ok: false,
                reason: "The target window moved to another monitor."
            };
        if (!root.targetMonitorName || !root.monitorStillExists(root.targetMonitorName))
            return {
                ok: false,
                reason: "The target monitor is no longer connected."
            };
        const screen = root.targetScreen();
        if (!screen)
            return {
                ok: false,
                reason: "The target monitor has no layer-shell surface."
            };
        const rect = root.placementRectForScreen(screen, index);
        if (!rect || rect.width < 1 || rect.height < 1)
            return {
                ok: false,
                reason: "The selected zone is no longer valid."
            };
        return {
            ok: true,
            address: address,
            window: window,
            screen: screen,
            rect: rect
        };
    }

    function hidePicker() {
        root.pickerOpen = false;
        root.pendingAddress = "";
        root.pendingWindow = null;
        root.hoveredZone = -1;
    }

    function togglePicker() {
        if (root.pickerOpen)
            root.hidePicker();
        else
            root.beginPicker();
    }

    function placeZone(index, fromDrag = false) {
        let zoneIndex = Number(index);
        if (!Number.isInteger(zoneIndex) || zoneIndex < 0)
            return false;
        if (fromDrag === true && !root.dragActive)
            return false;
        if (bridge.busy) {
            root.errorMessage = "Another placement is still in progress.";
            return false;
        }
        if (!root.pickerOpen && !fromDrag && !root.beginPicker())
            return false;
        const placement = root.revalidatePlacement(zoneIndex, fromDrag === true);
        if (!placement.ok) {
            root.errorMessage = placement.reason;
            root.hidePicker();
            return false;
        }
        // Native Hyprland dragging has already changed the live rectangle by
        // release time. Keep the press-time snapshot for Restore so a failed
        // or subsequently reversed snap returns to the pre-drag geometry.
        const old = fromDrag && root.pendingWindow ? root.pendingWindow : placement.window;
        const clientState = HyprlandData.windowByAddress?.[placement.address];
        const floatingWasReported = clientState && typeof clientState.floating === "boolean";
        // Foreign-toplevel objects may expose a default `false` even though
        // they do not track floating state. Only an explicit hyprctl client
        // snapshot is authoritative; unknown state restores as floating so a
        // floating window is never accidentally inserted into the tile tree.
        const wasFloating = floatingWasReported ? clientState.floating : true;
        const mode = old.floating === true || wasFloating ? "none" : "floating";
        const accepted = bridge.place(placement.address, placement.rect, {
            mode: mode
        });
        if (!accepted) {
            root.errorMessage = "The placement command could not be queued.";
            return false;
        }
        const saved = {
            address: placement.address,
            x: old.at?.[0] ?? old.x ?? 0,
            y: old.at?.[1] ?? old.y ?? 0,
            width: old.size?.[0] ?? old.width ?? 1,
            height: old.size?.[1] ?? old.height ?? 1,
            floating: wasFloating,
            monitor: fromDrag ? (root.monitorForWindow(old) || root.targetMonitorName) : root.targetMonitorName
        };
        root.savedGeometry = Object.assign({}, root.savedGeometry, {
            [placement.address]: saved
        });
        root.pendingPlacement = {
            address: placement.address,
            saved: saved
        };
        root.hidePicker();
        return accepted;
    }

    function restoreWindow(address = "") {
        if (bridge.busy || root.pendingRestore) {
            root.errorMessage = "Another placement is still in progress.";
            return false;
        }
        const wanted = Validation.normalizeAddress(String(address || root.pendingAddress || root.activeWindowSnapshot()?.address || ""));
        const saved = root.savedGeometry?.[wanted];
        if (!saved || !root.windowStillExists(wanted))
            return false;
        if (saved.monitor && !root.monitorStillExists(saved.monitor)) {
            root.errorMessage = "The monitor from the saved geometry is no longer connected.";
            return false;
        }
        const current = root.currentWindowForAddress(wanted);
        if (!current || Validation.isUnsupportedWindow(current))
            return false;
        const restoreMonitorName = String(saved.monitor || root.monitorForWindow(current) || root.targetMonitorName || "");
        const liveRestoreScreen = (Quickshell.screens || []).find(screen => String(screen?.name || "") === restoreMonitorName) || null;
        const restoreMonitor = root.monitorForScreen(liveRestoreScreen || {
            name: restoreMonitorName
        });
        const normalizedRestoreMonitor = Geometry.normalizeMonitor(restoreMonitor);
        const restoreScreen = liveRestoreScreen || {
            name: restoreMonitorName,
            width: normalizedRestoreMonitor.width,
            height: normalizedRestoreMonitor.height
        };
        const restoreArea = Geometry.globalWorkAreaForScreen(restoreMonitor, restoreScreen, root.config.padding);
        const restoreRect = Geometry.clampWindowRect(saved, restoreArea);
        // Placement guarantees the target is floating. Do not invoke the Lua
        // float dispatcher again here: on the target Hyprland build it is a
        // toggle even when an action field is supplied.
        if (!bridge.place(wanted, restoreRect, {
            mode: "none"
        }))
            return false;
        root.pendingRestore = {
            address: wanted,
            saved: saved
        };
        return true;
    }

    function setHoveredZone(index) {
        root.hoveredZone = Number.isInteger(Number(index)) ? Number(index) : -1;
    }

    function cycleZone(direction = 1) {
        if (!root.pickerOpen && !root.beginPicker())
            return false;
        const screen = root.targetScreen();
        if (!screen)
            return false;
        const count = root.zoneRectsForScreen(screen).length;
        if (count < 1)
            return false;
        const step = Number(direction) < 0 ? -1 : 1;
        root.hoveredZone = (root.hoveredZone < 0 ? (step > 0 ? 0 : count - 1) : (root.hoveredZone + step + count) % count);
        return true;
    }

    Loader {
        // Keep IPC and global shortcuts in the same main-shell-only component as
        // the overlay. Settings, extension search, and update helper processes
        // load services too but must not register these global resources.
        active: root.isMainShell
        sourceComponent: Component {
            Item {
                IpcHandler {
                    target: "vynxZones"

                    function toggle() {
                        root.togglePicker();
                    }
                    function open() {
                        root.beginPicker();
                    }
                    function close() {
                        root.hidePicker();
                    }
                    function dragStart() {
                        dragController.start();
                    }
                    function dragEnd() {
                        dragController.end();
                    }
                    function dragCancel() {
                        root.cancelDrag("ipc-cancelled");
                    }
                    function place(index: int) {
                        if (index > 0 && !root.placeZone(index - 1))
                            console.warn("Vynx Zones: placement rejected:", root.errorMessage);
                    }
                    function nextLayout() {
                        root.cycleLayout(1);
                    }
                    function previousLayout() {
                        root.cycleLayout(-1);
                    }
                    function restore() {
                        root.restoreWindow();
                    }
                    function nextZone() {
                        root.cycleZone(1);
                    }
                    function previousZone() {
                        root.cycleZone(-1);
                    }
                }

                GlobalShortcut {
                    name: "vynxZonesToggle"
                    description: "Toggle the Vynx Zones picker"
                    onPressed: root.togglePicker()
                }
                GlobalShortcut {
                    name: "vynxZonesOpen"
                    description: "Open the Vynx Zones picker"
                    onPressed: root.beginPicker()
                }
                GlobalShortcut {
                    name: "vynxZonesNextLayout"
                    description: "Switch to the next Vynx Zones layout"
                    onPressed: root.cycleLayout(1)
                }
                GlobalShortcut {
                    name: "vynxZonesPreviousLayout"
                    description: "Switch to the previous Vynx Zones layout"
                    onPressed: root.cycleLayout(-1)
                }
                GlobalShortcut {
                    name: "vynxZonesRestore"
                    description: "Restore the focused window's previous geometry"
                    onPressed: root.restoreWindow()
                }
                GlobalShortcut {
                    name: "vynxZonesNextZone"
                    description: "Preview the next Vynx Zones zone"
                    onPressed: root.cycleZone(1)
                }
                GlobalShortcut {
                    name: "vynxZonesPreviousZone"
                    description: "Preview the previous Vynx Zones zone"
                    onPressed: root.cycleZone(-1)
                }
                GlobalShortcut {
                    name: "vynxZonesDragStart"
                    description: "Start native Super-drag zone preview"
                    onPressed: dragController.start()
                }
                GlobalShortcut {
                    name: "vynxZonesShiftCommit"
                    description: "Commit Vynx Zones when Shift is released"
                    onReleased: dragController.end()
                }
                GlobalShortcut {
                    name: "vynxZonesDragCancel"
                    description: "Cancel native Super-drag zone preview with Escape"
                    onPressed: root.cancelDrag("escape")
                }
            }
        }
    }

    Loader {
        active: root.isMainShell
        sourceComponent: Component {
            Item {
                id: overlayHost
                property var manager: root

                Variants {
                    model: Quickshell.screens
                    delegate: Loader {
                        id: overlayLoader
                        required property var modelData
                        property var zoneManager: overlayHost.manager
                        active: zoneManager.ready && (zoneManager.pickerOpen || zoneManager.dragActive) && String(modelData?.name || "") === zoneManager.targetMonitorName
                        sourceComponent: ZoneOverlay {
                            screen: overlayLoader.modelData
                            manager: overlayLoader.zoneManager
                            inputTransparent: overlayLoader.zoneManager.dragActive
                        }
                    }
                }
            }
        }
    }
}
