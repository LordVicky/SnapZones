-- SnapZones 0.2 native drag integration.
--
-- Keep the native move dispatcher: it owns the real pointer drag. The
-- non-consuming globals only tell Quickshell when to show/update the visual
-- click-through overlay. Releasing the mouse commits; releasing a modifier or
-- pressing Escape cancels.

hl.bind("SUPER + SHIFT + mouse:272", hl.dsp.window.drag(), {
    mouse = true,
    description = "Window: Move with SnapZones preview",
})

hl.bind("SUPER + SHIFT + mouse:272", hl.dsp.global("quickshell:snapZonesDragStart"), {
    mouse = true,
    non_consuming = true,
    description = "Shell: Start SnapZones drag preview",
})

hl.bind("SUPER + SHIFT + mouse:272", hl.dsp.exec_cmd("qs -c ii ipc call snapZones dragEnd"), {
    mouse = true,
    release = true,
    transparent = true,
    non_consuming = true,
    description = "Shell: Snap window into SnapZones zone",
})

hl.bind("SUPER + SHIFT_L", hl.dsp.global("quickshell:snapZonesShiftCancel"))
hl.bind("SUPER + SHIFT_R", hl.dsp.global("quickshell:snapZonesShiftCancel"))

-- Emergency cancellation. The drag layer is click-through and deliberately
-- does not take keyboard focus, so Escape must be forwarded by Hyprland.
hl.bind("Escape", hl.dsp.global("quickshell:snapZonesDragCancel"), {
    ignore_mods = true,
    non_consuming = true,
    description = "Shell: Cancel SnapZones drag",
})
