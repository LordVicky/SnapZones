import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers.mjs";

const drag = await loadQmlJs("src/js/drag.js", [
    "createDragState",
    "reduceDrag",
    "isDragActive",
    "zoneAtPoint",
]);

test("starts a drag without losing the captured target", () => {
    const initial = drag.createDragState();
    const result = drag.reduceDrag(initial, {
        type: "start",
        address: "0xabc123",
        monitor: "DP-1",
        point: { x: 40, y: 50 },
        now: 100,
    });

    assert.equal(result.effect.type, "started");
    assert.equal(result.state.phase, "active");
    assert.equal(result.state.address, "0xabc123");
    assert.equal(result.state.monitor, "DP-1");
    assert.deepEqual(result.state.point, { x: 40, y: 50 });
    assert.equal(drag.isDragActive(result.state), true);
});

test("updates hover and drops exactly once", () => {
    let state = drag.createDragState();
    state = drag.reduceDrag(state, {
        type: "start",
        address: "0xabc123",
        monitor: "DP-1",
        now: 1,
    }).state;
    const moved = drag.reduceDrag(state, {
        type: "move",
        point: { x: 900, y: 80 },
        zone: 1,
        now: 20,
    });
    assert.equal(moved.effect.type, "hover");
    assert.equal(moved.state.zone, 1);
    const dropped = drag.reduceDrag(moved.state, {
        type: "end",
        point: { x: 900, y: 80 },
        zone: 1,
        now: 40,
    });
    assert.equal(dropped.effect.type, "drop");
    assert.equal(dropped.effect.address, "0xabc123");
    assert.equal(dropped.effect.zone, 1);
    assert.equal(dropped.state.phase, "idle");
    assert.equal(drag.reduceDrag(dropped.state, { type: "end", zone: 1 }).effect.type, "ignored");
});

test("stale token callbacks are ignored without changing the active drag", () => {
    let state = drag.createDragState();
    state = drag.reduceDrag(state, {
        type: "start",
        address: "0xabc123",
        monitor: "DP-1",
        now: 1,
    }).state;

    const staleMove = drag.reduceDrag(state, {
        type: "move",
        token: state.token - 1,
        point: { x: 30, y: 40 },
        zone: 1,
        now: 11,
    });
    assert.equal(staleMove.effect.type, "ignored");
    assert.equal(staleMove.effect.reason, "stale-token");
    assert.deepEqual(staleMove.state, state);

    const staleEnd = drag.reduceDrag(state, {
        type: "end",
        token: state.token - 1,
        point: { x: 30, y: 40 },
        zone: 1,
        now: 11,
    });
    assert.equal(staleEnd.effect.type, "ignored");
    assert.equal(staleEnd.effect.reason, "stale-token");
    assert.deepEqual(staleEnd.state, state);
});

test("cancels stale or invalid drags without emitting a placement", () => {
    const invalid = drag.reduceDrag(drag.createDragState(), {
        type: "start",
        address: "not-an-address",
        monitor: "DP-1",
    });
    assert.equal(invalid.effect.type, "ignored");
    assert.equal(invalid.state.phase, "idle");

    let state = drag.createDragState();
    state = drag.reduceDrag(state, {
        type: "start",
        address: "0xabc123",
        monitor: "DP-1",
    }).state;
    const cancelled = drag.reduceDrag(state, { type: "cancel", reason: "modifier-released" });
    assert.equal(cancelled.effect.type, "cancelled");
    assert.equal(cancelled.effect.reason, "modifier-released");
    assert.equal(cancelled.state.phase, "idle");
});

test("finds a zone only when the cursor is inside a real rectangle", () => {
    const zones = [
        { x: 0, y: 0, width: 400, height: 800 },
        { x: 420, y: 0, width: 400, height: 800 },
    ];
    assert.equal(drag.zoneAtPoint(zones, { x: 40, y: 20 }), 0);
    assert.equal(drag.zoneAtPoint(zones, { x: 700, y: 20 }), 1);
    assert.equal(drag.zoneAtPoint(zones, { x: 410, y: 20 }), -1);
    assert.equal(drag.zoneAtPoint(zones, { x: 900, y: 20 }), -1);
});
