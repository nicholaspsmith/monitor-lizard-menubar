# monitor-lizard-menubar

<p align="center"><img src="docs/mascot.png" width="160" alt="Monitor Lizard mascot, from the Menubarn widget library"></p>

A tiny standalone macOS menu-bar app ("Monitor Lizard.app", built on
[StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit)) that does the
four things people actually install a display manager for — and nothing else:

- **Brightness and contrast of external displays** over DDC/CI (Apple Silicon,
  HDMI / DisplayPort / USB-C), plus the built-in panel's brightness.
- **HiDPI resolution** — a slider over the native "looks like" sizes and a
  picker for every mode.
- **Night Shift on external displays.** macOS silently disables Night Shift on
  any display it flags as a *television*, which it does to plenty of monitors
  on HDMI. Monitor Lizard writes the per-model override that marks it a
  computer monitor (one admin prompt, ever) and Night Shift works after the
  next reconnect.
- **Night Shift toggle and warmth** from the same menu.

Part of the [Menubarn](https://widgets.nicksmith.software) widget library.

![The menu-bar icon](docs/menubar-icon.png)

The lizard's screen fills with the main display's brightness and turns amber
while Night Shift is on; the tongue flicks when a DDC write lands.

## How it works

DDC/CI goes through `IOAVService` (the private IOKit interface every Apple
Silicon DDC tool uses), one serial queue per display, reads confirmed by
checksum. The built-in panel uses DisplayServices, Night Shift uses
CoreBrightness, and the "is this a TV?" flag comes from CoreDisplay's display
info dictionary — the same source `system_profiler` reads. Nothing is polled on
a timer; values are read when the menu opens and after each write. The app
never writes a gamma table and never persists slider values: the monitor keeps
its own DDC state and macOS keeps modes and Night Shift.

The TV override is a plain plist at
`/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<hex>/DisplayProductID-<hex>`
containing `DisplayIsTV = false`. macOS reads it when the display attaches;
Monitor Lizard does not need to be running for it to hold.

## Install

```sh
git clone https://github.com/nicholaspsmith/StatusItemKit ../StatusItemKit   # sibling checkout
./install.sh
```

Requires macOS 14+ on Apple Silicon (DDC). Quit BetterDisplay or MonitorControl
first if you run one — two writers on one DDC bus interfere.

## Verify

```sh
swift test
scripts/build-app.sh
log show --last 5m --predicate 'subsystem == "com.nicholaspsmith.MonitorLizard"' --style compact
```

`scripts/build-app.sh` builds `build/Monitor Lizard.app`.

## Why not a SwiftBar plugin?

This is a standalone `.app` built on [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit), not a script under a plugin host: no SwiftBar to install, real AppKit sliders instead of rendered stdout, event-driven refresh on display reconfiguration and wake instead of a re-run timer, and an icon that keeps its place in the bar. Sliders need in-process DDC — a shell-out per tick would lag visibly. The full comparison is in [StatusItemKit's README](https://github.com/nicholaspsmith/StatusItemKit#why-not-swiftbar).

## The menu-bar suite

Part of a suite of macOS menu-bar apps that share one framework, one
build-and-sign script, and one installer, designed to sit in the same bar
together. See [Menubarn](https://widgets.nicksmith.software).

## License

MIT
