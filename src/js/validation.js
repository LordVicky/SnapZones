.pragma library

function clamp(value, minimum, maximum) {
    const number = Number(value);
    if (!Number.isFinite(number)) return minimum;
    return Math.min(Math.max(number, minimum), maximum);
}

function normalizeRect(rect) {
    const x = clamp(Number(rect?.x), 0, 1);
    const y = clamp(Number(rect?.y), 0, 1);
    const width = clamp(Number(rect?.width), 0, 1 - x);
    const height = clamp(Number(rect?.height), 0, 1 - y);
    return { x, y, width, height };
}

const LAYOUT_ID = /^[a-z0-9][a-z0-9-]{0,63}$/;
const HEX_COLOR = /^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$/;
const ADDRESS = /^(?:0[xX])?[0-9a-fA-F]+$/;

function isSafeLayoutId(value) {
    return typeof value === "string" && LAYOUT_ID.test(value);
}

function isSafeAddress(value) {
    return typeof value === "string" && ADDRESS.test(value);
}

function normalizeAddress(value) {
    const candidate = String(value || "");
    if (!isSafeAddress(candidate)) return "";
    return /^0x/i.test(candidate) ? "0x" + candidate.slice(2) : "0x" + candidate;
}

function isSafeMonitorName(value) {
    return typeof value === "string" && value.length > 0 && value.length <= 256 && !/[\u0000\n\r]/.test(value);
}

function normalizeColor(value, fallback = "#8ab4f8") {
    const candidate = String(value || "");
    return HEX_COLOR.test(candidate) ? candidate : fallback;
}

function validateLayout(layout) {
    if (!layout || !isSafeLayoutId(layout.id)) return false;
    if (typeof layout.name !== "string" || layout.name.length < 1 || layout.name.length > 120) return false;
    if (!Array.isArray(layout.zones) || layout.zones.length < 1 || layout.zones.length > 64) return false;
    return layout.zones.every(zone => {
        const normalized = normalizeRect(zone);
        return Number.isFinite(Number(zone?.x))
            && Number.isFinite(Number(zone?.y))
            && Number.isFinite(Number(zone?.width))
            && Number.isFinite(Number(zone?.height))
            && normalized.width > 0
            && normalized.height > 0
            && normalized.x === Number(zone.x)
            && normalized.y === Number(zone.y)
            && normalized.width === Number(zone.width)
            && normalized.height === Number(zone.height);
    });
}

function sanitizeLayout(layout) {
    if (!validateLayout(layout)) return null;
    return {
        id: layout.id,
        name: layout.name,
        description: typeof layout.description === "string" ? layout.description.slice(0, 240) : "",
        zones: layout.zones.map(zone => normalizeRect(zone)),
    };
}

function sanitizeConfig(config = {}) {
    const rawGap = Number(config.gap);
    const rawPadding = Number(config.padding);
    const rawOpacity = Number(config.overlayOpacity);
    const rawCursorSampleInterval = Number(config.cursorSampleIntervalMs);
    const monitorLayouts = config.monitorLayouts && typeof config.monitorLayouts === "object" && !Array.isArray(config.monitorLayouts)
        ? Object.keys(config.monitorLayouts).reduce((result, name) => {
            if (isSafeMonitorName(name) && isSafeLayoutId(config.monitorLayouts[name])) result[name] = config.monitorLayouts[name];
            return result;
        }, {})
        : {};
    return {
        layout: isSafeLayoutId(config.layout) ? config.layout : "halves",
        gap: Number.isFinite(rawGap) ? clamp(Math.round(rawGap), 0, 80) : 12,
        padding: Number.isFinite(rawPadding) ? clamp(Math.round(rawPadding), 0, 80) : 12,
        overlayOpacity: Number.isFinite(rawOpacity) ? clamp(rawOpacity, 0.2, 1) : 0.86,
        zoneColor: normalizeColor(config.zoneColor),
        showLabels: config.showLabels !== false,
        floatOnPlacement: config.floatOnPlacement !== false,
        dragToZone: config.dragToZone !== false,
        cursorSampleIntervalMs: Number.isFinite(rawCursorSampleInterval) ? clamp(Math.round(rawCursorSampleInterval), 8, 1000) : 16,
        monitorLayouts: monitorLayouts,
    };
}

function parseJsonObject(text, fallback = null) {
    try {
        const parsed = JSON.parse(String(text));
        return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : fallback;
    } catch (_error) {
        return fallback;
    }
}

function isUnsupportedWindow(window) {
    if (!window || typeof window !== "object") return true;
    if (window.mapped === false || window.hidden === true) return true;
    if (window.pinned === true || window.pin === true) return true;
    if (window.fullscreen === true || Number(window.fullscreen) > 0 || Number(window.fullscreenState) > 0 || window.isFullscreen === true) return true;
    const workspace = window.workspace;
    if (typeof workspace === "string" && workspace.toLowerCase().startsWith("special")) return true;
    if (workspace && typeof workspace === "object" && (workspace.special === true || String(workspace.name || "").toLowerCase().startsWith("special") || Number(workspace.id) < 0)) return true;
    return false;
}
