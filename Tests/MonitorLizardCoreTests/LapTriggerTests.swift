// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

final class LapTriggerTests: XCTestCase {
    func testFirstLookOnlyLearns() {
        var t = LapTrigger()
        XCTAssertFalse(t.update(displays: [1, 2], nightShift: false))
    }

    func testNewDisplayTriggersOnce() {
        var t = LapTrigger()
        _ = t.update(displays: [1], nightShift: false)
        XCTAssertTrue(t.update(displays: [1, 2], nightShift: false))
        XCTAssertFalse(t.update(displays: [1, 2], nightShift: false))
    }

    // Unplugging and replugging a display it has already seen is not new.
    func testReturningDisplayDoesNotTrigger() {
        var t = LapTrigger()
        _ = t.update(displays: [1, 2], nightShift: false)
        XCTAssertFalse(t.update(displays: [1], nightShift: false))
        XCTAssertFalse(t.update(displays: [1, 2], nightShift: false))
    }

    func testNightShiftBothWays() {
        var t = LapTrigger()
        _ = t.update(displays: [1], nightShift: false)
        XCTAssertTrue(t.update(displays: [1], nightShift: true))
        XCTAssertFalse(t.update(displays: [1], nightShift: true))
        XCTAssertTrue(t.update(displays: [1], nightShift: false))
    }

    func testUnknownNightShiftNeverTriggers() {
        var t = LapTrigger()
        _ = t.update(displays: [1], nightShift: nil)
        XCTAssertFalse(t.update(displays: [1], nightShift: true))
        XCTAssertFalse(t.update(displays: [1], nightShift: nil))
    }
}
