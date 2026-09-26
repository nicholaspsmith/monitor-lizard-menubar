# Dim the built-in panel below macOS's minimum

**Date:** 2026-09-26
**Status:** approved in chat ("implement it for the built-in MacBook screen");
revised the same day after testing by eye. See "Revision" at the end. The
sections above it describe the first version.

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

## Revision (tested by eye, 2026-09-26)

The first version turned the screen off at every step. Two separate causes:

1. **Brightness 0 is the backlight off.** The panel driver's
   `IOMFBBrightnessLevel` (16.16 nits) reads 1.0 for every macOS brightness
   from 1/16 down to 0.0001, and 0 at brightness 0. The keys started dimming
   at 0, a screen already dark. Now they start at the lowest lit step,
   **1/16**. The ladder is 1/16, then the dim steps, then off, and up from
   off comes back at the deepest dim (`PanelDim.keyStep`).
2. **A transfer table below 1 does nothing visible on this panel,** in SDR,
   and in HDR mode (engaged with the XDR overlay, headroom 1.21), though
   macOS accepts and reads it back. 256- and 1024-entry tables behave
   the same.

What shipped instead: `DimOverlayController`, a click-through black window
over each built-in panel at `.screenSaver` level, `sharingType = .none`,
joining all Spaces and full-screen apps, refitted on screen-parameter
changes. The lifecycle is simpler than the table's: an overlay dies with
the process, and sleep can't strand it.

By eye at 1/16: 50% darker reads fine, 75% barely, 90% not at all. So there
are **5 steps** of `0.35^level`: 81, 66, 53, 43 and 35% of the light, each at
most 82% of the one above, so every key press is visibly different (a unit
test enforces that ratio).

`XDRController` is unchanged from the XDR branch (the `PanelGammaController`
merge was reverted). Dim and XDR stay exclusive, handled in `App.setDim` and
`toggleXDR`.

## One slider (2026-09-26, requested)

The Dim and Boost sliders are gone. The built-in panel has one Brightness
slider (`BuiltInSlider`): Dim across the bottom fifth, macOS brightness from
1/16 to full across the middle, and, with XDR Brightness on, the boost across
the top fifth. The keys walk the same ladder (`BrightnessKeys.route` gains
`.boost`: up past full with XDR on, four +25% steps). The XDR toggle stays.
Its boost starts at 0 and drops to 0 whenever XDR goes off, so the toggle
only extends the range. Dim and XDR are no longer exclusive: the slider can
never ask for both, because a boost only counts at full brightness.

Fixed on the way: the boost locked at the headroom seen at the first write
(about 1.26×, because the headroom ramps from 1.0× to 5.0× over about 2.25 s),
so the old Boost slider spanned 1.0–1.26×. The table now follows the headroom.
