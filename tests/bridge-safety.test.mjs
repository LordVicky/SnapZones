import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";

const bridge = await fs.readFile(new URL("../src/services/HyprlandBridge.qml", import.meta.url), "utf8");
const manager = await fs.readFile(new URL("../src/services/ZoneManager.qml", import.meta.url), "utf8");
const overlay = await fs.readFile(new URL("../src/overlay/ZoneOverlay.qml", import.meta.url), "utf8");
const dragController = await fs.readFile(new URL("../src/services/DragController.qml", import.meta.url), "utf8");
const cursorSampler = await fs.readFile(new URL("../src/services/CursorSampler.qml", import.meta.url), "utf8");
const luaIntegration = await fs.readFile(new URL("../docs/hyprland.lua", import.meta.url), "utf8");
const samplerPython = await fs.readFile(new URL("../src/helpers/cursor_sampler.py", import.meta.url), "utf8");

test("placement is an argument-safe atomic Hyprland batch", () => {
    assert.match(bridge, /\[\s*"hyprctl",\s*"--batch",/);
    assert.match(bridge, /dispatch setfloating address:/);
    assert.match(bridge, /dispatch settiled address:/);
    assert.match(bridge, /Validation\.isSafeAddress/);
    assert.doesNotMatch(bridge, /togglefloating/);
    assert.doesNotMatch(bridge, /bash\s+-c/);
    assert.match(bridge, /property Process dispatchProcess:\s*Process\s*\{/);
    assert.match(bridge, /commandFinished\(string operation, bool success, int exitCode, string errorText\)/);
});

test("placement branches to the installed Hyprland Lua dispatcher API", () => {
    assert.match(bridge, /readonly property bool usingLua:\s*Hyprland\.usingLua/);
    assert.match(bridge, /function _luaBatch\(commands\)/);
    assert.match(bridge, /\[\s*"hyprctl",\s*"eval",\s*commands\.join/);
    assert.match(bridge, /hl\.dispatch\(hl\.dsp\.window\.float\(\{ action = \\"set/);
    assert.match(bridge, /hl\.dispatch\(hl\.dsp\.window\.move\(\{ x =/);
    assert.match(bridge, /hl\.dispatch\(hl\.dsp\.window\.resize\(\{ x =/);
    assert.match(bridge, /window\.move\(\{ x = [^\n]+\\"exact\\"/);
    assert.match(bridge, /window\.resize\(\{ x = [^\n]+\\"exact\\"/);
    assert.ok(bridge.indexOf("window.resize") < bridge.indexOf("window.move"));
    assert.match(bridge, /function retile\(address\)/);
    assert.match(bridge, /action = \\"unset/);
    assert.ok(bridge.indexOf("dispatch settiled address:") > bridge.indexOf("dispatch movewindowpixel exact"));
});

test("manager guards stale placement and exposes one-based IPC zone commands", () => {
    assert.match(manager, /ToplevelManager\.activeToplevel/);
    assert.match(manager, /ToplevelManager\.toplevels\?\.values/);
    assert.doesNotMatch(manager, /Array\.isArray\(values\)\s*\?\s*values\s*:\s*\[\]/);
    assert.doesNotMatch(manager, /Hyprland\.activeToplevel/);
    assert.doesNotMatch(manager, /Hyprland\.toplevels/);
    assert.match(manager, /Object\.assign\(\{\}, raw, json, \{/);
    assert.match(manager, /if \(json\)\s*return json;/);
    assert.match(manager, /floatingWasReported \? clientState\.floating : true/);
    assert.match(manager, /function revalidatePlacement\(zoneIndex, fromDrag = false\)/);
    assert.match(manager, /windowStillExists\(address\)/);
    assert.match(manager, /screens\.some\(screen => String\(screen\?\.name/);
    assert.match(manager, /native !== null && native\.length > 0/);
    assert.match(manager, /targetMonitorName\)/);
    assert.match(manager, /function place\(index:\s*int\)/);
    assert.match(manager, /root\.placeZone\(index\s*-\s*1\)/);
    assert.match(manager, /function nextZone\(\)/);
    assert.match(manager, /function previousZone\(\)/);
    assert.match(manager, /property var zoneManager: overlayHost\.manager/);
    assert.match(manager, /manager: overlayLoader\.zoneManager/);
    assert.match(manager, /delete remaining\[pending\.address\]/);
    assert.match(manager, /pendingRestore/);
    assert.match(manager, /pendingPlacement/);
    assert.match(manager, /toggle even when an action field is supplied/);
    assert.match(manager, /mode:\s*"none"/);
    assert.doesNotMatch(manager, /restoreAsTiled/);
    assert.match(manager, /operation !== "place" && operation !== "retile"/);
    assert.match(manager, /if \(!success && root\.savedGeometry\?\.\[placement\.address\]/);
    assert.match(manager, /if \(success && root\.savedGeometry\?\.\[pending\.address\]/);
    assert.match(manager, /if \(bridge\.busy \|\| root\.pendingRestore\)/);
    assert.match(manager, /Geometry\.clampWindowRect\(saved, restoreArea\)/);
    assert.match(manager, /window\.floating !== true && !root\.config\.floatOnPlacement/);
    assert.match(manager, /function closePickerIfTargetGone\(\)/);
    assert.match(manager, /function monitorTopologyChanged\(\)/);
    assert.match(manager, /root\.closePickerIfTargetGone\(\)/);
    assert.match(manager, /Qt\.callLater\(root\.closePickerIfTargetGone\)/);
});

test("named layout changes stay per-monitor instead of changing the global fallback", () => {
    assert.match(
        manager,
        /if \(Validation\.isSafeMonitorName\(name\)\) \{[\s\S]*?setExtensionConfig\(root\.extensionId, "monitorLayouts", assignments\);[\s\S]*?return;\s*\}/,
    );
});

test("number keys place directly while arrows remain preview-only", () => {
    assert.match(overlay, /if \(index < root\.zoneRects\.length\)\s*root\.manager\.placeZone\(index\);/);
    assert.match(overlay, /root\.manager\.setHoveredZone\(index\)/);
});

test("native drag path is input-transparent and exposes press/release IPC", () => {
    assert.match(manager, /DragController\s*\{/);
    assert.match(manager, /function beginDragCapture\(\)/);
    assert.match(manager, /function cancelDragCapture\(\)/);
    assert.match(manager, /function globalZoneRectsForScreen\(screen\)/);
    assert.match(manager, /function monitorForGlobalPoint\(point\)/);
    assert.match(manager, /function dragStart\(\)/);
    assert.match(manager, /function dragEnd\(\)/);
    assert.match(manager, /function dragCancel\(\)/);
    assert.match(manager, /function cancelDrag\(reason = "cancelled"\)/);
    assert.match(manager, /function placeZone\(index, fromDrag = false\)/);
    assert.match(manager, /if \(fromDrag === true && !root\.dragActive\)/);
    assert.match(manager, /root\.revalidatePlacement\(zoneIndex, fromDrag === true\)/);
    assert.match(manager, /if \(!fromDrag && currentMonitor && currentMonitor !== root\.targetMonitorName\)/);
    assert.match(manager, /const old = fromDrag && root\.pendingWindow \? root\.pendingWindow : placement\.window/);
    assert.match(manager, /monitor: fromDrag \? \(root\.monitorForWindow\(old\) \|\| root\.targetMonitorName\)/);
    assert.match(overlay, /property bool inputTransparent/);
    assert.match(overlay, /mask: root\.inputTransparent \? emptyInputRegion : null/);
    assert.match(overlay, /WlrKeyboardFocus\.None/);
    assert.match(overlay, /focus: !root\.inputTransparent/);
    assert.match(overlay, /root\.manager\.cancelDrag\("escape"\)/);
    assert.match(dragController, /DragState\.reduceDrag/);
    assert.match(dragController, /root\.manager\.placeZone\(result\.effect\.zone, true\)/);
    assert.match(dragController, /property int cursorRevision/);
    assert.match(dragController, /property bool settling/);
    assert.match(dragController, /property bool committed/);
    assert.match(dragController, /root\.committed = true/);
    assert.match(dragController, /String\(reason\) === "modifier-released" && !force/);
    assert.match(dragController, /cursorRevision: root\.cursorRevision/);
    assert.match(dragController, /startedAt: root\.now\(\)/);
    assert.match(dragController, /elapsed >= root\.maxSettleMs/);
    assert.match(dragController, /cursorRevision <= Number\(pending\.cursorRevision\)/);
    assert.match(dragController, /const point = root\.cursorAvailable \? root\.cursor : root\.dragState\.point/);
    assert.match(dragController, /onCursorSample: .*sampleToken/);
    assert.match(dragController, /watchdogTimer/);
    assert.match(dragController, /root\.cancel\("cursor-timeout", true\)/);
    assert.match(dragController, /root\.cancel\("stale-release", true\)/);
    assert.match(dragController, /readonly property int activeWatchdogMs: 5000/);
    assert.match(dragController, /activityWatchdogTimer\.restart\(\)/);
    assert.match(dragController, /activityWatchdogTimer/);
    assert.match(dragController, /readonly property int hardLifetimeMs: 30000/);
    assert.match(dragController, /hardLifetimeTimer\.start\(\)/);
    assert.match(dragController, /hardLifetimeTimer/);
    assert.match(dragController, /root\.cancel\("lifetime-timeout", true\)/);
    assert.ok((dragController.match(/hardLifetimeTimer\.stop\(\)/g) || []).length >= 3);
    const cursorHandlerStart = dragController.indexOf("function acceptCursor");
    const cursorHandlerEnd = dragController.indexOf("function boundedDropDelay");
    assert.ok(cursorHandlerStart >= 0 && cursorHandlerEnd > cursorHandlerStart);
    assert.doesNotMatch(dragController.slice(cursorHandlerStart, cursorHandlerEnd), /hardLifetimeTimer\.(?:start|restart)\(\)/);
    assert.match(dragController, /sampleToken/);
    assert.match(cursorSampler, /cursor_sampler\.py/);
    assert.match(cursorSampler, /SplitParser/);
    assert.match(cursorSampler, /property int token/);
    assert.match(cursorSampler, /"--token"/);
    assert.match(cursorSampler, /restartCycle/);
    assert.match(cursorSampler, /onRunningChanged/);
    assert.match(cursorSampler, /scheduleRestart/);
    assert.match(cursorSampler, /maxRestartAttempts/);
    assert.match(cursorSampler, /restartAttempts >= root\.maxRestartAttempts/);
    assert.match(cursorSampler, /retry limit reached/);
    assert.match(cursorSampler, /sampleSeen/);
    assert.match(cursorSampler, /cursor sampler failed to start or stopped while requested/);
    assert.match(cursorSampler, /cursor sampler exited/);
    assert.doesNotMatch(cursorSampler, /process\.running\s*=\s*true/);
    assert.match(manager, /name: "vynxZonesDragEnd"[\s\S]*?onPressed: dragController\.end\(\)/);
    assert.match(manager, /name: "vynxZonesDragCancel"[\s\S]*?onPressed: root\.cancelDrag\("escape"\)/);
    assert.match(manager, /name: "vynxZonesDragModifierRelease"[\s\S]*?onPressed: root\.cancelDrag\("modifier-released"\)/);
});

test("Lua integration preserves native movement and has coherent drop/cancel releases", () => {
    assert.match(luaIntegration, /hl\.dsp\.window\.drag\(\)/);
    assert.match(luaIntegration, /quickshell:vynxZonesDragStart/);
    assert.match(luaIntegration, /quickshell:vynxZonesDragEnd/);
    assert.match(luaIntegration, /SUPER_L/);
    assert.match(luaIntegration, /SUPER_R/);
    assert.match(luaIntegration, /vynxZonesDragCancel/);
    assert.match(luaIntegration, /vynxZonesDragModifierRelease/);
    assert.match(luaIntegration, /release\s*=\s*true/);
    assert.match(luaIntegration, /non_consuming\s*=\s*true/);
    assert.match(luaIntegration, /hl\.bind\("Escape"[\s\S]*?ignore_mods\s*=\s*true/);
    assert.match(luaIntegration, /Releasing either Super key cancels/);
});

test("cursor sampler stays unprivileged and shell-free", () => {
    assert.match(samplerPython, /j\/cursorpos/);
    assert.match(samplerPython, /socket\.AF_UNIX/);
    assert.doesNotMatch(samplerPython, /\/dev\/input/);
    assert.doesNotMatch(samplerPython, /subprocess\./);
    assert.doesNotMatch(samplerPython, /os\.system/);
    assert.doesNotMatch(samplerPython, /shell\s*=\s*True/);
    assert.match(samplerPython, /"token": self\.token/);
});
