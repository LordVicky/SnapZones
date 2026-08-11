import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers.mjs";

const geometry = await loadQmlJs("src/js/geometry.js", [
    "clamp", "normalizeRect", "normalizeMonitor", "monitorWorkArea", "screenWorkArea",
    "globalWorkAreaForScreen", "zoneToPixels", "zonesToPixels", "zoneAtPoint", "clampWindowRect", "rectEquals",
]);

test("normalizes monitor geometry and reserved work area", () => {
    const monitor = geometry.normalizeMonitor({
        name: "DP-1", x: -1920, y: 20, width: 1920, height: 1080,
        scale: 1.25, reserved: [8, 32, 4, 12],
    });
    assert.deepEqual(monitor, {
        name: "DP-1", x: -1920, y: 20, width: 1920, height: 1080,
        scale: 1.25, transform: 0, reserved: [8, 32, 4, 12],
    });
    assert.deepEqual(geometry.monitorWorkArea(monitor, 10), {
        x: -1902, y: 62, width: 1504, height: 800,
    });
});

test("converts normalized zones to pixel rectangles with a gap", () => {
    const halves = geometry.zonesToPixels([
        { x: 0, y: 0, width: 0.5, height: 1 },
        { x: 0.5, y: 0, width: 0.5, height: 1 },
    ], { x: 0, y: 0, width: 1000, height: 800 }, 20);
    assert.deepEqual(halves, [
        { x: 10, y: 10, width: 480, height: 780 },
        { x: 510, y: 10, width: 480, height: 780 },
    ]);
    assert.equal(geometry.zoneAtPoint(halves, { x: 550, y: 200 }), 1);
    assert.equal(geometry.zoneAtPoint(halves, { x: 500, y: 200 }), -1);
});

test("clamps placement rectangles to the monitor work area", () => {
    assert.deepEqual(geometry.clampWindowRect({ x: -50, y: 900, width: 2000, height: 500 }, {
        x: 10, y: 20, width: 1000, height: 700,
    }), { x: 10, y: 220, width: 1000, height: 500 });
    assert.equal(geometry.rectEquals({ x: 0, y: 0, width: 1, height: 1 }, { x: 0, y: 0, width: 1, height: 1 }), true);
    assert.equal(geometry.clamp(7, 0, 5), 5);
});

test("keeps scaled logical overlay geometry separate from global placement geometry", () => {
    const monitor = {
        name: "DP-1", x: -1920, y: -100, width: 3840, height: 2160,
        scale: 2, reserved: [16, 80, 8, 20], transform: 0,
    };
    const screen = { name: "DP-1", width: 1920, height: 1080 };
    assert.deepEqual(geometry.screenWorkArea(screen, monitor, 10), {
        x: 26, y: 90, width: 1876, height: 960,
    });
    assert.deepEqual(geometry.globalWorkAreaForScreen(monitor, screen, 10), {
        x: -1894, y: -10, width: 1876, height: 960,
    });
    const local = geometry.zoneToPixels({ x: 0, y: 0, width: 0.5, height: 1 }, geometry.screenWorkArea(screen, monitor), 0);
    const global = geometry.zoneToPixels({ x: 0, y: 0, width: 0.5, height: 1 }, geometry.globalWorkAreaForScreen(monitor, screen), 0);
    assert.equal(local.x, 16);
    assert.equal(local.width, 948);
    assert.equal(global.x, -1904);
    assert.equal(global.width, 948);
});

test("preserves the rotated monitor width/height contract", () => {
    // Hyprland monitor JSON reports the configured mode dimensions; a 90°
    // transform changes the dimensions in the compositor's layout space.
    const monitor = { name: "DP-2", x: 100, y: 50, width: 1920, height: 1080, transform: 1, reserved: [0, 24, 0, 0] };
    const screen = { name: "DP-2", width: 1080, height: 1920 };
    assert.deepEqual(geometry.normalizeMonitor(monitor), {
        name: "DP-2", x: 100, y: 50, width: 1080, height: 1920,
        scale: 1, transform: 1, reserved: [0, 24, 0, 0],
    });
    const area = geometry.screenWorkArea(screen, monitor, 0);
    assert.deepEqual(area, { x: 0, y: 24, width: 1080, height: 1896 });
    assert.deepEqual(geometry.globalWorkAreaForScreen(monitor, screen, 0), {
        x: 100, y: 74, width: 1080, height: 1896,
    });
    const rect = geometry.zoneToPixels({ x: 0, y: 0, width: 1, height: 1 }, area, 0);
    assert.deepEqual(rect, { x: 0, y: 24, width: 1080, height: 1896 });
});
