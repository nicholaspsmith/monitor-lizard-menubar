# Monitor Lizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A StatusItemKit menu-bar app that controls external displays (DDC brightness/contrast, HiDPI resolution), the built-in panel's brightness, and Night Shift — including auto-fixing displays macOS wrongly flags as TVs — so BetterDisplay can be retired.

**Architecture:** SwiftPM package with a pure, unit-tested `MonitorLizardCore` library (DDC protocol, display matching, mode planning, TV-role state, thin `dlsym` wrappers for the private frameworks) and an AppKit executable `MonitorLizard` that owns a `DisplayModel`, builds an `NSMenu` of slider rows, and drives the `CharacterIcon.monitorLizard` glyph. Hardware is reached through protocols with fakes for tests.

**Tech Stack:** Swift 5.9 toolchain (Swift 6.2 compiler), SwiftPM, AppKit, IOKit (`IOAVService` private calls), CoreGraphics display modes, CoreDisplay / DisplayServices / CoreBrightness private frameworks via `dlsym`, XCTest, `../StatusItemKit`.

**Spec:** `docs/superpowers/specs/2026-09-12-monitor-lizard-design.md`

## Global Constraints

- Package name `MonitorLizard`, `swift-tools-version:5.9`, `platforms: [.macOS(.v14)]`, single dependency `.package(path: "../StatusItemKit")`.
- App display name `Monitor Lizard`, executable/product `MonitorLizard`, bundle id `com.nicholaspsmith.MonitorLizard`, `LSUIElement = true`.
- The app never writes a gamma table, never persists slider values, never polls DDC on a timer.
- Every private symbol is resolved with `dlopen`/`dlsym` or `NSClassFromString` and is optional; a missing symbol disables only that feature.
- DDC: chip `0x37`, source address `0x51`, only VCP `0x10` and `0x12`; 50 ms between request and reply read, ≥ 50 ms between transactions, 3 read attempts, one serial queue per service.
- Override path `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<vendor lowercase hex>/DisplayProductID-<product lowercase hex>` with `DisplayIsTV = false`, `DisplayVendorID`, `DisplayProductID`.
- `os.Logger` subsystem `com.nicholaspsmith.MonitorLizard`, categories `ddc`, `modes`, `nightshift`, `tvrole`, `menu`.
- Menu-bar glyph: image only, no text; drawn by `CharacterIcon.monitorLizard(brightness:nightShift:tongue:)` in StatusItemKit; amber fill `NSColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)` when Night Shift is on.
- Commit after every task. Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01FwLoyXwWMxdy7tpPJzWF6R
  ```
- Repo: `~/Code/monitor-lizard-menubar` (public, `origin` = `git@github.com:nicholaspsmith/monitor-lizard-menubar.git`, branch `main`). StatusItemKit changes go in `~/Code/StatusItemKit` (its own commit). Site changes go in `~/Code/widgets.nicksmith.software`.
- Do not launch `Monitor Lizard.app` while BetterDisplay is running (two writers on one DDC bus). Quit BetterDisplay first (`osascript -e 'quit app "BetterDisplay"'`) for any manual test, and reopen it afterwards until the soak phase begins.

---

## File map

| Path | Responsibility |
|---|---|
| `Package.swift` | targets: `MonitorLizardCore` (lib), `MonitorLizard` (exe), `MonitorLizardCoreTests` |
| `Resources/Info.plist` | bundle metadata (read by StatusItemKit's `make-app.sh`) |
| `Resources/bundle/AppIcon.icns` | app icon, built from the mascot by `scripts/make-icon.sh` |
| `Sources/MonitorLizardCore/VCP.swift` | DDC packet build/parse/checksum — pure |
| `Sources/MonitorLizardCore/DDCService.swift` | `DDCTransport` protocol, `DDCService` (queue, retries, latest-wins writes) |
| `Sources/MonitorLizardCore/IOAVTransport.swift` | real transport over `IOAVService` private calls |
| `Sources/MonitorLizardCore/DisplayInfo.swift` | `DisplayInfo`, CoreDisplay info-dictionary reader |
| `Sources/MonitorLizardCore/DisplayMatcher.swift` | pure matching of displays ↔ framebuffers ↔ AV services |
| `Sources/MonitorLizardCore/IORegistryScanner.swift` | reads framebuffers + AV services from the IORegistry |
| `Sources/MonitorLizardCore/DisplayModes.swift` | `ModeSpec`, `ModePlan`, pure planner, CG apply |
| `Sources/MonitorLizardCore/BuiltInBrightness.swift` | DisplayServices via `dlsym` |
| `Sources/MonitorLizardCore/NightShift.swift` | `CBBlueLightClient` via `NSClassFromString` |
| `Sources/MonitorLizardCore/TVRole.swift` | override path/plist, `TVRoleState`, `TVRoleTracker` |
| `Sources/MonitorLizardCore/Log.swift` | the `Logger` instances |
| `Sources/MonitorLizard/main.swift` | `App` delegate, status item, glyph, menu tail |
| `Sources/MonitorLizard/DisplayModel.swift` | orchestration: entries, re-enumeration, reads/writes |
| `Sources/MonitorLizard/SliderRow.swift` | slider-in-menu-item view |
| `Sources/MonitorLizard/ResolutionRow.swift` | stepped slider + picker submenu |
| `Sources/MonitorLizard/MenuBuilder+Displays.swift` | builds the display blocks and Night Shift rows |
| `Sources/MonitorLizard/OverrideWriter.swift` | admin-prompt write of the override plist |
| `Tests/MonitorLizardCoreTests/*.swift` | one test file per core file |
| `scripts/build-app.sh`, `scripts/make-icon.sh`, `install.sh` | packaging |
| `README.md`, `docs/mascot.png`, `docs/menubar-icon.png` | docs |

---

### Task 1: Package scaffold that builds and tests

**Files:**
- Create: `Package.swift`, `Resources/Info.plist`, `Sources/MonitorLizardCore/Log.swift`, `Sources/MonitorLizard/main.swift` (placeholder), `Tests/MonitorLizardCoreTests/LogTests.swift`, `scripts/build-app.sh`

**Interfaces:**
- Produces: `Log.ddc`, `Log.modes`, `Log.nightshift`, `Log.tvrole`, `Log.menu` (`os.Logger`), used by every later task.

- [ ] **Step 1: Write the package manifest**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonitorLizard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MonitorLizard", targets: ["MonitorLizard"]),
        .library(name: "MonitorLizardCore", targets: ["MonitorLizardCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
    ],
    targets: [
        .target(name: "MonitorLizardCore"),
        .executableTarget(
            name: "MonitorLizard",
            dependencies: ["MonitorLizardCore", .product(name: "StatusItemKit", package: "StatusItemKit")]
        ),
        .testTarget(name: "MonitorLizardCoreTests", dependencies: ["MonitorLizardCore"]),
    ]
)
```

- [ ] **Step 2: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>MonitorLizard</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.nicholaspsmith.MonitorLizard</string>
	<key>CFBundleName</key>
	<string>Monitor Lizard</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 3: Write the failing test for the loggers**

`Tests/MonitorLizardCoreTests/LogTests.swift`:
```swift
import XCTest
@testable import MonitorLizardCore

final class LogTests: XCTestCase {
    func testSubsystemIsTheBundleID() {
        XCTAssertEqual(Log.subsystem, "com.nicholaspsmith.MonitorLizard")
    }
}
```

- [ ] **Step 4: Run it to make sure it fails**

Run: `cd ~/Code/monitor-lizard-menubar && swift test 2>&1 | tail -5`
Expected: build error, `cannot find 'Log' in scope`.

- [ ] **Step 5: Write `Log.swift` and the placeholder `main.swift`**

`Sources/MonitorLizardCore/Log.swift`:
```swift
import os

/// One logger per subsystem area so `log show --predicate 'subsystem == "com.nicholaspsmith.MonitorLizard"'`
/// tells the story the way Barn's does.
public enum Log {
    public static let subsystem = "com.nicholaspsmith.MonitorLizard"
    public static let ddc = Logger(subsystem: subsystem, category: "ddc")
    public static let modes = Logger(subsystem: subsystem, category: "modes")
    public static let nightshift = Logger(subsystem: subsystem, category: "nightshift")
    public static let tvrole = Logger(subsystem: subsystem, category: "tvrole")
    public static let menu = Logger(subsystem: subsystem, category: "menu")
}
```

`Sources/MonitorLizard/main.swift` (replaced in Task 12):
```swift
import AppKit
import MonitorLizardCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 6: Write `scripts/build-app.sh`**

```bash
#!/bin/bash
# Build "Monitor Lizard.app" via the shared StatusItemKit bundler.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ../StatusItemKit/scripts/make-app.sh MonitorLizard "Monitor Lizard"
```
Then `chmod +x scripts/build-app.sh`.

- [ ] **Step 7: Run the tests and the build**

Run: `swift test 2>&1 | tail -3 && swift build 2>&1 | tail -1`
Expected: `Executed 1 test, with 0 failures`, `Build complete!`

- [ ] **Step 8: Commit**

```bash
git add Package.swift Resources/Info.plist Sources Tests scripts
git commit -m "build: package scaffold with core, app and test targets"
```

---

### Task 2: DDC packet codec (`VCP.swift`)

**Files:**
- Create: `Sources/MonitorLizardCore/VCP.swift`
- Test: `Tests/MonitorLizardCoreTests/VCPTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum VCPCode: UInt8 { case brightness = 0x10, contrast = 0x12 }
  public struct VCPValue: Equatable { public let current: UInt16; public let maximum: UInt16 }
  public enum VCP {
      public static let chipAddress: UInt32 = 0x37
      public static let sourceAddress: UInt32 = 0x51
      public static let replyLength = 12
      public static func readRequest(_ code: VCPCode) -> [UInt8]
      public static func writeRequest(_ code: VCPCode, value: UInt16) -> [UInt8]
      public static func parseReply(_ bytes: [UInt8], expecting code: VCPCode) -> VCPValue?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MonitorLizardCore

final class VCPTests: XCTestCase {
    // Vectors computed from the DDC/CI spec and confirmed against the Dell U3818DW on 2026-09-12.
    func testReadRequestBytes() {
        XCTAssertEqual(VCP.readRequest(.brightness), [0x82, 0x01, 0x10, 0xAC])
        XCTAssertEqual(VCP.readRequest(.contrast), [0x82, 0x01, 0x12, 0xAE])
    }

    func testWriteRequestBytes() {
        XCTAssertEqual(VCP.writeRequest(.brightness, value: 99), [0x84, 0x03, 0x10, 0x00, 0x63, 0xCB])
        XCTAssertEqual(VCP.writeRequest(.contrast, value: 75), [0x84, 0x03, 0x12, 0x00, 0x4B, 0xE1])
    }

    func testWriteRequestSplitsHighByte() {
        XCTAssertEqual(Array(VCP.writeRequest(.brightness, value: 0x0102)[3...4]), [0x01, 0x02])
    }

    func testParsesAGoodReply() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA3, 0x00]
        XCTAssertEqual(VCP.parseReply(reply, expecting: .brightness), VCPValue(current: 99, maximum: 100))
        let contrast: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x89, 0x00]
        XCTAssertEqual(VCP.parseReply(contrast, expecting: .contrast), VCPValue(current: 75, maximum: 100))
    }

    func testRejectsWrongVCP() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x89, 0x00]
        XCTAssertNil(VCP.parseReply(reply, expecting: .brightness))
    }

    func testRejectsBadChecksum() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA2, 0x00]
        XCTAssertNil(VCP.parseReply(reply, expecting: .brightness))
    }

    func testRejectsWrongLengthMarkerAndShortBuffers() {
        var reply: [UInt8] = [0x6E, 0x86, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA3, 0x00]
        XCTAssertNil(VCP.parseReply(reply, expecting: .brightness))
        reply = [0x6E, 0x88, 0x02]
        XCTAssertNil(VCP.parseReply(reply, expecting: .brightness))
        XCTAssertNil(VCP.parseReply([UInt8](repeating: 0, count: 12), expecting: .brightness))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter VCPTests 2>&1 | tail -3`
Expected: compile error `cannot find 'VCP' in scope`.

- [ ] **Step 3: Implement `VCP.swift`**

```swift
import Foundation

/// The two VCP codes the app uses. Nothing else is ever sent to a monitor.
public enum VCPCode: UInt8 {
    case brightness = 0x10
    case contrast = 0x12
}

public struct VCPValue: Equatable {
    public let current: UInt16
    public let maximum: UInt16
    public init(current: UInt16, maximum: UInt16) {
        self.current = current
        self.maximum = maximum
    }
}

/// DDC/CI over I²C as the monitor sees it. Pure byte-level codec; the
/// transport lives elsewhere.
///
/// Requests are sent to chip 0x37 with source address 0x51 and are
/// checksummed as `0x6E ^ 0x51 ^ payload`. A reply is 11 bytes
/// `6E 88 02 rc vcp type maxH maxL curH curL chk` (read as 12) and is
/// checksummed as `0x50 ^ bytes[0…9]`. Both forms were confirmed byte for
/// byte against a Dell U3818DW.
public enum VCP {
    public static let chipAddress: UInt32 = 0x37
    public static let sourceAddress: UInt32 = 0x51
    public static let replyLength = 12

    public static func readRequest(_ code: VCPCode) -> [UInt8] {
        checksummed([0x82, 0x01, code.rawValue])
    }

    public static func writeRequest(_ code: VCPCode, value: UInt16) -> [UInt8] {
        checksummed([0x84, 0x03, code.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    public static func parseReply(_ bytes: [UInt8], expecting code: VCPCode) -> VCPValue? {
        guard bytes.count >= 11, bytes[1] == 0x88, bytes[4] == code.rawValue else { return nil }
        var checksum: UInt8 = 0x50
        for byte in bytes[0..<10] { checksum ^= byte }
        guard checksum == bytes[10] else { return nil }
        let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        return VCPValue(current: current, maximum: maximum)
    }

    private static func checksummed(_ payload: [UInt8]) -> [UInt8] {
        var checksum: UInt8 = 0x6E ^ 0x51
        for byte in payload { checksum ^= byte }
        return payload + [checksum]
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VCPTests 2>&1 | tail -3`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MonitorLizardCore/VCP.swift Tests/MonitorLizardCoreTests/VCPTests.swift
git commit -m "core: DDC/CI packet codec with vectors from the Dell"
```

---

### Task 3: `DDCService` — queue, retries, latest-wins writes

**Files:**
- Create: `Sources/MonitorLizardCore/DDCService.swift`
- Test: `Tests/MonitorLizardCoreTests/DDCServiceTests.swift`

**Interfaces:**
- Consumes: `VCP`, `VCPCode`, `VCPValue` (Task 2).
- Produces:
  ```swift
  public protocol DDCTransport: AnyObject {
      func write(_ bytes: [UInt8]) throws          // I²C write to chip 0x37 / 0x51
      func read(count: Int) throws -> [UInt8]      // I²C read from chip 0x37 / 0x51
  }
  public enum DDCError: Error, Equatable { case io(Int32), badReply, unavailable }
  public final class DDCService {
      public init(transport: DDCTransport, sleep: @escaping (UInt32) -> Void = { usleep($0) }, queue: DispatchQueue = DispatchQueue(label: "ddc"))
      public func read(_ code: VCPCode, completion: @escaping (Result<VCPValue, DDCError>) -> Void)
      public func write(_ code: VCPCode, value: UInt16, completion: @escaping (Result<VCPValue, DDCError>) -> Void) // confirms by reading back
      public static let attempts = 3
      public static let settleMicroseconds: UInt32 = 50_000
  }
  ```
  Completions are invoked on the service's queue; callers hop to main themselves.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MonitorLizardCore

/// A transport that plays back scripted replies and records every write.
final class FakeTransport: DDCTransport {
    var writes: [[UInt8]] = []
    var replies: [[UInt8]] = []          // consumed in order by read(count:)
    var writeError: Int32?               // if set, every write throws
    func write(_ bytes: [UInt8]) throws {
        if let e = writeError { throw DDCError.io(e) }
        writes.append(bytes)
    }
    func read(count: Int) throws -> [UInt8] {
        guard !replies.isEmpty else { throw DDCError.io(-1) }
        return replies.removeFirst()
    }
}

final class DDCServiceTests: XCTestCase {
    static let goodBrightness: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA3, 0x00]
    static let badChecksum: [UInt8]    = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA2, 0x00]

    private func makeService(_ t: FakeTransport) -> (DDCService, DispatchQueue) {
        let q = DispatchQueue(label: "test.ddc")
        return (DDCService(transport: t, sleep: { _ in }, queue: q), q)
    }

    func testReadSendsRequestThenParsesReply() {
        let t = FakeTransport(); t.replies = [Self.goodBrightness]
        let (s, q) = makeService(t)
        let done = expectation(description: "read")
        s.read(.brightness) { result in
            XCTAssertEqual(try? result.get(), VCPValue(current: 99, maximum: 100))
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        q.sync {}
        XCTAssertEqual(t.writes, [[0x82, 0x01, 0x10, 0xAC]])
    }

    func testReadRetriesOnBadChecksumThenSucceeds() {
        let t = FakeTransport(); t.replies = [Self.badChecksum, Self.badChecksum, Self.goodBrightness]
        let (s, _) = makeService(t)
        let done = expectation(description: "read")
        s.read(.brightness) { result in
            XCTAssertEqual(try? result.get(), VCPValue(current: 99, maximum: 100))
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(t.writes.count, 3)
    }

    func testReadGivesUpAfterThreeAttempts() {
        let t = FakeTransport(); t.replies = [Self.badChecksum, Self.badChecksum, Self.badChecksum, Self.goodBrightness]
        let (s, _) = makeService(t)
        let done = expectation(description: "read")
        s.read(.brightness) { result in
            if case .failure(.badReply) = result { done.fulfill() } else { XCTFail("expected badReply, got \(result)") }
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(t.writes.count, 3)
    }

    func testWriteSendsPacketThenConfirmsByReading() {
        let t = FakeTransport(); t.replies = [Self.goodBrightness]
        let (s, _) = makeService(t)
        let done = expectation(description: "write")
        s.write(.brightness, value: 99) { result in
            XCTAssertEqual(try? result.get(), VCPValue(current: 99, maximum: 100))
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(t.writes.first, [0x84, 0x03, 0x10, 0x00, 0x63, 0xCB])
        XCTAssertEqual(t.writes.last, [0x82, 0x01, 0x10, 0xAC])
    }

    func testBurstOfWritesCollapsesToTheLatestValue() {
        // A slider drag posts many values faster than the bus can take them;
        // only the value current when the queue gets to it must be sent.
        let t = FakeTransport()
        t.replies = [[UInt8]](repeating: Self.goodBrightness, count: 30)
        let q = DispatchQueue(label: "test.ddc")
        let gate = DispatchSemaphore(value: 0)
        let s = DDCService(transport: t, sleep: { _ in }, queue: q)
        q.async { gate.wait() }                     // hold the queue so the burst piles up
        var completions = 0
        let all = expectation(description: "all completions")
        for v in 1...20 {
            s.write(.brightness, value: UInt16(v)) { _ in
                completions += 1
                if completions == 20 { all.fulfill() }
            }
        }
        gate.signal()
        wait(for: [all], timeout: 2)
        let sentWrites = t.writes.filter { $0[0] == 0x84 }
        XCTAssertEqual(sentWrites.count, 1, "only the last queued value is written")
        XCTAssertEqual(sentWrites.first?[4], 20)
    }

    func testIOErrorSurfacesAsIO() {
        let t = FakeTransport(); t.writeError = -536870201
        let (s, _) = makeService(t)
        let done = expectation(description: "read")
        s.read(.brightness) { result in
            if case .failure(.io(-536870201)) = result { done.fulfill() } else { XCTFail("\(result)") }
        }
        wait(for: [done], timeout: 1)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter DDCServiceTests 2>&1 | tail -3`
Expected: compile error `cannot find type 'DDCTransport'`.

- [ ] **Step 3: Implement `DDCService.swift`**

```swift
import Foundation

/// One I²C endpoint at the monitor's DDC address. The real one wraps an
/// `IOAVService`; tests script replies.
public protocol DDCTransport: AnyObject {
    func write(_ bytes: [UInt8]) throws
    func read(count: Int) throws -> [UInt8]
}

public enum DDCError: Error, Equatable {
    case io(Int32)
    case badReply
    case unavailable
}

/// Serialises every transaction on one display's bus, spaces them out, and
/// retries reads. Writes are latest-wins: a slider drag can post values far
/// faster than the bus accepts them, so a pending write is replaced rather than
/// queued, and each write is confirmed by the read that follows it.
public final class DDCService {
    public static let attempts = 3
    public static let settleMicroseconds: UInt32 = 50_000

    private let transport: DDCTransport
    private let sleep: (UInt32) -> Void
    private let queue: DispatchQueue
    private var pending: [VCPCode: (value: UInt16, completions: [(Result<VCPValue, DDCError>) -> Void])] = [:]
    private let lock = NSLock()

    public init(transport: DDCTransport,
                sleep: @escaping (UInt32) -> Void = { usleep($0) },
                queue: DispatchQueue = DispatchQueue(label: "com.nicholaspsmith.MonitorLizard.ddc")) {
        self.transport = transport
        self.sleep = sleep
        self.queue = queue
    }

    public func read(_ code: VCPCode, completion: @escaping (Result<VCPValue, DDCError>) -> Void) {
        queue.async { completion(self.readNow(code)) }
    }

    public func write(_ code: VCPCode, value: UInt16, completion: @escaping (Result<VCPValue, DDCError>) -> Void) {
        lock.lock()
        if var entry = pending[code] {
            entry.value = value
            entry.completions.append(completion)
            pending[code] = entry
            lock.unlock()
            return                                   // the queued block will pick up the new value
        }
        pending[code] = (value, [completion])
        lock.unlock()
        queue.async {
            self.lock.lock()
            let entry = self.pending.removeValue(forKey: code)
            self.lock.unlock()
            guard let entry else { return }
            let result = self.writeNow(code, value: entry.value)
            entry.completions.forEach { $0(result) }
        }
    }

    // MARK: - On the queue

    private func readNow(_ code: VCPCode) -> Result<VCPValue, DDCError> {
        var last: DDCError = .badReply
        for attempt in 1...Self.attempts {
            do {
                try transport.write(VCP.readRequest(code))
                sleep(Self.settleMicroseconds)
                let reply = try transport.read(count: VCP.replyLength)
                sleep(Self.settleMicroseconds)
                if let value = VCP.parseReply(reply, expecting: code) { return .success(value) }
                last = .badReply
                Log.ddc.debug("bad reply for \(code.rawValue, format: .hex) attempt \(attempt)")
            } catch let e as DDCError {
                last = e
                Log.ddc.debug("i/o error \(String(describing: e)) attempt \(attempt)")
                sleep(Self.settleMicroseconds)
            } catch {
                last = .io(-1)
            }
        }
        return .failure(last)
    }

    private func writeNow(_ code: VCPCode, value: UInt16) -> Result<VCPValue, DDCError> {
        do {
            try transport.write(VCP.writeRequest(code, value: value))
        } catch let e as DDCError {
            return .failure(e)
        } catch {
            return .failure(.io(-1))
        }
        sleep(Self.settleMicroseconds)
        return readNow(code)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter DDCServiceTests 2>&1 | tail -3`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MonitorLizardCore/DDCService.swift Tests/MonitorLizardCoreTests/DDCServiceTests.swift
git commit -m "core: DDCService with serial queue, retries and latest-wins writes"
```

---

### Task 4: Real transport over `IOAVService`

**Files:**
- Create: `Sources/MonitorLizardCore/IOAVTransport.swift`
- Test: `Tests/MonitorLizardCoreTests/IOAVTransportTests.swift` (symbol-resolution smoke test only; the bus itself is exercised by the manual checklist)

**Interfaces:**
- Consumes: `DDCTransport`, `DDCError`, `VCP.chipAddress`, `VCP.sourceAddress`.
- Produces:
  ```swift
  public final class IOAVTransport: DDCTransport {
      public init?(service: io_service_t)   // nil if IOAVServiceCreateWithService fails
  }
  public enum IOAVSymbols { public static var isAvailable: Bool }
  ```

- [ ] **Step 1: Write the failing smoke test**

```swift
import XCTest
@testable import MonitorLizardCore

final class IOAVTransportTests: XCTestCase {
    func testPrivateIOAVSymbolsResolveOnThisMac() {
        // Apple Silicon only; documents the dependency rather than proving the bus.
        XCTAssertTrue(IOAVSymbols.isAvailable)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter IOAVTransportTests 2>&1 | tail -3`
Expected: compile error `cannot find 'IOAVSymbols'`.

- [ ] **Step 3: Implement `IOAVTransport.swift`**

```swift
import Foundation
import IOKit

/// The three private IOKit entry points DDC needs on Apple Silicon. Resolved
/// with dlsym so a future macOS that drops one degrades to "No DDC control"
/// instead of a launch-time link failure.
public enum IOAVSymbols {
    typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias ReadI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias WriteI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeRawPointer, UInt32) -> IOReturn

    static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    static let create: CreateWithService? = symbol("IOAVServiceCreateWithService")
    static let read: ReadI2C? = symbol("IOAVServiceReadI2C")
    static let write: WriteI2C? = symbol("IOAVServiceWriteI2C")

    public static var isAvailable: Bool { create != nil && read != nil && write != nil }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}

/// A `DDCTransport` bound to one `DCPAVServiceProxy` (one external display).
public final class IOAVTransport: DDCTransport {
    private let service: CFTypeRef

    public init?(service ioService: io_service_t) {
        guard let create = IOAVSymbols.create,
              let ref = create(kCFAllocatorDefault, ioService)?.takeRetainedValue() else { return nil }
        service = ref
    }

    public func write(_ bytes: [UInt8]) throws {
        guard let write = IOAVSymbols.write else { throw DDCError.unavailable }
        let rc = bytes.withUnsafeBytes { write(service, VCP.chipAddress, VCP.sourceAddress, $0.baseAddress!, UInt32(bytes.count)) }
        if rc != KERN_SUCCESS { throw DDCError.io(rc) }
    }

    public func read(count: Int) throws -> [UInt8] {
        guard let read = IOAVSymbols.read else { throw DDCError.unavailable }
        var buffer = [UInt8](repeating: 0, count: count)
        let rc = buffer.withUnsafeMutableBytes { read(service, VCP.chipAddress, VCP.sourceAddress, $0.baseAddress!, UInt32(count)) }
        if rc != KERN_SUCCESS { throw DDCError.io(rc) }
        return buffer
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter IOAVTransportTests 2>&1 | tail -3`
Expected: `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MonitorLizardCore/IOAVTransport.swift Tests/MonitorLizardCoreTests/IOAVTransportTests.swift
git commit -m "core: IOAVService-backed DDC transport"
```

---

### Task 5: Display info and the display↔framebuffer↔AV-service matcher

**Files:**
- Create: `Sources/MonitorLizardCore/DisplayInfo.swift`, `Sources/MonitorLizardCore/DisplayMatcher.swift`
- Test: `Tests/MonitorLizardCoreTests/DisplayMatcherTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct DisplayInfo: Equatable, Identifiable {
      public let id: CGDirectDisplayID
      public let name: String
      public let vendorID: UInt32
      public let productID: UInt32
      public let serial: UInt32
      public let isBuiltIn: Bool
      public let isMain: Bool
      public let isTV: Bool
      public let isHDMI: Bool
      public init(id:name:vendorID:productID:serial:isBuiltIn:isMain:isTV:isHDMI:)
      public static func from(dictionary: [String: Any], id: CGDirectDisplayID, isBuiltIn: Bool, isMain: Bool) -> DisplayInfo
  }
  public enum CoreDisplayInfo { public static func dictionary(for id: CGDirectDisplayID) -> [String: Any]? }
  public struct FramebufferEntry: Equatable { public let name: String; public let productID: UInt32?; public let serial: UInt32?; public let entry: UInt32 /* io_registry_entry_t or 0 in tests */ }
  public struct AVServiceEntry: Equatable { public let path: String; public let entry: UInt32 }
  public enum DisplayMatcher {
      public static func framebufferName(inAVServicePath path: String) -> String?
      public static func match(displays: [DisplayInfo], framebuffers: [FramebufferEntry], services: [AVServiceEntry]) -> [CGDirectDisplayID: AVServiceEntry]
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CoreGraphics
@testable import MonitorLizardCore

final class DisplayMatcherTests: XCTestCase {
    // Real values from this Mac (ioreg, 2026-09-12).
    static let dellPath = "IOService:/AppleARMPE/arm-io@10F00000/AppleSoCIO/dcpext0@B2E00000/AppleASCWrapV6/iop-dcpext0-nub/RTBuddy(DCPEXT0)/DCPEXT0Endpoint11/AFKDCPEXT0Endpoint11/AFKEPInterfaceServiceKextV2/dispext0:dcpav-service-epic:0/DCPAVServiceProxy"

    func testExtractsFramebufferNameFromServicePath() {
        XCTAssertEqual(DisplayMatcher.framebufferName(inAVServicePath: Self.dellPath), "dispext0")
        XCTAssertEqual(DisplayMatcher.framebufferName(inAVServicePath: "…/dispext3:dcpav-service-epic:0/DCPAVServiceProxy"), "dispext3")
        XCTAssertNil(DisplayMatcher.framebufferName(inAVServicePath: "IOService:/nothing/here"))
    }

    func testMatchesByProductAndSerialThroughTheFramebufferName() {
        let dell = DisplayInfo(id: 5, name: "DELL U3818DW", vendorID: 4268, productID: 41200, serial: 825640780, isBuiltIn: false, isMain: true, isTV: false, isHDMI: true)
        let tv = DisplayInfo(id: 7, name: "65S455", vendorID: 20588, productID: 38483, serial: 0, isBuiltIn: false, isMain: false, isTV: true, isHDMI: true)
        let builtIn = DisplayInfo(id: 1, name: "Color LCD", vendorID: 1552, productID: 41055, serial: 4251086178, isBuiltIn: true, isMain: false, isTV: false, isHDMI: false)
        let fbs = [
            FramebufferEntry(name: "dispext0", productID: 41200, serial: 825640780, entry: 10),
            FramebufferEntry(name: "dispext1", productID: 38483, serial: 0, entry: 11),
            FramebufferEntry(name: "disp0", productID: nil, serial: nil, entry: 12),
        ]
        let services = [
            AVServiceEntry(path: "…/dispext1:dcpav-service-epic:0/DCPAVServiceProxy", entry: 21),
            AVServiceEntry(path: Self.dellPath, entry: 20),
        ]
        let matched = DisplayMatcher.match(displays: [dell, tv, builtIn], framebuffers: fbs, services: services)
        XCTAssertEqual(matched[5]?.entry, 20)
        XCTAssertEqual(matched[7]?.entry, 21)
        XCTAssertNil(matched[1], "the built-in panel never gets a DDC service")
    }

    func testSingleExternalFallbackWhenAttributesAreMissing() {
        // Some framebuffers publish no ProductAttributes (seen on this Mac for idle dispext slots).
        let dell = DisplayInfo(id: 5, name: "DELL U3818DW", vendorID: 4268, productID: 41200, serial: 825640780, isBuiltIn: false, isMain: true, isTV: false, isHDMI: true)
        let fbs = [FramebufferEntry(name: "dispext0", productID: nil, serial: nil, entry: 10)]
        let services = [AVServiceEntry(path: Self.dellPath, entry: 20)]
        XCTAssertEqual(DisplayMatcher.match(displays: [dell], framebuffers: fbs, services: services)[5]?.entry, 20)
    }

    func testNoFallbackWithTwoExternals() {
        let a = DisplayInfo(id: 5, name: "A", vendorID: 1, productID: 1, serial: 1, isBuiltIn: false, isMain: true, isTV: false, isHDMI: true)
        let b = DisplayInfo(id: 6, name: "B", vendorID: 2, productID: 2, serial: 2, isBuiltIn: false, isMain: false, isTV: false, isHDMI: true)
        let fbs = [FramebufferEntry(name: "dispext0", productID: nil, serial: nil, entry: 10)]
        let services = [AVServiceEntry(path: Self.dellPath, entry: 20)]
        XCTAssertTrue(DisplayMatcher.match(displays: [a, b], framebuffers: fbs, services: services).isEmpty)
    }

    func testDisplayInfoFromCoreDisplayDictionary() {
        let dict: [String: Any] = [
            "DisplayProductName": ["en_US": "DELL U3818DW"],
            "DisplayVendorID": 4268, "DisplayProductID": 41200, "DisplaySerialNumber": 825640780,
            "DisplayIsTV": 0, "IODisplayIsHDMISink": 1,
        ]
        let info = DisplayInfo.from(dictionary: dict, id: 5, isBuiltIn: false, isMain: true)
        XCTAssertEqual(info.name, "DELL U3818DW")
        XCTAssertEqual(info.productID, 41200)
        XCTAssertEqual(info.serial, 825640780)
        XCTAssertFalse(info.isTV)
        XCTAssertTrue(info.isHDMI)
    }

    func testDisplayInfoNameFallsBackToPlainStringAndGeneric() {
        XCTAssertEqual(DisplayInfo.from(dictionary: ["DisplayProductName": "X"], id: 1, isBuiltIn: false, isMain: false).name, "X")
        XCTAssertEqual(DisplayInfo.from(dictionary: [:], id: 1, isBuiltIn: true, isMain: false).name, "Built-in Display")
        XCTAssertEqual(DisplayInfo.from(dictionary: [:], id: 1, isBuiltIn: false, isMain: false).name, "Display 1")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter DisplayMatcherTests 2>&1 | tail -3`
Expected: compile error `cannot find 'DisplayInfo'`.

- [ ] **Step 3: Implement `DisplayInfo.swift`**

```swift
import Foundation
import CoreGraphics

/// What the app knows about one attached display, from CoreDisplay's info
/// dictionary (the same source `system_profiler` reads).
public struct DisplayInfo: Equatable, Identifiable {
    public let id: CGDirectDisplayID
    public let name: String
    public let vendorID: UInt32
    public let productID: UInt32
    public let serial: UInt32
    public let isBuiltIn: Bool
    public let isMain: Bool
    public let isTV: Bool
    public let isHDMI: Bool

    public init(id: CGDirectDisplayID, name: String, vendorID: UInt32, productID: UInt32, serial: UInt32,
                isBuiltIn: Bool, isMain: Bool, isTV: Bool, isHDMI: Bool) {
        self.id = id; self.name = name; self.vendorID = vendorID; self.productID = productID; self.serial = serial
        self.isBuiltIn = isBuiltIn; self.isMain = isMain; self.isTV = isTV; self.isHDMI = isHDMI
    }

    /// `DisplayProductName` is a locale → name dictionary on real hardware, a
    /// plain string on some virtual displays, and absent on the built-in panel.
    public static func from(dictionary d: [String: Any], id: CGDirectDisplayID, isBuiltIn: Bool, isMain: Bool) -> DisplayInfo {
        let name: String
        if let names = d["DisplayProductName"] as? [String: String], let first = names.values.sorted().first {
            name = first
        } else if let plain = d["DisplayProductName"] as? String {
            name = plain
        } else {
            name = isBuiltIn ? "Built-in Display" : "Display \(id)"
        }
        func number(_ key: String) -> UInt32 { UInt32(truncatingIfNeeded: (d[key] as? NSNumber)?.int64Value ?? 0) }
        func flag(_ key: String) -> Bool { ((d[key] as? NSNumber)?.boolValue) ?? false }
        return DisplayInfo(id: id, name: name,
                           vendorID: number("DisplayVendorID"), productID: number("DisplayProductID"),
                           serial: number("DisplaySerialNumber"),
                           isBuiltIn: isBuiltIn, isMain: isMain,
                           isTV: flag("DisplayIsTV"), isHDMI: flag("IODisplayIsHDMISink"))
    }
}

/// `CoreDisplay_DisplayCreateInfoDictionary` — private, so resolved at runtime.
public enum CoreDisplayInfo {
    private typealias Create = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    private static let create: Create? = {
        guard let h = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW),
              let sym = dlsym(h, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        return unsafeBitCast(sym, to: Create.self)
    }()

    public static var isAvailable: Bool { create != nil }

    public static func dictionary(for id: CGDirectDisplayID) -> [String: Any]? {
        create?(id)?.takeRetainedValue() as? [String: Any]
    }

    public static func info(for id: CGDirectDisplayID) -> DisplayInfo {
        DisplayInfo.from(dictionary: dictionary(for: id) ?? [:], id: id,
                         isBuiltIn: CGDisplayIsBuiltin(id) != 0, isMain: CGDisplayIsMain(id) != 0)
    }
}
```

- [ ] **Step 4: Implement `DisplayMatcher.swift`**

```swift
import Foundation
import CoreGraphics

/// A framebuffer (`IOMobileFramebufferShim` / `AppleCLCD2`) as found in the
/// IORegistry: its node name (`dispext0`) and the identity it publishes under
/// `DisplayAttributes.ProductAttributes`, when it publishes one.
public struct FramebufferEntry: Equatable {
    public let name: String
    public let productID: UInt32?
    public let serial: UInt32?
    public let entry: UInt32
    public init(name: String, productID: UInt32?, serial: UInt32?, entry: UInt32) {
        self.name = name; self.productID = productID; self.serial = serial; self.entry = entry
    }
}

/// A `DCPAVServiceProxy` with `Location = External`.
public struct AVServiceEntry: Equatable {
    public let path: String
    public let entry: UInt32
    public init(path: String, entry: UInt32) { self.path = path; self.entry = entry }
}

/// Which AV service belongs to which display. The service's registry path
/// names its framebuffer (`…/dispext0:dcpav-service-epic:0/…`); the framebuffer
/// carries the product ID and serial that CoreDisplay reports for the display.
public enum DisplayMatcher {
    public static func framebufferName(inAVServicePath path: String) -> String? {
        guard let range = path.range(of: #"(disp(?:ext)?\d+):dcpav-service-epic"#, options: .regularExpression) else { return nil }
        return String(path[range]).components(separatedBy: ":").first
    }

    public static func match(displays: [DisplayInfo], framebuffers: [FramebufferEntry], services: [AVServiceEntry]) -> [CGDirectDisplayID: AVServiceEntry] {
        var result: [CGDirectDisplayID: AVServiceEntry] = [:]
        let externals = displays.filter { !$0.isBuiltIn }
        for service in services {
            guard let fbName = framebufferName(inAVServicePath: service.path),
                  let fb = framebuffers.first(where: { $0.name == fbName }) else { continue }
            if let pid = fb.productID, let serial = fb.serial,
               let display = externals.first(where: { $0.productID == pid && $0.serial == serial }) {
                result[display.id] = service
            }
        }
        // One external display and one external service: the pairing is forced
        // even when the framebuffer publishes no attributes.
        if result.isEmpty, externals.count == 1, services.count == 1 {
            result[externals[0].id] = services[0]
        }
        return result
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter DisplayMatcherTests 2>&1 | tail -3`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/MonitorLizardCore/DisplayInfo.swift Sources/MonitorLizardCore/DisplayMatcher.swift Tests/MonitorLizardCoreTests/DisplayMatcherTests.swift
git commit -m "core: DisplayInfo from CoreDisplay and the display/AV-service matcher"
```

---

### Task 6: IORegistry scanner (real framebuffers and AV services)

**Files:**
- Create: `Sources/MonitorLizardCore/IORegistryScanner.swift`
- Test: `Tests/MonitorLizardCoreTests/IORegistryScannerTests.swift`

**Interfaces:**
- Consumes: `FramebufferEntry`, `AVServiceEntry`, `DisplayMatcher`, `IOAVTransport`, `DDCService`.
- Produces:
  ```swift
  public enum IORegistryScanner {
      public static func framebuffers() -> [FramebufferEntry]   // caller must not release .entry; scanner retains for process lifetime via IOObjectRetain
      public static func externalAVServices() -> [AVServiceEntry]
      public static func makeDDCServices(for displays: [DisplayInfo]) -> [CGDirectDisplayID: DDCService]
  }
  ```

- [ ] **Step 1: Write the failing test (this Mac has exactly one external service while the Dell is attached)**

```swift
import XCTest
@testable import MonitorLizardCore

final class IORegistryScannerTests: XCTestCase {
    func testFindsFramebuffersAndTheExternalService() throws {
        let fbs = IORegistryScanner.framebuffers()
        XCTAssertTrue(fbs.contains { $0.name.hasPrefix("disp") }, "no framebuffers found: \(fbs)")
        let services = IORegistryScanner.externalAVServices()
        for s in services { XCTAssertNotNil(DisplayMatcher.framebufferName(inAVServicePath: s.path), s.path) }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter IORegistryScannerTests 2>&1 | tail -3`
Expected: compile error `cannot find 'IORegistryScanner'`.

- [ ] **Step 3: Implement `IORegistryScanner.swift`**

```swift
import Foundation
import IOKit
import CoreGraphics

/// Reads the two kinds of IORegistry node the matcher needs. Entries are
/// retained (`IOObjectRetain`) for the life of the process — a handful of
/// kernel objects — and looked up fresh on every re-enumeration.
public enum IORegistryScanner {
    public static func framebuffers() -> [FramebufferEntry] {
        var out: [FramebufferEntry] = []
        for cls in ["IOMobileFramebufferShim", "AppleCLCD2"] {
            forEachService(matching: cls) { entry in
                let attrs = property(entry, "DisplayAttributes") as? [String: Any]
                let product = attrs?["ProductAttributes"] as? [String: Any]
                out.append(FramebufferEntry(
                    name: nodeName(entry),
                    productID: (product?["ProductID"] as? NSNumber).map { UInt32(truncating: $0) },
                    serial: (product?["SerialNumber"] as? NSNumber).map { UInt32(truncating: $0) },
                    entry: entry))
            }
        }
        return out
    }

    public static func externalAVServices() -> [AVServiceEntry] {
        var out: [AVServiceEntry] = []
        forEachService(matching: "DCPAVServiceProxy") { entry in
            guard property(entry, "Location") as? String == "External" else { IOObjectRelease(entry); return }
            out.append(AVServiceEntry(path: path(entry), entry: entry))
        }
        return out
    }

    public static func makeDDCServices(for displays: [DisplayInfo]) -> [CGDirectDisplayID: DDCService] {
        let matched = DisplayMatcher.match(displays: displays, framebuffers: framebuffers(), services: externalAVServices())
        var out: [CGDirectDisplayID: DDCService] = [:]
        for (id, service) in matched {
            if let transport = IOAVTransport(service: service.entry) {
                out[id] = DDCService(transport: transport)
            } else {
                Log.ddc.error("IOAVServiceCreateWithService failed for display \(id)")
            }
        }
        return out
    }

    // MARK: - IOKit helpers

    /// The parent node's name is the framebuffer's name (`dispext0@B0000000` → `dispext0`);
    /// `IOMobileFramebufferShim` itself is a child of that node.
    private static func nodeName(_ entry: io_registry_entry_t) -> String {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return "" }
        defer { IOObjectRelease(parent) }
        var name = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(parent, &name)
        return String(cString: name).components(separatedBy: "@").first ?? ""
    }

    private static func path(_ entry: io_registry_entry_t) -> String {
        var buf = [CChar](repeating: 0, count: 1024)
        IORegistryEntryGetPath(entry, kIOServicePlane, &buf)
        return String(cString: buf)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Hands each matching service to `body` retained; `body` owns the release.
    private static func forEachService(matching cls: String, _ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let s = IOIteratorNext(iterator), s != 0 { body(s) }
    }
}
```

- [ ] **Step 4: Run the test**

Run: `swift test --filter IORegistryScannerTests 2>&1 | tail -3`
Expected: `Executed 1 test, with 0 failures`. If `nodeName` returns `""` for every entry, print the parent name and adjust the split — the path on this Mac is `…/dispext0@B0000000/IOMobileFramebufferShim`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MonitorLizardCore/IORegistryScanner.swift Tests/MonitorLizardCoreTests/IORegistryScannerTests.swift
git commit -m "core: IORegistry scanner for framebuffers and external AV services"
```

---

### Task 7: Mode planner (`DisplayModes.swift`)

**Files:**
- Create: `Sources/MonitorLizardCore/DisplayModes.swift`
- Test: `Tests/MonitorLizardCoreTests/DisplayModesTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct ModeSpec: Equatable, Hashable {
      public let index: Int            // position in the CGDisplayCopyAllDisplayModes array
      public let width: Int, height: Int, pixelWidth: Int, pixelHeight: Int
      public let refresh: Double
      public let usable: Bool
      public var isHiDPI: Bool { pixelWidth == 2 * width }
      public var label: String         // "2560×1067"
  }
  public struct ModePlan: Equatable {
      public let native: ModeSpec?
      public let hiDPI: [ModeSpec]     // slider stops, width ascending
      public let lowRes: [ModeSpec]    // same-aspect low-resolution modes
      public let current: ModeSpec?
      public func stopIndex(of mode: ModeSpec) -> Int?
  }
  public enum DisplayModes {
      public static let aspectTolerance = 0.01
      public static func plan(all: [ModeSpec], current: ModeSpec?) -> ModePlan
      public static func specs(for id: CGDirectDisplayID) -> (all: [ModeSpec], current: ModeSpec?, modes: [CGDisplayMode])
      public static func apply(_ spec: ModeSpec, modes: [CGDisplayMode], to id: CGDirectDisplayID) -> CGError
  }
  ```

- [ ] **Step 1: Write the failing tests with the Dell fixture**

```swift
import XCTest
@testable import MonitorLizardCore

final class DisplayModesTests: XCTestCase {
    /// (w, h, pw, ph, hz, usable) — CGDisplayCopyAllDisplayModes for the DELL U3818DW, 2026-09-12.
    static let dell: [(Int, Int, Int, Int, Double, Bool)] = [
        (800,600,1600,1200,60,true),(800,600,1600,1200,30,true),(960,540,1920,1080,60,true),(960,540,1920,1080,50,true),
        (1280,533,2560,1066,60,true),(1280,533,2560,1066,30,true),(1280,540,2560,1080,60,true),(1280,720,2560,1440,60,true),
        (1504,627,3008,1254,60,true),(1504,627,3008,1254,30,true),(1600,667,3200,1334,60,true),(1600,667,3200,1334,30,true),
        (1680,700,3360,1400,60,true),(1680,700,3360,1400,30,true),(1920,800,3840,1600,60,true),(1920,800,3840,1600,30,true),
        (2048,853,4096,1706,60,true),(2048,853,4096,1706,30,true),(2304,960,4608,1920,60,true),(2304,960,4608,1920,30,true),
        (2560,1066,2560,1066,60,true),(2560,1066,2560,1066,30,true),(2560,1067,5120,2134,60,true),(2560,1067,5120,2134,30,true),
        (2560,1080,2560,1080,60,true),(2560,1440,2560,1440,60,true),(3008,1253,6016,2506,60,true),(3008,1253,6016,2506,30,true),
        (3008,1254,3008,1254,60,true),(3008,1254,3008,1254,30,true),(3200,1333,6400,2666,60,true),(3200,1333,6400,2666,30,true),
        (3200,1334,3200,1334,60,true),(3200,1334,3200,1334,30,true),(3360,1400,6720,2800,60,true),(3360,1400,3360,1400,60,true),
        (3360,1400,6720,2800,30,true),(3360,1400,3360,1400,30,true),(3840,1600,3840,1600,60,true),(3840,1600,3840,1600,30,true),
        (400,300,800,600,75,false),(512,384,1024,768,60,false),(640,480,1280,960,60,false),(1024,427,2048,854,60,false),
    ]
    static var specs: [ModeSpec] {
        dell.enumerated().map { i, m in ModeSpec(index: i, width: m.0, height: m.1, pixelWidth: m.2, pixelHeight: m.3, refresh: m.4, usable: m.5) }
    }
    static var current: ModeSpec { specs.first { $0.width == 2560 && $0.height == 1067 && $0.refresh == 60 }! }

    func testNativeIsTheLargestLowResMode() {
        let plan = DisplayModes.plan(all: Self.specs, current: Self.current)
        XCTAssertEqual(plan.native?.width, 3840)
        XCTAssertEqual(plan.native?.height, 1600)
        XCTAssertEqual(plan.native?.refresh, 60)
    }

    func testHiDPIStopsAreSameAspectDedupedAndOrdered() {
        let plan = DisplayModes.plan(all: Self.specs, current: Self.current)
        XCTAssertEqual(plan.hiDPI.map(\.width), [1280, 1504, 1600, 1680, 1920, 2048, 2304, 2560, 3008, 3200, 3360])
        XCTAssertTrue(plan.hiDPI.allSatisfy { $0.refresh == 60 }, "prefer the current refresh rate")
        XCTAssertTrue(plan.hiDPI.allSatisfy(\.isHiDPI))
    }

    func testLowResListIsSameAspectAndIncludesNative() {
        let plan = DisplayModes.plan(all: Self.specs, current: Self.current)
        XCTAssertEqual(plan.lowRes.map(\.width), [2560, 3008, 3200, 3360, 3840])
        XCTAssertFalse(plan.lowRes.contains { $0.width == 2560 && $0.height == 1080 }, "2560×1080 is 2.37:1, off by > 1 %")
    }

    func testUnusableModesNeverAppear() {
        let plan = DisplayModes.plan(all: Self.specs, current: Self.current)
        XCTAssertFalse((plan.hiDPI + plan.lowRes).contains { !$0.usable })
    }

    func testCurrentStopIndex() {
        let plan = DisplayModes.plan(all: Self.specs, current: Self.current)
        XCTAssertEqual(plan.stopIndex(of: Self.current), 7)
        XCTAssertEqual(plan.current, Self.current)
    }

    func testFallsBackToHighestRefreshWhenCurrentRateIsAbsent() {
        // Current at 30 Hz; the 1280×720-style oddballs are gone, but every stop has a 30 Hz twin, so all stops pick 30.
        let current30 = Self.specs.first { $0.width == 2560 && $0.height == 1067 && $0.refresh == 30 }!
        let plan = DisplayModes.plan(all: Self.specs, current: current30)
        XCTAssertTrue(plan.hiDPI.allSatisfy { $0.refresh == 30 })
        // With no current mode at all, the highest rate wins.
        XCTAssertTrue(DisplayModes.plan(all: Self.specs, current: nil).hiDPI.allSatisfy { $0.refresh == 60 })
    }

    func testEmptyInput() {
        let plan = DisplayModes.plan(all: [], current: nil)
        XCTAssertNil(plan.native); XCTAssertTrue(plan.hiDPI.isEmpty); XCTAssertTrue(plan.lowRes.isEmpty)
    }

    func testLabel() {
        XCTAssertEqual(Self.current.label, "2560×1067")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter DisplayModesTests 2>&1 | tail -3`
Expected: compile error `cannot find 'ModeSpec'`.

- [ ] **Step 3: Implement `DisplayModes.swift`**

```swift
import Foundation
import CoreGraphics

/// One CGDisplayMode, reduced to what the planner needs. `index` points back
/// into the array the mode came from so `apply` can find the real object.
public struct ModeSpec: Equatable, Hashable {
    public let index: Int
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refresh: Double
    public let usable: Bool

    public init(index: Int, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refresh: Double, usable: Bool) {
        self.index = index; self.width = width; self.height = height
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.refresh = refresh; self.usable = usable
    }

    public var isHiDPI: Bool { pixelWidth == 2 * width }
    public var aspect: Double { Double(width) / Double(height) }
    public var label: String { "\(width)×\(height)" }
}

public struct ModePlan: Equatable {
    public let native: ModeSpec?
    public let hiDPI: [ModeSpec]
    public let lowRes: [ModeSpec]
    public let current: ModeSpec?

    /// Position of `mode`'s size among the HiDPI stops (refresh ignored).
    public func stopIndex(of mode: ModeSpec) -> Int? {
        hiDPI.firstIndex { $0.width == mode.width && $0.height == mode.height }
    }
}

/// Turns the raw mode list into the slider's stops and the picker's rows.
/// Letterboxed aspect ratios are dropped everywhere; nobody wants 1280×720 on
/// a 21:9 panel from a slider.
public enum DisplayModes {
    public static let aspectTolerance = 0.01

    public static func plan(all: [ModeSpec], current: ModeSpec?) -> ModePlan {
        let usable = all.filter(\.usable)
        let native = usable.filter { !$0.isHiDPI }.max { a, b in
            (a.pixelWidth * a.pixelHeight, a.refresh) < (b.pixelWidth * b.pixelHeight, b.refresh)
        }
        guard let native else { return ModePlan(native: nil, hiDPI: [], lowRes: [], current: current) }
        let sameAspect = usable.filter { abs($0.aspect - native.aspect) / native.aspect <= aspectTolerance }
        return ModePlan(native: native,
                        hiDPI: dedup(sameAspect.filter(\.isHiDPI), preferring: current?.refresh),
                        lowRes: dedup(sameAspect.filter { !$0.isHiDPI }, preferring: current?.refresh),
                        current: current)
    }

    /// One mode per (width, height): the one at the preferred refresh rate if
    /// it exists, else the fastest. Ordered by width, then height.
    private static func dedup(_ modes: [ModeSpec], preferring refresh: Double?) -> [ModeSpec] {
        let groups = Dictionary(grouping: modes) { "\($0.width)x\($0.height)" }
        return groups.values.compactMap { group -> ModeSpec? in
            if let refresh, let exact = group.first(where: { $0.refresh == refresh }) { return exact }
            return group.max { $0.refresh < $1.refresh }
        }
        .sorted { ($0.width, $0.height) < ($1.width, $1.height) }
    }

    // MARK: - CoreGraphics

    public static func specs(for id: CGDirectDisplayID) -> (all: [ModeSpec], current: ModeSpec?, modes: [CGDisplayMode]) {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        let all = modes.enumerated().map { i, m in
            ModeSpec(index: i, width: m.width, height: m.height, pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight,
                     refresh: m.refreshRate, usable: m.isUsableForDesktopGUI())
        }
        let current = CGDisplayCopyDisplayMode(id).flatMap { cur in
            all.first { $0.width == cur.width && $0.height == cur.height && $0.pixelWidth == cur.pixelWidth && $0.refresh == cur.refreshRate }
        }
        return (all, current, modes)
    }

    public static func apply(_ spec: ModeSpec, modes: [CGDisplayMode], to id: CGDirectDisplayID) -> CGError {
        guard modes.indices.contains(spec.index) else { return .illegalArgument }
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else { return err }
        err = CGConfigureDisplayWithDisplayMode(config, id, modes[spec.index], nil)
        guard err == .success else { CGCancelDisplayConfiguration(config); return err }
        err = CGCompleteDisplayConfiguration(config, .forSession)
        Log.modes.info("display \(id) → \(spec.label) @\(spec.refresh) HiDPI=\(spec.isHiDPI) rc=\(err.rawValue)")
        return err
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter DisplayModesTests 2>&1 | tail -3`
Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MonitorLizardCore/DisplayModes.swift Tests/MonitorLizardCoreTests/DisplayModesTests.swift
git commit -m "core: HiDPI mode planner with the Dell's mode list as fixture"
```

---

### Task 8: TV-role state and override plist (`TVRole.swift`)

**Files:**
- Create: `Sources/MonitorLizardCore/TVRole.swift`
- Test: `Tests/MonitorLizardCoreTests/TVRoleTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo`.
- Produces:
  ```swift
  public enum TVRoleState: Equatable { case ok, blocked, fixedPendingReconnect, skipped }
  public enum OverridePlist {
      public static let root = "/Library/Displays/Contents/Resources/Overrides"
      public static func path(vendorID: UInt32, productID: UInt32) -> String
      public static func contents(vendorID: UInt32, productID: UInt32) -> Data   // XML plist
  }
  public final class TVRoleTracker {
      public init(fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
      public func state(for display: DisplayInfo) -> TVRoleState
      public func markSkipped(_ display: DisplayInfo)
      public func clearSkipped(_ display: DisplayInfo)
      public func needsFix(_ display: DisplayInfo) -> Bool      // blocked and not skipped
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MonitorLizardCore

final class TVRoleTests: XCTestCase {
    let dellHDMI = DisplayInfo(id: 5, name: "DELL U3818DW", vendorID: 4268, productID: 41200, serial: 1, isBuiltIn: false, isMain: true, isTV: true, isHDMI: true)
    let dellOK = DisplayInfo(id: 5, name: "DELL U3818DW", vendorID: 4268, productID: 41200, serial: 1, isBuiltIn: false, isMain: true, isTV: false, isHDMI: true)

    func testOverridePathUsesLowercaseHex() {
        XCTAssertEqual(OverridePlist.path(vendorID: 4268, productID: 41200),
                       "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-10ac/DisplayProductID-a0f0")
        XCTAssertEqual(OverridePlist.path(vendorID: 4268, productID: 41204),
                       "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-10ac/DisplayProductID-a0f4")
    }

    func testOverrideContentsMatchBetterDisplaysFile() throws {
        let data = OverridePlist.contents(vendorID: 4268, productID: 41200)
        let dict = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(dict["DisplayIsTV"] as? Bool, false)
        XCTAssertEqual(dict["DisplayVendorID"] as? Int, 4268)
        XCTAssertEqual(dict["DisplayProductID"] as? Int, 41200)
        XCTAssertEqual(dict.count, 3)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix("<?xml"))
    }

    func testStates() {
        var exists = false
        let tracker = TVRoleTracker(fileExists: { _ in exists })
        XCTAssertEqual(tracker.state(for: dellOK), .ok)
        XCTAssertEqual(tracker.state(for: dellHDMI), .blocked)
        XCTAssertTrue(tracker.needsFix(dellHDMI))
        exists = true
        XCTAssertEqual(tracker.state(for: dellHDMI), .fixedPendingReconnect)
        XCTAssertFalse(tracker.needsFix(dellHDMI))
    }

    func testSkippedUntilCleared() {
        let tracker = TVRoleTracker(fileExists: { _ in false })
        tracker.markSkipped(dellHDMI)
        XCTAssertEqual(tracker.state(for: dellHDMI), .skipped)
        XCTAssertFalse(tracker.needsFix(dellHDMI))
        tracker.clearSkipped(dellHDMI)
        XCTAssertEqual(tracker.state(for: dellHDMI), .blocked)
    }

    func testSkippedIsKeyedByModelNotDisplayID() {
        let tracker = TVRoleTracker(fileExists: { _ in false })
        tracker.markSkipped(dellHDMI)
        let sameModelNewID = DisplayInfo(id: 9, name: "DELL U3818DW", vendorID: 4268, productID: 41200, serial: 1, isBuiltIn: false, isMain: false, isTV: true, isHDMI: true)
        XCTAssertEqual(tracker.state(for: sameModelNewID), .skipped)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter TVRoleTests 2>&1 | tail -3`
Expected: compile error `cannot find 'OverridePlist'`.

- [ ] **Step 3: Implement `TVRole.swift`**

```swift
import Foundation

/// Whether Night Shift can work on a display, and what the app has done about it.
public enum TVRoleState: Equatable {
    case ok                      // macOS treats it as a monitor
    case blocked                 // flagged as a TV, no override on disk
    case fixedPendingReconnect   // override on disk; takes effect on the next attach
    case skipped                 // blocked, and the admin prompt was cancelled this launch
}

/// The per-model override macOS reads at display attach. Same file, same
/// three keys, as BetterDisplay's "display role: computer monitor" writes, so
/// an existing file counts as already fixed.
public enum OverridePlist {
    public static let root = "/Library/Displays/Contents/Resources/Overrides"

    public static func path(vendorID: UInt32, productID: UInt32) -> String {
        "\(root)/DisplayVendorID-\(String(vendorID, radix: 16))/DisplayProductID-\(String(productID, radix: 16))"
    }

    public static func contents(vendorID: UInt32, productID: UInt32) -> Data {
        let dict: [String: Any] = ["DisplayIsTV": false, "DisplayVendorID": Int(vendorID), "DisplayProductID": Int(productID)]
        // A fresh plist of three scalars cannot fail to serialise.
        return try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }
}

public final class TVRoleTracker {
    private let fileExists: (String) -> Bool
    private var skipped: Set<String> = []

    public init(fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.fileExists = fileExists
    }

    private func key(_ d: DisplayInfo) -> String { "\(d.vendorID):\(d.productID)" }

    public func state(for display: DisplayInfo) -> TVRoleState {
        guard display.isTV else { return .ok }
        if fileExists(OverridePlist.path(vendorID: display.vendorID, productID: display.productID)) { return .fixedPendingReconnect }
        return skipped.contains(key(display)) ? .skipped : .blocked
    }

    public func markSkipped(_ display: DisplayInfo) { skipped.insert(key(display)) }
    public func clearSkipped(_ display: DisplayInfo) { skipped.remove(key(display)) }
    public func needsFix(_ display: DisplayInfo) -> Bool { state(for: display) == .blocked }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter TVRoleTests 2>&1 | tail -3`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MonitorLizardCore/TVRole.swift Tests/MonitorLizardCoreTests/TVRoleTests.swift
git commit -m "core: TV-role state machine and override plist"
```

---

### Task 9: Built-in brightness and Night Shift backends

**Files:**
- Create: `Sources/MonitorLizardCore/BuiltInBrightness.swift`, `Sources/MonitorLizardCore/NightShift.swift`
- Test: `Tests/MonitorLizardCoreTests/PrivateBackendsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public protocol BrightnessBackend: AnyObject {
      var isAvailable: Bool { get }
      func canChange(_ id: CGDirectDisplayID) -> Bool
      func brightness(_ id: CGDirectDisplayID) -> Float?      // 0…1
      func setBrightness(_ id: CGDirectDisplayID, _ value: Float) -> Bool
  }
  public final class DisplayServicesBrightness: BrightnessBackend { public init() }

  public struct NightShiftStatus: Equatable { public let available: Bool; public let enabled: Bool; public let active: Bool; public let strength: Float }
  public protocol NightShiftBackend: AnyObject {
      var isAvailable: Bool { get }
      func status() -> NightShiftStatus
      func setEnabled(_ enabled: Bool) -> Bool
      func setStrength(_ strength: Float) -> Bool
      func onChange(_ handler: @escaping () -> Void)
  }
  public final class CoreBrightnessNightShift: NightShiftBackend { public init?() }   // nil if the class is missing
  ```

- [ ] **Step 1: Write the failing smoke tests**

```swift
import XCTest
@testable import MonitorLizardCore

final class PrivateBackendsTests: XCTestCase {
    func testDisplayServicesResolves() {
        XCTAssertTrue(DisplayServicesBrightness().isAvailable)
    }

    func testNightShiftStatusReadsSanely() throws {
        let ns = try XCTUnwrap(CoreBrightnessNightShift())
        let s = ns.status()
        XCTAssertTrue(s.available, "this Mac supports Night Shift")
        XCTAssertTrue((0...1).contains(s.strength))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PrivateBackendsTests 2>&1 | tail -3`
Expected: compile error `cannot find 'DisplayServicesBrightness'`.

- [ ] **Step 3: Implement `BuiltInBrightness.swift`**

```swift
import Foundation
import CoreGraphics

public protocol BrightnessBackend: AnyObject {
    var isAvailable: Bool { get }
    func canChange(_ id: CGDirectDisplayID) -> Bool
    func brightness(_ id: CGDirectDisplayID) -> Float?
    func setBrightness(_ id: CGDirectDisplayID, _ value: Float) -> Bool
}

/// DisplayServices.framework (private) — what Control Center uses for the
/// built-in panel. `BrightnessChanged` is posted after a set so Control
/// Center's own slider follows.
public final class DisplayServicesBrightness: BrightnessBackend {
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias Changed = @convention(c) (CGDirectDisplayID, Double) -> Void

    private let canChangeFn: CanChange?
    private let getFn: Get?
    private let setFn: Set?
    private let changedFn: Changed?

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        func sym<T>(_ name: String) -> T? {
            guard let handle, let s = dlsym(handle, name) else { return nil }
            return unsafeBitCast(s, to: T.self)
        }
        canChangeFn = sym("DisplayServicesCanChangeBrightness")
        getFn = sym("DisplayServicesGetBrightness")
        setFn = sym("DisplayServicesSetBrightness")
        changedFn = sym("DisplayServicesBrightnessChanged")
    }

    public var isAvailable: Bool { getFn != nil && setFn != nil }

    public func canChange(_ id: CGDirectDisplayID) -> Bool { canChangeFn?(id) ?? false }

    public func brightness(_ id: CGDirectDisplayID) -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(id, &value) == 0 ? value : nil
    }

    public func setBrightness(_ id: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let setFn, setFn(id, max(0, min(1, value))) == 0 else { return false }
        changedFn?(id, Double(value))
        return true
    }
}
```

- [ ] **Step 4: Implement `NightShift.swift`**

```swift
import Foundation

public struct NightShiftStatus: Equatable {
    public let available: Bool
    public let enabled: Bool
    public let active: Bool
    public let strength: Float
    public init(available: Bool, enabled: Bool, active: Bool, strength: Float) {
        self.available = available; self.enabled = enabled; self.active = active; self.strength = strength
    }
}

public protocol NightShiftBackend: AnyObject {
    var isAvailable: Bool { get }
    func status() -> NightShiftStatus
    func setEnabled(_ enabled: Bool) -> Bool
    func setStrength(_ strength: Float) -> Bool
    func onChange(_ handler: @escaping () -> Void)
}

/// `CBBlueLightClient`'s status struct, as laid out in CoreBrightness (the
/// layout the `nightlight` CLI uses; sanity-checked at runtime by `status()`).
private struct BlueLightTime { var hour: Int32; var minute: Int32 }
private struct BlueLightSchedule { var from: BlueLightTime; var to: BlueLightTime }
private struct BlueLightStatusData {
    var active: Bool
    var enabled: Bool
    var sunSchedulePermitted: Bool
    var mode: Int32
    var schedule: BlueLightSchedule
    var disableFlags: UInt64
    var available: Bool
}

/// The private class's selectors, expressed as an @objc protocol so the
/// existential is a plain object pointer and `unsafeBitCast` is legal.
@objc private protocol BlueLightClient {
    func setEnabled(_ enabled: Bool) -> Bool
    func setStrength(_ strength: Float, commit: Bool) -> Bool
    func getStrength(_ strength: UnsafeMutablePointer<Float>) -> Bool
    func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
    func setStatusNotificationBlock(_ block: @escaping @convention(block) () -> Void)
}

public final class CoreBrightnessNightShift: NightShiftBackend {
    private let client: BlueLightClient
    private var handlers: [() -> Void] = []

    public init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        let object = cls.init()
        client = unsafeBitCast(object, to: BlueLightClient.self)
        client.setStatusNotificationBlock { [weak self] in
            DispatchQueue.main.async { self?.handlers.forEach { $0() } }
        }
    }

    public var isAvailable: Bool { status().available }

    public func status() -> NightShiftStatus {
        var data = BlueLightStatusData(active: false, enabled: false, sunSchedulePermitted: false, mode: 0,
                                       schedule: .init(from: .init(hour: 0, minute: 0), to: .init(hour: 0, minute: 0)),
                                       disableFlags: 0, available: false)
        let ok = withUnsafeMutablePointer(to: &data) { client.getBlueLightStatus(UnsafeMutableRawPointer($0)) }
        var strength: Float = 0
        _ = client.getStrength(&strength)
        guard ok, (0...4).contains(data.mode) else {
            Log.nightshift.error("CBBlueLightClient status looked wrong (ok=\(ok) mode=\(data.mode)); treating Night Shift as unavailable")
            return NightShiftStatus(available: false, enabled: false, active: false, strength: 0)
        }
        return NightShiftStatus(available: data.available, enabled: data.enabled, active: data.active, strength: max(0, min(1, strength)))
    }

    public func setEnabled(_ enabled: Bool) -> Bool { client.setEnabled(enabled) }

    public func setStrength(_ strength: Float) -> Bool { client.setStrength(max(0, min(1, strength)), commit: true) }

    public func onChange(_ handler: @escaping () -> Void) { handlers.append(handler) }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter PrivateBackendsTests 2>&1 | tail -3`
Expected: `Executed 2 tests, with 0 failures`. If `testNightShiftStatusReadsSanely` fails with `available == false`, the struct layout differs on this macOS: dump the raw 64 bytes after the call (`withUnsafeBytes(of: &data) { print(Array($0)) }`), locate the `available`/`enabled` booleans, and adjust `BlueLightStatusData` before proceeding — do not weaken the test.

- [ ] **Step 6: Commit**

```bash
git add Sources/MonitorLizardCore/BuiltInBrightness.swift Sources/MonitorLizardCore/NightShift.swift Tests/MonitorLizardCoreTests/PrivateBackendsTests.swift
git commit -m "core: DisplayServices brightness and CBBlueLightClient Night Shift backends"
```

---

### Task 10: The glyph — `CharacterIcon.monitorLizard` in StatusItemKit

**Files:**
- Modify: `~/Code/StatusItemKit/Sources/StatusItemKit/CharacterIcon.swift` (append before the final `}` of the enum)
- Test: `~/Code/StatusItemKit/Tests/StatusItemKitTests/CharacterIconTests.swift` (add a test)

**Interfaces:**
- Produces: `public static func monitorLizard(brightness: CGFloat, nightShift: Bool, tongue: Bool = false) -> NSImage` — 24×20 canvas, non-template.

- [ ] **Step 1: Add the failing test to `CharacterIconTests.swift`**

```swift
    func testMonitorLizardIsWideNonTemplateAndVariesWithState() {
        let dim = CharacterIcon.monitorLizard(brightness: 0.1, nightShift: false)
        XCTAssertEqual(dim.size, NSSize(width: 24, height: 20))
        XCTAssertFalse(dim.isTemplate)
        let bright = CharacterIcon.monitorLizard(brightness: 1.0, nightShift: false)
        let amber = CharacterIcon.monitorLizard(brightness: 1.0, nightShift: true)
        XCTAssertNotEqual(dim.tiffRepresentation, bright.tiffRepresentation, "the screen fill tracks brightness")
        XCTAssertNotEqual(bright.tiffRepresentation, amber.tiffRepresentation, "Night Shift tints the screen")
        XCTAssertNotEqual(bright.tiffRepresentation, CharacterIcon.monitorLizard(brightness: 1.0, nightShift: false, tongue: true).tiffRepresentation)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/Code/StatusItemKit && swift test --filter CharacterIconTests 2>&1 | tail -3`
Expected: compile error `type 'CharacterIcon' has no member 'monitorLizard'`.

- [ ] **Step 3: Implement the glyph (append inside `public enum CharacterIcon`)**

```swift
    static let amber = NSColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)

    // MONITOR LIZARD: the screen is the lizard's body, a stout head rises from the top bezel, a tail curls
    // out of the stand. The screen fills bottom-up with the main display's brightness; Night Shift turns
    // the fill amber; a forked tongue flicks after a DDC write.
    public static func monitorLizard(brightness: CGFloat, nightShift: Bool, tongue: Bool = false) -> NSImage {
        let level = max(0, min(1, brightness))
        return canvas(width: 24, height: 20) { ctx in
            body.set()
            // Bezel: a rounded rect 15 wide, 10 tall, sitting on a stand.
            let bezel = NSRect(x: 2, y: 5.5, width: 15, height: 10)
            NSBezierPath(roundedRect: bezel, xRadius: 1.6, yRadius: 1.6).fill()
            NSBezierPath(rect: NSRect(x: 8, y: 3.4, width: 3, height: 2.4)).fill()          // neck of the stand
            NSBezierPath(roundedRect: NSRect(x: 5, y: 2.2, width: 9, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill() // foot
            // Head: stout, rising from the top bezel, offset right, with a snout to the right.
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 9.5, y: 15))
            head.curve(to: NSPoint(x: 12.5, y: 19), controlPoint1: NSPoint(x: 9.5, y: 17.6), controlPoint2: NSPoint(x: 10.6, y: 19))
            head.curve(to: NSPoint(x: 17.5, y: 17.4), controlPoint1: NSPoint(x: 14.6, y: 19), controlPoint2: NSPoint(x: 16.6, y: 18.4))
            head.line(to: NSPoint(x: 17.5, y: 15))
            head.close(); head.fill()
            // Tail: out of the stand's right side, curling up and away.
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 13.5, y: 3))
            tail.curve(to: NSPoint(x: 22.5, y: 6.5), controlPoint1: NSPoint(x: 18, y: 2.2), controlPoint2: NSPoint(x: 21.5, y: 3.5))
            tail.lineWidth = 1.7; tail.lineCapStyle = .round; tail.stroke()
            // Screen: cut out, then filled to the brightness level.
            let screen = NSRect(x: 3.4, y: 6.9, width: 12.2, height: 7.2)
            cut(ctx, NSBezierPath(rect: screen))
            if level > 0.02 {
                (nightShift ? amber : body).set()
                NSBezierPath(rect: NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height * level)).fill()
            }
            // Eye.
            cut(ctx, NSBezierPath(ovalIn: NSRect(x: 14.6, y: 16.6, width: 1.5, height: 1.5)))
            if tongue {
                NSColor(red: 0.96, green: 0.42, blue: 0.56, alpha: 1).set()
                let t = NSBezierPath(); t.move(to: NSPoint(x: 17.5, y: 15.8)); t.line(to: NSPoint(x: 21, y: 15.4))
                t.move(to: NSPoint(x: 21, y: 15.4)); t.line(to: NSPoint(x: 22.6, y: 16.2))
                t.move(to: NSPoint(x: 21, y: 15.4)); t.line(to: NSPoint(x: 22.6, y: 14.6))
                t.lineWidth = 0.9; t.lineCapStyle = .round; t.stroke()
            }
        }
    }
```

Also extend the doc comment at the top of the enum: add `the monitor lizard's screen fills with the brightness` to the list of what each character does.

- [ ] **Step 4: Run the StatusItemKit tests**

Run: `swift test 2>&1 | tail -3`
Expected: all pass (`with 0 failures`).

- [ ] **Step 5: Look at it**

Run (from the StatusItemKit repo):
```bash
cat > /tmp/lizard-preview.swift <<'EOF'
import AppKit
@testable import StatusItemKit
EOF
```
Simpler: temporarily render via the site's renderer after Task 16, or eyeball with:
```bash
swift run StatusItemKitDemo 2>/dev/null &
```
is not wired for this glyph, so instead write a 12-line script in the scratchpad that links `Sources/StatusItemKit/CharacterIcon.swift` directly (as `render-glyphs.sh` does) and saves `monitorLizard(brightness: 0.8, nightShift: true, tongue: true)` as a PNG at 4×, then open it. Adjust curves until the head reads as a lizard and the tail as a tail at 1× on the menu bar. Keep the canvas 24×20.

- [ ] **Step 6: Commit in StatusItemKit**

```bash
cd ~/Code/StatusItemKit
git add Sources/StatusItemKit/CharacterIcon.swift Tests/StatusItemKitTests/CharacterIconTests.swift
git commit -m "CharacterIcon: monitor lizard glyph for Monitor Lizard"
```

---

### Task 11: `DisplayModel` — orchestration in the app target

**Files:**
- Create: `Sources/MonitorLizard/DisplayModel.swift`

**Interfaces:**
- Consumes: everything from Tasks 3–9.
- Produces:
  ```swift
  final class DisplayModel {
      struct Entry {
          let info: DisplayInfo
          var ddc: DDCService?
          var ddcUnavailable: Bool
          var brightness: VCPValue?
          var contrast: VCPValue?
          var builtInBrightness: Float?
          var plan: ModePlan
          var modes: [CGDisplayMode]
          var tvState: TVRoleState
          var isExternalControllable: Bool { ddc != nil && !ddcUnavailable }
      }
      private(set) var entries: [Entry]                // main display first
      let nightShift: NightShiftBackend?
      let tvRoles: TVRoleTracker
      var onChange: (() -> Void)?                      // main thread; after any state change
      var onWrite: (() -> Void)?                       // main thread; after a confirmed DDC write (tongue)
      var onNeedsTVFix: ((DisplayInfo) -> Void)?       // main thread; a blocked display appeared
      init(brightness: BrightnessBackend, nightShift: NightShiftBackend?, tvRoles: TVRoleTracker)
      func start()                                     // registers reconfigure + wake observers, enumerates
      func refresh()                                   // re-enumerate everything
      func readValues()                                // async DDC reads for every controllable entry
      func setBrightness(_ id: CGDirectDisplayID, _ value: UInt16)
      func setContrast(_ id: CGDirectDisplayID, _ value: UInt16)
      func setBuiltInBrightness(_ id: CGDirectDisplayID, _ value: Float)
      func apply(_ spec: ModeSpec, to id: CGDirectDisplayID) -> CGError
      var mainBrightnessFraction: CGFloat              // for the glyph, 0…1
      func entry(_ id: CGDirectDisplayID) -> Entry?
  }
  ```

- [ ] **Step 1: Implement `DisplayModel.swift`**

```swift
import AppKit
import CoreGraphics
import MonitorLizardCore

/// Everything the menu shows, refreshed on display reconfiguration and wake.
/// DDC values are read on demand (menu open, after a write), never on a timer.
final class DisplayModel {
    struct Entry {
        let info: DisplayInfo
        var ddc: DDCService?
        var ddcUnavailable = false
        var brightness: VCPValue?
        var contrast: VCPValue?
        var builtInBrightness: Float?
        var plan: ModePlan
        var modes: [CGDisplayMode]
        var tvState: TVRoleState
        var isExternalControllable: Bool { ddc != nil && !ddcUnavailable }
    }

    private(set) var entries: [Entry] = []
    let nightShift: NightShiftBackend?
    let tvRoles: TVRoleTracker
    private let brightness: BrightnessBackend
    var onChange: (() -> Void)?
    var onWrite: (() -> Void)?
    var onNeedsTVFix: ((DisplayInfo) -> Void)?
    private var refreshWork: DispatchWorkItem?

    init(brightness: BrightnessBackend, nightShift: NightShiftBackend?, tvRoles: TVRoleTracker) {
        self.brightness = brightness
        self.nightShift = nightShift
        self.tvRoles = tvRoles
    }

    func start() {
        // Reconfiguration fires several times per change; act once, after the last one.
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard flags.contains(.endConfigurationFlag), let userInfo else { return }
            let model = Unmanaged<DisplayModel>.fromOpaque(userInfo).takeUnretainedValue()
            model.scheduleRefresh()
        }, Unmanaged.passUnretained(self).toOpaque())
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRefresh()
        }
        nightShift?.onChange { [weak self] in self?.onChange?() }
        refresh()
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func refresh() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        let infos = ids.prefix(Int(count)).map { CoreDisplayInfo.info(for: $0) }
            .sorted { $0.isMain && !$1.isMain }
        // Old services are dropped wholesale: after a long sleep the display ids
        // and the AV services behind them are new objects.
        let services = IORegistryScanner.makeDDCServices(for: infos)
        entries = infos.map { info in
            let (all, current, modes) = DisplayModes.specs(for: info.id)
            return Entry(info: info,
                         ddc: info.isBuiltIn ? nil : services[info.id],
                         builtInBrightness: info.isBuiltIn ? brightness.brightness(info.id) : nil,
                         plan: DisplayModes.plan(all: all, current: current),
                         modes: modes,
                         tvState: tvRoles.state(for: info))
        }
        Log.menu.info("enumerated \(self.entries.count) displays, \(services.count) with DDC")
        onChange?()
        for e in entries where tvRoles.needsFix(e.info) { onNeedsTVFix?(e.info) }
        readValues()
    }

    func readValues() {
        for (index, entry) in entries.enumerated() {
            if entry.info.isBuiltIn {
                entries[index].builtInBrightness = brightness.brightness(entry.info.id)
                continue
            }
            guard let ddc = entry.ddc, !entry.ddcUnavailable else { continue }
            let id = entry.info.id
            ddc.read(.brightness) { [weak self] result in
                DispatchQueue.main.async { self?.store(id: id, code: .brightness, result: result) }
                ddc.read(.contrast) { [weak self] result in
                    DispatchQueue.main.async { self?.store(id: id, code: .contrast, result: result) }
                }
            }
        }
    }

    private func store(id: CGDirectDisplayID, code: VCPCode, result: Result<VCPValue, DDCError>) {
        guard let i = entries.firstIndex(where: { $0.info.id == id }) else { return }
        switch result {
        case .success(let value):
            if code == .brightness { entries[i].brightness = value } else { entries[i].contrast = value }
        case .failure(let error):
            Log.ddc.error("display \(id) \(code.rawValue, format: .hex) read failed: \(String(describing: error))")
            entries[i].ddcUnavailable = true
        }
        onChange?()
    }

    func setBrightness(_ id: CGDirectDisplayID, _ value: UInt16) { write(id, .brightness, value) }
    func setContrast(_ id: CGDirectDisplayID, _ value: UInt16) { write(id, .contrast, value) }

    private func write(_ id: CGDirectDisplayID, _ code: VCPCode, _ value: UInt16) {
        guard let entry = entry(id), let ddc = entry.ddc else { return }
        ddc.write(code, value: value) { [weak self] result in
            DispatchQueue.main.async {
                self?.store(id: id, code: code, result: result)
                if case .success = result { self?.onWrite?() }
            }
        }
    }

    func setBuiltInBrightness(_ id: CGDirectDisplayID, _ value: Float) {
        guard brightness.setBrightness(id, value), let i = entries.firstIndex(where: { $0.info.id == id }) else { return }
        entries[i].builtInBrightness = value
        onChange?()
    }

    func apply(_ spec: ModeSpec, to id: CGDirectDisplayID) -> CGError {
        guard let entry = entry(id) else { return .illegalArgument }
        return DisplayModes.apply(spec, modes: entry.modes, to: id)   // the reconfigure callback refreshes the plan
    }

    func entry(_ id: CGDirectDisplayID) -> Entry? { entries.first { $0.info.id == id } }

    /// What the glyph shows: the main display's brightness, whichever backend owns it.
    var mainBrightnessFraction: CGFloat {
        guard let main = entries.first(where: { $0.info.isMain }) ?? entries.first else { return 0 }
        if let b = main.builtInBrightness { return CGFloat(b) }
        if let v = main.brightness, v.maximum > 0 { return CGFloat(v.current) / CGFloat(v.maximum) }
        return 0
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -E 'error|Compiling|Build complete' | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/MonitorLizard/DisplayModel.swift
git commit -m "app: DisplayModel orchestrates enumeration, DDC reads/writes and modes"
```

---

### Task 12: Slider rows and the resolution row

**Files:**
- Create: `Sources/MonitorLizard/SliderRow.swift`, `Sources/MonitorLizard/ResolutionRow.swift`

**Interfaces:**
- Produces:
  ```swift
  final class SliderRow: NSView {
      init(title: String, symbol: String, value: Double?, maximum: Double, format: @escaping (Double) -> String, onChange: @escaping (Double) -> Void)
      func update(value: Double)            // external change while open
      static let rowWidth: CGFloat = 260
  }
  final class ResolutionRow: NSView {
      init(plan: ModePlan, onApply: @escaping (ModeSpec) -> Void)
  }
  ```

- [ ] **Step 1: Implement `SliderRow.swift`**

```swift
import AppKit

/// A labelled slider in an `NSMenuItem.view`: title left, value right, an
/// SF Symbol at each end of the track. Fires `onChange` on every tick; the
/// DDC layer collapses bursts, so no debounce here.
final class SliderRow: NSView {
    static let rowWidth: CGFloat = 260
    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "–")
    private let format: (Double) -> String
    private let onChange: (Double) -> Void

    init(title: String, symbol: String, value: Double?, maximum: Double,
         format: @escaping (Double) -> String, onChange: @escaping (Double) -> Void) {
        self.format = format
        self.onChange = onChange
        slider = NSSlider(value: value ?? 0, minValue: 0, maxValue: maximum, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 28))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .menuFont(ofSize: 0)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor

        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(slid(_:))
        slider.isEnabled = value != nil

        for v in [titleLabel, icon, slider, valueLabel] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 72),
            icon.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            slider.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 30),
        ])
        if let value { show(value) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(value: Double) {
        guard !slider.isHighlighted else { return }
        slider.doubleValue = value
        slider.isEnabled = true
        show(value)
    }

    private func show(_ value: Double) { valueLabel.stringValue = format(value) }

    @objc private func slid(_ sender: NSSlider) {
        show(sender.doubleValue)
        onChange(sender.doubleValue)
    }
}
```

- [ ] **Step 2: Implement `ResolutionRow.swift`**

```swift
import AppKit
import MonitorLizardCore

/// A stepped slider over the HiDPI "looks like" sizes. Snaps to a stop while
/// dragging and applies only on release — a mode switch blanks the display for
/// a second, so it must not fire per tick.
final class ResolutionRow: NSView {
    private let slider: NSSlider
    private let label = NSTextField(labelWithString: "")
    private let plan: ModePlan
    private let onApply: (ModeSpec) -> Void
    private var lastApplied: Int?

    init(plan: ModePlan, onApply: @escaping (ModeSpec) -> Void) {
        self.plan = plan
        self.onApply = onApply
        let stops = max(plan.hiDPI.count - 1, 0)
        slider = NSSlider(value: 0, minValue: 0, maxValue: Double(stops), target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: SliderRow.rowWidth, height: 28))

        let title = NSTextField(labelWithString: "Resolution")
        title.font = .menuFont(ofSize: 0)
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.expand.diagonal", accessibilityDescription: nil)
                               ?? NSImage(systemSymbolName: "rectangle", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor

        slider.numberOfTickMarks = plan.hiDPI.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(slid(_:))
        slider.isEnabled = plan.hiDPI.count > 1
        if let current = plan.current, let i = plan.stopIndex(of: current) {
            slider.doubleValue = Double(i); lastApplied = i; label.stringValue = plan.hiDPI[i].label
        } else if let current = plan.current {
            label.stringValue = current.label + (current.isHiDPI ? "" : " (low-res)")
        }

        for v in [title, icon, slider, label] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(equalToConstant: 72),
            icon.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            slider.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 68),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func slid(_ sender: NSSlider) {
        let i = Int(sender.doubleValue.rounded())
        guard plan.hiDPI.indices.contains(i) else { return }
        label.stringValue = plan.hiDPI[i].label
        // NSSlider with isContinuous fires during the drag; the release is the
        // event whose type is .leftMouseUp.
        guard NSApp.currentEvent?.type == .leftMouseUp, i != lastApplied else { return }
        lastApplied = i
        onApply(plan.hiDPI[i])
    }
}

/// The picker submenu: every same-aspect mode, HiDPI first, the current one checked.
enum ResolutionMenu {
    static func make(plan: ModePlan, target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        func section(_ title: String, _ modes: [ModeSpec]) {
            guard !modes.isEmpty else { return }
            let header = NSMenuItem(title: title, action: nil, keyEquivalent: ""); header.isEnabled = false
            menu.addItem(header)
            for mode in modes {
                var text = mode.label
                if mode == plan.native { text += " (native)" }
                let item = NSMenuItem(title: text, action: action, keyEquivalent: "")
                item.target = target
                item.representedObject = mode
                if let current = plan.current, current.width == mode.width, current.height == mode.height, current.isHiDPI == mode.isHiDPI {
                    item.state = .on
                }
                menu.addItem(item)
            }
        }
        section("HiDPI", plan.hiDPI)
        if !plan.hiDPI.isEmpty && !plan.lowRes.isEmpty { menu.addItem(.separator()) }
        section("Low resolution", plan.lowRes)
        return menu
    }
}
```

`ModeSpec` must be usable as `representedObject` (it is a struct, so wrap: `item.representedObject = ModeBox(mode)`). Add to the same file:

```swift
final class ModeBox: NSObject {
    let mode: ModeSpec
    init(_ mode: ModeSpec) { self.mode = mode }
}
```
and use `item.representedObject = ModeBox(mode)` in `ResolutionMenu.make`.

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | grep -E 'error|Build complete' | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/MonitorLizard/SliderRow.swift Sources/MonitorLizard/ResolutionRow.swift
git commit -m "app: slider rows and the stepped resolution row with picker submenu"
```

---

### Task 13: Override writer and the Night Shift auto-fix

**Files:**
- Create: `Sources/MonitorLizard/OverrideWriter.swift`

**Interfaces:**
- Consumes: `OverridePlist`, `DisplayInfo`, `TVRoleTracker`.
- Produces:
  ```swift
  enum OverrideWriter {
      enum Outcome { case written, cancelled, failed(String) }
      static func write(for display: DisplayInfo) -> Outcome      // blocking; call on main (it shows the auth dialog)
  }
  ```

- [ ] **Step 1: Implement `OverrideWriter.swift`**

```swift
import AppKit
import MonitorLizardCore

/// Writes the per-model override into the root-owned Overrides directory
/// through the standard macOS administrator dialog. One prompt per new model.
enum OverrideWriter {
    enum Outcome { case written, cancelled, failed(String) }

    static func write(for display: DisplayInfo) -> Outcome {
        let dest = OverridePlist.path(vendorID: display.vendorID, productID: display.productID)
        let dir = (dest as NSString).deletingLastPathComponent
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("monitor-lizard-override-\(display.productID).plist")
        do {
            try OverridePlist.contents(vendorID: display.vendorID, productID: display.productID).write(to: tmp)
        } catch {
            return .failed("could not stage override: \(error.localizedDescription)")
        }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shell = "mkdir -p \(q(dir)) && cp \(q(tmp.path)) \(q(dest)) && chmod 644 \(q(dest))"
        let source = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        try? FileManager.default.removeItem(at: tmp)
        if result != nil {
            Log.tvrole.info("wrote override for \(display.name) at \(dest)")
            return .written
        }
        let code = (error?[NSAppleScript.errorNumber] as? Int) ?? 0
        if code == -128 {                       // userCanceledErr
            Log.tvrole.info("override for \(display.name) cancelled by the user")
            return .cancelled
        }
        let message = (error?[NSAppleScript.errorMessage] as? String) ?? "AppleScript error \(code)"
        Log.tvrole.error("override for \(display.name) failed: \(message)")
        return .failed(message)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -E 'error|Build complete' | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/MonitorLizard/OverrideWriter.swift
git commit -m "app: admin-prompt override writer for TV-flagged displays"
```

---

### Task 14: `main.swift` — status item, glyph, menu

**Files:**
- Create: `Sources/MonitorLizard/MenuBuilder+Displays.swift`
- Modify: `Sources/MonitorLizard/main.swift` (replace the placeholder)

**Interfaces:**
- Consumes: `DisplayModel`, `SliderRow`, `ResolutionRow`, `ResolutionMenu`, `ModeBox`, `OverrideWriter`, StatusItemKit (`StatusItemController`, `YieldClient`, `LoginItem`, `Notifier`, `MeterAppearance`, `AppearanceMenu`, `CharacterIcon`, `MeterStyle`).

- [ ] **Step 1: Implement `MenuBuilder+Displays.swift`**

```swift
import AppKit
import MonitorLizardCore

/// The per-display blocks of the menu. Kept out of `App` so main.swift stays
/// the wiring and this stays the layout.
extension App {
    func addDisplayBlock(_ entry: DisplayModel.Entry, to menu: NSMenu) {
        let header = NSMenuItem(title: entry.info.name, action: nil, keyEquivalent: "")
        header.isEnabled = false
        if entry.info.isHDMI {
            header.attributedTitle = headerTitle(entry.info.name, tag: "HDMI")
        }
        menu.addItem(header)

        if entry.info.isBuiltIn {
            let row = NSMenuItem()
            row.view = SliderRow(title: "Brightness", symbol: "sun.max", value: entry.builtInBrightness.map { Double($0) * 100 }, maximum: 100,
                                 format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setBuiltInBrightness(entry.info.id, Float(v / 100))
                self?.refreshIcon()
            }
            menu.addItem(row)
            return
        }

        if entry.isExternalControllable {
            let b = NSMenuItem()
            b.view = SliderRow(title: "Brightness", symbol: "sun.max",
                               value: entry.brightness.map { Double($0.current) }, maximum: Double(entry.brightness?.maximum ?? 100),
                               format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setBrightness(entry.info.id, UInt16(v.rounded()))
            }
            sliderRows[entry.info.id, default: [:]][.brightness] = b.view as? SliderRow
            menu.addItem(b)
            let c = NSMenuItem()
            c.view = SliderRow(title: "Contrast", symbol: "circle.lefthalf.filled",
                               value: entry.contrast.map { Double($0.current) }, maximum: Double(entry.contrast?.maximum ?? 100),
                               format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setContrast(entry.info.id, UInt16(v.rounded()))
            }
            sliderRows[entry.info.id, default: [:]][.contrast] = c.view as? SliderRow
            menu.addItem(c)
        } else {
            let none = NSMenuItem(title: "No DDC control", action: nil, keyEquivalent: "")
            none.isEnabled = false
            none.indentationLevel = 1
            menu.addItem(none)
        }

        let res = NSMenuItem()
        res.view = ResolutionRow(plan: entry.plan) { [weak self] spec in
            let rc = self?.model.apply(spec, to: entry.info.id)
            if rc != .success { Log.modes.error("apply failed rc=\(rc?.rawValue ?? -1)") }
        }
        res.submenu = ResolutionMenu.make(plan: entry.plan, target: self, action: #selector(pickMode(_:)))
        menu.addItem(res)

        let ns: NSMenuItem
        switch entry.tvState {
        case .ok:
            ns = NSMenuItem(title: "✓ Night Shift works on this display", action: nil, keyEquivalent: "")
            ns.isEnabled = false
        case .fixedPendingReconnect:
            ns = NSMenuItem(title: "⏳ Marked as a monitor — reconnect to enable Night Shift", action: nil, keyEquivalent: "")
            ns.isEnabled = false
        case .blocked, .skipped:
            ns = NSMenuItem(title: "✗ TV mode · Night Shift blocked · Retry", action: #selector(retryTVFix(_:)), keyEquivalent: "")
            ns.target = self
            ns.representedObject = NSNumber(value: entry.info.id)
        }
        ns.indentationLevel = 1
        menu.addItem(ns)
    }

    private func headerTitle(_ name: String, tag: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: name, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor])
        s.append(NSAttributedString(string: "   \(tag)", attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.tertiaryLabelColor]))
        return s
    }

    @objc func pickMode(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ModeBox,
              let entry = model.entries.first(where: { $0.modes.indices.contains(box.mode.index) && $0.plan.hiDPI.contains(box.mode) || $0.plan.lowRes.contains(box.mode) }) else { return }
        _ = model.apply(box.mode, to: entry.info.id)
    }

    @objc func retryTVFix(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value, let entry = model.entry(id) else { return }
        model.tvRoles.clearSkipped(entry.info)
        fixTVRole(entry.info)
    }
}
```

`pickMode` needs to know which display the submenu belongs to; make it unambiguous by tagging the item instead: in `ResolutionMenu.make` set `item.tag = Int(displayID)` — add a `displayID: CGDirectDisplayID` parameter to `ResolutionMenu.make(plan:displayID:target:action:)` and set `item.tag = Int(displayID)`. Then `pickMode` becomes:

```swift
    @objc func pickMode(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ModeBox else { return }
        _ = model.apply(box.mode, to: CGDirectDisplayID(sender.tag))
    }
```
Update the call site in `addDisplayBlock` to pass `displayID: entry.info.id`.

- [ ] **Step 2: Replace `main.swift`**

```swift
import AppKit
import MonitorLizardCore
import StatusItemKit

/// Monitor Lizard — external-display control for the menu bar: DDC brightness
/// and contrast, HiDPI resolution, built-in brightness, and Night Shift with an
/// automatic fix for displays macOS wrongly calls televisions.
final class App: NSObject, NSApplicationDelegate {
    private var status: StatusItemController!
    private var yieldClient: YieldClient!
    private let notifier = Notifier()
    let model: DisplayModel
    private let appearance = MeterAppearance(defaultStyle: .character)
    private var appearanceMenu: AppearanceMenu!
    private var tongueUntil = Date.distantPast
    /// Open-menu slider rows, so a confirmed read can correct them in place.
    var sliderRows: [CGDirectDisplayID: [VCPCode: SliderRow]] = [:]
    private var fixInProgress = false

    override init() {
        model = DisplayModel(brightness: DisplayServicesBrightness(), nightShift: CoreBrightnessNightShift(), tvRoles: TVRoleTracker())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.requestAuthorization()
        appearanceMenu = AppearanceMenu(appearance: appearance, styles: [.character] + MeterStyle.proportional, characterTitle: "Lizard") { [weak self] in
            self?.refreshIcon()
        }
        status = StatusItemController(
            pollInterval: 30,
            onPoll: { [weak self] in
                // Built-in brightness and Night Shift are cheap to read; DDC is not polled.
                self?.model.readBuiltInOnly()
                self?.refreshIcon()
            },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) }
        )
        model.onChange = { [weak self] in self?.modelChanged() }
        model.onWrite = { [weak self] in self?.flickTongue() }
        model.onNeedsTVFix = { [weak self] info in self?.fixTVRole(info) }
        model.start()
        status.start()
        yieldClient = YieldClient(item: status)
        yieldClient.start()
    }

    // MARK: - Icon

    func refreshIcon() {
        let fraction = model.mainBrightnessFraction
        let icon: NSImage
        if appearance.style == .character {
            let ns = model.nightShift?.status().active ?? false
            icon = CharacterIcon.monitorLizard(brightness: fraction, nightShift: ns, tongue: Date() < tongueUntil)
        } else {
            icon = appearance.image(fraction: fraction)
        }
        status.setIcon(icon)
    }

    private func flickTongue() {
        tongueUntil = Date().addingTimeInterval(0.6)
        refreshIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in self?.refreshIcon() }
    }

    private func modelChanged() {
        refreshIcon()
        // Correct any open slider to the value the monitor confirmed.
        for entry in model.entries {
            if let v = entry.brightness { sliderRows[entry.info.id]?[.brightness]?.update(value: Double(v.current)) }
            if let v = entry.contrast { sliderRows[entry.info.id]?[.contrast]?.update(value: Double(v.current)) }
        }
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        sliderRows = [:]
        model.readValues()

        if model.entries.isEmpty {
            menu.addItem(disabledItem("No displays"))
        }
        for (i, entry) in model.entries.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            addDisplayBlock(entry, to: menu)
        }

        menu.addItem(.separator())
        if let ns = model.nightShift, ns.isAvailable {
            let s = ns.status()
            let toggle = actionItem("Night Shift", #selector(toggleNightShift))
            toggle.state = s.enabled ? .on : .off
            menu.addItem(toggle)
            let warmth = NSMenuItem()
            warmth.view = SliderRow(title: "Warmth", symbol: "thermometer.sun", value: Double(s.strength) * 100, maximum: 100,
                                    format: { "\(Int($0.rounded()))" }) { v in
                _ = ns.setStrength(Float(v / 100))
            }
            menu.addItem(warmth)
        } else {
            menu.addItem(disabledItem("Night Shift unavailable on this macOS"))
        }

        menu.addItem(.separator())
        let login = actionItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(appearanceMenu.menuItem())
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Monitor Lizard", #selector(quit), key: "q"))
    }

    func disabledItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - TV-role fix

    func fixTVRole(_ info: DisplayInfo) {
        guard !fixInProgress, model.tvRoles.needsFix(info) else { return }
        fixInProgress = true
        defer { fixInProgress = false }
        switch OverrideWriter.write(for: info) {
        case .written:
            notifier.post(title: "Marked \(info.name) as a monitor",
                          body: "Reconnect it (or reboot) to enable Night Shift.")
        case .cancelled:
            model.tvRoles.markSkipped(info)
        case .failed(let message):
            notifier.post(title: "Couldn't mark \(info.name) as a monitor", body: message)
        }
        model.refresh()
    }

    // MARK: - Selectors

    @objc private func toggleNightShift() {
        guard let ns = model.nightShift else { return }
        _ = ns.setEnabled(!ns.status().enabled)
        refreshIcon()
    }

    @objc private func toggleLogin() { LoginItem.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
```

Add to `DisplayModel` (Task 11 file) the cheap poll used above:

```swift
    /// The poll tick: built-in brightness only. DDC is never read on a timer.
    func readBuiltInOnly() {
        for (i, e) in entries.enumerated() where e.info.isBuiltIn {
            entries[i].builtInBrightness = brightness.brightness(e.info.id)
        }
    }
```

- [ ] **Step 3: Build and run the unit tests**

Run: `swift build 2>&1 | grep -E 'error|Build complete' | tail -3 && swift test 2>&1 | tail -2`
Expected: `Build complete!` and `with 0 failures`.

- [ ] **Step 4: Build the .app and smoke-run it (BetterDisplay quit)**

```bash
osascript -e 'quit app "BetterDisplay"'
scripts/build-app.sh
open "build/Monitor Lizard.app"
sleep 3
log show --last 20s --predicate 'subsystem == "com.nicholaspsmith.MonitorLizard"' --style compact | tail -20
```
Expected: an `enumerated N displays, M with DDC` line; the lizard glyph in the bar; opening the menu shows the Dell block with live brightness/contrast values within a second. Then quit it (`osascript -e 'quit app "Monitor Lizard"'`) and reopen BetterDisplay (`open -a BetterDisplay`) until the soak begins.

- [ ] **Step 5: Commit**

```bash
git add Sources/MonitorLizard
git commit -m "app: status item, lizard glyph, display menu, Night Shift auto-fix"
```

---

### Task 15: Packaging — icon script, installer, README, docs

**Files:**
- Create: `scripts/make-icon.sh`, `install.sh`, `README.md`, `docs/menubar-icon.png` (generated in Task 16), `docs/mascot.png` (from the mascot, see Task 16)

- [ ] **Step 1: Write `scripts/make-icon.sh`**

```bash
#!/usr/bin/env bash
# docs/mascot.png (square, transparent) → Resources/bundle/AppIcon.icns.
# Without an .icns macOS shows a blank tile (e.g. in Barn's hidden-icons menu).
set -euo pipefail
cd "$(dirname "$0")/.."
src="${1:-docs/mascot.png}"
[ -f "$src" ] || { echo "no mascot at $src" >&2; exit 1; }
set_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set_dir" Resources/bundle
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$src" --out "$set_dir/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$src" --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/bundle/AppIcon.icns
echo "wrote Resources/bundle/AppIcon.icns"
```
`chmod +x scripts/make-icon.sh`.

- [ ] **Step 2: Write `install.sh`**

```bash
#!/usr/bin/env bash
# Build "Monitor Lizard.app" and symlink it into ~/Applications (rebuilds
# propagate; SMAppService accepts a symlink there for Start at Login).
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Monitor Lizard.app"

if pgrep -xq BetterDisplay; then
  echo "BetterDisplay is running. Quit it first — two apps on one DDC bus interfere." >&2
  exit 1
fi

"$SRC_DIR/scripts/build-app.sh"
mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"
open "$HOME/Applications/$APP_NAME"

cat <<'EOF'

Monitor Lizard is now running in the menu bar.

  • Drag Brightness / Contrast to drive the external display over DDC.
  • Resolution slider steps through the HiDPI "looks like" sizes; ▸ lists every mode.
  • If a display is flagged as a TV by macOS you will get ONE admin prompt; after
    that, reconnect the display (or reboot) and Night Shift works on it.
  • Optional: menu ▸ Start at Login.
EOF
```
`chmod +x install.sh`.

- [ ] **Step 3: Write `README.md`**

```markdown
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
log show --last 5m --predicate 'subsystem == "com.nicholaspsmith.MonitorLizard"' --style compact
```

## Why not a SwiftBar plugin?

This is a standalone `.app` built on [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit), not a script under a plugin host: no SwiftBar to install, real AppKit sliders instead of rendered stdout, event-driven refresh on display reconfiguration and wake instead of a re-run timer, and an icon that keeps its place in the bar. Sliders need in-process DDC — a shell-out per tick would lag visibly. The full comparison is in [StatusItemKit's README](https://github.com/nicholaspsmith/StatusItemKit#why-not-swiftbar).

## The menu-bar suite

Part of a suite of macOS menu-bar apps that share one framework, one
build-and-sign script, and one installer, designed to sit in the same bar
together. See [Menubarn](https://widgets.nicksmith.software).

## License

MIT
```

- [ ] **Step 4: Commit**

```bash
git add scripts/make-icon.sh install.sh README.md
git commit -m "docs+scripts: installer, icon builder, README"
```

---

### Task 16: Mascot prompt, glyph strip, and the Menubarn site

**Files (in `~/Code/widgets.nicksmith.software`):**
- Modify: `art/prompts.json` (add mascot), `art/PROMPTS.md` (add section), `art/glyphs/render-glyphs.sh` (repo map + copy), `art/glyphs/main.swift` (strip + icon), `art/glyphs/compose-bar.swift` (if the hero bar enumerates ids — check first), `site/index.html` (card)
- Create: `site/apps/monitor-lizard/index.html`

- [ ] **Step 1: Add the mascot prompt**

In `art/prompts.json`, append to `mascots`:
```json
  {
   "id": "monitor-lizard",
   "subject": "a chunky monitor lizard whose thick scaly body is a computer monitor: the flat screen is its torso, a stout wide lizard head with a friendly grin and a flicking forked tongue rises from the top edge of the screen (small, just enough to read as a lizard), and a long tapering scaly tail curls out from the monitor's stand along the bottom; tan-and-black spotted scales"
  }
```
In `art/PROMPTS.md`, add a `## monitor-lizard` section in the same format as the others (the shared style preamble followed by that subject; save as `art/raw/monitor-lizard.png`).

- [ ] **Step 2: Hand the generation to Nick**

Tell him: generate `monitor-lizard` at https://aistudio.google.com/ with the prompt from `art/PROMPTS.md`, save it as `art/raw/monitor-lizard.png`, then say "done". This is his step; do not drive AI Studio.

- [ ] **Step 3: After the raw image lands**

```bash
cd ~/Code/widgets.nicksmith.software
python3 art/gen_icons.py --reprocess
cp site/img/mascots/monitor-lizard.png ~/Code/monitor-lizard-menubar/docs/mascot.png
cd ~/Code/monitor-lizard-menubar && scripts/make-icon.sh && scripts/build-app.sh
```
Expected: `site/img/mascots/monitor-lizard.png` (256 px, transparent), `Resources/bundle/AppIcon.icns`, and the rebuilt app shows the icon in Finder (`qlmanage -p "build/Monitor Lizard.app"` or Get Info).

- [ ] **Step 4: Add the glyph to the renderer**

In `art/glyphs/main.swift` add, next to the other `save`/`strip` lines:
```swift
save(CharacterIcon.monitorLizard(brightness: 0.8, nightShift: false), "icon-monitor-lizard.png")
strip([CharacterIcon.monitorLizard(brightness: 0.25, nightShift: false), CharacterIcon.monitorLizard(brightness: 0.8, nightShift: false), CharacterIcon.monitorLizard(brightness: 0.8, nightShift: true), CharacterIcon.monitorLizard(brightness: 0.8, nightShift: true, tongue: true)], "states-monitor-lizard.png")
```
In `art/glyphs/render-glyphs.sh` add `[monitor-lizard]=monitor-lizard-menubar` to the `repo` map. Check `compose-bar.swift` for a hard-coded id list; if it has one, add `monitor-lizard` there too. Run:
```bash
art/glyphs/render-glyphs.sh
```
Expected: `site/img/glyphs/monitor-lizard.png` and `~/Code/monitor-lizard-menubar/docs/menubar-icon.png` exist; open the strip and check the four states read at 1×.

- [ ] **Step 5: Site card and app page**

In `site/index.html`, add a card before the Barn card, mirroring the Download Recycler card:
```html
    <a class="card" href="apps/monitor-lizard/" data-repo="https://github.com/nicholaspsmith/monitor-lizard-menubar">
      <div class="card-top"><img class="mascot" src="img/mascots/monitor-lizard.png" alt="" width="72" height="72"><div><h3>Monitor Lizard</h3><p class="chips"><span>StatusItemKit</span></p></div></div>
      <div class="inbar"><img src="img/glyphs/monitor-lizard.png" alt="Monitor Lizard at low and high brightness, amber with Night Shift, then flicking its tongue" loading="lazy"><p>The screen fills with the main display's brightness, turns amber under Night Shift, and the tongue flicks when a DDC write lands.</p></div>
      <p>Brightness, contrast and HiDPI resolution for external displays, built-in brightness, and Night Shift on monitors macOS mistakes for TVs. The four things a display manager is for, without the other forty.</p>
      <div class="shot"><img src="img/menus/monitor-lizard.png" alt="The Monitor Lizard menu" loading="lazy"></div>
    </a>
```
Create `site/apps/monitor-lizard/index.html` by copying `site/apps/download-recycler/index.html` and replacing: title/description/og tags, mascot/glyph/menu image paths, the repo link, and the `<article class="prose">` body with the README's first two sections rendered as HTML (bullets + "How it works" paragraphs). Capture the dropdown with the site's existing capture pipeline (`scripts/collect-screenshots.sh` — read it first; it OCR-scrubs IPs) into `site/img/menus/monitor-lizard.png`.

- [ ] **Step 6: Commit both repos**

```bash
cd ~/Code/monitor-lizard-menubar && git add docs Resources/bundle/AppIcon.icns && git commit -m "docs: mascot, menu-bar strip, app icon"
cd ~/Code/widgets.nicksmith.software && git add art site && git commit -m "site: Monitor Lizard card, page, mascot prompt and glyph strip"
```
Deploy the site the way its README says (Cloudflare Worker `menubarn`) only after Nick confirms the page looks right.

---

### Task 17: Manual verification (spec §6) and soak start

**Files:** none (checklist). Record results in `docs/verification-2026-09.md`.

- [ ] **Step 1: Precondition**

```bash
osascript -e 'quit app "BetterDisplay"'
launchctl bootout gui/$UID/com.nicholassmith.bdcolorguard 2>/dev/null || true
~/Code/monitor-lizard-menubar/install.sh
```

- [ ] **Step 2: Walk the checklist, ticking each in `docs/verification-2026-09.md`**

1. Brightness and contrast sliders move the Dell; the menu value matches the Dell's own OSD after a release.
2. Resolution slider: drag to 1920 and release → mode switches; drag back to 2560 → returns; the picker shows ✓ on `2560×1067`.
3. Night Shift toggle and warmth change the screen; glyph turns amber when active.
4. Unplug and replug the Dell: block disappears, returns, sliders live.
5. Lid-closed sleep ≥ 30 min, wake: colours sane, sliders live; `log show --predicate 'subsystem == "com.nicholaspsmith.MonitorLizard"' --last 1h` shows a fresh `enumerated` line and no `Invalid display` errors.
6. `~/Code/menubar-barn/scripts/verify-menubar.sh` lists Monitor Lizard and reports no phantom.
7. TV-role flow, using the real Dell: `sudo mv /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-10ac/DisplayProductID-a0f0 /tmp/a0f0.bak`, unplug/replug the Dell (it will now be flagged TV) → the admin prompt appears once → file written (`plutil -p` shows the three keys) → notification posts → the row reads ⏳; cancel path: repeat with the file moved away again and cancel the prompt → row reads ✗ with Retry, no second prompt until Retry. Finish with the override in place and one more replug → row reads ✓.

- [ ] **Step 3: Start the soak**

Enable Start at Login in the menu. Turn off BetterDisplay's start-at-login (System Settings ▸ General ▸ Login Items, or its own Settings). Leave the guard unloaded (its plist stays on disk). Note the start date in `docs/verification-2026-09.md`; Phase 2 of the spec's §8 begins only after Nick reports a clean 7 days.

- [ ] **Step 4: Commit**

```bash
git add docs/verification-2026-09.md
git commit -m "docs: manual verification record and soak start"
git push
```
Also push StatusItemKit (`cd ~/Code/StatusItemKit && git push`) and the site repo.

---

## Self-review

**Spec coverage.** §1 four features → Tasks 3–9 (DDC, built-in, modes, Night Shift/TV). §3 name/mascot/glyph → Tasks 1 (bundle), 10 (glyph), 16 (mascot, strip). §4.1 wire format/timing → Tasks 2–3. §4.2 registry + matching + re-enumeration → Tasks 5, 6, 11. §4.3 modes → Task 7 (+ apply). §4.4/4.5 backends → Task 9. §4.6 override → Tasks 8, 13. §5.1 menu → Tasks 12, 14. §5.2 auto-fix + notification + skipped/retry → Tasks 13, 14. §5.3 glyph refresh triggers → Task 14 (`onChange`, `onWrite`, poll, Night Shift notification). §5.4 errors → Task 3 (retries), 11 (`ddcUnavailable`, snap-back via `update`), 13 (failure notification), 14. §6 tests → each task; manual list → Task 17. §7 packaging/site → Tasks 15–16. §8 soak start → Task 17; Phase 2 deliberately not in this plan. §9 open items → Task 9 Step 5 (struct layout), Task 9 (`BrightnessChanged` called), Task 6 (registry walk via parent node name, with the single-external fallback).

**Placeholder scan.** None; every step carries code or an exact command. Task 10 Step 5 tells the implementer to write a short render script rather than dictating one — acceptable, the renderer pattern exists in `render-glyphs.sh`.

**Type consistency.** `VCPValue(current:maximum:)`, `DDCService.read/write` completions on the service queue (Task 3) and hopped to main in Task 11 ✓. `DisplayInfo` initialiser order matches all uses ✓. `ModePlan.stopIndex(of:)` used by `ResolutionRow` ✓. `TVRoleTracker.needsFix/markSkipped/clearSkipped/state(for:)` used by Tasks 11, 14 ✓. `ResolutionMenu.make(plan:displayID:target:action:)` — Task 12 defines it with `displayID` per the Task 14 amendment; implement the amended signature directly. `DisplayModel.readBuiltInOnly()` is added in Task 14 to the Task 11 file ✓. `App.sliderRows` is `var` and internal so the extension can write it ✓.
