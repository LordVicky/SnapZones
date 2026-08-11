// .pragma library keeps this module shared by QML instances. Coordinates stored
// in layouts are normalized to the monitor work area (0..1); coordinates sent to
// Hyprland are pixels.
.pragma library

var EPSILON = 0.000001;

function clamp(value, minimum, maximum) {
    const number = Number(value);
    if (!Number.isFinite(number)) return minimum;
    return Math.min(Math.max(number, minimum), maximum);
}

function finite(value, fallback = 0) {
    const number = Number(value);
    return Number.isFinite(number) ? number : fallback;
}

function normalizeRect(rect) {
    const x = clamp(finite(rect?.x), 0, 1);
    const y = clamp(finite(rect?.y), 0, 1);
    const width = clamp(finite(rect?.width, 1), 0, 1 - x);
    const height = clamp(finite(rect?.height, 1), 0, 1 - y);
    return { x, y, width, height };
}

function rectIsUsable(rect, minimum = 0.0001) {
    return !!rect && rect.width >= minimum && rect.height >= minimum;
}

function monitorSizeComponent(monitor, axis, fallback) {
    const size = monitor?.size;
    if (Array.isArray(size))
        return finite(size[axis], fallback);
    if (size && typeof size === "object")
        return finite(size[axis === 0 ? "width" : "height"], fallback);
    return finite(monitor?.[axis === 0 ? "width" : "height"], fallback);
}

function transformNumber(value) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.round(number) : 0;
}

function transformSwapsAxes(transform) {
    const normalized = ((transform % 8) + 8) % 8;
    return normalized === 1 || normalized === 3 || normalized === 5 || normalized === 7;
}

function normalizeMonitor(monitor) {
    const rawPosition = monitor?.position || [monitor?.x, monitor?.y];
    const transform = transformNumber(monitor?.transform);
    const rawWidth = Math.max(1, Math.round(monitorSizeComponent(monitor, 0, 1)));
    const rawHeight = Math.max(1, Math.round(monitorSizeComponent(monitor, 1, 1)));
    // Hyprland's monitor JSON dimensions describe the configured mode. A
    // quarter-turn transform swaps the compositor/layout axes; Quickshell's
    // Screen dimensions already expose that oriented surface size.
    const width = transformSwapsAxes(transform) ? rawHeight : rawWidth;
    const height = transformSwapsAxes(transform) ? rawWidth : rawHeight;
    const x = Math.round(finite(rawPosition?.[0], finite(monitor?.x, 0)));
    const y = Math.round(finite(rawPosition?.[1], finite(monitor?.y, 0)));
    const scale = Math.max(0.1, finite(monitor?.scale, 1));
    const reserved = Array.isArray(monitor?.reserved) ? monitor.reserved : [0, 0, 0, 0];
    return {
        name: String(monitor?.name || monitor?.description || ""),
        x,
        y,
        width,
        height,
        scale,
        transform: transform,
        reserved: [0, 1, 2, 3].map(index => Math.max(0, Math.round(finite(reserved[index])))),
    };
}

function monitorWorkArea(monitor, padding = 0) {
    const normalized = normalizeMonitor(monitor);
    const [reservedLeft, reservedTop, reservedRight, reservedBottom] = normalized.reserved;
    const edge = Math.max(0, Math.round(finite(padding)));
    const left = normalized.x + reservedLeft + edge;
    const top = normalized.y + reservedTop + edge;
    const logicalWidth = normalized.width / normalized.scale;
    const logicalHeight = normalized.height / normalized.scale;
    const right = normalized.x + logicalWidth - reservedRight - edge;
    const bottom = normalized.y + logicalHeight - reservedBottom - edge;
    return {
        x: left,
        y: top,
        width: Math.max(1, right - left),
        height: Math.max(1, bottom - top),
    };
}

// Hyprland's monitor JSON is the source of truth for compositor coordinates.
// Quickshell Screen dimensions are the source of truth for a layer-shell
// surface, which can be logical (scaled) dimensions. Keep these two spaces
// separate instead of subtracting a JSON origin from a logical overlay rect.
function screenWorkArea(screen, monitor, padding = 0) {
    const normalized = normalizeMonitor(monitor);
    const width = Math.max(1, Math.round(finite(screen?.width, normalized.width)));
    const height = Math.max(1, Math.round(finite(screen?.height, normalized.height)));
    const logicalWidth = normalized.width / normalized.scale;
    const logicalHeight = normalized.height / normalized.scale;
    const scaleX = width / Math.max(1, logicalWidth);
    const scaleY = height / Math.max(1, logicalHeight);
    const [reservedLeft, reservedTop, reservedRight, reservedBottom] = normalized.reserved;
    const edge = Math.max(0, Math.round(finite(padding)));
    const left = Math.round(reservedLeft * scaleX) + edge;
    const top = Math.round(reservedTop * scaleY) + edge;
    const right = width - Math.round(reservedRight * scaleX) - edge;
    const bottom = height - Math.round(reservedBottom * scaleY) - edge;
    return {
        x: left,
        y: top,
        width: Math.max(1, right - left),
        height: Math.max(1, bottom - top),
    };
}

function globalWorkAreaForScreen(monitor, screen, padding = 0) {
    // Hyprland exact window dispatchers use compositor-layout coordinates:
    // mode pixels divided by monitor scale, plus the global monitor origin.
    // Qt's Screen dimensions may include an independent device-pixel ratio,
    // so they are correct for drawing but not for window placement.
    return monitorWorkArea(monitor, padding);
}

function zoneToPixels(zone, workArea, gap = 0) {
    const rect = normalizeRect(zone);
    const area = {
        x: finite(workArea?.x),
        y: finite(workArea?.y),
        width: Math.max(1, finite(workArea?.width, 1)),
        height: Math.max(1, finite(workArea?.height, 1)),
    };
    const gapPixels = Math.max(0, Math.round(finite(gap)));
    const left = area.x + rect.x * area.width;
    const top = area.y + rect.y * area.height;
    const right = area.x + (rect.x + rect.width) * area.width;
    const bottom = area.y + (rect.y + rect.height) * area.height;
    const inset = Math.min(gapPixels / 2, Math.max(0, (right - left - 1) / 2), Math.max(0, (bottom - top - 1) / 2));
    return {
        x: Math.round(left + inset),
        y: Math.round(top + inset),
        width: Math.max(1, Math.round(right - left - inset * 2)),
        height: Math.max(1, Math.round(bottom - top - inset * 2)),
    };
}

function zonesToPixels(zones, workArea, gap = 0) {
    return (Array.isArray(zones) ? zones : []).map(zone => zoneToPixels(zone, workArea, gap));
}

function containsPoint(rect, point) {
    return !!rect && !!point
        && point.x >= rect.x
        && point.y >= rect.y
        && point.x <= rect.x + rect.width
        && point.y <= rect.y + rect.height;
}

function zoneAtPoint(zones, point) {
    if (!Array.isArray(zones)) return -1;
    for (let index = 0; index < zones.length; index++) {
        if (containsPoint(zones[index], point)) return index;
    }
    return -1;
}

function clampWindowRect(rect, workArea) {
    const area = {
        x: finite(workArea?.x),
        y: finite(workArea?.y),
        width: Math.max(1, finite(workArea?.width, 1)),
        height: Math.max(1, finite(workArea?.height, 1)),
    };
    const width = clamp(Math.round(finite(rect?.width, 1)), 1, area.width);
    const height = clamp(Math.round(finite(rect?.height, 1)), 1, area.height);
    return {
        x: clamp(Math.round(finite(rect?.x, area.x)), area.x, area.x + area.width - width),
        y: clamp(Math.round(finite(rect?.y, area.y)), area.y, area.y + area.height - height),
        width,
        height,
    };
}

function rectEquals(left, right) {
    if (!left || !right) return false;
    return Math.abs(left.x - right.x) < EPSILON
        && Math.abs(left.y - right.y) < EPSILON
        && Math.abs(left.width - right.width) < EPSILON
        && Math.abs(left.height - right.height) < EPSILON;
}
