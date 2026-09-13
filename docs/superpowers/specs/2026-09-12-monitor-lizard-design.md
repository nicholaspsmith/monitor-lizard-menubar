# Monitor Lizard — design

*2026-09-12. A minimal external-display control app for the menu bar, replacing
BetterDisplay for the handful of things it is actually used for.*

## 1. Purpose and scope

BetterDisplay is installed for four things, measured from its preferences, the
scripts around it, and the live display state on 2026-09-12:

1. **DDC/CI control of the Dell U3818DW** over the MacBook Pro's HDMI port:
   brightness and contrast (volume and RGB gains are set once and never touched).
2. **Brightness of the built-in panel** alongside the external one.
3. **Choosing a HiDPI "looks like" resolution** for the Dell. The mode in use
   (2560×1067 HiDPI, 5120×2134 backing) is a native macOS mode; BetterDisplay
   adds no virtual screens and no EDID overrides here.
4. **Night Shift on external displays.** macOS silently disables Night Shift on
   any display it flags as a television, which it does for the Dell over HDMI.
   BetterDisplay's fix ("display role: computer monitor") writes
   `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<vendor hex>/DisplayProductID-<product hex>`
   containing `DisplayIsTV = false`. macOS reads that file when the display
   attaches; the app that wrote it need not be running.

Everything else BetterDisplay does (PIP, streaming, LUTs, compositor filters,
display groups, virtual screens, arrangement, LG/Samsung controllers) is unused.
Its one measurable cost is a wake-time bug that scrambles the hardware gamma
table, currently papered over by a launchd agent (`betterdisplay-color-guard`).

Monitor Lizard does exactly the four things above, natively, with no
dependencies, as a StatusItemKit app in the Menubarn family.

### Non-goals

- Keyboard brightness keys driving the external display.
- Volume / mute / input switching over DDC.
- Non-native ("flexible") resolutions, virtual screens, mirroring, arrangement.
- Colour/gamma adjustments of any kind. The app never writes a gamma table.
- HDR / nits mapping, ambient light, presets, schedules.
- Persisting slider values. The monitor keeps its DDC state; macOS keeps modes
  and Night Shift.

## 2. Feasibility evidence (spike, 2026-09-12)

Throwaway probes on the MacBook Pro M5 with the Dell on the built-in HDMI port:

- DDC over `IOAVService` (`DCPAVServiceProxy`, `Location = External`) read
  VCP 0x10 = 99/100, 0x12 = 75/100, 0x62 = 50/100, 0x60 = 0x1111, 0xD6 = 1 on
  the first attempt each, and a write of 0x10 round-tripped.
- `CGConfigureDisplayWithDisplayMode` + `CGCompleteDisplayConfiguration` to the
  current mode returned 0/0.
- `CoreDisplay_DisplayCreateInfoDictionary(id)` (CoreDisplay, resolved with
  `dlsym`) exposes `DisplayIsTV`, `DisplayVendorID`, `DisplayProductID`,
  `DisplaySerialNumber`, `IODisplayIsHDMISink`.
- `DisplayServicesGetBrightness` (DisplayServices.framework) and
  `CBBlueLightClient` (CoreBrightness.framework) both resolve.
- The override files exist for both Dell product IDs (`a0f0` HDMI, `a0f4`
  DisplayPort) and no attached display is flagged as a TV.

## 3. Name, mascot, glyph

- **Name:** Monitor Lizard. `Monitor Lizard.app`, bundle id
  `com.nicholaspsmith.MonitorLizard`, SwiftPM product `MonitorLizard`,
  repo `monitor-lizard-menubar` (public, MIT).
- **Mascot** (generated in the house style via the site's `art/prompts.json`;
  the concept mockup is a layout brief, not the image): a chunky monitor
  lizard whose thick body *is* a computer monitor — the flat screen is its
  torso, a stout wide head with a friendly grin rises from the top bezel
  (small: just enough to read as a lizard), and a long tapering scaly tail
  curls out of the monitor's stand along the bottom. Tan-and-black spotted
  scales. Same prompt preamble as every other mascot.
- **Menu-bar glyph** — `CharacterIcon.monitorLizard(brightness:nightShift:tongue:)`
  in StatusItemKit, drawn in code on a ~24×18 canvas like the others:
  - Bezel (rounded rect), stand, stout head protruding from the top bezel
    (offset right, one eye dot), tail curling out of the stand to the right —
    all in the bar's foreground colour.
  - **Screen = brightness.** The screen area fills bottom-up in proportion to
    the main display's brightness (0…1); at 0 only the bezel outline remains.
  - **Night Shift on → the fill is amber** (`NSColor(red: 1, green: 0.62, blue: 0.2)`);
    off → foreground colour.
  - **Tongue** (short forked line from the snout) for ~600 ms after a
    successful DDC write, as feedback in place of an OSD.
  - The "main display" is `CGMainDisplayID()`; its brightness comes from DDC if
    it is external, from DisplayServices if built-in.
  - Title is image-only, no text in the bar.
  - Joins `render-glyphs.sh` (id `monitor-lizard`) so the site strip, hero bar
    and `docs/menubar-icon.png` regenerate from code.

## 4. Architecture

SwiftPM package (`swift-tools-version:5.9`, `platforms: [.macOS(.v14)]`)
depending on `../StatusItemKit`, same shape as Battery Time and KeyLight:

```
Package.swift
Sources/MonitorLizardCore/      library, no AppKit, unit-tested
  VCP.swift                     DDC packet build / parse / checksum (pure)
  DDCService.swift              IOAVService bridge + serial queue + retries
  DisplayRegistry.swift         CG displays ↔ DDC services ↔ info dictionaries
  DisplayModes.swift            HiDPI mode list, dedup, ordering, apply
  BuiltInBrightness.swift       DisplayServices get/set via dlsym
  NightShift.swift              CBBlueLightClient enabled/strength/notify
  TVRole.swift                  DisplayIsTV detection, override path/plist, state
Sources/MonitorLizard/          AppKit executable
  main.swift                    app setup, StatusItemController, YieldClient, LoginItem
  DisplayModel.swift            re-enumeration on reconfigure/wake, cached values
  MenuController.swift          builds the menu from the model
  SliderItemView.swift          NSSlider in an NSMenuItem.view, coalesced writes
  OverrideWriter.swift          admin-prompt write of the override plist
Tests/MonitorLizardCoreTests/
Resources/Info.plist, Resources/bundle/AppIcon.icns
scripts/build-app.sh            exec ../StatusItemKit/scripts/make-app.sh MonitorLizard "Monitor Lizard"
scripts/make-icon.sh            mascot PNG → iconset → AppIcon.icns (sips + iconutil)
install.sh                      build + symlink into ~/Applications + open
docs/                           mascot.png, menubar-icon.png, superpowers/
README.md                       mascot, what it does, "Why not a SwiftBar plugin?"
```

Every hardware interface in `MonitorLizardCore` is a protocol
(`DDCTransport`, `BrightnessBackend`, `NightShiftBackend`, `DisplayInfoSource`)
with one real implementation and one fake used by tests. Every private symbol
is resolved with `dlsym`/`NSClassFromString` at first use and is optional: a
missing symbol disables that feature's rows ("unavailable on this macOS") and
nothing else.

### 4.1 DDC (`VCP.swift`, `DDCService.swift`)

Private IOKit functions, declared with `@_silgen_name` (IOKit exports them):

```
IOAVServiceCreateWithService(CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
IOAVServiceReadI2C(CFTypeRef, chip: UInt32, offset: UInt32, buf, len) -> IOReturn
IOAVServiceWriteI2C(CFTypeRef, chip: UInt32, dataAddress: UInt32, buf, len) -> IOReturn
```

Wire format (chip `0x37`, source address `0x51`), exactly as the spike used:

| | bytes | checksum |
|---|---|---|
| read request | `82 01 <vcp> <chk>` | `0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ vcp` |
| read reply (11 of 12 read) | `6E 88 02 <rc> <vcp> <type> <maxH> <maxL> <curH> <curL> <chk>` | `0x50 ^ bytes[0…9]` |
| write | `84 03 <vcp> <hi> <lo> <chk>` | `0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ vcp ^ hi ^ lo` |

A reply is accepted only if `bytes[1] == 0x88`, `bytes[4] == vcp` and the
checksum matches. Timing: 50 ms between request and reply read; ≥ 50 ms between
any two transactions on one bus. One serial `DispatchQueue` per service so two
sliders can never interleave. A read retries up to 3× on I/O error or bad
checksum; a write is sent once and confirmed by the next read. Only VCP `0x10`
(brightness) and `0x12` (contrast) are used.

### 4.2 Display registry (`DisplayRegistry.swift`)

For every id in `CGGetOnlineDisplayList`:

- `info = CoreDisplay_DisplayCreateInfoDictionary(id)` (CoreDisplay, `dlsym`).
  From it: name (`DisplayProductName`), vendor/product/serial, `DisplayIsTV`,
  `IODisplayLocation`. Built-in = `CGDisplayIsBuiltin(id)`.
- For external displays, find the matching `DCPAVServiceProxy`: iterate
  `IOServiceMatching("DCPAVServiceProxy")` with `Location == "External"`, walk
  up to the owning framebuffer (`IOMobileFramebufferShim` / `AppleCLCD2`) and
  compare its `DisplayAttributes.ProductAttributes` (`ProductID`,
  `SerialNumber`, `AlphanumericSerialNumber`) with the info dictionary. With a
  single external display, fall back to the only External service.
- A display with no matching service, or whose first read fails 3×, is marked
  `ddc: .unavailable` for the current menu session.

Re-enumerate on `CGDisplayRegisterReconfigurationCallback` (after the
`.endConfigurationFlag`, debounced 1 s) and `NSWorkspace.didWakeNotification`.
Old `IOAVService` handles are released and never reused — stale display ids
after a long sleep are the exact class of bug BetterDisplay has.

### 4.3 Modes (`DisplayModes.swift`)

`CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true])`,
filtered to `isUsableForDesktopGUI()`. The panel's **native mode** is the
non-HiDPI mode with the largest pixel area (3840×1600 on the Dell). Modes whose
aspect ratio differs from the native one by more than 1 % (the letterboxed
800×600, 960×540, 1280×540, 1280×720, 2560×1080, 2560×1440 entries) are
excluded everywhere — nobody wants them from a slider. Two lists:

- **HiDPI stops** (slider): modes with `pixelWidth == 2 * width`, one per
  `(width, height)`, preferring the refresh rate equal to the current mode's,
  else the highest. Ordered by width ascending. For the Dell today, 11 stops:
  1280, 1504, 1600, 1680, 1920, 2048, 2304, 2560, 3008, 3200, 3360 wide.
- **All modes** (picker submenu): a `HiDPI` header, the stops, a separator, a
  `Low resolution` header, then the same-aspect low-resolution modes
  (`pixelWidth == width`), deduped the same way. Rows are labelled `W×H`; the
  native mode's row ends in ` (native)`.

Apply with `CGBeginDisplayConfiguration` / `CGConfigureDisplayWithDisplayMode` /
`CGCompleteDisplayConfiguration(.forSession)`; `.forSession` because macOS
already persists the choice per display and the app has no state of its own.

### 4.4 Built-in brightness (`BuiltInBrightness.swift`)

`DisplayServicesCanChangeBrightness(id) -> Bool`,
`DisplayServicesGetBrightness(id, &Float) -> Int32`,
`DisplayServicesSetBrightness(id, Float) -> Int32` from
`/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices`
via `dlopen`/`dlsym`. Only ever called for `CGDisplayIsBuiltin` displays.

### 4.5 Night Shift (`NightShift.swift`)

`CBBlueLightClient` from
`/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness`
via `NSClassFromString`, called through an `@objc protocol` declaring
`setEnabled:`, `setStrength:commit:`, `getStrength:`, `getBlueLightStatus:`,
`setStatusNotificationBlock:` and the class method `supportsBlueLightReduction`.
The status struct layout (`active, enabled, sunSchedulePermitted, mode,
schedule, disableFlags, available`) is copied from the `nightlight` CLI and
verified at implementation time against the running system before use.
Strength is 0…1 and maps to the "warmth" slider.

### 4.6 TV role (`TVRole.swift`, `OverrideWriter.swift`)

State per external display:

| state | condition |
|---|---|
| `ok` | `DisplayIsTV == false` |
| `blocked` | `DisplayIsTV == true`, no override file |
| `fixedPendingReconnect` | `DisplayIsTV == true`, override file present (written now or earlier) |
| `skipped` | `blocked` and the user cancelled the admin prompt this launch |

Override path: `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<vendor lowercase hex>/DisplayProductID-<product lowercase hex>`.
Contents (XML plist): `DisplayIsTV = false`, `DisplayVendorID = <int>`,
`DisplayProductID = <int>` — identical to the files BetterDisplay writes, so an
existing file is recognised as already-fixed.

Write path: the app writes the plist to its own temp dir, then runs one
`do shell script "mkdir -p <dir> && cp <tmp> <dest> && chmod 644 <dest>" with administrator privileges`
through `NSAppleScript` (the standard macOS admin dialog). One prompt per new
display model, ever.

## 5. Behaviour

### 5.1 Menu

```
Monitor Lizard
────────────────
DELL U3818DW                       HDMI
  Brightness   ☀ ─────────●──── 99
  Contrast     ◐ ────────●───── 75
  Resolution   ▭ ───●────────── 2560×1067 ▸
  Night Shift  ✓ works on this display
────────────────
Built-in Display
  Brightness   ☀ ──────●─────── 56
────────────────
Night Shift              [on/off]
  Warmth       ─────●───────
────────────────
Start at Login ✓
Icon ▸
Quit
```

- One block per display, main display first, then `CGGetOnlineDisplayList`
  order. The right-hand tag is the transport (`HDMI` when `IODisplayIsHDMISink`,
  otherwise nothing). External blocks: brightness + contrast (DDC), resolution,
  Night Shift status. Built-in block: brightness only.
- Sliders are `NSSlider`s inside `NSMenuItem.view`s (KeyLight's
  `BrightnessSliderView` pattern, explicit frames). Brightness/contrast run 0…max as the
  monitor reports it (100 on the Dell); drags coalesce to at most 10 writes/s and the trailing value is
  always sent. The label to the right shows the value the monitor last
  confirmed, updated from the read that follows each write.
- Values are read asynchronously when the menu opens; until the first read
  returns, the slider shows the last cached value greyed, or a "–" label if
  there is none.
- **Resolution slider** has one tick per HiDPI stop (11 on the Dell), snaps, and applies on
  mouse-up only. The label is the "looks like" size. The `▸` opens the picker
  submenu (§4.3) with the current mode checked.
- A display whose DDC is unavailable shows one row, "No DDC control", instead
  of brightness/contrast sliders; resolution and Night Shift rows still appear.
- Global Night Shift toggle + warmth slider drive `CBBlueLightClient`; the
  notification block refreshes the glyph when Night Shift changes on its own
  (schedule, Control Center).
- Standard tail from StatusItemKit: Start at Login (`LoginItem`, SMAppService),
  Icon (`AppearanceMenu`), Quit.

### 5.2 Night Shift auto-fix

On launch and after every re-enumeration, for each external display in state
`blocked`: write the override (§4.6) immediately, then post a notification via
StatusItemKit `Notifier`: *"Marked DELL U3818DW as a monitor. Reconnect it (or
reboot) to enable Night Shift."* macOS only re-reads overrides on attach; the
app cannot force it. If the admin prompt is cancelled the display moves to
`skipped` until the next launch and its menu row reads
`✗ TV mode · Night Shift blocked · Retry`. The app never re-prompts on its own.

This applies to real TVs too (the TCL 65S455) — the only thing lost on a TV is
macOS's underscan slider.

### 5.3 Glyph updates

The glyph is re-rendered on: menu close, every DDC write, wake, re-enumeration,
Night Shift status notification, and the `StatusItemController` poll (every
30 s, which re-reads only the built-in brightness and Night Shift status — DDC
is never polled on a timer).

### 5.4 Errors

- DDC read fails 3× → `ddc: .unavailable` for this menu session; retried on the
  next menu open and on re-enumeration.
- DDC write I/O error → slider snaps back to the last confirmed value; the
  tongue does not show.
- Mode apply error → the slider returns to the current mode's stop; the error
  code is logged.
- Override write failure other than cancel → notification with the error text;
  state stays `blocked` (so it retries next launch).
- All hardware work runs off the main thread; UI mutations hop to main.
- `os.Logger` subsystem `com.nicholaspsmith.MonitorLizard`, categories `ddc`,
  `modes`, `nightshift`, `tvrole`, `menu`.

## 6. Testing

`swift test` on `MonitorLizardCoreTests`:

- `VCP`: request/write packet bytes and checksums for 0x10/0x12; reply parsing
  against the bytes captured in the spike; rejection of wrong-VCP, wrong-length
  and bad-checksum replies.
- `DisplayModes`: dedup/ordering from a fixture of the Dell's 60-mode list →
  the 11 HiDPI stops above; refresh-rate preference; low-res section.
- `TVRole`: path and plist contents for vendor 4268 / product 41200; state
  machine transitions including cancel → `skipped` → next-launch retry.
- `DisplayRegistry`: matching of fake CoreDisplay dictionaries to fake
  registry `ProductAttributes`, including the single-external fallback and a
  display with no service.
- `DDCService` with a fake transport: retry count, serialisation, coalescing.

Manual verification before the app is called done:

1. Brightness and contrast sliders move the Dell; the label matches what the
   monitor's own OSD reports.
2. Resolution slider switches to another stop and back; the picker shows the
   check on the right row.
3. Night Shift toggle and warmth change the screen; the glyph tints amber.
4. Unplug and replug the Dell: block disappears and returns, sliders live.
5. Lid-closed sleep ≥ 30 min, wake: colours sane, sliders live, no stale-ID
   errors in `log show`.
6. Barn's `scripts/verify-menubar.sh` reports the icon and no phantom item.
7. With a display flagged TV (unplug-then-delete one override temporarily, or
   the TCL): the admin prompt appears once, the file is written, the
   notification posts, cancel → `skipped` row.

## 7. Packaging, site, framework changes

- `scripts/build-app.sh` → `make-app.sh MonitorLizard "Monitor Lizard"`
  (stable self-signed identity, so any future TCC grant survives rebuilds).
- `scripts/make-icon.sh`: `docs/mascot.png` → 16…1024 iconset via `sips` →
  `iconutil -c icns` → `Resources/bundle/AppIcon.icns`.
- `install.sh`: build, symlink `~/Applications/Monitor Lizard.app`, open.
- StatusItemKit: `CharacterIcon.monitorLizard(...)` (§3).
- widgets.nicksmith.software: mascot prompt (`art/prompts.json`, `PROMPTS.md`),
  glyph id `monitor-lizard` in `render-glyphs.sh` (repo map entry
  `monitor-lizard-menubar`), a card in `site/index.html`, dropdown capture via
  the usual OCR-scrubbed pipeline.
- README: mascot, what it does, the DDC/Night Shift explanation in two
  paragraphs, "Why not a SwiftBar plugin?", install, verify.

## 8. Rollout

Nothing irreversible happens until Monitor Lizard has run as the only display
controller for a full week with no problems reported by Nick.

**Phase 1 — soak (reversible; starts once §6 passes):**

1. Quit BetterDisplay and turn off its start-at-login. Do not uninstall it.
   Two apps on the same DDC bus and two wake-time re-appliers would make any
   fault impossible to attribute.
2. Unload the colour guard without deleting it:
   `launchctl bootout gui/$UID/com.nicholassmith.bdcolorguard`. Its only job
   is undoing BetterDisplay's wake bug, so with BetterDisplay quit it must stay
   idle for the soak to prove anything.
3. Monitor Lizard starts at login. Nick uses the machine normally for **7 days**
   — including lid-closed sleeps, replugging the Dell, and resolution changes —
   and reports any problem. Any report resets the clock after the fix.
   Rollback at any point: `launchctl bootstrap` the guard, reopen BetterDisplay.

**Phase 2 — decommission (after the week, each step approved separately):**

1. Uninstall BetterDisplay: app and `pro.betterdisplay.BetterDisplay` prefs to
   the Trash. Keep the override files — they are the Night Shift fix.
2. Remove `betterdisplay-color-guard` for good: delete
   `~/Library/LaunchAgents/com.nicholassmith.bdcolorguard.plist`, delete
   `~/.local/bin/fixcolors`, and archive `~/Code/betterdisplay-color-guard`
   (README note: superseded by Monitor Lizard, repo kept for the investigation
   write-up).
3. Delete `~/.local/bin/dell-display-fix` (manages P2722H virtual screens that
   no longer exist).
4. Update the global CLAUDE.md StatusItemKit app list and Barn notes (the
   BetterDisplay status-item special cases become moot); update the memory
   files that reference BetterDisplay and the colour guard.

## 9. Open items to verify during implementation (not design decisions)

- `CBBlueLightClient` status struct layout on macOS 26 (compare with the
  `nightlight` source; assert `available`/`enabled` read back sanely).
- Whether `DisplayServicesSetBrightness` needs `DisplayServicesBrightnessChanged`
  afterwards for Control Center to notice (MonitorControl calls it).
- Exact `IORegistry` walk from `DCPAVServiceProxy` to the framebuffer's
  `ProductAttributes` on this machine (the spike only used the single-External
  fallback).
