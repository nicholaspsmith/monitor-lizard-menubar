# Changelog

Every push to `main` is a release. Add a `## [X.Y.Z] - YYYY-MM-DD` section at
the top (minor for features, patch for fixes); GitHub tags it and publishes
the section as the release notes. Versions follow [Semantic
Versioning](https://semver.org/).

## [Unreleased]

- docs: README shows the version and how releases carry the changelog

## [1.2.0] - 2026-09-26

- docs: README introduces the built-in screen's dim and XDR range
- menu: drop the Off on Battery row and the XDR side-effects note
- feat: one Brightness slider for the built-in screen
- fix: XDR boost follows the panel's headroom as it ramps
- docs: README covers how Dim and XDR brightness work
- fix: dim with a click-through overlay; five distinct steps
- fix: dim from the lowest lit brightness, not from 0 (the panel off)
- feat: dim the built-in panel below macOS's lowest brightness
- app: XDR engages HDR with a one-pixel overlay and waits for the headroom
- feat: XDR brightness drives the built-in panel past the SDR cap

## [1.1.0] - 2026-09-23

- app: the brightness keys take the DisplayServices route where DDC has refused
- core: note that DisplayServicesBrightnessChanged is gone since macOS 15.6
- app: keep the DisplayServices brightness slider live while the menu is open
- app: fall back to DisplayServices brightness on external displays that refuse DDC

## [1.0.0] - 2026-09-23

- feat: the menu shows the version it was built from
- feat: the keyboard's brightness keys step the main monitor over DDC
- LICENSE: name the copyright holder above the MPL text
- License: Mozilla Public License 2.0
- docs: regenerated icon strip and caption for the redrawn gecko glyph
- docs: rewrite README around the menu capture and icon strip
- app: follow built-in brightness changes via DisplayServices notifications
- app: fix stale DDC completions, sticky ddcUnavailable, slider failure UX
- core: fix Night Shift enabled/active field, guard private selectors
- docs: mascot, menu-bar strip, app icon
- docs+scripts: installer, icon builder, README
- app: fix icon refresh on menu close and TV-fix reentrancy
- app: status item, lizard glyph, display menu, Night Shift auto-fix
- app: admin-prompt override writer for TV-flagged displays
- app: fix resolution row apply gating, off-plan label and native match
- app: slider rows and the stepped resolution row with picker submenu
- app: fix DDC write failures marking displays unavailable
- app: DisplayModel orchestrates enumeration, DDC reads/writes and modes
- core: fix unclamped Night Shift/brightness change notification
- core: DisplayServices brightness and CBBlueLightClient Night Shift backends
- core: TV-role state machine and override plist
- core: validate stale mode indices in DisplayModes.apply and log failures
- core: HiDPI mode planner with the Dell's mode list as fixture
- core: fix IOKit handle leak in IORegistryScanner
- core: IORegistry scanner for framebuffers and external AV services
- core: fix DisplayInfo product-name locale selection
- core: DisplayInfo from CoreDisplay and the display/AV-service matcher
- core: fix IOAVService buffer safety and add validation tests
- core: IOAVService-backed DDC transport
- core: DDCService sleeps on every failure exit and covers the pop-vs-write race
- core: DDCService with serial queue, retries and latest-wins writes
- core: DDC/CI packet codec with vectors from the Dell
- build: package scaffold with core, app and test targets
- build: ignore SDD workspace
- docs: implementation plan
- docs: rollout gated on a one-week soak before removing BetterDisplay
- docs: spec self-review fixes (aspect filter, slider range)
- docs: Monitor Lizard design spec
