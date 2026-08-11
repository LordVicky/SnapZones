import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers.mjs";

const validation = await loadQmlJs("src/js/validation.js", [
    "isSafeLayoutId", "isSafeAddress", "normalizeAddress", "isSafeMonitorName",
    "validateLayout", "sanitizeLayout", "sanitizeConfig", "parseJsonObject", "isUnsupportedWindow",
]);

test("validates command and persistence identifiers", () => {
    assert.equal(validation.isSafeLayoutId("main-side"), true);
    assert.equal(validation.isSafeLayoutId("../escape"), false);
    assert.equal(validation.isSafeAddress("0xABC123"), true);
    assert.equal(validation.normalizeAddress("0XABC123"), "0xABC123");
    assert.equal(validation.isSafeAddress("0xdead;notify-send pwned"), false);
    assert.equal(validation.isSafeMonitorName("DP-1"), true);
    assert.equal(validation.isSafeMonitorName("DP-1\nmalicious"), false);
});

test("sanitizes config values and rejects malformed layouts", () => {
    const config = validation.sanitizeConfig({
        layout: "quadrants", gap: 999, padding: -4,
        overlayOpacity: 0.1, showLabels: false,
        monitorLayouts: { "DP-1": "thirds", "bad\nname": "halves", "HDMI-1": "../../x" },
    });
    assert.deepEqual(config, {
        layout: "quadrants", gap: 80, padding: 0,
        overlayOpacity: 0.2, showLabels: false,
        floatOnPlacement: true,
        cursorSampleIntervalMs: 16,
        monitorLayouts: { "DP-1": "thirds" },
    });
    assert.equal(validation.validateLayout({ id: "safe", name: "Safe", zones: [{ x: 0, y: 0, width: 0.5, height: 1 }] }), true);
    assert.equal(validation.validateLayout({ id: "unsafe id", name: "No", zones: [] }), false);
    assert.equal(validation.sanitizeLayout({ id: "safe", name: "Safe", zones: [{ x: 0, y: 0, width: 0.5, height: 1 }] }).zones[0].width, 0.5);
});

test("bounds native drag sampling", () => {
    const config = validation.sanitizeConfig({
        cursorSampleIntervalMs: 1,
    });
    assert.equal(config.cursorSampleIntervalMs, 8);
});

test("handles malformed JSON and unsupported windows safely", () => {
    assert.deepEqual(validation.parseJsonObject('{"ok":true}'), { ok: true });
    assert.equal(validation.parseJsonObject("not json", null), null);
    assert.equal(validation.isUnsupportedWindow({ address: "0x1", fullscreen: true }), true);
    assert.equal(validation.isUnsupportedWindow({ address: "0x1", fullscreen: 1 }), true);
    assert.equal(validation.isUnsupportedWindow({ address: "0x1", fullscreenState: 2 }), true);
    assert.equal(validation.isUnsupportedWindow({ address: "0x1", pinned: true }), true);
    assert.equal(validation.isUnsupportedWindow({ address: "0x1", workspace: "special:scratchpad" }), true);
    assert.equal(validation.isUnsupportedWindow({ address: "0x1", workspace: { name: "special:scratchpad" } }), true);
    assert.equal(validation.isUnsupportedWindow({ address: "0x1", mapped: true, floating: true }), false);
});
