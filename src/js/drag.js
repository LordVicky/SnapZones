.pragma library

// Pure drag state transitions. The compositor owns the actual pointer drag;
// this reducer only tracks the target, latest cursor sample, and pending zone.
// Keeping it side-effect free makes timing, cancellation, and stale-release
// handling testable without a Quickshell runtime.

const ADDRESS = /^(?:0[xX])?[0-9a-fA-F]{1,128}$/;

function createDragState() {
    return {
        phase: "idle",
        token: 0,
        address: "",
        monitor: "",
        point: null,
        zone: -1,
        startedAt: 0,
        updatedAt: 0,
    };
}

function copyPoint(point) {
    if (!point || !Number.isFinite(Number(point.x)) || !Number.isFinite(Number(point.y)))
        return null;
    return {
        x: Number(point.x),
        y: Number(point.y),
    };
}

function safeAddress(address) {
    return typeof address === "string" && ADDRESS.test(address);
}

function safeMonitor(monitor) {
    return typeof monitor === "string" && monitor.length > 0 && monitor.length <= 256 && !/[\u0000\n\r]/.test(monitor);
}

function normalizedAddress(address) {
    if (!safeAddress(address))
        return "";
    return /^0x/i.test(address) ? "0x" + address.slice(2) : "0x" + address;
}

function normalizedNow(value, fallback) {
    const number = Number(value);
    return Number.isFinite(number) && number >= 0 ? number : fallback;
}

function ignored(state, reason) {
    return {
        state: state,
        effect: {
            type: "ignored",
            reason: String(reason || "invalid-transition"),
        },
    };
}

function resetState(state) {
    return {
        phase: "idle",
        token: Number(state?.token) || 0,
        address: "",
        monitor: "",
        point: null,
        zone: -1,
        startedAt: 0,
        updatedAt: 0,
    };
}

function eventMatchesToken(state, event) {
    if (event?.token === undefined || event?.token === null)
        return true;
    return Number.isSafeInteger(Number(event.token)) && Number(event.token) === Number(state.token);
}

function isDragActive(state) {
    return state?.phase === "active" && safeAddress(String(state?.address || ""));
}

function reduceDrag(inputState, event = ({})) {
    const state = inputState && typeof inputState === "object" ? inputState : createDragState();
    const type = String(event?.type || "");

    if (type === "start") {
        if (isDragActive(state))
            return ignored(state, "already-active");
        const address = normalizedAddress(String(event?.address || ""));
        const monitor = String(event?.monitor || "");
        if (!address || !safeMonitor(monitor))
            return ignored(state, "invalid-target");
        const now = normalizedNow(event?.now, 0);
        const point = copyPoint(event?.point);
        const next = {
            phase: "active",
            token: (Number(state?.token) || 0) + 1,
            address: address,
            monitor: monitor,
            point: point,
            zone: -1,
            startedAt: now,
            updatedAt: now,
        };
        return {
            state: next,
            effect: {
                type: "started",
                token: next.token,
                address: address,
                monitor: monitor,
            },
        };
    }

    if (!isDragActive(state))
        return ignored(state, "not-active");

    if (!eventMatchesToken(state, event))
        return ignored(state, "stale-token");

    if (type === "move") {
        const point = copyPoint(event?.point);
        if (!point)
            return ignored(state, "invalid-point");
        const zoneNumber = Number(event?.zone);
        const zone = Number.isInteger(zoneNumber) && zoneNumber >= 0 ? zoneNumber : -1;
        const next = Object.assign({}, state, {
            point: point,
            zone: zone,
            updatedAt: normalizedNow(event?.now, state.updatedAt),
        });
        return {
            state: next,
            effect: {
                type: "hover",
                token: next.token,
                address: next.address,
                monitor: next.monitor,
                point: point,
                zone: zone,
            },
        };
    }

    if (type === "end") {
        const point = copyPoint(event?.point) || state.point;
        const zoneNumber = Number(event?.zone ?? state.zone);
        const zone = Number.isInteger(zoneNumber) && zoneNumber >= 0 ? zoneNumber : -1;
        const token = state.token;
        const address = state.address;
        const monitor = state.monitor;
        const next = resetState(state);
        if (zone < 0)
            return {
                state: next,
                effect: {
                    type: "cancelled",
                    token: token,
                    address: address,
                    reason: "no-zone",
                },
            };
        return {
            state: next,
            effect: {
                type: "drop",
                token: token,
                address: address,
                monitor: monitor,
                point: point,
                zone: zone,
            },
        };
    }

    if (type === "cancel") {
        const next = resetState(state);
        return {
            state: next,
            effect: {
                type: "cancelled",
                token: state.token,
                address: state.address,
                reason: String(event?.reason || "cancelled"),
            },
        };
    }

    return ignored(state, "unknown-event");
}

function zoneAtPoint(rects, point) {
    if (!Array.isArray(rects) || !point)
        return -1;
    const x = Number(point.x);
    const y = Number(point.y);
    if (!Number.isFinite(x) || !Number.isFinite(y))
        return -1;
    for (let index = 0; index < rects.length; index += 1) {
        const rect = rects[index];
        const left = Number(rect?.x);
        const top = Number(rect?.y);
        const width = Number(rect?.width);
        const height = Number(rect?.height);
        if (!Number.isFinite(left) || !Number.isFinite(top) || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0)
            continue;
        if (x >= left && x < left + width && y >= top && y < top + height)
            return index;
    }
    return -1;
}
