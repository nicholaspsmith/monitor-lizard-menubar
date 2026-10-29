// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

/// A monitor that has just been plugged in or woken refuses DDC for a few
/// seconds. One refusal must not turn its brightness keys off for good.
final class DDCRetryTests: XCTestCase {
    func testRetriesBackOffOverAboutAMinute() {
        let delays = (0..<DDCRetry.delays.count).compactMap { DDCRetry.delay(afterFailure: $0) }
        XCTAssertEqual(delays, [2, 4, 8, 16, 30])
        XCTAssertEqual(delays.reduce(0, +), 60)
    }

    func testGivesUpAfterTheLastRetry() {
        // A TV over HDMI never answers; it falls back to DisplayServices
        // instead of being asked forever.
        XCTAssertNil(DDCRetry.delay(afterFailure: DDCRetry.delays.count))
        XCTAssertNil(DDCRetry.delay(afterFailure: 99))
    }

    func testOnlyABrightnessFailureMakesDDCUnavailable() {
        // The keys and the Brightness row depend on brightness alone; a
        // monitor that refuses contrast still dims fine.
        XCTAssertTrue(DDCRetry.marksUnavailable(.brightness))
        XCTAssertFalse(DDCRetry.marksUnavailable(.contrast))
    }
}
