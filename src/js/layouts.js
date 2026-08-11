// Built-in Phase 1 layouts. Keep these normalized: they work on any monitor
// resolution, scale, orientation, and Hyprland coordinate origin.
.pragma library

var layouts = [
    {
        id: "halves",
        name: "Halves",
        description: "Two equal columns",
        zones: [
            { x: 0, y: 0, width: 0.5, height: 1 },
            { x: 0.5, y: 0, width: 0.5, height: 1 },
        ],
    },
    {
        id: "thirds",
        name: "Thirds",
        description: "Three equal columns",
        zones: [
            { x: 0, y: 0, width: 1 / 3, height: 1 },
            { x: 1 / 3, y: 0, width: 1 / 3, height: 1 },
            { x: 2 / 3, y: 0, width: 1 / 3, height: 1 },
        ],
    },
    {
        id: "main-side",
        name: "Main + Side",
        description: "A wide main zone and two stacked side zones",
        zones: [
            { x: 0, y: 0, width: 0.66, height: 1 },
            { x: 0.66, y: 0, width: 0.34, height: 0.5 },
            { x: 0.66, y: 0.5, width: 0.34, height: 0.5 },
        ],
    },
    {
        id: "quadrants",
        name: "Four Quadrants",
        description: "A two-by-two grid",
        zones: [
            { x: 0, y: 0, width: 0.5, height: 0.5 },
            { x: 0.5, y: 0, width: 0.5, height: 0.5 },
            { x: 0, y: 0.5, width: 0.5, height: 0.5 },
            { x: 0.5, y: 0.5, width: 0.5, height: 0.5 },
        ],
    },
    {
        id: "ultrawide",
        name: "Ultrawide",
        description: "A focused center with two side columns",
        zones: [
            { x: 0, y: 0, width: 0.25, height: 1 },
            { x: 0.25, y: 0, width: 0.5, height: 1 },
            { x: 0.75, y: 0, width: 0.25, height: 1 },
        ],
    },
    {
        id: "fullscreen",
        name: "Full Screen",
        description: "One window fills the work area",
        zones: [{ x: 0, y: 0, width: 1, height: 1 }],
    },
];

function listLayouts() {
    return layouts.map(layout => ({
        id: layout.id,
        name: layout.name,
        description: layout.description,
        zones: layout.zones.map(zone => ({
            x: zone.x,
            y: zone.y,
            width: zone.width,
            height: zone.height,
        })),
    }));
}

function getLayout(id) {
    const wanted = String(id || "");
    return layouts.find(layout => layout.id === wanted) || layouts[0];
}

function getLayoutIndex(id) {
    const index = layouts.findIndex(layout => layout.id === String(id || ""));
    return index >= 0 ? index : 0;
}

function nextLayoutId(id, direction = 1) {
    const index = getLayoutIndex(id);
    const step = Number(direction) < 0 ? -1 : 1;
    return layouts[(index + step + layouts.length) % layouts.length].id;
}
