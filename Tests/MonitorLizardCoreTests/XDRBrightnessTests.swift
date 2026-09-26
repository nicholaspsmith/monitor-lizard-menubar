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

    func testScalingKeepsThePanelsOwnCurveAndLiftsIt() {
        // A calibrated (non-linear) table keeps its shape; only the scale changes.
        let base: [CGGammaValue] = (0..<XDRGamma.tableSize).map { powf(Float($0) / 255, 2.2) }
        let scaled = XDRGamma.scaled(base, by: 1.5)
        XCTAssertEqual(scaled.count, base.count)
        XCTAssertEqual(scaled.last!, 1.5, accuracy: 0.0001)
        XCTAssertEqual(scaled[128], base[128] * 1.5, accuracy: 0.0001)
        XCTAssertTrue(XDRGamma.carriesBoost(scaled))
        XCTAssertFalse(XDRGamma.carriesBoost(XDRGamma.scaled(base, by: 1)))
    }

    func testHDRIsEngagedOnlyOncePanelReportsHeadroom() {
        // Before the overlay takes effect the panel reports 1.0; a rounding wobble is not HDR.
        XCTAssertFalse(XDRGamma.isHDREngaged(currentHeadroom: 1))
        XCTAssertFalse(XDRGamma.isHDREngaged(currentHeadroom: 1.02))
        XCTAssertTrue(XDRGamma.isHDREngaged(currentHeadroom: 1.6))
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

    // The panel's headroom ramps from 1.0 to its maximum over ~2 s after HDR
    // engages (measured 1.0 → 5.0 in 2.25 s), and moves with brightness; the
    // table is rewritten whenever the factor it should carry changes.
    func testRewriteWhenTheFactorMoves() {
        XCTAssertTrue(XDRGamma.shouldRewrite(written: nil, wanted: 1.2))
        XCTAssertTrue(XDRGamma.shouldRewrite(written: 1.26, wanted: 2))
        XCTAssertFalse(XDRGamma.shouldRewrite(written: 2, wanted: 2.002))
    }

    func testFactorOnceTheHeadroomHasRamped() {
        XCTAssertEqual(XDRGamma.factor(boost: 1, headroom: 1.26), 1.26, accuracy: 1e-6, "early in the ramp")
        XCTAssertEqual(XDRGamma.factor(boost: 1, headroom: 5), 2, accuracy: 1e-6, "ramped: capped at maxFactor")
        XCTAssertEqual(XDRGamma.factor(boost: 0.5, headroom: 5), 1.5, accuracy: 1e-6)
    }
}
