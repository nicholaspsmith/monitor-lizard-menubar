// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

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
