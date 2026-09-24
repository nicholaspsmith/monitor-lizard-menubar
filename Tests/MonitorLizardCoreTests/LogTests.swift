// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

final class LogTests: XCTestCase {
    func testSubsystemIsTheBundleID() {
        XCTAssertEqual(Log.subsystem, "com.nicholaspsmith.MonitorLizard")
    }
}
