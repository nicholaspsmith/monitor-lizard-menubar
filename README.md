# Monitor Lizard

<p align="center"><img src="docs/mascot.png" width="160" alt="Monitor Lizard mascot, from the Menubarn widget library"></p>

A small macOS menu-bar app that controls your **external monitor** from one
dropdown: brightness, contrast, resolution and Night Shift. Nothing else.

Part of the [Menubarn](https://widgets.nicksmith.software) widget library.

## What you get

<p align="center"><img src="docs/menu.png" width="450" alt="The Monitor Lizard menu: Brightness, Contrast and Resolution sliders for a Dell monitor over HDMI, a Night Shift toggle with a Warmth slider, Start at Login, Icon and Quit"></p>

One section per display, then Night Shift for the whole Mac:

| Row | What it does |
|-----|--------------|
| **Brightness** | Sets the monitor's own backlight over DDC/CI, like pressing its front buttons. Also works for the built-in screen. |
| **Contrast** | Same, for contrast. |
| **Resolution** | Drag through the sharp HiDPI "looks like" sizes. The `▸` submenu lists every mode. |
| **Night Shift** | Toggle it, and set the warmth. |
| **Brightness Keys** | The keyboard's brightness keys step the main monitor's brightness over DDC, sixteen steps across the range. Needs Accessibility once. |
| **✓ / ⏳ / ✗ line** | Whether Night Shift works on that display. See below. |

Sliders apply live as you drag. Nothing is polled on a timer, and nothing you
set is stored by the app: the monitor keeps its own brightness and macOS keeps
the rest.

## Brightness keys

macOS only lets the brightness keys dim the built-in panel. With **Brightness
Keys** on (the default), Monitor Lizard catches the plain brightness keys and,
when the main display is an external monitor it can drive, steps that
monitor's brightness instead and eats the key; the gecko flicks its tongue as
the change lands. When the main display is the built-in panel, or a monitor
with no DDC, the key passes through untouched and macOS does what it always
did. Holding a key repeats. `Ctrl` + brightness is never touched, so
[KeyLight](https://github.com/nicholaspsmith/keylight-menubar) still gets it
for the keyboard backlight.

It listens for the media-key event an Apple keyboard sends, which is also what
KeyLight posts for F1/F2 on a third-party keyboard, so both kinds of keyboard
work without the two apps knowing about each other.

An event tap needs **Accessibility**: grant it when prompted, or later from the
menu's "⚠ Grant Accessibility…" row. The app is signed with the same stable
local identity as the other Menubarn apps, so the grant survives rebuilds.

## Why Night Shift may be off on your monitor

macOS turns Night Shift off on any display it thinks is a **television**, and
it thinks that about plenty of ordinary monitors plugged in over HDMI. Monitor
Lizard spots that, asks for your password **once**, and writes a small override
telling macOS the display is a monitor. Unplug and replug the display (or
reboot) and Night Shift works on it from then on. The app does not need to be
running for the fix to hold.

## The icon

<p align="center"><img src="docs/menubar-icon.png" alt="The menu-bar icon in four states: dim blue screen, bright blue screen, amber Night Shift screen, and the tongue flick"></p>

The mascot, shrunk to the menu bar: a gecko hugging the monitor, head
peering over the top corner, paws on the bezel, tail curling up over the
screen. The screen fills with blue as your main display gets brighter, turns
amber while Night Shift is on, and the gecko flicks its tongue when a slider
change lands on the monitor. Prefer a plain meter? **menu ▸ Icon** offers
Arc, Gauge, Pie or Wedge instead.

## Install

Requires macOS 14 or later on Apple Silicon.

```sh
git clone https://github.com/nicholaspsmith/StatusItemKit ../StatusItemKit
git clone https://github.com/nicholaspsmith/monitor-lizard-menubar
cd monitor-lizard-menubar
./install.sh
```

That builds `Monitor Lizard.app`, links it into `~/Applications` and launches
it. Turn on **Start at Login** from the menu if you want it to stay.

Quit BetterDisplay, MonitorControl or any other DDC tool first. Two apps
talking to one monitor at the same time interfere with each other.

## How it works

- **Brightness and contrast** go over DDC/CI through `IOAVService`, the private
  IOKit interface every Apple Silicon DDC tool uses. One serial queue per
  display, every read confirmed by checksum.
- **Built-in screen brightness** uses DisplayServices.
- **Brightness keys** come through a `CGEventTap` from
  [HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit), bound to the two
  brightness media keys with no modifiers.
- **Night Shift** uses CoreBrightness.
- **The "is this a TV?" flag** comes from CoreDisplay, the same source
  `system_profiler` reads.
- **The TV fix** is a plist at
  `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<hex>/DisplayProductID-<hex>`
  containing `DisplayIsTV = false`. macOS reads it when the display attaches.

The app never touches gamma tables.

## Develop

```sh
swift test                 # unit tests, no display needed
scripts/build-app.sh       # builds build/Monitor Lizard.app
log show --last 5m --predicate 'subsystem == "com.nicholaspsmith.MonitorLizard"' --style compact
```

## Why not a SwiftBar plugin?

This is a standalone `.app` built on
[StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit), not a script
under a plugin host: no SwiftBar to install, real AppKit sliders instead of
rendered text, event-driven refresh when displays connect or the Mac wakes,
and an icon that keeps its place in the bar. Sliders need in-process DDC; a
shell-out per tick would lag visibly. The full comparison is in
[StatusItemKit's README](https://github.com/nicholaspsmith/StatusItemKit#why-not-swiftbar).

## License

Copyright (c) 2026 Nicholas Smith. Licensed under the
[Mozilla Public License 2.0](LICENSE). You may use, modify, sell and
redistribute this software, including inside proprietary products, provided
the copyright notice and license stay on these files and any modified
versions of them are made available under the same license.
