# Vynx Zones

FancyZones-style window placement for [ii-vynx](https://github.com/lll2yu/illogical-impulse) and Hyprland. Vynx Zones is a Phase 1 extension: it provides a keyboard/pointer picker, six reusable layouts, normalized multi-monitor geometry, and safe `hyprctl` placement for the focused window.

## What is included

- Halves, Thirds, Main + Side, Four Quadrants, Ultrawide, and Full Screen layouts.
- A monitor-wide overlay with numbered zones and mouse hover/click selection.
- Keyboard placement (`1`–`9`), arrow-key preview, Enter/Space confirmation, and Escape cancel.
- Per-monitor layout assignments, gap and work-area padding controls.
- Correct handling of monitor origins, scale-independent normalized layout data, reserved edges, and hot-plug fallback.
- Optional float-on-placement for tiled windows.
- A cheatsheet page plus manifest-driven settings for the layout and placement options.
- A main-shell process guard so settings/helper Quickshell processes do not register the overlay or global shortcuts.
- Argument validation for all Hyprland commands. No shell command is assembled from a title, class, or other untrusted window string.

## Requirements

- ii-vynx with extension support enabled.
- Hyprland and `hyprctl` on `PATH`.
- Quickshell 0.3 or a compatible ii-vynx build.

The extension intentionally does not edit Hyprland or ii-vynx configuration files. It registers the following names; bind them in your own Hyprland configuration or use ii-vynx's keybind editor:

```lua
-- Example; choose keys that do not conflict with your setup.
hl.bind("SUPER + Z", hl.dsp.global("quickshell:vynxZonesToggle"), { description = "Shell: Toggle Vynx Zones" })
hl.bind("SUPER + SHIFT + Z", hl.dsp.global("quickshell:vynxZonesNextLayout"), { description = "Shell: Next Vynx Zones layout" })
```

The exact global syntax may differ between Hyprland versions. The names exposed by Quickshell are `vynxZonesToggle`, `vynxZonesOpen`, `vynxZonesNextLayout`, `vynxZonesPreviousLayout`, `vynxZonesNextZone`, `vynxZonesPreviousZone`, and `vynxZonesRestore`.

## Install locally

1. Open ii-vynx Settings → Extensions.
2. Choose **Install local extension**.
3. Select this repository directory.
4. Enable **Vynx Zones**.
5. Add a keybind for `vynxZonesToggle`.

For a manual test install, copy or symlink this directory to ii-vynx's installed extension directory. Do not copy it into the running shell while the extension is active; use ii-vynx's local extension reload flow so its metadata stays in sync.

## Usage

Open the picker with the configured shortcut or the ii-vynx IPC command:

```sh
qs -c ii ipc call vynxZones toggle
```

With the picker open:

- Click a highlighted zone, or press `1`–`9`.
- Use arrow keys to preview a zone and Enter/Space to place it.
- Press Escape to cancel.

The active layout and geometry settings are available through ii-vynx's extension configuration. Per-monitor assignments are stored by the service for the focused monitor; layouts are stored as normalized rectangles and therefore survive resolution changes.

## IPC surface

The service target is `vynxZones`:

| Method | Description |
| --- | --- |
| `toggle` | Open or close the picker |
| `open` | Open the picker for the focused window |
| `close` | Close the picker |
| `place <zone>` | Place in a one-based zone number (the overlay's `1` is zone `1`) |
| `nextLayout` | Select the next built-in layout |
| `previousLayout` | Select the previous built-in layout |
| `nextZone` | Preview the next zone in the open picker |
| `previousZone` | Preview the previous zone in the open picker |
| `restore` | Restore the focused window's last saved geometry |

## Scope and limitations

Phase 1 intentionally uses a picker activation flow rather than intercepting every native drag. It acts on the focused Hyprland window and sends pixel move/resize dispatches. Fullscreen, pinned, hidden, unmapped, and special-workspace windows are ignored. Tiled windows are floated before placement when **Float tiled windows** is enabled.

Hyprland's own tiling layout remains authoritative for tiled windows. If you need a window to remain tiled, disable float-on-placement and use native Hyprland directional/container operations instead; exact arbitrary rectangles require floating clients. Phase 1 restore always restores exact geometry as a floating window because the ii-vynx extension API does not reliably expose the prior tiled/floating state on every Quickshell build.

The current monitor's reserved edges are read from `hyprctl monitors -j` when available. If no JSON snapshot is available during startup, the screen geometry is used safely and the next Hyprland update corrects it. If a monitor or window disappears before placement, the request is rejected and no command is sent.

## Development

This repository has no runtime dependency install step. Run the pure geometry/layout tests with:

```sh
npm test
```

Run the metadata, JavaScript, QML formatting, and QML lint checks with:

```sh
npm run validate
```

`validate.sh` uses the installed ii-vynx tree for import resolution when it is present. A live compositor is not required for the pure tests or static checks; actual overlay behavior should be smoke-tested inside a running ii-vynx/Hyprland session.

## License

Vynx Zones is licensed under the GNU General Public License, version 3 or later. See [`LICENSE`](LICENSE).
