// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

final class XDRBrightnessTests: XCTestCase {
    func testFactorSpansOneToTheHeadroom() {
        XCTAssertEqual(XDRGamma.factor(boost: 0, headroom: 1.8), 1, accuracy: 0.0001)
        XCTAssertEqual(XDRGamma.factor(boost: 1, headroom: 1.8), 1.8, accuracy: 0.0001)
        XCTAssertEqual(XDRGamma.factor(boost: 0.5, headroom: 1.8), 1.4, accuracy: 0.0001)
    }

    func testFactorIsCappedWhateverTheReportedHeadroom() {
        // An XDR panel reports 16× potential headroom (reference-mode HDR).
        XCTAssertEqual(XDRGamma.factor(boost: 1, headroom: 16), XDRGamma.maxFactor, accuracy: 0.0001)
    }

    func testNoHeadroomMeansNoBoost() {
        XCTAssertEqual(XDRGamma.factor(boost: 1, headroom: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(XDRGamma.factor(boost: 1, headroom: 0), 1, accuracy: 0.0001)
    }

    func testTableIsAScaledRamp() {
        let t = XDRGamma.table(factor: 1.5)
        XCTAssertEqual(t.count, XDRGamma.tableSize)
        XCTAssertEqual(t.first!, 0, accuracy: 0.0001)
        XCTAssertEqual(t.last!, 1.5, accuracy: 0.0001)
        XCTAssertTrue(XDRGamma.carriesBoost(t))
        XCTAssertFalse(XDRGamma.isPlainRamp(t))
    }

    func testIdentityTableIsAPlainRampWithNoBoost() {
        let t = XDRGamma.table(factor: 1)
        XCTAssertFalse(XDRGamma.carriesBoost(t))
        XCTAssertTrue(XDRGamma.isPlainRamp(t))
    }

    func testScrambledTableFailsTheRampCheck() {
        var t = XDRGamma.table(factor: 1)
        t[100] = 0.9; t[101] = 0.1
        XCTAssertFalse(XDRGamma.isPlainRamp(t))
        XCTAssertFalse(XDRGamma.isPlainRamp([]))
    }

    func testBoostOnlyWhileAwakeSettledAndAllowedOnPower() {
        XCTAssertTrue(XDRPolicy.shouldBoost(enabled: true, asleep: false, settling: false, onBattery: false, offOnBattery: true))
        XCTAssertTrue(XDRPolicy.shouldBoost(enabled: true, asleep: false, settling: false, onBattery: true, offOnBattery: false))
        XCTAssertFalse(XDRPolicy.shouldBoost(enabled: false, asleep: false, settling: false, onBattery: false, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldBoost(enabled: true, asleep: true, settling: false, onBattery: false, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldBoost(enabled: true, asleep: false, settling: true, onBattery: false, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldBoost(enabled: true, asleep: false, settling: false, onBattery: true, offOnBattery: true))
    }

    func testUnpluggingSwitchesItOffOnlyWhenAsked() {
        XCTAssertTrue(XDRPolicy.shouldSwitchOff(enabled: true, onBattery: true, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldSwitchOff(enabled: true, onBattery: true, offOnBattery: false))
        XCTAssertFalse(XDRPolicy.shouldSwitchOff(enabled: true, onBattery: false, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldSwitchOff(enabled: false, onBattery: true, offOnBattery: true))
    }
}
