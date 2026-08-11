import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";

const bridge = await fs.readFile(new URL("../src/services/HyprlandBridge.qml", import.meta.url), "utf8");
const manager = await fs.readFile(new URL("../src/services/ZoneManager.qml", import.meta.url), "utf8");
const overlay = await fs.readFile(new URL("../src/overlay/ZoneOverlay.qml", import.meta.url), "utf8");

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
    assert.match(manager, /function revalidatePlacement\(zoneIndex\)/);
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
