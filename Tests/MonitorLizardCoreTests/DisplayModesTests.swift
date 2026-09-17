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

    func testValidateAcceptsASpecFromTheFixture() {
        XCTAssertEqual(DisplayModes.validate(Self.current, against: Self.specs), .success)
    }

    func testValidateRejectsAnOutOfRangeIndex() {
        let outOfRange = ModeSpec(index: 999, width: 2560, height: 1067, pixelWidth: 5120, pixelHeight: 2134, refresh: 60, usable: true)
        XCTAssertEqual(DisplayModes.validate(outOfRange, against: Self.specs), .rangeCheck)
    }

    func testValidateRejectsAStaleIndexPointingAtADifferentMode() {
        // Same fields as the current 2560×1067 spec, but its index now names the 3840×1600 entry.
        let nativeIndex = Self.specs.first { $0.width == 3840 && $0.height == 1600 && $0.refresh == 60 }!.index
        let stale = ModeSpec(index: nativeIndex, width: Self.current.width, height: Self.current.height,
                              pixelWidth: Self.current.pixelWidth, pixelHeight: Self.current.pixelHeight,
                              refresh: Self.current.refresh, usable: Self.current.usable)
        XCTAssertEqual(DisplayModes.validate(stale, against: Self.specs), .illegalArgument)
    }
}
