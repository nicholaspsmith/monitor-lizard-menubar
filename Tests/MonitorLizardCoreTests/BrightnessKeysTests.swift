// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

/// The brightness keys step the main display's DDC brightness the way Apple's
/// keys step the built-in panel: sixteen steps across the range.
final class BrightnessKeysTests: XCTestCase {
    func testStepIsOneSixteenthOfTheRange() {
        XCTAssertEqual(BrightnessKeys.step(VCPValue(current: 50, maximum: 100), .up), 56)
        XCTAssertEqual(BrightnessKeys.step(VCPValue(current: 50, maximum: 100), .down), 44)
    }

    func testStepClampsToTheRange() {
        XCTAssertEqual(BrightnessKeys.step(VCPValue(current: 98, maximum: 100), .up), 100)
        XCTAssertEqual(BrightnessKeys.step(VCPValue(current: 3, maximum: 100), .down), 0)
    }

    func testStepIsNeverZeroOnATinyRange() {
        XCTAssertEqual(BrightnessKeys.step(VCPValue(current: 4, maximum: 10), .up), 5)
    }

    func testSystemStepIsOneSixteenthOfTheRange() {
        XCTAssertEqual(BrightnessKeys.step(0.5, .up), 0.5625, accuracy: 0.0001)
        XCTAssertEqual(BrightnessKeys.step(0.5, .down), 0.4375, accuracy: 0.0001)
    }

    func testSystemStepClampsToTheRange() {
        XCTAssertEqual(BrightnessKeys.step(0.98, .up), 1)
        XCTAssertEqual(BrightnessKeys.step(0.03, .down), 0)
    }

    private func display(_ id: UInt32, main: Bool, builtIn: Bool = false, source: BrightnessSource = .ddc) -> BrightnessKeys.Display {
        BrightnessKeys.Display(id: id, isMain: main, isBuiltIn: builtIn, source: source)
    }

    func testTargetIsTheMainExternalDisplayWithDDC() {
        let displays = [display(7, main: false), display(5, main: true)]
        XCTAssertEqual(BrightnessKeys.target(among: displays), 5)
    }

    func testMainExternalDisplayMacOSDimsItselfIsSteppedToo() {
        // A TV over HDMI that refuses DDC: its row fell back to DisplayServices,
        // so the keys take the same route rather than doing nothing.
        XCTAssertEqual(BrightnessKeys.target(among: [display(5, main: true, source: .system)]), 5)
    }

    func testBuiltInMainDisplayPassesTheKeyThrough() {
        // macOS handles the panel's own brightness keys; don't get in the way.
        let displays = [display(1, main: true, builtIn: true, source: .system), display(5, main: false)]
        XCTAssertNil(BrightnessKeys.target(among: displays))
    }

    func testMainDisplayWithNoControlPassesTheKeyThrough() {
        XCTAssertNil(BrightnessKeys.target(among: [display(5, main: true, source: .none)]))
    }

    func testNoMainFlagFallsBackToTheFirstDisplay() {
        XCTAssertEqual(BrightnessKeys.target(among: [display(9, main: false), display(5, main: false)]), 9)
    }

    func testNoDisplaysPassesThrough() {
        XCTAssertNil(BrightnessKeys.target(among: []))
    }
}
