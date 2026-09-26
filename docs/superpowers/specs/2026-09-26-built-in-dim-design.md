# Dim the built-in panel below macOS's minimum

**Date:** 2026-09-26
**Status:** approved in chat ("implement it for the built-in MacBook screen")

## Goal

At macOS's lowest brightness the built-in panel is still too bright for a
dark room. Let the brightness keys, and a menu slider, keep dimming past it.

## Mechanism

The panel's backlight minimum is macOS's (the IO registry reports about
1 nit and exposes no lower route), so this dims the pixels: the panel's
transfer table, scaled by a factor below 1. It is the XDR boost's table with
the opposite factor, so it reuses that code and its lifecycle.

- **Levels:** `level` 0…1, factor = `0.1^level` (perceptually even). The keys
  step in eighths: 75, 56, 42, 32, 24, 18, 13, 10% of normal. The slider is
  continuous over the same range.
- **Deepest is 10%.** 256-entry table; below that gradients band and text
  becomes hard to read.
- **Blacks are unchanged.** The backlight stays at its minimum; only lit
  pixels dim.

## Keys (`BrightnessKeys.route`)

- Main display external and controllable → step it (unchanged).
- Built-in main, dim level above 0 → down dims deeper, up dims less. Swallowed.
- Built-in main, macOS brightness at 0 (≤ 0.001), down → start dimming.
- Otherwise the key passes through to macOS (its HUD and its steps).

So down walks macOS's 16 steps to 0, then the 8 dim steps; up walks back.

## Table ownership (`PanelGammaController`, was `XDRController`)

One controller owns the built-in panel's transfer table, with one pure policy
(`PanelTablePolicy.mode`): asleep or settling → none; dim level above 0 → dim;
else XDR boost if its own policy allows; else none.

- Dim and XDR are exclusive: dimming switches XDR off, turning XDR on clears
  the dim.
- Dim needs no EDR overlay and ignores the battery rule.
- Everything the XDR lifecycle does applies: cleared before sleep, display
  sleep, and at the start of any reconfiguration, re-applied after 2 s of
  quiet; cleared on quit; CoreGraphics restores tables if the process dies;
  read back and checked after every clear.
- Not persisted: off at every launch, like XDR.

## Cancelling

Raising macOS brightness by more than 0.05 while dimmed (Control Center,
auto-brightness in a brighter room) clears the dim: someone wants light.

## Menu

The built-in block gains a **Dim** slider under Brightness: "Off", or the
percentage of normal. The keys move it while the menu is open.

## Testing

Unit: dim levels, key routing, table policy. Live: the table is written,
scaled and cleared (read back via `CGGetDisplayTransferByTable`); the user
checks the look.
