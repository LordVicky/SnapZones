import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";

const manifest = JSON.parse(await fs.readFile(new URL("../extension.json", import.meta.url), "utf8"));

test("manifest declares the extension and Phase 1 contribution points", () => {
    assert.equal(manifest.extensionId, "vynx-zones");
    assert.equal(manifest.version, "0.1.2");
    assert.equal(manifest.contributes.services[0].id, "zoneManager");
    assert.equal(manifest.contributes.cheatsheet[0].component, "src/cheatsheet/ZoneCheatsheet.qml");
    assert.equal(manifest.contributes.sidebarLeftPages, undefined);
    assert.deepEqual(manifest.configSchema.layout.options.map(option => option.value), ["halves", "thirds", "main-side", "quadrants", "ultrawide", "fullscreen"]);
});
