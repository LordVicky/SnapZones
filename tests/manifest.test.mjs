import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";

const manifest = JSON.parse(await fs.readFile(new URL("../extension.json", import.meta.url), "utf8"));

test("manifest declares the extension and Phase 2 contribution points", () => {
    assert.equal(manifest.extensionId, "snapzones");
    assert.equal(manifest.version, "0.2.0");
    assert.equal(manifest.contributes.services[0].id, "zoneManager");
    assert.equal(manifest.contributes.cheatsheet[0].component, "src/cheatsheet/ZoneCheatsheet.qml");
    assert.equal(manifest.contributes.sidebarLeftPages, undefined);
    assert.deepEqual(manifest.configSchema.layout.options.map(option => option.value), ["halves", "thirds", "main-side", "quadrants", "ultrawide", "fullscreen"]);
    assert.equal(manifest.configDefaults.dragToZone, true);
    assert.equal(manifest.configDefaults.enabled, undefined);
    assert.equal(manifest.configSchema.enabled, undefined);
    assert.equal(manifest.configSchema.dragToZone.type, "bool");
    assert.equal(manifest.configSchema.dragDropDelayMs, undefined);
    assert.equal(manifest.configSchema.cursorSampleIntervalMs.max, 1000);
});
