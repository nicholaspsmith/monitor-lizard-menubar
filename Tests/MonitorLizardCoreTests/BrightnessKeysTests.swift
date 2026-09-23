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

    private func display(_ id: UInt32, main: Bool, builtIn: Bool = false, ddc: Bool = true) -> BrightnessKeys.Display {
        BrightnessKeys.Display(id: id, isMain: main, isBuiltIn: builtIn, hasDDC: ddc)
    }

    func testTargetIsTheMainExternalDisplayWithDDC() {
        let displays = [display(7, main: false), display(5, main: true)]
        XCTAssertEqual(BrightnessKeys.target(among: displays), 5)
    }

    func testBuiltInMainDisplayPassesTheKeyThrough() {
        // macOS handles the panel's own brightness keys; don't get in the way.
        let displays = [display(1, main: true, builtIn: true, ddc: false), display(5, main: false)]
        XCTAssertNil(BrightnessKeys.target(among: displays))
    }

    func testMainDisplayWithoutDDCPassesTheKeyThrough() {
        XCTAssertNil(BrightnessKeys.target(among: [display(5, main: true, ddc: false)]))
    }

    func testNoMainFlagFallsBackToTheFirstDisplay() {
        XCTAssertEqual(BrightnessKeys.target(among: [display(9, main: false), display(5, main: false)]), 9)
    }

    func testNoDisplaysPassesThrough() {
        XCTAssertNil(BrightnessKeys.target(among: []))
    }
}
