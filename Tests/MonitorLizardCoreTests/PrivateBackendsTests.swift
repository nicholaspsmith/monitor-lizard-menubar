// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

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

    func testClampBounds() {
        XCTAssertEqual(DisplayServicesBrightness.clamp(1.4), 1)
        XCTAssertEqual(DisplayServicesBrightness.clamp(-0.2), 0)
        XCTAssertEqual(DisplayServicesBrightness.clamp(0.5), 0.5)
    }
}
