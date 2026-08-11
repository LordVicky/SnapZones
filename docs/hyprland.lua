-- Vynx Zones 0.2 native drag integration.
--
-- Keep the native move dispatcher: it owns the real pointer drag. The
-- non-consuming globals only tell Quickshell when to show/update the visual
-- click-through overlay. Releasing Super commits; Escape cancels.

hl.bind("SUPER + SHIFT + mouse:272", hl.dsp.window.drag(), {
    mouse = true,
    description = "Window: Move with Vynx Zones preview",
})

hl.bind("SUPER + SHIFT + mouse:272", hl.dsp.global("quickshell:vynxZonesDragStart"), {
    mouse = true,
    non_consuming = true,
    description = "Shell: Start Vynx Zones drag preview",
})

hl.bind("SUPER + SHIFT_L", hl.dsp.global("quickshell:vynxZonesShiftCommit"))
hl.bind("SUPER + SHIFT_R", hl.dsp.global("quickshell:vynxZonesShiftCommit"))

-- Emergency cancellation. The drag layer is click-through and deliberately
-- does not take keyboard focus, so Escape must be forwarded by Hyprland.
hl.bind("Escape", hl.dsp.global("quickshell:vynxZonesDragCancel"), {
    ignore_mods = true,
    non_consuming = true,
    description = "Shell: Cancel Vynx Zones drag",
})
