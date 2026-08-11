# SnapZones

FancyZones-style window placement for [ii-vynx](https://github.com/lll2yu/illogical-impulse) and Hyprland. SnapZones provides a keyboard/pointer picker, six reusable layouts, normalized multi-monitor geometry, safe `hyprctl` placement, and native `Super + left-drag` snapping.

## What is included

- Halves, Thirds, Main + Side, Four Quadrants, Ultrawide, and Full Screen layouts.
- A monitor-wide overlay with numbered zones and mouse hover/click selection.
- Keyboard placement (`1`–`9`), arrow-key preview, Enter/Space confirmation, and Escape cancel.
- Per-monitor layout assignments, gap and work-area padding controls.
- Correct handling of monitor origins, scale-independent normalized layout data, reserved edges, and hot-plug fallback.
- Optional float-on-placement for tiled windows.
- Native `Super+Shift + left-drag` preview and mouse-release snapping, with monitor crossing support.
- An input-transparent drag overlay so Hyprland keeps ownership of the real pointer gesture.
- A bounded, unprivileged Python stdlib cursor sampler using Hyprland's user IPC socket (no raw input, elevated privileges, daemon, or plugin).
- A cheatsheet page plus manifest-driven settings for the layout and placement options.
- A main-shell process guard so settings/helper Quickshell processes do not register the overlay or global shortcuts.
- Argument validation for all Hyprland commands. No shell command is assembled from a title, class, or other untrusted window string.

## Requirements

- ii-vynx with extension support enabled.
- Hyprland and `hyprctl` on `PATH`.
- Python 3 (standard library only) for native drag cursor sampling.
- Quickshell 0.3 or a compatible ii-vynx build.

The extension intentionally does not edit Hyprland or ii-vynx configuration files. It registers the following names; bind them in your own Hyprland configuration or use ii-vynx's keybind editor:

```lua
-- Example; choose keys that do not conflict with your setup.
hl.bind("SUPER + Z", hl.dsp.global("quickshell:snapZonesToggle"), { description = "Shell: Toggle SnapZones" })
hl.bind("SUPER + SHIFT + Z", hl.dsp.global("quickshell:snapZonesNextLayout"), { description = "Shell: Next SnapZones layout" })
```

The exact global syntax may differ between Hyprland versions. The names exposed by Quickshell are `snapZonesToggle`, `snapZonesOpen`, `snapZonesNextLayout`, `snapZonesPreviousLayout`, `snapZonesNextZone`, `snapZonesPreviousZone`, `snapZonesRestore`, `snapZonesDragStart`, `snapZonesShiftCancel`, and `snapZonesDragCancel`.

### Enable native Super-drag

Phase 2 keeps Hyprland's native move dispatcher in charge of the pointer. Add the bindings in [`docs/hyprland.lua`](docs/hyprland.lua) beside your existing Lua keybinds. The dedicated gesture is `Super+Shift + left-drag`; releasing the left mouse button commits the highlighted zone. Releasing either modifier only closes the overlay. Normal `Super + left-drag` stays unchanged.

The extension deliberately does not install these binds or edit your live configuration. Without the press/release integration, the Phase 1 picker and IPC commands still work, but holding Super while dragging will not open the preview.

## Install locally

1. Open ii-vynx Settings → Extensions.
2. Choose **Install local extension**.
3. Select this repository directory.
4. Enable **SnapZones**.
5. Add a keybind for `snapZonesToggle`.

For a manual test install, copy or symlink this directory to ii-vynx's installed extension directory. Do not copy it into the running shell while the extension is active; use ii-vynx's local extension reload flow so its metadata stays in sync.

## Usage

Open the picker with the configured shortcut or the ii-vynx IPC command:

```sh
qs -c ii ipc call snapZones toggle
```

With the picker open:

- Click a highlighted zone, or press `1`–`9`.
- Use arrow keys to preview a zone and Enter/Space to place it.
- Press Escape to cancel.

With the Lua integration enabled:

- Hold `Super+Shift` and left-drag a window.
- Move over a highlighted zone; the overlay follows the monitor under the cursor.
- Release the left mouse button to place the window in the highlighted zone.
- Release `Super` or `Shift` to close the overlay without placing.
- Press `Esc` to cancel explicitly.

The drag surface is intentionally click-through and does not take keyboard focus. Escape comes from the Hyprland binding; Super release uses ii-vynx's existing global modifier state.

The active layout and geometry settings are available through ii-vynx's extension configuration. Per-monitor assignments are stored by the service for the focused monitor; layouts are stored as normalized rectangles and therefore survive resolution changes.

## IPC surface

The service target is `snapZones`:

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
| `dragStart` | Start a native drag preview (normally called by the Lua press bind) |
| `dragEnd` | Drop into the current hovered zone (normally called by the Lua release bind) |
| `dragCancel` | Cancel a native drag preview |

## Scope and limitations

Native drag preview is opt-in through the Hyprland Lua snippet because an ii-vynx extension cannot intercept compositor pointer bindings by itself. It acts on the focused Hyprland window captured at press time and sends pixel move/resize dispatches when the left mouse button is released. Modifier release or Escape cancels. Fullscreen, pinned, hidden, unmapped, and special-workspace windows are ignored. Tiled windows are floated before placement when **Float tiled windows** is enabled.

The cursor helper polls `j/cursorpos` on Hyprland's per-user command socket only while a drag is active. It validates the socket environment, command, response size, coordinate range, and sampling interval. It never reads raw input devices and never invokes a shell. If the socket is unavailable, the overlay remains harmless and release cancels without issuing a placement.

Hyprland's own tiling layout remains authoritative for tiled windows. If you need a window to remain tiled, disable float-on-placement and use native Hyprland directional/container operations instead; exact arbitrary rectangles require floating clients. Phase 1 restore always restores exact geometry as a floating window because the ii-vynx extension API does not reliably expose the prior tiled/floating state on every Quickshell build.

The current monitor's reserved edges are read from `hyprctl monitors -j` when available. If no JSON snapshot is available during startup, the screen geometry is used safely and the next Hyprland update corrects it. If a monitor or window disappears before placement, the request is rejected and no command is sent.

## Development

This repository has no runtime dependency install step. Run the JavaScript state/geometry/layout tests with:

```sh
npm test
```

Run the Python fake-socket protocol tests with:

```sh
python3 tests/cursor_sampler.test.py
```

Run the metadata, JavaScript, QML formatting, and QML lint checks with:

```sh
npm run validate
```

`validate.sh` uses the installed ii-vynx tree for import resolution when it is present. A live compositor is not required for the pure tests or static checks; actual overlay behavior should be smoke-tested inside a running ii-vynx/Hyprland session.

## License

SnapZones is licensed under the GNU General Public License, version 3 or later. See [`LICENSE`](LICENSE).
