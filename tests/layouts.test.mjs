import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { loadQmlJs } from "./helpers.mjs";

const layouts = await loadQmlJs("src/js/layouts.js", ["layouts", "listLayouts", "getLayout", "getLayoutIndex", "nextLayoutId"]);

test("ships all Phase 1 built-in layouts", () => {
    assert.deepEqual(layouts.layouts.map(layout => layout.id), ["halves", "thirds", "main-side", "quadrants", "ultrawide", "fullscreen"]);
    for (const layout of layouts.layouts) {
        assert.ok(layout.zones.length >= 1);
        for (const zone of layout.zones) {
            assert.ok(zone.x >= 0 && zone.y >= 0 && zone.x + zone.width <= 1 && zone.y + zone.height <= 1);
        }
    }
});

test("returns defensive layout copies and wraps cycling", () => {
    const copy = layouts.listLayouts();
    copy[0].zones[0].x = 0.4;
    assert.equal(layouts.getLayout("halves").zones[0].x, 0);
    assert.equal(layouts.getLayout("missing").id, "halves");
    assert.equal(layouts.nextLayoutId("fullscreen"), "halves");
    assert.equal(layouts.nextLayoutId("halves", -1), "fullscreen");
    assert.equal(layouts.getLayoutIndex("quadrants"), 3);
});

test("avoids object spread unsupported by the target QML JavaScript parser", () => {
    const source = fs.readFileSync(new URL("../src/js/layouts.js", import.meta.url), "utf8");
    assert.doesNotMatch(source, /\{\s*\.\.\./);
});
