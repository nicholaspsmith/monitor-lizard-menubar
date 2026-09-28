# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.2.1] - 2026-09-28

- `install.sh` now asks whether to turn on Start at Login (skipped when it is already on, or when there is no terminal to ask in), then relaunches the app, quitting any running copy first so the new build takes over
- `MonitorLizard --login on|off|status` turns Start at Login on or off from the shell, or reports it, and exits without opening the app
- docs: README shows the version and how releases carry the changelog

## [1.2.0] - 2026-09-26

### The MacBook screen, dimmer and brighter than macOS allows

The built-in screen gets **one Brightness slider** for its whole range:
- **Bottom fifth: Dim.** Below macOS's lowest lit step (1/16), a click-through black overlay dims the screen in five steps. Each lets through about 20% less light than the last: 81, 66, 53, 43 and 35%.
- **Middle: macOS's own range,** 1/16 to full.
- **Top fifth: XDR boost,** up to 2× past full, while **XDR Brightness** is on.

The **brightness keys** walk the same ladder: off ↔ the five dim steps ↔ macOS's steps ↔ four +25% boost steps with XDR on. Brightness-down at 1/16 dims instead of switching the screen off.

#### Dim
- On this panel, every macOS brightness from 1/16 down to 0.0001 is the same 1-nit backlight, and 0 is off, so macOS has nothing dimmer to offer.
- A gamma table scaled below 1 does nothing visible on the panel, in SDR or in HDR mode, so Dim is an overlay. It covers menus and the menu bar, takes no clicks, joins every Space and full-screen app, is left out of screenshots and recordings, and disappears when the app quits.
- Raising brightness another way (Control Center, auto-brightness in a brighter room) cancels it. Off at every launch.

#### XDR Brightness
- A one-pixel EDR overlay switches the panel into HDR mode, and a transfer table lifts SDR white into its headroom, capped at 2× (about 1000 nits).
- The table follows the headroom as it ramps up after HDR engages (1.0× to 5.0× over about 2 seconds) and as brightness changes.
- The table is removed before sleep and display sleep, on quit and whenever the display setup changes, then read back to confirm. It only ever touches the built-in panel.
- Off at every launch, and off on battery.

Merged in #7. Design notes: `docs/superpowers/specs/2026-09-26-built-in-dim-design.md`.

## [1.1.0] - 2026-09-23

### Brightness where DDC refuses
- External displays that refuse DDC (TVs over HDMI, typically) fall back to DisplayServices brightness when macOS can dim them itself.
- The brightness keys take the same route, so they work on those displays too.
- The DisplayServices brightness slider stays live while the menu is open.

Merged in #5.

## [1.0.0] - 2026-09-23

The first release of Monitor Lizard, a menu-bar app for external displays. It replaces BetterDisplay for this Mac's everyday needs.

### Features
- **Brightness and contrast over DDC/CI** through `IOAVService`, one serial queue per display, every read checksum-confirmed, latest-wins writes.
- **Resolution:** a stepped slider through the sharp HiDPI "looks like" sizes, with a submenu of every mode.
- **Built-in screen brightness** through DisplayServices, following changes made anywhere.
- **Night Shift** toggle and warmth slider.
- **TV-flag fix:** a display macOS wrongly calls a television (which blocks Night Shift) gets a display override plist, written with an admin prompt.
- **Brightness keys** step the main external monitor over DDC; on the built-in screen they pass through to macOS. Needs Accessibility once.
- **Menu-bar icon:** a gecko on a monitor whose screen shows brightness, amber for Night Shift, and a tongue flick when a change lands.
- The menu shows the version it was built from.

Licensed under the Mozilla Public License 2.0.
